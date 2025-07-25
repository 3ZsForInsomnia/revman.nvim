local M = {}

local with_db = require("revman.db.create").with_db

function M.get_id(name)
	return with_db(function(db)
		local rows = db:select("review_status", { where = { name = name } })
		if rows[1] then
			return rows[1].id
		else
			db:insert("review_status", { name = name })
			local new_rows = db:select("review_status", { where = { name = name } })
			return new_rows[1] and new_rows[1].id or nil
		end
	end)
end

function M.get_name(id)
	if not id then
		return nil
	end

	return with_db(function(db)
		local rows = db:select("review_status", { where = { id = id } })
		return rows[1] and rows[1].name or nil
	end)
end

function M.add(name)
	with_db(function(db)
		db:insert("review_status", { name = name })
	end)
end

function M.delete(id)
	with_db(function(db)
		db:delete("review_status", { id = id })
	end)
end

function M.list()
	return with_db(function(db)
		local rows = db:select("review_status")
		return rows
	end)
end

function M.add_status_transition(pr_id, from_status_id, to_status_id)
	with_db(function(db)
		db:insert("review_status_history", {
			pr_id = pr_id,
			from_status_id = from_status_id,
			to_status_id = to_status_id,
			timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
		})
	end)
end

function M.get_status_history(pr_id)
	return with_db(function(db)
		local rows = db:select("review_status_history", { where = { pr_id = pr_id } })
		return rows
	end)
end

return M
