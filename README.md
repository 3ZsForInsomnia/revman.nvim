# revman.nvim


The core workflow is simple:
- **Add a PR** to your local database.
- **Browse PRs** (especially those "waiting for review") using Telescope.
- **Open the PR in Octo.nvim** for a full-featured review.
- **Mark the PR as "waiting for changes"** when you’re done.
- **Optionally add a note** for future references outside of comments.
- **Let revman.nvim sync PRs in the background** so your review queue is always up to date.

And it also includes features like analytics and advanced filtering - handy extras to help you stay organized and productive!

---

## Typical Workflow

1. **Add your repo:**  
   Use `:RevmanAddRepo` in your project directory to register the current repo.

2. **Sync PRs:**  
   Run `:RevmanSyncAllPRs` to fetch PRs from GitHub into a local SQLite database.

3. **Browse & Filter:**  
   Use Telescope-powered commands like `:RevmanListOpenPRs` or `:RevmanListPRs` to find and select PRs.

4. **Review & Take Notes:**  
   Open a PR for review with `:RevmanReviewPR` (opens in Octo.nvim if installed).  
   Add or edit notes with `:RevmanAddNote`.

5. **Track Status:**  
   Update PR review status with `:RevmanSetStatus`.

6. **Stay Up to Date:**  
   Enable background sync with `:RevmanEnableBackgroundSync` to keep your PR list fresh.

---

## Installation

Requirements:
- Neovim 0.7+
- [kkharji/sqlite.lua](https://github.com/kkharji/sqlite.lua)
- [GitHub CLI (`gh`)](https://cli.github.com/) (must be installed and authenticated)
- [pwntester/octo.nvim](https://github.com/pwntester/octo.nvim) (optional, but required for PR review UI and strongly suggested)

A Picker is strongly recommended. Supported pickers:
- [Snacks Picker](https://github.com/folke/snacks.nvim/blob/main/docs/picker.md)
- [nvim-telescope/telescope.nvim](https://github.com/nvim-telescope/telescope.nvim)

Example (Lazy.nvim):

```lua
{
  "3ZsForInsomnia/revman.nvim",
  dependencies = {
    "kkharji/sqlite.lua",
    "pwntester/octo.nvim",
  },
  config = true,
}
```

---

## Setup

Call `require("revman").setup()` in your config.  
Example:

```lua
require("revman").setup({
  database_path = vim.fn.stdpath("state") .. "/revman/revman.db",
  data_retention_days = 30, -- days to keep PRs (0 = keep forever)
  background_sync_frequency = 15, -- minutes between background syncs (0 = disable)
  
  -- Auto-assignment features
  auto_add_assigned_prs = "smart", -- "smart", "smart+manual", "manual", "off"
  remove_unassigned_prs = "smart", -- "smart", "always", "never"
  
  picker = "vimSelect", -- "vimSelect", "telescope", or "snacks"
  log_level = "warn", -- "info", "warn", or "error"
})
```

---

## Main Commands

| Command                        | Description                                |
|--------------------------------|--------------------------------------------|
| `:RevmanAddRepo`               | Add current repo to tracking               |
| `:RevmanSyncAllPRs`            | Sync all PRs for the current repo          |
| `:RevmanListPRs`               | List all PRs (Telescope picker)            |
| `:RevmanListOpenPRs`           | List open PRs (Telescope picker)           |
| `:RevmanListMergedPRs`         | List merged PRs (Telescope picker)         |
| `:RevmanReviewPR`              | Mark PR as reviewed and open for review    |
| `:RevmanSetStatus`             | Set review status for a PR                 |
| `:RevmanAddNote`               | Add or edit a note for a PR                |
| `:RevmanShowNotes`             | Browse PR notes (Telescope picker)         |
| `:RevmanEnableBackgroundSync`  | Enable background PR sync                  |
| `:RevmanDisableBackgroundSync` | Disable background PR sync                 |
| `:RevmanListAssignedPRs`       | List PRs where you're assigned/requested   |
| `:RevmanRepairDB`              | Repair and upgrade database schema         |

---

For full details and advanced usage, see `:help revman`.

## Auto-Assignment Features

RevMan.nvim can automatically track PRs where you're assigned or your review is requested, keeping your review queue up to date without manual intervention.

### Configuration Options

**`auto_add_assigned_prs`** - Controls when PRs are automatically added to tracking:
- `"smart"` (default): Automatically add PRs where you're assigned or review-requested
- `"smart+manual"`: Auto-add like smart mode, but also show `:RevmanListAssignedPRs` for manual selection
- `"manual"`: Only add PRs via `:RevmanListAssignedPRs` command (no auto-add)
- `"off"`: Disable auto-assignment features entirely

**`remove_unassigned_prs`** - Controls when PRs are automatically removed from tracking:
- `"smart"` (default): Remove PRs when you're unassigned, but keep them if you've interacted (notes, comments, status changes, recent views)
- `"always"`: Always remove PRs when you're unassigned (ignores interaction)
- `"never"`: Never automatically remove PRs

### How It Works

1. **Assignment Detection**: The plugin treats being assigned to a PR and having your review requested as equivalent
2. **Smart Removal**: In "smart" mode, PRs are only removed if you haven't:
   - Added notes to the PR
   - Commented on the PR  
   - Changed the PR's review status
3. **Background Sync**: Auto-assignment runs during background sync to keep your queue current
4. **Manual Override**: Use `:RevmanListAssignedPRs` to manually select from assigned/requested PRs

### Example Workflows

**For active reviewers** (recommended):
```lua
auto_add_assigned_prs = "smart",
remove_unassigned_prs = "smart",
```
This automatically manages your review queue while protecting PRs you've interacted with.

**For manual control**:
```lua
auto_add_assigned_prs = "manual", 
remove_unassigned_prs = "never",
```
You manually select which assigned PRs to track, and they stay tracked until you remove them.

**For comprehensive tracking**:
```lua
auto_add_assigned_prs = "smart+manual",
remove_unassigned_prs = "smart", 
```
Auto-adds assigned PRs but also provides `:RevmanListAssignedPRs` for additional manual selection.

## Roadmap

- [ ] Simplifying and documenting exposed API
