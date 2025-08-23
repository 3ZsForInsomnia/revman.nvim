# Configuration

## Recommended Setup

Use `event = "VeryLazy"` for optimal loading. **Do not** use `cmd = {...}` for lazy loading as it complicates the setup process.

```lua
-- lazy.nvim
{
  "your-username/revman.nvim",
  dependencies = {
    "kkharji/sqlite.lua",
    "nvim-telescope/telescope.nvim", -- Optional but recommended
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
    if config.picker.backend == "telescope" then
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
background = {
  frequency = 15, -- minutes between syncs (0 to disable)
}
```

### Database

```lua
database = {
  path = vim.fn.stdpath("state") .. "/revman/revman.db",
}
```

### Logging

```lua
log_level = "warn", -- "info", "warn", or "error"
```

## Health Check

Run `:checkhealth revman` to verify your setup and troubleshoot any issues.