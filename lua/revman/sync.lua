local workflows = require("revman.workflows")
local utils = require("revman.utils")
local config = require("revman.config")
local log = require("revman.log")

local M = {}

local sync_timer = nil
local consecutive_failures = 0
local MAX_CONSECUTIVE_FAILURES = 3

-- Perform a sync of all PRs for the current repo
function M.sync_now()
	-- Only sync if we are in a GitHub repository
	local repo_name = utils.get_current_repo()
	if not repo_name then
		M.disable_background_sync() -- Stop any existing timer
		log.info("Not in a GitHub repository, skipping sync.")
		return
	end

	-- Only sync if the repo is in the database/has been added
	local repo_row = utils.ensure_repo(repo_name)
	if not repo_row then
		M.disable_background_sync()
		log.error(
			"Current repository '"
				.. repo_name
				.. "' is not in the database. Please add it with :RevmanAddRepo. Background sync disabled."
		)
		return
	end

	workflows.sync_all_prs(repo_name, false, function(success)
		if not success then
			consecutive_failures = consecutive_failures + 1

			log.error("PR sync failed (attempt " .. consecutive_failures .. "/" .. MAX_CONSECUTIVE_FAILURES .. ")")

			if consecutive_failures >= MAX_CONSECUTIVE_FAILURES then
				M.disable_background_sync()
				log.error(
					"Background sync disabled after "
						.. MAX_CONSECUTIVE_FAILURES
						.. " consecutive failures. Re-enable manually with :RevmanEnableBackgroundSync"
				)
			end

			log.error("Some PRs failed to sync.")
		else
			consecutive_failures = 0
		end
	end)
end

function M.enable_background_sync()
	M.disable_background_sync() -- Ensure no duplicate timers

	local freq = config.get().background_sync_frequency or 15
	if freq == 0 then
		log.info("Background sync is disabled by config.")
		return
	end

	local repo_name = utils.get_current_repo()
	if not repo_name then
		log.warn("Not in a GitHub repository, cannot enable background sync.")
		return
	end

	local repo_row = utils.ensure_repo(repo_name)
	if not repo_row then
		log.error(
			"Current repository '"
				.. repo_name
				.. "' is not in the database. Please add it with :RevmanAddRepo before enabling background sync."
		)
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
	end
end

function M.setup_autosync()
	local repo_name = utils.get_current_repo()
	if not repo_name then
		M.disable_background_sync()
		log.info("Not in a GitHub repository, skipping sync.")
		return
	end

	local repo_row = utils.ensure_repo(repo_name)
	if not repo_row then
		log.warn(
			"Current repository '"
				.. repo_name
				.. "' is not in the database. Background sync will not be enabled. Add the repo with :RevmanAddRepo"
		)
		return
	end

	local freq = config.get().background_sync_frequency or 15
	if freq > 0 then
		M.enable_background_sync()
	end
end

return M
