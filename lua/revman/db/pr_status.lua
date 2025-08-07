local log = require("revman.log")
local with_db = require("revman.db.helpers").with_db
local status = require("revman.db.status")
local prs = require("revman.db.prs")

local M = {}

function M.get_review_status(pr_id)
	local pr = prs.get_by_id(pr_id)
	if not pr then
		return nil, "PR not found"
	end
	return status.get_name(pr.review_status_id)
end

M.maybe_transition_status = function(pr_id, old_status, new_status)
	if not new_status or new_status == old_status then
		return
	end

	M.set_review_status(pr_id, new_status)

	local from_id = status.get_id(old_status)
	local to_id = status.get_id(new_status)

	status.add_status_transition(pr_id, from_id, to_id)
end

function M.set_review_status(pr_id, status_name)
	local status_id = status.get_id(status_name)

	if not status_id then
		log.error("db_prs.set_review_status: Unknown status: " .. status_name)
		return false
	end

	return with_db(function(db)
		-- Get old status before updating
		local pr = db:select("pull_requests", { where = { id = pr_id } })[1]
		local old_status = pr and status.get_name(pr.review_status_id) or nil

		db:update("pull_requests", { set = { review_status_id = status_id }, where = { id = pr_id } })

		M.maybe_transition_status(pr_id, old_status, status_name)

		return true
	end)
end

return M
