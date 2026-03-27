---
phase: 2
slug: gin-provider
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-26
---

# Phase 2 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | plenary.nvim (not yet installed — Wave 0 installs) |
| **Config file** | None — Wave 0 creates test structure |
| **Quick run command** | `:PlenaryBustedDirectory tests/` |
| **Full suite command** | `:PlenaryBustedDirectory tests/` |
| **Estimated runtime** | ~5 seconds (once infrastructure exists) |

---

## Sampling Rate

- **After every task commit:** Run `:NimbleAPI info` to verify provider loads without error
- **After every plan wave:** Run `:NimbleAPI toggle` in a Gin project to verify route display
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** ~30 seconds (manual verification in Neovim)

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 02-W0-01 | 01 | 0 | GIN-02..07 | unit | `:PlenaryBustedDirectory tests/` | ❌ W0 | ⬜ pending |
| 02-01-01 | 01 | 1 | GIN-01 | unit | `:PlenaryBustedDirectory tests/providers/` | ❌ W0 | ⬜ pending |
| 02-01-02 | 01 | 1 | GIN-02 | unit | `:PlenaryBustedDirectory tests/providers/` | ❌ W0 | ⬜ pending |
| 02-01-03 | 01 | 1 | GIN-03 | unit | `:PlenaryBustedDirectory tests/providers/` | ❌ W0 | ⬜ pending |
| 02-01-04 | 01 | 1 | GIN-04 | unit | `:PlenaryBustedDirectory tests/providers/` | ❌ W0 | ⬜ pending |
| 02-01-05 | 01 | 1 | GIN-05 | unit | `:PlenaryBustedDirectory tests/providers/` | ❌ W0 | ⬜ pending |
| 02-01-06 | 01 | 1 | GIN-06 | unit | `:PlenaryBustedDirectory tests/providers/` | ❌ W0 | ⬜ pending |
| 02-02-01 | 02 | 2 | GIN-07 | unit | `:PlenaryBustedDirectory tests/providers/` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `tests/providers/test_gin.lua` — unit tests for `extract_routes()`, group resolution (GIN-02 through GIN-06)
- [ ] `tests/queries/test_gin_queries.lua` — query match tests for each `.scm` pattern
- [ ] plenary.nvim dev dependency — add to documentation/setup instructions

*Note: Full test infrastructure is absent project-wide (per CLAUDE.md: "No automated test suite exists yet"). Wave 0 creates the initial structure.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Explorer shows fully-prefixed routes | GIN-06 | Requires live Neovim + real Gin project | Open a Gin project, run `:NimbleAPI toggle`, verify paths like `/api/v1/users/:id` appear (not just `/:id`) |
| Codelens appears on `*_test.go` files | GIN-07 | Requires live Neovim buffer rendering | Open a `*_test.go` file with `http.NewRequest` calls, verify virtual text annotations appear |
| All route methods shown | GIN-02..04 | Requires live project | Verify GET/POST/PUT/DELETE/PATCH/HEAD/OPTIONS/Handle/Any all appear in explorer |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
