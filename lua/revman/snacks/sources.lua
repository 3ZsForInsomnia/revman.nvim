-- Snacks picker sources registration for revman.nvim
-- This registers revman sources with snacks picker globally

local M = {}

-- Register revman sources with snacks picker
local function register_sources()
	local ok, snacks = pcall(require, "snacks")
	if not ok or not snacks.picker then
		return false
	end
	
	local snacks_revman = require("revman.snacks")
	local entry_utils = require("revman.picker.entry")
	
	-- Register PR source
	snacks.picker.sources.revman_prs = {
		finder = function(picker)
			local pr_lists = require("revman.db.pr_lists")
			local prs = pr_lists.list_with_status()
			local items = {}
			
			for _, pr in ipairs(prs) do
				table.insert(items, vim.tbl_extend("force", pr, {
					text = entry_utils.pr_searchable(pr)
				}))
			end
			
			return items
		end,
		format = function(item, picker)
			local pr = item
			local status_icon = ""
			if pr.state == "MERGED" then
				status_icon = "✓ "
			elseif pr.state == "CLOSED" then
				status_icon = "✗ "
			elseif pr.is_draft and pr.is_draft == 1 then
				status_icon = "📝 "
			end
			
			local review_status = pr.review_status and (" [" .. pr.review_status .. "]") or ""
			
			return {
				{ string.format("%s#%s", status_icon, pr.number), "Number" },
				{ " " },
				{ pr.title or "No title", "Title" },
				{ review_status, "Comment" },
				{ " (" },
				{ pr.author or "unknown", "Identifier" },
				{ ")" },
			}
		end,
		preview = function(ctx)
			local pr = ctx.item
			if not pr then
				return false
			end
			
			-- Make buffer modifiable
			vim.bo[ctx.buf].modifiable = true
			
			local ci = require("revman.github.ci")
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
			
			vim.api.nvim_buf_set_lines(ctx.buf, 0, -1, false, lines)
			
			-- Make buffer non-modifiable after setting content
			vim.bo[ctx.buf].modifiable = false
			
			-- Add highlights
			local ns_id = vim.api.nvim_create_namespace("revman_pr_preview")
			vim.api.nvim_buf_set_extmark(ctx.buf, ns_id, 0, 0, { 
				end_line = 0, 
				hl_group = "Title" 
			})
			vim.api.nvim_buf_set_extmark(ctx.buf, ns_id, 1, 0, { 
				end_line = 1, 
				hl_group = "Identifier" 
			})
			vim.api.nvim_buf_set_extmark(ctx.buf, ns_id, 2, 0, { 
				end_line = 2, 
				hl_group = "Comment" 
			})
			vim.api.nvim_buf_set_extmark(ctx.buf, ns_id, 4, 0, { 
				end_line = 4, 
				hl_group = "Special" 
			})
			vim.api.nvim_buf_set_extmark(ctx.buf, ns_id, 5, 0, { 
				end_line = 5, 
				hl_group = "WarningMsg" 
			})
			
			return true
		end,
		confirm = function(picker, item)
			picker:close()
			if item then
				local cmd_utils = require("revman.command-utils")
				cmd_utils.default_pr_select_callback(item)
			end
		end,
		actions = {
			open_browser = function(picker, item)
				if item and item.url then
					local cmd
					if vim.fn.has("mac") == 1 then
						cmd = { "open", item.url }
					elseif vim.fn.has("unix") == 1 then
						cmd = { "xdg-open", item.url }
					elseif vim.fn.has("win32") == 1 then
						cmd = { "start", item.url }
					end
					if cmd then
						vim.fn.jobstart(cmd, { detach = true })
					end
				end
			end,
			set_status = function(picker, item)
				if item then
					local db_status = require("revman.db.status")
					local pr_status = require("revman.db.pr_status")
					local log = require("revman.log")
					local statuses = {}
					for _, s in ipairs(db_status.list()) do
						table.insert(statuses, s.name)
					end
					vim.ui.select(statuses, { prompt = "Set PR Status" }, function(selected_status)
						if selected_status then
							pr_status.set_review_status(item.id, selected_status)
							log.info("PR #" .. item.number .. " status updated to: " .. selected_status)
						end
					end)
				end
			end,
		},
		win = {
			input = {
				keys = {
					["<C-b>"] = { "open_browser", mode = { "n", "i" } },
					["<C-s>"] = { "set_status", mode = { "n", "i" } },
				},
			},
		},
	}
	
	-- Register authors source
	snacks.picker.sources.revman_authors = {
		finder = function(picker)
			local author_analytics = require("revman.analytics.authors")
			local author_stats = author_analytics.get_author_analytics()
			local authors = {}
			
			for author, stats in pairs(author_stats) do
				stats.author = author -- ensure author field is present for display
				table.insert(authors, vim.tbl_extend("force", stats, {
					text = entry_utils.author_searchable(stats)
				}))
			end
			
			return authors
		end,
		format = function(item, picker)
			local author_stats = item
			local opened = author_stats.prs_opened or 0
			local merged = author_stats.prs_merged or 0
			local comments = author_stats.comments_written or 0
			
			return {
				{ author_stats.author or "unknown", "Identifier" },
				{ string.format(" (%d PRs, %d merged, %d comments)", opened, merged, comments), "Comment" },
			}
		end,
		preview = function(ctx)
			local stats = ctx.item
			if not stats then
				return false
			end
			
			-- Make buffer modifiable
			vim.bo[ctx.buf].modifiable = true
			
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
			
			vim.api.nvim_buf_set_lines(ctx.buf, 0, -1, false, lines)
			
			-- Make buffer non-modifiable after setting content
			vim.bo[ctx.buf].modifiable = false
			
			-- Add highlights
			local ns_id = vim.api.nvim_create_namespace("revman_author_preview")
			vim.api.nvim_buf_set_extmark(ctx.buf, ns_id, 0, 0, { 
				end_line = 0, 
				hl_group = "Title" 
			})
			vim.api.nvim_buf_set_extmark(ctx.buf, ns_id, 2, 0, { 
				end_line = 2, 
				hl_group = "Identifier" 
			})
			vim.api.nvim_buf_set_extmark(ctx.buf, ns_id, 3, 0, { 
				end_line = 3, 
				hl_group = "Identifier" 
			})
			vim.api.nvim_buf_set_extmark(ctx.buf, ns_id, 4, 0, { 
				end_line = 4, 
				hl_group = "WarningMsg" 
			})
			
			return true
		end,
		confirm = function(picker, item)
			picker:close()
			-- No default action for authors - could be extended
		end,
	}
	
	-- Register other sources similarly...
	-- For brevity, I'm showing the pattern but not implementing all of them
	
	return true
end

-- Setup function to register sources with snacks
function M.setup()
	local config = require("revman.config")
	local picker_backend = config.get().picker or "vimSelect"
	
	if picker_backend ~= "snacks" then
		return
	end
	
	if register_sources() then
		local log = require("revman.log")
		log.info("Revman snacks sources registered successfully")
		
		-- Create convenience functions that can be called via lua
		_G.Snacks = _G.Snacks or {}
		_G.Snacks.revman = require("revman.snacks")
	end
end

return M