local github_data = require("revman.github.data")
local ci = require("revman.github.ci")
local github_prs = require("revman.github.prs")
local db_prs = require("revman.db.prs")
local pr_lists = require("revman.db.pr_lists")
local pr_status = require("revman.db.pr_status")
local db_repos = require("revman.db.repos")
local db_comments = require("revman.db.comments")
local status = require("revman.db.status")
local logic_prs = require("revman.logic.prs")
local utils = require("revman.utils")
local log = require("revman.log")

local M = {}

function M.sync_all_prs(repo_name, sync_all, callback)
	repo_name = repo_name or utils.get_current_repo()
	if not repo_name then
		log.error("No repo specified for sync")
		return
	end

	local repo_row = utils.ensure_repo(repo_name)
	if not repo_row then
		log.error("Could not ensure repo in DB for sync")
		return
	end

	local query = { where = { repo_id = repo_row.id } }
	if not sync_all then
		query.where.state = "OPEN"
	end

	local tracked_prs = pr_lists.list(query)
	if #tracked_prs == 0 then
		log.info("No tracked PRs to sync for this repo.")
		return
	end

	local remaining = #tracked_prs
	local errors = {}
	local results = {}

	for _, pr in ipairs(tracked_prs) do
		M.sync_pr(pr.number, repo_name, function(pr_id, err)
			if pr_id then
				table.insert(results, pr_id)
			else
				table.insert(errors, "Failed to sync PR #" .. pr.number .. ": " .. (err or "unknown error"))
			end

			remaining = remaining - 1
			if remaining == 0 then
				if #errors > 0 then
					log.error("Some PRs failed to sync: " .. table.concat(errors, "; "))
				else
					log.info("All tracked PRs synced successfully: " .. vim.inspect(results))
					log.notify("All tracked PRs synced successfully")
				end
				if callback then
					callback(#errors == 0)
				end
			end
		end)
	end
end

function M.sync_pr(pr_number, repo_name, callback)
	repo_name = repo_name or utils.get_current_repo()
	if not repo_name then
		callback(nil, "No repo specified")
		return
	end

	github_data.get_pr_async(pr_number, repo_name, function(pr_data, fetch_err)
		if not pr_data then
			callback(nil, fetch_err or "Failed to fetch PR")
			return
		end

		local pr_db_row = github_prs.extract_pr_fields(pr_data)
		local repo_row, err = utils.ensure_repo(repo_name)
		if not repo_row then
			log.error(err or "Could not ensure repo in DB for sync")
			callback(nil, "Repo not found or could not be created")
			return
		end
		pr_db_row.repo_id = repo_row.id

		-- Extract latest activity (comments/commits)
		local activity = github_prs.extract_latest_activity(pr_data)
		if activity then
			pr_db_row.last_activity = activity.latest_comment_time or activity.latest_commit_time
		end

		local existing_pr = db_prs.get_by_repo_and_number(pr_db_row.repo_id, pr_db_row.number)
		local old_status = existing_pr and pr_status.get_review_status(existing_pr.id) or nil
		local new_status = old_status

		-- Status transition logic
		if pr_db_row.state == "MERGED" then
			new_status = "merged"
		elseif pr_db_row.state == "CLOSED" then
			new_status = "closed"
		elseif pr_db_row.review_decision == "APPROVED" then
			new_status = "approved"
		elseif existing_pr and old_status == "waiting_for_changes" then
			local parse = utils.parse_iso8601
			local status_history = status.get_status_history(existing_pr.id)
			local waiting_for_changes_id = status.get_id("waiting_for_changes")
			local last_waiting_for_changes_ts = nil
			for _, entry in ipairs(status_history) do
				if entry.to_status_id == waiting_for_changes_id then
					last_waiting_for_changes_ts = entry.timestamp
				end
			end

			if last_waiting_for_changes_ts then
				local last_changes_ts = parse(last_waiting_for_changes_ts)
				local comment_ts = activity.latest_comment_time and parse(activity.latest_comment_time) or nil
				local commit_ts = activity.latest_commit_time and parse(activity.latest_commit_time) or nil

				if (comment_ts and comment_ts > last_changes_ts) or (commit_ts and commit_ts > last_changes_ts) then
					new_status = "waiting_for_review"
				end
			end
		end

		local pr_id = logic_prs.upsert_pr(db_prs, db_repos, pr_db_row)

		local history = status.get_status_history(pr_id)
		if not history or #history == 0 then
			status.add_status_transition(pr_id, nil, pr_db_row.review_status_id)
		end

		pr_status.maybe_transition_status(pr_id, old_status, new_status)

		if pr_data.statusCheckRollup and type(pr_data.statusCheckRollup) == "table" then
			pr_db_row.ci_status = ci.extract_ci_status(pr_data)
		end

		github_data.get_comments_async(pr_number, repo_name, function(comments)
			local formatted_comments = {}
			for _, c in ipairs(comments or {}) do
				local author = c.user and c.user.login or "unknown"
				local created_at = c.createdAt or c.created_at
				if author and created_at then
					table.insert(formatted_comments, {
						github_id = c.id,
						author = author,
						created_at = created_at,
						body = c.body,
						in_reply_to_id = c.in_reply_to_id,
					})
				end
			end
			db_comments.replace_for_pr(pr_id, formatted_comments)
		end)

		callback(pr_id, nil)
	end)
end

function M.select_pr_for_review(pr_id)
	local pr = db_prs.get_by_id(pr_id)
	if not pr then
		return nil, "PR not found"
	end

	local now = os.date("!%Y-%m-%dT%H:%M:%SZ")
	db_prs.update(pr.id, { last_viewed = now })

	local old_status = pr_status.get_review_status(pr.id)
	local new_status = old_status
	if old_status == "waiting_for_review" then
		new_status = "waiting_for_changes"
	end
	pr_status.maybe_transition_status(pr.id, old_status, new_status)

	-- Open in Octo (if available)
	vim.cmd(string.format("Octo pr view %d", pr.number))

	return true
end

return M
