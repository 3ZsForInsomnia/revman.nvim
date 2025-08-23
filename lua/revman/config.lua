local M = {}

M.defaults = {
	database = {
		path = vim.fn.stdpath("state") .. "/revman/revman.db",
	},

	retention = {
		days = 30, -- Set to 0 to keep forever
	},

	background = {
		frequency = 15, -- Set to 0 to disable background checks
	},

	picker = {
		backend = "vimSelect", -- "vimSelect" or "telescope"
	},

	log_level = "error", -- "info", "warn", or "error"
}

M.options = {}

function M.setup(opts)
	M.options = vim.tbl_deep_extend("force", {}, M.defaults, opts or {})

	-- Validate picker backend
	local valid_backends = { "vimSelect", "telescope" }
	local backend = M.options.picker and M.options.picker.backend
	if backend and not vim.tbl_contains(valid_backends, backend) then
		local log = require("revman.log")
		log.error("Invalid picker backend: " .. tostring(backend) .. ". Valid options: " .. table.concat(valid_backends, ", "))
		M.options.picker.backend = "vimSelect" -- fallback to default
	end

	-- Handle nil database path by setting the default
	if M.options.database.path == nil then
		M.options.database.path = vim.fn.stdpath("state") .. "/revman.db"
	end

	-- Expand the path if it contains ~ for home directory
	if M.options.database.path:match("^~") then
		M.options.database.path = vim.fn.expand(M.options.database.path)
	end

	return M.options
end

function M.get()
	return M.options
end

return M
