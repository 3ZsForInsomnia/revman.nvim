local with_db = require("revman.db.helpers").with_db
local db_users = require("revman.db.users")

local M = {}

function M.get_assignees_for_pr(pr_id)
	return with_db(function(db)
		local rows = db:select("pr_assignees pa JOIN users u ON pa.user_id = u.id", {
			select = "u.id, u.username, u.display_name, u.avatar_url",
			where = { ["pa.pr_id"] = pr_id }
		})
		return rows or {}
	end)
end

function M.get_prs_for_user(user_id)
	return with_db(function(db)
		local rows = db:select("pr_assignees pa JOIN pull_requests pr ON pa.pr_id = pr.id", {
			select = "pr.*",
			where = { ["pa.user_id"] = user_id }
		})
		return rows or {}
	end)
end

function M.add_assignee(pr_id, username)
	return with_db(function(db)
		-- Find or create user
		local user = db_users.find_or_create_with_profile(username, true)
		if not user then
			return false, "Could not create user: " .. username
		end
		
		-- Check if assignment already exists
		local existing = db:select("pr_assignees", {
			where = { pr_id = pr_id, user_id = user.id }
		})
		
		if existing and #existing > 0 then
			return true -- Already assigned, no need to add
		end
		
		-- Add assignment
		db:insert("pr_assignees", {
			pr_id = pr_id,
			user_id = user.id
		})
		
		return true
	end)
end

function M.remove_assignee(pr_id, username)
	return with_db(function(db)
		-- Find user
		local user = db_users.get_by_username(username)
		if not user then
			return true -- User doesn't exist, consider it removed
		end
		
		-- Remove assignment
		db:delete("pr_assignees", {
			where = { pr_id = pr_id, user_id = user.id }
		})
		
		return true
	end)
end

function M.replace_assignees_for_pr(pr_id, assignee_usernames)
	return with_db(function(db)
		-- Remove all existing assignments for this PR
		db:delete("pr_assignees", {
			where = { pr_id = pr_id }
		})
		
		-- Add new assignments
		for _, username in ipairs(assignee_usernames or {}) do
			local user = db_users.find_or_create_with_profile(username, true)
			if user then
				db:insert("pr_assignees", {
					pr_id = pr_id,
					user_id = user.id
				})
			end
		end
		
		return true
	end)
end

function M.is_user_assigned(pr_id, username)
	return with_db(function(db)
		local user = db_users.get_by_username(username)
		if not user then
			return false
		end
		
		local assignment = db:select("pr_assignees", {
			where = { pr_id = pr_id, user_id = user.id }
		})
		
		return assignment and #assignment > 0
	end)
end

function M.is_current_user_assigned(pr_id)
	local utils = require("revman.utils")
	local current_user = utils.get_current_user()
	if not current_user then
		return false
	end
	
	return M.is_user_assigned(pr_id, current_user)
end

return M