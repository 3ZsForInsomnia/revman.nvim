local config = require("revman.config")
local sync = require("revman.sync")
---@diagnostic disable-next-line: unused-local
local commands = require("revman.commands")
local db_create = require("revman.db.create")

local M = {}

function M.setup(user_opts)
	-- 1. Setup user config (merges with defaults)
	config.setup(user_opts)

	-- 2. Ensure DB schema and review statuses exist
	db_create.ensure_schema()
	db_create.ensure_review_statuses()

	-- 3. Register user commands (side effect of requiring commands)
	-- (Already done by requiring 'commands' above)

	-- 4. Setup background sync if enabled
	sync.setup_autosync()
end

return M
