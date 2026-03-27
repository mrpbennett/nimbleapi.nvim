# Phase 3: Echo Provider - Research

**Researched:** 2026-03-26
**Domain:** Echo framework route patterns, Go Tree-sitter queries, Lua provider implementation
**Confidence:** HIGH (based on `.planning/research/echo.md` + Gin Phase 2 patterns)

## Summary

This phase fills in the echo.lua stub created in Phase 1. The approach mirrors Gin Phase 2 exactly — write Tree-sitter queries for Go+Echo patterns, then implement extraction logic using the existing `parser.lua` infrastructure. The queries are structurally identical to the Gin queries with only the method list and test client package name changing.

The two-pass group prefix resolution algorithm developed for Gin (gin.lua `resolve_prefix()`) is directly reusable for Echo — both frameworks use the same `g := e.Group("/prefix")` variable assignment pattern at the Go AST level. No algorithmic changes are needed.

The codelens query changes package from `http` to `httptest` — Echo tests use `httptest.NewRequest` (from `net/http/httptest`) rather than `http.NewRequest` (from `net/http`). The rest of the query structure is identical.

**Key lessons from Gin Phase 2 to apply proactively:**
1. func_literal guard — anonymous inline handlers produce multi-line body text that crashes `nvim_buf_set_lines`; always check `node:type() == "func_literal"` before calling `get_text`
2. Newline sanitization — already applied in explorer.lua; no additional action needed in echo.lua
3. iter_matches compatibility — always use `type(nodes) == "table" and nodes[1] or nodes` before accessing nodes

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** `e.Any("/path", handler)` records as a **single entry with method `ANY``
- **D-02:** Track Group variable assignments within the **same file only** — cross-function/file deferred
- **D-03:** Scan **all `*.go` files** with pre-filtering on `echo.`/`.GET(`/etc.; no entry-point needed
- **D-04:** Show **first match only** in codelens virtual text
- **D-05:** `e.Add("METHOD", "/path", handler)` — method from first string argument
- **D-06:** `e.Match([]string{...}, path, handler)` — deferred; not included

### Deferred

- `e.Match(...)` — composite literal for method list; too complex for MVP
- `e.AddRoute(route Route)` — v5-only struct-based registration; too rare to prioritize
- Cross-function group prefix tracking
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| ECHO-01 | Echo project detection via `go.mod` containing `github.com/labstack/echo` | Already implemented in Phase 1 stub — no work needed |
| ECHO-02 | Route extraction for HTTP method shortcuts: GET, POST, PUT, DELETE, PATCH, HEAD, OPTIONS, CONNECT, TRACE | Same `call_expression` + `selector_expression` pattern as Gin; 9 method names |
| ECHO-03 | Route extraction for `e.Add("METHOD", "/path", handler)` — method from first string arg | Field name `Add`, first arg is method string; analogous to Gin's Handle |
| ECHO-04 | Route extraction for `e.Any("/path", handler)` recorded as method `ANY` | Same pattern as ECHO-02; method name `Any` maps to `ANY` |
| ECHO-05 | Group detection: `g := e.Group("/prefix")` short variable declarations | `short_var_declaration` with `call_expression` RHS; field name `Group`; identical TS shape to Gin |
| ECHO-06 | Full recursive prefix resolution: nested groups fully concatenated | Same Lua-side two-pass + `resolve_prefix()` algorithm as Gin |
| ECHO-07 | CodeLens for `httptest.NewRequest(method, "/path", ...)` in `*_test.go` files | Same query shape as Gin's `http.NewRequest`; change `@_pkg` to `httptest` |

</phase_requirements>

---

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| nvim-treesitter (Go parser) | bundled | Parses Go source into AST | Required by INFRA-01, validated in Phase 1 |
| tree-sitter-go grammar | shipped with nvim-treesitter | Go node types and field names | Authoritative grammar |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `parser.lua` (internal) | — | `parse_file()`, `get_query_public()`, `get_text()`, `parse_buffer()` | All file/buffer parsing |
| `utils.lua` (internal) | — | `glob_files()`, `file_contains()`, `join()` | File discovery and pre-filtering |

---

## Pattern Analysis

### Pattern 1: Method Shortcuts (ECHO-02, ECHO-04)

`e.GET("/users", handler)` — identical Go AST shape to Gin:

```
(call_expression
  function: (selector_expression
    operand: (identifier)        ; "e" — the Echo/Group variable
    field: (field_identifier))   ; "GET" — the HTTP method
  arguments: (argument_list
    (interpreted_string_literal) ; "/users"
    (_)))                        ; handler (identifier or selector_expression)
```

All 9 method shortcuts (GET/POST/PUT/DELETE/PATCH/HEAD/OPTIONS/CONNECT/TRACE) and `Any` match this exact AST shape. The same single-pattern query covers all of them; Lua-side ECHO_METHODS table provides the filter.

**Query (echo-routes.scm, Pattern 1):**
```scheme
(call_expression
  function: (selector_expression
    operand: (identifier) @router_obj
    field: (field_identifier) @http_method)
  arguments: (argument_list
    (interpreted_string_literal) @route_path
    .
    (_) @func_name)) @route_def
```

No `#eq?` predicate — let all method names match; filter in Lua via ECHO_METHODS table (same approach as Gin).

### Pattern 2: e.Add (ECHO-03)

`e.Add("GET", "/users", handler)` — method is first string arg, path is second:

```
(call_expression
  function: (selector_expression
    operand: (identifier)        ; "e"
    field: (field_identifier)    ; "Add"
  arguments: (argument_list
    (interpreted_string_literal) ; "GET" — the HTTP method
    (interpreted_string_literal) ; "/users" — the path
    (_)))                        ; handler
```

**Query (echo-routes.scm, Pattern 2):**
```scheme
(call_expression
  function: (selector_expression
    operand: (identifier) @router_obj
    field: (field_identifier) @http_method
    (#eq? @http_method "Add"))
  arguments: (argument_list
    (interpreted_string_literal) @_add_method
    (interpreted_string_literal) @route_path
    .
    (_) @func_name)) @route_def
```

Lua logic: if `http_method_text == "Add"`, read method from `@_add_method` capture (strip quotes, uppercase). Mirrors exact Gin Handle() logic.

### Pattern 3: Group Assignments (ECHO-05, ECHO-06)

`g := e.Group("/api")` — identical AST shape to Gin's RouterGroup:

```
(short_var_declaration
  left: (expression_list (identifier))  ; "g"
  right: (expression_list
    (call_expression
      function: (selector_expression
        operand: (identifier)           ; "e" or parent group var
        field: (field_identifier))      ; "Group"
      arguments: (argument_list
        (interpreted_string_literal))))) ; "/api"
```

**Query (echo-groups.scm):** Copy gin-groups.scm exactly — same node types, same predicates (`#eq? @_group_method "Group"`), same capture names.

### Pattern 4: Test Client (ECHO-07)

`httptest.NewRequest(http.MethodGet, "/path", nil)` in test files.

Key observation: the first argument is often `http.MethodGet` (a constant identifier expression), NOT a string literal. However, it can also be a string literal `"GET"`. The query should capture both.

Two approaches:
1. Capture first arg as `(_)` (any node) then in Lua check node type: if `interpreted_string_literal` call strip_quotes; if `selector_expression` (e.g., `http.MethodGet`) extract the field name (`MethodGet`) and map to HTTP method ("GET")
2. Only match string literal form `"GET"` and miss the `http.MethodGet` form

**Recommendation:** Use approach 1 — capture as `(_) @http_method_expr`, then in Lua:
- If node type is `interpreted_string_literal`: strip_quotes(text) → method
- If node type is `selector_expression`: extract field_identifier text, strip "Method" prefix (MethodGet → "GET")

This gives coverage of both common forms.

**Query (echo-testclient.scm):**
```scheme
; httptest.NewRequest(method, "/path", ...) calls in test files
(call_expression
  function: (selector_expression
    operand: (identifier) @_pkg
    field: (field_identifier) @_func
    (#eq? @_pkg "httptest")
    (#eq? @_func "NewRequest"))
  arguments: (argument_list
    (_) @http_method_expr
    (interpreted_string_literal) @test_path
    .)) @test_call
```

Note: capture name for method is `@http_method_expr` (not `@http_method`) to signal it requires type-aware post-processing.

### Pattern 5: Two-Pass Group Resolution Algorithm

Identical to gin.lua. Pseudocode:

```
Pass 1: gin-groups.scm query → groups table
  groups[group_var] = { prefix = "/api", parent = "e" }

Pass 2: gin-routes.scm query → routes
  for each route match:
    prefix = resolve_prefix(router_obj, groups, {})
    full_path = normalize_path(prefix .. route_path)
    emit { method, path=full_path, func, file, line }
```

`resolve_prefix()` is a direct copy from gin.lua — no modifications needed.

---

## Pitfalls and Gotchas

### Pitfall 1: func_literal anonymous handlers (CRITICAL — from Gin Phase 2 bug fix)

`e.GET("/path", func(c echo.Context) error { ... })` — the `@func_name` capture matches the entire `func_literal` node. `parser.get_text()` returns the full multi-line body, which crashes `nvim_buf_set_lines` with `E315: ml_get: invalid lnum`.

**Fix:** `if node:type() == "func_literal" then func_name_text = "" end` — apply in extract_routes before calling get_text on `@func_name`.

### Pitfall 2: http.MethodGet vs "GET" in test files

`httptest.NewRequest(http.MethodGet, "/path", nil)` — the method argument is a `selector_expression` (`http.MethodGet`), not a string literal. Capturing as `(interpreted_string_literal)` will miss this form.

**Fix:** Capture as `(_) @http_method_expr`, then in Lua handle both node types.

### Pitfall 3: iter_matches node compatibility (CRITICAL)

`for id, nodes in pairs(match)` — in Neovim 0.10+, `nodes` may be a table (slice) rather than a single node.

**Fix:** Always apply `local node = type(nodes) == "table" and nodes[1] or nodes` before using the node.

### Pitfall 4: Group with middleware argument

`admin := e.Group("/admin", authMiddleware)` — the Group call has additional arguments after the prefix string. The groups query must not anchor after the first argument:

```scheme
arguments: (argument_list
  (interpreted_string_literal) @route_path)  ; NO anchor — allows additional middleware args
```

Gin's group query already handles this correctly (no anchor on Group arguments).

### Pitfall 5: Cycle guard in resolve_prefix

`v1 := v1.Group("/sub")` (same variable name reused) — the resolve_prefix `visited` set prevents infinite recursion. Always pass `{}` as the initial visited set per-route-resolution call.

### Pitfall 6: Add method argument is string with uppercase method name

`e.Add("GET", "/path", handler)` — the method is `"GET"` (already uppercase). After strip_quotes, no additional uppercasing is needed. But `e.Add("get", ...)` with lowercase is theoretically possible. Apply `.upper()` defensively: `handle_method_text:upper()`.

---

## Anti-Patterns to Avoid

- **Do not** use `#eq?` to filter method shortcuts in the query — filter in Lua via ECHO_METHODS table (more robust against query engine version differences)
- **Do not** use `(string_literal)` — Go string nodes are `(interpreted_string_literal)` or `(raw_string_literal)`; use `(interpreted_string_literal)` for path and method strings
- **Do not** anchor the route query's argument list after `@func_name` — middleware args may follow the handler: `e.GET("/path", handler, middleware1, middleware2)`
- **Do not** track group variables across files — same-file only (D-02)

---

## ECHO_METHODS Table

```lua
local ECHO_METHODS = {
  GET     = "GET",
  POST    = "POST",
  PUT     = "PUT",
  DELETE  = "DELETE",
  PATCH   = "PATCH",
  HEAD    = "HEAD",
  OPTIONS = "OPTIONS",
  CONNECT = "CONNECT",
  TRACE   = "TRACE",
  Any     = "ANY",
}
```

Note: Echo has 9 HTTP method shortcuts (vs Gin's 7 — Echo adds CONNECT and TRACE). `Any` maps to "ANY".

---

## HTTP Method Constant Mapping (for httptest.NewRequest)

When the test file uses `http.MethodXxx` constants:

| Go constant | HTTP method |
|-------------|-------------|
| `http.MethodGet` | GET |
| `http.MethodPost` | POST |
| `http.MethodPut` | PUT |
| `http.MethodDelete` | DELETE |
| `http.MethodPatch` | PATCH |
| `http.MethodHead` | HEAD |
| `http.MethodOptions` | OPTIONS |
| `http.MethodConnect` | CONNECT |
| `http.MethodTrace` | TRACE |

Pattern: strip `"Method"` prefix from the constant name and uppercase the result.

In Lua: `text:match("^Method(.+)$")` extracts the suffix, then `:upper()` normalizes it.

---

## File Pre-filter Strings

Files to parse via `utils.file_contains` pre-filter:
- `"echo."` — catches `echo.New()`, `echo.Echo`, import usage
- `".GET("` — route method call
- `".POST("` — route method call
- `".Group("` — group creation
- `".Add("` — generic Add route registration

This is the same approach as Gin's pre-filter, adapted for Echo's import path.
