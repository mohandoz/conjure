---
phase: 30-workspace-orchestration-mutating-rollback-saga
plan: "01"
subsystem: lib
tags: [workspace, saga, state-machine, atomic-write, shellcheck]

requires:
  - phase: 30-workspace-orchestration-mutating-rollback-saga
    plan: "00"
    provides: _workspace-trio fixture + Phase 30 graceful-red test block

provides:
  - lib/workspace.sh: workspace_state_write, workspace_state_read, workspace_state_validate

affects:
  - scripts/workspace.sh ws_do_adopt (Wave 3 — sources lib/workspace.sh)
  - scripts/workspace.sh ws_do_rollback (Wave 4 — sources lib/workspace.sh)

tech-stack:
  added: []
  patterns:
    - "atomic-write: jq > tmp.$$ && mv (same-dir rename, mirrors adopt.sh state_record)"
    - "create-vs-update branch: jq -n on first write, jq filter on existing file"
    - "safe read: jq -r expr // empty with 2>/dev/null || true (never exits non-zero)"
    - "validate: sequential jq -e checks, all errors to stderr, returns 2"

key-files:
  created: []
  modified:
    - lib/workspace.sh

key-decisions:
  - "workspace_state_validate accepts snapshotting as a valid in-progress repo status; per-repo status-level validation is the caller's responsibility (ws_do_rollback treats snapshotting + empty snapshot_ref as never-mutated, skip with note)"
  - "tmp path is state_path.tmp.$$ (same directory as state file) to guarantee atomic mv on POSIX — not /tmp/ which may be on a different filesystem"
  - "workspace_state_read never exits non-zero: missing file, null result, or jq error all return empty string; callers use optional extraction safely"

metrics:
  duration: 15min
  completed: 2026-06-04
---

# Phase 30 Plan 01: lib/workspace.sh saga state helpers Summary

**SIGKILL-durable atomic state primitives (workspace_state_write/read/validate) appended to lib/workspace.sh using the adopt.sh state_record pattern**

## Performance

- **Duration:** 15 min
- **Started:** 2026-06-04T00:30:00Z
- **Completed:** 2026-06-04T00:45:00Z
- **Tasks:** 1
- **Files modified:** 1

## Accomplishments

- Appended 3 new functions to `lib/workspace.sh` after `workspace_discover_siblings`:
  - `workspace_state_write <state_path> <jq_filter> [jq_args...]`: atomic jq>tmp.$$+mv; create branch uses `jq -n`, update branch applies filter to existing file; on jq failure removes tmp and returns 2 with error to stderr
  - `workspace_state_read <state_path> <jq_expr>`: one-liner `jq -r expr // empty` with `2>/dev/null || true`; never exits non-zero; safe for optional field extraction
  - `workspace_state_validate <state_path>`: sequential checks for file presence, valid JSON, run_id, phase, repos array; returns 2 with specific error messages to stderr; does NOT reject "snapshotting" status (in-progress sentinel per WS-06)
- shellcheck -S error -e SC2164,SC2044,SC2034,SC2155 passes with zero warnings
- All 566 Phase 29 tests remain green; 8 graceful-red Phase 30 tests remain unchanged (require Wave 3+ feature code)

## Task Commits

1. **Task 1: workspace_state_write/read/validate** - `f8e59b1` (feat)

## Files Created/Modified

- `lib/workspace.sh` - 3 new functions appended (81 lines added); existing workspace_manifest_validate, workspace_manifest_load, workspace_discover_siblings unchanged

## Decisions Made

- **snapshotting is a valid status in workspace_state_validate.** The function checks structural schema only (run_id, phase, repos array). Per-repo status validation — including the "snapshotting + empty snapshot_ref = never mutated, skip during rollback" rule — belongs in ws_do_rollback (Wave 4) where the semantic meaning matters. workspace_state_validate is a schema gate, not a semantic gate.
- **tmp path is same-dir, not /tmp/.** Using `${state_path}.tmp.$$` ensures the rename is atomic on POSIX (src and dst on same filesystem). A /tmp/ path could cross filesystem boundaries (e.g., tmpfs vs ext4), making mv a copy+delete which is not atomic.
- **workspace_state_read never exits non-zero.** Callers need safe optional extraction; having it fail on missing file would force every caller to guard with `|| true` themselves. The `// empty` default and `2>/dev/null || true` idiom produces empty string for any failure mode.

## Deviations from Plan

None — plan executed exactly as written.

## Known Stubs

None — this plan delivers building-block primitives only. The functions are fully implemented. Callers (ws_do_adopt, ws_do_rollback) are in Waves 3-4.

## Threat Flags

No new security surface introduced. workspace_state_write accepts a caller-provided state_path but path traversal is already enforced by workspace_manifest_validate before any state write is initiated. jq filters are written by the orchestrator, not from user input.

## Self-Check: PASSED

- [x] `lib/workspace.sh` exists and has 3 new function definitions (workspace_state_write, workspace_state_read, workspace_state_validate at lines 169, 196, 211)
- [x] Commit f8e59b1 exists
- [x] shellcheck exits 0
- [x] PASS: 566 FAIL: 8 (unchanged from Phase 30-00 baseline)

---
*Phase: 30-workspace-orchestration-mutating-rollback-saga*
*Completed: 2026-06-04*
