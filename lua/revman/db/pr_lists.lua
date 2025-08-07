local status = require("revman.db.status")
local with_db = require("revman.db.helpers").with_db

local M = {}

local defaultSort = { desc = { "number" } }

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

return M
