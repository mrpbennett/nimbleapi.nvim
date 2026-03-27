---
phase: 5
slug: stdlib-provider
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-26
---

# Phase 5 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | none — no automated test suite yet (manual Neovim testing only) |
| **Config file** | none |
| **Quick run command** | `grep -c "function M.extract_routes" lua/nimbleapi/providers/stdlib.lua` |
| **Full suite command** | manual — `:NimbleAPI toggle` in a net/http stdlib project |
| **Estimated runtime** | ~30 seconds (manual) |

---

## Sampling Rate

- **After every task commit:** Run the automated grep checks in task `<verify>` blocks
- **After every plan wave:** Manual `:NimbleAPI toggle` and `:NimbleAPI info` in a stdlib project
- **Before `/gsd:verify-work`:** Manual smoke test with all three receiver styles (mux.HandleFunc, http.HandleFunc, s.mux.HandleFunc)
- **Max feedback latency:** grep checks < 2 seconds; manual test ~30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 05-01-01 | 01 | 1 | STD-02, STD-03, STD-04, STD-05 | grep | `grep -q "@route_path" queries/go/stdlib-routes.scm && echo PASS` | ❌ W0 | ⬜ pending |
| 05-01-02 | 01 | 1 | STD-02, STD-03, STD-04, STD-05, STD-06 | grep | `grep -q "split_method_path\|KNOWN_METHODS" lua/nimbleapi/providers/stdlib.lua && echo PASS` | ❌ W0 | ⬜ pending |
| 05-02-01 | 02 | 2 | STD-07 | grep | `grep -q "httptest" queries/go/stdlib-testclient.scm && echo PASS` | ❌ W0 | ⬜ pending |
| 05-02-02 | 02 | 2 | STD-07 | grep | `grep -q "extract_test_calls_buf" lua/nimbleapi/providers/stdlib.lua && echo PASS` | ❌ W0 | ⬜ pending |
| 05-02-03 | 02 | 2 | STD-01 | grep | `grep -q "source-scan\|HandleFunc(" lua/nimbleapi/providers/stdlib.lua && echo PASS` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

No test infrastructure to install — this project has no automated test suite yet. All verification is via:
1. grep-based checks in `<verify>` blocks of each task (check file existence and key patterns)
2. Manual Neovim testing with `:NimbleAPI toggle` / `:NimbleAPI info` / `:NimbleAPI pick`

*Existing grep-based infrastructure covers all phase requirements.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Pre-1.22 HandleFunc appears with method ANY | STD-02 | No plenary test suite | Open a stdlib project, `:NimbleAPI toggle`, verify method column shows ANY for routes without method prefix |
| Go 1.22+ "GET /path" splits to method=GET path=/path | STD-03 | No plenary test suite | Open a stdlib project with `mux.HandleFunc("GET /users", ...)`, verify method=GET in explorer |
| s.mux.HandleFunc captured | STD-05 | No plenary test suite | Open a project where routes are registered via struct field mux, verify routes appear |
| {$} stripped from paths | STD-06 | No plenary test suite | Open a project with `mux.HandleFunc("/users/{$}", ...)`, verify path shows `/users/` not `/users/{$}` |
| httptest.NewRequest codelens | STD-07 | No plenary test suite | Open a *_test.go with httptest.NewRequest calls, `:NimbleAPI codelens`, verify virtual text |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 120s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
