local pickers = require("telescope.pickers")
local previewers = require("telescope.previewers")
local finders = require("telescope.finders")
local conf = require("telescope.config").values
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")
local ci = require("revman.github.ci")
local cmd_utils = require("revman.command-utils")
local db_status = require("revman.db.status")
local pr_status = require("revman.db.pr_status")
local log = require("revman.log")

local M = {}

local function open_in_browser(pr)
	if pr and pr.url then
		local cmd
		if vim.fn.has("mac") == 1 then
			cmd = { "open", pr.url }
		elseif vim.fn.has("unix") == 1 then
			cmd = { "xdg-open", pr.url }
		elseif vim.fn.has("win32") == 1 then
			cmd = { "start", pr.url }
		end
		if cmd then
			vim.fn.jobstart(cmd, { detach = true })
		end
	end
end

local function pr_previewer(self, entry, status)
	if not entry or not entry.value then
		vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, { "No PR selected." })
		return
	end
	local pr = entry.value
	local ci_status = pr.ci_status or "unknown"
	local ci_icon = ci.get_status_icon({ status = ci_status })

	local lines = {
		string.format("PR #%s: %s", pr.number, pr.title),
		string.format("Author: %s", pr.author or "unknown"),
		string.format("State: %s", pr.state),
		"",
		string.format("Review Status: %s", pr.review_status or "N/A"),
		string.format("CI Status: %s %s", ci_icon, ci_status),
		"",
		string.format("Created: %s", pr.created_at),
		string.format("Last Activity: %s", pr.last_activity or "Unknown"),
		string.format("Comment Count: %s", pr.comment_count or "0"),
		"",
		string.format("URL: %s", pr.url),
	}
	vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)

	-- Add highlights for better readability
	vim.api.nvim_buf_add_highlight(self.state.bufnr, -1, "Title", 0, 0, -1)
	vim.api.nvim_buf_add_highlight(self.state.bufnr, -1, "Identifier", 1, 0, -1)
	vim.api.nvim_buf_add_highlight(self.state.bufnr, -1, "Comment", 2, 0, -1)
	vim.api.nvim_buf_add_highlight(self.state.bufnr, -1, "Special", 4, 0, -1)
	vim.api.nvim_buf_add_highlight(self.state.bufnr, -1, "WarningMsg", 5, 0, -1)
end

local function make_picker(prs, opts, title, on_select)
	opts = opts or {}
	pickers
		.new(opts, {
			prompt_title = title,
			finder = finders.new_table({
				results = prs,
				entry_maker = function(pr)
					return {
						value = pr,
						display = cmd_utils.format_pr_entry(pr),
						ordinal = cmd_utils.format_pr_entry(pr),
					}
				end,
			}),
			sorter = conf.generic_sorter(opts),
			previewer = previewers.new_buffer_previewer({
				define_preview = pr_previewer,
			}),
			attach_mappings = function(prompt_bufnr, map)
				local select_fn = function()
					local entry = action_state.get_selected_entry()
					if entry and entry.value then
						actions.close(prompt_bufnr)
						if on_select then
							on_select(entry.value)
						end
					end
				end

				map("i", "<CR>", select_fn)
				map("n", "<CR>", select_fn)
				map("n", "<C-b>", function()
					local entry = action_state.get_selected_entry()
					if entry and entry.value then
						open_in_browser(entry.value)
					end
				end)
				map("n", "<C-s>", function()
					local entry = action_state.get_selected_entry()
					if entry and entry.value then
						local pr = entry.value
						local statuses = {}
						for _, s in ipairs(db_status.list()) do
							table.insert(statuses, s.name)
						end
						vim.ui.select(statuses, { prompt = "Set PR Status" }, function(selected_status)
							if selected_status then
								pr_status.set_review_status(pr.id, selected_status)
								log.info("PR #" .. pr.number .. " status updated to: " .. selected_status)
							end
						end)
					end
				end)
				return true
			end,
		})
		:find()
end

function M.pick_prs(prs, opts, title, on_select)
	make_picker(prs, opts, title or "PRs", on_select)
end

return M
