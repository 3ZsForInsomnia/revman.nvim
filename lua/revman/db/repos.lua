local M = {}

local with_db = require("revman.db.helpers").with_db

function M.add(name, directory)
	with_db(function(db)
		db:insert("repositories", { name = name, directory = directory })
	end)
end

function M.get_by_name(name)
	return with_db(function(db)
		local rows = db:select("repositories", { where = { name = name } })
		return rows[1]
	end)
end

function M.get_by_id(id)
	return with_db(function(db)
		local rows = db:select("repositories", { where = { id = id } })
		return rows[1]
	end)
end

function M.delete(id)
	with_db(function(db)
		db:delete("repositories", { id = id })
	end)
end

function M.set_reminder_days(id, days)
	with_db(function(db)
		db:update("repositories", { set = { reminder_days = days }, where = { id = id } })
	end)
end

function M.get_reminder_days(id)
	return with_db(function(db)
		local rows = db:select("repositories", { where = { id = id } })
		return rows[1] and rows[1].reminder_days or 3
	end)
end

function M.list()
	return with_db(function(db)
		return db:select("repositories")
	end)
end

function M.update(id, updates)
	with_db(function(db)
		db:update("repositories", { set = updates, where = { id = id } })
	end)
end

return M
