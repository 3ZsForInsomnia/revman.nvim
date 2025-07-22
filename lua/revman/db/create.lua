local M = {}

local log = require("revman.log")

local has_sqlite, sqlite = pcall(require, "sqlite.db")
if not has_sqlite then
	vim.notify("revman.nvim requires kkharji/sqlite.lua to function properly", vim.log.levels.ERROR)
	return M
end

local config = require("revman.config")

M.get_db = function()
	local db_path = config.get().database.path

	return sqlite:open(db_path)
end

M.ensure_schema = function()
	local db_path = config.get().database.path
	log.info("Using database file: " .. db_path)

	local db_dir = db_path:match("(.+)/[^/]+$")
	if db_dir and not vim.loop.fs_stat(db_dir) then
		vim.fn.mkdir(db_dir, "p")
	end

	local db, err = M.get_db()
	if not db then
		log.error("Failed to create DB: " .. tostring(err))
		return
	else
		log.info("DB opened successfully")
	end

	local stmts = {
		[[
		CREATE TABLE IF NOT EXISTS repositories (
			id INTEGER PRIMARY KEY,
			name TEXT NOT NULL UNIQUE,
			reminder_days INTEGER DEFAULT 3,
			directory TEXT NOT NULL
		)
		]],
		[[
		CREATE TABLE IF NOT EXISTS review_status (
			id INTEGER PRIMARY KEY,
			name TEXT NOT NULL UNIQUE
		)
		]],
		[[
		CREATE TABLE IF NOT EXISTS pull_requests (
			id INTEGER PRIMARY KEY,
			repo_id INTEGER NOT NULL,
			number INTEGER NOT NULL,
			title TEXT NOT NULL,
      description TEXT,
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
			review_status_id INTEGER,
			comment_count INTEGER DEFAULT 0,
			UNIQUE(repo_id, number),
			FOREIGN KEY(repo_id) REFERENCES repositories(id),
			FOREIGN KEY(review_status_id) REFERENCES review_status(id)
		)
		]],
		[[
		CREATE TABLE IF NOT EXISTS notes (
			id INTEGER PRIMARY KEY,
			pr_id INTEGER NOT NULL,
			content TEXT,
			updated_at TEXT NOT NULL,
			FOREIGN KEY(pr_id) REFERENCES pull_requests(id)
		)
		]],
		[[
		CREATE TABLE IF NOT EXISTS review_status_history (
			id INTEGER PRIMARY KEY,
			pr_id INTEGER NOT NULL,
			from_status_id INTEGER,
			to_status_id INTEGER,
			timestamp TEXT NOT NULL,
			FOREIGN KEY(pr_id) REFERENCES pull_requests(id),
			FOREIGN KEY(from_status_id) REFERENCES review_status(id),
			FOREIGN KEY(to_status_id) REFERENCES review_status(id)
		)
		]],
	}

	for _, stmt in ipairs(stmts) do
		local _, statement_error = pcall(function()
			db:execute(stmt)
		end)
		if err then
			log.error("DB schema error: " .. tostring(statement_error))
		end
	end

	log.info("DB schema created and verified successfully")

	local statuses = {
		"waiting_for_review",
		"waiting_for_changes",
		"ready_for_re_review",
		"approved",
		"merged",
		"closed",
		"needs_nudge",
	}
	for _, name in ipairs(statuses) do
		db:insert("review_status", { name = name })
	end

	log.info("Review statuses initialized")
	db:close()

	if vim.loop.fs_stat(db_path) then
		log.info("DB file exists after schema creation: " .. db_path)
	else
		log.error("DB file does NOT exist after schema creation: " .. db_path)
	end
end

M.get_review_status_id = function(name)
	local db = M.get_db()
	local rows = db:select("review_status", { where = { name = name } })
	db:close()
	return rows[1] and rows[1].id or nil
end

M.get_review_status_name = function(id)
	local db = M.get_db()
	local rows = db:select("review_status", { where = { id = id } })
	db:close()
	return rows[1] and rows[1].name or nil
end

function M.set_review_status(pr_id, status_name)
	local status_id = M.get_review_status_id(status_name)
	if not status_id then
		return false, "Unknown status: " .. status_name
	end
	local db = M.get_db()
	db:update("pull_requests", { review_status_id = status_id }, { id = pr_id })
	db:close()
	return true
end

function M.get_review_status(pr_id)
	local db = M.get_db()
	local pr = db:select("pull_requests", { where = { id = pr_id } })
	db:close()
	if not pr[1] then
		return nil, "PR not found"
	end
	return M.get_review_status_name(pr[1].review_status_id)
end

return M
