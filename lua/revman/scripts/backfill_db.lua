local db_prs = require("revman.db.prs")
local pr_lists = require("revman.db.pr_lists")
local db_repos = require("revman.db.repos")
local github_data = require("revman.github.data")
local github_prs = require("revman.github.prs")
local db_comments = require("revman.db.comments")
local github_user = require("revman.github.user")

local function backfill_db()
	local n = 200 -- how many PRs to backfill
	local repo_name = require("revman.utils").get_current_repo()
	local repo_row = db_repos.get_by_name(repo_name)
	if not repo_row then
		print("Repo not found in DB: " .. repo_name)
		return
	end

	-- 1. Get all PR numbers in DB
	local all_prs = pr_lists.list({ where = { repo_id = repo_row.id } })
	local pr_numbers_in_db = {}
	local min_number = math.huge
	for _, pr in ipairs(all_prs) do
		pr_numbers_in_db[pr.number] = true
		if pr.number < min_number then
			min_number = pr.number
		end
	end

	-- 2. Get current user login
	local user = github_user.extract_user_login(github_data.get_current_user())

	-- 3. Backfill previous n PRs
	for pr_number = min_number - 1, min_number - n, -1 do
		if pr_number < 1 then
			break
		end
		if not pr_numbers_in_db[pr_number] then
			github_data.get_pr_async(pr_number, repo_name, function(pr_data)
				if not pr_data then
					return
				end
				local is_author = pr_data.author and pr_data.author.login == user

				-- Check for approval or comments by user
				local has_approved = false
				local has_commented = false
				if pr_data.reviews then
					for _, review in ipairs(pr_data.reviews) do
						if review.author and review.author.login == user and review.state == "APPROVED" then
							has_approved = true
							break
						end
					end
				end
				if pr_data.comments then
					for _, comment in ipairs(pr_data.comments) do
						if comment.author and comment.author.login == user then
							has_commented = true
							break
						end
					end
				end

				if is_author or has_approved or has_commented then
					-- Add PR to DB
					local pr_db_row = github_prs.extract_pr_fields(pr_data)
					pr_db_row.repo_id = repo_row.id
					db_prs.add(pr_db_row)
					-- Add comments to DB
					if pr_data.comments then
						local formatted_comments = {}
						for _, c in ipairs(pr_data.comments) do
							table.insert(formatted_comments, {
								github_id = c.id,
								author = c.author and c.author.login or "unknown",
								created_at = c.createdAt,
								body = c.body,
							})
						end
						db_comments.bulk_insert(pr_db_row.id, formatted_comments)
					end
					print("Backfilled PR #" .. pr_number)
				end
			end)
		end
	end
end

return backfill_db
