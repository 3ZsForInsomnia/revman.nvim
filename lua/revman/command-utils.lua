local db_status = require("revman.db.status")
local db_prs = require("revman.db.prs")
local pr_lists = require("revman.db.pr_lists")
local pr_status = require("revman.db.pr_status")
local log = require("revman.log")
local utils = require("revman.utils")

local M = {}

function M.update_last_viewed(pr)
	if pr and pr.id then
		local now = os.date("!%Y-%m-%dT%H:%M:%SZ")
		db_prs.update(pr.id, { last_viewed = now })
	end
end

function M.format_pr_entry(pr)
	return string.format("#%s [%s] %s (%s)", pr.number, pr.state, pr.title, pr.author or "unknown")
end

function M.default_pr_select_callback(pr)
	M.update_last_viewed(pr)
	vim.cmd(string.format("Octo pr edit %d", pr.number))
end

function M.prompt_select_pr(callback)
	local prs = pr_lists.list_open()
	local entries = {}
	for _, pr in ipairs(prs) do
		table.insert(entries, {
			pr = pr,
			display = string.format("#%s [%s] %s (%s)", pr.number, pr.state, pr.title, pr.author or "unknown"),
		})
	end
	vim.ui.select(entries, {
		prompt = "Select PR",
		format_item = function(item)
			return item.display
		end,
	}, function(choice)
		if choice then
			callback(choice.pr)
		end
	end)
end

function M.resolve_pr(pr_arg, callback)
	if pr_arg and pr_arg ~= "" then
		local pr = db_prs.get_by_id(tonumber(pr_arg)) or db_prs.get_by_repo_and_number(nil, tonumber(pr_arg))
		if pr then
			callback(pr)
			return
		end
	end
	M.prompt_select_pr(callback)
end

function M.extract_pr_number_from_octobuffer(bufname)
	-- Match "octo://org/repo/pull/1234"
	local pr_number = bufname:match("octo://[^/]+/[^/]+/pull/(%d+)")
	if pr_number then
		return tonumber(pr_number)
	end
	return nil
end

function M.select_status_and_set(pr, status_arg)
	status_arg = utils.strip_quotes(status_arg)
	local function set_status(status)
		if status then
			pr_status.set_review_status(pr.id, status)
			log.info("PR #" .. pr.number .. " status updated to: " .. status)
		end
	end

	if status_arg then
		set_status(status_arg)
	else
		local statuses = {}

		for _, s in ipairs(db_status.list()) do
			table.insert(statuses, s.name)
		end

		vim.ui.select(statuses, { prompt = "Select status" }, set_status)
	end
end

function M.with_selected_pr(pr_arg, action)
	M.resolve_pr(pr_arg, function(pr)
		if not pr then
			log.error("No PR selected or found.")
			return
		end
		action(pr)
	end)
end

function M.with_pr_from_current_buffer(action)
	local bufname = vim.api.nvim_buf_get_name(0)
	local pr_number = M.extract_pr_number_from_octobuffer(bufname)
	if not pr_number then
		log.error("Could not infer PR number from buffer name.")
		return
	end
	local pr = db_prs.get_by_repo_and_number(nil, tonumber(pr_number))
	if not pr then
		log.error("No PR found for number: " .. pr_number)
		return
	end
	action(pr)
end

function M.status_completion(arglead)
	local statuses = {}
	for _, s in ipairs(db_status.list()) do
		if s.name:match("^" .. arglead) then
			table.insert(statuses, s.name)
		end
	end
	return statuses
end

return M
