local entry_utils = require("revman.picker.entry")

local M = {}

-- Check if telescope is available and configured
local function should_use_telescope()
	local config = require("revman.config")
	local picker_config = config.get().picker or {}
	
	-- Only use telescope if explicitly configured
	if picker_config.backend ~= "telescope" then
		return false
	end
	
	local ok, _ = pcall(require, "telescope")
	if not ok then
		local log = require("revman.log")
		log.warn("Picker backend set to 'telescope' but telescope.nvim is not available. Falling back to vimSelect.")
		return false
	end
	
	return true
end

-- Enhanced vim.ui.select with better search capabilities
local function enhanced_select(items, opts, on_choice)
	-- Create searchable entries
	local entries = {}
	local entry_map = {}
	
	for i, item in ipairs(items) do
		local display, searchable
		
		if opts.entry_maker then
			local entry = opts.entry_maker(item)
			display = entry.display
			searchable = entry.ordinal
		else
			display = tostring(item)
			searchable = display
		end
		
		table.insert(entries, display)
		entry_map[display] = item
	end
	
	-- Use vim.ui.select with enhanced prompt
	local select_opts = {
		prompt = opts.prompt or "Select item",
		format_item = function(item)
			return item
		end,
	}
	
	vim.ui.select(entries, select_opts, function(choice)
		if choice and on_choice then
			on_choice(entry_map[choice])
		end
	end)
end

-- Telescope picker wrapper
local function telescope_pick(items, opts, on_choice)
	local pickers = require("telescope.pickers")
	local finders = require("telescope.finders")
	local conf = require("telescope.config").values
	local actions = require("telescope.actions")
	local action_state = require("telescope.actions.state")
	
	local picker_opts = vim.tbl_extend("force", {
		prompt_title = opts.prompt or "Select item",
		finder = finders.new_table({
			results = items,
			entry_maker = opts.entry_maker or function(item)
				return {
					value = item,
					display = tostring(item),
					ordinal = tostring(item),
				}
			end,
		}),
		sorter = conf.generic_sorter(opts),
		attach_mappings = function(prompt_bufnr, map)
			local select_fn = function()
				local entry = action_state.get_selected_entry()
				if entry and entry.value then
					actions.close(prompt_bufnr)
					if on_choice then
						on_choice(entry.value)
					end
				end
			end

			map("i", "<CR>", select_fn)
			map("n", "<CR>", select_fn)
			
			-- Add custom mappings if provided
			if opts.attach_mappings then
				opts.attach_mappings(prompt_bufnr, map)
			end
			
			return true
		end,
	}, opts.telescope_opts or {})
	
	-- Add previewer if provided
	if opts.previewer then
		picker_opts.previewer = opts.previewer
	end
	
	pickers.new(picker_opts.telescope_opts or {}, picker_opts):find()
end

-- Main picker function that chooses between telescope and vim.ui.select
function M.pick(items, opts, on_choice)
	opts = opts or {}
	
	-- Force telescope if explicitly requested, otherwise use config
	local use_telescope = opts.force_telescope or (should_use_telescope() and not opts.force_vim_select)
	
	if use_telescope then
		telescope_pick(items, opts, on_choice)
	else
		enhanced_select(items, opts, on_choice)
	end
end

-- Specialized picker functions

function M.pick_prs(prs, opts, on_choice)
	opts = opts or {}
	opts.prompt = opts.prompt or "Select PR"
	opts.entry_maker = function(pr)
		return {
			value = pr,
			display = entry_utils.pr_display(pr),
			ordinal = entry_utils.pr_searchable(pr),
		}
	end
	
	-- Add PR-specific telescope options
	local use_telescope = opts.force_telescope or should_use_telescope()
	if use_telescope then
		local previewers = require("telescope.previewers")
		local ci = require("revman.github.ci")
		
		opts.previewer = previewers.new_buffer_previewer({
			define_preview = function(self, entry, status)
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

				-- Add highlights for better readability using extmarks
				local ns_id = vim.api.nvim_create_namespace("revman_pr_preview")
				vim.api.nvim_buf_set_extmark(self.state.bufnr, ns_id, 0, 0, { 
					end_line = 0, 
					hl_group = "Title" 
				})
				vim.api.nvim_buf_set_extmark(self.state.bufnr, ns_id, 1, 0, { 
					end_line = 1, 
					hl_group = "Identifier" 
				})
				vim.api.nvim_buf_set_extmark(self.state.bufnr, ns_id, 2, 0, { 
					end_line = 2, 
					hl_group = "Comment" 
				})
				vim.api.nvim_buf_set_extmark(self.state.bufnr, ns_id, 4, 0, { 
					end_line = 4, 
					hl_group = "Special" 
				})
				vim.api.nvim_buf_set_extmark(self.state.bufnr, ns_id, 5, 0, { 
					end_line = 5, 
					hl_group = "WarningMsg" 
				})
			end,
		})
		
		-- Add PR-specific keymaps
		opts.attach_mappings = function(prompt_bufnr, map)
			local actions = require("telescope.actions")
			local action_state = require("telescope.actions.state")
			local db_status = require("revman.db.status") 
			local pr_status = require("revman.db.pr_status")
			local log = require("revman.log")
			
			-- Open in browser
			map("n", "<C-b>", function()
				local entry = action_state.get_selected_entry()
				if entry and entry.value and entry.value.url then
					local pr = entry.value
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
			end)
			
			-- Set status
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
		end
	end
	
	M.pick(prs, opts, on_choice)
end

function M.pick_authors(authors, opts, on_choice)
	opts = opts or {}
	opts.prompt = opts.prompt or "Select Author"
	opts.entry_maker = function(author)
		return {
			value = author,
			display = entry_utils.author_display(author),
			ordinal = entry_utils.author_searchable(author),
		}
	end
	
	-- Add author-specific telescope preview
	local use_telescope = opts.force_telescope or should_use_telescope()
	if use_telescope then
		local previewers = require("telescope.previewers")
		local utils = require("revman.utils")
		
		opts.previewer = previewers.new_buffer_previewer({
			define_preview = function(self, entry, _)
				local stats = entry.value
				local lines = {
					"User: " .. (stats.author or "unknown"),
					"",
					"PRs opened: " .. (stats.prs_opened or 0),
					"PRs merged: " .. (stats.prs_merged or 0),
					"PRs closed w/o merge: " .. (stats.prs_closed_without_merge or 0),
					"",
					string.format("PRs opened/week (avg): %.2f", stats.prs_opened_per_week_avg or 0),
					string.format("PRs merged/week (avg): %.2f", stats.prs_merged_per_week_avg or 0),
					"",
					"Comments written: " .. (stats.comments_written or 0),
					"  On own PRs: " .. (stats.comments_on_own_prs or 0),
					"  On others' PRs: " .. (stats.comments_on_others_prs or 0),
					"Comments received: " .. (stats.comments_received or 0),
					"",
					"Avg time to first comment: " .. (stats.avg_time_to_first_comment_human or "N/A"),
					string.format("Avg review cycles (heuristic): %.2f", stats.avg_review_cycles or 0),
				}
				vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
				
				-- Add highlights for better readability using extmarks
				local ns_id = vim.api.nvim_create_namespace("revman_author_preview")
				vim.api.nvim_buf_set_extmark(self.state.bufnr, ns_id, 0, 0, { 
					end_line = 0, 
					hl_group = "Title" 
				})
				vim.api.nvim_buf_set_extmark(self.state.bufnr, ns_id, 2, 0, { 
					end_line = 2, 
					hl_group = "Identifier" 
				})
				vim.api.nvim_buf_set_extmark(self.state.bufnr, ns_id, 3, 0, { 
					end_line = 3, 
					hl_group = "Identifier" 
				})
				vim.api.nvim_buf_set_extmark(self.state.bufnr, ns_id, 4, 0, { 
					end_line = 4, 
					hl_group = "WarningMsg" 
				})
			end,
		})
	end
	
	M.pick(authors, opts, on_choice)
end

function M.pick_repos(repos, opts, on_choice)
	opts = opts or {}
	opts.prompt = opts.prompt or "Select Repository"
	opts.entry_maker = function(repo)
		return {
			value = repo,
			display = entry_utils.repo_display(repo),
			ordinal = entry_utils.repo_searchable(repo),
		}
	end
	
	M.pick(repos, opts, on_choice)
end

function M.pick_notes(prs_with_notes, opts, on_choice) 
	opts = opts or {}
	opts.prompt = opts.prompt or "Select PR Note"
	opts.entry_maker = function(pr)
		return {
			value = pr,
			display = entry_utils.note_display(pr),
			ordinal = entry_utils.note_searchable(pr),
		}
	end
	
	-- Add note-specific telescope preview
	local use_telescope = opts.force_telescope or should_use_telescope()
	if use_telescope then
		local previewers = require("telescope.previewers")
		local db_notes = require("revman.db.notes")
		
		opts.previewer = previewers.new_buffer_previewer({
			define_preview = function(self, entry)
				local pr = entry.value
				local note = db_notes.get_by_pr_id(pr.id)
				local lines = note and vim.split(note.content or "", "\n") or { "No note found." }
				vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
				vim.bo[self.state.bufnr].filetype = "markdown"
			end,
		})
	end
	
	M.pick(prs_with_notes, opts, on_choice)
end

return M