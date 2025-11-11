local M = {}

local with_db = require("revman.db.helpers").with_db
local log = require("revman.log")

function M.get_id(name)
  -- Return null safely if database isn't ready
  local ok, result = pcall(function()
	return with_db(function(db)
		local rows = db:select("review_status", { where = { name = name } })
		if rows[1] then
			return rows[1].id
		else
        return nil
		end
	end)
  end)
  
  if not ok then
    -- Database not ready, return nil silently
    return nil
  end
  
  if not result then
    log.warn("Status not found: " .. name .. " (database may not be fully initialized)")
  end
  
  return result
end

function M.get_name(id)
	if not id then
		return nil
	end

	return with_db(function(db)
		local rows = db:select("review_status", { where = { id = id } })
		return rows[1] and rows[1].name or nil
	end)
end

function M.list()
	return with_db(function(db)
		local rows = db:select("review_status")
		return rows
	end)
end

function M.add_status_transition(pr_id, from_status_id, to_status_id)
	with_db(function(db)
		local ok, err = pcall(function()
			db:insert("review_status_history", {
				pr_id = pr_id,
				from_status_id = from_status_id,
				to_status_id = to_status_id,
				timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
			})
		end)
		if not ok then
			print("Error adding status transition:", err)
		end
	end)
end

function M.get_status_history(pr_id)
	return with_db(function(db)
		local rows = db:select("review_status_history", { where = { pr_id = pr_id } })
		return rows
	end)
end

return M
