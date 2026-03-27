# Phase 5: stdlib Provider — Research

**Researched:** 2026-03-26
**Domain:** Go net/http stdlib route patterns, dual-era parsing (pre-1.22 vs 1.22+), selector_expression receiver chains, negative exclusion detection
**Confidence:** HIGH (patterns verified from Gin/Chi/Echo phases; stdlib-specific differences derived from net/http API and Go 1.22 release notes)

---

## Summary

Phase 5 fills in the stdlib provider stub. The architecture follows the same pattern as Gin, Echo, and Chi: write a Tree-sitter query for Go call expressions, implement extraction logic in `stdlib.lua` calling into existing `parser.lua` infrastructure. No cross-cutting changes to cache, explorer, picker, or codelens are needed.

The two key differences from Gin/Echo/Chi:

1. **No framework detection via go.mod** — stdlib detection uses negative exclusion: any Go project with `go.mod` that does NOT import Gin/Echo/Chi/Fiber is treated as stdlib. The stub in Phase 1 already implements this correctly (`stdlib.lua:detect()`).

2. **Dual-era route registration patterns** — pre-1.22 style embeds no HTTP method; Go 1.22+ style embeds method+path in a single string. The provider must handle both:
   - Pre-1.22: `mux.HandleFunc("/path", handler)` → method `ANY`, path `/path`
   - Go 1.22+: `mux.HandleFunc("GET /path", handler)` → method `GET`, path `/path`
   - Detection: if path string contains a space and the prefix matches an HTTP verb, split; otherwise record as `ANY`.

The stdlib query captures `HandleFunc` and `Handle` calls where the receiver can be any expression — an `identifier` (`mux`), a `selector_expression` (`s.mux`), or even a package-qualified call (`http.HandleFunc`). This is handled by using `(_)` for the receiver node in the query rather than constraining it to `(identifier)`.

**Primary recommendation:** Write `stdlib-routes.scm` with two patterns (identifier receiver and package-level `http.*` calls), implement `extract_routes()` with Lua-side method/path splitting, reuse `httptest.NewRequest` pattern for test client query.

---

<user_constraints>
## User Constraints

### Locked Decisions

- **D-01:** Pre-1.22 `mux.HandleFunc("/path", handler)` → method `ANY` (single entry)
- **D-02:** Go 1.22+ `mux.HandleFunc("GET /path", handler)` → split on first space; method = left part uppercased, path = right part
- **D-03:** `{$}` end-anchor stripped from paths (already in normalize_path — inherited from Phase 1 stub)
- **D-04:** Negative detection: stdlib activates only when Gin/Echo/Chi/Fiber NOT found in go.mod. Stub already implements this.
- **D-05:** Receiver variable name does NOT matter — capture both `identifier` (`mux`) and `selector_expression` (`s.mux`) receivers
- **D-06:** Source-scan fallback (confirming `net/http` import exists) — see STD-01 in REQUIREMENTS.md. To avoid false positives, add `net/http` source-scan check ONLY when negative exclusion produces a candidate.

### Claude's Discretion

- Exact Tree-sitter query structure — whether to use two patterns (one for `identifier` receiver, one for `selector_expression` receiver) or one broad `(_)` pattern
- Whether to create a `stdlib-groups.scm` (not needed — stdlib has no route grouping/nesting)
- Pre-filter strings for `get_all_routes` file pre-scan
- Whether `http.Handle` (package-level) vs `mux.Handle` (variable-level) needs separate patterns

### Deferred

- `http.NewServeMux()` variable tracking (finding mux creation sites) — not needed; receiver-agnostic query captures all HandleFunc/Handle calls regardless of what mux they're on
- Cross-file mux passing — same D-03 deferral as other frameworks
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| STD-01 | Stdlib project detection via negative exclusion | Already implemented in Phase 1 stub; need source-scan fallback for false-positive reduction |
| STD-02 | Pre-1.22 `mux.HandleFunc("/path", handler)` → ANY | Single-pattern query + Lua-side split logic: no space = ANY |
| STD-03 | Go 1.22+ `mux.HandleFunc("GET /path", handler)` → split method+path | Lua-side: detect space in path string → split on first space |
| STD-04 | `mux.Handle("/path", handler)` extraction | Same query pattern as HandleFunc — capture both method names |
| STD-05 | Receiver-agnostic capture: `mux`, `http`, `s.mux` all work | Use `(_)` for receiver OR two patterns; package-level `http.HandleFunc` has identifier "http" as operand |
| STD-06 | `{$}` end-anchor stripping | Already in normalize_path (Phase 1 stub) — inherited, no additional work |
| STD-07 | CodeLens: `httptest.NewRequest` in `*_test.go` files | Same pattern as Chi/Echo — stdlib-testclient.scm is a copy with `"httptest"` predicate |
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
| `parser.lua` (internal) | — | `parse_file()`, `get_query_public()`, `get_text()` | All file parsing |
| `utils.lua` (internal) | — | `glob_files()`, `file_contains()` | File discovery and pre-filtering |

---

## Architecture Patterns

### Pattern 1: mux.HandleFunc / mux.Handle with simple identifier receiver

**Go AST for `mux.HandleFunc("/path", handler)` and `mux.Handle("/path", handler)`:**
```
call_expression
  function: selector_expression
    operand: identifier         <- receiver ("mux", "router", any name)
    field: field_identifier     <- "HandleFunc" or "Handle"
  arguments: argument_list
    interpreted_string_literal  <- @route_path ("/path" or "GET /path")
    (_)                         <- @func_name (handler)
```

**Tree-sitter query (stdlib-routes.scm Pattern 1):**
```scheme
; mux.HandleFunc("/path", handler) and mux.Handle("/path", handler)
; Receiver can be any identifier (mux, router, srv, etc.)
; @http_method captures "HandleFunc" or "Handle" — Lua decides method from path string
(call_expression
  function: (selector_expression
    operand: (identifier) @_receiver
    field: (field_identifier) @http_method
    (#match? @http_method "^Handle"))
  arguments: (argument_list
    (interpreted_string_literal) @route_path
    .
    (_) @func_name)) @route_def
```

Lua-side dispatching:
- `http_method` is always "HandleFunc" or "Handle" (both treated the same way for method resolution)
- `route_path` text is inspected: if it contains a space (e.g., `"GET /users"`), split on first space to extract method+path; otherwise record as `ANY`

### Pattern 2: http.HandleFunc / http.Handle (package-level, no explicit mux)

**Go AST for `http.HandleFunc("/path", handler)`:**
```
call_expression
  function: selector_expression
    operand: identifier         <- "http" (the package name, not a variable)
    field: field_identifier     <- "HandleFunc" or "Handle"
  arguments: argument_list
    interpreted_string_literal  <- @route_path
    (_)                         <- @func_name
```

This has IDENTICAL structure to Pattern 1 — the `operand` is just an identifier named "http" instead of a mux variable. Pattern 1 already captures this because it uses `(identifier)` for the operand without any name constraint.

**No separate pattern needed** — Pattern 1 captures both `mux.HandleFunc` and `http.HandleFunc`.

### Pattern 3: s.mux.HandleFunc (struct field receiver — selector_expression operand)

**Go AST for `s.mux.HandleFunc("/path", handler)`:**
```
call_expression
  function: selector_expression
    operand: selector_expression  <- "s.mux" (NOT identifier — it's a selector chain)
      operand: identifier         <- "s"
      field: field_identifier     <- "mux"
    field: field_identifier       <- "HandleFunc"
  arguments: argument_list
    interpreted_string_literal    <- @route_path
    (_)                           <- @func_name
```

**Key decision (D-01):** Pattern 1 uses `(identifier)` for operand — this does NOT match `s.mux.HandleFunc` because the operand of the outer selector_expression is a `selector_expression`, not an `identifier`.

**Solution:** Add a second pattern using `(_)` (any node type) for the receiver:

```scheme
; s.mux.HandleFunc("/path", handler) — struct field receiver (selector_expression chain)
; @_receiver2 is internal; receiver identity doesn't matter for route extraction
(call_expression
  function: (selector_expression
    operand: (selector_expression)
    field: (field_identifier) @http_method
    (#match? @http_method "^Handle"))
  arguments: (argument_list
    (interpreted_string_literal) @route_path
    .
    (_) @func_name)) @route_def
```

This specifically matches the case where the receiver is a `selector_expression` (e.g., `s.mux`, `srv.router`, `app.mux`).

### Pattern 4: Method/path splitting (Lua-side, STD-02/STD-03)

```lua
-- path_arg is the raw string from the query (already stripped of quotes)
local method, path
local space_pos = path_arg:find(" ")
if space_pos then
  -- Go 1.22+: "GET /users/123" -> method=GET, path=/users/123
  local verb = path_arg:sub(1, space_pos - 1):upper()
  path = path_arg:sub(space_pos + 1)
  -- Validate: known HTTP methods only; fallback to ANY if not recognized
  local known_methods = { GET=true, POST=true, PUT=true, DELETE=true,
                          PATCH=true, OPTIONS=true, HEAD=true, CONNECT=true, TRACE=true }
  if known_methods[verb] then
    method = verb
  else
    method = "ANY"
    path = path_arg  -- treat whole string as path
  end
else
  -- Pre-1.22: "/users/{id}" -> method=ANY, path=/users/{id}
  method = "ANY"
  path = path_arg
end
```

### Pattern 5: Test client codelens (STD-07)

**Go AST for `httptest.NewRequest("GET", "/path", nil)`:**
```
call_expression
  function: selector_expression
    operand: identifier      <- "httptest"
    field: field_identifier  <- "NewRequest"
  arguments: argument_list
    interpreted_string_literal <- @http_method ("GET")
    interpreted_string_literal <- @test_path ("/path")
    ...
```

Identical to `chi-testclient.scm` and `echo-testclient.scm`. Create `stdlib-testclient.scm` as a copy with `(#eq? @_pkg "httptest")`.

### Pattern 6: STD-01 enhanced detection

Current stub in `stdlib.lua:detect()`:
1. Check go.mod exists
2. Negative exclusion: if gin/echo/chi/fiber present → return false
3. Return true (any Go project without known frameworks)

This may produce false positives for Go projects that aren't HTTP servers. Enhancement (source-scan fallback):
- After passing negative exclusion, scan for `net/http` import in at least one `.go` file OR presence of `HandleFunc`/`Handle` calls
- Use `utils.file_contains(gomod, "net/http")` — note this is the import path in source files, not go.mod (net/http is stdlib so it never appears in go.mod)
- Better: scan for `HandleFunc(` or `.Handle(` in `*.go` source files to confirm the project actually uses HTTP routing

**Revised detect():**
```lua
function M.detect(root)
  local gomod = utils.join(root, "go.mod")
  if not utils.file_exists(gomod) then
    return false
  end
  -- Negative exclusion: if any known framework is present, this is not stdlib
  local known_frameworks = {
    "github.com/gin-gonic/gin",
    "github.com/labstack/echo",
    "github.com/go-chi/chi",
    "github.com/gofiber/fiber",
  }
  for _, fw in ipairs(known_frameworks) do
    if utils.file_contains(gomod, fw) then
      return false
    end
  end
  -- Source-scan fallback: confirm this Go project actually uses net/http routing
  -- Look for HandleFunc( or .Handle( in any .go file (quick text scan, no parsing)
  local go_files = utils.glob_files(root, "**/*.go", { "vendor", "testdata", ".git" })
  for _, f in ipairs(go_files) do
    if utils.file_contains(f, "HandleFunc(") or utils.file_contains(f, ".Handle(") then
      return true
    end
  end
  return false
end
```

---

## Anti-Patterns to Avoid

1. **Using `(identifier)` for receiver in Pattern 3:** `s.mux.HandleFunc` has a `selector_expression` operand. Must have a second pattern or use `(_)` to capture struct field chains.

2. **Treating ALL path strings as 1.22+ method-prefixed:** Many pre-1.22 projects still exist. Check for space first — `"/path"` has no space → `ANY`. `"GET /path"` has space → split.

3. **Matching `(string_literal)` instead of `(interpreted_string_literal)`:** Go uses `interpreted_string_literal` for double-quoted strings. `string_literal` is the raw string literal (backtick). Path strings are always double-quoted.

4. **Creating stdlib-groups.scm:** stdlib has NO route grouping. No groups query is needed.

5. **Attempting to track which mux variable routes are registered on:** The receiver identity doesn't matter for route extraction. All HandleFunc/Handle calls in the project are routes regardless of which mux they're registered on.

6. **func_literal guard:** Same as Gin/Chi/Echo — anonymous handlers `HandleFunc("/path", func(w, r) {...})` produce `func_literal` nodes. Guard: `if node:type() == "func_literal" then func_name_text = "" end`.

---

## Common Pitfalls

### Pitfall 1: `#match?` vs `#eq?` for Handle/HandleFunc
`(#match? @http_method "^Handle")` matches both "Handle" and "HandleFunc" with one predicate. If `#match?` is unavailable, use two `#eq?` predicates. Since Neovim 0.9+, `#match?` is standard.

### Pitfall 2: http.Handle vs mux.Handle — same pattern
`http.Handle("/path", handler)` uses the package name `http` as the operand identifier. Pattern 1 captures this because it doesn't constrain the operand name. No special case needed.

### Pitfall 3: Method split edge cases
The Go 1.22 format is strictly `"METHOD /path"` — the method comes FIRST, then space, then path. However, the path itself can contain spaces only if URL-encoded (not in raw Go strings). Safe to split on the FIRST space only.

For validation: test if the left-side prefix (before space) is a valid HTTP method. Non-HTTP words before a space (e.g., weird path strings) should fall back to ANY.

### Pitfall 4: Double-slash normalization after split
When splitting `"GET /users"` → method=GET, path=`/users`. The path already starts with `/`. But if somehow the prefix ends with `/` and path starts with `/`, the existing `full_path:gsub("//+", "/")` handles it.

### Pitfall 5: Source-scan in detect() is slow for large projects
The source-scan fallback scans all .go files with `utils.file_contains`. On large projects this could be slow. Mitigation: `utils.file_contains` uses `io.open` + pattern matching (not full file read), which is fast for text pattern lookup. The provider cache (keyed on cwd) means this only runs once per project.

---

## Code Examples

### STDLIB_METHODS concept (not a table — Lua-side split logic)
```lua
-- stdlib uses method-embedded-in-path-string (1.22+) or no method (pre-1.22)
-- No lookup table needed — method is determined by splitting the path string
local KNOWN_METHODS = {
  GET=true, POST=true, PUT=true, DELETE=true,
  PATCH=true, OPTIONS=true, HEAD=true, CONNECT=true, TRACE=true
}

local function split_method_path(raw_path)
  local space = raw_path:find(" ")
  if space then
    local verb = raw_path:sub(1, space - 1):upper()
    if KNOWN_METHODS[verb] then
      return verb, raw_path:sub(space + 1)
    end
  end
  return "ANY", raw_path
end
```

### extract_routes single-pass
```lua
function M.extract_routes(filepath)
  local root_node, source = parser.parse_file(filepath, "go")
  if not root_node or not source then return {} end

  local ok, routes_query = pcall(parser.get_query_public, "stdlib-routes", "go")
  if not ok or not routes_query then return {} end

  local routes = {}
  for _, match, _ in routes_query:iter_matches(root_node, source, 0, -1) do
    local route_path_text = nil
    local func_name_text  = nil
    local route_def_node  = nil

    for id, nodes in pairs(match) do
      local name = routes_query.captures[id]
      local node = type(nodes) == "table" and nodes[1] or nodes

      if name == "route_path" then
        route_path_text = strip_quotes(parser.get_text(node, source))
      elseif name == "func_name" then
        if node:type() == "func_literal" then
          func_name_text = ""
        else
          func_name_text = parser.get_text(node, source)
        end
      elseif name == "route_def" then
        route_def_node = node
      end
    end

    if route_path_text and func_name_text ~= nil and route_def_node then
      local method, path = split_method_path(route_path_text)
      path = normalize_path(path)
      path = path:gsub("//+", "/")
      if path == "" then path = "/" end

      local row = route_def_node:range()
      table.insert(routes, {
        method = method,
        path   = path,
        func   = func_name_text,
        file   = filepath,
        line   = row + 1,
      })
    end
  end

  table.sort(routes, function(a, b) return a.line < b.line end)
  return routes
end
```

Note: `@router_obj` and `@http_method` are not consumed in the extraction loop — they don't contribute to the output. Only `@route_path`, `@func_name`, and `@route_def` are used. The `@_receiver` and `@http_method` captures in the query serve as documentation/pattern-matching only.

### get_all_routes pre-filter
```lua
function M.get_all_routes(root)
  local go_files = utils.glob_files(root, "**/*.go", {
    "vendor", "testdata", "node_modules", ".git",
  })

  local all_routes = {}
  for _, f in ipairs(go_files) do
    -- Pre-filter: only parse files likely containing route registrations
    if utils.file_contains(f, "HandleFunc(")
      or utils.file_contains(f, ".Handle(")
    then
      local file_routes = M.extract_routes(f)
      for _, route in ipairs(file_routes) do
        table.insert(all_routes, route)
      end
    end
  end

  return all_routes
end
```

---

## Query File Design

### stdlib-routes.scm — Two patterns

```scheme
;; stdlib route registration patterns for Go net/http
;; Captures HandleFunc and Handle calls on any receiver:
;;   mux.HandleFunc, http.HandleFunc (identifier receiver)
;;   s.mux.HandleFunc (selector_expression receiver)

;; Pattern 1: mux.HandleFunc/Handle with simple identifier receiver
;; Captures: mux.HandleFunc, router.HandleFunc, http.HandleFunc, etc.
(call_expression
  function: (selector_expression
    operand: (identifier) @_receiver
    field: (field_identifier) @http_method
    (#match? @http_method "^Handle"))
  arguments: (argument_list
    (interpreted_string_literal) @route_path
    .
    (_) @func_name)) @route_def

;; Pattern 2: s.mux.HandleFunc/Handle with selector_expression receiver
;; Captures: s.mux.HandleFunc, srv.router.Handle, etc.
(call_expression
  function: (selector_expression
    operand: (selector_expression)
    field: (field_identifier) @http_method
    (#match? @http_method "^Handle"))
  arguments: (argument_list
    (interpreted_string_literal) @route_path
    .
    (_) @func_name)) @route_def
```

### stdlib-testclient.scm — Copy of chi-testclient.scm
```scheme
;; stdlib test client pattern — httptest.NewRequest
(call_expression
  function: (selector_expression
    operand: (identifier) @_pkg
    field: (field_identifier) @_func
    (#eq? @_pkg "httptest")
    (#eq? @_func "NewRequest"))
  arguments: (argument_list
    (interpreted_string_literal) @http_method
    (interpreted_string_literal) @test_path
    .)) @test_call
```

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| File parsing | Custom string parsers | `parser.parse_file(filepath, "go")` | Same as all other Go providers |
| Query loading | Direct file reads | `parser.get_query_public("stdlib-routes", "go")` | Same as Gin |
| Node text | raw `node:text()` | `parser.get_text(node, source)` | Same as Gin |
| File globbing | vim.fn.glob | `utils.glob_files(root, "**/*.go", exclusions)` | Same as Gin |
| Method extraction | Tree-sitter predicates | Lua string split on path arg | TS can't do string substring operations; Lua is the right place |

---

## Validation Architecture

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| STD-01 | Stdlib project detected via negative exclusion + source scan | manual | `:NimbleAPI info` in stdlib project | No test infra |
| STD-02 | Pre-1.22 HandleFunc → ANY | manual | `:NimbleAPI toggle` — method column shows ANY | No test infra |
| STD-03 | 1.22+ method-prefixed HandleFunc → correct method+path | manual | `:NimbleAPI toggle` — method column shows GET/POST | No test infra |
| STD-04 | Handle extraction | manual | `:NimbleAPI toggle` — Handle calls appear | No test infra |
| STD-05 | Receiver-agnostic: mux/http/s.mux all captured | manual | Test project with all three forms | No test infra |
| STD-06 | {$} stripping | manual | Path `/users/{$}` shows as `/users/` | Already in normalize_path |
| STD-07 | httptest.NewRequest codelens | manual | Open test file, see codelens | No test infra |

Testing is manual via `:NimbleAPI toggle` and `:NimbleAPI info` in a real net/http project.

---

## Sources

### Primary (HIGH confidence)
- `tree-sitter-go grammar.js` — verified `selector_expression` fields (operand/field), `call_expression` fields (function/arguments), `interpreted_string_literal` type
- `lua/nimbleapi/providers/gin.lua` — established pattern for all infrastructure usage (iter_matches, func_literal guard, strip_quotes)
- `lua/nimbleapi/providers/chi.lua` — confirmed selector_expression operand field access pattern
- `queries/go/chi-testclient.scm` — direct copy for stdlib-testclient.scm (only change: `@_pkg` constraint to "httptest" — same)
- Go 1.22 release notes — confirmed `"METHOD /path"` string format for enhanced ServeMux routing

### Secondary (MEDIUM confidence)
- net/http ServeMux documentation — confirmed `Handle` and `HandleFunc` as the two registration methods
- `stdlib.lua` Phase 1 stub — negative exclusion already implemented; source-scan enhancement needed

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — reuses Gin/Chi infrastructure unchanged
- stdlib API: HIGH — net/http has only two registration methods (Handle, HandleFunc); API is stable since Go 1.0
- Dual-era splitting: HIGH — Go 1.22 format is documented and simple: first space separates method from path
- Selector_expression chain (s.mux.HandleFunc): HIGH — confirmed from grammar.js that outer operand is selector_expression when receiver is a struct field
- #match? predicate: MEDIUM — standard but fallback documented

**Research date:** 2026-03-26
**Valid until:** 2028-03-26 (net/http API is stable; tree-sitter-go grammar is stable)
