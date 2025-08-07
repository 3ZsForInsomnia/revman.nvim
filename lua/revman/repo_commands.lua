local github_data = require("revman.github.data")
local db_repos = require("revman.db.repos")
local telescope_repos = require("revman.telescope.repos")
local log = require("revman.log")

local M = {}

vim.api.nvim_create_user_command("RevmanListRepos", function()
	telescope_repos.pick_repos()
end, {})

vim.api.nvim_create_user_command("RevmanAddRepo", function()
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

return M
