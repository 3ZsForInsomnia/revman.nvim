local M = {}
local has_sqlite, sqlite = pcall(require, "sqlite")
if not has_sqlite then
	vim.notify("revman.nvim requires kkharji/sqlite.lua to function properly", vim.log.levels.ERROR)
	return M
end

local config = require("revman.config")

local function get_db()
	local db_path = config.get().database.path

	return sqlite.new(db_path)
end

M.ensure_schema = function()
	local db = get_db()
	db:exec([[
    CREATE TABLE IF NOT EXISTS repositories (
      id INTEGER PRIMARY KEY,
      name TEXT NOT NULL UNIQUE,
      reminder_days INTEGER DEFAULT 3,
      directory TEXT NOT NULL
    );
    CREATE TABLE IF NOT EXISTS review_status (
      id INTEGER PRIMARY KEY,
      name TEXT NOT NULL UNIQUE
    );
    CREATE TABLE IF NOT EXISTS pull_requests (
      id INTEGER PRIMARY KEY,
      repo_id INTEGER NOT NULL,
      number INTEGER NOT NULL,
      title TEXT NOT NULL,
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
    );
    CREATE TABLE IF NOT EXISTS notes (
      id INTEGER PRIMARY KEY,
      pr_id INTEGER NOT NULL,
      content TEXT,
      updated_at TEXT NOT NULL,
      FOREIGN KEY(pr_id) REFERENCES pull_requests(id)
    );
    CREATE TABLE IF NOT EXISTS review_status_history (
      id INTEGER PRIMARY KEY,
      pr_id INTEGER NOT NULL,
      from_status_id INTEGER,
      to_status_id INTEGER,
      timestamp TEXT NOT NULL,
      FOREIGN KEY(pr_id) REFERENCES pull_requests(id),
      FOREIGN KEY(from_status_id) REFERENCES review_status(id),
      FOREIGN KEY(to_status_id) REFERENCES review_status(id)
    );
  ]])
	db:close()
end

M.ensure_review_statuses = function()
	local db = get_db()
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
	db:close()
end

M.get_review_status_id = function(name)
	local db = get_db()
	local rows = db:select("review_status", { where = { name = name } })
	db:close()
	return rows[1] and rows[1].id or nil
end

M.get_review_status_name = function(id)
	local db = get_db()
	local rows = db:select("review_status", { where = { id = id } })
	db:close()
	return rows[1] and rows[1].name or nil
end

function M.set_review_status(pr_id, status_name)
	local status_id = M.get_review_status_id(status_name)
	if not status_id then
		return false, "Unknown status: " .. status_name
	end
	local db = get_db()
	db:update("pull_requests", { review_status_id = status_id }, { id = pr_id })
	db:close()
	return true
end

function M.get_review_status(pr_id)
	local db = get_db()
	local pr = db:select("pull_requests", { where = { id = pr_id } })
	db:close()
	if not pr[1] then
		return nil, "PR not found"
	end
	return M.get_review_status_name(pr[1].review_status_id)
end

-- Call these at startup
-- ensure_schema()
-- ensure_review_statuses()

return M
