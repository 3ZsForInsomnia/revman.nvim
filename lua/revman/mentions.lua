-- Mention detection and interaction tracking for revman.nvim
local M = {}

local utils = require("revman.utils")
local log = require("revman.log")

-- Extract mentions from text content (PR body, comments, etc.)
function M.extract_mentions(text)
  if not text or text == "" then
    return {}
  end
  
  local mentions = {}
  -- Match @username patterns (GitHub usernames can contain alphanumeric, hyphens, but can't start/end with hyphen)
  for username in text:gmatch("@([%w%-]+[%w]*)") do
    -- Additional validation: GitHub usernames can't be longer than 39 characters
    if #username <= 39 and username:match("^[%w]") then
      mentions[username] = true
    end
  end
  
  -- Convert to array
  local mention_list = {}
  for username, _ in pairs(mentions) do
    table.insert(mention_list, username)
  end
  
  return mention_list
end

-- Check if a specific user is mentioned in text
function M.is_user_mentioned(text, username)
  if not text or not username then
    return false
  end
  
  local mentions = M.extract_mentions(text)
  for _, mentioned_user in ipairs(mentions) do
    if mentioned_user == username then
      return true
    end
  end
  
  return false
end

-- Check if current user is mentioned in PR or comments
function M.check_pr_mentions(pr_data, comments, current_user)
  current_user = current_user or utils.get_current_user()
  if not current_user then
    return false, {}
  end
  
  local mentioned_in = {}
  
  -- Check PR body for mentions
  if pr_data.body and M.is_user_mentioned(pr_data.body, current_user) then
    table.insert(mentioned_in, {
      type = "pr_body",
      author = pr_data.author and pr_data.author.login or "unknown",
      created_at = pr_data.createdAt or pr_data.created_at
    })
  end
  
  -- Check comments for mentions
  if comments then
    for _, comment in ipairs(comments) do
      local comment_body = comment.body
      if comment_body and M.is_user_mentioned(comment_body, current_user) then
        table.insert(mentioned_in, {
          type = comment.comment_type or "comment",
          author = (comment.user and comment.user.login) or comment.author or "unknown",
          created_at = comment.createdAt or comment.created_at,
          comment_id = comment.id
        })
      end
    end
  end
  
  return #mentioned_in > 0, mentioned_in
end

-- Get the most recent interaction timestamp for a PR
function M.get_latest_interaction_time(pr_data, comments, assignments, current_user)
  current_user = current_user or utils.get_current_user()
  if not current_user then
    return nil
  end
  
  local latest_time = nil
  
  -- Helper to update latest time
  local function update_latest(timestamp_str)
    if timestamp_str then
      local timestamp = utils.parse_iso8601(timestamp_str)
      if timestamp and (not latest_time or timestamp > latest_time) then
        latest_time = timestamp
      end
    end
  end
  
  -- Check assignment/review request times (if available)
  -- Note: This would require additional GitHub API calls to get timeline events
  
  -- Check comments by current user
  if comments then
    for _, comment in ipairs(comments) do
      local comment_author = (comment.user and comment.user.login) or comment.author
      if comment_author == current_user then
        update_latest(comment.createdAt or comment.created_at)
      end
    end
  end
  
  -- Check mentions of current user (indicates activity that might prompt interaction)
  local is_mentioned, mentions = M.check_pr_mentions(pr_data, comments, current_user)
  if is_mentioned then
    for _, mention in ipairs(mentions) do
      update_latest(mention.created_at)
    end
  end
  
  return latest_time
end

-- Check if a PR has recent interaction (within days threshold)
function M.has_recent_interaction(pr_data, comments, assignments, current_user, days_threshold)
  days_threshold = days_threshold or 3
  
  local latest_interaction = M.get_latest_interaction_time(pr_data, comments, assignments, current_user)
  if not latest_interaction then
    return false
  end
  
  local current_time = os.time()
  local days_since = (current_time - latest_interaction) / (24 * 60 * 60)
  
  return days_since <= days_threshold
end

return M