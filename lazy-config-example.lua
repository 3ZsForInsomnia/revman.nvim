-- Example lazy.nvim configuration for revman.nvim

return {
  "your-username/revman.nvim",
  dependencies = {
    "kkharji/sqlite.lua",
    "nvim-telescope/telescope.nvim", -- Optional: enhanced UI when available
  },
  
  -- Load on VeryLazy (recommended)
  event = "VeryLazy",
  
  config = function()
    require("revman").setup({
      log_level = "warn",
      background = {
        frequency = 15, -- minutes
      },
      picker = {
        backend = "telescope", -- "vimSelect" (default) or "telescope"
      },
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
  
  -- Optional: Add keymaps
  keys = {
    { "<leader>rp", "<cmd>RevmanListPRs<cr>", desc = "List PRs" },
    { "<leader>ro", "<cmd>RevmanListOpenPRs<cr>", desc = "List Open PRs" },
    { "<leader>rr", "<cmd>RevmanReviewPR<cr>", desc = "Review PR" },
    { "<leader>rs", "<cmd>RevmanSyncAllPRs<cr>", desc = "Sync All PRs" },
    { "<leader>rn", "<cmd>RevmanAddNote<cr>", desc = "Add Note" },
  },
}

-- Notes:
-- • Use event = "VeryLazy" for optimal loading
-- • Do NOT use cmd = {...} for lazy loading - it complicates setup
-- • The plugin handles internal lazy loading automatically
-- • Background sync starts immediately on VeryLazy
-- • Commands are lightweight stubs that load functionality on first use