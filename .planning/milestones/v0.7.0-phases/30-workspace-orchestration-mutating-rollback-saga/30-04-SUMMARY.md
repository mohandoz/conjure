---
phase: 30-workspace-orchestration-mutating-rollback-saga
plan: "04"
subsystem: scripts
tags: [workspace, rollback, saga, sigkill, zero-diff, sha256, shellcheck, posix]

requires:
  - phase: 30-workspace-orchestration-mutating-rollback-saga
    plan: "03"
    provides: scripts/workspace.sh ws_do_rollback (Wave 3 stub) + ws_do_adopt

provides:
  - scripts/workspace.sh: ws_do_rollback Wave 4 — created-files deletion, sha256 zero-diff verify, CR-02 re-check, D-03 .snapshot-meta.json cleanup, archive-is-copy pattern

affects: []

tech-stack:
  added: []
  patterns:
    - "created-files deletion after snapshot_rollback: find rb_abs | filter absent from rb_snap_ref | rm -f (mirrors adopt.sh rollback_path Step 2)"
    - "D-03 .snapshot-meta.json cleanup: explicit rm after snapshot_rollback (tar leaks it from snapshot root into target root)"
    - "bottom-up empty-dir prune: find -type d | awk length-sort desc | rmdir dirs absent from snapshot"
    - "sha256 zero-diff verify loop: per-repo; reads sha256_pre_ref hash file; mismatch → failure + continue (independence)"
    - "CR-02 rollback-time traversal re-check: pwd -P boundary guard per repo before restore; out-of-bounds → failure + continue"
    - "archive-is-COPY pattern: cp state to timestamped .json; original stays with all repos status=rolled_back; second --rollback → exit 0 no-op"

key-files:
  created: []
  modified:
    - scripts/workspace.sh

key-decisions:
  - "D-03 fix applied to ws_do_rollback: snapshot_rollback (tar -xpf snapshot/. → target) leaks .snapshot-meta.json into target root; explicit rm after snapshot_rollback (same fix as adopt.sh rollback_path line 338)"
  - "created-files deletion uses snapshot root as the reference: any file in repo_abs absent from rb_snap_ref was created by adopt and is deleted; .snapshot-meta.json already removed by D-03 fix before this loop"
  - "sha256 zero-diff verify happens AFTER created-files deletion so pre-adopt hash file records only original files and the verify loop compares against those same original files"
  - "Independence principle maintained: per-repo sha256 mismatch or restore failure → any_rb_failed=1 + continue; never exit mid-loop"

metrics:
  duration: 20min
  completed: 2026-06-04
---

# Phase 30 Plan 04: `workspace adopt --rollback` + SIGKILL saga zero-diff proof (WS-07) Summary

**Per-repo independent rollback with created-files deletion, sha256 zero-diff verify loop, D-03 .snapshot-meta.json cleanup, and CR-02 traversal re-check — SIGKILL saga proof passes (PASS: 574 FAIL: 0)**

## Performance

- **Duration:** 20 min
- **Started:** 2026-06-04T00:00:00Z
- **Completed:** 2026-06-04T00:20:00Z
- **Tasks:** 1
- **Files modified:** 1

## Accomplishments

Wave 4 enhanced `ws_do_rollback` in `scripts/workspace.sh` with all four steps required for the SIGKILL saga zero-diff proof:

**Step 1: snapshot_rollback** (inherited from Wave 3) — tar-based restore of all original files.

**D-03 cleanup:** After `snapshot_rollback`, explicitly `rm -f "$rb_abs/.snapshot-meta.json"`. The snapshot directory carries `.snapshot-meta.json` at its root; `tar -xpf snapshot/.` leaks it into the target root. This mirrors adopt.sh `rollback_path` line 338 (same D-03 fix). This was the critical fix that turned the SIGKILL diff-r test green.

**Step 2: created-files deletion** — Walk `rb_abs` with `find -type f`, excluding `.conjure-adopt-backups`, `.conjure-archive-*`, `.conjure-adopt-state`. For each file: if `! -e "$rb_snap_ref/$_rel"` (no counterpart in snapshot), `rm -f` it. This removes files created by `conjure adopt` that weren't in the pre-adopt tree. Followed by bottom-up empty-dir prune (longest paths first via awk length-sort): `rmdir` dirs absent from snapshot.

**Step 3: sha256 zero-diff verify** — If `sha256_pre_ref` file exists, read each `"hash  path"` line, compute `ws_sha_of "$rb_abs/$_frel"`, count mismatches. Mismatch > 0 → record per-repo failure + `continue` (independence, never `exit`).

**CR-02 rollback-time traversal re-check** — Before any restore, `cd "$rb_abs" && pwd -P` → boundary check against `$manifest_root`; out-of-bounds → `any_rb_failed=1 + continue`.

All behaviors:
- No-state-file → exit 2 "nothing to roll back"
- All repos already `rolled_back` → exit 0 no-op (idempotent)
- `snapshotting` + empty `snapshot_ref` → mark `rolled_back`, skip with note
- `pending` → mark `rolled_back`, skip
- `snapshot_ref` missing or not a dir → `any_rb_failed=1 + continue`
- Archive: `cp state_path timestamped_copy` after loop; original stays; second --rollback reads original → exit 0

## Task Commits

1. **Task 1: ws_do_rollback Wave 4** — `e24ffb6` (feat)

## Files Created/Modified

- `scripts/workspace.sh` — ws_do_rollback enhanced with CR-02 re-check, D-03 cleanup, created-files deletion, empty-dir prune, sha256 zero-diff verify loop (~123 net insertions)

## Test Results

- **Before:** PASS: 573  FAIL: 1
- **After:**  PASS: 574  FAIL: 0

WS-07 tests (4 of 4 green):
- WS-07-NO-STATE: --rollback with no state file exits 2
- WS-07-ARCHIVED: timestamped copy + original remain with all repos rolled_back
- WS-07-IDEMPOTENT: second --rollback exits 0
- SAGA SIGKILL diff-r: all repos diff -r pre vs post-rollback empty (PASS — Wave 4 deliverable)

SAGA SIGKILL proof (4 assertions, all green):
- Kill landed after ≥1 repo applied (in kill window)
- Post-kill --rollback exits 0
- All per-repo sha256 hashes match pre-run (zero-diff)
- diff -r pre vs post-rollback empty for all repos (excl. conjure dirs)

Phase 22/24/29/30 prior tests all remain green.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] D-03 .snapshot-meta.json leaks into repo root after snapshot_rollback**
- **Found during:** Task 1 verification — the diff -r test failed with "Only in post: .snapshot-meta.json" for each of the 3 repos
- **Issue:** `snapshot_rollback` uses `tar -xpf snapshot/.` to restore the repo; the snapshot directory contains `.snapshot-meta.json` at its root (created by `snapshot_create`); `tar -xpf` extracts it into the target root; the created-files deletion loop does NOT remove it because `.snapshot-meta.json` EXISTS in `$rb_snap_ref` (snapshot root) so `[ ! -e "$rb_snap_ref/.snapshot-meta.json" ]` is false
- **Fix:** Explicit `rm -f "$rb_abs/.snapshot-meta.json"` after `snapshot_rollback`, before the created-files deletion loop; mirrors adopt.sh rollback_path line 338 (same D-03 fix documented there)
- **Files modified:** scripts/workspace.sh
- **Commit:** e24ffb6

The sha256 zero-diff verify passed immediately (sha256_pre_ref records only files that existed before adopt, and those all restored correctly). The diff-r failure was solely the `.snapshot-meta.json` leak.

## Known Stubs

None — all Wave 4 deliverables implemented. The SIGKILL diff-r test is green.

## Threat Flags

No new security surface beyond the plan's threat model. All mitigations implemented:
- T-30-04-01: CR-02 traversal re-check at rollback time (pwd -P boundary guard) per repo before restore
- T-30-04-02: sha256 zero-diff verify loop per repo; mismatch → per-repo failure + aggregate exit 2
- T-30-04-03: workspace_state_validate (via repo capture check) + no-state-file guard at entry
- T-30-04-04: independence: per-repo continue (not exit) on failure; any_failed flag; aggregate exit 2 only after loop

## Self-Check: PASSED

- [x] `ws_do_rollback` present in scripts/workspace.sh (grep -c = 10: definition + calls + comments)
- [x] `CR-02` traversal re-check inside ws_do_rollback (manifest_root boundary guard)
- [x] `.snapshot-meta.json` D-03 cleanup present (rm -f after snapshot_rollback)
- [x] `find "$rb_abs" -type f` created-files deletion loop present
- [x] `sha256_pre_ref` verify loop present (reads hash file, ws_sha_of comparison)
- [x] `cp "$state_path" "$archive_name"` archive-is-copy pattern present (original stays)
- [x] shellcheck -S error -e SC2164,SC2044,SC2034,SC2155 exits 0
- [x] WS-07 tests: 4/4 green
- [x] SAGA SIGKILL proof: 4/4 assertions green including diff -r zero-diff
- [x] PASS: 574  FAIL: 0 (up from 573/1)
- [x] Commit e24ffb6 exists

---
*Phase: 30-workspace-orchestration-mutating-rollback-saga*
*Completed: 2026-06-04*
