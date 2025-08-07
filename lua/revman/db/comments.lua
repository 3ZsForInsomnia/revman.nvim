local M = {}
local with_db = require("revman.db.helpers").with_db

function M.replace_for_pr(pr_id, comments)
	with_db(function(db)
		db:delete("comments", { pr_id = pr_id })
		for _, c in ipairs(comments) do
			db:insert("comments", {
				pr_id = pr_id,
				github_id = c.github_id,
				author = c.author,
				created_at = c.created_at,
				body = c.body,
			})
		end
	end)
end

function M.add(pr_id, github_id, author, created_at, body)
	with_db(function(db)
		db:insert("comments", {
			pr_id = pr_id,
			github_id = github_id,
			author = author,
			created_at = created_at,
			body = body,
		})
	end)
end

function M.bulk_insert(pr_id, comments)
	with_db(function(db)
		for _, c in ipairs(comments) do
			db:insert("comments", {
				pr_id = pr_id,
				github_id = c.github_id,
				author = c.author,
				created_at = c.created_at,
				body = c.body,
			})
		end
	end)
end

function M.get_by_pr_id(pr_id)
	return with_db(function(db)
		return db:select("comments", { where = { pr_id = pr_id } })
	end)
end

function M.list()
	return with_db(function(db)
		return db:select("comments")
	end)
end

return M
