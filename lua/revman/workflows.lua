local github_data = require("revman.github.data")
local ci = require("revman.github.ci")
local github_prs = require("revman.github.prs")
local db_prs = require("revman.db.prs")
local pr_lists = require("revman.db.pr_lists")
local pr_status = require("revman.db.pr_status")
local db_repos = require("revman.db.repos")
local db_comments = require("revman.db.comments")
local status = require("revman.db.status")
local logic_prs = require("revman.logic.prs")
local utils = require("revman.utils")
local log = require("revman.log")

local M = {}

-- Batch sync all tracked PRs using a single API call
function M.sync_all_prs_batch(repo_name, sync_all, callback)
	repo_name = repo_name or utils.get_current_repo()
	if not repo_name then
		log.error("No repo specified for sync")
		if callback then callback(false) end
		return
	end

	local repo_row = utils.ensure_repo(repo_name)
	if not repo_row then
		log.error("Could not ensure repo in DB for sync")
		if callback then callback(false) end
		return
	end

	-- Get list of tracked PR numbers from DB
	local query = { where = { repo_id = repo_row.id } }
	if not sync_all then
		query.where.state = "OPEN"
	end

	local tracked_prs = pr_lists.list(query)
	if #tracked_prs == 0 then
		log.info("No tracked PRs to sync for this repo.")
		if callback then callback(true) end
		return
	end
	
	local tracked_numbers = {}
	for _, pr in ipairs(tracked_prs) do
		table.insert(tracked_numbers, pr.number)
	end
	
	log.info("Batch syncing " .. #tracked_numbers .. " PRs...")

	-- Fetch all PRs with detailed data in one call
	local state_filter = sync_all and "all" or "open"
	github_data.list_prs_detailed_async(repo_name, state_filter, function(all_prs_data, fetch_err)
		if not all_prs_data then
			log.error("Failed to fetch PRs: " .. (fetch_err or "unknown error"))
			if callback then callback(false) end
			return
		end
		
		-- Filter to only tracked PRs and process them
		local tracked_set = {}
		for _, num in ipairs(tracked_numbers) do
			tracked_set[num] = true
		end
		
		local errors = {}
		local results = {}
		
		for _, pr_data in ipairs(all_prs_data) do
			if tracked_set[pr_data.number] then
				local ok, pr_id = pcall(function()
					return M.process_pr_data(pr_data, repo_row.id, repo_name)
				end)
				
				if ok and pr_id then
					table.insert(results, pr_id)
				else
					table.insert(errors, "Failed to process PR #" .. pr_data.number .. ": " .. tostring(pr_id))
				end
			end
		end
		
		if #errors > 0 then
			log.error("Some PRs failed to sync: " .. table.concat(errors, "; "))
		else
			log.info("All tracked PRs synced successfully: " .. vim.inspect(results))
			log.notify("Synced " .. #results .. " PRs successfully")
		end
		
		if callback then
			callback(#errors == 0)
		end
	end)
end

-- Process a single PR's data (extracted from batch or individual fetch)
function M.process_pr_data(pr_data, repo_id, repo_name)
	local pr_db_row = github_prs.extract_pr_fields(pr_data)
	pr_db_row.repo_id = repo_id
	
	-- Extract latest activity
	local activity = github_prs.extract_latest_activity(pr_data)
	if activity then
		pr_db_row.last_activity = activity.latest_comment_time or activity.latest_commit_time
	end
	
	local existing_pr = db_prs.get_by_repo_and_number(repo_id, pr_db_row.number)
	local old_status = existing_pr and pr_status.get_review_status(existing_pr.id) or nil
	local new_status = old_status
	
	-- Status transition logic
	if github_prs.is_merged(pr_db_row) then
		new_status = "merged"
	elseif pr_db_row.state == "CLOSED" then
		new_status = "closed"
	elseif pr_db_row.review_decision == "APPROVED" then
		new_status = "approved"
	elseif existing_pr and old_status == "waiting_for_changes" then
		local parse = utils.parse_iso8601
		local status_history = status.get_status_history(existing_pr.id)
		local waiting_for_changes_id = status.get_id("waiting_for_changes")
		local last_waiting_for_changes_ts = nil
		for _, entry in ipairs(status_history) do
			if entry.to_status_id == waiting_for_changes_id then
				last_waiting_for_changes_ts = entry.timestamp
			end
		end
		
		if last_waiting_for_changes_ts then
			local last_changes_ts = parse(last_waiting_for_changes_ts)
			local comment_ts = activity.latest_comment_time and parse(activity.latest_comment_time) or nil
			local commit_ts = activity.latest_commit_time and parse(activity.latest_commit_time) or nil
			
			if (comment_ts and comment_ts > last_changes_ts) or (commit_ts and commit_ts > last_changes_ts) then
				new_status = "waiting_for_review"
			end
		end
	end
	
	-- Extract CI status
	if pr_data.statusCheckRollup and type(pr_data.statusCheckRollup) == "table" then
		pr_db_row.ci_status = ci.extract_ci_status(pr_data.statusCheckRollup)
	end
	
	-- Extract assignees
	local assignees = github_prs.extract_assignees(pr_data)
	
	local pr_id = logic_prs.upsert_pr(db_prs, db_repos, pr_db_row)
	
	-- Ensure PR author exists
	if pr_db_row.author then
		local db_users = require("revman.db.users")
		db_users.find_or_create_with_profile(pr_db_row.author, true)
	end
	
	-- Update assignees
	local pr_assignees = require("revman.db.pr_assignees")
	pr_assignees.replace_assignees_for_pr(pr_id, assignees)
	
	-- Add status history if needed
	local history = status.get_status_history(pr_id)
	if not history or #history == 0 then
		status.add_status_transition(pr_id, nil, pr_db_row.review_status_id)
	end
	
	pr_status.maybe_transition_status(pr_id, old_status, new_status)
	
	-- Sync comments separately (not in batch data)
	github_data.get_all_comments_async(pr_db_row.number, repo_name, function(comments)
		local formatted_comments = {}
		for _, c in ipairs(comments or {}) do
			local author = c.user and c.user.login or "unknown"
			local created_at = c.createdAt or c.created_at
			if author and created_at then
				table.insert(formatted_comments, {
					github_id = c.id,
					author = author,
					created_at = created_at,
					body = c.body,
					in_reply_to_id = c.in_reply_to_id,
				})
				
				if author ~= "unknown" then
					local db_users = require("revman.db.users")
					db_users.find_or_create_with_profile(author, true)
				end
			end
		end
		db_comments.replace_for_pr(pr_id, formatted_comments)
	end)
	
	return pr_id
end

-- Batch sync for repair command - processes in chunks to avoid rate limits
function M.sync_all_prs_repair_batch(repo_name, callback)
	repo_name = repo_name or utils.get_current_repo()
	if not repo_name then
		log.error("No repo specified for sync")
		if callback then callback(false) end
		return
	end
	
	local repo_row = utils.ensure_repo(repo_name)
	if not repo_row then
		log.error("Could not ensure repo in DB for sync")
		if callback then callback(false) end
		return
	end
	
	-- Get all tracked PRs
	local query = { where = { repo_id = repo_row.id } }
	local tracked_prs = pr_lists.list(query)
	
	if #tracked_prs == 0 then
		log.info("No tracked PRs to sync for this repo.")
		if callback then callback(true) end
		return
	end
	
	log.info("Repair: batch syncing " .. #tracked_prs .. " PRs in chunks...")
	log.notify("Syncing " .. #tracked_prs .. " PRs in batches (this may take a while)...")
	
	-- Split into chunks of 50
	local CHUNK_SIZE = 50
	local chunks = {}
	for i = 1, #tracked_prs, CHUNK_SIZE do
		local chunk = {}
		for j = i, math.min(i + CHUNK_SIZE - 1, #tracked_prs) do
			table.insert(chunk, tracked_prs[j])
		end
		table.insert(chunks, chunk)
	end
	
	local total_synced = 0
	local total_errors = 0
	
	-- Process chunks sequentially with delays
	local function process_chunk(chunk_index)
		if chunk_index > #chunks then
			log.info("✓ Repair sync completed: " .. total_synced .. " PRs synced, " .. total_errors .. " errors")
			log.notify("Synced " .. total_synced .. " PRs (" .. total_errors .. " errors)")
			if callback then callback(total_errors == 0) end
			return
		end
		
		local chunk = chunks[chunk_index]
		log.info("Processing chunk " .. chunk_index .. "/" .. #chunks .. " (" .. #chunk .. " PRs)")
		
		-- Sync this chunk using individual calls (batch API might not support state=all filter well)
		local chunk_remaining = #chunk
		local chunk_errors = 0
		
		for _, pr in ipairs(chunk) do
			M.sync_pr(pr.number, repo_name, function(pr_id, err)
				if pr_id then
					total_synced = total_synced + 1
				else
					chunk_errors = chunk_errors + 1
					total_errors = total_errors + 1
				end
				
				chunk_remaining = chunk_remaining - 1
				if chunk_remaining == 0 then
					-- Chunk complete, wait before next chunk
					log.info("Chunk " .. chunk_index .. " complete, waiting 2 seconds...")
					vim.defer_fn(function()
						process_chunk(chunk_index + 1)
					end, 2000)
				end
			end)
		end
	end
	
	process_chunk(1)
end

function M.sync_all_prs(repo_name, sync_all, callback)
	repo_name = repo_name or utils.get_current_repo()
	if not repo_name then
		log.error("No repo specified for sync")
		return
	end

	local repo_row = utils.ensure_repo(repo_name)
	if not repo_row then
		log.error("Could not ensure repo in DB for sync")
		return
	end

	local query = { where = { repo_id = repo_row.id } }
	if not sync_all then
		query.where.state = "OPEN"
	end

	local tracked_prs = pr_lists.list(query)
	if #tracked_prs == 0 then
		log.info("No tracked PRs to sync for this repo.")
		return
	end

	local remaining = #tracked_prs
	local errors = {}
	local results = {}

	for _, pr in ipairs(tracked_prs) do
		M.sync_pr(pr.number, repo_name, function(pr_id, err)
			if pr_id then
				table.insert(results, pr_id)
			else
				table.insert(errors, "Failed to sync PR #" .. pr.number .. ": " .. (err or "unknown error"))
			end

			remaining = remaining - 1
			if remaining == 0 then
				if #errors > 0 then
					log.error("Some PRs failed to sync: " .. table.concat(errors, "; "))
				else
					log.info("All tracked PRs synced successfully: " .. vim.inspect(results))
					log.notify("All tracked PRs synced successfully" .. vim.inspect(results))
				end
				if callback then
					callback(#errors == 0)
				end
			end
		end)
	end
end

function M.sync_pr(pr_number, repo_name, callback)
	repo_name = repo_name or utils.get_current_repo()
	if not repo_name then
		callback(nil, "No repo specified")
		return
	end

	github_data.get_pr_async(pr_number, repo_name, function(pr_data, fetch_err)
		if not pr_data then
			callback(nil, fetch_err or "Failed to fetch PR")
			return
		end

		local pr_db_row = github_prs.extract_pr_fields(pr_data)
		local repo_row, err = utils.ensure_repo(repo_name)
		if not repo_row then
			log.error(err or "Could not ensure repo in DB for sync")
			callback(nil, "Repo not found or could not be created")
			return
		end
		pr_db_row.repo_id = repo_row.id

		-- Extract latest activity (comments/commits)
		local activity = github_prs.extract_latest_activity(pr_data)
		if activity then
			pr_db_row.last_activity = activity.latest_comment_time or activity.latest_commit_time
		end

	local existing_pr = db_prs.get_by_repo_and_number(pr_db_row.repo_id, pr_db_row.number)
	local old_status = existing_pr and pr_status.get_review_status(existing_pr.id) or nil
	local new_status = old_status

	-- Status transition logic
	if github_prs.is_merged(pr_db_row) then
		new_status = "merged"
	elseif pr_db_row.state == "CLOSED" then
		new_status = "closed"
	elseif pr_db_row.review_decision == "APPROVED" then
		new_status = "approved"
		elseif existing_pr and old_status == "waiting_for_changes" then
			local parse = utils.parse_iso8601
			local status_history = status.get_status_history(existing_pr.id)
			local waiting_for_changes_id = status.get_id("waiting_for_changes")
			local last_waiting_for_changes_ts = nil
			for _, entry in ipairs(status_history) do
				if entry.to_status_id == waiting_for_changes_id then
					last_waiting_for_changes_ts = entry.timestamp
				end
			end

			if last_waiting_for_changes_ts then
				local last_changes_ts = parse(last_waiting_for_changes_ts)
				local comment_ts = activity.latest_comment_time and parse(activity.latest_comment_time) or nil
				local commit_ts = activity.latest_commit_time and parse(activity.latest_commit_time) or nil

				if (comment_ts and comment_ts > last_changes_ts) or (commit_ts and commit_ts > last_changes_ts) then
					new_status = "waiting_for_review"
				end
			end
		end

		-- Extract CI status before upserting to ensure it gets saved
		if pr_data.statusCheckRollup and type(pr_data.statusCheckRollup) == "table" then
			pr_db_row.ci_status = ci.extract_ci_status(pr_data.statusCheckRollup)
		end

		-- Extract and sync assignees
		local assignees = github_prs.extract_assignees(pr_data)

		local pr_id = logic_prs.upsert_pr(db_prs, db_repos, pr_db_row)

		-- Ensure PR author exists in users table with profile
		if pr_db_row.author then
			local db_users = require("revman.db.users")
			db_users.find_or_create_with_profile(pr_db_row.author, true)
		end
		-- Update assignee relationships
		local pr_assignees = require("revman.db.pr_assignees")
		pr_assignees.replace_assignees_for_pr(pr_id, assignees)

		local history = status.get_status_history(pr_id)
		if not history or #history == 0 then
			status.add_status_transition(pr_id, nil, pr_db_row.review_status_id)
		end

		pr_status.maybe_transition_status(pr_id, old_status, new_status)

		github_data.get_all_comments_async(pr_number, repo_name, function(comments)
			local formatted_comments = {}
			for _, c in ipairs(comments or {}) do
				local author = c.user and c.user.login or "unknown"
				local created_at = c.createdAt or c.created_at
				if author and created_at then
					table.insert(formatted_comments, {
						github_id = c.id,
						author = author,
						created_at = created_at,
						body = c.body,
						in_reply_to_id = c.in_reply_to_id,
					})
					
					-- Ensure comment author exists in users table with profile
					if author ~= "unknown" then
						local db_users = require("revman.db.users")
						db_users.find_or_create_with_profile(author, true)
					end
				end
			end
			db_comments.replace_for_pr(pr_id, formatted_comments)
		end)

		callback(pr_id, nil)
	end)
end

function M.select_pr_for_review(pr_id)
	local pr = db_prs.get_by_id(pr_id)
	if not pr then
		return nil, "PR not found"
	end

	local now = os.date("!%Y-%m-%dT%H:%M:%SZ")
	db_prs.update(pr.id, { last_viewed = now })

	local old_status = pr_status.get_review_status(pr.id)
	local new_status = old_status
	if old_status == "waiting_for_review" then
		new_status = "waiting_for_changes"
	end
	pr_status.maybe_transition_status(pr.id, old_status, new_status)

	-- Open in Octo (if available)
	vim.cmd(string.format("Octo pr view %d", pr.number))

	return true
end

function M.sync_assigned_prs(repo_name, callback)
  repo_name = repo_name or utils.get_current_repo()
  if not repo_name then
    log.error("No repo specified for assignment sync")
    return
  end

  local config = require("revman.config")
  local assignments = require("revman.logic.assignments")
  local tracking_mode = config.get().assignment_tracking or "smart"
  
  if tracking_mode == "off" then
    if callback then callback(true) end
    return
  end
  
  -- Only auto-add in "smart" and "always" modes, other modes require manual selection
  if tracking_mode == "manual" then
    if callback then callback(true) end
    return
  end
  
  assignments.find_new_assignments(repo_name, function(new_assignments, err)
    if not new_assignments then
      log.error("Failed to find new assignments: " .. (err or "unknown error"))
      if callback then callback(false) end
      return
    end
    
    if #new_assignments == 0 then
      log.info("No new PR assignments found")
      if callback then callback(true) end
      return
    end
    
    log.info("Found " .. #new_assignments .. " new PR assignments")
    
    local remaining = #new_assignments
    local errors = {}
    local results = {}
    
    for _, assignment in ipairs(new_assignments) do
      M.sync_pr(assignment.number, repo_name, function(pr_id, sync_err)
        if pr_id then
          table.insert(results, pr_id)
          log.info("Auto-added assigned PR #" .. assignment.number)
        else
          table.insert(errors, "Failed to sync PR #" .. assignment.number .. ": " .. (sync_err or "unknown error"))
        end
        
        remaining = remaining - 1
        if remaining == 0 then
          if #errors > 0 then
            log.error("Some assigned PRs failed to sync: " .. table.concat(errors, "; "))
          else
            log.notify("Auto-added " .. #results .. " assigned PRs")
          end
          
          -- After adding new assignments, check for removed assignments
          M.handle_removed_assignments(repo_name, function(removal_success)
            if callback then
              callback(#errors == 0 and removal_success)
            end
          end)
        end
      end)
    end
  end)
end

function M.handle_removed_assignments(repo_name, callback)
  local config = require("revman.config")
  local assignments = require("revman.logic.assignments")
  local tracking_mode = config.get().assignment_tracking or "smart"
  
  if tracking_mode == "manual" or tracking_mode == "always" then
    if callback then callback(true) end
    return
  end
  
  assignments.find_removed_assignments(repo_name, function(removed_assignments, err)
    if not removed_assignments then
      log.warn("Failed to check for removed assignments: " .. (err or "unknown error"))
      if callback then callback(false) end
      return
    end
    
    if #removed_assignments == 0 then
      if callback then callback(true) end
      return
    end
    
    log.info("Found " .. #removed_assignments .. " PRs where user is no longer assigned")
    
    local removed_count = 0
    for _, pr in ipairs(removed_assignments) do
      if assignments.should_remove_pr(pr.id, tracking_mode) then
        -- Set status to not_tracked instead of deleting
        local pr_status = require("revman.db.pr_status")
        local status = require("revman.db.status")
        local not_tracked_id = status.get_id("not_tracked")
        if not_tracked_id then
          pr_status.maybe_transition_status(pr.id, nil, "not_tracked")
          removed_count = removed_count + 1
          log.info("Marked PR #" .. pr.number .. " as not_tracked (no longer assigned)")
        else
          log.warn("Cannot mark PR as not_tracked - status not available (database may not be fully initialized)")
        end
      else
        log.info("Keeping PR #" .. pr.number .. " (user has notes or activity)")
      end
    end
    
    if removed_count > 0 then
      log.notify("Marked " .. removed_count .. " unassigned PRs as not tracked")
    end
    
    if callback then callback(true) end
  end)
end

return M
