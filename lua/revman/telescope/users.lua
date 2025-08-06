local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local previewers = require("telescope.previewers")
local conf = require("telescope.config").values

local analytics = require("revman.logic.analytics")

local M = {}

local function user_previewer(all_stats)
	return function(self, entry, status)
		local user = entry.value
		local stats = all_stats[entry.value] or {}
		local lines = {
			"User: " .. user,
			"----------------------",
			"PRs opened: " .. (stats.prs_opened or 0),
			-- "PRs reviewed: " .. (stats.prs_reviewed or 0),
			-- "PRs merged: " .. (stats.prs_merged or 0),
			-- "Comments: " .. (stats.comments or 0),
			-- "Comments/week: " .. (stats.comments_per_week or "N/A"),
			"Avg review time: " .. (stats.avg_review_time or "N/A"),
		}
		vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
	end
end

function M.pick_authors_with_preview(opts)
	opts = opts or {}
	local authors = analytics.authors_with_preview()
	pickers
		.new(opts, {
			prompt_title = "PR Authors (Analytics)",
			previewer = previewers.new_buffer_previewer({
				define_preview = user_previewer,
			}),
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
