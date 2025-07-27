local M = {}

local db_prs = require("revman.db.prs")

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
	local prs = db_prs.list_open()
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

return M
