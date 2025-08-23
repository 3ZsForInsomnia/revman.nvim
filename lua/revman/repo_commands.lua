local M = {}

-- Create real commands (replacing stubs)
local function create_commands()
	vim.api.nvim_create_user_command("RevmanListRepos", function()
	local picker = require("revman.picker")
	local db_repos = require("revman.db.repos")
	local repos = db_repos.list()
	picker.pick_repos(repos, { prompt = "Repositories" })
	end, {})

	vim.api.nvim_create_user_command("RevmanAddRepo", function()
	local github_data = require("revman.github.data")
	local db_repos = require("revman.db.repos")
	local log = require("revman.log")
	local repo_name = github_data.get_canonical_repo_name()
	local directory = vim.fn.getcwd()
	if not repo_name or repo_name == "" then
		log.error("Could not determine canonical repo name for current directory.")
		return
	end
	for _, repo in ipairs(db_repos.list()) do
		if repo.name == repo_name or repo.directory == directory then
			log.info("Repo already exists: " .. repo_name .. " (" .. directory .. ")")
			log.notify("Repo already exists: " .. repo_name .. " (" .. directory .. ")")
			return
		end
	end
	db_repos.add(repo_name, directory)
	local repo_row = db_repos.get_by_name(repo_name)
	if repo_row then
		db_repos.update(repo_row.id, { directory = directory })
		log.info("Added repo: " .. repo_name .. " (" .. directory .. ")")
		log.notify("Added repo: " .. repo_name .. " (" .. directory .. ")")
	else
		log.error("Failed to add repo: " .. repo_name)
	end
	end, {})
end

-- Auto-create real commands when this module loads
create_commands()

return M
