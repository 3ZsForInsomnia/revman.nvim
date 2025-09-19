# Configuration

## Recommended Setup

```lua
require("revman").setup({
  database_path = vim.fn.stdpath("state") .. "/revman/revman.db",
  data_retention_days = 30,
  background_sync_frequency = 15,
  picker = "telescope",
  log_level = "warn",
})
```
Use `event = "VeryLazy"` for optimal loading. **Do not** use `cmd = {...}` for lazy loading as it complicates the setup process.

```lua
-- lazy.nvim
{
  "3ZsForInsomnia/revman.nvim",
  dependencies = {
    "kkharji/sqlite.lua",
  },
  event = "VeryLazy",
  config = function()
    require("revman").setup({
      picker = {
        backend = "telescope", -- or "vimSelect" (default)
      },
      background = {
        frequency = 15, -- minutes (0 to disable)
      },
      log_level = "warn", -- "info", "warn", or "error"
    })
    
    -- Load telescope extension if using telescope backend
    local config = require("revman.config").get()
    if config.picker == "telescope" then
      local has_telescope, telescope = pcall(require, "telescope")
      if has_telescope then
        telescope.load_extension("revman")
      end
    end
  end,
}
```

## Why VeryLazy?

- ✅ **Background sync starts immediately** after Neovim loads
- ✅ **Commands available right away** (lightweight stubs)
- ✅ **Functionality loads on-demand** when first used
- ✅ **Simple configuration** - no complex `cmd` arrays needed
- ✅ **Reliable loading** - avoids timing issues

## Configuration Options

### Picker Backend

```lua
picker = {
  backend = "telescope", -- or "vimSelect"
}
```

- **`"vimSelect"`** (default): Uses `vim.ui.select` - works everywhere
- **`"telescope"`**: Enhanced UI with previews and advanced features

### Background Sync

```lua
-- Background sync configuration
background_sync_frequency = 15 -- minutes between syncs (0 to disable)

-- Database configuration  
database_path = vim.fn.stdpath("state") .. "/revman/revman.db"

-- Data retention configuration
data_retention_days = 30 -- days to keep PRs (0 = keep forever)

-- Picker backend configuration
picker = "vimSelect" -- "vimSelect", "telescope", or "snacks"
```

### Logging

```lua
log_level = "warn", -- "info", "warn", or "error"
```

## Health Check

Run `:checkhealth revman` to verify your setup and troubleshoot any issues.
