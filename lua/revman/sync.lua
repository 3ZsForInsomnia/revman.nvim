local M = {}
local config = require("revman.config")
local db = require("revman.db")
local github = require("revman.github")
local ci = require("revman.ci")
local prs = require("revman.prs")

local sync_timer = nil

-- Sync a single PR
function M.sync_pr(pr_number)
	-- Get PR details from GitHub
	local pr_details, err = github.get_pr_details(pr_number)
	if not pr_details then
		vim.notify("Failed to sync PR #" .. pr_number .. ": " .. (err or "Unknown error"), vim.log.levels.ERROR)
		return false
	end

	-- Get activity info
	local activity = github.get_pr_activity(pr_number)

	-- Get CI status
	local ci_status = ci.get_ci_status(pr_number)

	-- Update in database
	local success, db_err = db.update_pr(pr_number, pr_details, activity, ci_status)
	if not success then
		vim.notify("Failed to update PR in database: " .. (db_err or "Unknown error"), vim.log.levels.ERROR)
		return false
	end

	-- Auto-update status if needed
	prs.auto_update_status(pr_number)

	return true
end

-- Sync all PRs
function M.sync_all_prs(silent)
	silent = silent or false
	local pr_numbers = db.get_all_pr_numbers()
	local success_count = 0
	local error_count = 0

	for _, pr_number in ipairs(pr_numbers) do
		local ok = pcall(M.sync_pr, pr_number)
		if ok then
			success_count = success_count + 1
		else
			error_count = error_count + 1
		end
	end

	if not silent then
		vim.notify(string.format("Synced %d PRs. %d errors.", success_count, error_count), vim.log.levels.INFO)
	end

	-- Clean up old PRs based on retention policy
	db.cleanup_old_prs()

	return success_count > 0
end

-- Start background sync
function M.start_background_sync()
	if sync_timer then
		return -- Already running
	end

	local options = config.get()
	local frequency_ms = options.background.frequency * 60 * 1000 -- Convert minutes to ms

	-- If frequency is 0, don't start background sync
	if frequency_ms <= 0 then
		return
	end

	-- Create timer for background sync
	sync_timer = vim.loop.new_timer()

	-- Run immediately once, then on the interval
	sync_timer:start(
		0,
		frequency_ms,
		vim.schedule_wrap(function()
			M.sync_all_prs(true) -- Silent sync
		end)
	)

	vim.notify("Started background sync every " .. options.background.frequency .. " minutes", vim.log.levels.INFO)
end

-- Stop background sync
function M.stop_background_sync()
	if sync_timer then
		sync_timer:stop()
		sync_timer:close()
		sync_timer = nil
		vim.notify("Stopped background sync", vim.log.levels.INFO)
	end
end

-- Setup function
function M.setup()
	-- Check if background sync should be enabled
	local options = config.get()
	if options.background.frequency > 0 then
		M.start_background_sync()
	end
end

return M
