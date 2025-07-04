local M = {}
local github = require("revman.github")

-- Get CI status for a PR
function M.get_ci_status(pr_number)
	local repo = github.get_current_repo()
	if not repo then
		return nil, "Not in a GitHub repository"
	end

	local handle = io.popen(string.format("gh pr view %s --json statusCheckRollup -R %s 2>/dev/null", pr_number, repo))
	local result = handle:read("*a")
	handle:close()

	if result == "" then
		return nil, "PR not found or no CI status"
	end

	local data = vim.json.decode(result)

	-- If there are no status checks, return nil
	if not data.statusCheckRollup or #data.statusCheckRollup == 0 then
		return {
			status = "UNKNOWN",
			total = 0,
			passing = 0,
			failing = 0,
			pending = 0,
		}, nil
	end

	-- Count statuses
	local total = #data.statusCheckRollup
	local passing = 0
	local failing = 0
	local pending = 0

	for _, check in ipairs(data.statusCheckRollup) do
		if check.state == "SUCCESS" then
			passing = passing + 1
		elseif check.state == "FAILURE" or check.state == "ERROR" then
			failing = failing + 1
		else
			pending = pending + 1
		end
	end

	-- Determine overall status
	local status = "PENDING"
	if failing > 0 then
		status = "FAILING"
	elseif pending == 0 and passing == total then
		status = "PASSING"
	end

	return {
		status = status,
		total = total,
		passing = passing,
		failing = failing,
		pending = pending,
		checks = data.statusCheckRollup,
	},
		nil
end

-- Get CI status for multiple PRs
function M.get_multiple_ci_statuses(pr_numbers)
	local results = {}
	local errors = {}

	for _, pr_number in ipairs(pr_numbers) do
		local ci_data, err = M.get_ci_status(pr_number)
		if ci_data then
			results[tostring(pr_number)] = ci_data
		else
			errors[tostring(pr_number)] = err
		end
	end

	return results, errors
end

-- Get CI status icon for display
function M.get_status_icon(ci_status)
	if not ci_status then
		return "❓" -- Unknown
	end

	if ci_status.status == "PASSING" then
		return "✅" -- Passing
	elseif ci_status.status == "FAILING" then
		return "❌" -- Failing
	elseif ci_status.status == "PENDING" then
		return "⏳" -- Pending
	else
		return "❓" -- Unknown
	end
end

return M
