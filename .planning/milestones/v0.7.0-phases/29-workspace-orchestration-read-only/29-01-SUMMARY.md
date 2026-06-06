---
phase: 29-workspace-orchestration-read-only
plan: "01"
subsystem: workspace
tags: [workspace, manifest-validation, sibling-discovery, tty-gate, mutate_write]
dependency_graph:
  requires:
    - "29-00"
  provides:
    - lib/workspace.sh (workspace_manifest_validate, workspace_manifest_load, workspace_discover_siblings)
    - scripts/workspace.sh (init subcommand)
    - cli/conjure workspace) dispatch + cmd_workspace + usage line
  affects:
    - cli/conjure (new workspace) dispatch + cmd_workspace function + usage line)
    - tests/run.sh (WS-01 + WS-02 now green; WS-03 + WS-04 remain graceful-red pending Wave 2)
tech_stack:
  added: []
  patterns:
    - POSIX bash 3.2+ sourced library (lib/workspace.sh)
    - TTY-gated interactive prompt with /dev/tty (scripts/workspace.sh)
    - mutate_write chokepoint for filesystem writes
    - path traversal guard via subshell cd+pwd -P prefix check (no ../-counting)
    - cmd_* thin wrapper pattern forwarding "$@" verbatim to worker script
key_files:
  created:
    - lib/workspace.sh
    - scripts/workspace.sh
  modified:
    - cli/conjure (cmd_workspace function + workspace) dispatch + usage line)
decisions:
  - "cmd_workspace parses only subcommand (init|check|audit) + --dry-run; all other args forwarded verbatim — no --yes branch in cmd_workspace body"
  - "workspace_manifest_validate treats non-existent relative paths as safe (cd fails → skip); only rejects paths that resolve to outside workspace root"
  - "workspace_discover_siblings uses find -maxdepth 2 with sort -u to dedup symlinks"
  - "scripts/workspace.sh check + audit are exit-2 stubs for Wave 2; WS-03/04 tests remain graceful-red"
metrics:
  duration: "~15 minutes"
  completed_date: "2026-06-03"
  tasks_completed: 2
  files_created: 2
  files_modified: 1
---

# Phase 29 Plan 01: lib/workspace.sh manifest helpers + workspace init Summary

lib/workspace.sh delivers manifest validation with path traversal guard, sibling discovery, and parent-dir manifest walking; scripts/workspace.sh implements the TTY-gated workspace init subcommand; cli/conjure gains workspace) dispatch with a thin cmd_workspace wrapper that forwards all flags verbatim to the worker script.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | lib/workspace.sh manifest validation + sibling-discovery helpers | 7e96a0e | lib/workspace.sh (131 lines) |
| 2 | scripts/workspace.sh init + cli/conjure cmd_workspace dispatch | 1539cb5 | scripts/workspace.sh, cli/conjure |

## Test Results

- Pre-existing (Wave 0): PASS 541 FAIL 11 (all WS-* graceful-red)
- After Wave 1: PASS 548 FAIL 5
  - WS-01-manifest-valid: PASS
  - WS-01-manifest-invalid: PASS
  - WS-02-init-writes: PASS
  - WS-02-init-no-tty: PASS
  - WS-04-audit-fail: PASS (stub exits 2, test expects 2)
  - WS-04-audit-failfast: PASS (stub exits 2, test expects 2)
  - WS-03-check-table: FAIL (Wave 2 stub)
  - WS-03-check-fail-tolerant: FAIL (Wave 2 stub)
  - WS-03-check-badpath: FAIL (Wave 2 stub)
  - WS-04-audit-pass: FAIL (Wave 2 stub — test expects ≤1, stub exits 2)
  - WS-04-audit-badpath: FAIL (Wave 2 stub)

## Security: D-29 Threat Mitigations Applied

**T-29-01 (Non-TTY auto-write):** scripts/workspace.sh checks `[ -t 0 ]` before writing; exits 2 without writing if stdin is not a terminal and --yes not supplied. WS-02-init-no-tty validates this with `</dev/null` stdin.

**T-29-02 (Path traversal):** workspace_manifest_validate rejects absolute paths via `case "$rpath" in /*)` then resolves relative paths via `(cd "$manifest_dir/$rpath" && pwd -P)` and prefix-checks against `(cd "$manifest_dir/.." && pwd -P)`. Non-existent paths are safe (cd fails → skip). Only rejects paths that resolve outside workspace root.

**T-29-03 (CONJURE_HOME propagation):** cmd_workspace explicitly sets `CONJURE_HOME="$CONJURE_HOME"` in the subprocess invocation; scripts/workspace.sh has dirname fallback.

## Deviations from Plan

None — plan executed exactly as written. The WS-04-audit-fail and WS-04-audit-failfast tests passing with stubs is an artifact of the test expectations (exit 2) matching stub behavior, not an unplanned deviation.

## Known Stubs

- `scripts/workspace.sh check)` stub: exits 2 with "not yet implemented (Wave 2)" — Wave 2 plan (29-02) implements check
- `scripts/workspace.sh audit)` stub: exits 2 with "not yet implemented (Wave 2)" — Wave 2 plan (29-02) implements audit

These stubs intentionally keep WS-03 and WS-04 graceful-red pending Wave 2.

## Threat Flags

None — no new network endpoints or auth paths introduced. All filesystem writes route through mutate_write.

## Self-Check: PASSED

Files exist:
- lib/workspace.sh: FOUND
- scripts/workspace.sh: FOUND
- cli/conjure (workspace) dispatch): FOUND

Commits exist:
- 7e96a0e (lib/workspace.sh): FOUND
- 1539cb5 (scripts/workspace.sh + cli/conjure): FOUND
