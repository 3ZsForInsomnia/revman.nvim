local M = {}

local with_db = require("revman.db.helpers").with_db
local status = require("revman.db.status")
local log = require("revman.log")

-- sqlite.lua's stmt:bind has a heuristic that treats any string matching
-- `^[%S]+%(.*%)$` as a raw SQL function call (e.g. `datetime('now')`) and
-- silently skips binding it, leaving the parameter NULL. PR titles like
-- `feat(btx): ... (XTRM-1614)` match that pattern and get nulled out, which
-- trips the NOT NULL constraint on `pull_requests.title`. Append a trailing
-- space when the value matches so the heuristic no longer fires. Trailing
-- whitespace is harmless for display.
local function dodge_sqlite_fncall_heuristic(value)
	if type(value) == "string" and value:match("^[%S]+%(.*%)$") then
		return value .. " "
	end
	return value
end

local INSERT_SQL = "INSERT INTO pull_requests "
	.. "(repo_id, number, title, state, url, author, created_at, is_draft, "
	.. "review_decision, last_synced, last_viewed, last_activity, ci_status, "
	.. "review_status_id, comment_count, merged_by, merged_at) "
	.. "VALUES (:repo_id, :number, :title, :state, :url, :author, :created_at, :is_draft, "
	.. ":review_decision, :last_synced, :last_viewed, :last_activity, :ci_status, "
	.. ":review_status_id, :comment_count, :merged_by, :merged_at)"

function M.add(pr)
	with_db(function(db)
		if not pr.last_synced then
			pr.last_synced = os.date("!%Y-%m-%dT%H:%M:%SZ")
		end

		if not pr.review_status_id then
			pr.review_status_id = status.get_id("waiting_for_review")
		end

		local ok, err = pcall(function()
			db:eval(INSERT_SQL, {
				repo_id = pr.repo_id,
				number = pr.number,
				title = dodge_sqlite_fncall_heuristic(pr.title),
				state = pr.state,
				url = pr.url,
				author = pr.author,
				created_at = pr.created_at,
				is_draft = pr.is_draft,
				review_decision = pr.review_decision,
				last_synced = pr.last_synced,
				last_viewed = pr.last_viewed,
				last_activity = pr.last_activity,
				ci_status = pr.ci_status,
				review_status_id = pr.review_status_id,
				comment_count = pr.comment_count,
				merged_by = pr.merged_by,
				merged_at = pr.merged_at,
			})
		end)
		if not ok and tostring(err):match("UNIQUE constraint failed") then
			vim.schedule(function()
				log.notify("PR already exists in the database.")
			end)
		elseif not ok then
			error(err)
		else
			local inserted_pr = db:select("pull_requests", { where = { repo_id = pr.repo_id, number = pr.number } })[1]
			if inserted_pr and inserted_pr.id then
				status.add_status_transition(inserted_pr.id, nil, inserted_pr.review_status_id)
			end

			log.info("Added PR #" .. pr.number .. " to local database.")
			log.notify("Added PR #" .. pr.number .. " to local database.")
		end
	end)
end

function M.get_by_id(id)
	return with_db(function(db)
		local rows = db:select("pull_requests", { where = { id = id } })
		return rows[1]
	end)
end

function M.get_by_repo_and_number(repo_id, number)
	return with_db(function(db)
		local rows = db:select("pull_requests", { where = { repo_id = repo_id, number = number } })
		return rows[1]
	end)
end

function M.update(id, updates)
	if not id then
		error("db_prs.update: id is nil")
	end
	if not updates or vim.tbl_isempty(updates) then
		error("db_prs.update: updates table is empty")
	end

	if updates.title then
		updates.title = dodge_sqlite_fncall_heuristic(updates.title)
	end

	with_db(function(db)
		db:update("pull_requests", { set = updates, where = { id = id } })
	end)
end

function M.count_comments_by(user)
	local sql = [[SELECT COUNT(*) FROM comments WHERE author = ?]]
	return db.scalar(sql, user)
end

function M.comments_per_week(user)
	local sql = [[
    SELECT strftime('%Y-%W', created_at) as week, COUNT(*) as count
    FROM comments
    WHERE author = ?
    GROUP BY week
    ORDER BY week DESC
    LIMIT 8
  ]]
	local rows = db.query(sql, user)
	local total, weeks = 0, 0
	for _, row in ipairs(rows) do
		total = total + row.count
		weeks = weeks + 1
	end
	if weeks == 0 then
		return 0
	end
	return math.floor(total / weeks)
end

return M
