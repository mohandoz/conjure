---
phase: 09-3-way-merge
plan: "01"
subsystem: merge-library
tags: [merge, bash, lib, shellcheck, ci]
dependency_graph:
  requires: [lib/mutate.sh]
  provides: [lib/merge.sh — merge_file_3way, write_merge_sidecar, merge_user_files]
  affects: [.github/workflows/ci.yml, cli/conjure (plans 02-03)]
tech_stack:
  added: []
  patterns: [sourced-bash-library, posix-safe-find-mktemp, mutate_write-chokepoint]
key_files:
  created:
    - lib/merge.sh
  modified:
    - .github/workflows/ci.yml
decisions:
  - "POSIX-safe find loops via mktemp temp files (not process substitution) — bash 3.2 compat"
  - "All SC2155 compliance via two-line local+assignment pattern"
  - "Conditional-space expansion for CONJURE_MERGE_CONFLICT_FILES avoids leading space"
  - "write_merge_sidecar delegates to mutate_write for dry-run safety (not direct printf)"
metrics:
  duration: "~15 min"
  completed: "2026-05-25"
  tasks_completed: 3
  files_created: 1
  files_modified: 1
requirements:
  - MERGE-01
  - MERGE-03
---

# Phase 09 Plan 01: 3-Way Merge Library Summary

**One-liner:** Created lib/merge.sh with merge_file_3way (git merge-file rc-dispatched), write_merge_sidecar (mutate_write-based dry-run-safe sidecar), and merge_user_files (POSIX mktemp find loop iterator for CLAUDE.md, skills, agents, hooks).

## What Was Built

`lib/merge.sh` — a sourced bash library (no shebang) that implements the 3-way merge core for `cmd_update --apply`. Follows the exact structural pattern of `lib/mutate.sh`.

### Functions Implemented

**merge_file_3way(current, base, new, rel, pinned_ver, new_ver)**
- Calls `git merge-file -p --diff3` with `-L` labels for readable conflict markers
- Argument order verified: current (ours) / base (ancestor/middle) / new (upstream)
- rc=0: clean merge → `mutate_write $current $merged` (update in place)
- rc=1-127: conflict → `write_merge_sidecar` (original untouched per D-05)
- rc=255: hard error → stderr message, return 2

**write_merge_sidecar(current_file, rel, content)**
- Encodes relative path via `tr '/' '_'`, prefixes `.conjure-conflict-`
- Sidecar placed next to original file in same directory (D-04)
- Writes via `mutate_write` (not direct printf) — DRY_RUN handled by mutate_write
- Tracks `CONJURE_MERGE_CONFLICT_COUNT` and `CONJURE_MERGE_CONFLICT_FILES` with conditional-space expansion (`:+` pattern, no leading space)

**merge_user_files(target, snap_dir, conjure_ver, pinned_ver)**
- Resets conflict tracking at start
- Handles: CLAUDE.md template (single file), skills (SKILL.md), agents (*.md), hooks (*.mjs)
- All find loops use `mktemp` temp files (POSIX bash 3.2 safe; no `< <(find ...)` process substitution)
- Aborts immediately with rc=2 on any git error; rc=1 conflicts tracked in module vars

### CI Update

`.github/workflows/ci.yml` shellcheck glob extended: added `lib` at the end of the directory list after `tests`. This ensures `lib/merge.sh`, `lib/mutate.sh`, and `lib/cost.sh` are all covered by shellcheck on every PR.

## Deviations from Plan

None — plan executed exactly as written.

## Shellcheck Compliance

Shellcheck is not installed locally (darwin CI install only). Manual review confirmed:
- No SC2155 violations: all `local a="$(cmd)"` patterns use two-line form: `local a; a="$(cmd)"`
- No SC2044 violations: all find output consumed via `while IFS= read -r` from mktemp temp file
- No SC2034 violations: all declared locals are referenced
- No SC2164 violations: no `cd` calls in the library

CI will run shellcheck on ubuntu-latest with `shellcheck -S error -e SC2164,SC2044,SC2034,SC2155`.

## Threat Model Check

- T-09-01 (argument order tampering): mitigated — argument order is current/base/new per git-merge-file convention, documented in function comment
- T-09-02 (rc=255 DoS): mitigated — rc=255 branch returns 2 and callers abort immediately
- T-09-03 (sidecar path traversal): accepted — `rel` derived from trusted CONJURE_HOME/templates/ find output

## Known Stubs

None — all three public functions are fully implemented, not stubbed.

## Self-Check: PASSED

| Check | Result |
|-------|--------|
| lib/merge.sh exists | PASS |
| source lib/mutate.sh; source lib/merge.sh — all 3 functions defined | PASS |
| write_merge_sidecar uses mutate_write (not printf direct) | PASS |
| mktemp appears in all 3 find loops | PASS |
| CONJURE_MERGE_CONFLICT_FILES uses :+ conditional expansion | PASS |
| CI glob includes "lib" at end after "tests" | PASS |
| git log shows commit 7bff134 with lib/merge.sh and ci.yml | PASS |
| min_lines (60) satisfied — 163 lines | PASS |
