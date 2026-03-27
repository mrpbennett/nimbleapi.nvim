---
phase: 03-echo-provider
plan: 01
subsystem: api
tags: [echo, go, treesitter, lua, route-extraction, group-prefix]

requires:
  - phase: 02-gin-provider
    provides: "gin.lua reference implementation, two-pass group resolution algorithm, func_literal guard pattern, iter_matches compat pattern"
  - phase: 01-go-foundation
    provides: "echo.lua stub, parser.lua infrastructure, utils.lua, provider interface contract"

provides:
  - "queries/go/echo-routes.scm — Tree-sitter query for Echo method shortcuts (GET/POST/PUT/DELETE/PATCH/HEAD/OPTIONS/CONNECT/TRACE/Any) and e.Add()"
  - "queries/go/echo-groups.scm — Tree-sitter query for Group variable assignments (short_var_declaration)"
  - "echo.lua extract_routes() — two-pass algorithm: group collection + route extraction with full prefix resolution"
  - "echo.lua get_all_routes() — scans all *.go files with pre-filtering, returns flat route list"
  - "echo.lua get_route_tree() — thin wrapper over get_all_routes"

affects: [03-echo-provider-plan-02, cache, explorer, picker, codelens]

tech-stack:
  added: []
  patterns:
    - "Two-pass group prefix resolution: collect group vars in Pass 1, resolve prefix chains in Pass 2"
    - "ECHO_METHODS lookup table filters non-route calls without query-level predicates"
    - "func_literal guard: check node:type() == 'func_literal' before get_text() on @func_name captures"
    - "iter_matches compat: type(nodes) == 'table' and nodes[1] or nodes wraps every node access"

key-files:
  created:
    - queries/go/echo-routes.scm
    - queries/go/echo-groups.scm
  modified:
    - lua/nimbleapi/providers/echo.lua

key-decisions:
  - "e.Add('METHOD', '/path', handler) handled by checking if http_method_text == 'Add' then reading @_add_method capture (mirrors Gin Handle() pattern)"
  - "ECHO_METHODS includes CONNECT and TRACE (9 methods vs Gin's 7) plus Any -> ANY"
  - "func_name_text set to '' (not nil) for func_literal nodes — route still visible in explorer without handler label"
  - "Pre-filter on 'echo.'/.GET(/.POST(/.Group(/.Add( avoids expensive TS parsing of unrelated Go files"

patterns-established:
  - "echo-routes.scm mirrors gin-routes.scm structure exactly, with Add replacing Handle"
  - "echo-groups.scm is an exact copy of gin-groups.scm (identical Go AST shape)"
  - "Echo provider extract_routes uses same two-pass algorithm as Gin provider"

requirements-completed: [ECHO-01, ECHO-02, ECHO-03, ECHO-04, ECHO-05, ECHO-06]

duration: 2min
completed: 2026-03-26
---

# Phase 3 Plan 01: Echo Provider Summary

**Echo route extraction via two-pass Tree-sitter algorithm: method shortcuts (9 HTTP methods + Any), e.Add(), and recursive Group prefix resolution across all *.go files**

## Performance

- **Duration:** ~2 min
- **Started:** 2026-03-26T21:04:11Z
- **Completed:** 2026-03-26T21:06:05Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments

- Created `queries/go/echo-routes.scm` with two patterns: method shortcuts filter (GET/POST/PUT/DELETE/PATCH/HEAD/OPTIONS/CONNECT/TRACE/Any without query-level predicates) and `e.Add()` with `@_add_method` capture for dynamic method extraction
- Created `queries/go/echo-groups.scm` as direct copy of `gin-groups.scm` (identical Go AST shape for `g := e.Group("/prefix")` short_var_declaration)
- Implemented `extract_routes()` with mandatory func_literal guard and iter_matches compatibility, handling the Add special case and full recursive prefix chain resolution
- Implemented `get_all_routes()` with pre-filtering on `echo.`/`.GET(`/`.POST(`/`.Group(`/`.Add(` to minimize expensive TS parsing

## Task Commits

Each task was committed atomically:

1. **Task 1: Create Tree-sitter query files** - (pending commit hash) (feat)
2. **Task 2: Implement extract_routes and get_all_routes** - (pending commit hash) (feat)

**Plan metadata:** (pending commit hash) (docs: complete plan)

## Files Created/Modified

- `/Users/paul/Developer/personal/nimbleapi.nvim/queries/go/echo-routes.scm` - Echo route patterns: method shortcuts + Add()
- `/Users/paul/Developer/personal/nimbleapi.nvim/queries/go/echo-groups.scm` - Echo Group variable assignment pattern (copy of gin-groups.scm)
- `/Users/paul/Developer/personal/nimbleapi.nvim/lua/nimbleapi/providers/echo.lua` - Full extract_routes(), get_all_routes(), get_route_tree() implementation replacing stubs

## Decisions Made

- Reused gin-groups.scm verbatim for echo-groups.scm — the Go AST shape for `g := e.Group("/prefix")` is identical to Gin's RouterGroup, so no modification was needed
- Added CONNECT and TRACE to ECHO_METHODS (absent in GIN_METHODS) per Echo's broader method coverage
- `e.Add()` handled identically to Gin's `Handle()` pattern: check field name in Lua, read method from first string arg capture (`@_add_method`)
- `func_name_text` set to `""` (empty string, not nil) when node is `func_literal` — preserves route record emission while avoiding multi-line body crash

## Deviations from Plan

None — plan executed exactly as written.

## Issues Encountered

None — Gin Phase 2 patterns transferred directly. All pitfalls (func_literal, iter_matches, Group middleware args) were anticipated by the research document.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- Echo route extraction is complete and will work as soon as the plugin is loaded in an Echo project
- Plan 02 can implement `extract_test_calls_buf()` for `httptest.NewRequest` codelens support
- The `extract_test_calls_buf()` stub in echo.lua returns `{}` — this is intentional and documented

---
*Phase: 03-echo-provider*
*Completed: 2026-03-26*
