local pr_lists = require("revman.db.pr_lists")
local db_users = require("revman.db.users")
local utils = require("revman.utils")
local log = require("revman.log")
local helpers = require("revman.db.helpers")

local function migrate_users()
	log.info("Starting user migration and profile backfill...")

	-- Step 1: Discover all unique usernames from existing data
	local usernames = {}

	log.info("Discovering users from PR authors...")
	local all_prs = pr_lists.list({}, true) -- Get all PRs including not_tracked
	for _, pr in ipairs(all_prs) do
		if pr.author and pr.author ~= "" then
			usernames[pr.author] = true
		end
	end

	log.info("Discovering users from comment authors...")
	helpers.with_db(function(db)
		-- Get all comment authors (sqlite.lua doesn't support DISTINCT)
		local all_comments = db:select("comments", {
			select = "author",
		})

		for _, row in ipairs(all_comments or {}) do
			if row.author and row.author ~= "" then
				usernames[row.author] = true
			end
		end
	end)

	-- Convert to list
	local username_list = {}
	for username, _ in pairs(usernames) do
		table.insert(username_list, username)
	end

	log.info("Found " .. #username_list .. " unique users to migrate")

	if #username_list == 0 then
		log.info("No users found to migrate")
		return
	end

	-- First, create all users with basic info (this should always work)
	log.info("Creating basic user records...")
	local basic_created = 0
	for _, username in ipairs(username_list) do
		local create_ok, create_err = pcall(db_users.find_or_create, username)
		if create_ok then
			basic_created = basic_created + 1
		else
			log.warn("Failed to create basic user " .. username .. ": " .. tostring(create_err))
		end
	end
	log.info("Created " .. basic_created .. " basic user records")

	-- Step 2: Batch fetch user profiles from GitHub
	log.info("Fetching GitHub profiles (this may take a while)...")
	local batch_size = 10
	local processed = 0
	local successful = 0
	local failed = 0

	for i = 1, #username_list, batch_size do
		local batch = {}
		for j = i, math.min(i + batch_size - 1, #username_list) do
			table.insert(batch, username_list[j])
		end

		log.info("Processing batch " .. math.ceil(i / batch_size) .. " (" .. #batch .. " users)")

		-- Show progress notification
		if i == 1 then
			log.notify("Starting user profile migration...")
		elseif i % 50 == 1 then
			log.notify("Migrated " .. processed .. "/" .. #username_list .. " users...")
		end

		for _, username in ipairs(batch) do
			-- Fetch user profile from GitHub
			local lines = vim.fn.systemlist("gh api users/" .. username)
			if vim.v.shell_error ~= 0 then
				local error_msg = #lines > 0 and lines[1] or "unknown error"
				log.warn("Failed to fetch profile for user " .. username .. ": " .. error_msg)
				processed = processed + 1
			elseif #lines > 0 then
				local output = table.concat(lines, "\n")
				local ok, user_data = pcall(vim.json.decode, output)

				if ok and user_data and user_data.login then
					-- Create/update user with full profile
					-- Debug log the types we're getting from GitHub API
					log.info(
						"GitHub API data for "
							.. username
							.. ": name="
							.. type(user_data.name)
							.. ", avatar_url="
							.. type(user_data.avatar_url)
					)

					local profile_data = {
						display_name = user_data.name ~= vim.NIL and user_data.name or nil,
						avatar_url = user_data.avatar_url ~= vim.NIL and user_data.avatar_url or nil,
					}

					-- Update existing user with profile data
					local user = db_users.get_by_username(user_data.login)
					if user then
						local update_ok, update_err = pcall(db_users.update, user.id, profile_data)
						if update_ok then
							successful = successful + 1
							log.info("✓ Updated profile for user: " .. username)
						else
							log.error("Failed to update user " .. username .. ": " .. tostring(update_err))
							failed = failed + 1
						end
					else
						-- User doesn't exist, create with profile data
						local create_ok, create_err = pcall(db_users.find_or_create, user_data.login, profile_data)
						if create_ok then
							successful = successful + 1
							log.info("✓ Created user with profile: " .. username)
						else
							log.error("Failed to create user " .. username .. ": " .. tostring(create_err))
							failed = failed + 1
						end
					end
				else
					log.warn("Failed to parse user data for: " .. username)
					-- User already created in basic step, just count as failed profile fetch
					failed = failed + 1
				end
			else
				log.warn("Failed to fetch user profile for: " .. username .. " (may be private/deleted)")
				-- User already created in basic step, just count as failed profile fetch
				failed = failed + 1
			end

			processed = processed + 1

			-- Small delay to be nice to GitHub API
			vim.wait(100)
		end

		-- Longer delay between batches
		if i + batch_size <= #username_list then
			log.info("Waiting between batches...")
			vim.wait(1000)
		end
	end

	log.info(
		string.format("User migration completed: %d successful, %d failed, %d total", successful, failed, processed)
	)

	-- Step 3: Re-sync all PRs to populate assignee relationships
	log.info("Re-syncing all PRs to populate assignee relationships...")

	local repo_name = utils.get_current_repo()
	if not repo_name then
		log.warn("Not in a GitHub repository, skipping PR re-sync")
		return
	end

	local workflows = require("revman.workflows")
	local sync_count = 0
	local sync_errors = 0

	-- Get all PRs including closed ones for complete assignee history
	for _, pr in ipairs(all_prs) do
		workflows.sync_pr(pr.number, repo_name, function(pr_id, err)
			if pr_id then
				sync_count = sync_count + 1
				if sync_count % 10 == 0 then
					log.info("Re-synced " .. sync_count .. " PRs...")
				end
			else
				sync_errors = sync_errors + 1
				log.warn("Failed to re-sync PR #" .. pr.number .. ": " .. (err or "unknown error"))
			end
		end)

		-- Brief delay between syncs
		vim.wait(200)
	end

	log.info("PR re-sync completed: " .. sync_count .. " successful, " .. sync_errors .. " failed")
	log.notify("User migration and assignee backfill completed!")
end

local function migrate_users_safe()
	local ok, err = pcall(migrate_users)
	if not ok then
		log.error("User migration failed: " .. tostring(err))
		log.notify("User migration failed! Check logs for details.")
	end
end

return migrate_users_safe
