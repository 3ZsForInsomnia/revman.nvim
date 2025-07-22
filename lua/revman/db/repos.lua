local M = {}

local get_db = require("revman.db.create").get_db

function M.add(name, directory)
	local db = get_db()
	db:insert("repositories", { name = name, directory = directory })
	db:close()
end

function M.get_by_name(name)
	local db = get_db()
	local rows = db:select("repositories", { where = { name = name } })
	db:close()
	return rows[1]
end

function M.get_by_id(id)
	local db = get_db()
	local rows = db:select("repositories", { where = { id = id } })
	db:close()
	return rows[1]
end

function M.delete(id)
	local db = get_db()
	db:delete("repositories", { id = id })
	db:close()
end

function M.set_reminder_days(id, days)
	local db = get_db()
	db:update("repositories", { set = { reminder_days = days }, where = { id = id } })
	db:close()
end

function M.get_reminder_days(id)
	local db = get_db()
	local rows = db:select("repositories", { where = { id = id } })
	db:close()
	return rows[1] and rows[1].reminder_days or 3
end

function M.list()
	local db = get_db()
	local rows = db:select("repositories")
	db:close()
	return rows
end

function M.update(id, updates)
	local db = get_db()
	db:update("repositories", { set = updates, where = { id = id } })
	db:close()
end

return M
