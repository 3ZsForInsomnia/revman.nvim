local M = {}

-- Check if GitHub CLI is available and authenticated
function M.is_gh_available()
	local handle = io.popen("command -v gh && gh auth status 2>&1")
	local result = handle:read("*a")
	handle:close()

	return result:match("Logged in to") ~= nil
end

-- Get current repository
function M.get_current_repo()
	local handle = io.popen("gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null")
	local repo = handle:read("*a"):gsub("\n", "")
	handle:close()

	if repo == "" then
		return nil
	end

	return repo
end

-- Get PR details
function M.get_pr_details(pr_number)
	local repo = M.get_current_repo()
	if not repo then
		return nil, "Not in a GitHub repository"
	end

	local handle = io.popen(
		string.format(
			"gh pr view %s --json number,title,url,author,createdAt,state,isDraft,reviewDecision -R %s 2>/dev/null",
			pr_number,
			repo
		)
	)
	local result = handle:read("*a")
	handle:close()

	if result == "" then
		return nil, "PR not found"
	end

	return vim.json.decode(result), nil
end

-- Get PR comments
function M.get_pr_comments(pr_number)
	local repo = M.get_current_repo()
	if not repo then
		return nil, "Not in a GitHub repository"
	end

	local handle = io.popen(string.format("gh pr view %s --json comments -R %s 2>/dev/null", pr_number, repo))
	local result = handle:read("*a")
	handle:close()

	if result == "" then
		return nil, "PR not found or no comments"
	end

	local data = vim.json.decode(result)
	return data.comments, nil
end

-- Get PR commits
function M.get_pr_commits(pr_number)
	local repo = M.get_current_repo()
	if not repo then
		return nil, "Not in a GitHub repository"
	end

	local handle = io.popen(string.format("gh pr view %s --json commits -R %s 2>/dev/null", pr_number, repo))
	local result = handle:read("*a")
	handle:close()

	if result == "" then
		return nil, "PR not found or no commits"
	end

	local data = vim.json.decode(result)
	return data.commits, nil
end

-- Get latest comment and commit times
function M.get_pr_activity(pr_number)
	local repo = M.get_current_repo()
	if not repo then
		return nil, "Not in a GitHub repository"
	end

	local handle = io.popen(string.format("gh pr view %s --json comments,commits -R %s 2>/dev/null", pr_number, repo))
	local result = handle:read("*a")
	handle:close()

	if result == "" then
		return nil, "PR not found"
	end

	local data = vim.json.decode(result)

	-- Find latest comment time
	local latest_comment_time = nil
	if data.comments and #data.comments > 0 then
		for _, comment in ipairs(data.comments) do
			if not latest_comment_time or comment.createdAt > latest_comment_time then
				latest_comment_time = comment.createdAt
			end
		end
	end

	-- Find latest commit time
	local latest_commit_time = nil
	if data.commits and #data.commits > 0 then
		for _, commit in ipairs(data.commits) do
			if not latest_commit_time or commit.committedDate > latest_commit_time then
				latest_commit_time = commit.committedDate
			end
		end
	end

	return {
		latest_comment_time = latest_comment_time,
		latest_commit_time = latest_commit_time,
	}, nil
end

-- Get PRs where user is involved
function M.get_my_prs()
	local repo = M.get_current_repo()
	if not repo then
		return nil, "Not in a GitHub repository"
	end

	local handle = io.popen(
		string.format(
			'gh pr list --json number,title,url,author,createdAt,state,isDraft,reviewDecision --search "involves:@me" -R %s 2>/dev/null',
			repo
		)
	)
	local result = handle:read("*a")
	handle:close()

	if result == "" then
		return {}, "No PRs found"
	end

	return vim.json.decode(result), nil
end

-- Get multiple PRs by number
function M.get_multiple_prs(pr_numbers)
	local results = {}
	local errors = {}

	for _, pr_number in ipairs(pr_numbers) do
		local pr_data, err = M.get_pr_details(pr_number)
		if pr_data then
			results[tostring(pr_number)] = pr_data
		else
			errors[tostring(pr_number)] = err
		end
	end

	return results, errors
end

function M.has_new_activity(pr_number, last_viewed_time)
	local activity, err = M.get_pr_activity(pr_number)
	if not activity then
		return false, err
	end

	-- Check if there are newer comments or commits
	local has_new_comments = activity.latest_comment_time and activity.latest_comment_time > last_viewed_time
	local has_new_commits = activity.latest_commit_time and activity.latest_commit_time > last_viewed_time

	return has_new_comments or has_new_commits, nil
end

return M
