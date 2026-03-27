---
phase: 02-gin-provider
plan: "01"
subsystem: providers/gin
tags: [gin, go, tree-sitter, route-extraction, group-prefix]
dependency_graph:
  requires: []
  provides: [gin-route-extraction, gin-group-resolution]
  affects: [cache, explorer, picker]
tech_stack:
  added: []
  patterns: [two-pass-ast-walk, group-prefix-chain-resolution, iter_matches-compat]
key_files:
  created:
    - queries/go/gin-routes.scm
    - queries/go/gin-groups.scm
  modified:
    - lua/nimbleapi/providers/gin.lua
decisions:
  - "file-scope group collection (not function-scope) per D-02 recommendation — cross-function variable collision accepted as rare"
  - "pre-filter on gin./GET(/POST(/Handle(/Group( before parsing each .go file — avoids expensive TS parse on non-route files"
  - "Handle() case handled in Lua by checking http_method_text == 'Handle' and reading @_handle_method capture instead"
metrics:
  duration: "2m 11s"
  completed: "2026-03-26"
  tasks_completed: 2
  files_changed: 3
---

# Phase 02 Plan 01: Gin Route Extraction Summary

Two-pass Tree-sitter extraction for Gin routes with recursive RouterGroup prefix resolution using gin-routes.scm, gin-groups.scm query files and fully-implemented gin.lua provider.

## What Was Built

**queries/go/gin-routes.scm** — Two-pattern query file covering:
- Pattern 1: Method shortcuts (`router.GET/POST/PUT/DELETE/PATCH/OPTIONS/HEAD/Any`) — all captured via the same `(selector_expression)` pattern, Lua side filters by GIN_METHODS table
- Pattern 2: `router.Handle("METHOD", "/path", handler)` — `@_handle_method` capture for the first string argument, `#eq? @http_method "Handle"` predicate isolates this pattern

**queries/go/gin-groups.scm** — One-pattern query file:
- RouterGroup variable assignment: `v1 := router.Group("/v1")` via `short_var_declaration` with `#eq? @_group_method "Group"` predicate
- Captures `@group_var` (new variable), `@router_obj` (parent variable), `@route_path` (prefix string)

**lua/nimbleapi/providers/gin.lua** — Full provider implementation:
- `GIN_METHODS` lookup table: GET/POST/PUT/DELETE/PATCH/OPTIONS/HEAD all map to their HTTP string; Any maps to "ANY" (D-01)
- `strip_quotes()` helper: strips surrounding double/single quotes from `interpreted_string_literal` node text
- `resolve_prefix()`: recursive prefix chain resolution with visited-set cycle guard
- `extract_routes()`: two-pass algorithm — Pass 1 collects group variables via gin-groups.scm, Pass 2 extracts routes via gin-routes.scm applying resolved prefixes; returns sorted route list
- `get_all_routes()`: scans all `**/*.go` excluding vendor/testdata/node_modules/.git, pre-filters on `gin./GET(/POST(/Handle(/Group(`, calls extract_routes per matching file
- `get_route_tree()`: thin wrapper returning route tree struct

## Requirements Satisfied

| Req | Status | Notes |
|-----|--------|-------|
| GIN-01 | Preserved | detect() already implemented in Phase 1 stub |
| GIN-02 | Implemented | HTTP method shortcuts via gin-routes.scm Pattern 1 + GIN_METHODS table |
| GIN-03 | Implemented | Handle("METHOD",...) via gin-routes.scm Pattern 2 + Lua Handle case |
| GIN-04 | Implemented | Any("/path",...) -> method "ANY" via GIN_METHODS[Any] = "ANY" |
| GIN-05 | Implemented | RouterGroup variables collected in Pass 1 via gin-groups.scm |
| GIN-06 | Implemented | Full recursive prefix concatenation via resolve_prefix() |

## Deviations from Plan

None — plan executed exactly as written.

## Known Stubs

`extract_test_calls_buf()` remains a stub returning `{}`. This is intentional: GIN-07 (http.NewRequest codelens for test files) is explicitly deferred to Plan 02 per the task description ("Do NOT touch extract_test_calls_buf yet — handled in Plan 02"). The plan's goal (route extraction) is fully achieved; the stub does not prevent correct route display in the explorer or picker.

## Commits

| Task | Commit | Files |
|------|--------|-------|
| Task 1: Tree-sitter query files | 961b801 | queries/go/gin-routes.scm, queries/go/gin-groups.scm |
| Task 2: gin.lua implementation | 4a27e5d | lua/nimbleapi/providers/gin.lua |

## Self-Check: PASSED
