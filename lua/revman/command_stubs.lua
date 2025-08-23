-- Lightweight command stubs that lazy-load functionality on first use
local M = {}

-- Track which command modules have been loaded
local loaded = {
	commands = false,
	sync_commands = false,
	repo_commands = false,
}

-- Lazy loader helper
local function ensure_loaded(module_name, loader_func)
	if not loaded[module_name] then
		loader_func()
		loaded[module_name] = true
	end
end

-- Create lightweight command stubs
function M.create_command_stubs()
	-- PR commands - load main commands module on first use
	vim.api.nvim_create_user_command("RevmanListPRs", function()
		ensure_loaded("commands", function()
			require("revman.commands")
		end)
		-- Re-execute the command now that it's properly loaded
		vim.cmd("RevmanListPRs")
	end, {})

	vim.api.nvim_create_user_command("RevmanListOpenPRs", function()
		ensure_loaded("commands", function()
			require("revman.commands")
		end)
		vim.cmd("RevmanListOpenPRs")
	end, {})

	vim.api.nvim_create_user_command("RevmanListPRsNeedingReview", function()
		ensure_loaded("commands", function()
			require("revman.commands")
		end)
		vim.cmd("RevmanListPRsNeedingReview")
	end, {})

	vim.api.nvim_create_user_command("RevmanListMergedPRs", function()
		ensure_loaded("commands", function()
			require("revman.commands")
		end)
		vim.cmd("RevmanListMergedPRs")
	end, {})

	vim.api.nvim_create_user_command("RevmanListMyOpenPRs", function()
		ensure_loaded("commands", function()
			require("revman.commands")
		end)
		vim.cmd("RevmanListMyOpenPRs")
	end, {})

	vim.api.nvim_create_user_command("RevmanListAuthors", function()
		ensure_loaded("commands", function()
			require("revman.commands")
		end)
		vim.cmd("RevmanListAuthors")
	end, {})

	vim.api.nvim_create_user_command("RevmanReviewPR", function(opts)
		ensure_loaded("commands", function()
			require("revman.commands")
		end)
		vim.cmd("RevmanReviewPR " .. (opts.args or ""))
	end, { nargs = "?" })

	vim.api.nvim_create_user_command("RevmanSetStatus", function(opts)
		ensure_loaded("commands", function()
			require("revman.commands")
		end)
		vim.cmd("RevmanSetStatus " .. (opts.args or ""))
	end, { 
		nargs = "*",
		complete = function(arglead)
			-- Light completion without loading heavy modules
			return { "waiting_for_review", "waiting_for_changes", "approved", "merged", "closed", "needs_nudge" }
		end,
	})

	vim.api.nvim_create_user_command("RevmanSetStatusForCurrentPR", function(opts)
		ensure_loaded("commands", function()
			require("revman.commands")
		end)
		vim.cmd("RevmanSetStatusForCurrentPR " .. (opts.args or ""))
	end, { nargs = "?" })

	vim.api.nvim_create_user_command("RevmanAddNote", function()
		ensure_loaded("commands", function()
			require("revman.commands")
		end)
		vim.cmd("RevmanAddNote")
	end, {})

	vim.api.nvim_create_user_command("RevmanShowNotes", function()
		ensure_loaded("commands", function()
			require("revman.commands")
		end)
		vim.cmd("RevmanShowNotes")
	end, {})

	vim.api.nvim_create_user_command("RevmanNudgePRs", function()
		ensure_loaded("commands", function()
			require("revman.commands")
		end)
		vim.cmd("RevmanNudgePRs")
	end, {})

	vim.api.nvim_create_user_command("RevmanAddPR", function(opts)
		ensure_loaded("commands", function()
			require("revman.commands")
		end)
		vim.cmd("RevmanAddPR " .. (opts.args or ""))
	end, { nargs = 1 })

	-- Sync commands - load sync commands module on first use
	vim.api.nvim_create_user_command("RevmanSyncAllPRs", function()
		ensure_loaded("sync_commands", function()
			require("revman.sync_commands")
		end)
		vim.cmd("RevmanSyncAllPRs")
	end, {})

	vim.api.nvim_create_user_command("RevmanSyncPR", function(opts)
		ensure_loaded("sync_commands", function()
			require("revman.sync_commands")
		end)
		vim.cmd("RevmanSyncPR " .. (opts.args or ""))
	end, { nargs = 1 })

	vim.api.nvim_create_user_command("RevmanEnableBackgroundSync", function()
		ensure_loaded("sync_commands", function()
			require("revman.sync_commands")
		end)
		vim.cmd("RevmanEnableBackgroundSync")
	end, {})

	vim.api.nvim_create_user_command("RevmanDisableBackgroundSync", function()
		ensure_loaded("sync_commands", function()
			require("revman.sync_commands")
		end)
		vim.cmd("RevmanDisableBackgroundSync")
	end, {})

	-- Repo commands - load repo commands module on first use  
	vim.api.nvim_create_user_command("RevmanListRepos", function()
		ensure_loaded("repo_commands", function()
			require("revman.repo_commands")
		end)
		vim.cmd("RevmanListRepos")
	end, {})

	vim.api.nvim_create_user_command("RevmanAddRepo", function()
		ensure_loaded("repo_commands", function()
			require("revman.repo_commands")
		end)
		vim.cmd("RevmanAddRepo")
	end, {})
end

return M