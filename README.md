# revman.nvim

An easier way to track multiple PRs that you are reviewing.

NOTE: This plugin is in early development and may change significantly. It is still a bit buggy, so feel free to report issues or contribute!

revman.nvim is a Neovim plugin designed to make tracking, reviewing, and managing multiple GitHub pull requests (PRs) easier for busy developers and code reviewers. If you regularly review PRs across several repositories, keeping track of their status, your review notes, and which ones need your attention can quickly become overwhelming. revman.nvim centralizes this workflow inside Neovim, providing local analytics, note-taking, and seamless integration with GitHub and popular Neovim plugins like Telescope and Octo.nvim.

With revman.nvim, you can sync PRs from GitHub into a local SQLite database, browse and filter them using Telescope pickers, and keep personal notes for each PR. The plugin tracks review status, CI results, and your review history, helping you prioritize which PRs need action—such as those waiting for your review or needing a follow-up. Analytics features let you see trends by author or repository, and background sync ensures your local data stays up to date.

**Typical User Flow:**

1. **Sync PRs:** Start by running `:RevmanSyncAllPRs` to fetch all PRs for your current repository. PRs are stored locally, so you can browse and filter them even when offline.
2. **Browse & Filter:** Use commands like `:RevmanListOpenPRs` or `:RevmanListPRs` to open Telescope pickers and quickly find PRs by status, author, or repository.
3. **Review & Take Notes:** Select a PR to review with `:RevmanReviewPR`, which can open the PR in Octo.nvim for a rich review UI. Add or update your personal notes with `:RevmanAddNote`, and save them with a single keypress.
4. **Track Status:** Update the review status of a PR with `:RevmanSetStatus`, and let the plugin remind you of PRs needing a nudge or follow-up.
5. **Stay Up to Date:** Enable background sync to keep your PR list fresh, and use analytics commands to gain insights into your review habits and PR throughput.

revman.nvim is ideal for developers who want to streamline their PR review workflow, keep organized notes, and never lose track of what needs their attention—all without leaving Neovim.

---

## Requirements

- [Neovim](https://neovim.io/) 0.7+
- [kkharji/sqlite.lua](https://github.com/kkharji/sqlite.lua) (for local database)
- [GitHub CLI (`gh`)](https://cli.github.com/) (must be installed and authenticated)
- [nvim-telescope/telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) (for pickers)
- [pwntester/octo.nvim](https://github.com/pwntester/octo.nvim) (optional, for PR review UI)

---

## Installation

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

You must call `require("revman").setup()` in your Neovim config to initialize the plugin.
If you use a plugin manager like Lazy.nvim, this is handled automatically using `config = true`
If you use another manager or manual loading, ensure you call `setup()` yourself.

> [!note]
> Changing the plugin configuration while Neovim is running is not supported and may cause errors or inconsistent behavior.  
> Always restart Neovim after changing revman.nvim configuration.


```lua
require("revman").setup({
  database = {
    path = vim.fn.stdpath("state") .. "/revman/revman.db", -- default
  },
  retention = {
    days = 30, -- days to keep PRs (0 = keep forever)
  },
  background = {
    frequency = 15, -- minutes between background syncs (0 = disable)
  },
  keymaps = {
    save_notes = "<leader>zz", -- keybinding to save notes buffer
  },
  log_level = "warn", -- "info", "warn", or "error"
})
```

---

## Commands

| Command                        | Description                                                      |
|--------------------------------|------------------------------------------------------------------|
| `:RevmanSyncAllPRs`            | Sync all PRs for the current repo from GitHub                    |
| `:RevmanSyncPR {pr_number}`    | Sync a single PR by number from GitHub                           |
| `:RevmanListPRs`               | List all PRs (Telescope picker)                                  |
| `:RevmanListOpenPRs`           | List open PRs (Telescope picker)                                 |
| `:RevmanListMergedPRs`         | List merged PRs (Telescope picker)                               |
| `:RevmanListRepos`             | List all known repositories (Telescope picker)                   |
| `:RevmanListAuthors`           | List PR authors with analytics preview (Telescope picker)        |
| `:RevmanReviewPR [pr_id/number]` | Mark PR as reviewed, open in Octo, update status/timestamps   |
| `:RevmanSetStatus [pr_id/number]` | Set PR status (dropdown select)                              |
| `:RevmanAddNote [pr_id/number]`   | Open buffer to add/update note for PR (save with keymap)      |
| `:RevmanShowNotes [pr_id/number]` | Show notes for PR in a new buffer                             |
| `:RevmanNudgePRs`              | List PRs needing a nudge (attention)                             |
| `:RevmanEnableBackgroundSync`  | Enable background sync                                           |
| `:RevmanDisableBackgroundSync` | Disable background sync                                          |

- For PR-specific commands, if no PR ID/number is given, you will be prompted to select one.
- For status selection, a dropdown will appear.
- Notes are edited in a buffer and saved with the configured keybinding.

---

## Sync Behavior

- **Manual Sync:**  
  Use `:RevmanSyncAllPRs` or `:RevmanSyncPR` to fetch PRs from GitHub and update the local database.
- **Background Sync:**  
  If enabled (`background.frequency > 0`), PRs are synced automatically every N minutes.
  Enable/disable with `:RevmanEnableBackgroundSync` / `:RevmanDisableBackgroundSync`.
- **Sync on Startup:**  
  If background sync is enabled, it starts automatically on plugin setup.

---

## Configuration Options

| Option                        | Default                                      | Description                          |
|-------------------------------|----------------------------------------------|--------------------------------------|
| `database.path`               | `vim.fn.stdpath("state") .. "/revman/revman.db"` | Path to the SQLite database      |
| `retention.days`              | `30`                                         | Days to keep PRs (0 = keep forever)  |
| `background.frequency`        | `15`                                         | Minutes between background syncs (0 = disable) |
| `keymaps.save_notes`          | `"<leader>zz"`                               | Keybinding to save notes buffer      |

---

## Health Check

Run `:checkhealth revman` to verify all requirements and configuration.

---

## Features

- Track PRs, review status, review history, and CI status
- Add and edit personal notes for any PR
- List and filter PRs by status, repo, author, etc.
- Analytics on PRs and authors (age, review frequency, etc.)
- Background and manual sync with GitHub
- Integration with Octo.nvim for PR review UI

## TODO

Add error handling and logging everywhere

Fix analytics data retrieval
- And previews, right now is pretty simple
