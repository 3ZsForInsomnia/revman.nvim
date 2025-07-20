local M = {}

M.defaults = {
	database = {
		path = vim.fn.stdpath("state") .. "/revman/revman.db",
	},

	retention = {
		-- Set to 0 to keep forever
		days = 30,
	},

	background = {
		-- Set to 0 to disable background checks
		frequency = 15,
	},

	keymaps = {
		-- Set to nil or empty string to disable
		save_notes = "<leader>zz",
	},
}

M.options = {}

function M.setup(opts)
	M.options = vim.tbl_deep_extend("force", {}, M.defaults, opts or {})

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
