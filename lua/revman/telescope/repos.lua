local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local conf = require("telescope.config").values

local db_repos = require("revman.db.repos")

local M = {}

function M.pick_repos(opts)
	opts = opts or {}
	local repos = db_repos.list()
	pickers
		.new(opts, {
			prompt_title = "Repositories",
			finder = finders.new_table({
				results = repos,
				entry_maker = function(repo)
					return {
						value = repo,
						display = string.format("%s (%s)", repo.name, repo.directory or ""),
						ordinal = repo.name,
					}
				end,
			}),
			sorter = conf.generic_sorter(opts),
		})
		:find()
end

return M
