---
phase: 02-gin-provider
plan: 02
subsystem: api
tags: [gin, go, treesitter, codelens, testclient]

# Dependency graph
requires:
  - phase: 02-gin-provider/02-01
    provides: gin.lua provider with route extraction, group prefix resolution, and base provider interface

provides:
  - queries/go/gin-testclient.scm — Tree-sitter query for http.NewRequest patterns in Go test files
  - gin.lua extract_test_calls_buf — parses live buffers to find test HTTP calls for codelens matching
  - Bug fix: explorer.lua sanitizes route fields before nvim_buf_set_lines (strips newlines)
  - Bug fix: gin.lua handles func_literal nodes (anonymous inline handlers) gracefully
  - GIN-07 fully implemented and end-to-end verified

affects: [03-echo-provider, 04-chi-provider, 05-stdlib-provider]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "http.NewRequest codelens pattern: capture @http_method + @test_path + @test_call from call_expression with #eq? predicates on operand/field"
    - "parse_buffer (not parse_file) for live buffer codelens extraction — second return is bufnr used as get_text source"
    - "func_literal guard in extract_routes: check node:type() == 'func_literal' and emit empty string to prevent multi-line body capture"
    - "nvim_buf_set_lines safety: always gsub newlines from route.path and route.func before rendering"

key-files:
  created:
    - queries/go/gin-testclient.scm
  modified:
    - lua/nimbleapi/providers/gin.lua
    - lua/nimbleapi/explorer.lua

key-decisions:
  - "No @client_var capture in gin-testclient.scm — http.NewRequest is a package-level function, not a method on a client variable; codelens matching uses method+path only"
  - "func_literal anonymous handlers emit empty func name rather than blocking route extraction — route is still visible in explorer without a handler label"
  - "Newline sanitization applied at render time in explorer.lua rather than at parse time in the provider — keeps provider output raw, display layer defensive"

patterns-established:
  - "Test client query pattern: use #eq? predicates on @_pkg and @_func (underscore-prefixed = internal, not consumed by Lua) to filter by package.Function"
  - "extract_test_calls_buf always uses parse_buffer(bufnr, lang) not parse_file — test calls must reflect unsaved buffer state for codelens responsiveness"

requirements-completed: [GIN-07]

# Metrics
duration: ~45min
completed: 2026-03-26
---

# Phase 02 Plan 02: Gin Codelens and End-to-End Verification Summary

**Gin codelens for http.NewRequest test calls added and full Gin provider verified end-to-end with group prefix resolution, explorer, picker, and codelens all confirmed working**

## Performance

- **Duration:** ~45 min
- **Started:** 2026-03-26T18:14:24Z
- **Completed:** 2026-03-26T18:45:00Z
- **Tasks:** 2 (1 auto + 1 human-verify checkpoint)
- **Files modified:** 3

## Accomplishments

- Implemented `queries/go/gin-testclient.scm` with `http.NewRequest` Tree-sitter pattern using `#eq?` predicates to match `http.NewRequest` specifically
- Implemented `extract_test_calls_buf(bufnr)` in gin.lua following the established springboot.lua pattern — returns `{ method, path, line, file }` records for codelens matching
- End-to-end verification confirmed: `:NimbleAPI toggle` shows correct routes with fully-resolved group prefixes, `:NimbleAPI pick` fuzzy search works, codelens annotations appear in `*_test.go` files
- Fixed two bugs surfaced during live testing that blocked correct rendering

## Task Commits

1. **Task 1: Create test client query and implement extract_test_calls_buf** - `544422e` (feat)
2. **Task 2: Verify Gin provider end-to-end** — human-verify checkpoint, approved by user
3. **Bug fix: sanitize route fields and handle func_literal nodes** - `51a0f7c` (fix)

**Plan metadata:** (docs commit — see final commit)

## Files Created/Modified

- `queries/go/gin-testclient.scm` — Tree-sitter query matching `http.NewRequest("METHOD", "/path", ...)` in Go test files; captures `@http_method`, `@test_path`, `@test_call`
- `lua/nimbleapi/providers/gin.lua` — `extract_test_calls_buf` implementation; also fixed func_literal guard
- `lua/nimbleapi/explorer.lua` — Newline sanitization on route.path and route.func before `nvim_buf_set_lines`

## Decisions Made

- No `@client_var` capture in gin-testclient.scm because `http.NewRequest` is a package-level function (`http.NewRequest`), not a method on a client object. Codelens matching is purely method+path.
- Anonymous inline handlers (`func(c *gin.Context) { ... }`) emit an empty string for func_name rather than the full multi-line function body, which caused `nvim_buf_set_lines` to error.
- Newline sanitization placed in `explorer.lua` at render time rather than in the provider, keeping provider output raw and the display layer defensive.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed func_literal nodes producing multi-line function body as handler name**
- **Found during:** Task 2 (end-to-end verification)
- **Issue:** When a Gin route uses an inline anonymous handler (`r.GET("/path", func(c *gin.Context) {...})`), the Tree-sitter `@func_name` capture matched the full `func_literal` node. `parser.get_text()` returned the entire multi-line function body, which was stored as `route.func`. This caused `nvim_buf_set_lines` to throw `E315: ml_get: invalid lnum` because line strings cannot contain newlines.
- **Fix:** Added `if node:type() == "func_literal" then func_name_text = "" end` guard in `extract_routes` before calling `get_text`. Anonymous handlers are now recorded with an empty func name.
- **Files modified:** `lua/nimbleapi/providers/gin.lua`
- **Verification:** Routes with inline handlers appear in explorer without errors
- **Committed in:** `51a0f7c`

**2. [Rule 1 - Bug] Fixed nvim_buf_set_lines crash on route fields containing newlines**
- **Found during:** Task 2 (end-to-end verification)
- **Issue:** `explorer.lua:320` used `route.path` and `route.func` directly in string concatenation before passing to `nvim_buf_set_lines`. If either field contained a newline (e.g., from a multi-line func_literal capture), Neovim would error because buffer lines must not contain `\n` or `\r`.
- **Fix:** Applied `.gsub("[\n\r]", "")` to both `route.path` and `route.func` at the render site in `_render_route_line`.
- **Files modified:** `lua/nimbleapi/explorer.lua`
- **Verification:** Explorer renders without errors for all route types including those with anonymous handlers
- **Committed in:** `51a0f7c`

---

**Total deviations:** 2 auto-fixed (both Rule 1 — bug fixes)
**Impact on plan:** Both fixes were necessary for correctness. The func_literal issue would have prevented any Gin project using inline handlers from loading the explorer. The newline sanitization is a defensive belt-and-suspenders fix that prevents the same class of error from resurfacing with future providers.

## Issues Encountered

- The `gin-testclient.scm` query uses `.` (anchor) after the second argument to avoid matching partial argument lists. This is required because `http.NewRequest` with only 2 args is unusual — the third arg (body) is typically `nil`. The anchor ensures the pattern is specific.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- Gin provider (GIN-01 through GIN-07) is complete and verified
- Phase 02 is complete — ready to begin Phase 03 (Echo provider)
- The `extract_test_calls_buf` pattern established here is directly reusable for Echo, Chi, and stdlib providers (they all use `http.NewRequest`)
- The `func_literal` guard and newline sanitization patterns should be applied proactively in all future Go providers

---
*Phase: 02-gin-provider*
*Completed: 2026-03-26*

## Self-Check: PASSED

- FOUND: `.planning/phases/02-gin-provider/02-02-SUMMARY.md`
- FOUND: `queries/go/gin-testclient.scm`
- FOUND: `lua/nimbleapi/providers/gin.lua`
- FOUND: `lua/nimbleapi/explorer.lua`
- FOUND: commit `544422e` (feat: implement Gin codelens test client extraction)
- FOUND: commit `51a0f7c` (fix: sanitize route fields and handle func_literal nodes)
