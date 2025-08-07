local workflows = require("revman.workflows")
local utils = require("revman.utils")
local config = require("revman.config")
local log = require("revman.log")

local M = {}

local sync_timer = nil

-- Perform a sync of all PRs for the current repo
function M.sync_now()
	local repo_name = utils.get_current_repo()
	if not repo_name then
		M.disable_background_sync() -- Stop any existing timer
		log.info("Not in a GitHub repository, skipping sync.")
		return
	end

	workflows.sync_all_prs(repo_name, false, function(success)
		if not success then
			log.error("Some PRs failed to sync.")
		end
	end)
end

function M.enable_background_sync()
	M.disable_background_sync() -- Ensure no duplicate timers

	local freq = config.get().background.frequency or 15
	if freq == 0 then
		log.info("Background sync is disabled by config.")
		return
	end

	sync_timer = vim.loop.new_timer()
	sync_timer:start(
		0, -- initial delay (ms)
		freq * 60 * 1000, -- repeat interval (ms)
		vim.schedule_wrap(function()
			M.sync_now()
		end)
	)
	log.notify("Background sync enabled (every " .. freq .. " min)")
end

function M.disable_background_sync()
	if sync_timer then
		sync_timer:stop()
		sync_timer:close()
		sync_timer = nil
		log.notify("Background sync disabled.")
	end
end

function M.setup_autosync()
	local repo_name = utils.get_current_repo()
	if not repo_name then
		M.disable_background_sync()
		log.info("Not in a GitHub repository, skipping sync.")
		return
	end

	local freq = config.get().background.frequency or 15
	if freq > 0 then
		M.enable_background_sync()
	end
end

return M
