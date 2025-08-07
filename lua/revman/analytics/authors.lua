local pr_lists = require("revman.db.pr_lists")
local utils = require("revman.utils")
local analytics_utils = require("revman.analytics.utils")

local M = {}

function M.get_author_analytics()
	local all_prs = pr_lists.list()
	local prs_by_author = analytics_utils.get_prs_by_author(all_prs)
	local pr_comments, author_comments_written, author_comments_received = analytics_utils.aggregate_comments(all_prs)

	local stats = {}
	for author, prs in pairs(prs_by_author) do
		local opened_per_week, merged_per_week = analytics_utils.opened_merged_per_week(prs)
		local opened_weeks, merged_weeks = 0, 0
		local opened_total, merged_total = 0, 0
		for _, v in pairs(opened_per_week) do
			opened_total = opened_total + v
			opened_weeks = opened_weeks + 1
		end
		for _, v in pairs(merged_per_week) do
			merged_total = merged_total + v
			merged_weeks = merged_weeks + 1
		end

		local avg_first_comment = analytics_utils.avg_time_to_first_comment(prs, pr_comments, author)
		local avg_first_comment_human = avg_first_comment and utils.format_relative_time(avg_first_comment) or "N/A"
		local avg_cycles = analytics_utils.avg_review_cycles(prs, pr_comments, author)

		stats[author] = {
			prs_opened = #prs,
			prs_merged = analytics_utils.count_merged(prs),
			prs_closed_without_merge = analytics_utils.count_closed_without_merge(prs),
			prs_opened_per_week = opened_per_week,
			prs_merged_per_week = merged_per_week,
			prs_opened_per_week_avg = opened_weeks > 0 and (opened_total / opened_weeks) or 0,
			prs_merged_per_week_avg = merged_weeks > 0 and (merged_total / merged_weeks) or 0,
			comments_written = author_comments_written[author] and author_comments_written[author].count or 0,
			comments_on_own_prs = author_comments_written[author] and author_comments_written[author].on_own_prs or 0,
			comments_on_others_prs = author_comments_written[author] and author_comments_written[author].on_others_prs
				or 0,
			comments_received = author_comments_received[author] or 0,
			avg_time_to_first_comment = avg_first_comment,
			avg_time_to_first_comment_human = avg_first_comment_human,
			avg_review_cycles = avg_cycles,
		}
	end

	return stats
end

return M
