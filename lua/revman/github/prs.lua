local M = {}

local data = require("revman.github.data")

function M.extract_pr_fields(pr)
	if not pr then
		return nil
	end

	local latest_activity_time = M.extract_latest_activity(pr)

	return {
		number = pr.number,
		title = pr.title,
		state = pr.state,
		url = pr.url,
		author = pr.author and pr.author.login or nil,
		created_at = pr.createdAt,
		is_draft = pr.isDraft and 1 or 0,
		review_decision = pr.reviewDecision,
		comment_count = pr.comment_count,
		last_activity = latest_activity_time.latest_activity_time,
	}
end

function M.extract_assignees(pr)
	if not pr or not pr.assignees then
		return {}
	end
	
	local assignees = {}
	for _, assignee in ipairs(pr.assignees) do
		if assignee.login then
			table.insert(assignees, assignee.login)
		end
	end
	
	return assignees
end

function M.extract_multiple_prs(prs_data)
	local result = {}
	for _, pr in ipairs(prs_data or {}) do
		table.insert(result, data.convert_pr_to_db(pr))
	end
	return result
end

function M.extract_comments(pr_data)
	return pr_data and pr_data.comments or {}
end

function M.extract_comment_count(pr_data)
	local count = 0

	if pr_data and pr_data.comments then
		count = count + #pr_data.comments
	end

	if pr_data and pr_data.reviews then
		count = count + #pr_data.reviews
	end

	return count
end

function M.extract_commits(pr_data)
	return pr_data and pr_data.commits or {}
end

function M.extract_latest_activity(pr_data)
	local latest_comment_time = nil
	if pr_data and pr_data.comments then
		for _, comment in ipairs(pr_data.comments) do
			if not latest_comment_time or comment.createdAt > latest_comment_time then
				latest_comment_time = comment.createdAt
			end
		end
	end

	local latest_commit_time = nil
	if pr_data and pr_data.commits then
		for _, commit in ipairs(pr_data.commits) do
			if not latest_commit_time or commit.committedDate > latest_commit_time then
				latest_commit_time = commit.committedDate
			end
		end
	end

	local latest_activity_time = latest_comment_time
	if latest_commit_time and (not latest_activity_time or latest_commit_time > latest_activity_time) then
		latest_activity_time = latest_commit_time
	end

	return {
		latest_comment_time = latest_comment_time,
		latest_commit_time = latest_commit_time,
		latest_activity_time = latest_activity_time,
	}
end

function M.extract_multiple_prs_by_number(prs_data, pr_numbers)
	local results = {}
	for _, pr_number in ipairs(pr_numbers) do
		if prs_data[tostring(pr_number)] then
			results[tostring(pr_number)] = prs_data[tostring(pr_number)]
		end
	end
	return results
end

function M.has_new_activity(latest_activity, last_viewed_time)
	local comment_newer = latest_activity.latest_comment_time and latest_activity.latest_comment_time > last_viewed_time
	local commit_newer = latest_activity.latest_commit_time and latest_activity.latest_commit_time > last_viewed_time
	return comment_newer or commit_newer
end

return M
