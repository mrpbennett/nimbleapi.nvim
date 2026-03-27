# Phase 1: Go Foundation - Context

**Gathered:** 2026-03-26
**Status:** Ready for planning

<domain>
## Phase Boundary

Shared Go infrastructure only — no route extraction yet. This phase delivers:
1. Go Tree-sitter grammar prerequisite check surfacing a clear error via `:NimbleAPI info`
2. Four stub provider files registered (gin, echo, chi, stdlib) — enough to be detected and report status
3. File watcher extended to `*.go` files
4. Path parameter normalization logic (`:param` → `{param}`, `*wildcard` → `{wildcard}`, `{id:[0-9]+}` → `{id}`) inline in each provider

This is infrastructure plumbing. No Tree-sitter queries, no route parsing, no codelens — those come in Phases 2–5.

</domain>

<decisions>
## Implementation Decisions

### Provider Architecture
- **D-01:** Create 4 independent provider files: `lua/nimbleapi/providers/gin.lua`, `echo.lua`, `chi.lua`, `stdlib.lua` — each self-contained, consistent with the existing `fastapi.lua` / `springboot.lua` pattern. No shared go_utils.lua module.
- **D-02:** Inline duplication is acceptable for the 2-3 shared lines (grammar check, path normalization). Simple, no extra require() calls, zero risk of coupling between providers.

### Claude's Discretion
- Where exactly `go.mod` is added to ROOT_MARKERS (global in providers/init.lua vs. only inside Go provider detect()) — use judgment based on existing patterns
- Exact error message wording for missing Go TS grammar (follow the FastAPI pattern: "Go tree-sitter parser not installed. Run :TSInstall go")
- Whether Phase 1 provider stubs implement `get_all_routes()` returning `{}` or raise a clear "not implemented" message
- Ordering of the 4 Go providers in `providers_to_load` (alphabetical is fine)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Existing provider pattern to replicate
- `lua/nimbleapi/providers/fastapi.lua` — The exact pattern to follow for check_prerequisites(), detect(), and provider interface
- `lua/nimbleapi/providers/init.lua` — ROOT_MARKERS list, M.register(), provider interface definition (RouteProvider class)

### Files to modify
- `lua/nimbleapi/init.lua:18` — `providers_to_load` list, add gin/echo/chi/stdlib
- `plugin/nimbleapi.lua:52` — BufWritePost autocmd `pattern = { "*.py", "*.java" }`, add `"*.go"`

### Requirements
- `.planning/REQUIREMENTS.md` §INFRA-01 through INFRA-04

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `fastapi.lua:check_prerequisites()`: `pcall(vim.treesitter.language.inspect, "python")` — copy this pattern verbatim, substitute "go"
- `fastapi.lua:detect()`: reads dependency files with `utils.file_contains()` — same approach for go.mod
- `parser.lua:get_query(name, language)`: already accepts any language string, just pass "go"

### Established Patterns
- Providers are self-contained Lua modules that call `require("nimbleapi.providers").register(M)` at the bottom
- `ROOT_MARKERS` is a module-level table in providers/init.lua — `go.mod` should be added there
- The autocmd in plugin/nimbleapi.lua uses a string array for `pattern` — simple to extend
- `providers_to_load` in init.lua is a plain string array — add 4 new entries

### Integration Points
- Each new provider file must call `require("nimbleapi.providers").register(M)` at the end (check fastapi.lua for the exact call site)
- The `providers_to_load` list in `lua/nimbleapi/init.lua` drives which providers get loaded at setup

</code_context>

<specifics>
## Specific Ideas

- Path normalization rules (inline in each provider):
  - `:param` → `{param}` (Gin/Echo style)
  - `*wildcard` → `{wildcard}` (Gin/Echo wildcard)
  - `{id:[0-9]+}` → `{id}` (Chi regex variant — strip `:pattern` suffix inside braces)
  - `{$}` → strip entirely (stdlib end-anchor)

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 01-go-foundation*
*Context gathered: 2026-03-26*
