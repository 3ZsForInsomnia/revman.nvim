local config = require("revman.config")

local M = {}

function M.setup(user_opts)
	config.setup(user_opts)

	-- Create lightweight command stubs immediately
	local command_stubs = require("revman.command_stubs")
	command_stubs.create_command_stubs()

	-- Only setup auto-sync immediately - everything else loads on-demand
	vim.schedule(function()
		local utils = require("revman.utils")
		local db_schema = require("revman.db.schema")

		if not utils.db_file_exists() then
			db_schema.ensure_schema()
		end

		local sync = require("revman.sync")
		sync.setup_autosync()
	end)
end

-- Function to load all commands - call this from lazy.nvim config when needed
function M.load_commands()
	require("revman.commands")
	require("revman.sync_commands") 
	require("revman.repo_commands")
end

	-- DO NOT UNCOMMENT THESE UNLESS you have a very good reason
	-- require("revman.scripts.migrate_comments")()
	-- require("revman.scripts.backfill_db")()

return M
