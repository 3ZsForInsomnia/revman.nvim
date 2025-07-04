local M = {}
local db = require("revman.db")
local github = require("revman.github")

-- PR status constants
M.STATUS = {
	WAITING_FOR_REVIEW = "waiting_for_review",
	WAITING_FOR_UPDATES = "waiting_for_updates",
	APPROVED = "approved",
	MERGED = "merged",
}

-- Set PR status
function M.set_status(pr_number, status)
	if not vim.tbl_contains(vim.tbl_values(M.STATUS), status) then
		return false, "Invalid status: " .. status
	end

	-- Get current PR
	local pr = db.get_pr(pr_number)
	if not pr then
		return false, "PR not found in database"
	end

	-- Update status in database
	local success, err = db.update_pr_status(pr_number, status)
	if not success then
		return false, err
	end

	-- Record status change in history
	local history_entry = {
		timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
		from_status = pr.status,
		to_status = status,
	}

	db.add_status_history(pr_number, history_entry)

	return true
end

-- Get PR status
function M.get_status(pr_number)
	local pr = db.get_pr(pr_number)
	if not pr then
		return nil, "PR not found in database"
	end

	return pr.status
end

-- Get status history
function M.get_status_history(pr_number)
	return db.get_status_history(pr_number)
end

-- Determine if PR needs attention based on status and activity
function M.needs_attention(pr_number)
	local pr = db.get_pr(pr_number)
	if not pr then
		return false
	end

	-- PR needs attention if:
	-- 1. Status is waiting_for_review
	-- 2. Status is waiting_for_updates but there's new activity since last viewed
	if pr.status == M.STATUS.WAITING_FOR_REVIEW then
		return true
	elseif pr.status == M.STATUS.WAITING_FOR_UPDATES then
		return pr.last_activity and pr.last_viewed and pr.last_activity > pr.last_viewed
	end

	return false
end

-- Auto-update PR status based on GitHub state
function M.auto_update_status(pr_number)
	local pr = db.get_pr(pr_number)
	if not pr then
		return false, "PR not found in database"
	end

	-- If PR is merged, update status to merged
	if pr.state == "MERGED" and pr.status ~= M.STATUS.MERGED then
		return M.set_status(pr_number, M.STATUS.MERGED)
	end

	-- If PR is approved, update status to approved
	if pr.review_decision == "APPROVED" and pr.status ~= M.STATUS.APPROVED then
		return M.set_status(pr_number, M.STATUS.APPROVED)
	end

	return true
end

-- Add PR (wrapper around db.add_pr that also sets initial status)
function M.add_pr(pr_number)
	-- Get PR details from GitHub
	local github = require("revman.github")
	local pr_details, err = github.get_pr_details(pr_number)
	if not pr_details then
		return false, "Failed to fetch PR details: " .. (err or "Unknown error")
	end

	-- Get activity info
	local activity = github.get_pr_activity(pr_number)

	-- Get CI status
	local ci = require("revman.ci")
	local ci_status = ci.get_ci_status(pr_number)

	-- Determine initial status
	local initial_status = M.STATUS.WAITING_FOR_REVIEW
	if pr_details.state == "MERGED" then
		initial_status = M.STATUS.MERGED
	elseif pr_details.reviewDecision == "APPROVED" then
		initial_status = M.STATUS.APPROVED
	end

	-- Add to database
	local success, db_err = db.add_pr(pr_details, activity, ci_status, initial_status)
	if not success then
		return false, db_err
	end

	return true
end

-- Get all PRs that need attention
function M.get_attention_needed_prs()
	local all_prs = db.get_prs()
	local result = {}

	for _, pr in ipairs(all_prs) do
		if M.needs_attention(pr.number) then
			table.insert(result, pr)
		end
	end

	return result
end

return M
