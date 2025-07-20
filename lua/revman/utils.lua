local M = {}

local github_data = require("revman.github.data")
local db_repos = require("revman.db.repos")

M.format_relative_time = function(timestamp)
	local now = os.time()
	local diff = now - timestamp
	if diff < 60 then
		return diff .. "s ago"
	elseif diff < 3600 then
		return math.floor(diff / 60) .. "m ago"
	elseif diff < 86400 then
		return math.floor(diff / 3600) .. "h ago"
	else
		return math.floor(diff / 86400) .. "d ago"
	end
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
	local repo_info = github_data.get_repo_info(repo_name)
	if not repo_info then
		return nil, "Could not fetch repo info"
	end
	db_repos.add(repo_info.name)
	return db_repos.get_by_name(repo_info.name)
end

return M
