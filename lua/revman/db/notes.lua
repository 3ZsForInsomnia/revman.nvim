local M = {}
local get_db = require("revman.db.create").get_db

function M.add(pr_id, content, updated_at)
	local db = get_db()
	db:insert("notes", { pr_id = pr_id, content = content, updated_at = updated_at })
	db:close()
end

function M.get_by_pr_id(pr_id)
	local db = get_db()
	local rows = db:select("notes", { where = { pr_id = pr_id } })
	db:close()
	return rows[1]
end

function M.update_by_pr_id(pr_id, updates)
	local db = get_db()
	db:update("notes", { set = updates, where = { pr_id = pr_id } })
	db:close()
end

function M.delete_by_id(id)
	local db = get_db()
	db:delete("notes", { id = id })
	db:close()
end

return M
