local config = require("revman.config")

local levels = { error = 1, warn = 2, info = 3 }
local messagePrefix = "[Revman.nvim]: "

local M = {}

M.log_levels = { error = vim.log.levels.ERROR, warn = vim.log.levels.WARN, info = vim.log.levels.INFO }

local function should_log(level)
	local cfg = config.get()
	local user_level = cfg.log_level or "warn"

	return levels[level] >= levels[user_level]
end

M.info = function(msg)
	if should_log("info") then
		vim.api.nvim_echo({ { messagePrefix .. msg, "None" } }, true, {})
	end
end

M.warn = function(msg)
	if should_log("warn") then
		vim.api.nvim_echo({ { messagePrefix .. msg, "WarningMsg" } }, true, {})
	end
end

M.error = function(msg)
	if should_log("error") then
		vim.api.nvim_echo({ { messagePrefix .. msg, "ErrorMsg" } }, true, {})
		M.notify(messagePrefix .. msg, vim.log.levels.ERROR)
	end
end

M.notify = function(msg, level)
	level = level or vim.log.levels.INFO
	vim.notify(messagePrefix .. msg, level)
end

return M
