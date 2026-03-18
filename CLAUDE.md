# fastapi.nvim — Project Context for Agents

## What This Plugin Does

fastapi.nvim is a Neovim plugin for exploring and navigating API route definitions. It currently supports **FastAPI (Python)** and is being extended to support Express.js, Gin, Axum, and Ruby on Rails.

Core features:
- **Route Explorer** — sidebar listing all HTTP routes grouped by source file, with jump-to-definition
- **Fuzzy Picker** — searchable route list via Telescope, Snacks.nvim, or `vim.ui.select`
- **CodeLens Annotations** — virtual text on test client calls linking them to their route handler
- **Auto-Refresh** — debounced file watcher refreshes routes on save

---

## Architecture

The UI layer is **framework-agnostic** — explorer, pickers, and codelens all consume a flat route record:

```lua
{ method = "GET", path = "/users/{id}", func = "get_user", file = "/abs/path.py", line = 42 }
```

The parsing layer is **currently FastAPI-specific** and is being refactored into a provider pattern.

### Module Dependency Graph

```
plugin/fastapi.lua          -- entry: Neovim commands + autocmds
  └─ lua/fastapi/init.lua   -- public API: setup(), toggle(), pick(), refresh(), codelens()
       ├─ config.lua         -- configuration store
       ├─ explorer.lua       -- sidebar UI (consumes cache)
       ├─ picker.lua         -- dispatcher → pickers/{telescope,snacks,builtin}.lua
       ├─ codelens.lua       -- virtual text annotations (consumes parser + cache)
       └─ cache.lua          -- mtime-based file cache
            ├─ parser.lua           -- Tree-sitter analysis engine (hardcoded to Python)
            ├─ app_finder.lua       -- FastAPI() constructor discovery
            ├─ router_resolver.lua  -- follows include_router() calls recursively
            └─ import_resolver.lua  -- Python import → filesystem path resolution
```

### Data Flow

1. `app_finder` locates the file containing `FastAPI()` (3-tier: config → pyproject.toml → heuristic scan)
2. `parser` runs Tree-sitter queries to extract routes, imports, and `include_router()` calls
3. `import_resolver` converts Python import statements to filesystem paths
4. `router_resolver` recursively walks `include_router()` calls, prepends prefixes, builds the full route tree
5. `cache` stores results keyed by file path, validated by mtime
6. `explorer`, `picker`, `codelens` read from the cache for their UIs

---

## Directory Structure

```
fastapi.nvim/
  plugin/
    fastapi.lua               -- Neovim entry point: commands, autocmds
  lua/fastapi/
    init.lua                  -- Public API facade
    config.lua                -- Configuration defaults and merge
    parser.lua                -- Tree-sitter engine (currently Python-only)
    cache.lua                 -- mtime-based file + route tree cache
    explorer.lua              -- Sidebar UI
    codelens.lua              -- Virtual text annotations
    picker.lua                -- Picker backend dispatcher
    app_finder.lua            -- FastAPI app discovery
    router_resolver.lua       -- Route tree builder (follows include_router)
    import_resolver.lua       -- Python import → filepath resolution
    utils.lua                 -- File I/O, path manipulation, globbing
    pickers/
      builtin.lua             -- vim.ui.select backend
      telescope.lua           -- Telescope backend
      snacks.lua              -- Snacks.nvim backend
  queries/python/
    fastapi-routes.scm        -- Route decorator patterns
    fastapi-apps.scm          -- FastAPI() constructor patterns
    fastapi-includes.scm      -- include_router() patterns
    fastapi-imports.scm       -- Python import patterns (generic)
    fastapi-testclient.scm    -- TestClient call patterns
  docs/                       -- Research and planning documents
  tasks/                      -- Implementation task lists
```

---

## Tree-sitter Queries

Queries live in `queries/<language>/<name>.scm`. They are loaded by `parser.lua:get_query()` via `vim.api.nvim_get_runtime_file()`.

**Currently hardcoded to Python** at `parser.lua:42,52,66,79`. The multi-framework refactor will parameterize the language.

Naming convention: `<framework>-<purpose>.scm`
Examples: `fastapi-routes.scm`, `gin-routes.scm`, `axum-routes.scm`

Capture names used by the parser engine:
- `@router_obj` — the variable the route is called on (e.g., `app`, `router`)
- `@http_method` — the method name (`get`, `post`, `put`, etc.)
- `@route_path` — the URL path string
- `@func_name` — the handler function name
- `@route_def` — the full route definition node (for line numbers)

---

## Configuration (`lua/fastapi/config.lua`)

```lua
M.defaults = {
  entry_point = nil,       -- "module:variable" override; nil = auto-detect
  explorer    = { position = "left", width = 40, icons = true },
  picker      = { provider = nil },   -- nil = auto-detect (telescope/snacks/builtin)
  keymaps     = {
    toggle   = "<leader>Ft",
    pick     = "<leader>Fp",
    refresh  = "<leader>Fr",
    codelens = "<leader>Fc",
  },
  codelens    = { enabled = true, test_patterns = { "test_*.py", "*_test.py", "tests/**/*.py" } },
  watch       = { enabled = true, debounce_ms = 200 },
}
```

Merged with `vim.tbl_deep_extend("force", defaults, user_opts)`.

---

## What's FastAPI-Specific vs Generic

### FastAPI-Specific (will become provider pattern)
| File | What it does |
|------|-------------|
| `queries/python/fastapi-*.scm` | Matches `@app.get(...)`, `FastAPI()`, `include_router()` |
| `app_finder.lua` | Finds `FastAPI()` constructor; reads `[tool.fastapi]` in pyproject.toml |
| `router_resolver.lua` | Follows `include_router(prefix=...)` recursively |
| `import_resolver.lua` | Python-specific: dotted paths, relative imports, `__init__.py`, src-layout |
| `parser.lua:ROUTE_METHODS` | FastAPI HTTP method names including `api_route`, `websocket` |

### Generic (UI layer — framework-agnostic)
| File | Why it's generic |
|------|-----------------|
| `explorer.lua` | Renders any `{ method, path, func, file, line }` list |
| `picker.lua` + `pickers/` | Dispatches to any picker backend |
| `codelens.lua` | Virtual text engine; only path param pattern is framework-specific |
| `cache.lua` | mtime cache; data format is route records |
| `utils.lua` | File I/O, path helpers |
| `config.lua` | Standard Neovim plugin config merge |

---

## Multi-Framework Expansion Plan

See `docs/` for per-framework research. The planned provider interface:

```lua
---@class RouteProvider
---@field language string           -- Tree-sitter language ("python", "go", "rust", "ruby")
---@field file_glob string          -- Source files ("**/*.py", "**/*.go", etc.)
---@field test_patterns string[]    -- Test file globs
---@field path_param_pattern string -- Lua regex for path params
---@field detect fun(root: string): boolean
---@field find_app fun(root: string): table|nil
---@field extract_routes fun(filepath: string): table[]
---@field extract_includes fun(filepath: string): table[]
---@field resolve_import fun(file: string, import_info: table, root: string): string|nil
---@field extract_test_calls fun(filepath: string): table[]
```

Providers live in `lua/fastapi/providers/<name>.lua`. The registry (`providers/init.lua`) auto-detects from project marker files.

### Path Parameter Normalization

All frameworks normalize path params to `{param}` at extraction time:

| Style | Frameworks |
|-------|-----------|
| `{param}` | FastAPI, Axum (planned), Chi |
| `:param` | Express, Gin, Rails, Sinatra |
| `<type:name>` | Flask, Django |
| `[param]` | Next.js |

Codelens matching at `codelens.lua:135` currently only handles `{param}`. Must be extended per provider.

---

## Build & Test

No build step. This is a pure Lua Neovim plugin.

**Manual testing**: Open a FastAPI project in Neovim, run `:FastAPI toggle` to verify the explorer, `:FastAPI pick` for the picker, open a test file for codelens.

**No automated test suite exists yet.** When adding tests, use [plenary.nvim](https://github.com/nvim-lua/plenary.nvim)'s test harness.

---

## Coding Conventions

- Lua 5.1 (LuaJIT) compatible — no `table.pack`, avoid 5.2+ syntax
- Use `require("fastapi.module")` not `require("fastapi/module")`
- Error reporting via `vim.notify(msg, vim.log.levels.ERROR)` — never `error()` in callbacks
- All public module functions documented with LuaLS annotations (`---@param`, `---@return`)
- Guard against `nil` from `package.loaded` before calling into dependent modules (see `plugin/fastapi.lua` pattern)
- Prefer `vim.tbl_deep_extend` for config merging
- Tree-sitter node text: use `get_text(node, source)` helper — handles both string and buffer sources

---

## Key Files for New Framework Support

When adding a new framework, these are the files to touch:

1. `queries/<language>/<framework>-routes.scm` — route extraction query
2. `queries/<language>/<framework>-apps.scm` — app/router discovery query
3. `queries/<language>/<framework>-includes.scm` — router composition query (if applicable)
4. `lua/fastapi/providers/<framework>.lua` — provider implementation
5. `lua/fastapi/providers/init.lua` — register provider + add detection logic
6. `lua/fastapi/config.lua` — add per-framework test patterns + file globs
7. `plugin/fastapi.lua` — extend autocmd file patterns beyond `*.py`
