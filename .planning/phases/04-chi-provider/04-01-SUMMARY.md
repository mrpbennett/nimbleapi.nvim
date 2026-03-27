---
phase: 04-chi-provider
plan: 01
subsystem: api
tags: [chi, go, tree-sitter, route-extraction, ast-walking]

# Dependency graph
requires:
  - phase: 02-gin-provider
    provides: "Gin provider pattern — extract_routes, get_all_routes, strip_quotes, func_literal guard, iter_matches compat"
  - phase: 01-go-foundation
    provides: "parser.lua Go support, utils.lua glob_files/file_contains, normalize_path pattern"
provides:
  - "Chi Tree-sitter query (chi-routes.scm) covering all registration patterns"
  - "Chi provider extract_routes with parent-chain closure prefix resolution (CHI-05)"
  - "Chi provider get_all_routes scanning all Go files with Chi-specific pre-filtering"
  - "CHI_METHODS lookup table mapping mixed-case Chi methods to HTTP method strings"
  - "collect_route_prefixes() helper for AST parent-chain walking"
affects: [04-chi-provider plan 02, providers/init.lua, codelens]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Parent-chain AST walking to resolve closure-based route nesting (Chi-specific, no variable table needed)"
    - "Single-pass route extraction — Route/Group calls captured by query but skipped in Lua with goto continue"
    - "Depth-limited parent walk (max 50) with inside-out prefix accumulation via table.insert(prefixes, 1, prefix)"

key-files:
  created:
    - queries/go/chi-routes.scm
  modified:
    - lua/nimbleapi/providers/chi.lua

key-decisions:
  - "Parent-chain walk (Option B) chosen over pure Tree-sitter nesting — simpler, more reliable with Neovim's TS engine"
  - "Route and Group calls captured by chi-routes.scm but skipped in Lua (goto continue) — Route serves as parent-chain anchor"
  - "r.Mount emits method MOUNT with path = prefix (no /* suffix) per D-CHI-01"
  - "r.Group contributes zero prefix — routes inside inherit parent's prefix chain per D-CHI-02"
  - "CHI_METHODS uses mixed-case keys (Get/Post not GET/POST) matching Chi's actual API"

patterns-established:
  - "collect_route_prefixes(start_node, source): reusable pattern for any closure-based router nesting"
  - "goto continue in LuaJIT to skip non-route entries cleanly within iter_matches loop"

requirements-completed: [CHI-01, CHI-02, CHI-03, CHI-04, CHI-05, CHI-06, CHI-07]

# Metrics
duration: 15min
completed: 2026-03-26
---

# Phase 4 Plan 01: Chi Route Extraction Summary

**Chi route extraction with parent-chain AST walking for closure-based r.Route nesting, covering all 9 HTTP method shortcuts, Handle/HandleFunc (ANY), Method/MethodFunc, and Mount (MOUNT)**

## Performance

- **Duration:** ~15 min
- **Started:** 2026-03-26T19:30:00Z
- **Completed:** 2026-03-26T19:45:00Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments

- Created `queries/go/chi-routes.scm` with two patterns: all-methods pattern (Pattern 1) and Method/MethodFunc pattern (Pattern 2 with `#match?` predicate)
- Implemented `extract_routes()` with the novel parent-chain walk algorithm (`collect_route_prefixes`) that resolves Chi's closure-based nesting without a variable table
- Implemented `get_all_routes()` scanning all `*.go` files with Chi-specific pre-filter strings
- Added `CHI_METHODS` lookup table with mixed-case Chi method names (Get/Post/Put etc.)
- Added `get_route_tree()` thin wrapper returning ChiApp route tree structure

## Task Commits

Each task was committed atomically:

1. **Task 1: Chi Tree-sitter query (chi-routes.scm)** - `[hash-t1]` (feat)
2. **Task 2: Chi provider extract_routes and get_all_routes** - `[hash-t2]` (feat)

**Plan metadata:** `[hash-docs]` (docs: complete plan)

_Note: commit hashes updated after git operations_

## Files Created/Modified

- `queries/go/chi-routes.scm` - Two-pattern Tree-sitter query covering all Chi route registration styles
- `lua/nimbleapi/providers/chi.lua` - Full provider implementation with parent-chain closure resolution

## Decisions Made

- **Parent-chain walk chosen over pure TS query** — Chi's `r.Route("/prefix", func(r chi.Router) { ... })` closure syntax creates nested AST nodes where the inner `r` shadows the outer. Walking `node:parent()` upward to find enclosing `call_expression` nodes with method "Route" is simpler than any Tree-sitter-only approach and works reliably with Neovim's engine.
- **Route/Group in query but skipped in Lua** — Capturing Route and Group with the same Pattern 1 is intentional: the `@route_def` node on Route calls enables the parent-chain walk. Skipping them with `goto continue` keeps the emit logic clean.
- **Mount path with no `/*` suffix** — Per D-CHI-01: emit the mount prefix as-is (e.g., `/admin`) rather than `/admin/*`. This matches how explorers typically display mount points.
- **Group contributes zero prefix** — Per D-CHI-02: `r.Group(func...)` is middleware-scoped only; `collect_route_prefixes` explicitly skips Group ancestors.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Chi route extraction is complete and ready for Plan 02 (Chi codelens/testclient support)
- `extract_test_calls_buf` is stubbed returning `{}` — Plan 02 fills this in with `chi-testclient.scm`
- Provider is registered via `require("nimbleapi.providers").register(M)` and ready for detection/use

---
*Phase: 04-chi-provider*
*Completed: 2026-03-26*
