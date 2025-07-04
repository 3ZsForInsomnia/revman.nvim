local M = {}
local config = require("revman.config")

-- Check if sqlite is available
local has_sqlite, sqlite = pcall(require, "sqlite")
if not has_sqlite then
	vim.notify("revman.nvim requires sqlite.lua to function properly", vim.log.levels.ERROR)
	return M
end

local db = nil

-- Initialize the database
function M.init()
	local options = config.get()
	local db_path = options.database.path

	db = sqlite.new(db_path, {
		vfs = "unix",
	})

	-- Create tables if they don't exist
	db:exec([[
    CREATE TABLE IF NOT EXISTS repositories (
      id INTEGER PRIMARY KEY,
      name TEXT NOT NULL UNIQUE
    );

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
      UNIQUE(repo_id, number),
      FOREIGN KEY(repo_id) REFERENCES repositories(id)
    );

    CREATE TABLE IF NOT EXISTS notes (
      id INTEGER PRIMARY KEY,
      pr_id INTEGER NOT NULL,
      content TEXT,
      updated_at TEXT NOT NULL,
      FOREIGN KEY(pr_id) REFERENCES pull_requests(id)
    );
  ]])

	return true
end

-- Get or create repository entry
local function get_or_create_repo(repo_name)
	if not db then
		M.init()
	end

	-- Check if repo exists
	local repo = db:select("repositories", { where = { name = repo_name } })

	if #repo > 0 then
		return repo[1].id
	end

	-- Create new repo
	db:insert("repositories", {
		name = repo_name,
	})

	return db:last_insert_rowid()
end

-- Add a PR to the database
function M.add_pr(pr_details, activity, ci_status)
	if not db then
		M.init()
	end

	local repo_name = pr_details.headRepositoryOwner.login .. "/" .. pr_details.headRepository.name
	local repo_id = get_or_create_repo(repo_name)

	-- Format CI status as JSON string
	local ci_status_json = nil
	if ci_status then
		ci_status_json = vim.json.encode(ci_status)
	end

	-- Find latest activity time
	local last_activity = nil
	if activity then
		if activity.latest_comment_time and activity.latest_commit_time then
			last_activity = activity.latest_comment_time > activity.latest_commit_time and activity.latest_comment_time
				or activity.latest_commit_time
		elseif activity.latest_comment_time then
			last_activity = activity.latest_comment_time
		elseif activity.latest_commit_time then
			last_activity = activity.latest_commit_time
		end
	end

	-- Check if PR already exists
	local existing_pr = db:select("pull_requests", {
		where = {
			repo_id = repo_id,
			number = pr_details.number,
		},
	})

	if #existing_pr > 0 then
		return false, "PR already exists in database"
	end

	-- Insert PR
	local now = os.date("!%Y-%m-%dT%H:%M:%SZ")
	db:insert("pull_requests", {
		repo_id = repo_id,
		number = pr_details.number,
		title = pr_details.title,
		state = pr_details.state,
		url = pr_details.url,
		author = pr_details.author.login,
		created_at = pr_details.createdAt,
		is_draft = pr_details.isDraft and 1 or 0,
		review_decision = pr_details.reviewDecision,
		last_synced = now,
		last_activity = last_activity,
		ci_status = ci_status_json,
	})

	return true
end

-- Update PR information
function M.update_pr(pr_number, pr_details, activity, ci_status)
	if not db then
		M.init()
	end

	local repo_name = pr_details.headRepositoryOwner.login .. "/" .. pr_details.headRepository.name
	local repo_id = get_or_create_repo(repo_name)

	-- Find latest activity time
	local last_activity = nil
	if activity then
		if activity.latest_comment_time and activity.latest_commit_time then
			last_activity = activity.latest_comment_time > activity.latest_commit_time and activity.latest_comment_time
				or activity.latest_commit_time
		elseif activity.latest_comment_time then
			last_activity = activity.latest_comment_time
		elseif activity.latest_commit_time then
			last_activity = activity.latest_commit_time
		end
	end

	-- Format CI status as JSON string
	local ci_status_json = nil
	if ci_status then
		ci_status_json = vim.json.encode(ci_status)
	end

	-- Check if PR exists
	local existing_pr = db:select("pull_requests", {
		where = {
			repo_id = repo_id,
			number = pr_number,
		},
	})

	if #existing_pr == 0 then
		return false, "PR not found in database"
	end

	-- Update PR
	local now = os.date("!%Y-%m-%dT%H:%M:%SZ")
	db:update("pull_requests", {
		title = pr_details.title,
		state = pr_details.state,
		url = pr_details.url,
		is_draft = pr_details.isDraft and 1 or 0,
		review_decision = pr_details.reviewDecision,
		last_synced = now,
		last_activity = last_activity,
		ci_status = ci_status_json,
	}, {
		id = existing_pr[1].id,
	})

	return true
end

-- Get PR information
function M.get_pr(pr_number)
	if not db then
		M.init()
	end

	-- Get current repo from GitHub
	local github = require("revman.github")
	local repo_name = github.get_current_repo()

	if not repo_name then
		return nil, "Not in a GitHub repository"
	end

	local repo = db:select("repositories", { where = { name = repo_name } })
	if #repo == 0 then
		return nil, "Repository not found in database"
	end

	-- Get PR
	local pr = db:select("pull_requests", {
		where = {
			repo_id = repo[1].id,
			number = pr_number,
		},
	})

	if #pr == 0 then
		return nil, "PR not found in database"
	end

	-- Get notes
	local notes = db:select("notes", {
		where = { pr_id = pr[1].id },
	})

	local result = pr[1]

	-- Parse CI status JSON
	if result.ci_status then
		result.ci_status = vim.json.decode(result.ci_status)
	end

	-- Add notes if they exist
	if #notes > 0 then
		result.notes = notes[1].content
	else
		result.notes = ""
	end

	return result
end

-- Get all PR numbers
function M.get_all_pr_numbers()
	if not db then
		M.init()
	end

	-- Get current repo from GitHub
	local github = require("revman.github")
	local repo_name = github.get_current_repo()

	if not repo_name then
		return {}
	end

	local repo = db:select("repositories", { where = { name = repo_name } })
	if #repo == 0 then
		return {}
	end

	-- Get PR numbers
	local prs = db:select("pull_requests", {
		where = { repo_id = repo[1].id },
		columns = { "number" },
	})

	local result = {}
	for _, pr in ipairs(prs) do
		table.insert(result, pr.number)
	end

	return result
end

-- Get PRs with filtering options
function M.get_prs(opts)
	if not db then
		M.init()
	end
	opts = opts or {}

	-- Get current repo from GitHub
	local github = require("revman.github")
	local repo_name = github.get_current_repo()

	if not repo_name then
		return {}, "Not in a GitHub repository"
	end

	local repo = db:select("repositories", { where = { name = repo_name } })
	if #repo == 0 then
		return {}, "Repository not found in database"
	end

	-- Prepare query
	local where_clause = { repo_id = repo[1].id }

	-- Apply filters
	if opts.filter == "open" then
		where_clause.state = "OPEN"
	elseif opts.filter == "merged" then
		where_clause.state = "MERGED"
	elseif opts.filter == "updates" then
		-- Filter will be applied after fetching
	end

	-- Get PRs
	local prs = db:select("pull_requests", { where = where_clause })

	-- Process results
	local results = {}
	for _, pr in ipairs(prs) do
		-- Parse CI status JSON
		if pr.ci_status then
			pr.ci_status = vim.json.decode(pr.ci_status)
		end

		-- Filter for updates if requested
		if opts.filter == "updates" and pr.last_viewed and pr.last_activity then
			if pr.last_activity > pr.last_viewed then
				table.insert(results, pr)
			end
		else
			table.insert(results, pr)
		end
	end

	return results
end

-- Update PR notes
function M.update_pr_notes(pr_number, content)
	if not db then
		M.init()
	end

	-- Get PR ID
	local pr = M.get_pr(pr_number)
	if not pr then
		return false, "PR not found in database"
	end

	-- Check if notes exist
	local notes = db:select("notes", { where = { pr_id = pr.id } })
	local now = os.date("!%Y-%m-%dT%H:%M:%SZ")

	if #notes > 0 then
		-- Update existing notes
		db:update("notes", {
			content = content,
			updated_at = now,
		}, {
			pr_id = pr.id,
		})
	else
		-- Create new notes
		db:insert("notes", {
			pr_id = pr.id,
			content = content,
			updated_at = now,
		})
	end

	return true
end

-- Update PR last viewed time
function M.update_pr_opened_time(pr_number)
	if not db then
		M.init()
	end

	-- Get current repo
	local github = require("revman.github")
	local repo_name = github.get_current_repo()

	if not repo_name then
		return false, "Not in a GitHub repository"
	end

	local repo = db:select("repositories", { where = { name = repo_name } })
	if #repo == 0 then
		return false, "Repository not found in database"
	end

	-- Get PR
	local pr = db:select("pull_requests", {
		where = {
			repo_id = repo[1].id,
			number = pr_number,
		},
	})

	if #pr == 0 then
		return false, "PR not found in database"
	end

	-- Update last viewed time
	local now = os.date("!%Y-%m-%dT%H:%M:%SZ")
	db:update("pull_requests", {
		last_viewed = now,
	}, {
		id = pr[1].id,
	})

	return true
end

-- Clean up old PRs based on retention policy
function M.cleanup_old_prs()
	if not db then
		M.init()
	end

	local options = config.get()
	local retention_days = options.retention.days

	-- If retention is 0, keep forever
	if retention_days == 0 then
		return true
	end

	-- Calculate cutoff date
	local cutoff_date = os.date("!%Y-%m-%dT%H:%M:%SZ", os.time() - (retention_days * 86400))

	-- Delete old merged PRs
	db:delete("pull_requests", {
		state = "MERGED",
		last_activity = { lt = cutoff_date },
	})

	return true
end

-- Add the has_new_activity function to the github.lua module (as suggested)
function M.has_new_activity_since_last_view(pr_number)
	local pr = M.get_pr(pr_number)
	if not pr or not pr.last_viewed or not pr.last_activity then
		return false
	end

	return pr.last_activity > pr.last_viewed
end

return M
