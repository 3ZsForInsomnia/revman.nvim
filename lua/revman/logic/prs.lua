local M = {}

function M.upsert_pr(db_prs, db_repos, pr_row)
	local repo = db_repos.get_by_id(pr_row.repo_id)
	if not repo then
		return nil, "Repository not found"
	end

	local pr = db_prs.get_by_repo_and_number(pr_row.repo_id, pr_row.number)
	if pr then
		db_prs.update(pr.id, pr_row)
		return pr.id
	else
		db_prs.add(pr_row)
		local new_pr = db_prs.get_by_repo_and_number(pr_row.repo_id, pr_row.number)
		return new_pr and new_pr.id or nil
	end
end

function M.needs_attention(db_prs, pr_id)
	local pr = db_prs.get_by_id(pr_id)
	if not pr then
		return false
	end
	local status = db_prs.get_review_status(pr_id)
	if status == "waiting_for_review" then
		return true
	elseif status == "waiting_for_changes" then
		return pr.last_activity and pr.last_viewed and pr.last_activity > pr.last_viewed
	end
	return false
end

function M.list_attention_needed(db_prs)
	local all_prs = db_prs.list()
	local result = {}
	for _, pr in ipairs(all_prs) do
		if M.needs_attention(db_prs, pr.id) then
			table.insert(result, pr)
		end
	end
	return result
end

function M.list_prs_needing_nudge(db_prs, db_repos, utils)
	local all_prs = db_prs.list()
	local result = {}
	for _, pr in ipairs(all_prs) do
		local repo = db_repos.get_by_id(pr.repo_id)
		local reminder_days = repo and repo.reminder_days or 3
		local status = db_prs.get_review_status(pr.id)
		if status == "waiting_for_review" or status == "waiting_for_changes" then
			local last_update = pr.last_activity or pr.last_synced
			if last_update then
				local last_update_time = utils.parse_iso8601(last_update)
				if last_update_time and os.difftime(os.time(), last_update_time) > (reminder_days * 86400) then
					table.insert(result, pr)
				end
			end
		end
	end
	return result
end

return M
