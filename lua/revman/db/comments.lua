local M = {}
local with_db = require("revman.db.helpers").with_db

local INSERT_SQL = "INSERT INTO comments (pr_id, github_id, author, created_at, body) "
	.. "VALUES (:pr_id, :github_id, :author, :created_at, :body)"

local function insert_comment(db, pr_id, comment)
	db:eval(INSERT_SQL, {
		pr_id = pr_id,
		github_id = comment.github_id,
		author = comment.author,
		created_at = comment.created_at,
		body = comment.body,
	})
end

function M.replace_for_pr(pr_id, comments)
	with_db(function(db)
		db:delete("comments", { pr_id = pr_id })
		for _, c in ipairs(comments) do
			insert_comment(db, pr_id, c)
		end
	end)
end

function M.add(pr_id, github_id, author, created_at, body)
	with_db(function(db)
		insert_comment(db, pr_id, {
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
			insert_comment(db, pr_id, c)
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
