local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local conf = require("telescope.config").values

local db_prs = require("revman.db.prs")

local function format_pr_entry(pr)
	return string.format("#%s [%s] %s (%s)", pr.number, pr.state, pr.title, pr.author or "unknown")
end

local M = {}

function M.pick_all_prs(opts)
	opts = opts or {}
	local prs = db_prs.list()
	pickers
		.new(opts, {
			prompt_title = "All PRs",
			finder = finders.new_table({
				results = prs,
				entry_maker = function(pr)
					return {
						value = pr,
						display = format_pr_entry(pr),
						ordinal = pr.title .. " " .. (pr.author or ""),
					}
				end,
			}),
			sorter = conf.generic_sorter(opts),
			attach_mappings = function(_, map)
				-- You can add mappings here for actions on PR selection
				return true
			end,
		})
		:find()
end

function M.pick_open_prs(opts)
	opts = opts or {}
	local prs = db_prs.list_open()
	pickers
		.new(opts, {
			prompt_title = "Open PRs",
			finder = finders.new_table({
				results = prs,
				entry_maker = function(pr)
					return {
						value = pr,
						display = format_pr_entry(pr),
						ordinal = pr.title .. " " .. (pr.author or ""),
					}
				end,
			}),
			sorter = conf.generic_sorter(opts),
		})
		:find()
end

function M.pick_merged_prs(opts)
	opts = opts or {}
	local prs = db_prs.list_merged()
	pickers
		.new(opts, {
			prompt_title = "Merged PRs",
			finder = finders.new_table({
				results = prs,
				entry_maker = function(pr)
					return {
						value = pr,
						display = format_pr_entry(pr),
						ordinal = pr.title .. " " .. (pr.author or ""),
					}
				end,
			}),
			sorter = conf.generic_sorter(opts),
		})
		:find()
end

return M
