local M = {}

local get_db = require("revman.db.create").get_db

function M.get_id(name)
	local db = get_db()
	local rows = db:select("review_status", { where = { name = name } })
	db:close()
	return rows[1] and rows[1].id or nil
end

function M.get_name(id)
	local db = get_db()
	local rows = db:select("review_status", { where = { id = id } })
	db:close()
	return rows[1] and rows[1].name or nil
end

function M.add(name)
	local db = get_db()
	db:insert("review_status", { name = name })
	db:close()
end

function M.delete(id)
	local db = get_db()
	db:delete("review_status", { id = id })
	db:close()
end

function M.list()
	local db = get_db()
	local rows = db:select("review_status")
	db:close()
	return rows
end

function M.add_status_transition(pr_id, from_status_id, to_status_id)
	local db = get_db()
	db:insert("review_status_history", {
		pr_id = pr_id,
		from_status_id = from_status_id,
		to_status_id = to_status_id,
		timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
	})
	db:close()
end

function M.get_status_history(pr_id)
	local db = get_db()
	local rows = db:select("review_status_history", { where = { pr_id = pr_id } })
	db:close()
	return rows
end

return M
