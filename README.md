# fastapi.nvim

A Neovim plugin for exploring, navigating, and testing [FastAPI](https://fastapi.tiangolo.com/) applications. Browse your routes in a sidebar explorer, jump to handlers via fuzzy picker, and see CodeLens annotations linking test client calls to their route definitions.

## Features

- **Route Explorer** — Toggle a sidebar that displays all routes grouped by source file, with a clean flat layout.
- **Fuzzy Picker** — Search and jump to any route handler using Telescope, Snacks.nvim, or the built-in `vim.ui.select`.
- **CodeLens Annotations** — Virtual text on test client calls (e.g. `client.get("/users")`) showing the matched route handler and its location.
- **Auto-Refresh** — File watcher detects Python file saves and refreshes the explorer and CodeLens automatically.
- **Smart Discovery** — Finds your FastAPI app via config override, `pyproject.toml`, or heuristic scan.

## Requirements

- Neovim >= 0.10
- [Tree-sitter Python parser](https://github.com/nvim-treesitter/nvim-treesitter) installed
- **Optional:** [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) or [snacks.nvim](https://github.com/folke/snacks.nvim) for enhanced picker UIs

## Installation

### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "mrpbennett/fastapi.nvim",
  ft = "python",
  dependencies = {
    "nvim-treesitter/nvim-treesitter",
    -- optional picker backends:
    -- "nvim-telescope/telescope.nvim",
    -- "folke/snacks.nvim",
  },
  opts = {},
}
```

### [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  "mrpbennett/fastapi.nvim",
  requires = { "nvim-treesitter/nvim-treesitter" },
  config = function()
    require("fastapi").setup()
  end,
}
```

## Configuration

All options below are shown with their defaults. Pass only what you want to change:

```lua
require("fastapi").setup({
  -- Override auto-detection with "module.path:variable" format
  entry_point = nil,

  explorer = {
    position = "left",  -- "left" or "right"
    width = 40,
    icons = true,       -- requires a Nerd Font
  },

  picker = {
    provider = nil, -- "telescope", "snacks", or "builtin" (nil = auto-detect)
  },

  keymaps = {
    toggle   = "<leader>Ft", -- toggle explorer sidebar
    pick     = "<leader>Fp", -- open route picker
    refresh  = "<leader>Fr", -- refresh route cache
    codelens = "<leader>Fc", -- toggle codelens
  },

  codelens = {
    enabled = true,
    test_patterns = { "test_*.py", "*_test.py", "tests/**/*.py" },
  },

  watch = {
    enabled = true,
    debounce_ms = 200,
  },
})
```

## Usage

### Commands

All commands are available under the `:FastAPI` prefix:

| Command             | Description                 |
| ------------------- | --------------------------- |
| `:FastAPI toggle`   | Toggle the explorer sidebar |
| `:FastAPI pick`     | Open the route picker       |
| `:FastAPI refresh`  | Refresh the route cache     |
| `:FastAPI codelens` | Toggle CodeLens annotations |

### Keymaps

Default keymaps (all configurable, set to `false` to disable):

| Keymap       | Action          |
| ------------ | --------------- |
| `<leader>Ft` | Toggle explorer |
| `<leader>Fp` | Open picker     |
| `<leader>Fr` | Refresh routes  |
| `<leader>Fc` | Toggle CodeLens |

### Explorer Sidebar

The explorer groups routes by source file. The main app file appears first, followed by router files alphabetically. When your active buffer belongs to a file that contains routes, the explorer automatically filters to show only that file's routes.

```
 FastAPI App (main.py)
──────────────────────────────────────
 main.py
   GET       /              → root()
   GET       /health        → health_check()

 routers/items.py
   GET       /items         → get_all_items()
   POST      /items         → create_item()
```

Pressing `<CR>` or `o` on a file header jumps to that file; pressing it on a route line jumps to the handler definition.

When the explorer is open, these buffer-local keymaps are available:

| Key          | Action                   |
| ------------ | ------------------------ |
| `<CR>` / `o` | Jump to route or file    |
| `s`          | Open in horizontal split |
| `v`          | Open in vertical split   |
| `r`          | Refresh routes           |
| `q`          | Close the sidebar        |

### CodeLens in Test Files

When CodeLens is enabled and you open a test file matching one of the configured patterns, virtual text annotations appear on test client calls showing the matched handler:

```
client.get("/users/123")  -> get_user() app/routers/users.py:15
```

Press `gd` on an annotated line to jump to the route definition.

## App Discovery

The plugin locates your FastAPI application in this order:

1. **Config override** — Set `entry_point = "app.main:app"` to skip detection entirely.
2. **pyproject.toml** — Reads the `[tool.fastapi]` section for an `app` key.
3. **Heuristic scan** — Searches Python files for `FastAPI()` constructor calls, preferring shallower paths (e.g. `main.py` over `src/app/core/main.py`).

## Highlight Groups

All highlights ship with sensible defaults and can be overridden:

| Group                    | Default        |
| ------------------------ | -------------- |
| `FastapiMethodGET`       | Green, bold    |
| `FastapiMethodPOST`      | Blue, bold     |
| `FastapiMethodPUT`       | Yellow, bold   |
| `FastapiMethodPATCH`     | Orange, bold   |
| `FastapiMethodDELETE`    | Red, bold      |
| `FastapiMethodOPTIONS`   | Purple, bold   |
| `FastapiMethodHEAD`      | Cyan, bold     |
| `FastapiMethodTRACE`     | Gray, bold     |
| `FastapiMethodWEBSOCKET` | Teal, bold     |
| `FastapiTitle`           | Orange, bold   |
| `FastapiRouter`          | Purple, italic |
| `FastapiPath`            | Light gray     |
| `FastapiFunc`            | Cyan           |

## License

MIT

# fastapi.nvim
