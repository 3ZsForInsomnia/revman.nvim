local log = require("revman.log")

local M = {}

local function async_step(step_name, step_fn, success_cb, error_cb)
  vim.schedule(function()
    log.info("Starting " .. step_name .. "...")
    
    local ok, err = pcall(step_fn)
    
    vim.schedule(function()
      if ok then
        log.info("✓ " .. step_name .. " completed")
        if success_cb then success_cb() end
      else
        log.error("✗ " .. step_name .. " failed: " .. tostring(err))
        log.notify("Database repair failed during " .. step_name)
        if error_cb then error_cb(err) end
      end
    end)
  end)
end

local function run_schema_creation(callback)
  async_step("Schema Creation", function()
    local schema = require("revman.db.schema")
    schema.ensure_schema()
  end, callback, function(err)
    log.notify("Repair failed: Could not create database schema")
  end)
end

local function run_data_migration(callback)
  async_step("Data Migration", function()
    local schema = require("revman.db.schema")
    local helpers = require("revman.db.helpers")
    helpers.with_db(function(db)
      schema.run_migrations(db)
    end)
  end, callback, function(err)
    log.notify("Repair failed: Could not migrate existing data")
  end)
end

local function run_user_migration(callback)
  log.info("Starting User Migration (this may take a while)...")
  log.notify("Migrating users and fetching GitHub profiles...")
  
  -- Run user migration in chunks to avoid blocking
  vim.schedule(function()
    local migrate_users = require("revman.scripts.migrate_users")
    
    -- Wrap the migration to make it non-blocking
    local ok, err = pcall(function()
      -- The migrate_users function itself needs to be made async
      M.run_async_user_migration(callback)
    end)
    
    if not ok then
      vim.schedule(function()
        log.error("User migration failed: " .. tostring(err))
        log.notify("Repair failed: Could not migrate users")
      end)
    end
  end)
end

local function run_pr_resync(callback)
  log.info("Starting PR resync...")
  log.notify("Re-syncing all PRs with assignee data...")
  
  vim.schedule(function()
    local utils = require("revman.utils")
    local workflows = require("revman.workflows")
    
    local repo_name = utils.get_current_repo()
    if repo_name then
      workflows.sync_all_prs(repo_name, true, function(success)
        vim.schedule(function()
          if success then
            log.info("✓ PR resync completed")
            if callback then callback() end
          else
            log.warn("PR resync completed with some failures")
            if callback then callback() end
          end
        end)
      end)
    else
      log.info("Not in a GitHub repository, skipping PR resync")
      if callback then callback() end
    end
  end)
end

function M.run_async_repair()
  log.info("=== Database Repair Started ===")
  
  -- Step 1: Schema Creation
  run_schema_creation(function()
    
    -- Step 2: Data Migration  
    run_data_migration(function()
      
      -- Step 3: User Migration
      run_user_migration(function()
        
        -- Step 4: PR Resync
        run_pr_resync(function()
          
          -- All done!
          vim.schedule(function()
            log.info("=== Database Repair Completed ===")
            log.notify("🎉 Database repair completed successfully!")
          end)
        end)
      end)
    end)
  end)
end

function M.run_async_user_migration(callback)
  -- This is a simplified, non-blocking version of user migration
  local db_users = require("revman.db.users")
  local pr_lists = require("revman.db.pr_lists")
  local helpers = require("revman.db.helpers")
  
  local function discover_users()
    local usernames = {}
    
    -- Get users from PRs (quick operation)
    local all_prs = pr_lists.list({}, true)
    for _, pr in ipairs(all_prs) do
      if pr.author and pr.author ~= "" then
        usernames[pr.author] = true
      end
    end
    
    -- Get users from comments (quick operation)
    helpers.with_db(function(db)
      local all_comments = db:select("comments", {})
      for _, comment in ipairs(all_comments or {}) do
        if comment.author and comment.author ~= "" then
          usernames[comment.author] = true
        end
      end
    end)
    
    local username_list = {}
    for username, _ in pairs(usernames) do
      table.insert(username_list, username)
    end
    
    return username_list
  end
  
  local function create_basic_users(username_list, done_callback)
    log.info("Creating " .. #username_list .. " basic user records...")
    
    local created = 0
    local remaining = #username_list
    
    if remaining == 0 then
      done_callback()
      return
    end
    
    -- Process users in small batches to avoid blocking
    local batch_size = 5
    local batch_index = 1
    
    local function process_batch()
      local batch_end = math.min(batch_index + batch_size - 1, #username_list)
      
      for i = batch_index, batch_end do
        local username = username_list[i]
        -- Use the profile-fetching version for repair operations
        local ok, err = pcall(db_users.find_or_create_with_profile, username, true)
        if ok then
          created = created + 1
        else
          log.warn("Failed to create user " .. username .. ": " .. tostring(err))
        end
      end
      
      batch_index = batch_end + 1
      
      -- Show progress
      log.info("Created " .. created .. "/" .. #username_list .. " users...")
      
      if batch_index <= #username_list then
        -- Schedule next batch
        vim.defer_fn(process_batch, 50) -- Small delay to avoid blocking
      else
        -- All done
        log.info("✓ Created " .. created .. " basic user records")
        done_callback()
      end
    end
    
    -- Start processing
    process_batch()
  end
  
  -- Main user migration flow
  vim.schedule(function()
    local username_list = discover_users()
    
    if #username_list == 0 then
      log.info("No users found to migrate")
      if callback then callback() end
      return
    end
    
    create_basic_users(username_list, function()
      -- For now, skip GitHub profile fetching to avoid blocking
      -- Users can run a separate command for that if needed
      log.info("✓ User migration completed (basic records created)")
      log.notify("Users migrated successfully (profiles can be fetched separately)")
      if callback then callback() end
    end)
  end)
end

function M.fetch_github_profiles_async()
  local db_users = require("revman.db.users")
  local utils = require("revman.utils")
  
  -- Check if GitHub CLI is available
  if not utils.is_gh_available() then
    log.notify("GitHub CLI not available - cannot fetch user profiles")
    return
  end
  
  log.info("Starting GitHub profile fetch...")
  
  vim.schedule(function()
    -- Get all users without profile data
    local users = db_users.list_all()
    local users_to_fetch = {}
    
    for _, user in ipairs(users) do
      if not user.display_name and not user.avatar_url then
        table.insert(users_to_fetch, user)
      end
    end
    
    if #users_to_fetch == 0 then
      log.notify("All users already have profile data")
      return
    end
    
    log.info("Found " .. #users_to_fetch .. " users without profile data")
    log.notify("Fetching profiles for " .. #users_to_fetch .. " users...")
    
    local processed = 0
    local successful = 0
    local failed = 0
    
    local function fetch_next_user()
      processed = processed + 1
      
      if processed > #users_to_fetch then
        -- All done
        log.info("Profile fetch completed: " .. successful .. " successful, " .. failed .. " failed")
        log.notify("GitHub profile fetch completed!")
        return
      end
      
      local user = users_to_fetch[processed]
      
      -- Fetch user profile from GitHub (async)
      local cmd = { "gh", "api", "users/" .. user.username }
      
      vim.system(cmd, { text = true }, function(result)
        vim.schedule(function()
          if result.code == 0 and result.stdout then
            local ok, user_data = pcall(vim.json.decode, result.stdout)
            
            if ok and user_data and user_data.login then
              -- Update user with profile data
              local profile_data = {
                display_name = user_data.name ~= vim.NIL and user_data.name or nil,
                avatar_url = user_data.avatar_url ~= vim.NIL and user_data.avatar_url or nil
              }
              
              local update_ok = pcall(db_users.update, user.id, profile_data)
              if update_ok then
                successful = successful + 1
                log.info("✓ Updated profile for: " .. user.username)
              else
                failed = failed + 1
                log.warn("Failed to update profile for: " .. user.username)
              end
            else
              failed = failed + 1
              log.warn("Failed to parse profile for: " .. user.username)
            end
          else
            failed = failed + 1
            log.warn("Failed to fetch profile for: " .. user.username .. " (may be private/deleted)")
          end
          
          -- Show progress every 10 users
          if processed % 10 == 0 or processed == #users_to_fetch then
            log.notify("Profile fetch progress: " .. processed .. "/" .. #users_to_fetch)
          end
          
          -- Small delay then fetch next user
          vim.defer_fn(fetch_next_user, 200)
        end)
      end)
    end
    
    -- Start fetching
    fetch_next_user()
  end)
end

return M