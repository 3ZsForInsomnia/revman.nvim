local pickers = require("telescope.pickers")
local previewers = require("telescope.previewers")
local finders = require("telescope.finders")
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")
local conf = require("telescope.config").values
local pr_lists = require("revman.db.pr_lists")
local db_notes = require("revman.db.notes")
local note_utils = require("revman.note-utils")

local M = {}

function M.pick_pr_notes(opts)
	opts = opts or {}
	local prs = pr_lists.list()
	local prs_with_notes = {}
	for _, pr in ipairs(prs) do
		local note = db_notes.get_by_pr_id(pr.id)
		if note and note.content and note.content ~= "" then
			table.insert(prs_with_notes, pr)
		end
	end

	pickers
		.new(opts, {
			prompt_title = "PR Notes",
			finder = finders.new_table({
				results = prs_with_notes,
				entry_maker = function(pr)
					return {
						value = pr,
						display = string.format(
							"#%s [%s] %s (%s)",
							pr.number,
							pr.state,
							pr.title,
							pr.author or "unknown"
						),
						ordinal = pr.title .. " " .. (pr.author or ""),
					}
				end,
			}),
			sorter = conf.generic_sorter(opts),
			previewer = previewers.new_buffer_previewer({
				define_preview = function(self, entry)
					local pr = entry.value
					local note = db_notes.get_by_pr_id(pr.id)
					local lines = note and vim.split(note.content or "", "\n") or { "No note found." }
					vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
					vim.bo[self.state.bufnr].filetype = "markdown"
				end,
			}),
			attach_mappings = function(prompt_bufnr, map)
				local function open_note()
					local entry = action_state.get_selected_entry()
					if entry and entry.value then
						actions.close(prompt_bufnr)
						note_utils.open_note_for_pr(entry.value)
					end
				end
				map("i", "<CR>", open_note)
				map("n", "<CR>", open_note)
				return true
			end,
		})
		:find()
end

return M
