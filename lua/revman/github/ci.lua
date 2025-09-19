local M = {}

function M.extract_ci_status(status_data)
	-- Debug logging to understand the data structure
	local log = require("revman.log")
	log.info("CI status data type: " .. type(status_data))
	if type(status_data) == "table" then
		log.info("CI status data keys: " .. vim.inspect(vim.tbl_keys(status_data)))
		if status_data[1] then
			log.info("First item: " .. vim.inspect(status_data[1]))
		end
	end
	
	if not status_data then
		return nil
	end
	
	-- Handle both direct statusCheckRollup data and wrapped PR data
	local checks
	if status_data.statusCheckRollup then
		checks = status_data.statusCheckRollup
	elseif type(status_data) == "table" and status_data[1] then
		-- statusCheckRollup is an array
		checks = status_data
	else
		return nil
	end
	
	if not checks or type(checks) ~= "table" then
		return nil
	end
	
	local total = #checks
	local passing, failing, pending, skipped = 0, 0, 0, 0

	for _, check in ipairs(checks) do
		if check.conclusion == "SUCCESS" then
			passing = passing + 1
		elseif check.conclusion == "FAILURE" or check.conclusion == "ERROR" then
			failing = failing + 1
		elseif check.conclusion == "SKIPPED" then
			skipped = skipped + 1
		elseif not check.conclusion or check.conclusion == "PENDING" then
			pending = pending + 1
		end
	end

	if failing > 0 then
		return "FAILING"
	elseif pending > 0 then
		return "PENDING"
	elseif passing + skipped == total and passing > 0 then
		return "PASSING"
	elseif skipped == total then
		return "SKIPPED"
	else
		return "PENDING"
	end
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
