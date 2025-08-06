local M = {}

local get_current_repo = function()
	local lines = vim.fn.systemlist("gh repo view --json nameWithOwner -q .nameWithOwner")
	if vim.v.shell_error ~= 0 or #lines == 0 or (lines[1] == "" and #lines == 1) then
		return nil
	end
	return lines[1]:gsub("\n", "")
end

local function gh_json(cmd)
	local lines = vim.fn.systemlist(cmd)
	if vim.v.shell_error ~= 0 or #lines == 0 or (lines[1] == "" and #lines == 1) then
		return nil
	end
	local output = table.concat(lines, "\n")
	local ok, json = pcall(vim.json.decode, output)
	if not ok or not json then
		return nil, "Failed to parse JSON output: " .. output
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
		"number,title,state,url,author,createdAt,isDraft,reviewDecision,statusCheckRollup,body,commits,reviews",
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

local function run_gh_cmd_sync(cmd)
	local lines = vim.fn.systemlist(table.concat(cmd, " "))
	if vim.v.shell_error ~= 0 or #lines == 0 then
		return nil
	end
	local output = table.concat(lines, "\n")
	local ok, json = pcall(vim.json.decode, output)
	if not ok or not json then
		return nil
	end
	return json
end

-- Asynchronous runner
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
			vim.schedule(function()
				callback(ok and json or nil)
			end)
		else
			vim.schedule(function()
				callback(nil)
			end)
		end
	end)
	stdout:read_start(function(err, data)
		assert(not err, err)
		if data then
			table.insert(output, data)
		end
	end)
end

-- Synchronous get_pr
function M.get_pr(pr_number, repo)
	repo = repo or get_current_repo()
	if not repo then
		return nil, "Not in a GitHub repository"
	end
	local pr = run_gh_cmd_sync(get_gh_pr_view_cmd(pr_number, repo))
	if not pr then
		return nil, "Failed to fetch PR metadata"
	end
	local comments = run_gh_cmd_sync(get_gh_comments_cmd(pr_number, repo))
	pr.comment_count = comments and #comments or 0
	return pr
end

-- Synchronous get_all_review_comments
function M.get_all_review_comments(repo, pr_number)
	return run_gh_cmd_sync(get_gh_comments_cmd(pr_number, repo)) or {}
end

-- Asynchronous get_pr
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

	-- Extract CI status if available
	local ci_status = nil
	if pr.statusCheckRollup and pr.statusCheckRollup.state then
		ci_status = pr.statusCheckRollup.state
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
	}
end

return M
