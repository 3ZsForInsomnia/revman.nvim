local config = require("revman.config")
local utils = require("revman.utils")

local function check_sqlite()
	local ok, sqlite = pcall(require, "sqlite")
	if ok and sqlite then
		vim.health.ok("sqlite.lua is installed")
	else
		vim.health.error("sqlite.lua is not installed. Install kkharji/sqlite.lua")
	end
end

local function check_db_schema()
	local ok, db_schema = pcall(require, "revman.db.schema")
	if not ok then
		vim.health.error("Could not load revman.db.schema: " .. tostring(db_schema))
		return
	end
	local db_path = config.get().database_path
	local stat = vim.loop.fs_stat(db_path)
	if not (stat and stat.type == "file") then
		-- Try to create the DB/schema
		local ok_schema, err = pcall(db_schema.ensure_schema)
		if not ok_schema then
			vim.health.error("Failed to create DB schema: " .. tostring(err))
			return
		end
		stat = vim.loop.fs_stat(db_path)
	end
	if stat and stat.type == "file" then
		vim.health.ok("Database file exists: " .. db_path)
	else
		vim.health.error("Database file does not exist and could not be created: " .. db_path)
	end
end

local function check_gh()
	if utils.is_gh_available() then
		vim.health.ok("GitHub CLI (gh) is installed and authenticated")
	else
		vim.health.error("GitHub CLI (gh) is not available or not authenticated")
	end
end

local function check_config()
	local opts = config.get()
	if opts.database and opts.database.path then
		vim.health.ok("Database path: " .. opts.database.path)
	else
		vim.health.error("Database path is not set in config")
	end
	if opts.background and type(opts.background.frequency) == "number" then
		vim.health.ok("Background sync frequency: " .. tostring(opts.background.frequency))
	else
		vim.health.warn("Background sync frequency not set (default will be used)")
	end
	if opts.keymaps and opts.keymaps.save_notes then
		vim.health.ok("Save notes keymap: " .. opts.keymaps.save_notes)
	else
		vim.health.warn("Save notes keymap not set (default will be used)")
	end
end

local function check_octonvim()
	local ok, _ = pcall(require, "octo")
	if ok then
		vim.health.ok("Octo.nvim is installed (for PR review UI)")
	else
		vim.health.warn("Octo.nvim not detected. PR review UI will not be available.")
	end
end

local function check_telescope()
	local backend = config.get().picker or "vimSelect"

	vim.health.info("Picker backend configured: " .. backend)

	local has_telescope, telescope = pcall(require, "telescope")
	local has_snacks, snacks = pcall(require, "snacks")

	if backend == "telescope" then
		if has_telescope then
			vim.health.ok("Telescope backend configured and telescope.nvim is available")

			-- Check if extension is loaded
			local has_extension = pcall(function()
				return telescope.extensions.revman ~= nil
			end)

			if has_extension then
				vim.health.ok("Revman telescope extension loaded - :Telescope revman <command> available")
			else
				vim.health.info(
					"Revman telescope extension not loaded - call telescope.load_extension('revman') to enable"
				)
			end
		else
			vim.health.error("Picker backend set to 'telescope' but telescope.nvim is not available")
			vim.health.info("Either install telescope.nvim or change picker to 'vimSelect'")
		end
	elseif backend == "snacks" then
		if has_snacks and snacks.picker then
			vim.health.ok("Snacks backend configured and snacks.nvim picker is available")
			
			-- Check if sources are registered
			local has_sources = snacks.picker.sources and snacks.picker.sources.revman_prs ~= nil
			if has_sources then
				vim.health.ok("Revman snacks sources registered - Snacks.revman.<command> available")
			else
				vim.health.info(
					"Revman snacks sources not registered - call require('revman.snacks.sources').setup() to enable"
				)
			end
		else
			vim.health.error("Picker backend set to 'snacks' but snacks.nvim picker is not available")
			vim.health.info("Either install snacks.nvim with picker enabled or change picker to 'vimSelect'")
		end
	elseif backend == "vimSelect" then
		vim.health.ok("Using vim.ui.select picker backend")
		if has_telescope then
			vim.health.info("Telescope.nvim is available - set picker = 'telescope' to use enhanced UI")
		end
		if has_snacks and snacks.picker then
			vim.health.info("Snacks.nvim picker is available - set picker = 'snacks' to use enhanced UI")
		end
	else
		vim.health.error("Invalid picker backend: " .. tostring(backend))
		vim.health.info("Valid options: 'vimSelect', 'telescope', 'snacks'")
	end
end

local function check_module_loading()
	-- Load all modules to test functionality (health check should test features, not lazy loading)
	local modules_to_test = {
		{ name = "revman.commands", desc = "Main commands" },
		{ name = "revman.sync_commands", desc = "Sync commands" },
		{ name = "revman.repo_commands", desc = "Repository commands" },
		{ name = "revman.picker", desc = "Picker system" },
		{ name = "revman.workflows", desc = "Core workflows" },
	}
	
	-- Add snacks modules if snacks backend is configured
	local picker_backend = config.get().picker or "vimSelect"
	if picker_backend == "snacks" then
		table.insert(modules_to_test, { name = "revman.snacks", desc = "Snacks picker integration" })
		table.insert(modules_to_test, { name = "revman.snacks.commands", desc = "Snacks commands" })
		table.insert(modules_to_test, { name = "revman.snacks.sources", desc = "Snacks sources registration" })
	end
	
	local failed_modules = {}
	for _, mod in ipairs(modules_to_test) do
		local ok, _ = pcall(require, mod.name)
		if ok then
			vim.health.ok(mod.desc .. " module loads successfully")
		else
			table.insert(failed_modules, mod.desc)
			vim.health.error(mod.desc .. " module failed to load")
		end
	end
	
	if #failed_modules == 0 then
		vim.health.ok("All core modules loaded successfully")
	else
		vim.health.error("Some modules failed to load: " .. table.concat(failed_modules, ", "))
	end
	
	-- Check if sync is working
	local sync_loaded = package.loaded["revman.sync"] ~= nil
	if sync_loaded then
		vim.health.ok("Background sync is loaded and ready")
	else
		local ok, _ = pcall(require, "revman.sync")
		if ok then
			vim.health.ok("Background sync module loads successfully")
		else
			vim.health.error("Background sync module failed to load")
		end
	end
end

local M = {}

M.check = function()
	vim.health.start("revman.nvim")
	check_sqlite()
	check_db_schema()
	check_gh()
	check_config()
	check_telescope()
	check_octonvim()
	check_module_loading()
end

return M
