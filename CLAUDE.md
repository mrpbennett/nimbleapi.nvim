# nimbleapi.nvim — Project Context for Agents

## What This Plugin Does

nimbleapi.nvim is a Neovim plugin for exploring and navigating API route definitions. It supports **FastAPI (Python)** and **Spring / Spring Boot (Java)**, with plans to add Express.js, Gin, Axum, and Ruby on Rails.

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

The parsing layer uses a **provider pattern** — each framework implements a provider that handles detection, route extraction, and app discovery.

### Module Dependency Graph

```
plugin/nimbleapi.lua          -- entry: Neovim commands + autocmds
  └─ lua/nimbleapi/init.lua   -- public API: setup(), toggle(), pick(), refresh(), codelens(), info()
       ├─ config.lua           -- configuration store
       ├─ explorer.lua         -- sidebar UI (consumes cache)
       ├─ picker.lua           -- dispatcher → pickers/{telescope,snacks,builtin}.lua
       ├─ codelens.lua         -- virtual text annotations (consumes provider + cache)
       └─ cache.lua            -- mtime-based file cache
            ├─ providers/init.lua      -- provider registry + auto-detection + diagnostics
            ├─ providers/fastapi.lua   -- FastAPI provider (Python)
            ├─ providers/springboot.lua -- Spring/Spring Boot provider (Java)
            ├─ parser.lua              -- Tree-sitter analysis engine (multi-language)
            ├─ app_finder.lua          -- FastAPI() constructor discovery
            ├─ router_resolver.lua     -- follows include_router() calls recursively
            └─ import_resolver.lua     -- Python import → filesystem path resolution
```

### Data Flow

#### FastAPI (Python)
1. `app_finder` locates the file containing `FastAPI()` (3-tier: config → pyproject.toml → heuristic scan)
2. `parser` runs Tree-sitter queries to extract routes, imports, and `include_router()` calls
3. `import_resolver` converts Python import statements to filesystem paths
4. `router_resolver` recursively walks `include_router()` calls, prepends prefixes, builds the full route tree

#### Spring / Spring Boot (Java)
1. Provider detects project via `spring-boot-starter-web`, `spring-webmvc`, or `spring-web` in pom.xml/build.gradle
2. Finds entry point: `@SpringBootApplication` class, or falls back to first `@Controller`/`@RestController`
3. Two-pass extraction: class-level `@RequestMapping` prefix + method-level `@GetMapping` etc.
4. No cross-file router resolution needed (annotation model is self-contained per class)

#### Common
5. `cache` stores results keyed by file path, validated by mtime
6. `explorer`, `picker`, `codelens` read from the cache for their UIs

---

## Directory Structure

```
nimbleapi.nvim/
  plugin/
    nimbleapi.lua             -- Neovim entry point: commands, autocmds
  lua/nimbleapi/
    init.lua                  -- Public API facade
    config.lua                -- Configuration defaults and merge
    parser.lua                -- Tree-sitter engine (multi-language)
    cache.lua                 -- mtime-based file + route tree cache
    explorer.lua              -- Sidebar UI
    codelens.lua              -- Virtual text annotations
    picker.lua                -- Picker backend dispatcher
    app_finder.lua            -- FastAPI app discovery
    router_resolver.lua       -- Route tree builder (follows include_router)
    import_resolver.lua       -- Python import → filepath resolution
    utils.lua                 -- File I/O, path manipulation, globbing
    providers/
      init.lua                -- Provider registry, detection, diagnostics
      fastapi.lua             -- FastAPI provider (Python)
      springboot.lua          -- Spring / Spring Boot provider (Java)
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
  queries/java/
    springboot-routes.scm     -- Method-level route annotations
    springboot-controllers.scm -- Class-level @RequestMapping prefix
    springboot-apps.scm       -- @SpringBootApplication detection
    springboot-testclient.scm -- MockMvc/WebTestClient patterns
  docs/                       -- Research and planning documents
  tasks/                      -- Implementation task lists
```

---

## Tree-sitter Queries

Queries live in `queries/<language>/<name>.scm`. They are loaded by `parser.lua:get_query()` via `vim.api.nvim_get_runtime_file()`.

Naming convention: `<framework>-<purpose>.scm`
Examples: `fastapi-routes.scm`, `springboot-routes.scm`, `gin-routes.scm`

Capture names used by the parser engine:
- `@router_obj` — the variable the route is called on (e.g., `app`, `router`)
- `@http_method` — the method name (`get`, `post`, `put`, etc.)
- `@route_path` — the URL path string
- `@func_name` — the handler function name
- `@route_def` — the full route definition node (for line numbers)

---

## Configuration (`lua/nimbleapi/config.lua`)

```lua
M.defaults = {
  provider    = nil,         -- auto-detect; override: "fastapi", "spring"
  explorer    = { position = "left", width = 40, icons = true },
  picker      = { provider = nil },   -- nil = auto-detect (telescope/snacks/builtin)
  keymaps     = {
    toggle   = "<leader>Nt",
    pick     = "<leader>Np",
    refresh  = "<leader>Nr",
    codelens = "<leader>Nc",
  },
  codelens    = { enabled = true, test_patterns = { "test_*.py", "*_test.py", "tests/**/*.py" } },
  watch       = { enabled = true, debounce_ms = 200 },
}
```

Merged with `vim.tbl_deep_extend("force", defaults, user_opts)`.

---

## Provider System

### Provider Interface

```lua
---@class RouteProvider
---@field name string                -- "fastapi", "spring"
---@field language string            -- Tree-sitter language ("python", "java")
---@field file_extensions string[]   -- { "py" }, { "java" }
---@field test_patterns string[]     -- Test file globs
---@field path_param_pattern string  -- Lua regex for path params
---@field check_prerequisites fun(): { ok: boolean, message: string|nil }
---@field detect fun(root: string): boolean
---@field find_app fun(root: string): table|nil
---@field get_all_routes fun(root: string): table[]
---@field extract_routes fun(filepath: string): table[]
---@field extract_includes fun(filepath: string): table[]
---@field extract_test_calls_buf fun(bufnr: integer): table[]
---@field find_project_root fun(): string
```

Providers live in `lua/nimbleapi/providers/<name>.lua`. The registry (`providers/init.lua`) auto-detects from project marker files.

### Detection Flow

1. `check_prerequisites()` verifies environment (e.g., TS parser installed)
2. `detect(root)` checks project markers (dependency files, source patterns)
3. On failure, diagnostics are collected and surfaced via `:NimbleAPI info`
4. Provider cache is keyed on `cwd` — switching projects triggers re-detection

### Path Parameter Normalization

All frameworks normalize path params to `{param}` at extraction time:

| Style | Frameworks |
|-------|-----------|
| `{param}` | FastAPI, Spring, Axum (planned), Chi |
| `:param` | Express, Gin, Rails, Sinatra |
| `<type:name>` | Flask, Django |
| `[param]` | Next.js |

---

## Build & Test

No build step. This is a pure Lua Neovim plugin.

**Manual testing**: Open a project in Neovim, run `:NimbleAPI toggle` to verify the explorer, `:NimbleAPI pick` for the picker, `:NimbleAPI info` to check provider status, open a test file for codelens.

**No automated test suite exists yet.** When adding tests, use [plenary.nvim](https://github.com/nvim-lua/plenary.nvim)'s test harness.

---

## Coding Conventions

- Lua 5.1 (LuaJIT) compatible — no `table.pack`, avoid 5.2+ syntax
- Use `require("nimbleapi.module")` not `require("nimbleapi/module")`
- Error reporting via `vim.notify(msg, vim.log.levels.ERROR)` — never `error()` in callbacks
- All public module functions documented with LuaLS annotations (`---@param`, `---@return`)
- Guard against `nil` from `package.loaded` before calling into dependent modules (see `plugin/nimbleapi.lua` pattern)
- Prefer `vim.tbl_deep_extend` for config merging
- Tree-sitter node text: use `get_text(node, source)` helper — handles both string and buffer sources

---

## Key Files for New Framework Support

When adding a new framework, these are the files to touch:

1. `queries/<language>/<framework>-routes.scm` — route extraction query
2. `queries/<language>/<framework>-apps.scm` — app/router discovery query
3. `queries/<language>/<framework>-includes.scm` — router composition query (if applicable)
4. `lua/nimbleapi/providers/<framework>.lua` — provider implementation
5. `lua/nimbleapi/providers/init.lua` — register provider + add detection logic
6. `lua/nimbleapi/init.lua` — add provider to `providers_to_load` list
7. `plugin/nimbleapi.lua` — extend autocmd file patterns

<!-- GSD:project-start source:PROJECT.md -->
## Project

**nimbleapi.nvim — Go Framework Support**

nimbleapi.nvim is a Neovim plugin for exploring and navigating API route definitions. It already supports FastAPI (Python) and Spring/Spring Boot (Java). This milestone adds Go support across four frameworks: Gin, Echo, Chi, and net/http stdlib — giving Go developers the same route explorer, fuzzy picker, codelens, and auto-refresh experience.

**Core Value:** A Go developer can open any Gin/Echo/Chi/net/http project and instantly see, search, and jump to every route — with full group/prefix nesting resolved.

### Constraints

- **Language**: Lua 5.1 (LuaJIT) — no Lua 5.2+ syntax
- **Tree-sitter**: Go parser must be available via nvim-treesitter; query files follow `queries/go/<framework>-routes.scm` naming
- **Provider interface**: Must implement full `RouteProvider` interface without breaking existing FastAPI/Spring detection
- **Path params**: Normalize all Go styles (`:param`, `{param}`) to `{param}` at extraction time
- **No build step**: Pure Lua plugin — no compilation or build tooling
<!-- GSD:project-end -->

<!-- GSD:stack-start source:STACK.md -->
## Technology Stack

Technology stack not yet documented. Will populate after codebase mapping or first phase.
<!-- GSD:stack-end -->

<!-- GSD:conventions-start source:CONVENTIONS.md -->
## Conventions

Conventions not yet established. Will populate as patterns emerge during development.
<!-- GSD:conventions-end -->

<!-- GSD:architecture-start source:ARCHITECTURE.md -->
## Architecture

Architecture not yet mapped. Follow existing patterns found in the codebase.
<!-- GSD:architecture-end -->

<!-- GSD:workflow-start source:GSD defaults -->
## GSD Workflow Enforcement

Before using Edit, Write, or other file-changing tools, start work through a GSD command so planning artifacts and execution context stay in sync.

Use these entry points:
- `/gsd:quick` for small fixes, doc updates, and ad-hoc tasks
- `/gsd:debug` for investigation and bug fixing
- `/gsd:execute-phase` for planned phase work

Do not make direct repo edits outside a GSD workflow unless the user explicitly asks to bypass it.
<!-- GSD:workflow-end -->

<!-- GSD:profile-start -->
## Developer Profile

> Profile not yet configured. Run `/gsd:profile-user` to generate your developer profile.
> This section is managed by `generate-claude-profile` -- do not edit manually.
<!-- GSD:profile-end -->
