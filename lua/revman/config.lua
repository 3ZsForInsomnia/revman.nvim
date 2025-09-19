local M = {}

M.defaults = {
	database_path = vim.fn.stdpath("state") .. "/revman/revman.db",
	data_retention_days = 30, -- Set to 0 to keep forever
	background_sync_frequency = 15, -- Set to 0 to disable background checks

	picker = "vimSelect", -- "vimSelect", "telescope", or "snacks"

	log_level = "error", -- "info", "warn", or "error"
}

M.options = {}

function M.setup(opts)
	M.options = vim.tbl_deep_extend("force", {}, M.defaults, opts or {})

	local valid_backends = { "vimSelect", "telescope", "snacks" }
	local backend = M.options.picker
	if backend and not vim.tbl_contains(valid_backends, backend) then
		local log = require("revman.log")
		log.error(
			"Invalid picker backend: " .. tostring(backend) .. ". Valid options: " .. table.concat(valid_backends, ", ")
		)
		M.options.picker = "vimSelect" -- fallback to default
	end

	-- Handle nil database path by setting the default
	if M.options.database_path == nil then
		M.options.database_path = vim.fn.stdpath("state") .. "/revman/revman.db"
	end

	-- Expand the path if it contains ~ for home directory
	if M.options.database_path:match("^~") then
		M.options.database_path = vim.fn.expand(M.options.database_path)
	end

	return M.options
end

function M.get()
	return M.options
end

return M
