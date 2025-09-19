local config = require("revman.config")
local log = require("revman.log")
local has_sqlite, sqlite = pcall(require, "sqlite.db")
if not has_sqlite then
	log.error("This plugin requires kkharji/sqlite.lua to function properly")
	return {}
end

local M = {}

function M.get_db()
	local db_path = config.get().database_path
	return sqlite:open(db_path)
end

function M.with_db(fn)
	local db = M.get_db()
	local ok, result_or_err = pcall(fn, db)
	local close_ok, close_err = pcall(function()
		db:close()
	end)
	if not ok then
		error(result_or_err)
	end
	if not close_ok then
		error("DB close failed: " .. tostring(close_err))
	end
	return result_or_err
end

return M
