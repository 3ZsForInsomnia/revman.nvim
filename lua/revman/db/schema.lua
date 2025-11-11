local config = require("revman.config")
local log = require("revman.log")

local M = {}

M.ensure_schema = function()
	local db_path = config.get().database_path
	log.info("Using database file: " .. db_path)

	local db_dir = db_path:match("(.+)/[^/]+$")
	if db_dir and not vim.loop.fs_stat(db_dir) then
		vim.fn.mkdir(db_dir, "p")
	end

	local db, err = M.get_db()
	if not db then
		log.error("Failed to create DB: " .. tostring(err))
		return
	else
		log.info("DB opened successfully")
	end

	local stmts = {
		[[
		CREATE TABLE IF NOT EXISTS users (
			id INTEGER PRIMARY KEY,
			username TEXT NOT NULL UNIQUE,
			display_name TEXT,
			avatar_url TEXT,
			first_seen TEXT NOT NULL,
			last_seen TEXT NOT NULL
		)
		]],
		[[
		CREATE TABLE IF NOT EXISTS repositories (
			id INTEGER PRIMARY KEY,
			name TEXT NOT NULL UNIQUE,
			reminder_days INTEGER DEFAULT 3,
			directory TEXT NOT NULL
		)
		]],
		[[
		CREATE TABLE IF NOT EXISTS review_status (
			id INTEGER PRIMARY KEY,
			name TEXT NOT NULL UNIQUE
		)
		]],
		[[
		CREATE TABLE IF NOT EXISTS pull_requests (
			id INTEGER PRIMARY KEY,
			repo_id INTEGER NOT NULL,
			number INTEGER NOT NULL,
			title TEXT NOT NULL,
			state TEXT NOT NULL,
			url TEXT NOT NULL,
			author TEXT NOT NULL,
			created_at TEXT NOT NULL,
			is_draft INTEGER NOT NULL,
			review_decision TEXT,
			last_synced TEXT NOT NULL,
			last_viewed TEXT,
			last_activity TEXT,
			ci_status TEXT,
			review_status_id INTEGER,
			comment_count INTEGER DEFAULT 0,
			UNIQUE(repo_id, number),
			FOREIGN KEY(repo_id) REFERENCES repositories(id),
			FOREIGN KEY(review_status_id) REFERENCES review_status(id)
		)
		]],
		[[
		CREATE TABLE IF NOT EXISTS notes (
			id INTEGER PRIMARY KEY,
			pr_id INTEGER NOT NULL,
			content TEXT,
			updated_at TEXT NOT NULL,
			FOREIGN KEY(pr_id) REFERENCES pull_requests(id)
		)
		]],
		[[
		CREATE TABLE IF NOT EXISTS review_status_history (
			id INTEGER PRIMARY KEY,
			pr_id INTEGER NOT NULL,
			from_status_id INTEGER,
			to_status_id INTEGER,
			timestamp TEXT NOT NULL,
			FOREIGN KEY(pr_id) REFERENCES pull_requests(id),
			FOREIGN KEY(from_status_id) REFERENCES review_status(id),
			FOREIGN KEY(to_status_id) REFERENCES review_status(id)
		)
		]],
		[[
		CREATE TABLE IF NOT EXISTS pr_assignees (
			id INTEGER PRIMARY KEY,
			pr_id INTEGER NOT NULL,
			user_id INTEGER NOT NULL,
			UNIQUE(pr_id, user_id),
			FOREIGN KEY(pr_id) REFERENCES pull_requests(id),
			FOREIGN KEY(user_id) REFERENCES users(id)
		)
		]],
		[[
		CREATE TABLE IF NOT EXISTS user_analytics (
			id INTEGER PRIMARY KEY,
			user_id INTEGER NOT NULL,
			metric_name TEXT NOT NULL,
			metric_value TEXT NOT NULL,
			calculated_at TEXT NOT NULL,
			period_start TEXT,
			period_end TEXT,
			UNIQUE(user_id, metric_name, period_start, period_end),
			FOREIGN KEY(user_id) REFERENCES users(id)
		)
		]],
		[[
      CREATE TABLE IF NOT EXISTS comments (
        id INTEGER PRIMARY KEY,
        github_id INTEGER UNIQUE,
        pr_id INTEGER NOT NULL,
        author TEXT NOT NULL,
        created_at TEXT NOT NULL,
        body TEXT,
        in_reply_to_id INTEGER,
        FOREIGN KEY(pr_id) REFERENCES pull_requests(id)
      )
    ]],
	}

	for _, stmt in ipairs(stmts) do
		local _, statement_error = pcall(function()
			db:execute(stmt)
		end)
		if err then
			log.error("DB schema error: " .. tostring(statement_error))
		end
	end

	log.info("DB schema created and verified successfully")

	local statuses = {
		"waiting_for_review",
		"waiting_for_changes",
		"ready_for_re_review",
		"approved",
		"merged",
		"closed",
		"needs_nudge",
		"not_tracked",
	}
  
  -- Only insert statuses that don't already exist
  for _, name in ipairs(statuses) do
    local existing = db:select("review_status", { where = { name = name } })
    if not existing or #existing == 0 then
      db:insert("review_status", { name = name })
      log.info("Added review status: " .. name)
    end
  end

	log.info("Review statuses initialized")
	db:close()

	if vim.loop.fs_stat(db_path) then
		log.info("DB file exists after schema creation: " .. db_path)
	else
		log.error("DB file does NOT exist after schema creation: " .. db_path)
	end
end

function M.get_db()
	local helpers = require("revman.db.helpers")
	return helpers.get_db()
end

function M.run_migrations(db)
	-- Migration 1: Populate users table from existing PR authors
	M.migrate_existing_authors(db)
end

function M.migrate_existing_authors(db)
	log.info("Running migration: populate users table from existing authors")
	
  -- Check if users table exists by trying to query it
  local users_table_exists = pcall(function()
    db:select("users", { limit = 1 })
  end)
  
  if not users_table_exists then
    log.warn("Users table does not exist, skipping author migration")
    return
  end
  
  -- Get all unique authors from pull_requests  
  -- Note: sqlite.lua doesn't support DISTINCT in select, so we'll get all and deduplicate
  local ok, all_prs = pcall(function()
    return db:select("pull_requests", {})
  end)
  
  if not ok or not all_prs then
    log.warn("Could not query pull_requests table, skipping migration")
    return
  end
  
  -- Deduplicate authors manually
  local unique_authors = {}
  for _, row in ipairs(all_prs) do
    if row.author and row.author ~= "" then
      unique_authors[row.author] = true
    end
  end
	
  local author_list = {}
  for author, _ in pairs(unique_authors) do
    table.insert(author_list, author)
  end
  
  if #author_list == 0 then
		log.info("No existing authors found to migrate")
		return
	end
	
  -- Check if migration already ran by seeing if users already exist
  local users_ok, existing_users = pcall(function()
    return db:select("users", {})
  end)
  
  if users_ok and existing_users and #existing_users > 0 then
    log.info("Users table already populated (" .. #existing_users .. " users), skipping author migration")
    return
  end
  
	local now = os.date("!%Y-%m-%dT%H:%M:%SZ")
  local migrated_count = 0
	
  for _, username in ipairs(author_list) do
		if username and username ~= "" then
			-- Check if user already exists
      local user_exists = false
      local check_ok, existing_user = pcall(function()
        return db:select("users", { where = { username = username } })
      end)
			
      if check_ok and existing_user and #existing_user > 0 then
        user_exists = true
      end
      
      if not user_exists then
        -- Insert new user
        local insert_ok, insert_err = pcall(function()
          db:insert("users", {
            username = username,
            display_name = nil, -- Will be populated by future GitHub fetch
            avatar_url = nil,   -- Will be populated by future GitHub fetch
            first_seen = now,
            last_seen = now
          })
        end)
        
        if insert_ok then
          migrated_count = migrated_count + 1
          log.info("Migrated user: " .. username)
        else
          log.warn("Failed to migrate user " .. username .. ": " .. tostring(insert_err))
        end
			end
		end
	end
	
  log.info("Author migration completed: " .. migrated_count .. " users migrated")
end

return M
