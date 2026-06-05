---
phase: quick-260605-udi
plan: "01"
subsystem: scripts/refresh-graph.sh
tags: [graph, workspace, merge, cli]
dependency_graph:
  requires: []
  provides: [workspace-level-graph-merge]
  affects: [scripts/refresh-graph.sh, cli/conjure]
tech_stack:
  added: []
  patterns: [posix-bash-3.2, exit-2-never-1, stub-bin-smoke-test]
key_files:
  created:
    - tests/smoke-refresh-graph-merge.sh
  modified:
    - scripts/refresh-graph.sh
    - cli/conjure
decisions:
  - "Workspace merge uses graphify merge-graphs, not graphify global add — scope is workspace-level not machine-global"
  - "Three detection modes in priority order: manifest (.conjure-workspace.json) > manifest-less workspace (not-git + >=2 child .git dirs) > single git repo (info + exit 0)"
  - "Mode A uses jq to parse .repos[].path; Mode B uses POSIX glob for ./*/ with -d guard; POSIX bash 3.2+ throughout"
  - "Smoke test placed in tests/ as a reusable regression asset and accepts CONJURE_HOME env var for portability"
metrics:
  duration: "~10 minutes"
  completed: "2026-06-05T18:59:35Z"
  tasks_completed: 3
  tasks_total: 3
  files_created: 1
  files_modified: 2
---

# Phase quick-260605-udi Plan 01: Global Graph Merge Made Opt-In via --merge Summary

**One-liner:** Replaced `graphify global add` (machine-wide side-effect in `--setup`) with a new `--merge` flag that runs `graphify merge-graphs` at workspace scope using three detection modes.

## What Was Built

### Task 1 — scripts/refresh-graph.sh rewrite

- Removed Step 2 (global merge via `graphify global add`) from the `--setup` block; renumbered remaining setup steps 1-3.
- Added `DO_MERGE=0` variable and `--merge) DO_MERGE=1 ;;` case to the POSIX arg parser.
- Added a new `--merge` block after `--setup` implementing three detection modes:
  - **Mode A** (.conjure-workspace.json exists): reads member paths via `jq -r '.repos[].path'`, accumulates graph paths via positional params (`set --`), calls `graphify merge-graphs` if >=2 graphs found.
  - **Mode B** (cwd not a git repo, >=2 child dirs with .git): discovers child repos via POSIX glob `for _d in ./*/ ; do ... done`, same accumulate-and-merge pattern.
  - **Mode C** (cwd is a git repo): prints info message and exits cleanly, no merge call.
- `graphify global add` is absent from the entire file.
- Updated comment header to document `[--merge]` flag.
- shellcheck passes with zero errors.

### Task 2 — cli/conjure usage lines

- Updated top-of-file comment block line 13: added `[--merge]` to `refresh-graph` usage.
- Updated `usage()` function line 48: same addition.
- Zero occurrences of `--merge-global` in the file.

### Task 3 — Smoke tests

- Created `tests/smoke-refresh-graph-merge.sh` with four scenarios:
  - (a) `--setup` calls no `global add` or `merge-graphs` — PASS
  - (b) `--merge` with `.conjure-workspace.json` + 2 member graphs calls `merge-graphs` with both paths — PASS
  - (c) `--merge` inside a single git repo prints "single repo" message without calling `merge-graphs` — PASS
  - (d) `--merge` with only 1 member graph found prints "fewer than 2" warning and skips — PASS
- Test uses stub executables in `$TMPDIR/bin` (graphify, jq, git); accepts `CONJURE_HOME` env var for portability when run from `$TMPDIR`.

## Verification Results

| Check | Result |
|-------|--------|
| `shellcheck -S error -e SC2164,SC2044,SC2034,SC2155 scripts/refresh-graph.sh` | PASS (exit 0) |
| `grep "global add" scripts/refresh-graph.sh` | PASS (no output) |
| `--setup` block contains no `merge-graphs` call | PASS |
| `--merge` block calls `graphify merge-graphs` | PASS |
| `grep "merge-global" cli/conjure` | PASS (no output) |
| `grep -c "\-\-merge" cli/conjure` | PASS (2 occurrences) |
| Smoke test all 4 scenarios | PASS (exit 0) |

## Commits

| Hash | Message |
|------|---------|
| 4077d3c | feat(quick-260605-udi-01): replace --merge-global with --merge (workspace-level) |
| ded3cc9 | docs(quick-260605-udi-01): update cli/conjure usage to document --merge flag |
| 621ef72 | test(quick-260605-udi-01): smoke tests for --merge three-mode detection and --setup cleanliness |

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Smoke test script discovery when run from $TMPDIR**
- **Found during:** Task 3
- **Issue:** The smoke test used `$(dirname "$0")/..` to locate `scripts/refresh-graph.sh`, which fails when the script is copied to `$TMPDIR`.
- **Fix:** Added multi-fallback discovery: `CONJURE_HOME` env var first, then `dirname "$0"` relative path, then upward cwd search. Allows `CONJURE_HOME=<repo> bash $TMPDIR/refresh-graph-smoke.sh` as required by the plan's verification step.
- **Files modified:** `tests/smoke-refresh-graph-merge.sh`
- **Commit:** 621ef72

### Verification Check 3 False Positive

The plan's verification check 3 (`grep -A 40 'DO_SETUP.*=.*1' | grep -c "merge-graphs"`) returns 2, not 0, because the `-A 40` context window extends past the end of the `--setup` block and into the `--merge` block (which legitimately calls `merge-graphs`). The `--setup` block itself (lines 108-129) contains zero `merge-graphs` calls — verified with `sed -n '108,129p' | grep "merge-graphs"` returning empty.

## Known Stubs

None. No UI rendering or data-flow stubs introduced.

## Threat Flags

None. Changes are confined to shell flag handling and subprocess invocation. Member paths from `.conjure-workspace.json` are used only as file existence checks and CLI args; no eval or unquoted expansion.

## Self-Check: PASSED

- `scripts/refresh-graph.sh` — exists, shellcheck passes, `global add` absent
- `cli/conjure` — exists, `merge-global` absent, 2 `--merge` occurrences
- `tests/smoke-refresh-graph-merge.sh` — exists, all 4 scenarios PASS
- Commits 4077d3c, ded3cc9, 621ef72 — all present in git log
