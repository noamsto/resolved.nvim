# resolved.nvim

Surface stale issue/PR references in your code. When a GitHub issue you're working around gets closed, resolved.nvim lets you know it's time to clean up.

## The Problem

```lua
-- TODO: Remove this workaround when https://github.com/neovim/neovim/issues/12345 is fixed
local function ugly_hack()
  -- ...
end
```

Months later, the issue is closed. But the workaround lives on, forgotten.

## The Solution

resolved.nvim scans your code for GitHub issue/PR URLs in comments and shows their status:

- **Stale** (closed + keywords like TODO/FIXME): ⚠ gutter sign, yellow strikethrough URL
- **Closed** (no keywords): Subtle strikethrough, hint color
- **Open**: Green status indicator

![screenshot](https://github.com/user-attachments/assets/placeholder.png)

## Requirements

- Neovim 0.10+
- [GitHub CLI](https://cli.github.com/) (`gh`) - must be authenticated
- [plenary.nvim](https://github.com/nvim-lua/plenary.nvim)
- [nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter) (recommended)

## Installation

### lazy.nvim

```lua
{
  "noams/resolved.nvim",
  dependencies = { "nvim-lua/plenary.nvim" },
  event = "VeryLazy",
  opts = {},
}
```

### packer.nvim

```lua
use {
  "noams/resolved.nvim",
  requires = { "nvim-lua/plenary.nvim" },
  config = function()
    require("resolved").setup()
  end,
}
```

## Security

This plugin takes security seriously. All external commands are executed safely via plenary.job with proper argument separation and timeouts. URLs are validated before processing. See [SECURITY.md](docs/SECURITY.md) for details.

If you discover a security vulnerability, please see our [security policy](docs/SECURITY.md#reporting-a-vulnerability).

## Configuration

Default configuration (all optional):

```lua
require("resolved").setup({
  -- Enable on startup
  enabled = true,

  -- Cache TTL in seconds
  cache_ttl = 300,

  -- Debounce delay for buffer scanning
  debounce_ms = 500,

  -- Keywords indicating workarounds (triggers "stale" when issue closes)
  stale_keywords = {
    "TODO", "FIXME", "HACK", "XXX", "WA",
    "workaround", "temporary", "temp", "WIP",
    "blocked", "waiting", "upstream",
  },

  -- Per-filetype treesitter node types to search
  filetypes = {
    lua = { node_types = { "comment" } },
    python = { node_types = { "comment", "string" } },
    rust = { node_types = { "line_comment", "block_comment" } },
    -- Disable for a filetype:
    markdown = false,
    -- Fallback for unlisted filetypes:
    ["*"] = { node_types = { "comment" } },
  },

  -- Show gutter signs for stale references
  signs = true,

  -- Icons
  icons = {
    stale = "⚠",
    stale_sign = "⚠",
    open = "",
  },

  -- Highlight groups
  highlights = {
    stale = "DiagnosticWarn",
    stale_sign = "DiagnosticWarn",
    stale_url = "ResolvedStaleUrl",
    closed = "DiagnosticHint",
    closed_url = "ResolvedClosedUrl",
    open = "DiagnosticOk",
  },

  -- Icon provider: "mini", "devicons", or false for defaults
  icon_provider = false,
})
```

## Commands

Single command with tab completion:

```
:Resolved <Tab>    → show all subcommands
:Resolved          → show status
```

| Command                  | Description                  |
| ------------------------ | ---------------------------- |
| `:Resolved`              | Show plugin status           |
| `:Resolved enable`       | Enable the plugin            |
| `:Resolved disable`      | Disable the plugin           |
| `:Resolved toggle`       | Toggle enabled state         |
| `:Resolved refresh`      | Refresh current buffer       |
| `:Resolved clear_cache`  | Clear the issue status cache |
| `:Resolved status`       | Show plugin status           |

## Lua API

```lua
local resolved = require("resolved")

resolved.is_enabled()  -- Check if enabled
resolved.enable()      -- Enable
resolved.disable()     -- Disable
resolved.toggle()      -- Toggle
resolved.refresh()     -- Refresh current buffer
resolved.refresh_all() -- Refresh all visible buffers
resolved.clear_cache() -- Clear cache
```

## Integrations

### snacks.nvim

```lua
Snacks.toggle.new({
  name = "Resolved",
  get = function()
    return require("resolved").is_enabled()
  end,
  set = function(state)
    if state then
      require("resolved").enable()
    else
      require("resolved").disable()
    end
  end,
}):map("<leader>uR")
```

### lualine.nvim

```lua
{
  function()
    if require("resolved").is_enabled() then
      return "⚠"
    end
    return ""
  end,
  cond = function()
    return package.loaded["resolved"] ~= nil
  end,
}
```

## Health Check

Verify your setup with `:checkhealth resolved`:

```
resolved.nvim
- OK gh CLI found: /usr/bin/gh
- OK gh CLI authenticated
- OK nvim-treesitter installed
- OK Plugin initialized
- OK Plugin enabled
```

## How It Works

1. **Scan**: Treesitter finds comments, regex extracts GitHub URLs
2. **Fetch**: Queries GitHub API via `gh` CLI (cached)
3. **Display**: Inline status after URL, strikethrough for closed issues

## Tier System

| Tier       | Condition                   | Display                                     |
| ---------- | --------------------------- | ------------------------------------------- |
| **Stale**  | Closed/merged + keywords    | ⚠ gutter, yellow strikethrough, `[closed]` |
| **Closed** | Closed/merged, no keywords  | Strikethrough, `[closed]` in hint color     |
| **Open**   | Still open or "not_planned" | `[open]` in green                           |

Issues closed as "not_planned" (won't fix) are treated as open—your workaround is still needed.

## Why Keywords Matter

Not every closed issue reference is stale. Documentation references remain valid.

But when your comment says `TODO: remove when #123 is fixed` and #123 is now closed—you want to know. That's what stale keywords detect.

## Development

### Running Tests

Tests are written using [plenary.nvim](https://github.com/nvim-lua/plenary.nvim).

```bash
# Run all tests
nvim --headless -c "lua require('plenary.busted').run('tests/resolved/')" -c "qa"

# Run specific test file
nvim --headless -c "lua require('plenary.busted').run('tests/resolved/patterns_spec.lua')" -c "qa"
```

### Test Coverage

The plugin has comprehensive test coverage including:
- URL pattern extraction and validation
- Multi-line comment handling
- Async operation race conditions
- Buffer validity checks
- Configuration validation
- Timer lifecycle management

### Code Quality

- All code follows Lua best practices
- Type annotations using LuaLS format
- Comprehensive error handling with logging
- Security-first design (input validation, safe command execution)

## License

MIT
