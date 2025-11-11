local M = {}

-- Create searchable string for PRs that includes number, title, author, and state
function M.pr_searchable(pr)
	local parts = {}
	
	-- Add PR number (both with and without #)
	if pr.number then
		table.insert(parts, "#" .. pr.number)
		table.insert(parts, tostring(pr.number))
	end
	
	-- Add title
	if pr.title then
		table.insert(parts, pr.title)
	end
	
	-- Add author
	if pr.author then
		table.insert(parts, pr.author)
		table.insert(parts, "@" .. pr.author) -- Also searchable with @
	end
	
	-- Add state
	if pr.state then
		table.insert(parts, pr.state:lower())
	end
	
	-- Add review status if available
	if pr.review_status then
		table.insert(parts, pr.review_status)
	end
	
	-- Add repo name if available
	if pr.repo_name then
		table.insert(parts, pr.repo_name)
	end
	
	return table.concat(parts, " ")
end

function M.pr_display(pr)
	local github_prs = require("revman.github.prs")
	local status_icon = ""
	if github_prs.is_merged(pr) then
		status_icon = "✓ "
	elseif pr.state == "CLOSED" then
		status_icon = "✗ "
	elseif pr.is_draft and pr.is_draft == 1 then
		status_icon = "📝 "
	end
	
	local review_status = pr.review_status and (" [" .. pr.review_status .. "]") or ""
	
	return string.format("%s#%s %s%s (%s)", 
		status_icon,
		pr.number, 
		pr.title or "No title",
		review_status,
		pr.author or "unknown"
	)
end

-- Create searchable string for authors/users
function M.author_searchable(author_stats)
	local parts = {}
	
	-- Add author name
	if author_stats.author then
		table.insert(parts, author_stats.author)
		table.insert(parts, "@" .. author_stats.author)
	end
	
	-- Add PR counts for searching by activity level
	if author_stats.prs_opened then
		table.insert(parts, author_stats.prs_opened .. " prs")
		table.insert(parts, author_stats.prs_opened .. " opened")
	end
	
	if author_stats.prs_merged then
		table.insert(parts, author_stats.prs_merged .. " merged")
	end
	
	-- Add qualitative descriptors based on activity
	local prs_opened = author_stats.prs_opened or 0
	if prs_opened > 20 then
		table.insert(parts, "active prolific")
	elseif prs_opened > 10 then
		table.insert(parts, "active")
	elseif prs_opened > 0 then
		table.insert(parts, "contributor")
	end
	
	return table.concat(parts, " ")
end

function M.author_display(author_stats)
	local opened = author_stats.prs_opened or 0
	local merged = author_stats.prs_merged or 0
	local comments = author_stats.comments_written or 0
	
	return string.format("%s (%d PRs, %d merged, %d comments)", 
		author_stats.author or "unknown",
		opened,
		merged, 
		comments
	)
end

-- Create searchable string for repositories
function M.repo_searchable(repo)
	local parts = {}
	
	-- Add repo name (full and short)
	if repo.name then
		table.insert(parts, repo.name)
		-- Add just the repo name without owner
		local short_name = repo.name:match("/(.+)$")
		if short_name then
			table.insert(parts, short_name)
		end
	end
	
	-- Add directory path
	if repo.directory then
		table.insert(parts, repo.directory)
		-- Add just the directory name
		local dir_name = repo.directory:match("([^/]+)/?$")
		if dir_name then
			table.insert(parts, dir_name)
		end
	end
	
	return table.concat(parts, " ")
end

-- Create display string for repositories
function M.repo_display(repo)
	return string.format("%s (%s)", 
		repo.name or "unknown",
		repo.directory or "no directory"
	)
end

-- Create searchable string for notes (by PR info)
function M.note_searchable(pr_with_note)
	-- Reuse PR searchable and add note-specific terms
	local pr_search = M.pr_searchable(pr_with_note)
	local parts = { pr_search, "note", "notes", "documented" }
	
	-- Add content preview if available
	if pr_with_note.note_content then
		-- Add first few words of note content
		local preview = pr_with_note.note_content:match("^%s*(.-)[\n\r]") or pr_with_note.note_content
		if preview and #preview > 10 then
			preview = preview:sub(1, 50) -- First 50 chars
			table.insert(parts, preview)
		end
	end
	
	return table.concat(parts, " ")
end

-- Create display string for notes
function M.note_display(pr_with_note)
	local pr_display = M.pr_display(pr_with_note)
	local note_preview = ""
	
	if pr_with_note.note_content then
		local preview = pr_with_note.note_content:match("^%s*(.-)[\n\r]") or pr_with_note.note_content
		if preview and #preview > 0 then
			preview = preview:sub(1, 60) -- First 60 chars
			if #pr_with_note.note_content > 60 then
				preview = preview .. "..."
			end
			note_preview = " | " .. preview
		end
	end
	
	return pr_display .. note_preview
end

return M