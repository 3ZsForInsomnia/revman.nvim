local workflows = require("revman.workflows")
local github_data = require("revman.github.data")
local logic_prs = require("revman.logic.prs")
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

local M = {}

-- Helper: prompt user to select a PR (by number or db id)
local function prompt_select_pr(callback)
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

-- Helper: resolve PR from user input (db id or PR number)
local function resolve_pr(pr_arg, callback)
	if pr_arg and pr_arg ~= "" then
		local pr = db_prs.get_by_id(tonumber(pr_arg)) or db_prs.get_by_repo_and_number(nil, tonumber(pr_arg))
		if pr then
			callback(pr)
			return
		end
	end
	prompt_select_pr(callback)
end

-- 1. Sync all PRs
vim.api.nvim_create_user_command("RevmanSyncAllPRs", function()
	local res, err = workflows.sync_all_tracked_prs_async()
	if res then
		log.info("Synced PRs: " .. vim.inspect(res))
	else
		log.error("Error syncing PRs: " .. (err or "unknown"))
	end
end, {})

-- 2. Sync a single PR
vim.api.nvim_create_user_command("RevmanSyncPR", function(opts)
	local pr_number = tonumber(opts.args)
	if not pr_number then
		-- print("Usage: :RevmanSyncPR {pr_number}")
		-- TODO: this should allow no args for normal prompting of rfp id or number
		return
	end
	local pr_id, err = workflows.sync_pr(pr_number)
	if pr_id then
		log.info("PR synced: " .. pr_id)
	else
		log.error("Error syncing PR: " .. (err or "unknown"))
	end
end, { nargs = 1 })

-- 3. List all PRs (Telescope)
vim.api.nvim_create_user_command("RevmanListPRs", function()
	telescope_prs.pick_all_prs()
end, {})

-- 4. List open PRs (Telescope)
vim.api.nvim_create_user_command("RevmanListOpenPRs", function()
	telescope_prs.pick_open_prs()
end, {})

vim.api.nvim_create_user_command("RevmanListPRsNeedingReview", function()
	telescope_prs.pick_prs_needing_review()
end, {})

-- 5. List merged PRs (Telescope)
vim.api.nvim_create_user_command("RevmanListMergedPRs", function()
	telescope_prs.pick_merged_prs()
end, {})

-- 6. List repos (Telescope)
vim.api.nvim_create_user_command("RevmanListRepos", function()
	telescope_repos.pick_repos()
end, {})

-- 7. List authors (Telescope)
vim.api.nvim_create_user_command("RevmanListAuthors", function()
	telescope_authors.pick_authors_with_preview()
end, {})

-- 8. Review PR (select for review, open in Octo)
vim.api.nvim_create_user_command("RevmanReviewPR", function(opts)
	resolve_pr(opts.args, function(pr)
		if not pr then
			local pr_number = tonumber(opts.args)
			if pr_number then
				local repo_name = utils.get_current_repo()
				local pr_data = github_data.get_pr(pr_number, repo_name)
				if pr_data then
					local repo_row = utils.ensure_repo(repo_name)
					local pr_db_row = github_prs.extract_pr_fields(pr_data)
					pr_db_row.repo_id = repo_row.id
					pr_db_row.last_synced = os.date("!%Y-%m-%dT%H:%M:%SZ")
					db_prs.add(pr_db_row)
					pr = db_prs.get_by_repo_and_number(repo_row.id, pr_number)
				end
			end
		end
		if not pr then
			print("No PR selected or found.")
			return
		end
		workflows.select_pr_for_review(pr.id)
	end)
end, { nargs = "?" })

-- 9. Set PR status (with vim.ui.select)
vim.api.nvim_create_user_command("RevmanSetStatus", function(opts)
	resolve_pr(opts.args, function(pr)
		if not pr then
			log.error("No PR selected for status update.")
			return
		end
		local statuses = {}
		for _, s in ipairs(db_status.list()) do
			table.insert(statuses, s.name)
		end
		vim.ui.select(statuses, { prompt = "Select status" }, function(choice)
			if choice then
				workflows.set_status(pr.id, choice)
				log.info("PR #" .. pr.number .. " status updated to: " .. choice)
			end
		end)
	end)
end, { nargs = "?" })

-- 10. Add or update note (open buffer, save with keybinding)
vim.api.nvim_create_user_command("RevmanAddNote", function(opts)
	resolve_pr(opts.args, function(pr)
		if not pr then
			log.error("No PR selected for note.")
			return
		end
		local note = db_notes.get_by_pr_id(pr.id)
		local buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_option(buf, "buftype", "acwrite")
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
	resolve_pr(opts.args, function(pr)
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

-- 12. List PRs needing a nudge
vim.api.nvim_create_user_command("RevmanNudgePRs", function()
	local prs = logic_prs.list_prs_needing_nudge(db_prs, db_repos, utils)
	if #prs == 0 then
		log.notify("No PRs need a nudge!", "info")
		log.info("No PRs need a nudge!")
		return
	end
	for _, pr in ipairs(prs) do
		print(string.format("#%s %s (%s)", pr.number, pr.title, pr.author or "unknown"))
	end
end, {})

-- 13. Toggle background sync
vim.api.nvim_create_user_command("RevmanEnableBackgroundSync", function()
	sync.enable_background_sync()
	log.info("Background sync enabled.")
	log.notify("Background sync enabled.", "info")
end, {})

vim.api.nvim_create_user_command("RevmanDisableBackgroundSync", function()
	sync.disable_background_sync()
	log.info("Background sync disabled.")
	log.notify("Background sync disabled.", "info")
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
	local pr_data = github_data.get_pr(pr_number, repo_name)
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
		return
	end

	db_repos.add(repo_name, directory)
	local repo_row = db_repos.get_by_name(repo_name)
	if repo_row then
		db_repos.update(repo_row.id, { directory = directory })
		log.info("Added repo: " .. repo_name .. " (" .. directory .. ")")
	else
		log.error("Failed to add repo: " .. repo_name)
	end
end, { nargs = "*" })

return M
