local config = require("revman.config")
local sync = require("revman.sync")
---@diagnostic disable-next-line: unused-local
local commands = require("revman.commands")
local db_create = require("revman.db.create")
local utils = require("revman.utils")

local M = {}

function M.setup(user_opts)
	config.setup(user_opts)

	if not utils.db_file_exists() then
		db_create.ensure_schema()
	end

	sync.setup_autosync()
end

return M
