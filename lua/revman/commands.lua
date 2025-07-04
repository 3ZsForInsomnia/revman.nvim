local M = {}
local prs = require("revman.prs")
local db = require("revman.db")
local sync = require("revman.sync")
local telescope = require("revman.telescope")
local config = require("revman.config")

-- Helper function to get PR number from arguments or current Octo buffer
function M.get_pr_number(pr_number, show_error)
	if not pr_number or pr_number == "" then
		-- Try to get PR number from the current buffer if it's an Octo buffer
		local buf_name = vim.api.nvim_buf_get_name(0)
		pr_number = buf_name:match("octo://[^/]*/[^/]*/pull/(%d+)")

		if not pr_number and show_error then
			vim.notify("Please provide a PR number", vim.log.levels.ERROR)
			return nil
		end
	end

	if pr_number then
		-- Convert to number
		return tonumber(pr_number)
	end

	return nil
end

-- Command to add a PR to tracking
function M.add_pr(pr_number)
	pr_number = M.get_pr_number(pr_number, true)
	if not pr_number then
		return
	end

	-- Check if PR exists in GitHub
	local success, err = prs.add_pr(pr_number)

	if success then
		vim.notify("Added PR #" .. pr_number .. " to tracking", vim.log.levels.INFO)
	else
		vim.notify("Failed to add PR #" .. pr_number .. ": " .. (err or "Unknown error"), vim.log.levels.ERROR)
	end
end

-- Command to edit PR notes
function M.edit_pr_notes(pr_number)
	pr_number = M.get_pr_number(pr_number, true)
	if not pr_number then
		return
	end

	-- Get PR from database
	local pr = db.get_pr(pr_number)
	if not pr then
		vim.notify("PR #" .. pr_number .. " not found in tracking database", vim.log.levels.ERROR)
		return
	end

	-- Create notes buffer
	local buf = vim.api.nvim_create_buf(true, false)
	vim.api.nvim_buf_set_name(buf, "PR #" .. pr_number .. " Notes")

	-- Set buffer options
	vim.api.nvim_buf_set_option(buf, "buftype", "acwrite")
	vim.api.nvim_buf_set_option(buf, "filetype", "markdown")

	-- Set content to existing notes
	local notes = pr.notes or ""
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(notes, "\n"))

	-- Create window for the buffer
	vim.cmd("vsplit")
	vim.api.nvim_win_set_buf(0, buf)

	-- Set up autocmd to save notes when buffer is written
	vim.cmd(string.format(
		[[
    augroup RevmanNotes_%s
      autocmd!
      autocmd BufWriteCmd <buffer> lua require('revman.commands').save_notes(%s)
    augroup END
  ]],
		pr_number,
		pr_number
	))

	-- Add PR info at the top of the window in a split
	local info_buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(info_buf, 0, -1, false, {
		"# PR #" .. pr_number .. ": " .. pr.title,
		"",
		"Author: " .. pr.author,
		"Status: " .. (pr.status or "Unknown"),
		"State: " .. pr.state,
		"",
		"-- Press :w to save notes --",
	})
	vim.api.nvim_buf_set_option(info_buf, "modifiable", false)
	vim.api.nvim_buf_set_option(info_buf, "buftype", "nofile")
	vim.api.nvim_buf_set_option(info_buf, "filetype", "markdown")

	-- Create window above notes for PR info
	vim.cmd("aboveleft split")
	vim.api.nvim_win_set_buf(0, info_buf)
	vim.api.nvim_win_set_height(0, 8)
	vim.cmd("wincmd j") -- Go back to notes window
end

-- Save notes for a PR
function M.save_notes(pr_number)
	local buf = vim.api.nvim_get_current_buf()
	local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
	local notes = table.concat(lines, "\n")

	-- Save to database
	local success, err = db.update_pr_notes(pr_number, notes)

	if success then
		vim.notify("Saved notes for PR #" .. pr_number, vim.log.levels.INFO)
		vim.api.nvim_buf_set_option(buf, "modified", false)
	else
		vim.notify("Failed to save notes: " .. (err or "Unknown error"), vim.log.levels.ERROR)
	end
end

-- Command to sync a PR with GitHub
function M.sync_pr(pr_number)
	pr_number = M.get_pr_number(pr_number, true)
	if not pr_number then
		return
	end

	-- Sync PR
	local success = sync.sync_pr(pr_number)

	if success then
		vim.notify("Synced PR #" .. pr_number .. " with GitHub", vim.log.levels.INFO)
	end
end

-- Command to sync all PRs
function M.sync_all_prs()
	sync.sync_all_prs()
end

-- Command to set PR status
function M.set_pr_status(pr_number, status)
	pr_number = M.get_pr_number(pr_number, true)
	if not pr_number then
		return
	end

	-- Validate status
	if not status or not vim.tbl_contains(vim.tbl_values(prs.STATUS), status) then
		-- Show available statuses
		local status_list = {}
		for name, value in pairs(prs.STATUS) do
			table.insert(status_list, name .. " (" .. value .. ")")
		end

		vim.notify("Invalid status. Available statuses:\n" .. table.concat(status_list, "\n"), vim.log.levels.ERROR)
		return
	end

	-- Set status
	local success, err = prs.set_status(pr_number, status)

	if success then
		vim.notify("Set PR #" .. pr_number .. " status to " .. status, vim.log.levels.INFO)
	else
		vim.notify("Failed to set status: " .. (err or "Unknown error"), vim.log.levels.ERROR)
	end
end

-- Command to toggle background sync
function M.toggle_background_sync()
	local options = config.get()

	if options.background.frequency > 0 then
		if sync.is_background_sync_running() then
			sync.stop_background_sync()
			vim.notify("Stopped background sync", vim.log.levels.INFO)
		else
			sync.start_background_sync()
			vim.notify("Started background sync", vim.log.levels.INFO)
		end
	else
		vim.notify("Background sync is disabled in config (frequency=0)", vim.log.levels.WARN)
	end
end

-- Command to show a PR in Octo
function M.open_pr(pr_number)
	pr_number = M.get_pr_number(pr_number, true)
	if not pr_number then
		return
	end

	-- Update last viewed time
	db.update_pr_opened_time(pr_number)

	-- Open in Octo
	vim.cmd("Octo pr edit " .. pr_number)
end

-- Command to get PR status
function M.get_pr_status(pr_number)
	pr_number = M.get_pr_number(pr_number, true)
	if not pr_number then
		return
	end

	-- Get status
	local status, err = prs.get_status(pr_number)

	if status then
		vim.notify("PR #" .. pr_number .. " status: " .. status, vim.log.levels.INFO)
	else
		vim.notify("Failed to get status: " .. (err or "Unknown error"), vim.log.levels.ERROR)
	end
end

-- Function to expose telescope pickers
function M.list_prs(filter)
	if filter == "open" then
		telescope.list_open_prs()
	elseif filter == "merged" then
		telescope.list_merged_prs()
	elseif filter == "updates" then
		telescope.list_updated_prs()
	else
		telescope.list_all_prs()
	end
end

-- Helper function to expose these commands to Neovim
function M.setup_commands()
	-- Register user commands
	vim.api.nvim_create_user_command("RevmanAddPR", function(opts)
		M.add_pr(opts.args)
	end, {
		nargs = "?",
		desc = "Add a PR to tracking",
	})

	vim.api.nvim_create_user_command("RevmanEditNotes", function(opts)
		M.edit_pr_notes(opts.args)
	end, {
		nargs = "?",
		desc = "Edit notes for a PR",
	})

	vim.api.nvim_create_user_command("RevmanSyncPR", function(opts)
		M.sync_pr(opts.args)
	end, {
		nargs = "?",
		desc = "Sync a PR with GitHub",
	})

	vim.api.nvim_create_user_command("RevmanSyncAll", function()
		M.sync_all_prs()
	end, {
		desc = "Sync all PRs with GitHub",
	})

	vim.api.nvim_create_user_command("RevmanSetStatus", function(opts)
		local args = vim.split(opts.args, " ")
		M.set_pr_status(args[1], args[2])
	end, {
		nargs = "+",
		desc = "Set PR status (pr_number status)",
		complete = function(ArgLead, CmdLine, CursorPos)
			-- Provide completion for status values
			local args = vim.split(CmdLine, " ")
			if #args > 2 then
				return vim.tbl_keys(prs.STATUS)
			end
			return {}
		end,
	})

	vim.api.nvim_create_user_command("RevmanToggleSync", function()
		M.toggle_background_sync()
	end, {
		desc = "Toggle background sync",
	})

	vim.api.nvim_create_user_command("RevmanOpenPR", function(opts)
		M.open_pr(opts.args)
	end, {
		nargs = 1,
		desc = "Open a PR in Octo",
	})

	vim.api.nvim_create_user_command("RevmanStatus", function(opts)
		M.get_pr_status(opts.args)
	end, {
		nargs = "?",
		desc = "Get PR status",
	})

	-- List commands
	vim.api.nvim_create_user_command("RevmanListPRs", function()
		M.list_prs()
	end, {
		desc = "List all tracked PRs",
	})

	vim.api.nvim_create_user_command("RevmanListOpenPRs", function()
		M.list_prs("open")
	end, {
		desc = "List open PRs",
	})

	vim.api.nvim_create_user_command("RevmanListMergedPRs", function()
		M.list_prs("merged")
	end, {
		desc = "List merged PRs",
	})

	vim.api.nvim_create_user_command("RevmanListUpdatedPRs", function()
		M.list_prs("updates")
	end, {
		desc = "List PRs with new activity",
	})
end

return M
