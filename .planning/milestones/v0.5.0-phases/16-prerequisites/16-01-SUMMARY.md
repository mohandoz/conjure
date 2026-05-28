---
phase: 16-prerequisites
plan: "01"
subsystem: lib/mutate.sh
tags: [mutate, dry-run, infrastructure, INFRA-01]
dependency_graph:
  requires: []
  provides: [mutate_rm]
  affects: [lib/merge.sh (Phase 18), scripts/init-overlay.sh]
tech_stack:
  added: []
  patterns: [DRY_RUN guard pattern, CONJURE_DRY_MUTATION_COUNT counter]
key_files:
  created: []
  modified:
    - lib/mutate.sh
    - tests/run.sh
decisions:
  - "No -r flag on mutate_rm: callers control recursive logic; Phase 18 only deletes individual sidecar files"
  - "mutate_rm placed between mutate_write and mutate_summary, consistent with sibling ordering"
metrics:
  duration: ~8 minutes
  completed: "2026-05-26T02:50:12Z"
---

# Phase 16 Plan 01: Add mutate_rm to lib/mutate.sh Summary

**One-liner:** Dry-run-safe `mutate_rm` primitive using the established `${DRY_RUN:-0}` guard pattern with counter increment, enabling Phase 18 (`conjure resolve`) to delete conflict sidecars through the mutation chokepoint.

## Tasks Completed

| # | Task | Commit | Files |
|---|------|--------|-------|
| 1 | Add mutate_rm to lib/mutate.sh | c1d5bd6 | lib/mutate.sh |
| 2 | Add mutate_rm regression tests | 8cbe37e | tests/run.sh |

## What Was Built

### lib/mutate.sh

Added `mutate_rm <path>` function placed between `mutate_write` and `mutate_summary`:

- DRY_RUN=1 path: echoes `[dry-run] would rm $1`, increments `CONJURE_DRY_MUTATION_COUNT` by 1, returns 0, filesystem unchanged
- DRY_RUN=0 path: executes `rm -f "$1"` (no `-r` flag; callers control recursive logic)
- DRY_RUN unset: treated as 0 via `${DRY_RUN:-0}` guard (same as sibling functions)
- Updated Usage comment block at top to include `mutate_rm <path>`
- Comment block style consistent with `mutate_cp`, `mutate_mkdir`, `mutate_write`

### tests/run.sh

Added `▸ mutate_rm unit tests (INFRA-01)` section inserted after the dry-run enforcement block (`trap - EXIT` line 222), before the migration coverage section:

- Sub-case 1 (dry-run): invokes mutate_rm in a subshell with DRY_RUN=1 on a nonexistent path; asserts output contains "would rm", counter=1, path still absent
- Sub-case 2 (live): creates real mktemp file, sources lib/mutate.sh, calls DRY_RUN=0 mutate_rm, asserts file is gone
- 4 new passing assertions; test suite total: 265 → 269 PASS, FAIL stays 0

## Verification Results

1. `bash tests/run.sh` exits 0, FAIL=0 (269 PASS) — confirmed
2. `grep -n 'mutate_rm' lib/mutate.sh` returns 4 lines (comment block, function def, echo, rm -f) — confirmed
3. `grep -c 'mutate_rm' tests/run.sh` returns 13 — confirmed (>= 4 required)
4. DRY_RUN=1 path: no filesystem mutation, prints "would rm" — confirmed
5. DRY_RUN=0 path: file deleted — confirmed

## Deviations from Plan

None — plan executed exactly as written.

## Threat Surface Scan

No new network endpoints, auth paths, file access patterns beyond plan scope, or schema changes. `mutate_rm` operates on caller-controlled paths at trust boundaries already described in the plan's threat model.

## Self-Check: PASSED

- lib/mutate.sh exists and contains mutate_rm: FOUND
- tests/run.sh mutate_rm section: FOUND (13 references)
- Commit c1d5bd6 exists: FOUND
- Commit 8cbe37e exists: FOUND
- Test suite: 269 PASS, 0 FAIL
