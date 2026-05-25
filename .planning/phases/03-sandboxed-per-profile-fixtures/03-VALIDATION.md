---
phase: 3
slug: sandboxed-per-profile-fixtures
status: draft
nyquist_compliant: true
wave_0_complete: false
created: 2026-05-25
---

# Phase 3 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Hand-rolled `tests/run.sh` (POSIX bash) |
| **Config file** | None — self-contained script |
| **Quick run command** | `bash tests/run.sh` |
| **Full suite command** | `bash tests/run.sh` |
| **Estimated runtime** | ~10 seconds |

---

## Sampling Rate

- **After every task commit:** Run `bash tests/run.sh`
- **After every plan wave:** Run `bash tests/run.sh`
- **Before `/gsd-verify-work`:** Full suite must be green
- **Max feedback latency:** 10 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 3-01-01 | 01 | 1 | TEST-02 | — | N/A | integration | `bash tests/run.sh` | ❌ W0 | ⬜ pending |
| 3-02-01 | 02 | 1 | TEST-01 | — | N/A | smoke | `bash tests/run.sh` | ❌ W0 | ⬜ pending |
| 3-02-02 | 02 | 1 | TEST-01 | — | N/A | smoke | `bash tests/run.sh` | ❌ W0 | ⬜ pending |
| 3-03-01 | 03 | 2 | TEST-04 | — | N/A | integration | `bash tests/run.sh` | ❌ W0 | ⬜ pending |
| 3-03-02 | 03 | wave 3 | TEST-01, TEST-02, TEST-04 | — | N/A | integration | `bash tests/run.sh` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `tests/lib/sandbox.sh` — shared sandbox isolation helper (sourced by run.sh and Phase 4 loop)
- [ ] `tests/fixtures/` directory tree — all 9 green profile fixtures + `_broken/` fixture
- [ ] `scripts/regen-fixtures.sh` — fixture regeneration script
- [ ] New `tests/run.sh` sections — fixture audit loop + broken fixture assertions

---

## Manual-Only Verifications

All phase behaviors have automated verification.

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 10s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
