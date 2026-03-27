---
phase: 04-chi-provider
plan: 02
status: checkpoint
completed_tasks: [1]
pending_tasks: [2]
commit: c794c1f
---

# Phase 04-02 Summary: Chi Codelens

## What Was Built

Task 1 (auto) completed. Task 2 is a human-verify checkpoint — awaiting user confirmation.

### Task 1: chi-testclient.scm query + extract_test_calls_buf

**`queries/go/chi-testclient.scm`** (new file):
- Tree-sitter query matching `httptest.NewRequest("METHOD", "/path", ...)` calls in Go test files
- Identical structure to `gin-testclient.scm` but uses `(#eq? @_pkg "httptest")` instead of `http`
- Captures: `@http_method`, `@test_path`, `@test_call` (plus internal `@_pkg`, `@_func` filtered by predicates)

**`lua/nimbleapi/providers/chi.lua`** — replaced stub with full implementation:
- Calls `parser.parse_buffer(bufnr, "go")` (live buffer, not file)
- Loads query via `parser.get_query_public("chi-testclient", "go")`
- Uses `type(nodes) == "table" and nodes[1] or nodes` iter_matches compat pattern
- Calls `strip_quotes` on method and path text from `interpreted_string_literal` nodes
- Returns `{ method, path, line, file }` records; line is 1-indexed via `node:range() + 1`
- Guards: only inserts entries where both `call.method` and `call.path` are truthy

All automated checks passed:
```
PASS: chi-testclient.scm exists with @http_method, @test_path, @test_call, NewRequest, httptest
PASS: chi.lua uses get_query_public("chi-testclient", ...) and parse_buffer
```

## Checkpoint

**Task 2 is a human-verify checkpoint** — the user must open a Chi project in Neovim and verify:
1. `:NimbleAPI info` shows Chi provider detected without errors
2. `:NimbleAPI toggle` shows routes with correctly-resolved closure-nested prefixes
3. `r.Route` nesting resolves correctly (e.g., `/users/{userID}/`)
4. `r.Group` routes appear at parent path level (zero prefix contribution)
5. `r.Mount` entries appear with method `MOUNT`
6. `:NimbleAPI pick` shows all routes
7. Codelens virtual text appears on `httptest.NewRequest` lines in `*_test.go` files

## Files Modified

| File | Change |
|------|--------|
| `queries/go/chi-testclient.scm` | Created — httptest.NewRequest TS query |
| `lua/nimbleapi/providers/chi.lua` | Replaced extract_test_calls_buf stub with full implementation |

## Commit

`c794c1f` — feat(04-02): add Chi codelens — chi-testclient.scm query and extract_test_calls_buf
