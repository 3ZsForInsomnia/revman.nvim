local config = require("revman.config")
local sync = require("revman.sync")
---@diagnostic disable-next-line: unused-local
local commands = require("revman.commands")
---@diagnostic disable-next-line: unused-local
local sync_commands = require("revman.sync_commands")
---@diagnostic disable-next-line: unused-local
local repo_commands = require("revman.repo_commands")
local db_schema = require("revman.db.schema")
local utils = require("revman.utils")

local M = {}

function M.setup(user_opts)
	config.setup(user_opts)

	if not utils.db_file_exists() then
		db_schema.ensure_schema()
	end

	sync.setup_autosync()
	-- DO NOT UNCOMMENT THESE UNLESS you have a very good reason
	-- require("revman.scripts.migrate_comments")()
	-- require("revman.scripts.backfill_db")()
end

return M
