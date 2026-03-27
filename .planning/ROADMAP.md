# Roadmap: nimbleapi.nvim — Go Framework Support

## Overview

This milestone adds Go web framework support to nimbleapi.nvim. Starting from shared
infrastructure (Tree-sitter Go grammar integration, path param normalization, file
watcher extension), the work proceeds framework-by-framework in ascending order of
implementation complexity: Gin establishes the call_expression query pattern that all
other frameworks share; Echo follows the same shape with a different group model; Chi
introduces the unique closure-based nesting that requires AST parent-chain walking;
and stdlib caps the work with negative-exclusion detection and dual-era pattern support.

---

## Milestone v1.1: Express.js Support

This milestone adds Express.js route extraction for JavaScript and TypeScript. A single
Express provider handles both `.js` and `.ts` files, backed by duplicate Tree-sitter query
files under `queries/javascript/` and `queries/typescript/`. Cross-file router composition
via `app.use()` and `require`/`import` follows the FastAPI tree-walk pattern, implemented
with a JS-specific import resolver. Phases 6–9 extend the existing roadmap.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [ ] **Phase 1: Go Foundation** - Shared Go infrastructure: Tree-sitter grammar check, provider registration, path param normalization, file watcher extension
- [ ] **Phase 2: Gin Provider** - Full Gin route extraction with group nesting and codelens
- [x] **Phase 3: Echo Provider** - Full Echo route extraction with group nesting and codelens (completed 2026-03-26)
- [x] **Phase 4: Chi Provider** - Full Chi route extraction with closure-based nesting and codelens (completed 2026-03-26)
- [x] **Phase 5: stdlib Provider** - net/http stdlib route extraction with dual-era pattern support and codelens (completed 2026-03-27)
- [ ] **Phase 6: Express Infrastructure** - JS/TS grammar prerequisites, package.json detection, provider registration, ROOT_MARKERS update
- [ ] **Phase 7: Route Extraction (Single-File)** - app.METHOD/router.METHOD extraction in JS and TS, path normalization, middleware exclusion, app.route() chaining, auto-refresh
- [ ] **Phase 8: Router Composition** - JS import resolver, app.use() prefix mounting, cross-file require/import resolution, TypeScript export patterns, cycle guard
- [ ] **Phase 9: CodeLens** - Supertest and node:http codelens annotations in JS/TS test files

## Phase Details

### Phase 1: Go Foundation
**Goal**: The shared Go infrastructure is in place so that all Go providers can build on a verified grammar, normalized path params, and watched files
**Depends on**: Nothing (first phase)
**Requirements**: INFRA-01, INFRA-02, INFRA-03, INFRA-04
**Success Criteria** (what must be TRUE):
  1. Running `:NimbleAPI info` in a Go project surfaces a clear error message when the Go Tree-sitter grammar is not installed, rather than a cryptic Lua traceback
  2. Running `:NimbleAPI info` in a Go project when the grammar is installed confirms the Go provider is registered and detection ran
  3. Saving any `.go` file in a watched project triggers an auto-refresh (routes update without a manual `:NimbleAPI refresh`)
  4. Path strings like `:id`, `*wildcard`, and `{id:[0-9]+}` are all displayed as `{id}` / `{wildcard}` in the route explorer, never in their raw framework-specific form
**Plans**: 2 plans
Plans:
- [x] 01-01-PLAN.md — Create four Go provider stubs (gin, echo, chi, stdlib) with prerequisites check, detection, and path normalization
- [ ] 01-02-PLAN.md — Register Go providers in providers_to_load, add go.mod to ROOT_MARKERS, extend BufWritePost autocmd to *.go

### Phase 2: Gin Provider
**Goal**: A developer working in a Gin project can see all routes in the explorer and picker, with fully-qualified group-prefixed paths, and test calls in `*_test.go` files are annotated with codelens links
**Depends on**: Phase 1
**Requirements**: GIN-01, GIN-02, GIN-03, GIN-04, GIN-05, GIN-06, GIN-07
**Success Criteria** (what must be TRUE):
  1. Running `:NimbleAPI toggle` in a Gin project opens the explorer listing routes grouped by file, showing fully-qualified paths (e.g., `/api/v1/users/:id` not just `/:id`)
  2. Routes registered via `router.GET/POST/PUT/DELETE/PATCH/HEAD/OPTIONS`, `router.Handle`, and `router.Any` all appear in the route list with correct methods
  3. Nested groups (`v2 := v1.Group("/admin")`) resolve to fully-concatenated paths — no unresolved prefixes appear in the display
  4. Opening a `*_test.go` file with `http.NewRequest` calls shows virtual text annotations linking each test call to its route handler
**Plans**: 2 plans
Plans:
- [x] 02-01-PLAN.md — Tree-sitter queries and route extraction with two-pass group prefix resolution
- [x] 02-02-PLAN.md — Test client codelens and end-to-end verification
**UI hint**: yes

### Phase 3: Echo Provider
**Goal**: A developer working in an Echo project can see all routes in the explorer and picker, with fully-qualified group-prefixed paths, and test calls in `*_test.go` files are annotated with codelens links
**Depends on**: Phase 1
**Requirements**: ECHO-01, ECHO-02, ECHO-03, ECHO-04, ECHO-05, ECHO-06, ECHO-07
**Success Criteria** (what must be TRUE):
  1. Running `:NimbleAPI toggle` in an Echo project opens the explorer listing routes with fully-qualified paths — nested groups like `v1 := api.Group("/v1")` produce `/api/v1/...` paths
  2. Routes registered via `e.GET/POST/PUT/DELETE/PATCH/HEAD/OPTIONS/CONNECT/TRACE`, `e.Add`, and `e.Any` all appear with correct methods
  3. `:NimbleAPI pick` launches the fuzzy picker and shows all Echo routes searchable by path or handler name
  4. Opening a `*_test.go` file with `httptest.NewRequest` calls shows codelens annotations linking test calls to matching handlers
**Plans**: 2 plans
Plans:
- [x] 03-01-PLAN.md — Tree-sitter queries and route extraction with two-pass group prefix resolution
- [x] 03-02-PLAN.md — Test client codelens (httptest.NewRequest) and end-to-end verification
**UI hint**: yes

### Phase 4: Chi Provider
**Goal**: A developer working in a Chi project can see all routes in the explorer and picker, with closure-nested prefixes fully resolved, mount points visible, and test calls annotated
**Depends on**: Phase 1
**Requirements**: CHI-01, CHI-02, CHI-03, CHI-04, CHI-05, CHI-06, CHI-07, CHI-08
**Success Criteria** (what must be TRUE):
  1. Running `:NimbleAPI toggle` in a Chi project opens the explorer with fully-resolved paths — routes inside `r.Route("/users", func(r chi.Router) { r.Route("/{id}", ...) })` closures show `/users/{id}/...` not just `/{id}/...`
  2. Routes registered via `r.Get/Post/Put/Delete/Patch/Options/Head/Connect/Trace`, `r.Handle`, `r.HandleFunc`, `r.Method`, and `r.MethodFunc` all appear with correct methods
  3. `r.Mount("/prefix", handler)` entries appear in the explorer as mount points (method `MOUNT`) — they are not silently dropped
  4. Routes inside `r.Group(func(r chi.Router) {...})` closures appear at the same path level as their parent — `r.Group` does not prepend any prefix
**Plans**: 2 plans
Plans:
- [x] 04-01-PLAN.md — Tree-sitter query and route extraction with parent-chain closure prefix resolution
- [x] 04-02-PLAN.md — Test client codelens (httptest.NewRequest) and end-to-end verification
**UI hint**: yes

### Phase 5: stdlib Provider
**Goal**: A developer working in a net/http stdlib project can see all routes in the explorer and picker, with pre-1.22 and Go 1.22+ patterns both extracted correctly, and test calls annotated
**Depends on**: Phase 1
**Requirements**: STD-01, STD-02, STD-03, STD-04, STD-05, STD-06, STD-07
**Success Criteria** (what must be TRUE):
  1. Running `:NimbleAPI toggle` in a net/http project (with no framework imports in `go.mod`) activates the stdlib provider and shows routes in the explorer
  2. Pre-1.22 `mux.HandleFunc("/path", handler)` calls appear with method `ANY`; Go 1.22+ `mux.HandleFunc("GET /path", handler)` calls appear with method `GET` and path `/path`
  3. Routes registered on `http.HandleFunc`, `mux.HandleFunc`, and `s.mux.HandleFunc` (struct field receivers) are all captured — the receiver variable name does not matter
  4. Paths containing `{$}` end-anchors are displayed without the suffix (e.g., `/users/` not `/users/{$}`)
  5. Opening a `*_test.go` file with `httptest.NewRequest` calls shows codelens annotations linking test calls to matching route handlers
**Plans**: TBD
**UI hint**: yes

### Phase 6: Express Infrastructure
**Goal**: The Express provider is wired into the plugin and correctly detects Express projects, reports missing grammar prerequisites clearly, and appears in `:NimbleAPI info` — with no routes extracted yet
**Depends on**: Phase 5
**Requirements**: EINF-01, EINF-02, EINF-03, EINF-04
**Success Criteria** (what must be TRUE):
  1. Running `:NimbleAPI info` in a project without the JavaScript or TypeScript Tree-sitter grammar installed shows a readable error with install instructions (`:TSInstall javascript` / `:TSInstall typescript`), not a Lua traceback
  2. Running `:NimbleAPI info` in an Express project (with `"express"` in `dependencies`) confirms the Express provider was detected and activated
  3. Running `:NimbleAPI info` in a NestJS or devDependencies-only project does not falsely activate the Express provider
  4. Opening any `.js` or `.ts` file in a detected Express project triggers the plugin's file watcher (auto-refresh fires on save)
**Plans**: 2 plans
Plans:
- [x] 06-01-PLAN.md — Express provider module (dual JS/TS), multi-provider registry, package.json detection, ROOT_MARKERS
- [ ] 06-02-PLAN.md — File watcher JS/TS extension, BufEnter Go bug fix, multi-provider cache, end-to-end verification

### Phase 7: Route Extraction (Single-File)
**Goal**: A developer working in an Express project can see all routes from a single file — including chained routes — in the explorer and picker, with normalized path params and no middleware noise
**Depends on**: Phase 6
**Requirements**: EXPR-01, EXPR-02, EXPR-03, EXPR-04, EXPR-05, ETS-01, ETS-02, EWAT-01
**Success Criteria** (what must be TRUE):
  1. Running `:NimbleAPI toggle` in a single-file Express project shows all `app.get/post/put/delete/patch/options/head` and `router.METHOD` routes grouped by file with jump-to-definition
  2. `app.all('/path', handler)` routes appear in the explorer with method `ANY`
  3. `app.route('/users').get(listHandler).post(createHandler)` produces two separate route entries (`GET /users` and `POST /users`) — not a single entry or a missing entry
  4. Path parameters are displayed as `{param}` and `{wildcard}` in the explorer — `:userId` and `*rest` never appear in raw form
  5. `app.use(fn)` middleware calls without an HTTP method do not appear in the route list
  6. The same extraction works identically in `.ts` Express files as in `.js` files — TypeScript type annotations do not corrupt path or method capture
**Plans**: 2 plans
Plans:
- [x] 07-01-PLAN.md — Tree-sitter query files + extract_routes and get_all_routes implementation for JS and TS
- [ ] 07-02-PLAN.md — Test fixtures and human E2E verification checkpoint
**UI hint**: yes

### Phase 8: Router Composition
**Goal**: A developer working in a multi-file Express project sees all routes with fully-qualified prefix paths — routes defined in sub-router files appear with the prefix from their `app.use()` mount, and circular require chains do not hang Neovim
**Depends on**: Phase 7
**Requirements**: ECOMP-01, ECOMP-02, ECOMP-03, ECOMP-04, ECOMP-05, ETS-03
**Success Criteria** (what must be TRUE):
  1. Routes defined in a file like `routes/users.js` and mounted with `app.use('/users', usersRouter)` appear in the explorer as `/users/...` paths, not bare `/...` paths
  2. CJS projects using `const usersRouter = require('./routes/users')` resolve the sub-router file and include its routes with prefix applied
  3. ESM projects using `import usersRouter from './routes/users'` resolve the sub-router file and include its routes with prefix applied
  4. A project with a circular `require()` chain (file A requires file B which requires file A) does not cause Neovim to hang — extraction completes and returns whatever routes were resolved before the cycle
  5. TypeScript files using `export default router` and `export { router }` are resolved correctly as sub-routers in cross-file composition
**Plans**: TBD
**UI hint**: yes

### Phase 9: CodeLens
**Goal**: A developer writing Express tests sees virtual text annotations linking each supertest or node:http call to its matching route handler
**Depends on**: Phase 7
**Requirements**: ECLEN-01, ECLEN-02
**Success Criteria** (what must be TRUE):
  1. Opening a `.test.js`, `.test.ts`, `.spec.js`, or `.spec.ts` file with `request(app).get('/users')` or `supertest(app).post('/items')` calls shows codelens virtual text on each test call line linking to the matching route handler
  2. Codelens annotations do not appear on non-test files — `.js` and `.ts` source files without test name patterns are unaffected
**Plans**: TBD
**UI hint**: yes

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → 4 → 5 → 6 → 7 → 8 → 9

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Go Foundation | 1/2 | In Progress|  |
| 2. Gin Provider | 1/2 | In Progress|  |
| 3. Echo Provider | 2/2 | Complete   | 2026-03-26 |
| 4. Chi Provider | 2/2 | Complete   | 2026-03-26 |
| 5. stdlib Provider | 2/2 | Complete   | 2026-03-27 |
| 6. Express Infrastructure | 1/2 | In Progress|  |
| 7. Route Extraction (Single-File) | 1/2 | In Progress|  |
| 8. Router Composition | 0/TBD | Not started | - |
| 9. CodeLens | 0/TBD | Not started | - |
