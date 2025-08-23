# Revman.nvim Telescope Extension

When Telescope is available, revman.nvim automatically registers a telescope extension providing enhanced picker UI with previews, better search, and additional keymaps.

## Setup

```lua
-- In your lazy.nvim config
{
  "your-username/revman.nvim",
  dependencies = {
    "kkharji/sqlite.lua",
    "nvim-telescope/telescope.nvim", -- Optional but recommended
  },
  config = function()
    require("revman").setup({
      picker = {
        backend = "telescope", -- "vimSelect" (default) or "telescope"
      },
      -- ... other config
    })
    
    -- Load telescope extension if using telescope backend
    local config = require("revman.config").get()
    if config.picker.backend == "telescope" then
      local has_telescope, telescope = pcall(require, "telescope")
      if has_telescope then
        telescope.load_extension("revman")
      end
    end
  end
}
```

## Configuration Options

### Picker Backend

```lua
require("revman").setup({
  picker = {
    backend = "telescope", -- or "vimSelect" (default)
  },
})
```

- **`"vimSelect"`** (default): Uses `vim.ui.select` with enhanced search strings
- **`"telescope"`**: Uses Telescope with previews, advanced keymaps, and rich UI

The picker backend must be explicitly configured - revman.nvim will not automatically detect and use Telescope even if it's installed. This prevents conflicts when multiple picker libraries are available.

## Available Commands

### Both Command Styles Work

You can use **either** command style regardless of your `picker.backend` setting:

#### Traditional Commands (always available)
```
:Telescope revman prs                    " All PRs
:Telescope revman open_prs               " Open PRs  
:Telescope revman prs_needing_review     " PRs needing review
:Telescope revman merged_prs             " Merged PRs
:Telescope revman my_open_prs            " Current user's open PRs
:Telescope revman nudge_prs              " PRs needing a nudge
:Telescope revman authors                " Authors with analytics
:Telescope revman repos                  " Repositories
:Telescope revman notes                  " PR notes
```

#### Telescope Extension Commands (when extension loaded)
```
:RevmanListPRs                           " All PRs
:RevmanListOpenPRs                       " Open PRs
:RevmanListPRsNeedingReview             " PRs needing review
:RevmanListMergedPRs                    " Merged PRs
:RevmanListMyOpenPRs                    " Current user's open PRs
:RevmanNudgePRs                         " PRs needing a nudge  
:RevmanListAuthors                      " Authors with analytics
:RevmanListRepos                        " Repositories
:RevmanShowNotes                        " PR notes
```

### Behavior by Backend Configuration

- **`backend = "vimSelect"`**: Both command styles use vim.ui.select
- **`backend = "telescope"`**: Both command styles use Telescope UI
- **Telescope extension**: `:Telescope revman` commands always use Telescope (regardless of backend setting)

## Telescope-Specific Features

### Enhanced Search
- **PRs**: Search by PR number (#123), title, author (@username), state, review status
- **Authors**: Search by username (@author), PR counts, activity level (active, prolific, contributor)
- **Repositories**: Search by full name (owner/repo), short name (repo), directory path
- **Notes**: Search by PR info plus note content preview

### Keymaps (Telescope only)
- `<C-b>` - Open PR in browser (PR pickers)
- `<C-s>` - Set PR status (PR pickers)
- `<CR>` - Select item
- All standard Telescope navigation

### Previews
- **PRs**: Shows PR details, CI status, review status, timing info
- **Authors**: Shows detailed analytics and statistics  
- **Notes**: Shows note content with markdown highlighting

## Fallback Behavior

When picker backend is set to `"vimSelect"` or when Telescope is not available, all commands use `vim.ui.select` with:
- Enhanced searchable strings (same search terms)
- Consistent functionality
- Slightly reduced UX (no previews, fewer keymaps)

## Troubleshooting

### Check Configuration
Run `:checkhealth revman` to verify:
- Current picker backend setting
- Telescope availability (if using telescope backend)
- Extension loading status

### Common Issues
- **"Picker backend set to 'telescope' but telescope.nvim is not available"**: Install telescope.nvim or change to `picker.backend = "vimSelect"`
- **Telescope commands not working**: Ensure `telescope.load_extension("revman")` is called after setup
- **Multiple pickers acting weird**: Set explicit `picker.backend` instead of relying on auto-detection

## Configuration

The telescope extension respects your telescope configuration for:
- Color schemes and highlights
- General keymaps and behavior
- Layout and sizing preferences

### Extension Configuration

You can customize the revman telescope extension:

```lua
require("telescope").setup({
  extensions = {
    revman = {
      layout_strategy = "horizontal", -- or "vertical", "center", etc.
      layout_config = {
        preview_width = 0.6,
        width = 0.9,
        height = 0.8,
      },
      sorting_strategy = "ascending", -- or "descending"
    },
  },
})

require("telescope").load_extension("revman")
```

All standard telescope configuration options are supported.
