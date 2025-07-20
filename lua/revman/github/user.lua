local M = {}

function M.extract_user_login(user_data)
	return user_data and user_data.login or nil
end

return M
