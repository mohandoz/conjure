---
phase: 30
slug: workspace-orchestration-mutating-rollback-saga
status: draft
nyquist_compliant: true
wave_0_complete: false
created: 2026-06-04
---

# Phase 30 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Hand-rolled `tests/run.sh` fixture harness (project convention) |
| **Config file** | none — fixtures under `tests/fixtures/_workspace-trio/` |
| **Quick run command** | `bash tests/run.sh` (grep the WS-0[567]/SAGA block) |
| **Full suite command** | `bash tests/run.sh` |
| **Estimated runtime** | ~60–90 seconds (SIGKILL test adds bounded polling) |

---

## Sampling Rate

- **After every task commit:** Run `bash tests/run.sh`
- **After every plan wave:** Run `bash tests/run.sh` + `shellcheck -S error -e SC2164,SC2044,SC2034,SC2155 <changed .sh>`
- **Before `/gsd-verify-work`:** Full suite must be green
- **Max feedback latency:** 90 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Correct Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 30-00-01 | 00 | 0 | WS-05..07 | — | `_workspace-trio` fixture (3 small repos + manifest) + graceful-red WS-05/06/07 + SAGA test block | fixture | `bash tests/run.sh` (red) | ❌ W0 | ⬜ pending |
| 30-01-01 | 01 | 1 | WS-06 | T-30-01 | lib/workspace.sh state helpers: workspace_state_write (atomic jq>tmp+mv), workspace_state_read; schema {run_id,started,phase,repos[{name,snapshot_ref,sha256_pre,status}]} | fixture | `bash tests/run.sh` (STATE) | ❌ W0 | ⬜ pending |
| 30-02-01 | 02 | 2 | WS-05 | T-30-02 | `workspace update`: serial per-repo conjure update; stop-on-first-error default; --continue-on-error; merge/conflict status + sidecars surfaced in aggregate | fixture | `bash tests/run.sh` (WS-05) | ❌ W0 | ⬜ pending |
| 30-03-01 | 03 | 3 | WS-06 | T-30-03 | `workspace adopt`: traversal re-check per repo; du estimate >2GB gate (--allow-large-snapshots); ALL snapshots before ANY apply (state shows all "snapshotted" before first "applied"); state written before/after each op; --tag filter; --dry-run zero writes; stop-on-fail | fixture | `bash tests/run.sh` (WS-06) | ❌ W0 | ⬜ pending |
| 30-04-01 | 04 | 4 | WS-07 | T-30-04 | `--rollback`: per-repo independent restore from snapshot_ref; continue on partial failure; idempotent (re-run no-op exit 0; no state → exit 2); state archived timestamped | fixture | `bash tests/run.sh` (WS-07) | ❌ W0 | ⬜ pending |
| 30-04-02 | 04 | 4 | WS-07 | T-30-05 | SAGA PROOF: kill -9 mid-batch on _workspace-trio → --rollback → per-repo sha256 zero-diff (every pre-run file hash matches) | fixture+SIGKILL | `bash tests/run.sh` (SAGA) | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `tests/fixtures/_workspace-trio/` — 3 small repos (alpha/beta/gamma) each with .claude/ + a couple of content files (small enough for fast sha256), + `.conjure-workspace.json`
- [ ] One trio repo variant arranged so adopt has real work to apply (mutations occur → rollback is meaningful)
- [ ] Phase 30 graceful-red block in tests/run.sh: WS-05 (update aggregate), WS-06 (saga invariant + dry-run + 2GB gate via du stub), WS-07 (rollback + idempotency), SAGA (SIGKILL zero-diff, mirroring the Phase 22/24 bounded-poll + kill -9 pattern)

*Wave 0 establishes the Nyquist invariant: trio fixture + red tests before saga code.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| >2 GB real-disk snapshot warning | WS-06 | CI fixtures are tiny; the du gate is tested with a stubbed du, not 2 GB of real data | On a machine with a large repo set: `conjure workspace adopt` → warns and requires --allow-large-snapshots |

---

## Validation Sign-Off

- [x] All tasks have automated verify (fixture/test) or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references (trio fixture + red tests incl. SIGKILL)
- [x] No watch-mode flags
- [x] Feedback latency < 90s
- [x] `nyquist_compliant: true` set in frontmatter (Wave 0 wired)

**Approval:** pending (wave_0_complete: false)
