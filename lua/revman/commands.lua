local workflows = require("revman.workflows")
local github_data = require("revman.github.data")
local db_prs = require("revman.db.prs")
local pr_lists = require("revman.db.pr_lists")
local db_status = require("revman.db.status")
local utils = require("revman.utils")
local github_prs = require("revman.github.prs")
local telescope_prs = require("revman.telescope.prs")
local telescope_notes = require("revman.telescope.notes")
local telescope_authors = require("revman.telescope.users")
local note_utils = require("revman.note-utils")
local log = require("revman.log")
local cmd_utils = require("revman.command-utils")

local M = {}

vim.api.nvim_create_user_command("RevmanListPRs", function()
	local prs = pr_lists.list_with_status()
	telescope_prs.pick_prs(prs, nil, "All PRs", cmd_utils.default_pr_select_callback)
end, {})

vim.api.nvim_create_user_command("RevmanListOpenPRs", function()
	local prs = pr_lists.list_with_status({ where = { state = "OPEN" } })
	telescope_prs.pick_prs(prs, nil, "Open PRs", cmd_utils.default_pr_select_callback)
end, {})

vim.api.nvim_create_user_command("RevmanListPRsNeedingReview", function()
	local status_id = db_status.get_id("waiting_for_review")
	local prs = pr_lists.list_with_status({ where = { review_status_id = status_id, state = "OPEN" } })
	telescope_prs.pick_prs(prs, nil, "PRs Needing Review", cmd_utils.default_pr_select_callback)
end, {})

vim.api.nvim_create_user_command("RevmanListMergedPRs", function()
	local prs = pr_lists.list_with_status({
		where = { state = "MERGED" },
		order_by = { desc = { "last_activity" } },
	})
	telescope_prs.pick_prs(prs, nil, "Merged PRs", cmd_utils.default_pr_select_callback)
end, {})

vim.api.nvim_create_user_command("RevmanListAuthors", function()
	telescope_authors.pick_authors_with_preview()
end, {})

vim.api.nvim_create_user_command("RevmanReviewPR", function(opts)
	cmd_utils.with_selected_pr(opts.args, function(pr)
		workflows.select_pr_for_review(pr.id)
	end)
end, { nargs = "?" })

vim.api.nvim_create_user_command("RevmanSetStatus", function(opts)
	cmd_utils.with_selected_pr(opts.fargs[1], function(pr)
		cmd_utils.select_status_and_set(pr, opts.fargs[2])
	end)
end, {
	nargs = "*",
	complete = cmd_utils.status_completion,
})

vim.api.nvim_create_user_command("RevmanSetStatusForCurrentPR", function(opts)
	cmd_utils.with_pr_from_current_buffer(function(pr)
		cmd_utils.select_status_and_set(pr, opts.args)
	end)
end, { nargs = "?" })

vim.api.nvim_create_user_command("RevmanAddNote", function()
	local bufname = vim.api.nvim_buf_get_name(0)
	local pr_number = cmd_utils.extract_pr_number_from_octobuffer(bufname)
	if pr_number then
		local pr = db_prs.get_by_repo_and_number(nil, tonumber(pr_number))
		note_utils.open_note_for_pr(pr)
	else
		local open_prs = pr_lists.list_open()
		local entries = {}
		for _, pr in ipairs(open_prs) do
			table.insert(entries, {
				pr = pr,
				display = cmd_utils.format_pr_entry(pr),
			})
		end
		vim.ui.select(entries, {
			prompt = "Select PR for note",
			format_item = function(item)
				return item.display
			end,
		}, function(choice)
			if choice then
				note_utils.open_note_for_pr(choice.pr)
			end
		end)
	end
end, {})

vim.api.nvim_create_user_command("RevmanShowNotes", function()
	telescope_notes.pick_pr_notes()
end, {})

vim.api.nvim_create_user_command("RevmanNudgePRs", function()
	local status_id = db_status.get_id("needs_nudge")
	local prs = pr_lists.list_with_status({ where = { review_status_id = status_id } })
	if #prs == 0 then
		log.notify("No PRs need a nudge!", "info")
		log.info("No PRs need a nudge")
		return
	end
	telescope_prs.pick_prs(prs, nil, "PRs Needing a Nudge", cmd_utils.default_pr_select_callback)
end, {})

vim.api.nvim_create_user_command("RevmanAddPR", function(opts)
	local pr_number = tonumber(opts.args)
	if not pr_number then
		log.error("Usage: :RevmanAddPR {pr_number}")
		return
	end
	local repo_name = utils.get_current_repo()
	if not repo_name then
		log.error("Could not determine current repo.")
		return
	end
	github_data.get_pr_async(pr_number, repo_name, function(pr_data, err)
		if not pr_data then
			log.error("Could not fetch PR #" .. pr_number .. " from GitHub.")
			return
		end
		local repo_row = utils.ensure_repo(repo_name)
		if not repo_row then
			log.error("Could not ensure repo in DB.")
			return
		end
		local pr_db_row = github_prs.extract_pr_fields(pr_data)
		pr_db_row.repo_id = repo_row.id
		pr_db_row.last_synced = os.date("!%Y-%m-%dT%H:%M:%SZ")
		db_prs.add(pr_db_row)
		log.info("Added PR #" .. pr_number .. " to local database.")
		log.notify("Added PR #" .. pr_number .. " to local database.")
	end)
end, { nargs = 1 })

return M
