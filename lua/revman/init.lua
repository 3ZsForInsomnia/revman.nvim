local config = require("revman.config")
local sync = require("revman.sync")
---@diagnostic disable-next-line: unused-local
local commands = require("revman.commands")
local db_create = require("revman.db.create")
local utils = require("revman.utils")

local M = {}

function M.setup(user_opts)
	config.setup(user_opts)

	local ok, sqlite = pcall(require, "sqlite.db")
	assert(ok, "sqlite.lua not installed")
	local path = "file:" .. vim.fn.stdpath("state") .. "/revman/test_sqlite_lua.db"
	print("path", path)
	local db, err = sqlite:open(path, { open_mode = "rwc" })
	if err then
		print("Error opening database: " .. tostring(err))
		return
	end
	db:execute([[
     CREATE TABLE IF NOT EXISTS test (
       id INTEGER PRIMARY KEY,
       name TEXT NOT NULL
     )
   ]])
	db:execute("INSERT iNTO test (name) VALUES ('Hello, again!')")
	db:close()
	print("Success!")

	-- if not utils.db_file_exists() then
	-- 	db_create.ensure_schema()
	-- end

	-- sync.setup_autosync()
end

return M
