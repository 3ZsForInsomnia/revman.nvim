local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local conf = require("telescope.config").values

local analytics = require("revman.logic.analytics")

local M = {}

function M.pick_authors_with_preview(opts)
	opts = opts or {}
	local authors = analytics.authors_with_preview()
	pickers
		.new(opts, {
			prompt_title = "PR Authors (Analytics)",
			finder = finders.new_table({
				results = authors,
				entry_maker = function(author_info)
					return {
						value = author_info,
						display = string.format(
							"%s: %d PRs, Avg Age at Merge: %.1f days",
							author_info.author,
							author_info.pr_count,
							author_info.avg_age_at_merge / 86400 -- convert seconds to days
						),
						ordinal = author_info.author,
					}
				end,
			}),
			sorter = conf.generic_sorter(opts),
		})
		:find()
end

return M
