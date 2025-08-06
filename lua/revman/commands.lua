local workflows = require("revman.workflows")
local github_data = require("revman.github.data")
local db_prs = require("revman.db.prs")
local db_repos = require("revman.db.repos")
local db_status = require("revman.db.status")
local db_notes = require("revman.db.notes")
local config = require("revman.config")
local utils = require("revman.utils")
local github_prs = require("revman.github.prs")
local telescope_prs = require("revman.telescope.prs")
local telescope_authors = require("revman.telescope.users")
local telescope_repos = require("revman.telescope.repos")
local sync = require("revman.sync")
local log = require("revman.log")
local cmd_utils = require("revman.command-utils")

local M = {}

local function sanitize_status_name(status)
	-- Remove leading/trailing quotes if present
	if type(status) == "string" then
		status = status:gsub('^"(.*)"$', "%1")
	end
	return status
end

vim.api.nvim_create_user_command("RevmanSyncAllPRs", function()
	workflows.sync_all_prs(nil, false, function(success)
		if not success then
			log.error("Some PRs failed to sync.")
		end
	end)
end, {})

vim.api.nvim_create_user_command("RevmanSyncPR", function(opts)
	local pr_number = tonumber(opts.args)

	local sync_fn = function(pr_num)
		workflows.sync_pr(pr_num, nil, function(pr_id, err)
			if err then
				log.error("Error syncing PR #" .. pr_num .. ": " .. err .. ". Make sure the current repo is added!")
			elseif pr_id then
				log.info("PR synced: " .. pr_id)
			end
		end)
	end

	if not pr_number then
		cmd_utils.prompt_select_pr(function(selected_pr)
			if selected_pr then
				sync_fn(selected_pr.number)
			end
		end)
		return
	else
		sync_fn(pr_number)
	end
end, { nargs = 1 })

-- 3. List all PRs (Telescope)
vim.api.nvim_create_user_command("RevmanListPRs", function()
	local prs = db_prs.list_with_status()
	telescope_prs.pick_prs(prs, nil, "All PRs", cmd_utils.default_pr_select_callback)
end, {})

-- 4. List open PRs (Telescope)
vim.api.nvim_create_user_command("RevmanListOpenPRs", function()
	local prs = db_prs.list_with_status({ where = { state = "OPEN" } })
	telescope_prs.pick_prs(prs, nil, "Open PRs", cmd_utils.default_pr_select_callback)
end, {})

vim.api.nvim_create_user_command("RevmanListPRsNeedingReview", function()
	local status_id = db_status.get_id("waiting_for_review")
	local prs = db_prs.list_with_status({ where = { review_status_id = status_id, state = "OPEN" } })
	telescope_prs.pick_prs(prs, nil, "PRs Needing Review", cmd_utils.default_pr_select_callback)
end, {})

-- 5. List merged PRs (Telescope)
vim.api.nvim_create_user_command("RevmanListMergedPRs", function()
	local prs = db_prs.list_with_status({
		where = { state = "MERGED" },
		order_by = { desc = { "merged_at" } },
	})
	telescope_prs.pick_prs(prs, nil, "Merged PRs", cmd_utils.default_pr_select_callback)
end, {})

vim.api.nvim_create_user_command("RevmanListRepos", function()
	telescope_repos.pick_repos()
end, {})

-- 7. List authors (Telescope)
vim.api.nvim_create_user_command("RevmanListAuthors", function()
	telescope_authors.pick_authors_with_preview()
end, {})

vim.api.nvim_create_user_command("RevmanReviewPR", function(opts)
	cmd_utils.resolve_pr(opts.args, function(pr)
		if not pr then
			local pr_number = tonumber(opts.args)
			if pr_number then
				local repo_name = utils.get_current_repo()
				github_data.get_pr_async(pr_number, repo_name, function(pr_data, err)
					if pr_data then
						local repo_row = utils.ensure_repo(repo_name)
						local pr_db_row = github_prs.extract_pr_fields(pr_data)
						pr_db_row.repo_id = repo_row.id
						pr_db_row.last_synced = os.date("!%Y-%m-%dT%H:%M:%SZ")
						db_prs.add(pr_db_row)
						pr = db_prs.get_by_repo_and_number(repo_row.id, pr_number)
						if not pr then
							log.error("No PR selected or found.")
							return
						end
						workflows.select_pr_for_review(pr.id)
					else
						log.error("No PR selected or found.")
					end
				end)
				return
			end
			log.error("No PR selected or found.")
			return
		end
		workflows.select_pr_for_review(pr.id)
	end)
end, { nargs = "?" })

vim.api.nvim_create_user_command("RevmanSetStatus", function(opts)
	local status_arg = opts.fargs[2]
	cmd_utils.resolve_pr(opts.fargs[1], function(pr)
		if not pr then
			log.error("No PR selected for status update.")
			return
		end
		local function set_status(status)
			if status then
				status = sanitize_status_name(status)
				db_prs.set_review_status(pr.id, status)
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
	end)
end, {
	nargs = "*",
	complete = function(arglead, cmdline, cursorpos)
		local statuses = {}
		for _, s in ipairs(db_status.list()) do
			if s.name:match("^" .. arglead) then
				table.insert(statuses, s.name)
			end
		end
		return statuses
	end,
})

-- RevmanSetStatusForCurrentPR: for automation/keybindings
vim.api.nvim_create_user_command("RevmanSetStatusForCurrentPR", function(opts)
	local bufname = vim.api.nvim_buf_get_name(0)
	local pr_number = cmd_utils.extract_pr_number_from_octobuffer(bufname)
	if not pr_number then
		log.error("Could not infer PR number from buffer name.")
		return
	end
	local pr = db_prs.get_by_repo_and_number(nil, tonumber(pr_number))
	if not pr then
		log.error("No PR found for number: " .. pr_number)
		return
	end
	local status_arg = opts.args
	local function set_status(status)
		if status then
			status = sanitize_status_name(status)
			db_prs.set_review_status(pr.id, status)
			log.info("PR #" .. pr.number .. " status updated to: " .. status)
		end
	end
	if status_arg and status_arg ~= "" then
		set_status(status_arg)
	else
		local statuses = {}
		for _, s in ipairs(db_status.list()) do
			table.insert(statuses, s.name)
		end
		vim.ui.select(statuses, { prompt = "Select status" }, set_status)
	end
end, { nargs = "?" })

-- 10. Add or update note (open buffer, save with keybinding)
vim.api.nvim_create_user_command("RevmanAddNote", function(opts)
	cmd_utils.resolve_pr(opts.args, function(pr)
		if not pr then
			log.error("No PR selected for note.")
			return
		end
		local note = db_notes.get_by_pr_id(pr.id)
		local buf = vim.api.nvim_create_buf(false, true)
		vim.bo[buf].buftype = "acwrite"
		vim.api.nvim_buf_set_name(buf, "RevmanNote-" .. pr.id)
		if note and note.content then
			vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(note.content, "\n"))
		end
		vim.api.nvim_set_current_buf(buf)
		local save_key = config.get().background.keymaps.save_notes or "<leader>zz"
		vim.keymap.set("n", save_key, function()
			local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
			local content = table.concat(lines, "\n")
			local now = os.date("!%Y-%m-%dT%H:%M:%SZ")
			if note then
				db_notes.update_by_pr_id(pr.id, { content = content, updated_at = now })
			else
				db_notes.add(pr.id, content, now)
			end
			log.info("Note saved for PR #" .. pr.number)
			vim.api.nvim_buf_delete(buf, { force = true })
		end, { buffer = buf })
	end)
end, { nargs = "?" })

-- 11. Show notes for PR
vim.api.nvim_create_user_command("RevmanShowNotes", function(opts)
	cmd_utils.resolve_pr(opts.args, function(pr)
		if not pr then
			log.error("No PR selected for showing notes.")
			return
		end
		local note = db_notes.get_by_pr_id(pr.id)
		if note and note.content then
			vim.cmd("new")
			vim.api.nvim_buf_set_lines(0, 0, -1, false, vim.split(note.content, "\n"))
			vim.api.nvim_buf_set_option(0, "modifiable", false)
		else
			log.info("No note found for PR #" .. pr.number)
		end
	end)
end, { nargs = "?" })

vim.api.nvim_create_user_command("RevmanNudgePRs", function()
	local status_id = db_status.get_id("needs_nudge")
	local prs = db_prs.list_with_status({ where = { review_status_id = status_id } })
	if #prs == 0 then
		log.notify("No PRs need a nudge!", "info")
		log.info("No PRs need a nudge")
		return
	end
	telescope_prs.pick_prs(prs, nil, "PRs Needing a Nudge", cmd_utils.default_pr_select_callback)
end, {})

-- 13. Toggle background sync
vim.api.nvim_create_user_command("RevmanEnableBackgroundSync", function()
	sync.enable_background_sync()
	log.info("Background sync enabled.")
	log.notify("Background sync enabled.")
end, {})

vim.api.nvim_create_user_command("RevmanDisableBackgroundSync", function()
	sync.disable_background_sync()
	log.info("Background sync disabled.")
	log.notify("Background sync disabled.")
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

vim.api.nvim_create_user_command("RevmanAddRepo", function(opts)
	local repo_name, directory
	local args = vim.split(opts.args or "", " ")
	if #args == 0 or args[1] == "" then
		repo_name = utils.get_current_repo()
		directory = vim.fn.getcwd()
	elseif #args == 1 then
		repo_name = args[1]
		directory = vim.fn.getcwd()
	else
		repo_name = args[1]
		directory = args[2]
	end

	if not repo_name or repo_name == "" then
		log.error("Usage: :RevmanAddRepo {repo_url} [directory]")
		return
	end
	if not directory or directory == "" then
		directory = vim.fn.getcwd()
	end

	-- Check for existing repo with same name and directory
	local existing = nil
	for _, repo in ipairs(db_repos.list()) do
		if repo.name == repo_name and repo.directory == directory then
			existing = repo
			break
		end
	end
	if existing then
		log.info("Repo already exists: " .. repo_name .. " (" .. directory .. ")")
		log.notify("Repo already exists: " .. repo_name .. " (" .. directory .. ")")
		return
	end

	db_repos.add(repo_name, directory)
	local repo_row = db_repos.get_by_name(repo_name)
	if repo_row then
		db_repos.update(repo_row.id, { directory = directory })
		log.info("Added repo: " .. repo_name .. " (" .. directory .. ")")
		log.notify("Added repo: " .. repo_name .. " (" .. directory .. ")")
	else
		log.error("Failed to add repo: " .. repo_name)
	end
end, { nargs = "*" })

return M
