local db_comments = require("revman.db.comments")
local utils = require("revman.utils")

local M = {}

M.COPILOT_LOGIN = "Copilot" -- Change if your Copilot bot uses a different login

function M.week_key(ts)
	return os.date("%Y-W%U", ts)
end

function M.is_copilot(login)
	return login == M.COPILOT_LOGIN
end

function M.is_reviewer_comment(comment, pr_author)
	return comment.author ~= pr_author and not M.is_copilot(comment.author)
end

function M.get_prs_by_author(all_prs)
	local prs_by_author = {}
	for _, pr in ipairs(all_prs) do
		local author = pr.author or "unknown"
		prs_by_author[author] = prs_by_author[author] or {}
		table.insert(prs_by_author[author], pr)
	end
	return prs_by_author
end

function M.aggregate_comments(all_prs)
	local pr_comments = {}
	local author_comments_written = {}
	local author_comments_received = {}

	for _, pr in ipairs(all_prs) do
		local comments = db_comments.get_by_pr_id(pr.id) or {}
		pr_comments[pr.id] = comments

		for _, comment in ipairs(comments) do
			local comment_author = comment.author or "unknown"
			author_comments_written[comment_author] = author_comments_written[comment_author]
				or { count = 0, on_own_prs = 0, on_others_prs = 0 }
			author_comments_written[comment_author].count = author_comments_written[comment_author].count + 1
			if comment_author == pr.author then
				author_comments_written[comment_author].on_own_prs = author_comments_written[comment_author].on_own_prs
					+ 1
			else
				author_comments_written[comment_author].on_others_prs = author_comments_written[comment_author].on_others_prs
					+ 1
			end
			if comment_author ~= pr.author then
				author_comments_received[pr.author] = (author_comments_received[pr.author] or 0) + 1
			end
		end
	end

	return pr_comments, author_comments_written, author_comments_received
end

function M.count_closed_without_merge(prs)
	local count = 0
	for _, pr in ipairs(prs) do
		if pr.state == "CLOSED" then
			count = count + 1
		end
	end
	return count
end

function M.count_merged(prs)
	local count = 0
	for _, pr in ipairs(prs) do
		if pr.state == "MERGED" then
			count = count + 1
		end
	end
	return count
end

function M.opened_merged_per_week(prs)
	local opened_per_week, merged_per_week = {}, {}
	for _, pr in ipairs(prs) do
		local created_ts = pr.created_at and utils.parse_iso8601(pr.created_at)
		if created_ts then
			local wk = M.week_key(created_ts)
			opened_per_week[wk] = (opened_per_week[wk] or 0) + 1
		end
		if pr.state == "MERGED" and pr.last_activity then
			local merged_ts = utils.parse_iso8601(pr.last_activity)
			if merged_ts then
				local wk = M.week_key(merged_ts)
				merged_per_week[wk] = (merged_per_week[wk] or 0) + 1
			end
		end
	end
	return opened_per_week, merged_per_week
end

function M.avg_time_to_first_comment(prs, pr_comments, pr_author)
	local total_time = 0
	local count = 0
	for _, pr in ipairs(prs) do
		local created_ts = pr.created_at and utils.parse_iso8601(pr.created_at)
		local comments = pr_comments[pr.id] or {}
		local first_comment_ts = nil
		for _, comment in ipairs(comments) do
			local comment_author = comment.author or "unknown"
			if comment_author ~= pr_author and not M.is_copilot(comment_author) then
				local ts = comment.created_at and utils.parse_iso8601(comment.created_at)
				if ts and (not first_comment_ts or ts < first_comment_ts) then
					first_comment_ts = ts
				end
			end
		end
		if created_ts and first_comment_ts then
			total_time = total_time + (first_comment_ts - created_ts)
			count = count + 1
		end
	end
	return count > 0 and (total_time / count) or nil
end

function M.avg_review_cycles(prs, pr_comments, pr_author)
	local review_cycles_total, review_cycles_prs = 0, 0
	for _, pr in ipairs(prs) do
		local events = {}
		-- Add commits (by PR author)
		if pr.commits then
			for _, commit in ipairs(pr.commits) do
				table.insert(events, {
					type = "commit",
					ts = commit.committedDate and utils.parse_iso8601(commit.committedDate) or 0,
				})
			end
		end
		-- Add reviewer comments (not Copilot, not PR author)
		local comments = pr_comments[pr.id] or {}
		for _, comment in ipairs(comments) do
			if M.is_reviewer_comment(comment, pr_author) then
				table.insert(events, {
					type = "review_comment",
					ts = comment.created_at and utils.parse_iso8601(comment.created_at) or 0,
				})
			end
		end
		table.sort(events, function(a, b)
			return a.ts < b.ts
		end)

		-- Count cycles: a commit followed by a reviewer comment
		local cycles = 0
		local last_event = nil
		for _, event in ipairs(events) do
			if event.type == "review_comment" and last_event == "commit" then
				cycles = cycles + 1
			end
			last_event = event.type
		end
		if cycles > 0 then
			review_cycles_total = review_cycles_total + cycles
			review_cycles_prs = review_cycles_prs + 1
		end
	end
	return review_cycles_prs > 0 and (review_cycles_total / review_cycles_prs) or 0
end

return M
