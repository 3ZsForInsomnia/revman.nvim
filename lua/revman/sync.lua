local workflows = require("revman.workflows")
local config = require("revman.config")

local M = {}

local sync_timer = nil

-- Perform a sync of all PRs for the current repo
function M.sync_now()
	local res, err = workflows.sync_all_prs()
	if res then
		vim.schedule(function()
			vim.notify("revman.nvim: Synced PRs: " .. vim.inspect(res), vim.log.levels.INFO)
		end)
	else
		vim.schedule(function()
			vim.notify("revman.nvim: Error syncing PRs: " .. (err or "unknown"), vim.log.levels.ERROR)
		end)
	end
end

-- Enable background sync (runs every N minutes as configured)
function M.enable_background_sync()
	M.disable_background_sync() -- Ensure no duplicate timers

	local freq = config.get().background.frequency or 15
	if freq == 0 then
		vim.notify("revman.nvim: Background sync is disabled by config.", vim.log.levels.INFO)
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
	vim.notify("revman.nvim: Background sync enabled (every " .. freq .. " min)", vim.log.levels.INFO)
end

-- Disable background sync
function M.disable_background_sync()
	if sync_timer then
		sync_timer:stop()
		sync_timer:close()
		sync_timer = nil
		vim.notify("revman.nvim: Background sync disabled.", vim.log.levels.INFO)
	end
end

-- Optionally, start background sync on startup if configured
function M.setup_autosync()
	local freq = config.get().background.frequency or 15
	if freq > 0 then
		M.enable_background_sync()
	end
end

return M
