local M = {}

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

function M.get_pr(pr_number, repo)
	repo = repo or require("revman.github").get_current_repo()
	if not repo then
		return nil, "Not in a GitHub repository"
	end
	return gh_json(
		string.format(
			"gh pr view %s --json number,title,state,url,author,createdAt,isDraft,reviewDecision,statusCheckRollup,body -R %s",
			pr_number,
			repo
		)
	)
end

function M.list_prs(repo)
	repo = repo or require("revman.github").get_current_repo()
	if not repo then
		return nil, "Not in a GitHub repository"
	end
	return gh_json(
		string.format("gh pr list --json number,title,state,url,author,createdAt,isDraft,reviewDecision -R %s", repo)
	)
end

function M.get_status_check_rollup(pr_number, repo)
	repo = repo or require("revman.github").get_current_repo()
	if not repo then
		return nil, "Not in a GitHub repository"
	end
	return gh_json(string.format("gh pr view %s --json statusCheckRollup -R %s", pr_number, repo))
end

function M.get_current_user()
	return gh_json("gh api user")
end

function M.get_repo_info(repo)
	repo = repo or require("revman.github").get_current_repo()
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
		description = pr.body,
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
