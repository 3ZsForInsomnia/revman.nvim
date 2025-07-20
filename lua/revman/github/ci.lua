local M = {}

function M.extract_ci_status(status_data)
	if not status_data or not status_data.statusCheckRollup then
		return nil
	end
	local checks = status_data.statusCheckRollup
	local total, passing, failing, pending = #checks, 0, 0, 0
	for _, check in ipairs(checks) do
		if check.state == "SUCCESS" then
			passing = passing + 1
		elseif check.state == "FAILURE" or check.state == "ERROR" then
			failing = failing + 1
		else
			pending = pending + 1
		end
	end
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
		checks = checks,
	}
end

function M.get_status_icon(ci_status)
	if not ci_status then
		return "❓"
	end
	if ci_status.status == "PASSING" then
		return "✅"
	elseif ci_status.status == "FAILING" then
		return "❌"
	elseif ci_status.status == "PENDING" then
		return "⏳"
	else
		return "❓"
	end
end

return M
