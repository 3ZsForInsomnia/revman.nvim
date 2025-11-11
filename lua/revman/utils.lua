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
		local log = require("revman.log")
		local error_msg = #lines > 0 and lines[1] or "unknown error"
		log.error("GitHub CLI not authenticated: " .. error_msg)
		log.notify("GitHub CLI authentication required", { title = "Revman Error", icon = "❌" })
		return false
	end
	for _, line in ipairs(lines) do
		if line:match("Logged in to") then
			return true
		end
	end
	local log = require("revman.log")
	log.warn("GitHub CLI available but not logged in")
	return false
end

M.get_current_repo = function()
	local lines = vim.fn.systemlist("gh repo view --json nameWithOwner -q .nameWithOwner")
	if vim.v.shell_error ~= 0 then
		local log = require("revman.log")
		local error_msg = #lines > 0 and lines[1] or "unknown error"
		log.error("Failed to get current repo: " .. error_msg)
		return nil
	end
	if #lines == 0 or (lines[1] == "" and #lines == 1) then
		return nil
	end
	return lines[1]:gsub("\n", "")
end

M.get_current_user = function()
	local lines = vim.fn.systemlist("gh api user --jq .login")
	if vim.v.shell_error ~= 0 then
		local log = require("revman.log")
		local error_msg = #lines > 0 and lines[1] or "unknown error"
		log.error("Failed to get current user: " .. error_msg)
		log.notify("Failed to get GitHub user info", { title = "Revman Error", icon = "❌" })
		return nil
	end
	if #lines == 0 or (lines[1] == "" and #lines == 1) then
		return nil
	end
	local username = lines[1]:gsub("\n", "")
	
	-- Update users table with current user
	local db_users = require("revman.db.users")
	-- Fetch profile for current user if not already available
	db_users.find_or_create_with_profile(username, true)
	
	return username
end

M.get_current_user_with_profile = function()
	local lines = vim.fn.systemlist("gh api user")
	if vim.v.shell_error ~= 0 then
		local log = require("revman.log")
		local error_msg = #lines > 0 and lines[1] or "unknown error"
		log.error("Failed to get user profile: " .. error_msg)
		log.notify("Failed to get GitHub user profile", { title = "Revman Error", icon = "❌" })
		return nil
	end
	if #lines == 0 or (lines[1] == "" and #lines == 1) then
		return nil
	end
	
	local output = table.concat(lines, "\n")
	local ok, user_data = pcall(vim.json.decode, output)
	if not ok or not user_data then
		local log = require("revman.log")
		log.error("Failed to parse user profile JSON: " .. output)
		log.notify("Failed to parse GitHub user profile", { title = "Revman Error", icon = "❌" })
		return nil
	end
	
	-- Update users table with full profile data
	local db_users = require("revman.db.users")
	local profile_data = {
		display_name = user_data.name,
		avatar_url = user_data.avatar_url
	}
	db_users.find_or_create(user_data.login, profile_data)
	
	return user_data
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
	local db_path = config.get().database_path
	local stat = vim.loop.fs_stat(db_path)

	return stat and stat.type == "file"
end

function M.strip_quotes(s)
	return s and s:gsub('^"(.*)"$', "%1") or s
end

return M
