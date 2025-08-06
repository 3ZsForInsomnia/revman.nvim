local M = {}

local with_db = require("revman.db.create").with_db
local status = require("revman.db.status")
local log = require("revman.log")

local defaultSort = { desc = { "number" } }

function M.add(pr)
	with_db(function(db)
		if not pr.last_synced then
			pr.last_synced = os.date("!%Y-%m-%dT%H:%M:%SZ")
		end

		if not pr.review_status_id then
			pr.review_status_id = status.get_id("waiting_for_review")
		end

		local ok, err = pcall(function()
			db:insert("pull_requests", pr)
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

function M.set_review_status(pr_id, status_name)
	local status_id = status.get_id(status_name)
	if not status_id then
		log.error("db_prs.set_review_status: Unknown status: " .. status_name)
		return false
	end

	return with_db(function(db)
		-- Get old status before updating
		local pr = db:select("pull_requests", { where = { id = pr_id } })[1]
		local old_status = pr and status.get_name(pr.review_status_id) or nil

		db:update("pull_requests", { set = { review_status_id = status_id }, where = { id = pr_id } })

		M.maybe_transition_status(pr_id, old_status, status_name)
		return true
	end)
end

function M.update(id, updates)
	if not id then
		error("db_prs.update: id is nil")
	end
	if not updates or vim.tbl_isempty(updates) then
		error("db_prs.update: updates table is empty")
	end

	with_db(function(db)
		db:update("pull_requests", { set = updates, where = { id = id } })
	end)
end

function M.get_review_status(pr_id)
	local pr = M.get_by_id(pr_id)
	if not pr then
		return nil, "PR not found"
	end
	return status.get_name(pr.review_status_id)
end

function M.list(opts)
	return with_db(function(db)
		local query_opts = {}
		if opts then
			query_opts.where = opts.where
			query_opts.order_by = opts.order_by
		end
		if not query_opts.order_by then
			query_opts.order_by = defaultSort
		end
		local rows = db:select("pull_requests", query_opts)
		return rows
	end)
end

function M.list_with_status(opts)
	return with_db(function(db)
		local query_opts = {}
		if opts then
			query_opts.where = opts.where
			query_opts.order_by = opts.order_by
		end
		if not query_opts.order_by then
			query_opts.order_by = defaultSort
		end
		local rows = db:select("pull_requests", query_opts)
		for _, pr in ipairs(rows) do
			pr.review_status = status.get_name(pr.review_status_id)
		end
		return rows
	end)
end

function M.list_open(opts)
	return with_db(function(db)
		local query_opts = {}
		query_opts.where = { state = "OPEN" }
		if opts and opts.order_by then
			query_opts.order_by = opts.order_by
		else
			query_opts.order_by = defaultSort
		end
		local rows = db:select("pull_requests", query_opts)
		return rows
	end)
end

function M.list_merged(opts)
	return with_db(function(db)
		local query_opts = {}
		query_opts.where = { state = "MERGED" }
		if opts and opts.order_by then
			query_opts.order_by = opts.order_by
		else
			query_opts.order_by = defaultSort
		end
		local rows = db:select("pull_requests", query_opts)
		return rows
	end)
end

M.maybe_transition_status = function(pr_id, old_status, new_status)
	if not new_status or new_status == old_status then
		return
	end

	M.set_review_status(pr_id, new_status)

	local from_id = status.get_id(old_status)
	local to_id = status.get_id(new_status)

	status.add_status_transition(pr_id, from_id, to_id)
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
