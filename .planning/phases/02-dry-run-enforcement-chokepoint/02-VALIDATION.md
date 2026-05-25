---
phase: 2
slug: dry-run-enforcement-chokepoint
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-05-24
---

# Phase 2 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Hand-rolled bash (`tests/run.sh`) — project standard |
| **Config file** | none — `tests/run.sh` is self-contained |
| **Quick run command** | `bash tests/run.sh` |
| **Full suite command** | `bash tests/run.sh` |
| **Estimated runtime** | ~5 seconds |

---

## Sampling Rate

- **After every task commit:** Run `bash tests/run.sh`
- **After every plan wave:** Run `bash tests/run.sh`
- **Before `/gsd-verify-work`:** Full suite must be green
- **Max feedback latency:** 5 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------------|-----------|-------------------|-------------|--------|
| 2-01-01 | 01 | 1 | SAFE-02 | lib/mutate.sh is sourceable under set -uo pipefail | smoke | `source lib/mutate.sh && echo ok` | ❌ Wave 1 | ⬜ pending |
| 2-01-02 | 01 | 1 | SAFE-02 | mutate_mkdir/cp/write suppress writes when DRY_RUN=1 | unit | `bash tests/run.sh` | ❌ Wave 1 | ⬜ pending |
| 2-01-03 | 01 | 1 | SAFE-01 | mutate_* print [dry-run] prefix when DRY_RUN=1 | output | `bash tests/run.sh` | ❌ Wave 1 | ⬜ pending |
| 2-02-01 | 02 | 2 | SAFE-01 | init-project.sh makes no writes when DRY_RUN=1 | integration | `bash tests/run.sh` | ❌ Wave 2 | ⬜ pending |
| 2-03-01 | 03 | 2 | SAFE-01 | profiles/*/apply.sh makes no writes when DRY_RUN=1 | integration | `bash tests/run.sh` | ❌ Wave 2 | ⬜ pending |
| 2-04-01 | 04 | 2 | SAFE-01 | compliance/*/apply.sh makes no writes when DRY_RUN=1 | integration | `bash tests/run.sh` | ❌ Wave 2 | ⬜ pending |
| 2-05-01 | 05 | 3 | SAFE-01 | cli/conjure exports DRY_RUN before calling init-project.sh | smoke | `bash tests/run.sh` | ❌ Wave 3 | ⬜ pending |
| 2-06-01 | 06 | 4 | SAFE-01 | conjure init --dry-run leaves target tree byte-identical | integration | `bash tests/run.sh` | ❌ Wave 4 | ⬜ pending |
| 2-06-02 | 06 | 4 | SAFE-01 | [dry-run] prefixed lines appear in output | output | `bash tests/run.sh` | ❌ Wave 4 | ⬜ pending |
| 2-06-03 | 06 | 4 | SAFE-02 | mutation count > 0 in summary line | output | `bash tests/run.sh` | ❌ Wave 4 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `lib/mutate.sh` — must be created in Wave 1 (plan 02-01); tests in Wave 4 depend on it
- [ ] `tests/run.sh` dry-run section — added in Wave 4 (plan 02-06); requires lib/mutate.sh + all retrofits complete

*Note: This phase uses hand-rolled `tests/run.sh`. Unit-level tests for lib/mutate.sh are self-contained bash assertions inside `tests/run.sh`. Integration tests (02-06) run last after all write sites are wired.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Zero mutations confirmed on Windows | SAFE-01 | Requires native Windows environment | Run `conjure init --dry-run .` on native Windows; verify target directory unchanged |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave dependency noted
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING file references
- [ ] No watch-mode flags
- [ ] Feedback latency < 5s
- [ ] `nyquist_compliant: true` set in frontmatter
