-- Snacks picker integration for revman.nvim
-- This gets loaded when snacks backend is configured and available

local function setup_highlights()
  -- Define custom highlight groups with better colors
  vim.api.nvim_set_hl(0, "RevmanPROpen", { fg = "#6366f1" }) -- Softer blue
  vim.api.nvim_set_hl(0, "RevmanPRMerged", { fg = "#059669" }) -- Softer green  
  vim.api.nvim_set_hl(0, "RevmanPRClosed", { fg = "#dc2626" }) -- Softer red
  vim.api.nvim_set_hl(0, "RevmanPRDraft", { fg = "#d97706" }) -- Softer orange
  vim.api.nvim_set_hl(0, "RevmanAuthorActive", { fg = "#dc2626" }) -- Softer red for very active
  vim.api.nvim_set_hl(0, "RevmanAuthorMedium", { fg = "#d97706" }) -- Softer orange for active
  vim.api.nvim_set_hl(0, "RevmanAuthorLow", { fg = "#6366f1" }) -- Softer blue for contributor
  vim.api.nvim_set_hl(0, "RevmanIcon", { fg = "#64748b" }) -- Neutral gray for icons
  vim.api.nvim_set_hl(0, "RevmanPRNumber", { fg = "#fbbf24", bold = true }) -- Amber/yellow for better visibility on dark themes
end

local highlights_setup = false
local function ensure_highlights()
  if not highlights_setup then
    setup_highlights()
    highlights_setup = true
  end
end

local M = {}

 -- Helper function to format status text nicely
 local function format_status(status)
   if not status then return "N/A" end
   -- Convert snake_case to space-separated and capitalize first letter only
   local formatted = status:gsub("_", " "):lower()
   return formatted:gsub("^%l", string.upper)
 end
 
local function add_pr_preview(pr)
  local ci = require("revman.github.ci")
  local github_prs = require("revman.github.prs")
  local ci_status = pr.ci_status or "unknown"
  local ci_icon = ci.get_status_icon({ status = ci_status })
  
  -- Enhanced preview with icons and colors
  local state_icon = ""
  if github_prs.is_merged(pr) then
    state_icon = "✅"
  elseif pr.state == "CLOSED" then
    state_icon = "❌"
  elseif pr.is_draft and pr.is_draft == 1 then
    state_icon = "📝"
  else
    state_icon = "🔵"
  end
  
  local review_icon = "👁️"
  if pr.review_status == "approved" then
    review_icon = "✅"
  elseif pr.review_status == "changes_requested" then
    review_icon = "❌"
  elseif pr.review_status == "waiting_for_review" then
    review_icon = "👁️"
  elseif pr.review_status == "needs_nudge" then
    review_icon = "🔔"
  end
  
  local preview_text = string.format(
    "# 📋 Pull Request #%s\n\n" ..
    "**%s**\n" ..
    "👤 By %s\n\n" ..
    "## 📊 Status Overview\n\n" ..
    "%s **State:** `%s`\n" ..
    "%s **Review Status:** `%s`\n" ..
    "🚀 **CI Status:** `%s` %s\n\n" ..
    "## ⏰ Timeline & Activity\n\n" ..
    "📅 **Created:** %s\n" ..
    "⏰ **Last Activity:** %s\n\n" ..
    "💬 **Comment Count:** %s",
    pr.number, pr.title, pr.author or "unknown", 
    state_icon, format_status(pr.state),
    review_icon, format_status(pr.review_status), 
    format_status(ci_status), ci_icon,
    pr.created_at, pr.last_activity or "Unknown", pr.comment_count or "0")
  
  local entry_utils = require("revman.picker.entry")
  return vim.tbl_extend("force", pr, {
    text = entry_utils.pr_searchable(pr),
    preview = {
      text = preview_text,
      ft = "markdown"
    }
  })
end

-- Check if snacks picker is available
local function has_snacks()
  local ok, snacks = pcall(require, "snacks")
  if not ok then
    return false
  end
  return snacks.picker ~= nil
end

-- Helper to create snacks picker sources
local function create_source_config(source_name, items, format_fn, preview_fn, on_confirm)
  return {
    source = source_name,
    items = items,
    format = format_fn,
    preview = preview_fn,
    confirm = on_confirm,
    layout = {
      preset = "default",
      preview = true,
    },
    win = {
      preview = { minimal = true },
    },
  }
end
local function format_pr(item, picker)
  ensure_highlights()
  
  -- Use similar format as telescope but without status brackets
  local cmd_utils = require("revman.command-utils")
  local formatted_text = cmd_utils.format_pr_entry(item)
  
  -- Parse the format: "#123 [OPEN] Fix important bug (john.doe)"
  local pr_number, title_and_author = formatted_text:match("^(#%d+)%s+%[[^%]]+%]%s+(.+)$")
  if not pr_number then
    -- Fallback if parsing fails
    return {{ formatted_text, "Normal" }}
  end
  
  local title, author = title_and_author:match("^(.+)%s+%(([^%)]+)%)$")
  if not title then
    title = title_and_author
    author = ""
  end
  
  return {
    { pr_number, "RevmanPRNumber" },
    { " " },
    { title, "Comment" },
    { author ~= "" and (" (" .. author .. ")") or "", "Identifier" },
  }
end

-- Formatter for authors
local function format_author(item, picker)
  ensure_highlights()
  
  local author_stats = item
  local opened = author_stats.prs_opened or 0
  local merged = author_stats.prs_merged or 0
  local comments = author_stats.comments_written or 0
  
  -- Activity level icons and colors
  local activity_icon = ""
  local activity_hl = "RevmanIcon"
  if opened > 20 then
    activity_icon = "🔥" -- fire for very active
    activity_hl = "RevmanAuthorActive"
  elseif opened > 10 then
    activity_icon = "⭐" -- star for active
    activity_hl = "RevmanAuthorMedium"
  elseif opened > 0 then
    activity_icon = "👤" -- person for contributor
    activity_hl = "RevmanAuthorLow"
  else
    activity_icon = "👻" -- ghost for inactive
    activity_hl = "RevmanIcon"
  end
  
  return {
    { activity_icon, activity_hl },
    { " " },
    { author_stats.author or "unknown", "Identifier" },
    { "  " },
    { "📊", "RevmanIcon" },
    { tostring(opened), "Constant" },
    { "  " },
    { "✅", "RevmanIcon" },
    { tostring(merged), "Constant" },
    { "  " },
    { "💬", "RevmanIcon" },
    { tostring(comments), "Constant" },
  }
end

-- Formatter for repositories
local function format_repo(item, picker)
  ensure_highlights()
  
  local repo = item
  return {
    { "📁", "RevmanIcon" },
    { " " },
    { repo.name or "unknown", "Identifier" },
    { "  " },
    { "📂", "RevmanIcon" },
    { repo.directory or "no directory", "Comment" },
  }
end

-- Formatter for notes
local function format_note(item, picker)
  ensure_highlights()
  
  local pr_with_note = item
  local pr_format = format_pr(pr_with_note, picker)
  
  -- Add note icon at the beginning
  table.insert(pr_format, 1, { "📝", "RevmanIcon" })
  table.insert(pr_format, 2, { " " })
  
  local note_preview = ""
  if pr_with_note.note_content then
    local preview = pr_with_note.note_content:match("^%s*(.-)[\n\r]") or pr_with_note.note_content
    if preview and #preview > 0 then
      preview = preview:sub(1, 60) -- First 60 chars
      if #pr_with_note.note_content > 60 then
        preview = preview .. "..."
      end
      note_preview = "  " .. preview
    end
  end
  
  -- Add note preview to the PR format
  table.insert(pr_format, { note_preview, "String" })
  return pr_format
end

-- Main picker functions for snacks

-- List all PRs
function M.prs(opts)
  if not has_snacks() then
    local log = require("revman.log")
    log.error("Snacks picker is not available")
    return
  end

  opts = opts or {}
  local pr_lists = require("revman.db.pr_lists")
  local cmd_utils = require("revman.command-utils")
  local prs = pr_lists.list_with_status()

  -- Create items with proper text field for searching
  local items = {}
  for _, pr in ipairs(prs) do
    table.insert(items, add_pr_preview(pr))
  end

  local snacks = require("snacks")
  snacks.picker.pick({
    items = items,
    format = format_pr,
    preview = "preview", -- Use built-in preview that reads item.preview
    title = "📋 All PRs",
    confirm = function(picker, item)
      picker:close()
      if item then
        cmd_utils.default_pr_select_callback(item)
      end
    end,
    actions = {
      open_browser = function(picker, item)
        if item and item.url then
          local cmd
          if vim.fn.has("mac") == 1 then
            cmd = { "open", item.url }
          elseif vim.fn.has("unix") == 1 then
            cmd = { "xdg-open", item.url }
          elseif vim.fn.has("win32") == 1 then
            cmd = { "start", item.url }
          end
          if cmd then
            vim.fn.jobstart(cmd, { detach = true })
          end
        end
      end,
      set_status = function(picker, item)
        if item then
          local db_status = require("revman.db.status")
          local pr_status = require("revman.db.pr_status")
          local log = require("revman.log")
          local statuses = {}
          for _, s in ipairs(db_status.list()) do
            table.insert(statuses, s.name)
          end
          vim.ui.select(statuses, { prompt = "Set PR Status" }, function(selected_status)
            if selected_status then
              pr_status.set_review_status(item.id, selected_status)
              log.info("PR #" .. item.number .. " status updated to: " .. selected_status)
            end
          end)
        end
      end,
    },
    win = {
      input = {
        keys = {
          ["<C-b>"] = { "open_browser", mode = { "n", "i" } },
          ["<C-s>"] = { "set_status", mode = { "n", "i" } },
        },
      },
    },
  })
end

-- List open PRs
function M.open_prs(opts)
  if not has_snacks() then
    local log = require("revman.log")
    log.error("Snacks picker is not available")
    return
  end

  opts = opts or {}
  local pr_lists = require("revman.db.pr_lists")
  local cmd_utils = require("revman.command-utils")
  local prs = pr_lists.list_with_status({ where = { state = "OPEN" } })

  local items = {}
  for _, pr in ipairs(prs) do
    table.insert(items, add_pr_preview(pr))
  end

  local snacks = require("snacks")
  snacks.picker.pick({
    items = items,
    format = format_pr,
    preview = "preview",
    title = "🔵 Open PRs",
    confirm = function(picker, item)
      picker:close()
      if item then
        cmd_utils.default_pr_select_callback(item)
      end
    end,
  })
end

-- List PRs needing review
function M.prs_needing_review(opts)
  if not has_snacks() then
    local log = require("revman.log")
    log.error("Snacks picker is not available")
    return
  end

  opts = opts or {}
  local db_status = require("revman.db.status")
  local pr_lists = require("revman.db.pr_lists")
  local cmd_utils = require("revman.command-utils")
  local status_id = db_status.get_id("waiting_for_review")
  local prs = pr_lists.list_with_status({ where = { review_status_id = status_id, state = "OPEN" } })

  local items = {}
  for _, pr in ipairs(prs) do
    table.insert(items, add_pr_preview(pr))
  end

  local snacks = require("snacks")
  snacks.picker.pick({
    items = items,
    format = format_pr,
    preview = "preview",
    title = "👁️ PRs Needing Review",
    confirm = function(picker, item)
      picker:close()
      if item then
        cmd_utils.default_pr_select_callback(item)
      end
    end,
  })
end

-- List merged PRs
function M.merged_prs(opts)
  if not has_snacks() then
    local log = require("revman.log")
    log.error("Snacks picker is not available")
    return
  end

  opts = opts or {}
  local pr_lists = require("revman.db.pr_lists")
  local cmd_utils = require("revman.command-utils")
  local prs = pr_lists.list_with_status({
    where = { state = "MERGED" },
    order_by = { desc = { "last_activity" } },
  })

  local items = {}
  for _, pr in ipairs(prs) do
    table.insert(items, add_pr_preview(pr))
  end

  local snacks = require("snacks")
  snacks.picker.pick({
    items = items,
    format = format_pr,
    preview = "preview",
    title = "✅ Merged PRs",
    confirm = function(picker, item)
      picker:close()
      if item then
        cmd_utils.default_pr_select_callback(item)
      end
    end,
  })
end

-- List current user's open PRs
function M.my_open_prs(opts)
  if not has_snacks() then
    local log = require("revman.log")
    log.error("Snacks picker is not available")
    return
  end

  opts = opts or {}
  local utils = require("revman.utils")
  local pr_lists = require("revman.db.pr_lists")
  local cmd_utils = require("revman.command-utils")
  local log = require("revman.log")
  local current_user = utils.get_current_user()
  if not current_user then
    log.error("Could not determine current user")
    return
  end
  local prs = pr_lists.list_with_status({
    where = { state = "OPEN", author = current_user },
  })

  local items = {}
  for _, pr in ipairs(prs) do
    table.insert(items, add_pr_preview(pr))
  end

  local snacks = require("snacks")
  snacks.picker.pick({
    items = items,
    format = format_pr,
    preview = "preview",
    title = "👤 My Open PRs",
    confirm = function(picker, item)
      picker:close()
      if item then
        cmd_utils.default_pr_select_callback(item)
      end
    end,
  })
end

function M.nudge_prs(opts)
  if not has_snacks() then
    local log = require("revman.log")
    log.error("Snacks picker is not available")
    return
  end

  opts = opts or {}
  local db_status = require("revman.db.status")
  local pr_lists = require("revman.db.pr_lists")
  local cmd_utils = require("revman.command-utils")
  local log = require("revman.log")
  local status_id = db_status.get_id("needs_nudge")
  local prs = pr_lists.list_with_status({ where = { review_status_id = status_id } })
  if #prs == 0 then
    log.notify("No PRs need a nudge!", "info")
    log.info("No PRs need a nudge")
    return
  end

  local items = {}
  for _, pr in ipairs(prs) do
    table.insert(items, add_pr_preview(pr))
  end

  local snacks = require("snacks")
  snacks.picker.pick({
    items = items,
    format = format_pr,
    preview = "preview",
    title = "🔔 PRs Needing a Nudge",
    confirm = function(picker, item)
      picker:close()
      if item then
        cmd_utils.default_pr_select_callback(item)
      end
    end,
  })
end

-- List PRs where current user is mentioned
function M.mentioned_prs(opts)
  if not has_snacks() then
    local log = require("revman.log")
    log.error("Snacks picker is not available")
    return
  end

  opts = opts or {}
  local utils = require("revman.utils")
  local pr_lists = require("revman.db.pr_lists")
  local cmd_utils = require("revman.command-utils")
  local log = require("revman.log")
  local current_user = utils.get_current_user()
  if not current_user then
    log.error("Could not determine current user")
    return
  end
  local prs = pr_lists.list_mentioned_prs(current_user, {
    where = { state = "OPEN" }
  })
  if #prs == 0 then
    log.notify("No open PRs where you are mentioned", "info")
    return
  end

  local items = {}
  for _, pr in ipairs(prs) do
    table.insert(items, add_pr_preview(pr))
  end

  local snacks = require("snacks")
  snacks.picker.pick({
    items = items,
    format = format_pr,
    preview = "preview",
    title = "💬 PRs Where You Are Mentioned",
    confirm = function(picker, item)
      picker:close()
      if item then
        cmd_utils.default_pr_select_callback(item)
      end
    end,
  })
end

-- List recently closed/merged PRs (last week)
function M.recent_prs(opts)
  if not has_snacks() then
    local log = require("revman.log")
    log.error("Snacks picker is not available")
    return
  end

  opts = opts or {}
  local pr_lists = require("revman.db.pr_lists")
  local cmd_utils = require("revman.command-utils")
  local prs = pr_lists.list_recent_closed_merged(7) -- Last 7 days
  if #prs == 0 then
    local log = require("revman.log")
    log.notify("No recently closed/merged PRs found", "info")
    return
  end

  local items = {}
  for _, pr in ipairs(prs) do
    table.insert(items, add_pr_preview(pr))
  end

  local snacks = require("snacks")
  snacks.picker.pick({
    items = items,
    format = format_pr,
    preview = "preview",
    title = "📅 Recent PRs (Last Week)",
    confirm = function(picker, item)
      picker:close()
      if item then
        cmd_utils.default_pr_select_callback(item)
      end
    end,
  })
end
 function M.authors(authors_data, opts)
  if not has_snacks() then
    local log = require("revman.log")
    log.error("Snacks picker is not available")
    return
  end

  opts = opts or {}
  
  -- Use provided authors data or fetch if not provided
  local authors = authors_data
  if not authors or #authors == 0 then
    local author_analytics = require("revman.analytics.authors")
    local author_stats = author_analytics.get_author_analytics()
    authors = {}
    
    for author, stats in pairs(author_stats) do
      stats.author = author -- ensure author field is present for display
      table.insert(authors, stats)
    end
  end

  local items = {}
  for _, author in ipairs(authors) do
    local entry_utils = require("revman.picker.entry")
    
    local preview_text = string.format(
      "# 👤 %s\n\n" ..
      "## 📊 Pull Request Statistics\n\n" ..
      "**PRs Opened:** `%s`\n" ..
      "**PRs Merged:** `%s`\n" ..
      "**PRs Closed (w/o merge):** `%s`\n\n" ..
      "## 📈 Activity Trends\n\n" ..
      "**PRs Opened/Week (avg):** `%.2f`\n" ..
      "**PRs Merged/Week (avg):** `%.2f`\n\n" ..
      "## 💬 Comment Activity\n\n" ..
      "**Total Comments Written:** `%s`\n" ..
      "📝 On own PRs: `%s`\n" ..
      "👥 On others' PRs: `%s`\n" ..
      "**Comments Received:** `%s`\n\n" ..
      "## ⚡ Performance Metrics\n\n" ..
      "**Avg Time to First Comment:** `%s`\n" ..
      "**Avg Review Cycles:** `%.2f`",
      author.author or "unknown",
      author.prs_opened or 0,
      author.prs_merged or 0,
      author.prs_closed_without_merge or 0,
      author.prs_opened_per_week_avg or 0,
      author.prs_merged_per_week_avg or 0,
      author.comments_written or 0,
      author.comments_on_own_prs or 0,
      author.comments_on_others_prs or 0,
      author.comments_received or 0,
      author.avg_time_to_first_comment_human or "N/A",
      author.avg_review_cycles or 0)
    
    table.insert(items, vim.tbl_extend("force", author, {
      text = entry_utils.author_searchable(author),
      preview = {
        text = preview_text,
        ft = "markdown"
      }
    }))
  end

  local snacks = require("snacks")
  snacks.picker.pick({
    items = items,
    format = format_author,
    preview = "preview",
    title = "📊 PR Authors (Analytics)",
    confirm = function(picker, item)
      picker:close()
      -- No default action for authors - could be extended
    end,
  })
end

-- List repositories
function M.repos(opts)
  if not has_snacks() then
    local log = require("revman.log")
    log.error("Snacks picker is not available")
    return
  end

  opts = opts or {}
  local db_repos = require("revman.db.repos")
  local repos = db_repos.list()

  local items = {}
  local entry_utils = require("revman.picker.entry")
  for _, repo in ipairs(repos) do
    table.insert(items, vim.tbl_extend("force", repo, {
      text = entry_utils.repo_searchable(repo)
    }))
  end

  local snacks = require("snacks")
  snacks.picker.pick({
    items = items,
    format = format_repo,
    preview = "none",
    title = "📁 Repositories",
    confirm = function(picker, item)
      picker:close()
      -- No default action for repos - could be extended
    end,
  })
end

-- List PR notes
function M.notes(opts)
  if not has_snacks() then
    local log = require("revman.log")
    log.error("Snacks picker is not available")
    return
  end

  opts = opts or {}
  local pr_lists = require("revman.db.pr_lists")
  local db_notes = require("revman.db.notes")
  local note_utils = require("revman.note-utils")
  local prs = pr_lists.list()
  local prs_with_notes = {}
  
  for _, pr in ipairs(prs) do
    local note = db_notes.get_by_pr_id(pr.id)
    if note and note.content and note.content ~= "" then
      pr.note_content = note.content -- Add note content for searching
      table.insert(prs_with_notes, pr)
    end
  end

  local items = {}
  for _, pr in ipairs(prs_with_notes) do
    local entry_utils = require("revman.picker.entry")
    local db_notes = require("revman.db.notes")
    local note = db_notes.get_by_pr_id(pr.id)
    local note_content = note and note.content or "No note found."
    
    table.insert(items, vim.tbl_extend("force", pr, {
      text = entry_utils.note_searchable(pr),
      preview = {
        text = note_content,
        ft = "markdown"
      }
    }))
  end

  local snacks = require("snacks")
  snacks.picker.pick({
    items = items,
    format = format_note,
    preview = "preview",
    title = "📝 PR Notes",
    confirm = function(picker, item)
      picker:close()
      if item then
        note_utils.open_note_for_pr(item)
      end
    end,
  })
end

return M