---
phase: 07-route-extraction-single-file
plan: 01
subsystem: express-provider
tags: [tree-sitter, express, javascript, typescript, route-extraction]
dependency_graph:
  requires:
    - 06-01 (express provider infrastructure — JS/TS provider tables, detection)
  provides:
    - extract_routes(filepath) for both JS and TS Express providers
    - get_all_routes(root) for both JS and TS Express providers
    - queries/javascript/express-routes.scm
    - queries/typescript/express-routes.scm
  affects:
    - lua/nimbleapi/providers/express.lua
    - queries/javascript/express-routes.scm
    - queries/typescript/express-routes.scm
tech_stack:
  added:
    - queries/javascript/ directory (new language query dir)
    - queries/typescript/ directory (new language query dir)
  patterns:
    - Two-pass extraction: tree-sitter query (direct calls) + Lua AST walker (chain calls)
    - normalize_path() with :param -> {param} and *wildcard -> {wildcard}
    - get_all_routes_for_ext() file scanner with pre-filter heuristic (avoids parsing non-route files)
key_files:
  created:
    - queries/javascript/express-routes.scm
    - queries/typescript/express-routes.scm
  modified:
    - lua/nimbleapi/providers/express.lua
decisions:
  - Shared internal extract_routes(filepath, language) function — JS and TS providers close over it with their language string, matching the existing pattern for check_prerequisites/detect/find_project_root
  - Two-pass strategy: tree-sitter query for direct routes, Lua recursive walker for app.route() chains — chain AST depth is arbitrary so queries cannot match it reliably
  - Top-level expression_statement scan for chains — prevents duplicate records from intermediate chain call_expression nodes
  - Pre-filter heuristic (.get(/.post(/.route(/.all() string match) before parsing — avoids tree-sitter parse overhead for non-route files
metrics:
  duration_seconds: 114
  completed_date: "2026-03-27"
  tasks_completed: 2
  tasks_total: 2
  files_changed: 3
---

# Phase 07 Plan 01: Express Route Extraction (Single-File) Summary

**One-liner:** Two-pass Express route extraction — tree-sitter query for direct `app.METHOD()` calls and a recursive Lua AST walker for `app.route().METHOD()` chains — with `:param`/`*wildcard` normalization and identical JS/TS query files.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Create Express route query files for JS and TS | cd7bc80 | queries/javascript/express-routes.scm, queries/typescript/express-routes.scm |
| 2 | Implement extract_routes and get_all_routes in Express provider | 80573cc | lua/nimbleapi/providers/express.lua |

## What Was Built

### Task 1: Query Files

Created `queries/javascript/express-routes.scm` and `queries/typescript/express-routes.scm` with identical content. The query matches `call_expression` nodes where:
- The method name matches `^(get|post|put|delete|patch|options|head|all)$` via `#match?` predicate (excludes `use`, `route`, `static`, `listen`, etc.)
- The first argument is a `string` containing a `string_fragment` capture (quote-free path)
- The `.` anchor ensures the handler is the immediate next sibling of the path string

### Task 2: Express Provider Implementation

Added to `lua/nimbleapi/providers/express.lua`:

- `EXPRESS_METHODS` — maps lowercase method names to uppercase HTTP verbs; `all` maps to `ANY`
- `HTTP_METHODS_SET` — set used by `walk_chain` to recognize HTTP verb calls (no `all` — chain HTTP methods are real verbs only)
- `normalize_path()` — `:param` → `{param}`, `*wildcard` → `{wildcard}`
- `extract_direct_routes()` — runs the tree-sitter query, handles identifier/member_expression handler text vs empty string for arrow/function handlers
- `walk_chain()` — recursive descent: base case is `.route('/path')` call, recursive case is HTTP method call wrapping a deeper chain
- `extract_chain_routes()` — scans top-level `expression_statement` children only (prevents duplicates from intermediate chain nodes)
- `extract_routes()` — merges direct + chain results, sorts by line number
- `get_all_routes_for_ext()` — globs files by extension, pre-filters with string heuristic, calls `extract_routes`

Both `JS` and `TS` provider tables now have working `extract_routes`, `get_all_routes`, and `get_route_tree`. Stubs retained: `find_app` (nil), `extract_includes` ({}), `extract_test_calls_buf` ({}).

## Requirements Satisfied

| Req ID | Description | Status |
|--------|-------------|--------|
| EXPR-01 | app.METHOD(path, handler) and router.METHOD(path, handler) routes visible | Done — query + extract_direct_routes |
| EXPR-02 | app.all(path, handler) → method ANY | Done — EXPRESS_METHODS["all"] = "ANY" |
| EXPR-03 | app.route('/path').get(h).post(h) → two separate route entries | Done — walk_chain + extract_chain_routes |
| EXPR-04 | Path params: :param → {param}, *wildcard → {wildcard} | Done — normalize_path() |
| EXPR-05 | app.use(fn) middleware calls excluded | Done — #match? predicate in query |
| ETS-01 | .ts parsed with "typescript", .js with "javascript" | Done — language arg threaded through |
| ETS-02 | Real query files in both queries/javascript/ and queries/typescript/ | Done — identical files, no symlinks |
| EWAT-01 | *.js and *.ts trigger auto-refresh | Already satisfied (plugin/nimbleapi.lua:52) |

## Deviations from Plan

None — plan executed exactly as written.

## Known Stubs

The following stubs are intentional and tracked for future phases:

| Stub | File | Reason |
|------|------|--------|
| `JS.find_app` / `TS.find_app` returning nil | express.lua | Express has no single entry point; Phase 8+ |
| `JS.extract_includes` / `TS.extract_includes` returning {} | express.lua | Router composition is Phase 8 work (ECOMP-01..05) |
| `JS.extract_test_calls_buf` / `TS.extract_test_calls_buf` returning {} | express.lua | CodeLens is Phase 9 work (ECLEN-01..02) |

These stubs do NOT prevent this plan's goal (single-file route extraction) from being achieved.

## Self-Check: PASSED
