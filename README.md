# revman.nvim

# **revman.nvim** is a Neovim plugin that streamlines your GitHub pull request review workflow—especially when paired with [Octo.nvim](https://github.com/pwntester/octo.nvim). Its primary purpose is to help you track and manage PRs that are waiting for your review, across multiple repositories, all from inside Neovim.

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
- [nvim-telescope/telescope.nvim](https://github.com/nvim-telescope/telescope.nvim)
- [GitHub CLI (`gh`)](https://cli.github.com/) (must be installed and authenticated)
- [pwntester/octo.nvim](https://github.com/pwntester/octo.nvim) (optional, but required for PR review UI and strongly suggested)

Example (Lazy.nvim):

```lua
{
  "yourusername/revman.nvim",
  dependencies = {
    "kkharji/sqlite.lua",
    "nvim-telescope/telescope.nvim",
    -- optional:
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
  database = {
    path = vim.fn.stdpath("state") .. "/revman/revman.db",
  },
  retention = {
    days = 30, -- days to keep PRs (0 = keep forever)
  },
  background = {
    frequency = 15, -- minutes between background syncs (0 = disable)
  },
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

---

For full details and advanced usage, see `:help revman`.

## Roadmap

- [ ] Add images and gifs of usage to the README
- [ ] Simplifying and documenting exposed API
- [ ] Allowing support for other pickers than Telescope
