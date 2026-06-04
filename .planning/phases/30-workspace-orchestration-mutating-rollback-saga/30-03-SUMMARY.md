---
phase: 30-workspace-orchestration-mutating-rollback-saga
plan: "03"
subsystem: scripts
tags: [workspace, adopt, saga, snapshot, rollback, state-machine, shellcheck]

requires:
  - phase: 30-workspace-orchestration-mutating-rollback-saga
    plan: "02"
    provides: scripts/workspace.sh ws_do_update + lib/workspace.sh saga state helpers

provides:
  - scripts/workspace.sh: ws_do_adopt (two-phase saga) + ws_do_rollback + adopt dispatch
  - lib/workspace.sh: ws_sha_of helper

affects:
  - scripts/workspace.sh ws_do_rollback (Wave 4 — extends ws_do_rollback with created-files deletion)

tech-stack:
  added: []
  patterns:
    - "two-phase saga: snapshot ALL repos (PHASE A) before applying ANY (PHASE B)"
    - "snapshotting pre-write sentinel: workspace_state_write before snapshot_create; upgraded to snapshotted post-write after rc=0"
    - "snapshot_create two-arg API: snapshot_create repo_abs backup_root; result via CONJURE_SNAPSHOT_PATH env var (not stdout)"
    - "CONJURE_ADOPT_REUSE_SNAPSHOT=1: passed in PHASE B per-repo subprocess env; prevents double-snapshot disk overhead"
    - "du gate: awk summing all lines handles stubs emitting multiple lines per argv from printf-based test shims"
    - "sha256_pre_ref: mktemp hash file (per-file manifest) stored outside repo tree; path recorded in state"
    - "ws_do_rollback: idempotent; skips snapshotting+empty snapshot_ref (never-mutated); archives state with timestamp"

key-files:
  created: []
  modified:
    - scripts/workspace.sh
    - lib/workspace.sh

key-decisions:
  - "PHASE B reads repos from the original filtered manifest (which has .path), not from the state file (which lacks .path); state is checked per-repo to confirm status == snapshotted before applying"
  - "du awk uses sum accumulator (sum+=$1) rather than print-first-field to handle test stubs that emit multiple lines when printf repeats for each argv"
  - "ws_do_rollback is included in Wave 3 for WS-07-NO-STATE, WS-07-ARCHIVED, and WS-07-IDEMPOTENT tests; full diff-r zero-diff (created-files deletion) is Wave 4"

metrics:
  duration: 45min
  completed: 2026-06-04
---

# Phase 30 Plan 03: `workspace adopt` saga orchestrator (WS-06) Summary

**Two-phase snapshot-all-before-apply saga: PHASE A snapshots ALL repos before PHASE B applies any, with atomic state writes before+after each op using snapshotting/snapshotted sentinel pattern**

## Performance

- **Duration:** 45 min
- **Started:** 2026-06-04T00:00:00Z
- **Completed:** 2026-06-04T00:45:00Z
- **Tasks:** 1
- **Files modified:** 2

## Accomplishments

- Appended `ws_sha_of` to `lib/workspace.sh` (cross-platform sha256 via sha256sum or shasum -a 256; tr -d '\r' for Windows Git Bash CR stripping; mirrors adopt.sh sha_of verbatim)
- Added source lines for `lib/log.sh` and `lib/mutate.sh` BEFORE `lib/snapshot.sh` in `scripts/workspace.sh` (snapshot_create load-order dependency; requires both libs already sourced)
- Added `WS_STATE_TMP=""` module-level variable; extended `_ws_cleanup` to `rm -f "${WS_STATE_TMP:-}"` — no new trap registration
- Implemented `ws_do_adopt <manifest_path> <manifest_dir> <tag_filter> <allow_large> <dry_run> <yes>`:
  - **Non-TTY consent gate**: YES=0 + non-TTY + DRY_RUN=0 → exit 2 (mutating op)
  - **Tag filter**: `jq -c --arg tag ... '.repos[] | select(.tags != null and (.tags | index($tag) != null))'`
  - **du disk estimate gate**: `du -sk | awk '{sum+=$1} END{print sum+0}'` per repo; sum > 2097152 KiB → exit 2 unless --allow-large-snapshots; awk sum accumulator handles test stubs emitting multiple lines
  - **DRY_RUN zero-write**: prints plan + estimate, returns 0, NO state file written, NO snapshots
  - **State init**: workspace_state_write with run_id (date-based + PID), started ISO ts, phase="snapshot", repos array with status="pending"
  - **PHASE A** (snapshot loop): CR-02 traversal re-check → PRE-WRITE status="snapshotting" → `snapshot_create "$repo_abs" "$backup_root"` (two-arg API) → `snap_ref="$CONJURE_SNAPSHOT_PATH"` → mktemp per-file hash file → POST-WRITE status="snapshotted" + snapshot_ref + sha256_pre_ref; break on any failure
  - **PHASE B** (apply loop): reads from original manifest (not state file); checks state status per-repo; CR-02 re-check; `CONJURE_ADOPT_REUSE_SNAPSHOT=1 bash conjure adopt "$repo_abs"`; workspace_state_write status="applied"|"failed"; stop-on-fail
  - **PHASE DONE**: workspace_state_write phase="done"; aggregate report
- Implemented `ws_do_rollback`: idempotent skipping of rolled_back repos; "snapshotting"+empty snapshot_ref treated as never-mutated; snapshot_rollback per repo; archives state file with timestamp (not rm -f); returns 2 if any repo fails
- Wired `adopt)` case in SUBCMD dispatch with full flag parsing (--tag, --allow-large-snapshots, --dry-run, --yes, --rollback)
- shellcheck -S error -e SC2164,SC2044,SC2034,SC2155 passes with zero warnings on both files

## Task Commits

1. **Task 1: ws_do_adopt + ws_sha_of + ws_do_rollback** — `e331390` (feat)

## Files Created/Modified

- `lib/workspace.sh` — ws_sha_of function appended (17 lines)
- `scripts/workspace.sh` — lib/log.sh + lib/snapshot.sh sourced; WS_STATE_TMP module var; _ws_cleanup extended; ws_do_adopt (~170 lines); ws_do_rollback (~90 lines); adopt case in dispatch (~20 lines); header/usage updated

## Test Results

- **Before:** PASS: 567  FAIL: 7
- **After:**  PASS: 573  FAIL: 1

WS-06 tests (4 of 4 green):
- WS-06-SAGA-INVARIANT: all repos snapshotted before applied (state confirms)
- WS-06-DRY-RUN: no state file, no snapshots, exits 0
- WS-06-DU-GATE: large snapshot refused without --allow-large-snapshots (exit 2)
- WS-06-DU-GATE-bypass: --allow-large-snapshots bypasses gate

WS-07 tests (3 of 4 green; 1 expected Wave 4 failure):
- WS-07-NO-STATE: --rollback with no state file exits 2
- WS-07-ARCHIVED: timestamped copy + original remain with all repos rolled_back
- WS-07-IDEMPOTENT: second --rollback exits 0
- SIGKILL diff-r: FAIL — expected; ws_do_rollback restores files but does not yet delete created[] files (requires Wave 4 per plan done-criteria: "SIGKILL test still fails (needs Wave 4 --rollback)")

Pre-existing 567 tests remain green (Phase 22/24/29 all pass).

## Decisions Made

- **PHASE B reads from manifest, not state file.** The state file's repos array has `{name, snapshot_ref, sha256_pre_ref, status}` but NOT `path`. PHASE B needs `path` to construct `repo_abs`. Reading from the original filtered manifest and checking per-repo status from state is the correct split: manifest = structural truth (paths), state = saga progress (status).
- **awk sum accumulator for du.** Test stubs using `printf '2200000\t%s\n' "${@}"` emit one line per argv (`-sk` and `/path`). `awk '{print $1}'` on multi-line output produces multi-value strings that break arithmetic. `awk '{sum+=$1} END{print sum+0}'` is robust for both real du (one line) and multi-line stubs.
- **ws_do_rollback included in Wave 3.** WS-07 tests (NO-STATE, ARCHIVED, IDEMPOTENT) test the rollback path without needing the full created-files deletion. Implementing ws_do_rollback now enables 3 of 4 WS-07 tests to pass. The remaining SIGKILL diff-r test requires Wave 4's created-list deletion loop (mirrors adopt.sh rollback_path Step 2).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] PHASE B repo path resolution using state file instead of manifest**
- **Found during:** Task 1 verification — PHASE B failed with "cannot resolve path for repo: alpha" because state file repos lack `.path` field
- **Issue:** Initial implementation queried `snapshotted_repos` from state file (which has `{name, snapshot_ref, sha256_pre_ref, status}` but NOT `path`); `jq -r '.path'` returned `null`; `"$manifest_dir/null"` is not a real directory
- **Fix:** PHASE B now iterates over original `repos_json` (from manifest, has `.path`) and checks per-repo state status via a jq lookup; skips repos not in "snapshotted" state
- **Files modified:** scripts/workspace.sh
- **Commit:** e331390

**2. [Rule 1 - Bug] du awk multi-line output breaking arithmetic**
- **Found during:** Task 1 verification — du gate test exited 1 instead of 2; arithmetic error from multi-line string in `$((total_kib + du_kib))`
- **Issue:** Test stub `printf '2200000\t%s\n' "${@}"` emits one line per argv (`-sk` and `/path/to/dir`), producing `"2200000\n2200000"` as du_kib; shell arithmetic `$((total_kib + 2200000\n2200000))` syntax error; bash exits 1 (from failed arithmetic)
- **Fix:** Changed `awk '{print $1}'` to `awk '{sum+=$1} END{print sum+0}'`; accumulates all lines robustly for both real du (one line) and test stubs (multiple lines)
- **Files modified:** scripts/workspace.sh
- **Commit:** e331390

## Known Stubs

The remaining SIGKILL diff-r failure is a KNOWN PLANNED stub — `ws_do_rollback` restores files via `snapshot_rollback` (tar -xpf) but does NOT yet delete files created by the adopt run that were absent from the snapshot. This is documented as the Wave 4 deliverable (per 30-03-PLAN.md done-criteria: "SIGKILL test still fails (needs Wave 4 --rollback)"). Wave 4 will add the created-files deletion loop mirroring adopt.sh rollback_path Step 2.

## Threat Flags

No new security surface beyond the plan's threat model. All threat mitigations implemented:
- T-30-03-01: atomic state writes + "snapshotting" sentinel implemented
- T-30-03-02: du gate (2097152 KiB threshold) implemented
- T-30-03-03: non-TTY consent gate (YES=0 + non-TTY + !DRY_RUN → exit 2) implemented
- T-30-03-04: CR-02 traversal re-check before snapshot AND before apply in both PHASE A and PHASE B

## Self-Check: PASSED

- [x] `ws_do_adopt` present in scripts/workspace.sh (grep -c = 6: definition + calls + comments)
- [x] `ws_sha_of` present in lib/workspace.sh (grep -c = 2: definition + usage comment)
- [x] `snapshot_create "$repo_abs" "$backup_root"` (two-arg call) present in scripts/workspace.sh
- [x] `CONJURE_SNAPSHOT_PATH` present in scripts/workspace.sh (env var capture pattern)
- [x] `snapshotting` present as pre-write sentinel status in scripts/workspace.sh
- [x] `CONJURE_ADOPT_REUSE_SNAPSHOT=1` present in PHASE B subprocess invocation
- [x] shellcheck -S error -e SC2164,SC2044,SC2034,SC2155 exits 0 on both files
- [x] DRY_RUN test: no state file written (PASS)
- [x] WS-06 tests: 4/4 green
- [x] WS-07 tests: 3/4 green (SIGKILL diff-r expected Wave 4 failure)
- [x] PASS: 573  FAIL: 1 (up from 567/7)
- [x] Commit e331390 exists

---
*Phase: 30-workspace-orchestration-mutating-rollback-saga*
*Completed: 2026-06-04*
