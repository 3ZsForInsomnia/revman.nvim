local pr_lists = require("revman.pr_lists")
local db_repos = require("revman.db.repos")
local db_comments = require("revman.db.comments")
local github_data = require("revman.github.data")

local function migrate_all_comments()
	local all_prs = pr_lists.list()
	local repos = {}
	for _, repo in ipairs(db_repos.list()) do
		repos[repo.id] = repo
	end

	local total = #all_prs
	local done = 0

	for _, pr in ipairs(all_prs) do
		local repo = repos[pr.repo_id]
		local repo_name = repo and repo.name or nil
		if repo_name then
			github_data.get_comments_async(pr.number, repo_name, function(comments)
				local formatted_comments = {}

				for _, c in ipairs(comments or {}) do
					local body = c.body or ""
					if type(body) ~= "string" then
						body = tostring(body)
					end

					local author = c.user and c.user.login or "unknown"
					local created_at = c.createdAt or c.created_at

					if author and created_at then
						table.insert(formatted_comments, {
							github_id = c.id,
							author = author,
							created_at = created_at,
							body = body,
							in_reply_to_id = c.in_reply_to_id,
						})
					end
				end

				db_comments.replace_for_pr(pr.id, formatted_comments)
				done = done + 1
				if done % 10 == 0 or done == total then
					print(string.format("Synced comments for %d/%d PRs", done, total))
				end
			end)
		end
	end
end

return migrate_all_comments
