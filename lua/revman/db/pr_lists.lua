local status = require("revman.db.status")
local with_db = require("revman.db.helpers").with_db

local M = {}

local defaultSort = { desc = { "number" } }

function M.list(opts, include_not_tracked)
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

		-- Exclude not_tracked status by filtering in Lua
		-- (sqlite.lua doesn't handle != well with multiple WHERE conditions)
		if not include_not_tracked then
			local not_tracked_id = status.get_id("not_tracked")
			if not_tracked_id then
				local filtered_rows = {}
				for _, row in ipairs(rows) do
					if row.review_status_id ~= not_tracked_id then
						table.insert(filtered_rows, row)
					end
				end
				return filtered_rows
			end
		end

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

		-- Don't use != in SQL (sqlite.lua doesn't handle it well)
		-- Instead, fetch all rows and filter in Lua
		local rows = db:select("pull_requests", query_opts)

		-- Filter out not_tracked status in Lua (unless explicitly requested in where clause)
		local not_tracked_id = status.get_id("not_tracked")
		local filtered_rows = {}

		-- Check if review_status_id was explicitly set in the query
		local explicit_status_filter = opts and opts.where and opts.where.review_status_id ~= nil

		for _, pr in ipairs(rows) do
			-- Skip not_tracked PRs unless explicitly filtered for them
			local should_include = true
			if not_tracked_id and not explicit_status_filter and pr.review_status_id == not_tracked_id then
				should_include = false
			end

			if should_include then
				pr.review_status = status.get_name(pr.review_status_id)
				table.insert(filtered_rows, pr)
			end
		end

		return filtered_rows
	end)
end

function M.list_open(opts)
	return with_db(function(db)
		local query_opts = {
			where = { state = "OPEN" },
		}

		if opts and opts.order_by then
			query_opts.order_by = opts.order_by
		else
			query_opts.order_by = defaultSort
		end

		-- Don't use != in SQL, filter in Lua instead
		local rows = db:select("pull_requests", query_opts)

		-- Filter out not_tracked status in Lua
		local not_tracked_id = status.get_id("not_tracked")
		if not_tracked_id then
			local filtered_rows = {}
			for _, pr in ipairs(rows) do
				if pr.review_status_id ~= not_tracked_id then
					table.insert(filtered_rows, pr)
				end
			end
			return filtered_rows
		end

		return rows
	end)
end

function M.list_merged(opts)
	return with_db(function(db)
		local github_prs = require("revman.github.prs")
		local query_opts = {}

		-- Apply where clause from opts if provided
		if opts and opts.where then
			query_opts.where = opts.where
		end

		-- Note: sqlite.lua doesn't support complex OR in where clause well,
		-- so we query with the where clause and then filter in Lua for merged status
		if opts and opts.order_by then
			query_opts.order_by = opts.order_by
		else
			query_opts.order_by = defaultSort
		end

		local all_rows = db:select("pull_requests", query_opts)

		-- Filter to only merged PRs using our authority function
		local merged_rows = {}
		for _, pr in ipairs(all_rows) do
			if github_prs.is_merged(pr) then
				table.insert(merged_rows, pr)
			end
		end

		return merged_rows
	end)
end

function M.list_assigned_to_user(username, opts)
	return with_db(function(db)
		local users = require("revman.db.users")
		local pr_assignees = require("revman.db.pr_assignees")
		local user = users.get_by_username(username)
		if not user then
			return {}
		end

		-- Get PRs assigned to this user
		local assigned_prs = pr_assignees.get_prs_for_user(user.id)

		-- Filter and sort results
		local filtered_prs = {}
		local not_tracked_id = status.get_id("not_tracked")

		for _, pr in ipairs(assigned_prs) do
			-- Apply state filter if specified
			local include = true
			if opts and opts.where and opts.where.state then
				include = pr.state == opts.where.state
			end

			-- Exclude not_tracked by default
			if include and not_tracked_id and pr.review_status_id == not_tracked_id then
				include = false
			end

			if include then
				table.insert(filtered_prs, pr)
			end
		end

		-- Sort results
		if opts and opts.order_by then
		-- Custom sorting would go here if needed
		else
			-- Default sort by PR number descending
			table.sort(filtered_prs, function(a, b)
				return a.number > b.number
			end)
		end

		-- Add status names
		for _, pr in ipairs(filtered_prs) do
			pr.review_status = status.get_name(pr.review_status_id)
		end

		return filtered_prs
	end)
end

function M.list_mentioned_prs(username, opts)
	return with_db(function(db)
		local users = require("revman.db.users")
		local user = users.get_by_username(username)
		if not user then
			return {}
		end

		-- Note: This function only checks for mentions in PR comments, not in PR body,
		-- since the PR body is not stored in the database schema.
		-- Get all PRs and their comments to check for mentions
		local query_opts = {}

		-- Apply filters from opts
		if opts and opts.where then
			query_opts.where = {}
			for k, v in pairs(opts.where) do
				query_opts.where[k] = v
			end
		end

		if opts and opts.order_by then
			query_opts.order_by = opts.order_by
		else
			query_opts.order_by = defaultSort
		end

		-- Don't use != in SQL, fetch all and filter in Lua
		local all_prs = db:select("pull_requests", query_opts)

		-- Filter out not_tracked and check for mentions
		local not_tracked_id = status.get_id("not_tracked")
		local mentioned_prs = {}
		local mentions = require("revman.mentions")

		for _, pr in ipairs(all_prs) do
			-- Skip not_tracked PRs
			if not_tracked_id and pr.review_status_id == not_tracked_id then
				-- Skip this PR
			else
				local is_mentioned = false

				-- Check if mentioned in any comments
				local comments = db:select("comments", { where = { pr_id = pr.id } })
				for _, comment in ipairs(comments or {}) do
					if comment.body and mentions.is_user_mentioned(comment.body, username) then
						is_mentioned = true
						break
					end
				end

				if is_mentioned then
					pr.review_status = status.get_name(pr.review_status_id)
					table.insert(mentioned_prs, pr)
				end
			end
		end

		return mentioned_prs
	end)
end

function M.list_recent_closed_merged(days_back, opts)
	return with_db(function(db)
		local cutoff_date = os.date("!%Y-%m-%dT%H:%M:%SZ", os.time() - (days_back * 24 * 60 * 60))

		local query_opts = {
			where = {
				state = { "in", { "MERGED", "CLOSED" } },
				last_activity = { ">=", cutoff_date },
			},
		}

		-- Apply additional filters from opts
		if opts and opts.where then
			for k, v in pairs(opts.where) do
				query_opts.where[k] = v
			end
		end

		if opts and opts.order_by then
			query_opts.order_by = opts.order_by
		else
			query_opts.order_by = { desc = { "last_activity" } }
		end

		local rows = db:select("pull_requests", query_opts)
		for _, pr in ipairs(rows) do
			pr.review_status = status.get_name(pr.review_status_id)
		end
		return rows
	end)
end

return M
