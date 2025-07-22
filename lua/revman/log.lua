local config = require("revman.config")

local levels = { error = 1, warn = 2, info = 3 }
local vim_levels = { error = vim.log.levels.ERROR, warn = vim.log.levels.WARN, info = vim.log.levels.INFO }

local M = {}

local function should_log(level)
	local cfg = config.get()
	local user_level = cfg.log_level or "warn"
	return levels[level] <= levels[user_level]
end

M.notify = function(msg, level)
	vim.notify("[revman.nvim] " .. msg, vim_levels[level])
	print("[revman.nvim] " .. msg)
end

local function notify(msg, level)
	if should_log(level) then
		M.notify(msg, vim_levels[level])
	end
end

M.info = function(msg)
	notify(msg, "info")
end
M.warn = function(msg)
	notify(msg, "warn")
end
M.error = function(msg)
	notify(msg, "error")
end

return M
