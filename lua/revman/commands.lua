local M = {}

-- Create real commands (replacing stubs)
local function create_commands()
	vim.api.nvim_create_user_command("RevmanListPRs", function()
		local picker = require("revman.picker")
		local pr_lists = require("revman.db.pr_lists")
		local cmd_utils = require("revman.command-utils")
		local prs = pr_lists.list_with_status()
		picker.pick_prs(prs, { prompt = "All PRs" }, cmd_utils.default_pr_select_callback)
	end, {})

	vim.api.nvim_create_user_command("RevmanListOpenPRs", function()
		local picker = require("revman.picker")
		local pr_lists = require("revman.db.pr_lists")
		local cmd_utils = require("revman.command-utils")
		local prs = pr_lists.list_with_status({ where = { state = "OPEN" } })
		picker.pick_prs(prs, { prompt = "Open PRs" }, cmd_utils.default_pr_select_callback)
	end, {})

	vim.api.nvim_create_user_command("RevmanListPRsNeedingReview", function()
		local db_status = require("revman.db.status")
		local picker = require("revman.picker")
		local pr_lists = require("revman.db.pr_lists")
		local cmd_utils = require("revman.command-utils")
		local status_id = db_status.get_id("waiting_for_review")
		local prs = pr_lists.list_with_status({ where = { review_status_id = status_id, state = "OPEN" } })
		picker.pick_prs(prs, { prompt = "PRs Needing Review" }, cmd_utils.default_pr_select_callback)
	end, {})

	vim.api.nvim_create_user_command("RevmanListMergedPRs", function()
		local picker = require("revman.picker")
		local pr_lists = require("revman.db.pr_lists")
		local cmd_utils = require("revman.command-utils")
		local prs = pr_lists.list_with_status({
			where = { state = "MERGED" },
			order_by = { desc = { "last_activity" } },
		})
		picker.pick_prs(prs, { prompt = "Merged PRs" }, cmd_utils.default_pr_select_callback)
	end, {})

	vim.api.nvim_create_user_command("RevmanListMyOpenPRs", function()
		local utils = require("revman.utils")
		local picker = require("revman.picker")
		local pr_lists = require("revman.db.pr_lists")
		local cmd_utils = require("revman.command-utils")
		local log = require("revman.log")
		local current_user = utils.get_current_user()
		if not current_user then
			log.error("Could not determine current user")
			return
		end
		local prs = pr_lists.list_with_status({
			where = { state = "OPEN", author = current_user },
		})
		picker.pick_prs(prs, { prompt = "My Open PRs" }, cmd_utils.default_pr_select_callback)
	end, {})

  vim.api.nvim_create_user_command("RevmanListAssignedPRs", function()
    local assignments = require("revman.logic.assignments")
    local utils = require("revman.utils")
    local log = require("revman.log")
    
    local repo_name = utils.get_current_repo()
    if not repo_name then
      log.error("Not in a GitHub repository")
      return
    end
    
    assignments.get_current_user_assignments(repo_name, function(assigned_prs, err)
      if not assigned_prs then
        log.error("Failed to fetch assigned PRs: " .. (err or "unknown error"))
        return
      end
      
      if #assigned_prs == 0 then
        log.notify("No PRs currently assigned to you", "info")
        return
      end
      
      -- Convert to picker-compatible format
      local picker_prs = {}
      local db_prs = require("revman.db.prs")
      local utils = require("revman.utils")
      local repo_row = utils.ensure_repo(repo_name)
      
      for _, assignment in ipairs(assigned_prs) do
        -- Check if PR is already tracked
        local is_tracked = false
        if repo_row then
          local existing_pr = db_prs.get_by_repo_and_number(repo_row.id, assignment.number)
          is_tracked = existing_pr ~= nil
        end
        
        table.insert(picker_prs, {
          number = assignment.number,
          title = assignment.title,
          state = assignment.state,
          assignees = assignment.assignees,
          is_tracked = is_tracked
        })
      end
      
      local picker = require("revman.picker")
      local cmd_utils = require("revman.command-utils")
      picker.pick_prs(picker_prs, { prompt = "Assigned PRs" }, function(selected_pr)
        if selected_pr.is_tracked then
          log.notify("PR #" .. selected_pr.number .. " is already being tracked")
          return
        end
        
        -- Add the selected PR to tracking
        local workflows = require("revman.workflows")
        workflows.sync_pr(selected_pr.number, repo_name, function(pr_id, sync_err)
          if pr_id then
            log.notify("Added PR #" .. selected_pr.number .. " to tracking")
          else
            log.error("Failed to add PR #" .. selected_pr.number .. ": " .. (sync_err or "unknown error"))
          end
        end)
      end)
    end)
  end, {})

	vim.api.nvim_create_user_command("RevmanListMentionedPRs", function()
		local utils = require("revman.utils")
		local picker = require("revman.picker")
		local pr_lists = require("revman.db.pr_lists")
		local cmd_utils = require("revman.command-utils")
		local log = require("revman.log")
		local current_user = utils.get_current_user()
		if not current_user then
			log.error("Could not determine current user")
			return
		end
		local prs = pr_lists.list_mentioned_prs(current_user, {
			where = { state = "OPEN" }
		})
		if #prs == 0 then
			log.notify("No open PRs where you are mentioned", "info")
			return
		end
		picker.pick_prs(prs, { prompt = "PRs Where You Are Mentioned" }, cmd_utils.default_pr_select_callback)
	end, {})

	vim.api.nvim_create_user_command("RevmanListRecentPRs", function()
		local picker = require("revman.picker")
		local pr_lists = require("revman.db.pr_lists")
		local cmd_utils = require("revman.command-utils")
		local prs = pr_lists.list_recent_closed_merged(7) -- Last 7 days
		if #prs == 0 then
			local log = require("revman.log")
			log.notify("No recently closed/merged PRs found", "info")
			return
		end
		picker.pick_prs(prs, { prompt = "Recent PRs (Last Week)" }, cmd_utils.default_pr_select_callback)
	end, {})

	vim.api.nvim_create_user_command("RevmanListAuthors", function()
		local picker = require("revman.picker")
		local author_analytics = require("revman.analytics.authors")
		local author_stats = author_analytics.get_author_analytics()
		local authors = {}

		for author, stats in pairs(author_stats) do
			stats.author = author -- ensure author field is present for display
			table.insert(authors, stats)
		end

		if #authors == 0 then
			local log = require("revman.log")
			log.notify("No PR data found for analytics. Add some PRs to track first.", "info")
			return
		end

		picker.pick_authors(authors, { prompt = "PR Authors (Analytics)" })
	end, {})

	vim.api.nvim_create_user_command("RevmanReviewPR", function(opts)
		local cmd_utils = require("revman.command-utils")
		local workflows = require("revman.workflows")
		cmd_utils.with_selected_pr(opts.args, function(pr)
			workflows.select_pr_for_review(pr.id)
		end)
	end, { nargs = "?" })

	vim.api.nvim_create_user_command("RevmanSetStatus", function(opts)
		local cmd_utils = require("revman.command-utils")
		cmd_utils.with_selected_pr(opts.fargs[1], function(pr)
			cmd_utils.select_status_and_set(pr, opts.fargs[2])
		end)
	end, {
		nargs = "*",
		complete = function(arglead)
			local cmd_utils = require("revman.command-utils")
			return cmd_utils.status_completion(arglead)
		end,
	})

	vim.api.nvim_create_user_command("RevmanSetStatusForCurrentPR", function(opts)
		local cmd_utils = require("revman.command-utils")
		cmd_utils.with_pr_from_current_buffer(function(pr)
			cmd_utils.select_status_and_set(pr, opts.args)
		end)
	end, { nargs = "?" })

	vim.api.nvim_create_user_command("RevmanAddNote", function()
		local db_prs = require("revman.db.prs")
		local pr_lists = require("revman.db.pr_lists")
		local note_utils = require("revman.note-utils")
		local cmd_utils = require("revman.command-utils")
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
		local picker = require("revman.picker")
		local pr_lists = require("revman.db.pr_lists")
		local db_notes = require("revman.db.notes")
		local note_utils = require("revman.note-utils")

		local prs = pr_lists.list()
		local prs_with_notes = {}
		for _, pr in ipairs(prs) do
			local note = db_notes.get_by_pr_id(pr.id)
			if note and note.content and note.content ~= "" then
				pr.note_content = note.content -- Add note content for searching
				table.insert(prs_with_notes, pr)
			end
		end

		picker.pick_notes(prs_with_notes, { prompt = "PR Notes" }, function(pr)
			note_utils.open_note_for_pr(pr)
		end)
	end, {})

	vim.api.nvim_create_user_command("RevmanNudgePRs", function()
		local db_status = require("revman.db.status")
		local picker = require("revman.picker")
		local pr_lists = require("revman.db.pr_lists")
		local cmd_utils = require("revman.command-utils")
		local log = require("revman.log")
		local status_id = db_status.get_id("needs_nudge")
		local prs = pr_lists.list_with_status({ where = { review_status_id = status_id } })
		if #prs == 0 then
			log.notify("No PRs need a nudge!", "info")
			log.info("No PRs need a nudge")
			return
		end
		picker.pick_prs(prs, { prompt = "PRs Needing a Nudge" }, cmd_utils.default_pr_select_callback)
	end, {})

	vim.api.nvim_create_user_command("RevmanAddPR", function(opts)
		local github_data = require("revman.github.data")
		local db_prs = require("revman.db.prs")
		local github_prs = require("revman.github.prs")
		local utils = require("revman.utils")
		local log = require("revman.log")
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
		end)
	end, { nargs = 1 })

	vim.api.nvim_create_user_command("RevmanRepairDB", function()
    local log = require("revman.log")
    
    log.notify("Starting database repair (running in background)...")
    log.info("Database repair started - this will run in the background")
    
    -- Run the repair in a separate thread to avoid blocking UI
    vim.schedule(function()
      local M = require("revman.repair")
      M.run_async_repair()
    end)
	end, {})

end

create_commands()

return M
