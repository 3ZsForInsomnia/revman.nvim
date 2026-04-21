local M = {}
local with_db = require("revman.db.helpers").with_db

local INSERT_SQL = "INSERT INTO notes (pr_id, content, updated_at) "
	.. "VALUES (:pr_id, :content, :updated_at)"

function M.add(pr_id, content, updated_at)
	with_db(function(db)
		db:eval(INSERT_SQL, {
			pr_id = pr_id,
			content = content,
			updated_at = updated_at,
		})
	end)
end

function M.get_by_pr_id(pr_id)
	return with_db(function(db)
		local rows = db:select("notes", { where = { pr_id = pr_id } })
		return rows[1]
	end)
end

function M.update_by_pr_id(pr_id, updates)
	with_db(function(db)
		db:update("notes", { set = updates, where = { pr_id = pr_id } })
	end)
end

function M.delete_by_id(id)
	with_db(function(db)
		db:delete("notes", { id = id })
	end)
end

return M
