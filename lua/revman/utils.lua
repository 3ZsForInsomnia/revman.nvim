local M = {}

local db_repos = require("revman.db.repos")
local config = require("revman.config")

M.format_relative_time = function(seconds)
	if not seconds or seconds < 0 then
		return "N/A"
	end
	local days = math.floor(seconds / 86400)
	local hours = math.floor((seconds % 86400) / 3600)
	local mins = math.floor((seconds % 3600) / 60)
	local parts = {}
	if days > 0 then
		table.insert(parts, days .. "d")
	end
	if hours > 0 or days > 0 then
		table.insert(parts, hours .. "h")
	end
	table.insert(parts, mins .. "m")
	return table.concat(parts, " ")
end

M.parse_iso8601 = function(str)
	-- Example: "2024-05-01T12:34:56Z"
	local year, month, day, hour, min, sec = str:match("^(%d+)%-(%d+)%-(%d+)T(%d+):(%d+):(%d+)Z$")
	if not year then
		return nil
	end
	return os.time({
		year = tonumber(year),
		month = tonumber(month),
		day = tonumber(day),
		hour = tonumber(hour),
		min = tonumber(min),
		sec = tonumber(sec),
		isdst = false,
	})
end

M.is_gh_available = function()
	local lines = vim.fn.systemlist("gh auth status")
	if vim.v.shell_error ~= 0 then
		return false
	end
	for _, line in ipairs(lines) do
		if line:match("Logged in to") then
			return true
		end
	end
	return false
end

M.get_current_repo = function()
	local lines = vim.fn.systemlist("gh repo view --json nameWithOwner -q .nameWithOwner")
	if vim.v.shell_error ~= 0 or #lines == 0 or (lines[1] == "" and #lines == 1) then
		return nil
	end
	return lines[1]:gsub("\n", "")
end

M.ensure_repo = function(repo_name)
	local repo_row = db_repos.get_by_name(repo_name)
	if repo_row then
		return repo_row
	end
	return nil, "Repository not yet added to the database"
	-- local repo_info = github_data.get_repo_info(repo_name)
	-- if not repo_info then
	-- 	return nil, "Could not fetch repo info"
	-- end
	-- local directory = vim.fn.getcwd()
	-- db_repos.add(repo_info.name, directory)
	-- return db_repos.get_by_name(repo_info.name)
end

M.db_file_exists = function()
	local db_path = config.get().database.path
	local stat = vim.loop.fs_stat(db_path)

	return stat and stat.type == "file"
end

return M
