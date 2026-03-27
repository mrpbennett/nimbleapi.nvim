---
phase: 03-echo-provider
plan: 02
status: checkpoint — awaiting human verification (Task 2)
completed_tasks: [1]
pending_tasks: [2]
---

# Phase 03-02 Summary: Echo Testclient Query + extract_test_calls_buf

## What Was Built

### Task 1 (Complete)

**`queries/go/echo-testclient.scm`** — Tree-sitter query for `httptest.NewRequest` patterns in Go test files.

Key design decisions:
- Package predicate `(#eq? @_pkg "httptest")` targets Echo's test package (vs `"http"` used by Gin)
- Function predicate `(#eq? @_func "NewRequest")` — unchanged from Gin pattern
- First argument captured as `(_) @http_method_expr` (any node, not just `interpreted_string_literal`) — handles both `"GET"` string literal AND `http.MethodGet` selector_expression forms
- Second argument captured as `(interpreted_string_literal) @test_path` — paths are always string literals
- Full call expression captured as `@test_call` — for line number extraction

**`lua/nimbleapi/providers/echo.lua`** — `extract_test_calls_buf` implementation replacing the stub.

Key implementation details:
- Uses `parser.parse_buffer(bufnr, "go")` (live buffer, not file — required for codelens)
- Calls `parser.get_query_public("echo-testclient", "go")` to load the new query
- Uses `type(nodes) == "table" and nodes[1] or nodes` pattern for Neovim 0.10+ `iter_matches` compat
- Type-aware method processing:
  - `interpreted_string_literal` → `strip_quotes(text)` → `"GET"` becomes `GET`
  - `selector_expression` → matches `http.MethodGet` → extracts `Get` suffix → uppercases to `GET`
  - Fallback path: full text uppercased for any other node type
- Returns `{ method, path, line, file }` records matching the codelens.lua contract
- Line is 1-indexed (`node:range() + 1`)

## Files Modified

| File | Change |
|------|--------|
| `queries/go/echo-testclient.scm` | Created — new Tree-sitter query |
| `lua/nimbleapi/providers/echo.lua` | Replaced stub with full implementation |

## Commit

`6d931b8` — `feat(03-02): add Echo testclient query and extract_test_calls_buf`

## Verification

Automated check passed:
```
test -f queries/go/echo-testclient.scm
grep -q "@http_method_expr" queries/go/echo-testclient.scm
grep -q "@test_path" queries/go/echo-testclient.scm
grep -q "@test_call" queries/go/echo-testclient.scm
grep -q "httptest" queries/go/echo-testclient.scm
grep -q 'get_query_public.*echo-testclient' lua/nimbleapi/providers/echo.lua
grep -q "parse_buffer" lua/nimbleapi/providers/echo.lua
grep -q "http_method_expr" lua/nimbleapi/providers/echo.lua
→ PASS
```

## Checkpoint: Human Verification Required (Task 2)

Task 2 is a blocking human-verify checkpoint. The agent has stopped here.

**What to verify:**

1. Open an Echo project in Neovim (any project with `github.com/labstack/echo` in go.mod)
2. `:NimbleAPI info` — confirm provider: echo, no errors
3. `:NimbleAPI toggle` — confirm routes with resolved group prefixes appear in sidebar
4. `:NimbleAPI pick` — confirm fuzzy search over all routes works
5. Open a `*_test.go` file with `httptest.NewRequest(...)` calls — confirm:
   - Virtual text annotations appear on test call lines
   - Both `httptest.NewRequest("GET", "/path", nil)` and `httptest.NewRequest(http.MethodGet, "/path", nil)` produce annotations
   - `gd` on an annotated line jumps to the route handler

**Resume signal:** Type "approved" if verification passes, or describe any issues.

## Requirements Coverage

| Requirement | Status |
|-------------|--------|
| ECHO-07: httptest.NewRequest codelens | Complete (pending human verification) |
| ECHO-01 through ECHO-06 | Complete (delivered in Plan 01) |
