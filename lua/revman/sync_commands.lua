local M = {}

-- Create real commands (replacing stubs)
local function create_commands()
	vim.api.nvim_create_user_command("RevmanSyncAllPRs", function()
	local workflows = require("revman.workflows")
	local log = require("revman.log")
	workflows.sync_all_prs(nil, false, function(success)
		if not success then
			log.error("Some PRs failed to sync.")
		end
	end)
	end, {})

	vim.api.nvim_create_user_command("RevmanSyncPR", function(opts)
	local workflows = require("revman.workflows")
	local log = require("revman.log")
	local cmd_utils = require("revman.command-utils")
	local pr_number = tonumber(opts.args)
	local sync_fn = function(pr_num)
		workflows.sync_pr(pr_num, nil, function(pr_id, err)
			if err then
				log.error("Error syncing PR #" .. pr_num .. ": " .. err .. ". Make sure the current repo is added!")
			elseif pr_id then
				log.info("PR synced: " .. pr_id)
				log.notify("PR synced: " .. pr_id)
			end
		end)
	end
	if not pr_number then
		cmd_utils.prompt_select_pr(function(selected_pr)
			if selected_pr then
				sync_fn(selected_pr.number)
			end
		end)
		return
	else
		sync_fn(pr_number)
	end
	end, { nargs = 1 })

	vim.api.nvim_create_user_command("RevmanEnableBackgroundSync", function()
	local sync = require("revman.sync")
	local log = require("revman.log")
	sync.enable_background_sync()
	log.info("Background sync enabled.")
	log.notify("Background sync enabled.")
	end, {})

	vim.api.nvim_create_user_command("RevmanDisableBackgroundSync", function()
	local sync = require("revman.sync")
	local log = require("revman.log")
	sync.disable_background_sync()
	log.info("Background sync disabled.")
	log.notify("Background sync disabled.")
	end, {})
end

-- Auto-create real commands when this module loads
create_commands()

return M
