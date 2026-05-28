---
phase: 18-conflict-resolution
plan: "02"
subsystem: resolve-cli
tags: [bash, cli, dispatch, regression-tests, conflict-resolution]
dependency_graph:
  requires: [scripts/resolve.sh, lib/mutate.sh]
  provides: [cli/conjure cmd_resolve, tests/run.sh RESOLVE section]
  affects: [cli/conjure (usage + dispatch), tests/run.sh]
tech_stack:
  added: []
  patterns: [cmd_resolve-delegates-to-script, CONJURE_FORCE_INTERACTIVE-test-escape-hatch, DRIFT-test-idiom-replicated]
key_files:
  created: []
  modified: [cli/conjure, tests/run.sh]
decisions:
  - "cmd_resolve mirrors cmd_check exactly: local vars + while loop arg parsing + env-forwarded bash exec to script"
  - "RESOLVE test sub-cases RESOLVE-02b and RESOLVE-02c invoke scripts/resolve.sh directly (not via cli/conjure) with CONJURE_FORCE_INTERACTIVE=1 to bypass TTY guard in CI"
  - "RESOLVE-02a uses </dev/null because all-clear path exits before TTY guard — no CONJURE_FORCE_INTERACTIVE needed"
  - "7 pass/fail assertions generated from 4 sub-cases: RESOLVE-01a(1), RESOLVE-02a(2), RESOLVE-02b(2), RESOLVE-02c(2)"
metrics:
  duration: "~2 minutes"
  completed: "2026-05-26"
  tasks_completed: 2
  tasks_total: 2
  files_created: 0
  files_modified: 2
---

# Phase 18 Plan 02: cmd_resolve CLI Wiring + RESOLVE Regression Tests — Summary

**One-liner:** Wired `conjure resolve` dispatch into cli/conjure and added 4-case RESOLVE regression test section to tests/run.sh, bringing total suite to 291 PASS / 0 FAIL.

## What Was Built

**cli/conjure** — `cmd_resolve` function added immediately after `cmd_check` (line 175):
- Parses `--dry-run` and `--help|-h` flags, defaulting target to `$(pwd)`
- Forwards `CONJURE_HOME` and `DRY_RUN` env vars to `scripts/resolve.sh` via `bash` exec
- Usage line `conjure resolve [--dry-run] [target]` added to `usage()` after `conjure check`
- Dispatch entry `resolve)` added adjacent to `check)` in the case block

**tests/run.sh** — RESOLVE section inserted between the DRIFT-02 cleanup and the summary block:
- `RESOLVE-01a`: piped stdin (`</dev/null`, no `CONJURE_FORCE_INTERACTIVE`) with sidecars present → `cli/conjure resolve` exits 2 (non-interactive guard)
- `RESOLVE-02a`: empty dir via `</dev/null` → exits 0, prints "No conflicts remain" (all-clear before TTY guard)
- `RESOLVE-02b`: `CONJURE_FORCE_INTERACTIVE=1` + `printf 'k\n'` → sidecar removed, current file unchanged
- `RESOLVE-02c`: `CONJURE_FORCE_INTERACTIVE=1` + `printf 'a\n'` → current file replaced with sidecar content, sidecar removed

## Verification Results

All acceptance criteria passed:

- `bash -n cli/conjure` — PASS
- `bash -n tests/run.sh` — PASS
- `grep cmd_resolve cli/conjure` — PASS
- `grep 'resolve)' cli/conjure` — PASS
- `CONJURE_HOME="$(pwd)" cli/conjure resolve --help` — prints usage, exits 0 — PASS
- `bash tests/run.sh`: 291 PASS, 0 FAIL — PASS
- RESOLVE passing tests: 7 — PASS

## Deviations from Plan

None — plan executed exactly as written. `scripts/resolve.sh` was not modified.

## Known Stubs

None.

## Threat Flags

No new security-relevant surface. `cmd_resolve` forwards user-controlled `target` path to `scripts/resolve.sh` as positional arg — identical trust boundary to `cmd_check`. No new network endpoints, auth paths, or schema changes.

## Self-Check: PASSED

- `cli/conjure` contains `cmd_resolve` and `resolve)` dispatch entry
- `tests/run.sh` contains RESOLVE section with header "▸ Conflict resolution tests (RESOLVE-01, RESOLVE-02)"
- Commit `4b5433b` present in git log (Task 1)
- Commit `599f967` present in git log (Task 2)
- `bash tests/run.sh`: 291 PASS, 0 FAIL verified
