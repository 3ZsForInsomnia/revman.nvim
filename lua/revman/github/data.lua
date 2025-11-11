local M = {}

local log = require("revman.log")

local get_current_repo = function()
	local lines = vim.fn.systemlist("gh repo view --json nameWithOwner -q .nameWithOwner")
	if vim.v.shell_error ~= 0 then
		log.error("Failed to get current repo (gh CLI error): " .. (lines[1] or "unknown error"))
		return nil
	end
	if #lines == 0 or (lines[1] == "" and #lines == 1) then
		log.warn("No repository found in current directory")
		return nil
	end
	return lines[1]:gsub("\n", "")
end

local function gh_json(cmd)
	local lines = vim.fn.systemlist(cmd)
	if vim.v.shell_error ~= 0 then
		local error_msg = #lines > 0 and lines[1] or "unknown error"
		log.error("GitHub CLI command failed: " .. cmd .. " - " .. error_msg)
		log.notify("GitHub CLI error: " .. error_msg, { title = "Revman Error", icon = "❌" })
		return nil, error_msg
	end
	if #lines == 0 or (lines[1] == "" and #lines == 1) then
		log.warn("GitHub CLI returned empty response for: " .. cmd)
		return nil
	end
	local output = table.concat(lines, "\n")
	local ok, json = pcall(vim.json.decode, output)
	if not ok or not json then
		local parse_error = "Failed to parse JSON output from: " .. cmd .. " - " .. output
		log.error(parse_error)
		log.notify("JSON parse error from GitHub CLI", { title = "Revman Error", icon = "❌" })
		return nil, parse_error
	end
	return json
end

local function get_gh_pr_view_cmd(pr_number, repo)
	return {
		"gh",
		"pr",
		"view",
		tostring(pr_number),
		"--json",
		"number,title,state,url,author,createdAt,isDraft,reviewDecision,statusCheckRollup,body,commits,reviews,assignees,mergedBy,mergedAt",
		"-R",
		repo,
	}
end

local function get_gh_comments_cmd(pr_number, repo)
	return {
		"gh",
		"api",
		"-H",
		"Accept: application/vnd.github+json",
		string.format("/repos/%s/pulls/%s/comments", repo, pr_number),
	}
end

local function get_gh_issue_comments_cmd(pr_number, repo)
	return {
		"gh",
		"api",
		"-H",
		"Accept: application/vnd.github+json",
		string.format("/repos/%s/issues/%s/comments", repo, pr_number),
	}
end

local function run_gh_cmd_async(cmd, callback)
	local stdout = vim.loop.new_pipe(false)
	local output = {}
	local handle
	handle = vim.loop.spawn(cmd[1], {
		args = { unpack(cmd, 2) },
		stdio = { nil, stdout, nil },
	}, function(code)
		stdout:close()
		handle:close()
		if code == 0 then
			local json_str = table.concat(output)
			local ok, json = pcall(vim.json.decode, json_str)
			if not ok then
				local parse_error = "Failed to parse JSON from gh command: " .. table.concat(cmd, " ") .. " - " .. json_str
				log.error(parse_error)
				log.notify("GitHub CLI JSON parse error", { title = "Revman Error", icon = "❌" })
			end
			vim.schedule(function()
				callback(ok and json or nil)
			end)
		else
			local error_output = table.concat(output)
			local cmd_str = table.concat(cmd, " ")
			log.error("GitHub CLI command failed (exit code " .. code .. "): " .. cmd_str .. " - " .. error_output)
			log.notify("GitHub CLI command failed: " .. (error_output ~= "" and error_output or "exit code " .. code), 
				{ title = "Revman Error", icon = "❌" })
			vim.schedule(function()
				callback(nil, "Command failed with exit code " .. code .. ": " .. error_output)
			end)
		end
	end)
	stdout:read_start(function(err, data)
		if err then
			log.error("Error reading from gh command stdout: " .. err)
			return
		end
		if data then
			table.insert(output, data)
		end
	end)
end

function M.get_comments_async(pr_number, repo, callback)
	run_gh_cmd_async(get_gh_comments_cmd(pr_number, repo), callback)
end

function M.get_issue_comments_async(pr_number, repo, callback)
	run_gh_cmd_async(get_gh_issue_comments_cmd(pr_number, repo), callback)
end

function M.get_all_comments_async(pr_number, repo, callback)
	-- Get both review comments and regular PR comments
	M.get_comments_async(pr_number, repo, function(review_comments)
		M.get_issue_comments_async(pr_number, repo, function(issue_comments)
			local all_comments = {}
			
			-- Add review comments
			if review_comments then
				for _, comment in ipairs(review_comments) do
					comment.comment_type = "review"
					table.insert(all_comments, comment)
				end
			end
			
			-- Add issue comments  
			if issue_comments then
				for _, comment in ipairs(issue_comments) do
					comment.comment_type = "issue"
					table.insert(all_comments, comment)
				end
			end
			
			callback(all_comments)
		end)
	end)
end

function M.get_pr_async(pr_number, repo, callback)
	repo = repo or get_current_repo()
	if not repo then
		vim.schedule(function()
			callback(nil, "Not in a GitHub repository")
		end)
		return
	end
	run_gh_cmd_async(get_gh_pr_view_cmd(pr_number, repo), function(pr)
		if not pr then
			callback(nil, "Failed to fetch PR metadata")
			return
		end
		run_gh_cmd_async(get_gh_comments_cmd(pr_number, repo), function(comments)
			pr.comment_count = comments and #comments or 0
			callback(pr)
		end)
	end)
end

function M.list_prs(repo)
	repo = repo or get_current_repo()
	if not repo then
		return nil, "Not in a GitHub repository"
	end

	return gh_json(
		string.format("gh pr list --json number,title,state,url,author,createdAt,isDraft,reviewDecision -R %s", repo)
	)
end

-- List PRs with all detailed fields in one call (efficient for syncing)
function M.list_prs_detailed(repo, state_filter)
	repo = repo or get_current_repo()
	if not repo then
		return nil, "Not in a GitHub repository"
	end
	
	local fields = "number,title,state,url,author,createdAt,isDraft,reviewDecision,statusCheckRollup,commits,reviews,assignees,mergedBy,mergedAt"
	local cmd = string.format("gh pr list --json %s -R %s", fields, repo)
	
	-- Add state filter if specified
	if state_filter then
		cmd = cmd .. " --state " .. state_filter
	end
	
	-- Limit to reasonable batch size
	cmd = cmd .. " --limit 1000"
	
	return gh_json(cmd)
end

-- Async version for batch PR sync
function M.list_prs_detailed_async(repo, state_filter, callback)
	repo = repo or get_current_repo()
	if not repo then
		vim.schedule(function()
			callback(nil, "Not in a GitHub repository")
		end)
		return
	end
	
	local fields = "number,title,state,url,author,createdAt,isDraft,reviewDecision,statusCheckRollup,commits,reviews,assignees,mergedBy,mergedAt"
	local cmd = {
		"gh", "pr", "list",
		"--json", fields,
		"-R", repo,
		"--limit", "1000"
	}
	
	if state_filter then
		table.insert(cmd, "--state")
		table.insert(cmd, state_filter)
	end
	
	run_gh_cmd_async(cmd, callback)
end

function M.get_assigned_prs(repo)
	repo = repo or get_current_repo()
	if not repo then
		return nil, "Not in a GitHub repository"
	end

	return gh_json(
		string.format("gh pr list --search \"assignee:@me OR review-requested:@me\" --json number,title,state,url,author,createdAt,isDraft,reviewDecision,assignees -R %s", repo)
	)
end

function M.get_assigned_prs_async(repo, callback)
	repo = repo or get_current_repo()
	if not repo then
		vim.schedule(function()
			callback(nil, "Not in a GitHub repository")
		end)
		return
	end
	
	local cmd = {
		"gh", "pr", "list",
		"--search", "assignee:@me OR review-requested:@me",
		"--json", "number,title,state,url,author,createdAt,isDraft,reviewDecision,assignees",
		"-R", repo
	}
	
	run_gh_cmd_async(cmd, callback)
end

function M.get_status_check_rollup(pr_number, repo)
	repo = repo or get_current_repo()
	if not repo then
		return nil, "Not in a GitHub repository"
	end
	return gh_json(string.format("gh pr view %s --json statusCheckRollup -R %s", pr_number, repo))
end

function M.get_current_user()
	return gh_json("gh api user")
end

function M.get_repo_info(repo)
	repo = repo or get_current_repo()
	if not repo then
		return nil, "Not in a GitHub repository"
	end
	return gh_json(string.format("gh repo view %s --json name,owner,url", repo))
end

function M.convert_pr_to_db(pr, repo_id)
	if not pr or not repo_id then
		return nil
	end

	local ci = require("revman.github.ci")

	-- Extract CI status if available
	local ci_status = nil
	if pr.statusCheckRollup and type(pr.statusCheckRollup) == "table" then
		ci_status = ci.extract_ci_status(pr.statusCheckRollup)
	end

	return {
		repo_id = repo_id,
		number = pr.number,
		title = pr.title,
		state = pr.state,
		url = pr.url,
		author = pr.author and pr.author.login or nil,
		created_at = pr.createdAt,
		is_draft = pr.isDraft and 1 or 0,
		review_decision = pr.reviewDecision,
		last_synced = os.date("!%Y-%m-%dT%H:%M:%SZ"),
		last_viewed = nil,
		last_activity = nil,
		ci_status = ci_status,
		review_status_id = nil,
		comment_count = 0,
		merged_by = (pr.mergedBy and type(pr.mergedBy) == "table" and pr.mergedBy.login) or nil,
		merged_at = (pr.mergedAt and type(pr.mergedAt) == "string" and pr.mergedAt) or nil,
	}
end

function M.get_canonical_repo_name(repo)
	if repo and repo:find("/") then
		return repo
	end

	local lines = vim.fn.systemlist("gh repo view --json nameWithOwner -q .nameWithOwner")

	if vim.v.shell_error == 0 and lines[1] and lines[1] ~= "" then
		return lines[1]:gsub("\n", "")
	end

	return repo
end

return M
