local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local previewers = require("telescope.previewers")
local conf = require("telescope.config").values
local author_analytics = require("revman.analytics.authors")

local M = {}

local function user_previewer()
	return previewers.new_buffer_previewer({
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
			vim.api.nvim_buf_add_highlight(self.state.bufnr, -1, "Title", 0, 0, -1)
			vim.api.nvim_buf_add_highlight(self.state.bufnr, -1, "Identifier", 2, 0, -1)
			vim.api.nvim_buf_add_highlight(self.state.bufnr, -1, "Identifier", 3, 0, -1)
			vim.api.nvim_buf_add_highlight(self.state.bufnr, -1, "WarningMsg", 4, 0, -1)

			vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
		end,
	})
end

function M.pick_authors_with_preview(opts)
	opts = opts or {}

	local author_stats = author_analytics.get_author_analytics()
	local authors = {}

	for author, stats in pairs(author_stats) do
		stats.author = author -- ensure author field is present for display
		table.insert(authors, stats)
	end

	pickers
		.new(opts, {
			prompt_title = "PR Authors (Analytics)",
			previewer = user_previewer(),
			finder = finders.new_table({
				results = authors,
				entry_maker = function(author_info)
					return {
						value = author_info,
						display = author_info.author,
						ordinal = author_info.author,
					}
				end,
			}),
			sorter = conf.generic_sorter(opts),
		})
		:find()
end

return M
