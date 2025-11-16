local config = require("revman.config")

local M = {}

-- Check if we're in a git repository
local function is_in_git_repo()
	local lines = vim.fn.systemlist("gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null")
	return vim.v.shell_error == 0 and #lines > 0 and lines[1] ~= ""
end

function M.setup(user_opts)
	config.setup(user_opts)

	-- Early exit if not in a git repository
	if not is_in_git_repo() then
		return
	end

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

function M.load_commands()
	require("revman.commands")
	require("revman.sync_commands") 
	require("revman.repo_commands")
	
	-- Load backend-specific commands
	local config = require("revman.config")
	local picker_backend = config.get().picker or "vimSelect"
	
	if picker_backend == "snacks" then
		require("revman.snacks.commands").load_commands()
	end
end

	-- DO NOT UNCOMMENT THESE UNLESS you have a very good reason
	-- require("revman.scripts.migrate_comments")()
	-- require("revman.scripts.backfill_db")()

return M
