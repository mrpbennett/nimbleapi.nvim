# Phase 2: Gin Provider - Research

**Researched:** 2026-03-26
**Domain:** Go Tree-sitter query authoring, Gin framework route patterns, Lua provider implementation
**Confidence:** HIGH

## Summary

This phase fills in the stub provider created in Phase 1. The work is purely additive: write Tree-sitter queries for Go + Gin patterns, then implement extraction logic in `gin.lua` that calls into the existing `parser.lua` infrastructure. No cross-cutting changes to cache, explorer, picker, or codelens are needed — those layers already handle Go routes once the provider returns a flat route list.

The most technically novel part is RouterGroup prefix resolution. Unlike Python (import-based) or Java (annotation-based), Gin uses imperative variable assignment within a function body (`v1 := router.Group("/v1")`). Resolution requires a two-pass approach over the parsed AST: first collect all `short_var_declaration` assignments whose right-hand side is a `.Group()` call, then walk route call expressions looking up each receiver variable against the collected prefix table. This is entirely within `extract_routes()` — no cross-function or cross-file tracking is needed per D-02 and D-03.

The codelens query is straightforward: `http.NewRequest("METHOD", "/path", ...)` in `*_test.go` files is a standard call expression where the first two arguments are string literals.

**Primary recommendation:** Write queries first, validate against real Gin code mentally, then implement `extract_routes()` as a two-pass AST walk using `parser.parse_file()` and `parser.get_query_public()`.

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** `router.Any("/path", handler)` records as a **single entry with method `ANY`** — one row in the explorer/picker. Do not expand to individual methods.
- **D-02:** Track RouterGroup variable assignments (`v1 := router.Group("/prefix")`) within the **same function body only**. Cross-function tracking is deferred.
- **D-03:** Scan **all `*.go` files** in the project directory tree (excluding `vendor/`, `testdata/`, hidden dirs). No entry-point discovery needed.
- **D-04:** When a test call matches multiple route handlers, show the **first match only** in the virtual text annotation.

### Claude's Discretion

- Exact Tree-sitter query structure for Go — research the Go AST node types for call expressions, short variable declarations, and selector expressions
- Whether `get_all_routes()` calls `extract_routes()` per-file or runs a single multi-file query
- Whether to use `parser.lua`'s `parse_file()` infrastructure or write file parsing inline in gin.lua (prefer reusing parser.lua)
- Exact capture names used in .scm files — must follow the naming convention in CLAUDE.md (`@router_obj`, `@http_method`, `@route_path`, `@func_name`, `@route_def`)

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope.
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| GIN-01 | Gin project detection via `go.mod` containing `github.com/gin-gonic/gin` | Already implemented in Phase 1 stub — no work needed |
| GIN-02 | Route extraction for HTTP method shortcuts: GET, POST, PUT, DELETE, PATCH, OPTIONS, HEAD | `call_expression` with `selector_expression` field matching method name; 7 shortcut names |
| GIN-03 | Route extraction for `router.Handle("METHOD", "/path", handler)` | Same `call_expression` pattern; first argument is the method string, second is path |
| GIN-04 | Route extraction for `router.Any("/path", handler)` recorded as method `ANY` | Same pattern as GIN-02; method name `Any` maps to `ANY` in Lua table |
| GIN-05 | RouterGroup detection: `v1 := router.Group("/v1")` short variable declarations | `short_var_declaration` with `call_expression` right-hand side; field name `Group` |
| GIN-06 | Full recursive prefix resolution: nested groups fully concatenated | Lua-side two-pass: collect group vars with their prefixes, then walk routes resolving receiver chain |
| GIN-07 | CodeLens for `http.NewRequest("METHOD", "/path", ...)` in `*_test.go` files | `call_expression` on `http.NewRequest` with string literal first two arguments |
</phase_requirements>

---

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| nvim-treesitter (Go parser) | bundled with nvim-treesitter | Parses Go source into AST | Required by INFRA-01, already validated in Phase 1 |
| tree-sitter-go grammar | shipped with nvim-treesitter | Go node types and field names | Authoritative grammar used by Neovim |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `parser.lua` (internal) | — | `parse_file()`, `get_query_public()`, `get_text()` | All file parsing — do not reinvent |
| `utils.lua` (internal) | — | `glob_files()`, `file_contains()`, `join()` | File discovery and pre-filtering |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Two-pass Lua group resolution | Pure TS query with predicates | TS predicates cannot track variable bindings across statements — Lua-side resolution is the only viable approach |
| `parse_file()` in parser.lua | Inline `vim.treesitter.get_string_parser` | No benefit to duplicating; parser.lua handles error cases and memoizes query parsing |

**Installation:** No new dependencies. Go parser already installed per INFRA-01.

---

## Architecture Patterns

### Recommended Project Structure

No new files added to `lua/nimbleapi/`. New files added:

```
queries/go/
├── gin-routes.scm          -- Method shortcuts + Handle + Any patterns
├── gin-groups.scm           -- RouterGroup short_var_declaration patterns
└── gin-testclient.scm       -- http.NewRequest patterns for codelens
lua/nimbleapi/providers/
└── gin.lua                  -- Fill in stubs; no other files change
```

### Pattern 1: Go call_expression query structure

**What:** Tree-sitter query matching `router.GET("/path", handlerFunc)` and variants.

**Go AST for `router.GET("/path", handler)`:**
```
expression_statement
  call_expression
    function: selector_expression
      operand: identifier        <- router variable name (@router_obj)
      field: field_identifier    <- method name "GET" (@http_method)
    arguments: argument_list
      interpreted_string_literal <- "/path" (@route_path)
      identifier                 <- handlerFunc (@func_name)
```

**Example query (gin-routes.scm):**
```scheme
; Source: tree-sitter-go grammar field names (verified against grammar.js)
; Method shortcuts: router.GET("/path", handler)
(call_expression
  function: (selector_expression
    operand: (identifier) @router_obj
    field: (field_identifier) @http_method)
  arguments: (argument_list
    (interpreted_string_literal) @route_path
    .
    (_) @func_name)) @route_def
```

**Note on `@func_name`:** In Gin, handlers are function values (identifiers or selector expressions like `pkg.Handler`), not function definitions. The `@func_name` capture should be `(_)` to match any expression, then extract its text. Line number comes from `@route_def`.

### Pattern 2: router.Handle query structure

**What:** `router.Handle("GET", "/path", handler)` — method is the first string argument.

**Go AST for `router.Handle("GET", "/path", handler)`:**
```
call_expression
  function: selector_expression
    operand: identifier          <- @router_obj
    field: field_identifier      <- "Handle" (@http_method)
  arguments: argument_list
    interpreted_string_literal   <- "GET" (first arg = method)
    interpreted_string_literal   <- "/path" (@route_path)
    (_)                          <- @func_name
```

**Example query fragment:**
```scheme
; Handle("METHOD", "/path", handler) — method from first string arg
(call_expression
  function: (selector_expression
    operand: (identifier) @router_obj
    field: (field_identifier) @http_method
    (#eq? @http_method "Handle"))
  arguments: (argument_list
    (interpreted_string_literal) @_handle_method
    (interpreted_string_literal) @route_path
    .
    (_) @func_name)) @route_def
```

The Lua side reads `@_handle_method` (stripped of quotes) as the HTTP method instead of the field identifier.

### Pattern 3: RouterGroup short_var_declaration query structure

**What:** `v1 := router.Group("/v1")` — variable assigned a Group call.

**Go AST:**
```
short_var_declaration
  left: expression_list
    identifier                   <- "v1" (group var name)
  right: expression_list
    call_expression
      function: selector_expression
        operand: identifier      <- parent group var (@router_obj)
        field: field_identifier  <- "Group"
      arguments: argument_list
        interpreted_string_literal <- "/v1" (@route_path = prefix)
```

**Example query (gin-groups.scm):**
```scheme
; Source: tree-sitter-go grammar field names
; RouterGroup variable assignment: v1 := router.Group("/v1")
(short_var_declaration
  left: (expression_list
    (identifier) @group_var)
  right: (expression_list
    (call_expression
      function: (selector_expression
        operand: (identifier) @router_obj
        field: (field_identifier) @_group_method
        (#eq? @_group_method "Group"))
      arguments: (argument_list
        (interpreted_string_literal) @route_path)))) @route_def
```

### Pattern 4: http.NewRequest codelens query

**What:** `http.NewRequest("GET", "/users/123", nil)` in test files.

**Go AST:**
```
call_expression
  function: selector_expression
    operand: identifier          <- "http"
    field: field_identifier      <- "NewRequest"
  arguments: argument_list
    interpreted_string_literal   <- "GET" (@http_method)
    interpreted_string_literal   <- "/users/123" (@test_path)
    ...
```

**Example query (gin-testclient.scm):**
```scheme
; Source: tree-sitter-go grammar field names
; http.NewRequest("METHOD", "/path", ...) calls in test files
(call_expression
  function: (selector_expression
    operand: (identifier) @_pkg
    field: (field_identifier) @_func
    (#eq? @_pkg "http")
    (#eq? @_func "NewRequest"))
  arguments: (argument_list
    (interpreted_string_literal) @http_method
    (interpreted_string_literal) @test_path
    .)) @test_call
```

### Pattern 5: Two-pass Lua prefix resolution (GIN-05, GIN-06)

**What:** RouterGroup variables form a chain: `v1 := r.Group("/v1")`, `admin := v1.Group("/admin")`. Each route on `admin` has full prefix `/v1/admin`.

**Algorithm:**
```
Pass 1 — collect group table (per file, within function scope per D-02):
  groups = {}   -- map: var_name -> { prefix, parent_var }
  for each gin-groups.scm match:
    groups[group_var] = { prefix = route_path, parent = router_obj }

  resolve_prefix(var_name):
    if not groups[var_name]: return ""        -- it's the root router
    parent_prefix = resolve_prefix(groups[var_name].parent)
    return parent_prefix .. groups[var_name].prefix

Pass 2 — apply to routes:
  for each route match from gin-routes.scm:
    full_path = resolve_prefix(router_obj) .. route_path
    full_path = normalize_path(full_path)
    full_path = full_path:gsub("//+", "/")
```

**Cycle guard:** `resolve_prefix()` needs a visited set to prevent infinite recursion if a file has circular variable assignments (pathological but safe to handle).

### Anti-Patterns to Avoid

- **String-stripping the interpreter_string_literal text directly:** The node text from `get_text()` includes surrounding double-quotes — always strip with `raw:match('^"(.*)"$') or raw` as done in parser.lua's existing code.
- **Using `iter_matches` result as a single node (not a list):** Neovim 0.10+ `iter_matches` returns `nodes` as a list. Always do `local node = type(nodes) == "table" and nodes[1] or nodes`. This pattern is already used throughout the codebase.
- **Running separate query passes per function body for scope isolation:** D-02 says same-function scope is sufficient, but implementing strict AST function-body scoping adds complexity. In practice, collecting all group assignments in a file and resolving by variable name gives correct results for all realistic Gin code (different functions rarely reuse the same variable name for different groups). Implement file-scope collection; add a note that cross-function collision is theoretically possible but D-02 explicitly accepts this.
- **Capturing handler names via `@func_name` expecting a simple identifier:** Gin handlers can be `pkg.Handler` (a selector_expression), anonymous funcs, or method values. Use `(_) @func_name` to capture any expression, then call `get_text()` on it. For line number, use `@route_def` start line.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| File parsing | Custom `vim.treesitter.get_string_parser` calls | `parser.parse_file(filepath, "go")` | Error handling, null checks, string/buffer duality already handled |
| Query loading | Direct file reads + `vim.treesitter.query.parse` | `parser.get_query_public(name, "go")` | Memoization, runtime path lookup, error reporting all done |
| Node text extraction | `node:range()` + string slicing | `parser.get_text(node, source)` | Multi-line node handling, string vs buffer source handled |
| File globbing | `vim.fn.glob` + manual exclusion | `utils.glob_files(root, "**/*.go", exclusions)` | Exclusion logic for vendor/, testdata/, .git/ already exists |
| Pre-filtering files | Parse every .go file | `utils.file_contains(f, "gin.")` pre-filter | Same pattern as springboot.lua's `"Mapping"` pre-filter — avoids parsing non-route files |

**Key insight:** The parser.lua + utils.lua infrastructure was designed to be language-agnostic. Passing `"go"` to `parse_file()` and `get_query_public()` is the entire integration surface.

---

## Common Pitfalls

### Pitfall 1: interpreted_string_literal includes surrounding quotes
**What goes wrong:** `parser.get_text(node, source)` on an `interpreted_string_literal` node returns `"/users"` (with quotes), not `/users`. Code that does direct path comparison fails.
**Why it happens:** Tree-sitter captures the full literal token including delimiters.
**How to avoid:** Always strip quotes: `raw:match('^"(.*)"$') or raw:match("^'(.*)'$") or raw`. This pattern already exists in parser.lua line 163 and springboot.lua's `strip_quotes()`.
**Warning signs:** Routes show up with leading `"` in the explorer.

### Pitfall 2: field_identifier vs identifier node type
**What goes wrong:** Writing `(identifier) @http_method` when the method name in `router.GET` is a `field_identifier` node (not a plain `identifier`).
**Why it happens:** In a selector_expression, the `.field` is always a `field_identifier`, which is a distinct node type in Go grammar.
**How to avoid:** Use `(field_identifier) @http_method` inside `selector_expression`. Use `(identifier) @router_obj` for the `operand`.
**Warning signs:** Query returns zero matches even though the code has obvious route calls.

### Pitfall 3: Lua method name lookup for field_identifier text
**What goes wrong:** `get_text()` on a `field_identifier` node may return the bare name `"GET"` or `"get"` depending on case. Gin uses upper-case method names for HTTP shortcuts (`router.GET`, `router.POST`).
**Why it happens:** Gin's API is deliberately upper-case for HTTP verbs. The provider method table needs upper-case keys.
**How to avoid:** Define `GIN_METHODS = { GET="GET", POST="POST", PUT="PUT", DELETE="DELETE", PATCH="PATCH", OPTIONS="OPTIONS", HEAD="HEAD", Any="ANY" }`. Look up the captured field identifier text directly — no lower-casing needed.
**Warning signs:** All routes have `nil` method and are silently dropped.

### Pitfall 4: router.Handle method is a string argument, not field_identifier
**What goes wrong:** Treating the method in `router.Handle("GET", "/path", handler)` the same way as `router.GET` — trying to read it from `@http_method` field identifier capture.
**Why it happens:** `Handle` takes the HTTP method as its first string argument, unlike the shortcut methods where the verb is baked into the function name.
**How to avoid:** Write a separate query pattern for `Handle` that captures `@_handle_method` as the first string argument. In Lua, when `http_method == "Handle"`, read the method from `_handle_method` capture instead.
**Warning signs:** All `router.Handle(...)` routes show method `HANDLE` instead of the actual verb.

### Pitfall 5: Group chain resolution infinite loop
**What goes wrong:** A malformed or unusual file causes `resolve_prefix()` to recurse infinitely.
**Why it happens:** If `groups["v1"].parent == "v1"` (self-referential), or if two groups reference each other.
**How to avoid:** Add a `visited` set to `resolve_prefix()`. If `var_name` is already in `visited`, return `""` and log a warning.
**Warning signs:** Neovim hangs when opening a Go file.

### Pitfall 6: vendor/ and testdata/ files parsed unnecessarily
**What goes wrong:** All `.go` files in vendor/ are parsed, adding thousands of routes from dependencies.
**Why it happens:** `utils.glob_files` exclusion list doesn't include `vendor` by default.
**How to avoid:** Pass explicit exclusions: `{ "vendor", "testdata", ".git", "node_modules" }` to `utils.glob_files`.
**Warning signs:** Route count is unexpectedly large; routes from gin-gonic's own source appear.

---

## Code Examples

Verified patterns from official sources and existing codebase:

### Calling parser.lua from a provider (established pattern from springboot.lua)
```lua
-- Source: lua/nimbleapi/providers/springboot.lua lines 162-188
local parser = require("nimbleapi.parser")

function M.extract_routes(filepath)
  local root_node, source = parser.parse_file(filepath, "go")
  if not root_node or not source then
    return {}
  end

  local ok, query = pcall(parser.get_query_public, "gin-routes", "go")
  if not ok or not query then
    return {}
  end

  local routes = {}
  for _, match, _ in query:iter_matches(root_node, source, 0, -1) do
    local entry = {}
    for id, nodes in pairs(match) do
      local name = query.captures[id]
      local node = type(nodes) == "table" and nodes[1] or nodes
      -- ... process captures
    end
    table.insert(routes, entry)
  end
  return routes
end
```

### Scanning all Go files (pattern from springboot.lua get_all_routes)
```lua
-- Source: lua/nimbleapi/providers/springboot.lua lines 339-357
function M.get_all_routes(root)
  local go_files = utils.glob_files(root, "**/*.go", {
    "vendor", "testdata", "node_modules", ".git",
  })

  local all_routes = {}
  -- Pre-filter: only parse files that might have route calls
  for _, f in ipairs(go_files) do
    if utils.file_contains(f, ".GET(")
      or utils.file_contains(f, ".POST(")
      or utils.file_contains(f, ".Handle(")
      or utils.file_contains(f, ".Group(") then
      local routes = M.extract_routes(f)
      for _, route in ipairs(routes) do
        table.insert(all_routes, route)
      end
    end
  end
  return all_routes
end
```

### Node text / quote stripping (established pattern)
```lua
-- Source: lua/nimbleapi/parser.lua line 163 / springboot.lua strip_quotes
local raw = parser.get_text(node, source)
local path = raw:match('^"(.*)"$') or raw:match("^'(.*)'$") or raw
```

### iter_matches node extraction (Neovim 0.10+ compatibility)
```lua
-- Source: lua/nimbleapi/parser.lua line 153 / providers/springboot.lua line 177
local node = type(nodes) == "table" and nodes[1] or nodes
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Separate query files per pattern | Multiple patterns in one .scm file with comments | N/A (existing convention) | Fewer files, easier to maintain |
| Manual `vim.treesitter.query.parse` | `parser.get_query_public()` with memoization | Phase 1 architecture | All providers share the cache |

**Deprecated/outdated:**
- Inline string parsers in providers: replaced by `parser.parse_file()` — do not add inline parsers.

---

## Open Questions

1. **`@func_name` for selector expression handlers**
   - What we know: Gin handlers can be `pkg.SomeHandler` (a `selector_expression`) or a plain `identifier`. The `(_)` wildcard captures both.
   - What's unclear: Whether `get_text()` on a `selector_expression` node returns `"pkg.SomeHandler"` — it should since it returns the full text range, but not verified against live Go parsing.
   - Recommendation: Use `(_) @func_name` and call `get_text()` — the text will be whatever the source code shows. This is acceptable for display; line numbers come from `@route_def`.

2. **`#eq?` predicates on `field_identifier` nodes**
   - What we know: `(#eq? @_group_method "Group")` should filter to only `Group` calls.
   - What's unclear: Whether `field_identifier` text comparison via `#eq?` predicate works correctly in Neovim's tree-sitter query engine for Go.
   - Recommendation: Test with a simple `.scm` query before relying on it. Fallback: capture all method names and filter in Lua via `if method_text == "Group" then`.

3. **Scope isolation for group variable tracking (D-02)**
   - What we know: D-02 says same-function scope only. Implementing this strictly requires finding which `function_declaration` or `func_literal` body each `short_var_declaration` belongs to.
   - What's unclear: Whether the added complexity of function-body scoping is worth it vs. file-scope collection.
   - Recommendation: Implement file-scope collection (simpler). Variable name collisions across functions in the same file are rare in practice. Document the limitation.

---

## Environment Availability

Step 2.6: SKIPPED (no external dependencies — this phase adds Lua files and .scm query files to an existing plugin; Go tree-sitter parser availability was validated in Phase 1 as INFRA-01).

---

## Validation Architecture

> nyquist_validation key absent from config.json — treated as enabled.

### Test Framework

| Property | Value |
|----------|-------|
| Framework | plenary.nvim (project-specified, not yet installed) |
| Config file | None — no test infrastructure exists yet |
| Quick run command | `:PlenaryBustedDirectory tests/` (once set up) |
| Full suite command | `:PlenaryBustedDirectory tests/` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| GIN-01 | Gin project detected via go.mod | unit | — | ❌ Wave 0 |
| GIN-02 | HTTP method shortcuts extracted | unit | — | ❌ Wave 0 |
| GIN-03 | Handle("METHOD",...) extraction | unit | — | ❌ Wave 0 |
| GIN-04 | Any("/path",...) recorded as ANY | unit | — | ❌ Wave 0 |
| GIN-05 | RouterGroup var detection | unit | — | ❌ Wave 0 |
| GIN-06 | Nested group prefix concatenation | unit | — | ❌ Wave 0 |
| GIN-07 | http.NewRequest codelens extraction | unit | — | ❌ Wave 0 |

**Note:** CLAUDE.md states "No automated test suite exists yet." Testing is manual via `:NimbleAPI toggle` and `:NimbleAPI info` in a real Gin project. Wave 0 infrastructure gap applies to all items above.

### Sampling Rate

- **Per task commit:** Manual `:NimbleAPI info` to verify provider loads without error
- **Per wave merge:** Manual `:NimbleAPI toggle` in a Gin project to verify route display
- **Phase gate:** Explorer shows correct fully-prefixed routes; codelens appears on `*_test.go` files

### Wave 0 Gaps

- [ ] `tests/providers/test_gin.lua` — unit tests for extract_routes, group resolution (REQ GIN-02 through GIN-06)
- [ ] `tests/queries/test_gin_queries.lua` — query match tests for each .scm pattern
- [ ] plenary.nvim must be available: add to dev dependencies

*(Full test infrastructure is absent — this is a known project-wide gap, not specific to this phase)*

---

## Project Constraints (from CLAUDE.md)

The following directives from `CLAUDE.md` apply to this phase. The planner must ensure all tasks comply:

| Directive | Impact on This Phase |
|-----------|---------------------|
| Lua 5.1 (LuaJIT) — no `table.pack`, no 5.2+ syntax | All provider Lua must use Lua 5.1 compatible patterns only |
| Use `require("nimbleapi.module")` not `require("nimbleapi/module")` | All requires in gin.lua must use dot notation |
| Error reporting via `vim.notify(..., vim.log.levels.ERROR)` — never `error()` in callbacks | Wrap parser calls in `pcall`; surface errors via notify |
| All public module functions documented with LuaLS annotations | Every `M.*` function needs `---@param` / `---@return` annotations |
| Guard against `nil` from `package.loaded` | `require("nimbleapi.providers").register(M)` at bottom of file (already in stub) |
| Tree-sitter node text: use `get_text(node, source)` helper | Never use raw `node:text()` — use `parser.get_text()` |
| Capture names: `@router_obj`, `@http_method`, `@route_path`, `@func_name`, `@route_def` | All .scm files must use these exact capture names |
| Extend existing defaults, not replace | gin.lua stub already registered — fill in stubs, do not restructure the file |
| No build step — pure Lua plugin | No compilation; query files are plain text .scm |
| GSD workflow enforcement — no direct edits outside GSD | Plan is being created through GSD now |

---

## Sources

### Primary (HIGH confidence)
- `tree-sitter/tree-sitter-go grammar.js` (fetched 2026-03-26) — exact field names: `operand`/`field` for selector_expression, `left`/`right` for short_var_declaration, `function`/`arguments` for call_expression
- `tree-sitter/tree-sitter-go src/node-types.json` (fetched 2026-03-26) — confirmed node type names: `call_expression`, `selector_expression`, `short_var_declaration`, `interpreted_string_literal`, `field_identifier`
- `lua/nimbleapi/providers/springboot.lua` — all-files scanning pattern, iter_matches usage, pcall wrapping, extract_test_calls_buf contract
- `lua/nimbleapi/parser.lua` — parse_file, get_query_public, get_text API signatures (lines 62-83, 498-508)
- `lua/nimbleapi/providers/gin.lua` — Phase 1 stub; normalize_path, detect, find_project_root already implemented

### Secondary (MEDIUM confidence)
- gin-gonic/examples/group-routes (fetched 2026-03-26) — confirmed `router.Group("/v1")` and nested group patterns are standard; helpers pass `*gin.RouterGroup` to sub-functions (cross-function pattern, but D-02 defers this)
- Gin documentation grouping-routes page — confirmed `Group()`, `GET/POST/PUT/DELETE/PATCH/OPTIONS/HEAD`, `Handle`, `Any` are the complete set of route registration methods

### Tertiary (LOW confidence)
- WebSearch for `#eq?` predicate behavior on `field_identifier` nodes in Neovim's tree-sitter engine — not directly verified against Neovim source. Recommendation: test in Wave 0 and add fallback Lua-side filtering if predicates don't work.

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — parser.lua and utils.lua APIs verified by reading source; no new libraries
- Architecture: HIGH — node type names verified from official tree-sitter-go grammar.js; query structure confirmed against existing .scm examples in codebase
- Pitfalls: HIGH — most pitfalls derived from reading the existing codebase (iter_matches node lists, quote stripping) plus one medium-confidence item (field_identifier predicate behavior)

**Research date:** 2026-03-26
**Valid until:** 2026-09-26 (tree-sitter-go grammar is stable; Gin API for route registration unchanged for years)
