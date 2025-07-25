local pickers = require("telescope.pickers")
local previewers = require("telescope.previewers")
local finders = require("telescope.finders")
local conf = require("telescope.config").values
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")

local db_prs = require("revman.db.prs")
local ci = require("revman.github.ci")

local function pr_previewer(self, entry, status)
	if not entry or not entry.value then
		vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, { "No PR selected." })
		return
	end
	local pr = entry.value
	local ci_status = pr.ci_status or "unknown"
	local ci_icon = ci.get_status_icon({ status = ci_status })

	local REVIEW_STATUS_LABELS = {
		waiting_for_review = "Waiting for Review",
		waiting_for_changes = "Waiting for Changes",
		ready_for_re_review = "Ready for Re-Review",
		approved = "Approved",
		merged = "Merged",
		closed = "Closed",
		needs_nudge = "Needs Nudge",
	}
	local review_status = pr.review_status and REVIEW_STATUS_LABELS[pr.review_status] or "N/A"

	local lines = {
		string.format("PR #%s", pr.number),
		string.format("Title: %s", pr.title),
		string.format("Author: %s", pr.author or "unknown"),
		string.format("State: %s", pr.state),
		string.format("Review Decision: %s", pr.review_decision or "N/A"),
		string.format("Is Draft: %s", pr.is_draft == 1 and "Yes" or "No"),
		string.format("Created: %s", pr.created_at),
		string.format("Last Viewed: %s", pr.last_viewed or "Never"),
		string.format("Last Synced: %s", pr.last_synced or "Never"),
		string.format("Last Activity: %s", pr.last_activity or "Unknown"),
		string.format("Comment Count: %s", pr.comment_count or "0"),
		string.format("Review Status: %s", review_status),
		string.format("CI Status: %s %s", ci_icon, ci_status),
		string.format("URL: %s", pr.url),
		"",
	}
	vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
end

local function format_pr_entry(pr)
	return string.format("#%s [%s] %s (%s)", pr.number, pr.state, pr.title, pr.author or "unknown")
end

local M = {}

local function make_picker(prs, opts, title)
	opts = opts or {}
	pickers
		.new(opts, {
			prompt_title = title,
			finder = finders.new_table({
				results = prs,
				entry_maker = function(pr)
					return {
						value = pr,
						display = format_pr_entry(pr),
						ordinal = pr.title .. " " .. (pr.author or ""),
					}
				end,
			}),
			sorter = conf.generic_sorter(opts),
			previewer = previewers.new_buffer_previewer({
				define_preview = pr_previewer,
			}),
			attach_mappings = function(prompt_bufnr, map)
				local update_last_viewed = function(entry)
					if entry and entry.value then
						local now = os.date("!%Y-%m-%dT%H:%M:%SZ")
						actions.close(prompt_bufnr)
						db_prs.update(entry.value.id, { last_viewed = now })
						vim.cmd(string.format("Octo pr edit %d", entry.value.number))
					end
				end

				map("i", "<CR>", function()
					local entry = action_state.get_selected_entry()
					update_last_viewed(entry)
				end)

				map("n", "<CR>", function()
					local entry = action_state.get_selected_entry()
					update_last_viewed(entry)
				end)

				return true
			end,
		})
		:find()
end

function M.pick_all_prs(opts)
	make_picker(db_prs.list_with_status(), opts, "All PRs")
end

function M.pick_open_prs(opts)
	make_picker(db_prs.list_with_status({ where = { state = "OPEN" } }), opts, "Open PRs")
end

function M.pick_prs_needing_review(opts)
	make_picker(
		db_prs.list_with_status({ where = { review_status = "waiting_for_review" } }),
		opts,
		"PRs Needing Review"
	)
end

function M.pick_merged_prs(opts)
	make_picker(db_prs.list_with_status({ where = { state = "MERGED" } }), opts, "Merged PRs")
end

return M
