local M = {}

function M.extract_repo_name(repo_data)
	return repo_data and repo_data.name or nil
end

function M.extract_repo_owner(repo_data)
	return repo_data and repo_data.owner and repo_data.owner.login or nil
end

return M
