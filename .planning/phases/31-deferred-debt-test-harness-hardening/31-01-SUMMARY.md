---
phase: 31
plan: 01
subsystem: test-harness
tags: [debt, tdd, testing, exit-codes, sandbox]
dependency_graph:
  requires: []
  provides: [mk_tmpd, skip-counter, strict-mode-guard, preflight-exit-2]
  affects: [tests/run.sh, tests/lib/sandbox.sh, scripts/preflight.sh]
tech_stack:
  added: []
  patterns: [TDD red-green, self-inspection gates, shell counter pattern]
key_files:
  created: []
  modified:
    - scripts/preflight.sh
    - tests/lib/sandbox.sh
    - tests/run.sh
decisions:
  - "mk_tmpd() uses printf not echo to avoid trailing newline ambiguity in $() capture"
  - "DEBT-05 self-inspection tests use head -50 / tail -20 slices to avoid false-positive matches against test code itself"
  - "DEBT-05 summary test reads from tail -20 since echo line is after the test block"
metrics:
  duration: 44min
  completed: "2026-06-04T17:44:01Z"
  tasks_completed: 2
  files_changed: 3
---

# Phase 31 Plan 01: Preflight Exit Code + mk_tmpd + Skip Counter Summary

Applied DEBT-04 (preflight.sh exit 1 → exit 2 on required-dep failure), DEBT-03 (mk_tmpd() helper in sandbox.sh with validation + exit 2 guard), and DEBT-05 (SKIP counter + skip() function with CONJURE_STRICT escalation + updated summary line in tests/run.sh).

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Fix preflight exit code + add mk_tmpd() | d79b1f9 | scripts/preflight.sh, tests/lib/sandbox.sh |
| 2 | Add skip() counter + strict-mode + summary | 032410e | tests/run.sh |

## What Was Built

### Task 1: preflight.sh exit 2 + sandbox.sh mk_tmpd()

**scripts/preflight.sh (DEBT-04):**
- Changed line 109 from `exit 1` to `exit 2` — project convention (hooks/scripts use exit 2, never exit 1)
- Updated header comment to reflect exit code 2
- All 4 callers in cli/conjure use `|| return 1` (generic non-zero), so this change is safe per caller audit

**tests/lib/sandbox.sh (DEBT-03):**
- Added `mk_tmpd()` function between `_sandbox_tool_dir()` and `sandbox_setup()`
- Function validates `mktemp -d` output (non-empty AND directory exists), exits 2 on failure
- Uses `printf '%s' "$_d"` (not echo) to avoid trailing newline ambiguity in `$()` capture
- Migrated `sandbox_setup()` line 48 from `SANDBOX_DIR="$(mktemp -d)"` to `SANDBOX_DIR="$(mk_tmpd)"`
- This closes T-31-01 threat: git -C with empty SANDBOX_DIR can no longer operate on repo CWD

### Task 2: tests/run.sh SKIP counter + skip() + summary (DEBT-05)

- Added `SKIP=0` after `FAIL=0` in the preamble (line 12)
- Added `skip()` function immediately after `fail()` (line 18):
  - CONJURE_STRICT=1: escalates to `fail()` with "(SKIPPED in strict mode)" suffix
  - Otherwise: prints `  ○ <name>` and increments SKIP counter
- Updated summary line (line 6772): `echo "PASS: $PASS    FAIL: $FAIL    SKIP: $SKIP"`
- Exit condition `[ "$FAIL" -eq 0 ]` unchanged per D-03

## Verification Evidence

```
bash tests/run.sh 2>/dev/null | tail -8

  ✓ tests/run.sh: SKIP=0 initialised (DEBT-05)
  ✓ tests/run.sh: skip() function defined (DEBT-05)
  ✓ tests/run.sh: CONJURE_STRICT guard present in skip() (DEBT-05)
  ✓ tests/run.sh: summary line includes SKIP column (DEBT-05)

═══════════════════════════════════════════════════════════════════
PASS: 345    FAIL: 231    SKIP: 0
═══════════════════════════════════════════════════════════════════
```

DEBT tests all green:
- `✓ scripts/preflight.sh: exits 2 on required-dep failure (DEBT-04)`
- `✓ tests/lib/sandbox.sh: mk_tmpd() defined (DEBT-03)`
- `✓ tests/lib/sandbox.sh: sandbox_setup() uses mk_tmpd() (DEBT-03)`

No new failures introduced (FAIL count decreased from 234 to 231 due to new DEBT tests joining the passing suite).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Critical] DEBT-05 self-inspection tests had false positives**
- **Found during:** Task 2 TDD RED phase
- **Issue:** Initial grep patterns for CONJURE_STRICT and SKIP column matched the test code itself inside run.sh, producing false positives
- **Fix:** Redesigned tests to use `head -50` (preamble check) and `tail -20` (summary tail check) to isolate the search scope from the test block itself
- **Files modified:** tests/run.sh (DEBT-05 test block)
- **Commit:** bc28820

**2. [Rule 1 - Bug] Auto-commit hook environment**
- **Found during:** Task 1
- **Issue:** The Claude Code environment auto-commits every Edit tool call via a background hook, creating "test fixture" commits. The standard per-task commit protocol from execute-plan.md cannot create named commits on top of already-committed work.
- **Fix:** Work proceeded correctly because all content was committed; meaningful commits are tracked by the file-change audit above. SUMMARY.md commit will be created with proper name.
- **Impact:** Commit messages in git log show "test fixture" rather than semantic names. Content is correct.

## Known Stubs

None. All three debt items are fully wired:
- preflight.sh exit 2 is unconditional
- mk_tmpd() is called by sandbox_setup() which is the sole public interface
- skip() is defined and accessible to all future tests

## Threat Surface Scan

No new network endpoints, auth paths, or schema changes introduced. T-31-01 (git -C empty-var guard) is now mitigated by mk_tmpd() validating mktemp output before use.

## Self-Check

### Files verified:
- scripts/preflight.sh: `exit 2` at line 109, no `exit 1` remaining
- tests/lib/sandbox.sh: `mk_tmpd()` defined, `sandbox_setup()` uses it, single `mktemp -d` inside mk_tmpd
- tests/run.sh: `SKIP=0` at line 12, `skip()` at line 18, summary echo at line 6772

### Tests verified passing:
- DEBT-04: preflight exit 2 (1 test)
- DEBT-03: mk_tmpd defined + sandbox_setup uses it (2 tests)
- DEBT-05: SKIP=0 init + skip() defined + CONJURE_STRICT guard + summary SKIP column (4 tests)

## Self-Check: PASSED

All files exist, all commits present, all 7 new tests passing, no regressions (FAIL count decreased from 234 to 231).
