---
phase: 05-stdlib-provider
plan: 02
status: complete
completed: 2026-03-26
commits:
  - ff17edc  feat(05-02): add stdlib-testclient.scm query for httptest.NewRequest codelens
  - 95df68f  feat(05-02): implement extract_test_calls_buf in stdlib provider
  - e68b223  feat(05-02): enhance stdlib detect() with source-scan fallback (STD-01)
---

## What Was Done

### Task 1: queries/go/stdlib-testclient.scm
Created the Tree-sitter query for `httptest.NewRequest("METHOD", "/path", ...)` codelens matching.
Functionally identical to `chi-testclient.scm`; only the `(#eq? @_pkg "httptest")` predicate differs (chi uses the same httptest package — they are in fact identical, which is correct).
Captures: `@http_method`, `@test_path`, `@test_call`. Internal-only: `@_pkg`, `@_func`.

### Task 2: extract_test_calls_buf implementation
Replaced the one-liner stub in `lua/nimbleapi/providers/stdlib.lua` with a full implementation.
Direct port of `gin.lua`'s `extract_test_calls_buf` — same structure, only the query name changed to `"stdlib-testclient"`.
Returns `{ method, path, line, file }` records for codelens.lua consumption.

### Task 3: Enhanced detect() (STD-01)
Replaced the naïve `return true` at end of detect() with a source-scan fallback:
- Globs all `**/*.go` files (excluding vendor/testdata/.git)
- Returns `true` only if at least one file contains `HandleFunc(` or `.Handle(`
- Returns `false` if no such file is found (non-HTTP Go project)
- Negative exclusion for Gin/Echo/Chi/Fiber runs FIRST to avoid unnecessary scanning

### Task 4: Smoke verification
All automated checks passed:
- File existence: OK
- Query captures (@route_path, @http_method, selector_expression): OK
- Provider functions (extract_routes, get_all_routes, extract_test_calls_buf, split_method_path): OK
- stdlib in providers_to_load (init.lua line 18): OK
- Provider self-registration via `require("nimbleapi.providers").register(M)` at stdlib.lua:243: OK
- No stub bodies remaining (early-exit guards are correct, not stubs)

Note: `providers/init.lua` has no hardcoded provider names — the registry uses a dynamic push pattern. "stdlib" is not present as a string in that file, which is correct and expected.

---

## Human-Verify Checkpoint

**Status: AWAITING MANUAL VERIFICATION**

The stdlib provider is code-complete. The following must be verified in a real net/http project before this plan can be marked done.

### Test Environment Required

A Go project that:
- Has `go.mod` (any module name)
- Does NOT import gin/echo/chi/fiber
- Uses `net/http` routing (`mux.HandleFunc`, `http.HandleFunc`, or `.Handle`)
- Has `*_test.go` files with `httptest.NewRequest` calls

### Verification Steps

1. **Detection check**
   Open the project in Neovim, run `:NimbleAPI info`
   - Expected: stdlib provider detected and active
   - Failure mode: "no provider detected" → detect() source-scan not finding HandleFunc/Handle

2. **Route explorer (pre-1.22 style)**
   Project has `mux.HandleFunc("/users", listUsers)` → run `:NimbleAPI toggle`
   - Expected: route entry with method=ANY, path=/users, func=listUsers

3. **Route explorer (Go 1.22+ style)**
   Project has `mux.HandleFunc("GET /users/{id}", getUser)` → run `:NimbleAPI toggle`
   - Expected: route entry with method=GET, path=/users/{id}, func=getUser

4. **Struct field receiver**
   Project has `s.mux.HandleFunc("/health", handler)` → run `:NimbleAPI toggle`
   - Expected: route entry captured (Pattern 2 in stdlib-routes.scm)

5. **Codelens on test file**
   Open a `*_test.go` file containing `httptest.NewRequest("POST", "/orders", body)`
   Run `:NimbleAPI codelens`
   - Expected: virtual text annotation linking the test call to the matching route handler

6. **False-positive rejection**
   Open a plain Go CLI project (no HTTP routing) in Neovim → run `:NimbleAPI info`
   - Expected: "no provider detected" (detect() returns false due to no HandleFunc/Handle in source)

### Files Changed in This Plan

- `queries/go/stdlib-testclient.scm` (new)
- `lua/nimbleapi/providers/stdlib.lua` (extract_test_calls_buf + detect() enhanced)
