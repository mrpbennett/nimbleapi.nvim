# Phase 3: Echo Provider - Context

**Gathered:** 2026-03-26
**Status:** Ready for planning

<domain>
## Phase Boundary

Full Echo route extraction — implement the `echo.lua` provider stub from Phase 1 to actually parse and return routes. This phase delivers:

1. Tree-sitter queries in `queries/go/` for Echo route patterns (method shortcuts, `Add`, `Any`), Group variable assignments, and test client patterns
2. Lua extraction logic in `lua/nimbleapi/providers/echo.lua` — `extract_routes()`, `get_all_routes()`, Group prefix resolution
3. Codelens annotations for `httptest.NewRequest` calls in `*_test.go` files

This phase is Echo-only. Gin was Phase 2; Chi and stdlib are later phases.

**Key difference from Gin:** Echo's test client uses `httptest.NewRequest` (not `http.NewRequest`). The query package/function predicates must target `httptest`/`NewRequest` respectively.

**Similarity to Gin:** The group nesting model (`g := e.Group("/prefix")`) is structurally identical to Gin's RouterGroup model — the same two-pass algorithm and `resolve_prefix()` helper apply directly.

</domain>

<decisions>
## Implementation Decisions

### D-01: echo.Any representation
`e.Any("/path", handler)` records as a **single entry with method `ANY`** — one row in the explorer/picker. Do not expand to the 9 individual HTTP methods. Consistent with how Gin handled Any (GIN-04 → ECHO-04).

### D-02: Group variable tracking scope
Track Group variable assignments (`g := e.Group("/prefix")`) within the **same file only** (file-scope, not function-scope). Cross-function and cross-file tracking deferred. Same decision as Gin Phase 2 (D-02).

### D-03: Route discovery breadth
Scan **all `*.go` files** in the project directory tree (excluding `vendor/`, `testdata/`, hidden dirs). No entry-point discovery needed. Pre-filter to files that reference `echo.` or common route method calls (`.GET(`, `.POST(`, `.Group(`, `.Add(`) before expensive TS parsing.

### D-04: Codelens match display
When a test call matches multiple route handlers, show the **first match only** in the virtual text annotation. Consistent with Gin (D-04).

### D-05: e.Add handling
`e.Add("METHOD", "/path", handler)` — the HTTP method is the first string argument (not the field name). Handle in Lua analogously to how Gin handles `router.Handle("METHOD", "/path", handler)`: check if field name is "Add", then read method from first string argument (captured as `@_add_method`).

### D-06: e.Match not supported
`e.Match([]string{"GET", "HEAD"}, "/path", handler)` uses a composite literal for the method list, not a string literal. This cannot be cleanly extracted with a single TS query without a complex intermediate representation. Deferred — not included in this phase.

### Claude's Discretion
- Exact Tree-sitter query structure for Go — follow gin-routes.scm patterns exactly, adapting method list
- Whether `get_all_routes()` calls `extract_routes()` per-file or a multi-file query (use per-file — matches gin.lua)
- Reuse `parser.lua` infrastructure — do not reinvent
- Exact capture names in .scm files — follow CLAUDE.md convention (`@router_obj`, `@http_method`, `@route_path`, `@func_name`, `@route_def`)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before implementing.**

### Existing provider pattern (replicate this)
- `lua/nimbleapi/providers/echo.lua` — Stub from Phase 1 — this is the file to fill in
- `lua/nimbleapi/providers/gin.lua` — Complete Gin implementation — primary reference for all patterns
- `lua/nimbleapi/providers/springboot.lua` — All-files scanning pattern fallback reference

### Tree-sitter query files (replicate these)
- `queries/go/gin-routes.scm` — Route query structure and capture naming (echo-routes.scm mirrors this)
- `queries/go/gin-groups.scm` — Group query structure (echo-groups.scm mirrors this exactly)
- `queries/go/gin-testclient.scm` — Test client query (echo-testclient.scm changes pkg to `httptest`, func to `NewRequest`)

### Parser infrastructure
- `lua/nimbleapi/parser.lua` — `parse_file()`, `get_query_public()`, `get_text()`, `parse_buffer()` — use these
- `lua/nimbleapi/codelens.lua` — How codelens calls `extract_test_calls_buf()` — understand the interface contract

### Research
- `.planning/research/echo.md` — Echo API signatures, group patterns, test client patterns, TS capture notes

### Requirements
- `.planning/REQUIREMENTS.md` §ECHO-01 through ECHO-07 — every requirement must be implemented

### Conventions
- `CLAUDE.md` §Tree-sitter Queries — capture naming: `@router_obj`, `@http_method`, `@route_path`, `@func_name`, `@route_def`
- `CLAUDE.md` §Coding Conventions — Lua 5.1 compatible, LuaLS annotations
- Gin Phase 2 Summary (02-02-SUMMARY.md) — critical lessons: func_literal guard, newline sanitization

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets from gin.lua
- `normalize_path(path)` — already duplicated in echo.lua stub; handles `:param`, `*wildcard`, `{$}` stripping
- `strip_quotes(text)` — copy from gin.lua; strips `"` or `'` from interpreted_string_literal text
- `resolve_prefix(var_name, groups, visited)` — copy from gin.lua; recursive with cycle guard; works identically for Echo
- `extract_routes` two-pass algorithm — copy and adapt: same structure, different method names, different methods table
- `get_all_routes` with pre-filter — copy and adapt: change pre-filter strings to `echo.`/`.GET(`/etc.
- `extract_test_calls_buf` — copy from gin.lua; change query name from `"gin-testclient"` to `"echo-testclient"`

### Echo-specific differences from Gin
1. ECHO_METHODS table: GET, POST, PUT, DELETE, PATCH, HEAD, OPTIONS, CONNECT, TRACE (9 methods vs Gin's 7); Any -> "ANY"
2. `e.Add("METHOD", "/path", handler)` — field name is "Add", method is first string arg (analogous to Gin's Handle)
3. Test client uses `httptest.NewRequest` — change `@_pkg` eq? from "http" to "httptest", `@_func` eq? stays "NewRequest"
4. No `Handle` method in Echo — remove `@_handle_method` capture; replace with `@_add_method` for `e.Add`

### Patterns to Apply Proactively (from Gin lessons)
- func_literal guard: `if node:type() == "func_literal" then func_name_text = "" end` — apply in extract_routes
- Newline sanitization: already in explorer.lua from Gin fix — no action needed here
- `type(nodes) == "table" and nodes[1] or nodes` — CRITICAL Neovim 0.10+ iter_matches compat pattern

</code_context>

<specifics>
## Specific Ideas

- Echo method shortcuts: GET, POST, PUT, DELETE, PATCH, HEAD, OPTIONS, CONNECT, TRACE (ECHO-02)
- `e.Add("METHOD", "/path", handler)` — method from first string arg (ECHO-03)
- `e.Any("/path", handler)` → `{ method = "ANY", ... }` (ECHO-04, D-01)
- Group pattern: `g := e.Group("/prefix")` short variable declaration (ECHO-05) — same TS node shape as Gin
- Nested groups: `v1 := api.Group("/v1")` → fully concatenated `/api/v1` (ECHO-06) — same resolve_prefix logic
- Test codelens: `httptest.NewRequest(http.MethodGet, "/path", nil)` in `*_test.go` files (ECHO-07)
- Note: `http.MethodGet` is a constant string — the TS query captures it as an `identifier`, not a string literal. The codelens query should capture the first argument as `(_)` (any node) to handle both string literals and identifiers, then strip quotes if present.

</specifics>

<deferred>
## Deferred Ideas

- `e.Match([]string{"GET", "HEAD"}, "/path", handler)` — composite literal method list; too complex for MVP; deferred (D-06)
- `e.AddRoute(route Route)` (v5 only) — struct-based registration; too rare to prioritize; deferred
- Cross-function parameter tracking (e.g., `RegisterUserRoutes(g *echo.Group)`) — full prefix resolution requires inter-function dataflow analysis; deferred to potential v2
- `e.RouteNotFound` special handler — not an API route; excluded

</deferred>

---

*Phase: 03-echo-provider*
*Context gathered: 2026-03-26*
