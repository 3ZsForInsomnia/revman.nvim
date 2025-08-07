local helpers = require("revman.db.helpers")

local M = {}

function M.get_review_status_id(name)
	if not name then
		return nil
	end
	return helpers.with_db(function(db)
		local rows = db:select("review_status", { where = { name = name } })
		return rows[1] and rows[1].id or nil
	end)
end

function M.get_review_status_name(id)
	if not id then
		return nil
	end
	return helpers.with_db(function(db)
		local rows = db:select("review_status", { where = { id = id } })
		return rows[1] and rows[1].name or nil
	end)
end

function M.set_review_status(pr_id, status_name)
	local status_id = M.get_review_status_id(status_name)
	if not status_id then
		return false, "Unknown status: " .. status_name
	end
	helpers.with_db(function(db)
		db:update("pull_requests", { set = { review_status_id = status_id }, where = { id = pr_id } })
	end)
	return true
end

function M.get_review_status(pr_id)
	return helpers.with_db(function(db)
		local pr = db:select("pull_requests", { where = { id = pr_id } })
		if not pr[1] then
			return nil, "PR not found"
		end
		return M.get_review_status_name(pr[1].review_status_id)
	end)
end

return M
