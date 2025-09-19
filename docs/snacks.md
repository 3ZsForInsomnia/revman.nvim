# Snacks Integration

Using revman.nvim with [snacks.nvim](https://github.com/folke/snacks.nvim) picker.

## Setup

```lua
require("revman").setup({
  picker = "snacks",
})
```

Requires [snacks.nvim](https://github.com/folke/snacks.nvim) with picker enabled.

## Usage

All standard revman commands work automatically with the snacks backend:

```vim
:RevmanListPRs
:RevmanListOpenPRs  
:RevmanReviewPR
" ... etc
```

### Direct Lua Functions

```lua
require("revman.snacks").prs()
require("revman.snacks").open_prs()
require("revman.snacks").authors()
require("revman.snacks").repos()
```

### Snacks-Specific Commands

```vim
:SnacksRevmanPRs
:SnacksRevmanOpenPRs
:SnacksRevmanAuthors
:SnacksRevmanRepos
```

### Optional: Register as Snacks Sources

```lua
-- Enable Snacks.revman.* functions
require("revman.snacks.sources").setup()

-- Then use:
Snacks.revman.prs()
Snacks.picker.pick("revman_prs")
```

## Keybindings

- `<C-b>` - Open PR in browser
- `<C-s>` - Set PR review status

## Troubleshooting

Run `:checkhealth revman` to verify setup.
