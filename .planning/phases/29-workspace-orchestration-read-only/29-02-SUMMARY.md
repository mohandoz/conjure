---
phase: 29-workspace-orchestration-read-only
plan: "02"
subsystem: workspace
tags: [workspace, check, audit, jq, fail-tolerant, exit-semantics, subprocess]
dependency_graph:
  requires:
    - "29-01"
  provides:
    - scripts/workspace.sh (check and audit subcommands — ws_do_check, ws_do_audit)
    - cli/conjure (usage updated to include workspace check and workspace audit)
  affects:
    - Phase 30 workspace-mutating (workspace check/audit primitives now stable; Phase 30 can proceed)
tech_stack:
  added: []
  patterns:
    - Fail-tolerant aggregate: per-repo exit 2 maps to overall exit 1 (partial-success, SC-mandated documented exception)
    - Single EXIT trap pattern: TMPJSON declared at script top level, _ws_cleanup handles all tempfiles
    - Argv-flag subprocess invocation: --porcelain and --json passed as flags, NOT env vars (cmd_check/cmd_audit override env)
    - jq JSON validation before .status parse (jq empty guard prevents injection on malformed output)
key_files:
  created: []
  modified:
    - scripts/workspace.sh (ws_do_check + ws_do_audit + check)/audit) dispatch cases)
    - cli/conjure (usage() updated with workspace check + workspace audit lines)
key-decisions:
  - "Per-repo exit 2 from conjure check → overall exit 1 (fail-tolerant aggregate, not hard failure); only invalid manifest = exit 2 from workspace check"
  - "ws_do_audit does NOT register its own EXIT trap — script-level TMPJSON + _ws_cleanup (Phase 27 single-trap lesson)"
  - "--porcelain and --json passed as argv flags to per-repo conjure invocations (not env vars), because cmd_check/cmd_audit initialize flags=0 from their own argv on every invocation"
  - "Bad-path repos: skip with warning to stderr + OVERALL_RC=1 + continue (never abort); audit bad-path is SKIP (no count toward fail)"
  - "workspace audit --fail-fast: return 2 immediately on first fail (no summary printed)"

requirements-completed: [WS-03, WS-04]

duration: ~20min
completed: 2026-06-03
---

# Phase 29 Plan 02: workspace check + workspace audit subcommands Summary

**Per-repo check aggregation (WS-03) and audit aggregation (WS-04) using fail-tolerant exit semantics, argv-flag subprocess invocation, and a single script-level EXIT trap for TMPJSON cleanup.**

## Performance

- **Duration:** ~20 min
- **Started:** 2026-06-03T21:30:00Z
- **Completed:** 2026-06-03T21:50:00Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments

- `workspace check` runs `conjure check --porcelain` per repo (manifest order); emits REPO|STATUS|EXIT table; exits 0 (all clean) or 1 (any drift/error/skip — partial-success); bad-path repos skip with warning; per-repo exit 2 maps to overall exit 1
- `workspace audit` runs `conjure audit --json` per repo; parses `.status` via jq; emits per-repo table + global Pass/Warn/Fail/Skip summary; exit semantics: fail→2, warn-only→1, all-pass→0; `--fail-fast` aborts at first fail; bad-path repos skipped with warning
- cli/conjure usage updated to document `conjure workspace check` and `conjure workspace audit`
- All 553 tests pass (FAIL: 0), including all 7 WS-03 and WS-04 test cases

## Task Commits

Each task was committed atomically:

1. **Task 1: workspace check subcommand (WS-03)** - `0ac5a3c` (feat)
2. **Task 2: workspace audit subcommand + cli/conjure usage update (WS-04)** - `d72fd35` (feat)

## Files Created/Modified

- `scripts/workspace.sh` — Added `ws_do_check`, `ws_do_audit` functions and `check)` / `audit)` dispatch cases; TMPJSON declared at script top level with `_ws_cleanup` EXIT trap
- `cli/conjure` — Updated `usage()` to include workspace check and workspace audit usage lines

## Decisions Made

- Argv-flag form (`bash "$CONJURE_HOME/cli/conjure" check --porcelain "$repo_abs"`) is the only correct per-repo invocation — cmd_check/cmd_audit initialize `porcelain=0` / `do_json=0` from their own argv, overriding any inherited env var
- ws_do_audit allocates TMPJSON at function entry but the variable is declared at script top level; `_ws_cleanup` handles it on EXIT — no per-function trap (Phase 27 lesson: second `trap ... EXIT` silently clobbers the script-level trap)
- Bad-path in workspace audit does not increment fail_count (it's a SKIP); overall exit depends only on repos that were actually audited

## Deviations from Plan

None — plan executed exactly as written. All invariants and key implementation notes from the plan were followed precisely.

## Security: Threat Mitigations Applied

**T-29-03 (Exit-code laundering — false negative):** ws_do_audit maps `status:"fail"` → OVERALL_RC=2 unconditionally; jq parse failure → `TABLE_STATUS="error($repo_rc)"` → fail_count++ → OVERALL_RC=2. No path exists where a failing repo produces exit 0.

**T-29-04 (CONJURE_JSON/CONJURE_PORCELAIN env leakage):** Flags passed as argv to per-repo conjure invocations; cmd_check/cmd_audit reset to 0 on every invocation — env var inheritance is impossible with this call form.

**T-29-05 (Bad-path DoS):** `[ -d "$repo_abs" ]` guard before any subprocess call; missing dir → SKIP with warning + continue loop.

**T-29-06 (Status injection):** REPO_STATUS parsed via `jq -r '.status'`; case block matches only `pass|warn|fail`; unrecognized values fall through to error branch.

## Known Stubs

None — all workspace subcommands (init, check, audit) are fully implemented.

## Threat Flags

None — no new network endpoints, auth paths, or trust boundaries introduced.

## Self-Check: PASSED

Files exist:
- scripts/workspace.sh (ws_do_check + ws_do_audit): FOUND
- cli/conjure (workspace check + audit usage lines): FOUND

Commits exist:
- 0ac5a3c (feat(29-02): workspace check subcommand): FOUND
- d72fd35 (feat(29-02): workspace audit subcommand + cli usage): FOUND

Test results: PASS 553, FAIL 0 (all WS-03 + WS-04 tests green)
