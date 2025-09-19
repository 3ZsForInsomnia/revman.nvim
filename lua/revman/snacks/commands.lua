-- Snacks commands for revman.nvim
-- This provides direct access to snacks picker functions via user commands

local M = {}

-- Create snacks-specific commands
local function create_snacks_commands()
	-- Only create if snacks is configured and available
	local config = require("revman.config")
	local picker_backend = config.get().picker or "vimSelect"
	
	if picker_backend ~= "snacks" then
		return
	end
	
	local ok, snacks = pcall(require, "snacks")
	if not ok or not snacks.picker then
		local log = require("revman.log")
		log.warn("Snacks picker backend configured but snacks.nvim picker is not available")
		return
	end
	
	local snacks_picker = require("revman.snacks")
	
	-- PR commands
	vim.api.nvim_create_user_command("SnacksRevmanPRs", function()
		snacks_picker.prs()
	end, { desc = "List all PRs with Snacks picker" })
	
	vim.api.nvim_create_user_command("SnacksRevmanOpenPRs", function()
		snacks_picker.open_prs()
	end, { desc = "List open PRs with Snacks picker" })
	
	vim.api.nvim_create_user_command("SnacksRevmanPRsNeedingReview", function()
		snacks_picker.prs_needing_review()
	end, { desc = "List PRs needing review with Snacks picker" })
	
	vim.api.nvim_create_user_command("SnacksRevmanMergedPRs", function()
		snacks_picker.merged_prs()
	end, { desc = "List merged PRs with Snacks picker" })
	
	vim.api.nvim_create_user_command("SnacksRevmanMyOpenPRs", function()
		snacks_picker.my_open_prs()
	end, { desc = "List my open PRs with Snacks picker" })
	
	vim.api.nvim_create_user_command("SnacksRevmanNudgePRs", function()
		snacks_picker.nudge_prs()
	end, { desc = "List PRs needing a nudge with Snacks picker" })
	
	-- Other commands
	vim.api.nvim_create_user_command("SnacksRevmanAuthors", function()
		snacks_picker.authors()
	end, { desc = "List authors with analytics using Snacks picker" })
	
	vim.api.nvim_create_user_command("SnacksRevmanRepos", function()
		snacks_picker.repos()
	end, { desc = "List repositories with Snacks picker" })
	
	vim.api.nvim_create_user_command("SnacksRevmanNotes", function()
		snacks_picker.notes()
	end, { desc = "List PR notes with Snacks picker" })
	
	local log = require("revman.log")
	log.info("Snacks Revman commands created successfully")
end

function M.should_load()
	local config = require("revman.config")
	local picker_backend = config.get().picker or "vimSelect"
	return picker_backend == "snacks"
end

-- Function to load snacks commands - call this from setup when appropriate
function M.load_commands()
	if M.should_load() then
		create_snacks_commands()
	end
end

return M