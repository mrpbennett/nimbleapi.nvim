# Phase 2: Gin Provider - Context

**Gathered:** 2026-03-26
**Status:** Ready for planning

<domain>
## Phase Boundary

Full Gin route extraction — implement the `gin.lua` provider stub from Phase 1 to actually parse and return routes. This phase delivers:

1. Tree-sitter queries in `queries/go/` for Gin route patterns (method shortcuts, `Handle`, `Any`), RouterGroup variable assignments, and test client patterns
2. Lua extraction logic in `lua/nimbleapi/providers/gin.lua` — `extract_routes()`, `get_all_routes()`, RouterGroup prefix resolution
3. Codelens annotations for `http.NewRequest` calls in `*_test.go` files

This phase is Gin-only. Echo, Chi, and stdlib are separate phases.

</domain>

<decisions>
## Implementation Decisions

### router.Any representation
- **D-01:** `router.Any("/path", handler)` records as a **single entry with method `ANY`** — one row in the explorer/picker. Do not expand to individual methods. Consistent with GIN-04 in REQUIREMENTS.md.

### RouterGroup variable tracking scope
- **D-02 (Claude's Discretion):** Track RouterGroup variable assignments (`v1 := router.Group("/prefix")`) within the **same function body only**. Cross-function tracking is deferred. This aligns with the "same-file and same-function group resolution is sufficient" note in PROJECT.md and handles the vast majority of real Gin projects.

### Route discovery breadth
- **D-03 (Claude's Discretion):** Scan **all `*.go` files** in the project directory tree (excluding `vendor/`, `testdata/`, hidden dirs). No entry-point discovery needed. Simple, consistent with the Spring provider's all-files approach. Cross-file group variable tracking is explicitly out of scope.

### Codelens match display
- **D-04 (Claude's Discretion):** When a test call matches multiple route handlers, show the **first match only** in the virtual text annotation. Keeps codelens output clean and non-verbose.

### Claude's Discretion
- Exact Tree-sitter query structure for Go — research the Go AST node types for call expressions, short variable declarations, and selector expressions
- Whether `get_all_routes()` calls `extract_routes()` per-file or runs a single multi-file query
- Whether to use `parser.lua`'s `parse_file()` infrastructure or write file parsing inline in gin.lua (prefer reusing parser.lua)
- Exact capture names used in .scm files — must follow the naming convention in CLAUDE.md (`@router_obj`, `@http_method`, `@route_path`, `@func_name`, `@route_def`)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Existing provider pattern (replicate this)
- `lua/nimbleapi/providers/gin.lua` — Stub from Phase 1 — this is the file to fill in
- `lua/nimbleapi/providers/fastapi.lua` — Complete provider implementation to reference for interface shape
- `lua/nimbleapi/providers/springboot.lua` — All-files scanning pattern (no entry-point walk)

### Tree-sitter query patterns
- `queries/python/fastapi-routes.scm` — Query file structure and capture naming conventions
- `queries/python/fastapi-testclient.scm` — Test client query pattern
- `queries/java/springboot-routes.scm` — More complex multi-pattern query to reference

### Parser infrastructure
- `lua/nimbleapi/parser.lua` — `parse_file()`, `get_query()`, `get_text()` helpers — use these, don't reinvent
- `lua/nimbleapi/codelens.lua` — How codelens calls `extract_test_calls_buf()` — understand the interface contract

### Requirements
- `.planning/REQUIREMENTS.md` §GIN-01 through GIN-07 — every requirement must be implemented

### Conventions
- `CLAUDE.md` §Tree-sitter Queries — capture naming: `@router_obj`, `@http_method`, `@route_path`, `@func_name`, `@route_def`
- `CLAUDE.md` §Coding Conventions — Lua 5.1 compatible, no table.pack, LuaLS annotations

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `parser.lua:parse_file(filepath, language)`: accepts any language — pass `"go"` for gin files
- `parser.lua:get_query(name, language)`: loads `queries/go/<name>.scm` automatically
- `parser.lua:get_text(node, source)`: use for extracting strings from captures
- `gin.lua:normalize_path(path)`: already implemented in the Phase 1 stub — just call it

### Established Patterns
- `springboot.lua` scans all Java files with `utils.glob_files(root, "**/*.java", exclusions)` — same pattern for `*.go`
- Providers return flat `{ method, path, func, file, line }` tables — match this exactly
- `extract_test_calls_buf()` receives a `bufnr` and returns `{ method, path, line }` tables for codelens

### Integration Points
- `codelens.lua` calls `provider.extract_test_calls_buf(bufnr)` — the return format must match what codelens expects
- `cache.lua` calls `provider.get_all_routes(root)` — must return a flat list of route records
- Query files go in `queries/go/` and are auto-discovered by `parser.lua:get_query()`

</code_context>

<specifics>
## Specific Ideas

- Gin method shortcuts to capture: GET, POST, PUT, DELETE, PATCH, OPTIONS, HEAD (GIN-02)
- `router.Handle("METHOD", "/path", handler)` — method from first string arg (GIN-03)
- `router.Any("/path", handler)` → `{ method = "ANY", ... }` (GIN-04, D-01)
- RouterGroup pattern: `v1 := router.Group("/v1")` short variable declaration (GIN-05)
- Nested groups: `v2 := v1.Group("/admin")` → fully concatenated `/v1/admin` (GIN-06)
- Test codelens: `http.NewRequest("GET", "/path", nil)` in `*_test.go` files (GIN-07)

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 02-gin-provider*
*Context gathered: 2026-03-26*
