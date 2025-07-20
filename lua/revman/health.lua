local health = vim.health or require("health")
local config = require("revman.config")
local utils = require("revman.utils")

local function check_sqlite()
	local ok, sqlite = pcall(require, "sqlite")
	if ok and sqlite then
		health.report_ok("sqlite.lua is installed")
	else
		health.report_error("sqlite.lua is not installed. Install kkharji/sqlite.lua")
	end
end

local function check_db_schema()
	local ok, db_create = pcall(require, "revman.db.create")
	if not ok then
		health.report_error("Could not load revman.db.create: " .. tostring(db_create))
		return
	end
	local db_path = config.get().database.path
	local stat = vim.loop.fs_stat(db_path)
	if stat and stat.type == "file" then
		health.report_ok("Database file exists: " .. db_path)
	else
		health.report_warn("Database file does not exist yet: " .. db_path)
	end
	-- Try to ensure schema and review statuses
	local ok_schema, err = pcall(db_create.ensure_schema)
	if ok_schema then
		health.report_ok("Database schema is valid")
	else
		health.report_error("Failed to ensure DB schema: " .. tostring(err))
	end
	local ok_status, err2 = pcall(db_create.ensure_review_statuses)
	if ok_status then
		health.report_ok("Review statuses are present")
	else
		health.report_error("Failed to ensure review statuses: " .. tostring(err2))
	end
end

local function check_gh()
	if utils.is_gh_available() then
		health.report_ok("GitHub CLI (gh) is installed and authenticated")
	else
		health.report_error("GitHub CLI (gh) is not available or not authenticated")
	end
end

local function check_config()
	local opts = config.get()
	if opts.database and opts.database.path then
		health.report_ok("Database path: " .. opts.database.path)
	else
		health.report_error("Database path is not set in config")
	end
	if opts.background and type(opts.background.frequency) == "number" then
		health.report_ok("Background sync frequency: " .. tostring(opts.background.frequency))
	else
		health.report_warn("Background sync frequency not set (default will be used)")
	end
	if opts.keymaps and opts.keymaps.save_notes then
		health.report_ok("Save notes keymap: " .. opts.keymaps.save_notes)
	else
		health.report_warn("Save notes keymap not set (default will be used)")
	end
end

local function check_octonvim()
	local ok, _ = pcall(function()
		vim.fn["octo#util#is_octonvim"]()
	end)
	if ok then
		health.report_ok("Octo.nvim is installed (for PR review UI)")
	else
		health.report_warn("Octo.nvim not detected. PR review UI will not be available.")
	end
end

return function()
	health.start("revman.nvim")
	check_sqlite()
	check_db_schema()
	check_gh()
	check_config()
	check_octonvim()
end
