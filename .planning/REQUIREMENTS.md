# Requirements: nimbleapi.nvim — Express.js Support

**Defined:** 2026-03-27
**Core Value:** A Node.js developer can open any Express.js project (JS or TS) and instantly see, search, and jump to every route — with full router composition and prefix nesting resolved.

## v1 Requirements (Milestone v1.0 — Go Framework Support)

### Infrastructure

- [x] **INFRA-01**: Go Tree-sitter grammar prerequisite check — `check_prerequisites()` verifies `vim.treesitter.language.require("go")` succeeds and surfaces a clear error via `:NimbleAPI info` if not
- [x] **INFRA-02**: Go provider registered in `providers/init.lua` registry and `providers_to_load` list in `init.lua`
- [x] **INFRA-03**: File watcher auto-refresh extended to watch `*.go` files (add to autocmd patterns in `plugin/nimbleapi.lua`)
- [x] **INFRA-04**: Path parameter normalization for Go styles: `:param` → `{param}`, `*wildcard` → `{wildcard}`, regex variants `{id:[0-9]+}` → `{id}` — applied at extraction time in all Go providers

### Gin Provider

- [x] **GIN-01**: Gin project detection via `go.mod` containing `github.com/gin-gonic/gin`
- [x] **GIN-02**: Route extraction for all HTTP method shortcuts: `router.GET`, `POST`, `PUT`, `DELETE`, `PATCH`, `OPTIONS`, `HEAD` — captures router variable, method, path string, handler name
- [x] **GIN-03**: Route extraction for `router.Handle("METHOD", "/path", handler)` — HTTP method from first string argument
- [x] **GIN-04**: Route extraction for `router.Any("/path", handler)` — recorded as method `ANY`
- [x] **GIN-05**: RouterGroup detection: `v1 := router.Group("/v1")` short variable declarations tracked within function scope
- [x] **GIN-06**: Full recursive prefix resolution: nested groups (`v2 := v1.Group("/admin")`) fully concatenated into final route paths
- [x] **GIN-07**: CodeLens for Gin test files: `http.NewRequest("METHOD", "/path", ...)` calls in `*_test.go` files annotated with links to matching route handlers

### Echo Provider

- [ ] **ECHO-01**: Echo project detection via `go.mod` containing `github.com/labstack/echo`
- [ ] **ECHO-02**: Route extraction for HTTP method shortcuts: `e.GET`, `POST`, `PUT`, `DELETE`, `PATCH`, `HEAD`, `OPTIONS`, `CONNECT`, `TRACE` — captures receiver variable, method, path string, handler name
- [ ] **ECHO-03**: Route extraction for `e.Add("METHOD", "/path", handler)` — HTTP method from first string argument
- [ ] **ECHO-04**: Route extraction for `e.Any("/path", handler)` — recorded as method `ANY`
- [ ] **ECHO-05**: Group detection: `g := e.Group("/prefix")` short variable declarations tracked within function scope
- [ ] **ECHO-06**: Full recursive group prefix resolution for nested `g.Group("/sub")` chains
- [ ] **ECHO-07**: CodeLens for Echo test files: `httptest.NewRequest` / `http.NewRequest` calls in `*_test.go` files annotated with links to matching handlers

### Chi Provider

- [ ] **CHI-01**: Chi project detection via `go.mod` containing `github.com/go-chi/chi`
- [ ] **CHI-02**: Route extraction for HTTP method shortcuts: `r.Get`, `Post`, `Put`, `Delete`, `Patch`, `Options`, `Head`, `Connect`, `Trace`
- [ ] **CHI-03**: Route extraction for `r.Handle` and `r.HandleFunc` — recorded as method `ANY`
- [ ] **CHI-04**: Route extraction for `r.Method("METHOD", "/path", handler)` and `r.MethodFunc` — HTTP method from first string argument
- [ ] **CHI-05**: `r.Route("/prefix", func(r chi.Router) { ... })` closure nesting resolved by walking AST parent chain to concatenate all enclosing route prefixes
- [ ] **CHI-06**: `r.Mount("/prefix", handler)` detected and recorded as a mount point (method `MOUNT`, path = prefix + `/*`)
- [ ] **CHI-07**: `r.Group(func(r chi.Router) { ... })` correctly identified as middleware-only (no prefix contribution — do not prepend any path)
- [ ] **CHI-08**: CodeLens for Chi test files: `httptest.NewRequest("METHOD", "/path", ...)` calls in `*_test.go` annotated with links to matching handlers

### net/http Stdlib Provider

- [ ] **STD-01**: Stdlib project detection via negative exclusion — go.mod exists + no known framework imports + `net/http` import present + `HandleFunc`/`Handle` calls found in source
- [ ] **STD-02**: Route extraction for `mux.HandleFunc("/path", handler)` and `http.HandleFunc("/path", handler)` (pre-1.22) — method recorded as `ANY`
- [ ] **STD-03**: Route extraction for Go 1.22+ method-prefixed patterns: `mux.HandleFunc("GET /path", handler)` — method split from path string on first space
- [ ] **STD-04**: Route extraction for `mux.Handle("/path", handler)` patterns
- [ ] **STD-05**: Tree-sitter query anchored on field name (`HandleFunc`, `Handle`) rather than receiver variable name — handles `mux.HandleFunc`, `http.HandleFunc`, `s.mux.HandleFunc`, etc.
- [ ] **STD-06**: `{$}` end-anchor suffix stripped from displayed paths
- [ ] **STD-07**: CodeLens for stdlib test files: `httptest.NewRequest("METHOD", "/path", ...)` calls in `*_test.go` annotated with links to matching handlers

---

## v1.1 Requirements (Milestone v1.1 — Express.js Support)

### Express Infrastructure

- [x] **EINF-01**: User can see a clear error via `:NimbleAPI info` when the JavaScript or TypeScript Tree-sitter grammar is missing — `check_prerequisites()` verifies both grammars and surfaces actionable guidance, not a cryptic traceback
- [x] **EINF-02**: Express project detection via `package.json` with `"express"` in `dependencies` (JSON-parsed, not string-searched) — excludes `devDependencies`-only installs and NestJS monorepo false positives
- [x] **EINF-03**: `package.json` added to `ROOT_MARKERS` in `providers/init.lua` for project root detection
- [x] **EINF-04**: Express provider registered in `providers/init.lua` registry and `providers_to_load` list in `init.lua`

### Express Route Extraction (Single-File)

- [x] **EXPR-01**: User can see all `app.METHOD(path, handler)` and `router.METHOD(path, handler)` routes (get/post/put/delete/patch/options/head) in the explorer, grouped by file with jump-to-definition
- [x] **EXPR-02**: User can see `app.all(path, handler)` routes — recorded as method `ANY`
- [x] **EXPR-03**: User can see `app.route("/path").get(handler).post(handler)` chained routes — path sourced from outer `route()` call, one entry per HTTP method in the chain
- [x] **EXPR-04**: Path parameters normalized at extraction time: `:param` → `{param}`, `*wildcard` → `{wildcard}`
- [x] **EXPR-05**: Middleware `app.use(fn)` calls without an HTTP method are excluded from the route list — only entries with an explicit HTTP verb appear

### Router Composition (Cross-File)

- [ ] **ECOMP-01**: `express.Router()` variable assignments tracked in-file — `const router = express.Router()` recognized as a router object
- [ ] **ECOMP-02**: `app.use("/prefix", router)` mounts resolve all routes from the mounted router to fully-qualified paths (prefix + route path) in the explorer
- [ ] **ECOMP-03**: Cross-file CJS `require()` resolution — `const usersRouter = require("./routes/users")` followed to filesystem path, routes extracted and prefix applied
- [ ] **ECOMP-04**: Cross-file ESM `import` resolution — `import usersRouter from "./routes/users"` followed to filesystem path, routes extracted and prefix applied
- [ ] **ECOMP-05**: Circular `require()`/`import` cycle guard — `visited_files` set prevents infinite loops on circular dependency chains

### TypeScript Support

- [x] **ETS-01**: `.ts` files parsed with `"typescript"` Tree-sitter language; `.js` files parsed with `"javascript"` — same query content applied to both
- [x] **ETS-02**: Query files present as real copies in both `queries/javascript/` and `queries/typescript/` directories (not symlinks — no symlink precedent in this plugin)
- [ ] **ETS-03**: `export default router` and named `export { router }` recognized in cross-file resolution — TypeScript ESM export patterns handled alongside CJS `module.exports`

### CodeLens

- [ ] **ECLEN-01**: `extract_test_calls_buf()` detects supertest patterns in test files: `request(app).METHOD("/path")` and `supertest(app).METHOD("/path")`
- [ ] **ECLEN-02**: CodeLens virtual text annotations displayed in `.test.js`, `.test.ts`, `.spec.js`, `.spec.ts` files — links each test HTTP call to its matching route handler

### Auto-Refresh

- [x] **EWAT-01**: Saving any `.js` or `.ts` file in a watched Express project triggers auto-refresh — `*.js` and `*.ts` added to `BufWritePost` autocmd patterns in `plugin/nimbleapi.lua`

---

## v2 Requirements

### Cross-file Resolution (Go)

- **CROSS-01**: Follow router variables passed between Go functions in the same package (e.g., `setupRoutes(r *gin.Engine)`) — same-package cross-function tracking
- **CROSS-02**: Cross-package router variable tracking (Gin/Echo routers defined in one package and passed to another)

### Additional Frameworks

- **FRAME-01**: Fiber framework support (`github.com/gofiber/fiber`)
- **FRAME-02**: gorilla/mux support (`github.com/gorilla/mux`)
- **FRAME-03**: Fastify support (Node.js)
- **FRAME-04**: NestJS support (Node.js TypeScript)

---

## Out of Scope

| Feature | Reason |
|---------|--------|
| Fiber, gorilla/mux, Beego | Not requested for this milestone — deferred to v2 |
| Cross-package router variable tracking (Go) | Too complex for v1; same-file + same-function group resolution is sufficient |
| GraphQL endpoint detection | REST focus only |
| Fastify, Koa, Hapi, NestJS | Not requested for this milestone — deferred to v2 |
| Circular dependency resolution (advanced) | `visited_files` guard covers practical cases; deep circular analysis deferred |
| TSX/JSX route files | Not a common Express pattern — deferred |
| Express 5 optional param syntax (`:id?` → `{/:id}`) | Version detection complexity deferred; v4 patterns cover the majority |

---

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| INFRA-01 | Phase 1 | Complete |
| INFRA-02 | Phase 1 | Complete |
| INFRA-03 | Phase 1 | Complete |
| INFRA-04 | Phase 1 | Complete |
| GIN-01 | Phase 2 | Complete |
| GIN-02 | Phase 2 | Complete |
| GIN-03 | Phase 2 | Complete |
| GIN-04 | Phase 2 | Complete |
| GIN-05 | Phase 2 | Complete |
| GIN-06 | Phase 2 | Complete |
| GIN-07 | Phase 2 | Complete |
| ECHO-01 | Phase 3 | Pending |
| ECHO-02 | Phase 3 | Pending |
| ECHO-03 | Phase 3 | Pending |
| ECHO-04 | Phase 3 | Pending |
| ECHO-05 | Phase 3 | Pending |
| ECHO-06 | Phase 3 | Pending |
| ECHO-07 | Phase 3 | Pending |
| CHI-01 | Phase 4 | Pending |
| CHI-02 | Phase 4 | Pending |
| CHI-03 | Phase 4 | Pending |
| CHI-04 | Phase 4 | Pending |
| CHI-05 | Phase 4 | Pending |
| CHI-06 | Phase 4 | Pending |
| CHI-07 | Phase 4 | Pending |
| CHI-08 | Phase 4 | Pending |
| STD-01 | Phase 5 | Pending |
| STD-02 | Phase 5 | Pending |
| STD-03 | Phase 5 | Pending |
| STD-04 | Phase 5 | Pending |
| STD-05 | Phase 5 | Pending |
| STD-06 | Phase 5 | Pending |
| STD-07 | Phase 5 | Pending |
| EINF-01 | Phase 6 | Complete |
| EINF-02 | Phase 6 | Complete |
| EINF-03 | Phase 6 | Complete |
| EINF-04 | Phase 6 | Complete |
| EXPR-01 | Phase 7 | Complete |
| EXPR-02 | Phase 7 | Complete |
| EXPR-03 | Phase 7 | Complete |
| EXPR-04 | Phase 7 | Complete |
| EXPR-05 | Phase 7 | Complete |
| ETS-01 | Phase 7 | Complete |
| ETS-02 | Phase 7 | Complete |
| EWAT-01 | Phase 7 | Complete |
| ECOMP-01 | Phase 8 | Pending |
| ECOMP-02 | Phase 8 | Pending |
| ECOMP-03 | Phase 8 | Pending |
| ECOMP-04 | Phase 8 | Pending |
| ECOMP-05 | Phase 8 | Pending |
| ETS-03 | Phase 8 | Pending |
| ECLEN-01 | Phase 9 | Pending |
| ECLEN-02 | Phase 9 | Pending |

**Coverage:**
- v1.0 requirements: 33 total, all mapped
- v1.1 requirements: 20 total, all mapped (Phases 6–9)
- Unmapped: 0

---
*Requirements defined: 2026-03-27*
*Last updated: 2026-03-27 after v1.1 roadmap creation (Phases 6–9)*
