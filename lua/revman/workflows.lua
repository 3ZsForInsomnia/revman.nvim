local github_data = require("revman.github.data")
local ci = require("revman.github.ci")
local github_prs = require("revman.github.prs")
local db_prs = require("revman.db.prs")
local db_repos = require("revman.db.repos")
local logic_prs = require("revman.logic.prs")
local utils = require("revman.utils")
local log = require("revman.log")

local M = {}

local function async_get_pr(pr_number, repo, callback)
	local cmd = {
		"gh",
		"pr",
		"view",
		tostring(pr_number),
		"--json",
		"number,title,state,url,author,createdAt,isDraft,reviewDecision,statusCheckRollup,body",
		"-R",
		repo,
	}
	local stdout = vim.loop.new_pipe(false)
	local stderr = vim.loop.new_pipe(false)
	local output = {}

	local handle
	handle = vim.loop.spawn(cmd[1], {
		args = { unpack(cmd, 2) },
		stdio = { nil, stdout, stderr },
	}, function(code, signal)
		stdout:close()
		stderr:close()
		handle:close()
		if code == 0 then
			local json = table.concat(output)
			local ok, pr_data = pcall(vim.json.decode, json)
			if ok then
				vim.schedule(function()
					callback(pr_data)
				end)
			else
				vim.schedule(function()
					callback(nil, "Failed to decode JSON")
				end)
			end
		else
			vim.schedule(function()
				callback(nil, "gh exited with code " .. code)
			end)
		end
	end)

	stdout:read_start(function(err, data)
		assert(not err, err)
		if data then
			table.insert(output, data)
		end
	end)
	stderr:read_start(function(err, data) end)
end

function M.sync_all_tracked_prs_async(repo_name)
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

	local tracked_prs = db_prs.list({ where = { repo_id = repo_row.id } })
	if #tracked_prs == 0 then
		log.info("No tracked PRs to sync for this repo.")
		return
	end

	local remaining = #tracked_prs
	local errors = {}
	local results = {}

	for _, pr in ipairs(tracked_prs) do
		async_get_pr(pr.number, repo_name, function(pr_data, err)
			if pr_data then
				local pr_db_row = github_prs.extract_pr_fields(pr_data)
				pr_db_row.repo_id = repo_row.id

				-- Extract latest activity
				local activity = github_prs.extract_latest_activity(pr_data)
				if activity then
					pr_db_row.last_activity = activity.latest_comment_time or activity.latest_commit_time
				end

				-- Extract CI status
				if pr_data.statusCheckRollup and type(pr_data.statusCheckRollup) == "table" then
					local ci_summary = ci.extract_ci_status(pr_data)
					pr_db_row.ci_status = ci_summary and ci_summary.status or nil
				end

				local pr_id = logic_prs.upsert_pr(db_prs, db_repos, pr_db_row)
				table.insert(results, pr_id)
			else
				table.insert(errors, "Failed to fetch PR #" .. pr.number .. ": " .. (err or "unknown error"))
			end

			remaining = remaining - 1
			if remaining == 0 then
				if #errors > 0 then
					log.error("Some PRs failed to sync: " .. table.concat(errors, "; "))
				else
					log.info("All tracked PRs synced successfully: " .. vim.inspect(results))
				end
			end
		end)
	end
end

function M.sync_pr(pr_number, repo_name)
	repo_name = repo_name or utils.get_current_repo()
	if not repo_name then
		return nil, "No repo specified"
	end

	local pr_data = github_data.get_pr(pr_number, repo_name)
	if not pr_data then
		return nil, "Failed to fetch PR"
	end

	local pr_db_row = github_prs.extract_pr_fields(pr_data)
	local repo_row = utils.ensure_repo(repo_name)
	if not repo_row then
		return nil, "Repo not found or could not be created"
	end
	pr_db_row.repo_id = repo_row.id

	-- Extract latest activity (comments/commits)
	local activity = github_prs.extract_latest_activity(pr_data)
	if activity then
		pr_db_row.last_activity = activity.latest_comment_time or activity.latest_commit_time
	end

	-- Get current DB PR (if exists) to compare status/activity
	local existing_pr = db_prs.get_by_repo_and_number(pr_db_row.repo_id, pr_db_row.number)
	local old_status = existing_pr and db_prs.get_review_status(existing_pr.id) or nil
	local new_status = old_status

	-- Example status transition logic:
	-- If new comments/commits since last_viewed, set to "waiting_for_review"
	if existing_pr and existing_pr.last_viewed then
		if
			(activity.latest_comment_time and activity.latest_comment_time > existing_pr.last_viewed)
			or (activity.latest_commit_time and activity.latest_commit_time > existing_pr.last_viewed)
		then
			new_status = "waiting_for_review"
		end
	end

	-- If PR is merged, set status to "merged"
	if pr_db_row.state == "MERGED" then
		new_status = "merged"
	elseif pr_db_row.state == "CLOSED" then
		new_status = "closed"
	end

	-- If PR is approved, set status to "approved"
	if pr_db_row.review_decision == "APPROVED" then
		new_status = "approved"
	end

	-- Upsert PR in DB
	local pr_id = logic_prs.upsert_pr(db_prs, db_repos, pr_db_row)

	-- Handle status transition and history
	db_prs.maybe_transition_status(pr_id, old_status, new_status)

	if pr_data.statusCheckRollup and type(pr_data.statusCheckRollup) == "table" then
		local ci_summary = ci.extract_ci_status(pr_data)
		pr_db_row.ci_status = ci_summary and ci_summary.status or nil
	end

	return pr_id
end

-- Sync all PRs for a repo from GitHub to DB
function M.sync_all_prs(repo_name)
	repo_name = repo_name or utils.get_current_repo()
	if not repo_name then
		return nil, "No repo specified"
	end

	local repo_row = utils.ensure_repo(repo_name)
	if not repo_row then
		return nil, "Repo not found or could not be created"
	end

	-- Get all tracked PRs for this repo
	local tracked_prs = db_prs.list({ where = { repo_id = repo_row.id } })
	local results = {}

	for _, pr in ipairs(tracked_prs) do
		local pr_data = github_data.get_pr(pr.number, repo_name)
		if pr_data then
			-- Now you can extract/transform and upsert as before
			local pr_db_row = github_prs.extract_pr_fields(pr_data)
			pr_db_row.repo_id = repo_row.id
			local pr_id = logic_prs.upsert_pr(db_prs, db_repos, pr_db_row)
			table.insert(results, pr_id)
		end
	end
	return results
end

-- Workflow: select a PR for review (open in Octo, update status/timestamps)
function M.select_pr_for_review(pr_id)
	local pr = db_prs.get_by_id(pr_id)
	if not pr then
		return nil, "PR not found"
	end

	-- Update last_viewed timestamp
	local now = os.date("!%Y-%m-%dT%H:%M:%SZ")
	db_prs.update(pr.id, { last_viewed = now })

	-- If status is "waiting_for_review", transition to "waiting_for_changes"
	local old_status = db_prs.get_review_status(pr.id)
	local new_status = old_status
	if old_status == "waiting_for_review" then
		new_status = "waiting_for_changes"
	end
	db_prs.maybe_transition_status(pr.id, old_status, new_status)

	-- Open in Octo (if available)
	vim.cmd(string.format("Octo pr view %d", pr.number))

	return true
end

return M
