local v = vim
local M = {}

M.defaults = {
	database = {
		path = nil, -- Will use vim.fn.stdpath('state') .. '/revman.db' if nil
	},

	retention = {
		-- Set to 0 to keep forever
		days = 30,
	},

	background = {
		-- Set to 0 to disable background checks
		frequency = 15,
	},
}

M.options = {}

function M.setup(opts)
	M.options = v.tbl_deep_extend("force", {}, M.defaults, opts or {})

	if M.options.database.path == nil then
		M.options.database.path = v.fn.stdpath("state") .. "/revman.db"
	end

	return M.options
end

function M.get()
	return M.options
end

return M
