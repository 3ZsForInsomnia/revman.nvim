local db_notes = require("revman.db.notes")
local config = require("revman.config")
local log = require("revman.log")

local M = {}

function M.open_note_for_pr(pr)
	if not pr then
		log.error("No PR selected for note.")
		return
	end

	local note = db_notes.get_by_pr_id(pr.id)
	local notes_dir = vim.fn.stdpath("state") .. "/revman/notes"
	vim.fn.mkdir(notes_dir, "p")
	local note_path = notes_dir .. "/PR-" .. pr.id .. ".md"

	-- If file doesn't exist, write DB content to it
	if vim.fn.filereadable(note_path) == 0 and note and note.content then
		local f = io.open(note_path, "w")
		if f then
			f:write(note.content)
			f:close()
		end
	end

	-- Open the note file in a buffer
	vim.cmd("edit " .. vim.fn.fnameescape(note_path))

	-- Autocmd to sync file content to DB on save
	vim.api.nvim_create_autocmd("BufWritePost", {
		pattern = note_path,
		callback = function()
			local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
			local content = table.concat(lines, "\n")
			local now = os.date("!%Y-%m-%dT%H:%M:%SZ")
			if note then
				db_notes.update_by_pr_id(pr.id, { content = content, updated_at = now })
			else
				db_notes.add(pr.id, content, now)
			end
			log.info("Note saved for PR #" .. pr.number)
		end,
		once = false,
	})
end

return M
