local github_data = require("revman.github.data")
local github_prs = require("revman.github.prs")
local pr_lists = require("revman.db.pr_lists")
local pr_assignees = require("revman.db.pr_assignees")
local utils = require("revman.utils")
local log = require("revman.log")

local M = {}

-- Filter GitHub PRs to find those where current user is assigned or review-requested
-- For this plugin, being assigned to a PR or having your review requested are equivalent
function M.filter_assigned_prs(github_prs, current_user)
  if not current_user then
    current_user = utils.get_current_user()
  end
  
  if not current_user then
    return {}
  end
  
  local assigned_prs = {}
  
  for _, pr in ipairs(github_prs) do
    local is_assigned = false
    
    -- Check if user is directly assigned
    if pr.assignees then
      for _, assignee in ipairs(pr.assignees) do
        if assignee.login == current_user then
          is_assigned = true
          break
        end
      end
    end
    
    -- For review requests, gh CLI with --requested-reviewer @me should already filter these
    -- But we can add additional checks here if needed in the future
    
    if is_assigned then
      table.insert(assigned_prs, pr)
    end
  end
  
  return assigned_prs
end

function M.get_current_user_assignments(repo_name, callback)
  repo_name = repo_name or utils.get_current_repo()
  if not repo_name then
    callback(nil, "Not in a GitHub repository")
    return
  end

  github_data.get_assigned_prs_async(repo_name, function(assigned_prs, err)
    if not assigned_prs then
      callback(nil, err or "Failed to fetch assigned PRs")
      return
    end

    -- Extract PR numbers and assignees
    local assignments = {}
    for _, pr in ipairs(assigned_prs) do
      local assignees = github_prs.extract_assignees(pr)
      table.insert(assignments, {
        number = pr.number,
        title = pr.title,
        state = pr.state,
        assignees = assignees,
        pr_data = pr
      })
    end

    callback(assignments, nil)
  end)
end

function M.find_new_assignments(repo_name, callback)
  local repo_row = utils.ensure_repo(repo_name)
  if not repo_row then
    callback(nil, "Repository not found in database")
    return
  end

  M.get_current_user_assignments(repo_name, function(assignments, err)
    if not assignments then
      callback(nil, err)
      return
    end

    -- Get currently tracked PRs
    local tracked_prs = pr_lists.list({ where = { repo_id = repo_row.id } })
    local tracked_numbers = {}
    for _, pr in ipairs(tracked_prs) do
      tracked_numbers[pr.number] = true
    end

    -- Find assignments that aren't currently tracked
    local new_assignments = {}
    for _, assignment in ipairs(assignments) do
      if not tracked_numbers[assignment.number] then
        table.insert(new_assignments, assignment)
      end
    end

    callback(new_assignments, nil)
  end)
end

function M.find_removed_assignments(repo_name, callback)
  local repo_row = utils.ensure_repo(repo_name)
  if not repo_row then
    callback(nil, "Repository not found in database")
    return
  end

  local current_user = utils.get_current_user()
  if not current_user then
    callback(nil, "Could not determine current user")
    return
  end

  -- Get PRs currently assigned to user in database
  local assigned_prs = pr_lists.list_assigned_to_user(current_user, {
    where = { state = "OPEN" }
  })

  if #assigned_prs == 0 then
    callback({}, nil) -- No assigned PRs, nothing to check
    return
  end

  -- Get current assignments from GitHub
  M.get_current_user_assignments(repo_name, function(current_assignments, err)
    if not current_assignments then
      callback(nil, err)
      return
    end

    -- Create lookup of current GitHub assignments
    local current_numbers = {}
    for _, assignment in ipairs(current_assignments) do
      current_numbers[assignment.number] = true
    end

    -- Find PRs that were assigned in DB but not in current GitHub state
    local removed_assignments = {}
    for _, pr in ipairs(assigned_prs) do
      if not current_numbers[pr.number] then
        table.insert(removed_assignments, pr)
      end
    end

    callback(removed_assignments, nil)
  end)
end

function M.should_auto_add_pr(pr_data, config_mode)
  -- Use new assignment_tracking config
  if not config_mode then
    local config = require("revman.config")
    config_mode = config.get().assignment_tracking or "smart"
  end
  
  if config_mode == "off" then
    return false
  end
  
                                   if config_mode == "manual" then
    return false -- These modes require manual selection
  end
  
  if config_mode == "smart" or config_mode == "always" then
    return true -- Auto-add all assigned/requested PRs
  end
  
  return false
end

function M.should_remove_pr(pr_id, config_mode)
  -- Use new assignment_tracking config  
  if not config_mode then
    local config = require("revman.config")
    config_mode = config.get().assignment_tracking or "smart"
  end
  
  if config_mode == "manual" or config_mode == "always" then
    return false
  end
  
  if config_mode == "smart" then
    -- Smart removal: only remove if user hasn't interacted with PR recently
    return M.is_safe_to_remove_with_time_check(pr_id)
  end
  
  return false
end

function M.is_safe_to_remove(pr_id)
  local db_notes = require("revman.db.notes")
  local db_comments = require("revman.db.comments")
  local db_prs = require("revman.db.prs")
  local utils = require("revman.utils")
  
  -- Check if user has notes on this PR
  local note = db_notes.get_by_pr_id(pr_id)
  if note and note.content and note.content ~= "" then
    log.info("PR " .. pr_id .. " not safe to remove: user has notes")
    return false -- Don't remove if user has notes
  end
  
  -- Check if user has commented on this PR
  local current_user = utils.get_current_user()
  if current_user then
    local helpers = require("revman.db.helpers")
    local has_comments = helpers.with_db(function(db)
      local user_comments = db:select("comments", {
        where = { pr_id = pr_id, author = current_user }
      })
      return user_comments and #user_comments > 0
    end)
    
    if has_comments then
      log.info("PR " .. pr_id .. " not safe to remove: user has comments")
      return false -- Don't remove if user has commented
    end
  end
  
  -- Check if user has changed the PR status (indicates interaction)
  local status = require("revman.db.status")
  local status_history = status.get_status_history(pr_id)
  if status_history and #status_history > 1 then
    log.info("PR " .. pr_id .. " not safe to remove: user has changed status")
    return false -- Don't remove if user has changed status
  end
  
  -- Safe to remove if no user interaction
  log.info("PR " .. pr_id .. " safe to remove: no significant user interaction found")
  return true
end

-- New function that includes time-based interaction checking for smart mode
function M.is_safe_to_remove_with_time_check(pr_id)
  local db_notes = require("revman.db.notes")
  local db_comments = require("revman.db.comments")
  local db_prs = require("revman.db.prs")
  local mentions = require("revman.mentions")
  local utils = require("revman.utils")
  
  -- Check if user has notes on this PR (always protect)
  local note = db_notes.get_by_pr_id(pr_id)
  if note and note.content and note.content ~= "" then
    log.info("PR " .. pr_id .. " not safe to remove: user has notes")
    return false
  end
  
  -- Check if user has changed the PR status (always protect)
  local status = require("revman.db.status")
  local status_history = status.get_status_history(pr_id)
  if status_history and #status_history > 1 then
    log.info("PR " .. pr_id .. " not safe to remove: user has changed status")
    return false
  end
  
  -- For smart mode, check recent interactions (3 day window)
  local pr = db_prs.get_by_id(pr_id)
  if not pr then
    return true -- PR not found, safe to remove
  end
  
  local current_user = utils.get_current_user()
  if not current_user then
    return true -- Can't check interactions without user
  end
  
  -- Get all comments for this PR to check interactions and mentions
  local helpers = require("revman.db.helpers")
  local all_comments = helpers.with_db(function(db)
    return db:select("comments", {
      where = { pr_id = pr_id }
    }) or {}
  end)
  
  -- Check if user has recent interactions (comments, mentions, etc.)
  -- Note: We would need pr_data here to check PR body mentions
  -- For now, just check comment-based interactions
  local has_recent_interaction = mentions.has_recent_interaction(
    { body = "" }, -- TODO: We'd need to store/fetch PR body for full mention checking
    all_comments,
    nil, -- assignments (not implemented yet)
    current_user,
    3 -- 3 day threshold
  )
  
  if has_recent_interaction then
    log.info("PR " .. pr_id .. " not safe to remove: recent interaction within 3 days")
    return false
  end
  
  -- Safe to remove if no recent interactions
  log.info("PR " .. pr_id .. " safe to remove: no recent interactions")
  return true
end

return M