# nimbleapi.nvim — Express.js Support

## What This Is

nimbleapi.nvim is a Neovim plugin for exploring and navigating API route definitions. It supports FastAPI (Python), Spring/Spring Boot (Java), and Go (Gin, Echo, Chi, net/http stdlib). This milestone adds Express.js support for JavaScript and TypeScript — giving Node.js developers the same route explorer, fuzzy picker, codelens, and auto-refresh experience.

## Core Value

A Node.js developer can open any Express.js project (JS or TS) and instantly see, search, and jump to every route — with full router composition and prefix nesting resolved.

## Current Milestone: v1.1 Express.js Support

**Goal:** Add Express.js route extraction for JavaScript and TypeScript, including router composition via app.use() and express.Router(), with codelens for supertest/node:http test clients.

**Target features:**
- Express route extraction: app.get/post/put/delete/patch/all, router.METHOD
- Router composition: express.Router() instances with prefix mounting (app.use)
- Nested router support: follow router variable assignments + app.use() mounts
- CodeLens for test clients: supertest/node:http request patterns in test files
- Auto-refresh for .js/.ts files
- TypeScript support: same patterns work in .ts Express files

## Requirements

### Validated

- ✓ Route Explorer sidebar listing routes grouped by source file with jump-to-definition — existing
- ✓ Fuzzy Picker via Telescope, Snacks.nvim, or vim.ui.select — existing
- ✓ CodeLens virtual text on test client calls linking to route handlers — existing
- ✓ Auto-refresh debounced file watcher on save — existing
- ✓ FastAPI (Python) provider with cross-file router resolution — existing
- ✓ Spring/Spring Boot (Java) provider with annotation-based extraction — existing
- ✓ Go provider infrastructure: Tree-sitter Go parser, provider interface, go.mod detection — existing
- ✓ Gin provider with group nesting and codelens — existing
- ✓ Echo provider with group nesting and codelens — existing
- ✓ Chi provider with closure-based nesting and codelens — existing
- ✓ net/http stdlib provider with dual-era pattern support and codelens — existing

### Active

- [ ] Express.js provider infrastructure: Tree-sitter JavaScript/TypeScript parser integration, provider interface, detection via package.json express dependency
- [ ] Express route extraction: app.get/post/put/delete/patch/all, router.METHOD, app.route() chaining
- [ ] Router composition: express.Router() instances mounted via app.use("/prefix", router)
- [ ] Nested router resolution: follow router variable assignments across require/import to resolve full paths
- [ ] TypeScript support: same extraction patterns applied to .ts files (TypeScript Tree-sitter grammar)
- [ ] CodeLens for test clients: supertest and node:http request patterns in test files
- [ ] Auto-refresh for .js/.ts files: extend file watcher patterns

### Out of Scope

- Fiber, gorilla/mux, Beego, and other Go frameworks — not requested for this milestone
- Cross-package router variable tracking for Go — routes defined in a separate package and passed back; same-file/same-package resolution is sufficient
- GraphQL endpoint detection — REST focus only
- Fastify, Koa, Hapi, NestJS — not requested for this milestone
- Cross-file router tracking beyond require/import resolution — circular dependency resolution is out of scope

## Context

The plugin uses a provider pattern where each framework implements a standard interface. Tree-sitter is already integrated for Python (fastapi), Java (spring), and Go. The JavaScript and TypeScript Tree-sitter grammars will need to be available in the user's Neovim install via nvim-treesitter.

Express router composition is import-based (require/import), similar to FastAPI's include_router pattern. Route variables are assigned (e.g., `const router = express.Router()`) then mounted (e.g., `app.use('/prefix', router)`). The resolver needs to track these assignments and follow them across file boundaries via import resolution.

Path parameter normalization: Express uses `:param` style — must normalize to `{param}` at extraction time.

Existing codebase: `lua/nimbleapi/providers/`, `queries/python/`, `queries/java/`, `queries/go/`, `lua/nimbleapi/parser.lua`, `lua/nimbleapi/import_resolver.lua`.

## Constraints

- **Language**: Lua 5.1 (LuaJIT) — no Lua 5.2+ syntax
- **Tree-sitter**: JavaScript and TypeScript parsers must be available via nvim-treesitter; query files follow `queries/javascript/<framework>-routes.scm` naming
- **Provider interface**: Must implement full `RouteProvider` interface without breaking existing FastAPI/Spring/Go detection
- **Path params**: Normalize Express `:param` style to `{param}` at extraction time
- **No build step**: Pure Lua plugin — no compilation or build tooling

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| All 4 frameworks in one milestone (Go) | User preference; shared Go provider infrastructure amortizes setup cost | — Validated |
| Variable-based group tracking (same-file, Go) | Cross-package tracking is complex and rarely needed in practice | — Validated |
| `:param` → `{param}` normalization | Consistent with existing provider convention for path parameters | — Validated |
| JS + TS in one milestone | TypeScript Express is very common; shared query patterns amortize setup cost | — Pending |

---

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd:transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd:complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-03-27 — Milestone v1.1 Express.js Support started*
