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
	local db_path = config.get().database.path
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

local M = {}

M.check = function()
	vim.health.start("revman.nvim")
	check_sqlite()
	check_db_schema()
	check_gh()
	check_config()
	check_octonvim()
end

return M
