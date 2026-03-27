---
phase: 05-stdlib-provider
plan: 01
type: summary
status: complete
completed: 2026-03-26
---

# Phase 05-01 Summary: stdlib Route Extraction

## What Was Done

Implemented the core route extraction infrastructure for the Go net/http stdlib provider across two files.

### Task 1: queries/go/stdlib-routes.scm

Created the Tree-sitter query with two patterns covering all Go stdlib receiver forms:

- **Pattern 1** — identifier receiver: captures `mux.HandleFunc(...)`, `http.HandleFunc(...)`, `router.Handle(...)` (any single identifier as receiver)
- **Pattern 2** — selector_expression receiver: captures `s.mux.HandleFunc(...)`, `srv.router.Handle(...)` (struct field chains)

Both patterns use `(#match? @http_method "^Handle")` to match both `Handle` and `HandleFunc` with a single predicate, and `(interpreted_string_literal)` (not `string_literal`) for double-quoted path strings.

### Task 2: lua/nimbleapi/providers/stdlib.lua

Replaced four stubs with full implementations:

- **`strip_quotes(text)`** — strips surrounding quotes from Tree-sitter string literal tokens
- **`KNOWN_METHODS`** — lookup set for HTTP verb validation in 1.22+ path splitting
- **`split_method_path(raw_path)`** — core dual-era logic:
  - Pre-1.22: `"/path"` → `("ANY", "/path")`
  - Go 1.22+: `"GET /path"` → `("GET", "/path")` (validated against KNOWN_METHODS)
- **`extract_routes(filepath)`** — single-pass extraction using stdlib-routes.scm; handles func_literal guard for anonymous handlers; sorts by line number
- **`get_all_routes(root)`** — scans all `**/*.go` files (excluding vendor/testdata/node_modules/.git) with pre-filter on `HandleFunc(` and `.Handle(`
- **`get_route_tree(root)`** — thin wrapper returning `{ file = "", var_name = "StdlibApp", routes = routes, routers = {} }`

## Requirements Addressed

| ID | Description | Status |
|----|-------------|--------|
| STD-02 | Pre-1.22 `mux.HandleFunc("/path", handler)` → ANY | Done |
| STD-03 | Go 1.22+ `mux.HandleFunc("GET /path", handler)` → method=GET, path=/path | Done |
| STD-04 | `mux.Handle("/path", handler)` extraction | Done |
| STD-05 | Receiver-agnostic: mux/http/s.mux all captured | Done |
| STD-06 | `{$}` end-anchor stripping | Inherited from normalize_path (Phase 1 stub) |

## Key Design Decisions

- Method is extracted Lua-side from the path string, not from `@http_method` (which is always "Handle" or "HandleFunc") — this is the right layer since Tree-sitter can't do substring operations
- `func_name_text ~= nil` guard (not just truthiness) allows empty string for anonymous handlers
- `type(nodes) == "table" and nodes[1] or nodes` pattern handles both old and new iter_matches API forms
- `@_receiver` in Pattern 1 is prefixed with `_` (internal — not consumed in Lua extraction loop)

## Files Modified

- `queries/go/stdlib-routes.scm` (created)
- `lua/nimbleapi/providers/stdlib.lua` (stubs replaced with full implementation)

## Commits

- `feat(05-01): add stdlib-routes.scm with identifier and selector_expression receiver patterns`
- `feat(05-01): implement extract_routes and get_all_routes in stdlib provider`
