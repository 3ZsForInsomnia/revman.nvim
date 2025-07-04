local M = {}
local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local conf = require("telescope.config").values
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")
local previewers = require("telescope.previewers")
local entry_display = require("telescope.pickers.entry_display")
local db = require("revman.db")
local ci = require("revman.ci")

-- Format the PR preview content
local function format_pr_preview(pr)
	local lines = {}

	-- Title and basic info
	table.insert(lines, "# PR #" .. pr.number .. ": " .. pr.title)
	table.insert(lines, "")

	-- Status line with icons
	local state_icon = pr.state == "OPEN" and "🟢" or (pr.state == "MERGED" and "🟣" or "🔴")
	local draft_status = pr.is_draft == 1 and " 📝 DRAFT" or ""
	local review_status = ""
	if pr.review_decision == "APPROVED" then
		review_status = " ✅ APPROVED"
	elseif pr.review_decision == "CHANGES_REQUESTED" then
		review_status = " ❌ CHANGES REQUESTED"
	elseif pr.review_decision == "REVIEW_REQUIRED" then
		review_status = " ⏳ REVIEW REQUIRED"
	end

	table.insert(lines, state_icon .. " " .. pr.state .. draft_status .. review_status)
	table.insert(lines, "")

	-- Author and creation date
	table.insert(lines, "**Author:** " .. pr.author)
	table.insert(lines, "**Created:** " .. pr.created_at:gsub("T", " "):gsub("Z", " UTC"))

	-- CI Status if available
	if pr.ci_status then
		table.insert(lines, "")
		table.insert(lines, "## CI Status: " .. ci.get_status_icon(pr.ci_status) .. " " .. pr.ci_status.status)
		table.insert(
			lines,
			string.format(
				"Passing: %d | Failing: %d | Pending: %d",
				pr.ci_status.passing,
				pr.ci_status.failing,
				pr.ci_status.pending
			)
		)

		if pr.ci_status.checks and #pr.ci_status.checks > 0 then
			table.insert(lines, "")
			table.insert(lines, "### Checks")
			for _, check in ipairs(pr.ci_status.checks) do
				local check_icon = check.state == "SUCCESS" and "✅" or (check.state == "FAILURE" and "❌" or "⏳")
				table.insert(lines, check_icon .. " " .. check.name)
			end
		end
	end

	-- Activity info
	table.insert(lines, "")
	table.insert(lines, "## Activity")
	table.insert(lines, "Last synced: " .. (pr.last_synced or "Never"):gsub("T", " "):gsub("Z", " UTC"))
	table.insert(lines, "Last activity: " .. (pr.last_activity or "Never"):gsub("T", " "):gsub("Z", " UTC"))
	table.insert(lines, "Last viewed: " .. (pr.last_viewed or "Never"):gsub("T", " "):gsub("Z", " UTC"))

	if pr.last_viewed and pr.last_activity and pr.last_activity > pr.last_viewed then
		table.insert(lines, "")
		table.insert(lines, "⚠️ **New activity since last viewed!**")
	end

	-- Notes section
	if pr.notes and pr.notes ~= "" then
		table.insert(lines, "")
		table.insert(lines, "## Personal Notes")
		table.insert(lines, "")

		-- Split notes by newline and add to preview
		for _, line in ipairs(vim.split(pr.notes, "\n")) do
			table.insert(lines, line)
		end
	end

	-- URL at the bottom
	table.insert(lines, "")
	table.insert(lines, "URL: " .. pr.url)

	return lines
end

-- Custom PR previewer
local pr_previewer = previewers.new_buffer_previewer({
	title = "Pull Request Preview",
	define_preview = function(self, entry, status)
		local pr = entry.value
		local bufnr = self.state.bufnr

		-- Format the preview content
		local content = format_pr_preview(pr)

		-- Set lines in preview buffer
		vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, content)

		-- Set buffer options for the preview
		vim.api.nvim_buf_set_option(bufnr, "filetype", "markdown")
		vim.api.nvim_buf_set_option(bufnr, "bufhidden", "wipe")
	end,
})

-- Make a fancy display for PR entries
local function make_display(entry)
	local displayer = entry_display.create({
		separator = " ",
		items = {
			{ width = 6 }, -- PR number
			{ width = 2 }, -- CI status icon
			{ width = 2 }, -- State icon
			{ width = 2 }, -- New activity icon
			{ remaining = true }, -- Title
		},
	})

	local pr = entry.value

	-- Get icons
	local ci_icon = ci.get_status_icon(pr.ci_status)

	local state_icon = pr.state == "OPEN" and "🟢" or (pr.state == "MERGED" and "🟣" or "🔴")

	local new_activity = ""
	if pr.last_viewed and pr.last_activity and pr.last_activity > pr.last_viewed then
		new_activity = "🔔"
	end

	return displayer({
		{ "#" .. pr.number, "TelescopeResultsNumber" },
		{ ci_icon },
		{ state_icon },
		{ new_activity },
		pr.title,
	})
end

-- Generic PR picker function
local function pr_picker(opts, filter_type)
	opts = opts or {}

	-- Get PRs with the specified filter
	local prs, err = db.get_prs({ filter = filter_type })
	if err then
		vim.notify("Failed to get PRs: " .. err, vim.log.levels.ERROR)
		return
	end

	-- Create picker with our custom formatting
	pickers
		.new(opts, {
			prompt_title = "Pull Requests" .. (filter_type and (" - " .. filter_type:upper()) or ""),
			finder = finders.new_table({
				results = prs,
				entry_maker = function(pr)
					return {
						value = pr,
						display = make_display,
						ordinal = pr.number .. " " .. pr.title .. " " .. pr.state .. " " .. pr.author,
					}
				end,
			}),
			sorter = conf.generic_sorter(opts),
			previewer = pr_previewer,
			attach_mappings = function(prompt_bufnr)
				-- Open PR in Octo when selected
				actions.select_default:replace(function()
					local selection = action_state.get_selected_entry()
					actions.close(prompt_bufnr)

					-- Update last viewed time and open in Octo
					local pr_number = selection.value.number
					db.update_pr_opened_time(pr_number)
					vim.cmd("Octo pr edit " .. pr_number)
				end)

				-- Add custom key bindings
				-- Edit notes with <C-e>
				vim.api.nvim_buf_set_keymap(
					prompt_bufnr,
					"n",
					"<C-e>",
					[[<cmd>lua require('revman.commands').edit_pr_notes(require('telescope.actions.state').get_selected_entry().value.number)<CR>]],
					{ noremap = true, silent = true }
				)
				vim.api.nvim_buf_set_keymap(
					prompt_bufnr,
					"i",
					"<C-e>",
					[[<cmd>lua require('revman.commands').edit_pr_notes(require('telescope.actions.state').get_selected_entry().value.number)<CR>]],
					{ noremap = true, silent = true }
				)

				-- Sync PR with <C-s>
				vim.api.nvim_buf_set_keymap(
					prompt_bufnr,
					"n",
					"<C-s>",
					[[<cmd>lua require('revman.commands').sync_pr(require('telescope.actions.state').get_selected_entry().value.number)<CR>]],
					{ noremap = true, silent = true }
				)
				vim.api.nvim_buf_set_keymap(
					prompt_bufnr,
					"i",
					"<C-s>",
					[[<cmd>lua require('revman.commands').sync_pr(require('telescope.actions.state').get_selected_entry().value.number)<CR>]],
					{ noremap = true, silent = true }
				)

				return true
			end,
		})
		:find()
end

-- Show all PRs
function M.list_all_prs(opts)
	pr_picker(opts)
end

-- Show open PRs
function M.list_open_prs(opts)
	pr_picker(opts, "open")
end

-- Show merged PRs
function M.list_merged_prs(opts)
	pr_picker(opts, "merged")
end

-- Show PRs with new activity
function M.list_updated_prs(opts)
	pr_picker(opts, "updates")
end

-- Setup function to register the extension with telescope
function M.setup()
	require("telescope").register_extension({
		exports = {
			revman = M.list_all_prs,
			revman_open = M.list_open_prs,
			revman_merged = M.list_merged_prs,
			revman_updates = M.list_updated_prs,
		},
	})
end

return M
