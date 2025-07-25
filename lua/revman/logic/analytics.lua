local db_prs = require("revman.db.prs")
local db_status = require("revman.db.status")
local utils = require("revman.utils")

local M = {}

function M.analytics_by_author()
	local all_prs = db_prs.list()
	local by_author = {}
	for _, pr in ipairs(all_prs) do
		local author = pr.author or "unknown"
		by_author[author] = by_author[author] or {}
		table.insert(by_author[author], pr)
	end
	return by_author
end

function M.average_pr_age_at_merge()
	local prs = db_prs.list()
	local ages = {}
	for _, pr in ipairs(prs) do
		if pr.state == "MERGED" then
			local created = pr.created_at and utils.parse_iso8601(pr.created_at)
			local merged = pr.last_activity and utils.parse_iso8601(pr.last_activity)
			if created and merged then
				local author = pr.author or "unknown"
				ages[author] = ages[author] or { total = 0, count = 0 }
				ages[author].total = ages[author].total + (merged - created)
				ages[author].count = ages[author].count + 1
			end
		end
	end
	local result = {}
	for author, data in pairs(ages) do
		result[author] = data.count > 0 and (data.total / data.count) or 0
	end
	return result
end

function M.prs_reviewed_over_time()
	local history = db_status.get_all_status_history()
	local counts = { day = {}, week = {}, month = {} }
	for _, entry in ipairs(history) do
		local ts = utils.parse_iso8601(entry.timestamp)
		if ts then
			local day = os.date("%Y-%m-%d", ts)
			local week = os.date("%Y-W%U", ts)
			local month = os.date("%Y-%m", ts)
			counts.day[day] = (counts.day[day] or 0) + 1
			counts.week[week] = (counts.week[week] or 0) + 1
			counts.month[month] = (counts.month[month] or 0) + 1
		end
	end
	return counts
end

function M.approved_without_changes()
	local prs = db_prs.list()
	local result = {}
	for _, pr in ipairs(prs) do
		local history = db_status.get_status_history(pr.id)
		local saw_changes = false
		for _, entry in ipairs(history) do
			local to_status = db_status.get_name(entry.to_status_id)
			if to_status == "waiting_for_changes" then
				saw_changes = true
			elseif to_status == "approved" and not saw_changes then
				local author = pr.author or "unknown"
				result[author] = (result[author] or 0) + 1
			end
		end
	end
	return result
end

function M.revisits_after_changes()
	local prs = db_prs.list()
	local revisits = {}
	for _, pr in ipairs(prs) do
		local history = db_status.get_status_history(pr.id)
		local count = 0
		for _, entry in ipairs(history) do
			local from_status = db_status.get_name(entry.from_status_id)
			local to_status = db_status.get_name(entry.to_status_id)
			if
				from_status == "waiting_for_changes" and (to_status == "waiting_for_review" or to_status == "approved")
			then
				count = count + 1
			end
		end
		revisits[pr.id] = count
	end
	return revisits
end

function M.authors_with_preview()
	local by_author = M.analytics_by_author()
	local avg_age = M.average_pr_age_at_merge()
	local result = {}
	for author, prs in pairs(by_author) do
		table.insert(result, {
			author = author,
			pr_count = #prs,
			avg_age_at_merge = avg_age[author] or 0,
		})
	end
	return result
end

return M
