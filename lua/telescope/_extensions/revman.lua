local has_telescope, telescope = pcall(require, "telescope")
if not has_telescope then
	-- Don't error, just return empty module since this might be loaded
	-- during discovery even when not configured
	return {}
end

-- Extension functions that get registered with telescope
local revman = {}

-- List all PRs
revman.prs = function(opts)
	opts = vim.tbl_extend("force", revman._config or {}, opts or {})

	-- Call picker directly with telescope-specific options
	local picker = require("revman.picker")
	local pr_lists = require("revman.db.pr_lists")
	local cmd_utils = require("revman.command-utils")
	local prs = pr_lists.list_with_status()

	-- Force telescope for telescope extension calls
	local picker_opts = {
		prompt = "All PRs",
		telescope_opts = opts,
		force_telescope = true,
	}
	picker.pick_prs(prs, picker_opts, cmd_utils.default_pr_select_callback)
end

-- List open PRs
revman.open_prs = function(opts)
	opts = vim.tbl_extend("force", revman._config or {}, opts or {})

	local picker = require("revman.picker")
	local pr_lists = require("revman.db.pr_lists")
	local cmd_utils = require("revman.command-utils")
	local prs = pr_lists.list_with_status({ where = { state = "OPEN" } })

	local picker_opts = {
		prompt = "Open PRs",
		telescope_opts = opts,
		force_telescope = true,
	}
	picker.pick_prs(prs, picker_opts, cmd_utils.default_pr_select_callback)
end

-- List PRs needing review
revman.prs_needing_review = function(opts)
	opts = vim.tbl_extend("force", revman._config or {}, opts or {})

	local picker = require("revman.picker")
	local db_status = require("revman.db.status")
	local pr_lists = require("revman.db.pr_lists")
	local cmd_utils = require("revman.command-utils")
	local status_id = db_status.get_id("waiting_for_review")
	local prs = pr_lists.list_with_status({ where = { review_status_id = status_id, state = "OPEN" } })

	local picker_opts = {
		prompt = "PRs Needing Review",
		telescope_opts = opts,
		force_telescope = true,
	}
	picker.pick_prs(prs, picker_opts, cmd_utils.default_pr_select_callback)
end

-- List merged PRs
revman.merged_prs = function(opts)
	opts = vim.tbl_extend("force", revman._config or {}, opts or {})

	local picker = require("revman.picker")
	local pr_lists = require("revman.db.pr_lists")
	local cmd_utils = require("revman.command-utils")
	local status = require("revman.db.status")
	-- Use list_merged which now uses is_merged logic
	local prs = pr_lists.list_merged({
		order_by = { desc = { "last_activity" } },
	})
	-- Add status names
	for _, pr in ipairs(prs) do
		pr.review_status = status.get_name(pr.review_status_id)
	end

	local picker_opts = {
		prompt = "Merged PRs",
		telescope_opts = opts,
		force_telescope = true,
	}
	picker.pick_prs(prs, picker_opts, cmd_utils.default_pr_select_callback)
end

-- List current user's open PRs
revman.my_open_prs = function(opts)
	opts = vim.tbl_extend("force", revman._config or {}, opts or {})

	local picker = require("revman.picker")
	local utils = require("revman.utils")
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

	local picker_opts = {
		prompt = "My Open PRs",
		telescope_opts = opts,
		force_telescope = true,
	}
	picker.pick_prs(prs, picker_opts, cmd_utils.default_pr_select_callback)
end

-- List PRs needing a nudge
revman.nudge_prs = function(opts)
	opts = vim.tbl_extend("force", revman._config or {}, opts or {})

	local picker = require("revman.picker")
	local db_status = require("revman.db.status")
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

	local picker_opts = {
		prompt = "PRs Needing a Nudge",
		telescope_opts = opts,
		force_telescope = true,
	}
	picker.pick_prs(prs, picker_opts, cmd_utils.default_pr_select_callback)
end

-- List authors with analytics
revman.authors = function(opts)
	opts = vim.tbl_extend("force", revman._config or {}, opts or {})

	local picker = require("revman.picker")
	local author_analytics = require("revman.analytics.authors")
	local author_stats = author_analytics.get_author_analytics()
	local authors = {}
	local picker_opts = {
		prompt = "PR Authors (Analytics)",
		telescope_opts = opts,
		force_telescope = true,
	}
	picker.pick_authors(authors, picker_opts)
end

-- List repositories
revman.repos = function(opts)
	opts = vim.tbl_extend("force", revman._config or {}, opts or {})

	local picker = require("revman.picker")
	local db_repos = require("revman.db.repos")
	local repos = db_repos.list()

	local picker_opts = {
		prompt = "Repositories",
		telescope_opts = opts,
		force_telescope = true,
	}
	picker.pick_repos(repos, picker_opts)
end

-- List PR notes
revman.notes = function(opts)
	opts = vim.tbl_extend("force", revman._config or {}, opts or {})

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
end

-- Register extension with telescope
return telescope.register_extension({
	exports = revman,
	setup = function(ext_config, config)
		-- Extension setup - configure defaults and validate
		ext_config = ext_config or {}

		-- Set default telescope options for revman pickers
		local defaults = {
			layout_strategy = "horizontal",
			layout_config = {
				preview_width = 0.6,
				width = 0.9,
				height = 0.8,
			},
			sorting_strategy = "ascending",
		}

		-- Merge user config with defaults
		for key, value in pairs(defaults) do
			if ext_config[key] == nil then
				ext_config[key] = value
			end
		end

		-- Store config for use in pickers
		revman._config = ext_config

		-- Log that extension was loaded
		local log = require("revman.log")
		log.info("Revman telescope extension loaded successfully")
	end,
})
