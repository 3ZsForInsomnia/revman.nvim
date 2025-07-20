local M = {}
local get_db = require("revman.db.create").get_db
local review_status = require("revman.db.review_status")

function M.add(pr)
	local db = get_db()
	db:insert("pull_requests", pr)
	db:close()
end

function M.get_by_id(id)
	local db = get_db()
	local rows = db:select("pull_requests", { where = { id = id } })
	db:close()
	return rows[1]
end

function M.get_by_repo_and_number(repo_id, number)
	local db = get_db()
	local rows = db:select("pull_requests", { where = { repo_id = repo_id, number = number } })
	db:close()
	return rows[1]
end

function M.set_review_status(pr_id, status_name)
	local status_id = review_status.get_id(status_name)
	if not status_id then
		return false, "Unknown status: " .. status_name
	end
	local db = get_db()
	db:update("pull_requests", { review_status_id = status_id }, { id = pr_id })
	db:close()
	return true
end

function M.update(id, updates)
	local db = get_db()
	db:update("pull_requests", updates, { id = id })
	db:close()
end

function M.get_review_status(pr_id)
	local pr = M.get_by_id(pr_id)
	if not pr then
		return nil, "PR not found"
	end
	return review_status.get_name(pr.review_status_id)
end

function M.list(opts)
	local db = get_db()
	local rows
	if opts and opts.where then
		rows = db:select("pull_requests", { where = opts.where })
	else
		rows = db:select("pull_requests")
	end
	db:close()
	return rows
end

function M.list_open()
	local db = get_db()
	local rows = db:select("pull_requests", { where = { state = "OPEN" } })
	db:close()
	return rows
end

function M.list_merged()
	local db = get_db()
	local rows = db:select("pull_requests", { where = { state = "MERGED" } })
	db:close()
	return rows
end

return M
