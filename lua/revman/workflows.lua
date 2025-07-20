local github_data = require("revman.github.data")
local github_prs = require("revman.github.prs")
local db_prs = require("revman.db.prs")
local db_repos = require("revman.db.repos")
local db_status = require("revman.db.status")
local logic_prs = require("revman.logic.prs")
local utils = require("revman.utils")

local M = {}

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
	pr_db_row.last_activity = activity.latest_comment_time or activity.latest_commit_time

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

	-- Add more status rules as needed...

	-- Upsert PR in DB
	local pr_id = logic_prs.upsert_pr(db_prs, db_repos, pr_db_row)

	-- Handle status transition and history
	db_status.maybe_transition_status(pr_id, old_status, new_status)

	return pr_id
end

-- Sync all PRs for a repo from GitHub to DB
function M.sync_all_prs(repo_name)
	repo_name = repo_name or utils.get_current_repo()
	if not repo_name then
		return nil, "No repo specified"
	end

	local prs_data = github_data.list_prs(repo_name)
	if not prs_data then
		return nil, "Failed to fetch PRs"
	end

	local repo_row = utils.ensure_repo(repo_name)
	if not repo_row then
		return nil, "Repo not found or could not be created"
	end

	local results = {}
	for _, pr_data in ipairs(prs_data) do
		local pr_db_row = github_prs.extract_pr_fields(pr_data)
		pr_db_row.repo_id = repo_row.id
		local pr_id = M.sync_pr(pr_db_row.number, repo_name)
		table.insert(results, pr_id)
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
	db_status.maybe_transition_status(pr.id, old_status, new_status)

	-- Open in Octo (if available)
	vim.cmd(string.format("Octo pr view %d", pr.number))

	return true
end

return M
