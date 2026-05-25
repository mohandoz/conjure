---
phase: 12
slug: org-overlay
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-05-26
---

# Phase 12 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Hand-rolled bash test runner |
| **Config file** | none |
| **Quick run command** | `bash tests/run.sh` |
| **Full suite command** | `bash tests/run.sh` |
| **Estimated runtime** | ~15 seconds |

---

## Sampling Rate

- **After every task commit:** Run `bash tests/run.sh`
- **After every plan wave:** Run `bash tests/run.sh`
- **Before `/gsd-verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------------|-----------|-------------------|-------------|--------|
| OVLY-01a | init-overlay | 1 | OVLY-01 | init --overlay exits 0 and applies base kit | integration | `bash tests/run.sh` | ❌ Wave 0 | ⬜ pending |
| OVLY-01b | init-overlay | 1 | OVLY-01 | overlay files appear in .claude/ | integration | `bash tests/run.sh` | ❌ Wave 0 | ⬜ pending |
| OVLY-01c | init-overlay | 1 | OVLY-01 | all writes go through lib/mutate.sh (DRY_RUN honored) | unit | `bash tests/run.sh` | ❌ Wave 0 | ⬜ pending |
| OVLY-02a | init-overlay | 1 | OVLY-02 | .conjure-org-overlay marker written | integration | `bash tests/run.sh` | ❌ Wave 0 | ⬜ pending |
| OVLY-02b | init-overlay | 1 | OVLY-02 | marker contains url= matching overlay URL | integration | `bash tests/run.sh` | ❌ Wave 0 | ⬜ pending |
| OVLY-02c | init-overlay | 1 | OVLY-02 | marker contains sha= matching actual overlay commit | integration | `bash tests/run.sh` | ❌ Wave 0 | ⬜ pending |
| OVLY-03a | refresh-overlay | 2 | OVLY-03 | refresh-overlay re-applies with overlay-wins semantics | integration | `bash tests/run.sh` | ❌ Wave 0 | ⬜ pending |
| OVLY-03b | refresh-overlay | 2 | OVLY-03 | missing marker → exit 1 with correct message | unit | `bash tests/run.sh` | ❌ Wave 0 | ⬜ pending |
| OVLY-04a | audit | 2 | OVLY-04 | audit reports up-to-date when SHA matches | integration | `bash tests/run.sh` | ❌ Wave 0 | ⬜ pending |
| OVLY-04b | audit | 2 | OVLY-04 | audit reports DRIFT when SHA differs | integration | `bash tests/run.sh` | ❌ Wave 0 | ⬜ pending |
| OVLY-04c | audit | 2 | OVLY-04 | audit skips drift check on git ls-remote failure | unit | `bash tests/run.sh` | ❌ Wave 0 | ⬜ pending |
| OVLY-05a | init-overlay | 1 | OVLY-05 | no credential storage in Conjure code (static grep) | static | `bash tests/run.sh` | ❌ Wave 0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] OVLY test blocks in `tests/run.sh` — all 12 test assertions above
- [ ] `scripts/init-overlay.sh` — new worker script (created in Wave 1)
- [ ] `scripts/refresh-overlay.sh` — new worker script (created in Wave 1)

*No separate test infrastructure needed — all tests inline in `tests/run.sh` following established pattern.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Private repo auth uses git credential store | OVLY-05 | Requires real private repo with SSH/HTTPS auth configured | Run `conjure init --overlay <private-repo-url>` and confirm it clones without prompting for credentials |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
