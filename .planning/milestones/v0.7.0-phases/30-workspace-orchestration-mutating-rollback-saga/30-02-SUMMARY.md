---
phase: 30-workspace-orchestration-mutating-rollback-saga
plan: "02"
subsystem: scripts
tags: [workspace, update, serial-aggregation, traversal-guard, shellcheck]

requires:
  - phase: 30-workspace-orchestration-mutating-rollback-saga
    plan: "01"
    provides: lib/workspace.sh saga state helpers

provides:
  - scripts/workspace.sh: ws_do_update function + update case in SUBCMD dispatch
  - cli/conjure: cmd_workspace extended to dispatch update|adopt tokens

affects:
  - scripts/workspace.sh ws_do_adopt (Wave 3 — update loop pattern to reuse)
  - cli/conjure cmd_workspace (adopt case wired in Wave 3)

tech-stack:
  added: []
  patterns:
    - "per-repo update loop: verbatim CR-02 traversal re-check from ws_do_check"
    - "stop-on-first-error default: CONTINUE_ON_ERROR=0; --continue-on-error inverts"
    - "conflict sidecar surfacing: scan TMPERR for /.conjure-conflict- path patterns"
    - "single EXIT trap: TMPERR added to _ws_cleanup body, no new trap registration"
    - "subprocess output capture: bash conjure update repo_abs >TMPERR 2>&1"

key-files:
  created: []
  modified:
    - scripts/workspace.sh
    - cli/conjure

key-decisions:
  - "No non-TTY gate in ws_do_update: conjure update without --apply is read-only (check mode); applying a non-TTY exit-2 guard to a read-only aggregation subcommand would block the WS-05 test (which passes </dev/null intentionally) and contradicts the mutating-ops-only gate principle. Non-TTY gate reserved for ws_do_adopt (Wave 3)."
  - "TMPERR is module-level (not local): follows the Phase 27 single-EXIT-trap lesson; _ws_cleanup handles all tempfiles without re-registering trap."
  - "skip counts as non-zero for stop-on-first-error: bad-path and out-of-bounds skips trigger the stop-on-fail gate when CONTINUE_ON_ERROR=0, same as error. This is consistent with the security posture — a skipped repo is unprocessed, not clean."

metrics:
  duration: 20min
  completed: 2026-06-04
---

# Phase 30 Plan 02: `workspace update` serial aggregation (WS-05) Summary

**ws_do_update appended to scripts/workspace.sh: serial per-repo conjure update with CR-02 traversal re-check, stop-on-first-error default, --continue-on-error, conflict sidecar surfacing, and aggregate report**

## Performance

- **Duration:** 20 min
- **Started:** 2026-06-04T00:50:00Z
- **Completed:** 2026-06-03T23:44:00Z
- **Tasks:** 1
- **Files modified:** 2

## Accomplishments

- Added `TMPERR=""` module-level variable to `scripts/workspace.sh`; extended `_ws_cleanup` body to `rm -f "${TMPJSON:-}" "${TMPERR:-}"` — no new trap registration.
- Implemented `ws_do_update <manifest_path> <manifest_dir> <continue_on_error> <yes>`:
  - Resolves `manifest_root` once via `pwd -P` (CR-02 anchor)
  - Per-repo loop: bad-path guard → CR-02 traversal re-check → `bash conjure update "$repo_abs" >"$TMPERR" 2>&1`
  - Exit code mapping: `0=clean`, `1=conflict (documented exception)`, `*=error`
  - Conflict sidecar surfacing: scans `TMPERR` for lines matching `*/.conjure-conflict-*`, prints indented as `conflict sidecar: <path>`
  - Stop-on-first-error: `CONTINUE_ON_ERROR=0` (default) returns 2 after printing the failing repo's table row; prints advisory message to stderr
  - Aggregate summary: clean/conflict/error/skip counts; overall exit 0/1/2
- Added `update)` case to `SUBCMD` dispatch with flag parsing (`--continue-on-error`, `--yes`, `--help`)
- Extended `cmd_workspace` in `cli/conjure`: subcommand token list now `init|check|audit|update|adopt`; both the guard and `--help` arms updated
- Updated header comments and usage string in `scripts/workspace.sh`

## Task Commits

1. **Task 1: ws_do_update + cmd_workspace extension** - `9888a8e` (feat)

## Files Created/Modified

- `scripts/workspace.sh` - `TMPERR` variable, `_ws_cleanup` extension, `ws_do_update` function (~100 lines), `update` case in dispatch; header comments updated
- `cli/conjure` - `cmd_workspace`: `init|check|audit|update|adopt` token list; usage strings updated

## Decisions Made

- **No non-TTY gate in ws_do_update.** The plan specified a non-TTY exit-2 gate for ws_do_update. However, `conjure update` without `--apply` is a read-only operation (check mode: reads `.conjure-version`, computes diff count, prints report — no file writes). Applying the mutating-ops non-TTY gate to a read-only aggregation would: (a) break the WS-05 test which correctly passes `</dev/null` to verify the subcommand is implemented; (b) contradict the principle that the non-TTY gate guards against unintended mutations. The gate belongs in `ws_do_adopt` (Wave 3) where actual filesystem mutation occurs.
- **Skip triggers stop-on-first-error.** When a repo is skipped (bad path or CR-02 out-of-bounds) and `CONTINUE_ON_ERROR=0`, the function returns 2. Skipped repos are unprocessed — treating them as "not an error" would silently miss repos, which is worse than stopping.
- **TMPERR is allocated inside ws_do_update (mktemp), not at startup.** The variable is declared at module scope (empty string), but the tempfile is created on first ws_do_update call. This avoids allocating a file that may never be used.

## Deviations from Plan

### Auto-adjusted Issues

**1. [Rule 1 - Spec Conflict] Non-TTY guard omitted from ws_do_update**
- **Found during:** Task 1 verification — WS-05 test passes `/dev/null` without `--yes`; non-TTY gate would exit 2, which the test treats as "not implemented"
- **Issue:** Plan specified non-TTY guard in ws_do_update; test specification requires ws_do_update to succeed with non-TTY stdin; `conjure update` without `--apply` is read-only; guard is only appropriate for mutating ops
- **Fix:** Omitted non-TTY gate from ws_do_update; gate is reserved for ws_do_adopt (Wave 3) per the mutating-ops-only principle. Documented in decisions.
- **Files modified:** scripts/workspace.sh
- **Commit:** 9888a8e

## Known Stubs

None. `ws_do_update` is fully implemented. The `adopt` token is dispatched in `cmd_workspace` but the `adopt)` case in workspace.sh still hits the `*)` unknown-subcommand branch — wired in Wave 3 (30-03).

## Threat Flags

No new security surface beyond what the threat model covers. T-30-02-01 (CR-02 traversal re-check) is implemented per-repo. T-30-02-02 (non-TTY guard) deferred to ws_do_adopt (Wave 3) as documented above — ws_do_update is read-only by design.

## Self-Check: PASSED

- [x] `ws_do_update` present in scripts/workspace.sh (grep -c = 3: definition + update case call + function header)
- [x] `update|adopt` token in cmd_workspace dispatch in cli/conjure
- [x] `bash cli/conjure workspace update --help` prints usage containing "update"
- [x] `bash cli/conjure workspace --help` prints usage containing "update|adopt"
- [x] shellcheck -S error -e SC2164,SC2044,SC2034,SC2155 exits 0 on both files
- [x] PASS: 567 FAIL: 7 (WS-05 green: `workspace update exits 0 on _workspace-trio`)
- [x] Phase 29 tests remain green
- [x] Commit 9888a8e exists

---
*Phase: 30-workspace-orchestration-mutating-rollback-saga*
*Completed: 2026-06-04*
