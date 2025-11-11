local with_db = require("revman.db.helpers").with_db

local M = {}

function M.get_by_id(user_id)
	return with_db(function(db)
		local rows = db:select("users", {
			where = { id = user_id }
		})
		return rows and #rows > 0 and rows[1] or nil
	end)
end

function M.get_by_username(username)
	return with_db(function(db)
		local rows = db:select("users", {
			where = { username = username }
		})
		return rows and #rows > 0 and rows[1] or nil
	end)
end

function M.find_or_create(username, additional_data)
	return with_db(function(db)
		-- Try to find existing user
		local existing_user = db:select("users", {
			where = { username = username }
		})
		
		if existing_user and #existing_user > 0 then
			-- Update last_seen timestamp
			local now = os.date("!%Y-%m-%dT%H:%M:%SZ")
			db:update("users", {
				where = { id = existing_user[1].id },
				set = { last_seen = now }
			})
			return existing_user[1]
		end
		
		-- Create new user
		local now = os.date("!%Y-%m-%dT%H:%M:%SZ")
		local user_data = {
			username = username,
			display_name = (additional_data and additional_data.display_name ~= vim.NIL and additional_data.display_name) or nil,
			avatar_url = (additional_data and additional_data.avatar_url ~= vim.NIL and additional_data.avatar_url) or nil,
			first_seen = now,
			last_seen = now
		}
		
		local user_id = db:insert("users", user_data)
		user_data.id = user_id
		return user_data
	end)
end

function M.update(user_id, updates)
	return with_db(function(db)
		-- Always update last_seen when updating user
		local now = os.date("!%Y-%m-%dT%H:%M:%SZ")
		updates.last_seen = now
		
		db:update("users", {
			where = { id = user_id },
			set = updates
		})
		return M.get_by_id(user_id)
	end)
end

function M.list_all()
	return with_db(function(db)
		return db:select("users", {
			order_by = { asc = { "username" } }
		}) or {}
	end)
end

function M.get_recent_users(limit)
	limit = limit or 50
	return with_db(function(db)
		return db:select("users", {
			order_by = { desc = { "last_seen" } },
			limit = limit
		}) or {}
	end)
end

-- Async function to fetch user profile from GitHub and update database
function M.fetch_and_update_profile_async(username, callback)
	local log = require("revman.log")
	
	-- Run GitHub API call in background
	vim.schedule(function()
		local lines = vim.fn.systemlist("gh api users/" .. username)
		
		if vim.v.shell_error ~= 0 then
			local error_msg = #lines > 0 and lines[1] or "unknown error"
			log.warn("Failed to fetch profile for user " .. username .. ": " .. error_msg)
			if callback then callback(nil, error_msg) end
			return
		end
		
		if #lines == 0 then
			log.warn("Empty response when fetching profile for user: " .. username)
			if callback then callback(nil, "empty response") end
			return
		end
		
		local output = table.concat(lines, "\n")
		local ok, user_data = pcall(vim.json.decode, output)
		
		if not ok or not user_data or not user_data.login then
			log.warn("Failed to parse user data for: " .. username)
			if callback then callback(nil, "parse error") end
			return
		end
		
		-- Extract profile data, handling vim.NIL values
		local profile_data = {
			display_name = user_data.name ~= vim.NIL and user_data.name or nil,
			avatar_url = user_data.avatar_url ~= vim.NIL and user_data.avatar_url or nil,
		}
		
		-- Update the user in database
		local user = M.get_by_username(user_data.login)
		if user then
			local updated_user = M.update(user.id, profile_data)
			log.info("✓ Updated profile for user: " .. username)
			if callback then callback(updated_user, nil) end
		else
			-- User doesn't exist, create with profile data
			local new_user = M.find_or_create(user_data.login, profile_data)
			log.info("✓ Created user with profile: " .. username)
			if callback then callback(new_user, nil) end
		end
	end)
end

-- Enhanced find_or_create that can optionally fetch profile data
function M.find_or_create_with_profile(username, fetch_profile, callback)
	-- First, do the basic find_or_create
	local user = M.find_or_create(username)
	
	-- If we found an existing user with profile data, or not fetching, we're done
	if not fetch_profile or (user.display_name and user.avatar_url) then
		if callback then callback(user, nil) end
		return user
	end
	
	-- Otherwise, fetch profile data asynchronously
	M.fetch_and_update_profile_async(username, callback)
	return user -- Return the basic user immediately
end
return M