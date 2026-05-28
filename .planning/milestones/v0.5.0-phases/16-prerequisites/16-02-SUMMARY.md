---
phase: 16-prerequisites
plan: "02"
subsystem: testing
tags: [bash, publish-skill, cli, regression-tests, debt]

# Dependency graph
requires:
  - phase: 16-prerequisites-01
    provides: lib/mutate.sh with mutate_rm function

provides:
  - scripts/publish-skill.sh accepting positional $2 as org/repo (DEBT-02)
  - SKILL-05 regression test block covering positional arg, deprecation warn, missing-both-exit-2, and priority behavior

affects: [phase-19-auto-pr, any caller of publish-skill.sh]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "REPO_FROM_POS flag tracks source of TARGET_REPO to distinguish positional vs env vs --to"
    - "TARGET_REPO_ENV captures env at script start; deprecation fires only when env was set and positional absent"

key-files:
  created: []
  modified:
    - scripts/publish-skill.sh
    - tests/run.sh

key-decisions:
  - "DEBT-02 resolved: positional $2 accepted with priority over TARGET_REPO env; hardcoded mohandoz/conjure default removed"
  - "Deprecation fires only for env path (not --to flag) by tracking TARGET_REPO_ENV separately"
  - "SKILL-01/02/03 existing tests updated to pass myorg/myrepo as positional $2"

patterns-established:
  - "Pattern: track env-vs-positional source with REPO_FROM_POS + TARGET_REPO_ENV for clean deprecation logic"

requirements-completed: [DEBT-02]

# Metrics
duration: 15min
completed: 2026-05-26
---

# Phase 16 Plan 02: Prerequisites — publish-skill.sh Positional Arg Summary

**publish-skill.sh refactored to accept org/repo as positional $2 per DEBT-02; hardcoded mohandoz/conjure default removed; TARGET_REPO env triggers WARN: deprecation to stderr; SKILL-05 regression block added (7 assertions, all passing)**

## Performance

- **Duration:** ~15 min
- **Started:** 2026-05-26T05:40:00Z
- **Completed:** 2026-05-26T05:55:00Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments

- Removed hardcoded `TARGET_REPO=mohandoz/conjure` default from publish-skill.sh
- Added positional $2 consumption (REPO_FROM_POS=1) before the while loop so flags after the positional parse correctly
- Added deprecation warning when TARGET_REPO env is used without positional $2 (prints WARN: to stderr only)
- Missing both positional $2 and env now exits 2 with updated usage line
- --to flag path unchanged and backwards compatible (no spurious deprecation warning)
- Updated SKILL-01/02/03 test calls to use new positional interface (7 call sites updated)
- Added SKILL-05 block with 7 passing assertions covering all new behaviors
- Full test suite: 276 PASS, 0 FAIL

## Task Commits

Each task was committed atomically:

1. **Task 1: Refactor publish-skill.sh** - `60f3b28` (feat)
2. **Task 2: Add SKILL-05 regression tests** - `a4da3f8` (test)

## Files Created/Modified

- `scripts/publish-skill.sh` - Positional $2 arg parsing, deprecation warn, removed mohandoz/conjure default, updated usage text
- `tests/run.sh` - SKILL-05 block (7 sub-cases), SKILL-01/02/03 calls updated to pass positional repo

## Decisions Made

- Track env source via `TARGET_REPO_ENV` captured at script start; deprecation check uses `TARGET_REPO_ENV` not `TARGET_REPO` so `--to` flag does not trigger spurious deprecation warning
- REPO_FROM_POS=0/1 flag controls whether deprecation fires, giving clear separation of positional vs env path
- Existing SKILL-01/02/03 test calls updated inline (not wrapped in TARGET_REPO env) since they should exercise the new preferred interface

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Spurious deprecation WARN would have fired for --to flag path**
- **Found during:** Task 1 (refactoring publish-skill.sh)
- **Issue:** Plan specified tracking REPO_FROM_POS and checking `[ -n "$TARGET_REPO" ]` after the while loop. But when `--to` sets TARGET_REPO inside the while loop (from empty), the deprecation guard would also fire since REPO_FROM_POS=0 and TARGET_REPO is non-empty after `--to`.
- **Fix:** Captured `TARGET_REPO_ENV="${TARGET_REPO:-}"` before any arg processing; deprecation guard checks `TARGET_REPO_ENV` (the original env value) instead of `TARGET_REPO` (which may have been set by `--to`).
- **Files modified:** scripts/publish-skill.sh
- **Verification:** SKILL-04 (--to flag) passes without WARN; SKILL-05d (positional priority) passes without WARN
- **Committed in:** 60f3b28

---

**Total deviations:** 1 auto-fixed (Rule 1 - Bug)
**Impact on plan:** Essential correctness fix — --to backward compatibility would have broken. No scope creep.

## Issues Encountered

None beyond the deviation above.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- DEBT-02 fully resolved; Phase 19 Auto-PR can now pass `org/repo` as positional $2
- All SKILL-01 through SKILL-05 pass; publish-skill.sh interface is clean and documented
- No blockers

## Self-Check: PASSED

- scripts/publish-skill.sh: FOUND
- tests/run.sh: FOUND
- 16-02-SUMMARY.md: FOUND
- Commit 60f3b28: FOUND
- Commit a4da3f8: FOUND
- No hardcoded mohandoz/conjure default: VERIFIED
- SKILL-05 occurrences in tests/run.sh: 19 (>= 4 required)
- REPO_FROM_POS occurrences in publish-skill.sh: 3 (>= 2 required)

---
*Phase: 16-prerequisites*
*Completed: 2026-05-26*
