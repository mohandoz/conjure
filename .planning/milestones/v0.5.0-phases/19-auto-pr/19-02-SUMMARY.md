---
phase: 19-auto-pr
plan: 02
subsystem: tests
tags: [bash, regression-tests, stub-bins, autpr, gh-mock]

# Dependency graph
requires:
  - phase: 19-auto-pr
    plan: 01
    provides: conjure update --pr and --cron implementations
provides:
  - AUTPR regression test section in tests/run.sh
  - 11 new assertions covering AUTPR-01 and AUTPR-02 behaviors
affects: [phase-20-final-release]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "stub gh binary placed at PATH head with mktemp -d; cleaned up after each sub-test"
    - "FILTERED_PATH pattern: strips real gh directory from PATH for missing-gh guard tests"
    - "zero-drift test requires stub gh because --pr checks gh presence before zero-drift check"

key-files:
  created: []
  modified:
    - tests/run.sh

key-decisions:
  - "AUTPR-01a needs a stub gh binary (not a bare conjure invocation) because cmd_update --pr performs the gh guard before the zero-drift guard"

# Metrics
duration: 5min
completed: 2026-05-26
---

# Phase 19 Plan 02: AUTPR Regression Tests Summary

**11 AUTPR-tagged assertions added to tests/run.sh; all 302 tests pass (FAIL: 0); stub binaries used for isolated gh behaviour across zero-drift, missing-gh, idempotency, and cron-write scenarios**

## Performance

- **Duration:** ~5 min
- **Started:** 2026-05-26T05:40:00Z
- **Completed:** 2026-05-26T05:45:00Z
- **Tasks:** 1
- **Files modified:** 1

## Accomplishments

- AUTPR-01a: zero-drift guard — stub gh (no-op) + fully-current harness → "Harness is current" + exit 0 (2 assertions)
- AUTPR-01b: missing-gh guard — FILTERED_PATH strips gh directory → exit 2 + "gh CLI required" (2 assertions)
- AUTPR-01c: idempotency — stub gh pr list prints fake URL → exit 0 + URL in output (2 assertions)
- AUTPR-02a: cron template write — file exists + "0 9 * * 1" schedule + "conjure update --pr" invocation (4 assertions)
- AUTPR-02b: cron idempotency — second run exits 0 (1 assertion)
- Total: 11 assertions; overall suite: PASS 302, FAIL 0

## Task Commits

1. **Task 1: Add AUTPR regression tests to tests/run.sh** - `8f3bb25` (test)

## Files Created/Modified

- `tests/run.sh` — Added AUTPR section (131 lines) immediately before the summary block

## Decisions Made

- AUTPR-01a requires a stub `gh` no-op binary placed on PATH because `cmd_update --pr` guards against missing `gh` *before* the zero-drift check. Without a stub, the test would hit the missing-gh exit-2 path rather than the zero-drift path. This deviation from the original plan description (which said "does NOT need a stub for gh") was auto-fixed by Rule 1 (incorrect behavior otherwise).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] AUTPR-01a required a stub gh despite plan comment saying it did not**
- **Found during:** Task 1 (first test run)
- **Issue:** The plan description for AUTPR-01a stated "this test does NOT need a stub for gh because the zero-drift guard returns before ever calling gh." However, the actual `cmd_update --pr` implementation checks for `gh` *before* the zero-drift guard, so without a stub, the test exited 2 with "gh CLI required" instead of "Harness is current"
- **Fix:** Added a `mktemp -d` stub directory with a no-op `gh` binary on `PATH` head for AUTPR-01a
- **Files modified:** tests/run.sh
- **Commit:** 8f3bb25

---

**Total deviations:** 1 auto-fixed (Rule 1 — incorrect observable behavior)
**Impact on plan:** Minimal; test logic was adjusted to match actual implementation order. All 11 acceptance criteria pass.

## Issues Encountered

None beyond the one auto-fixed deviation above.

## Threat Surface Scan

No new network endpoints, auth paths, or file access patterns introduced. Tests use `mktemp -d` stub binaries cleaned up via `trap ... EXIT` + explicit `rm -rf`. T-19-06 (stub gh binary tampering) mitigated as designed.

## Known Stubs

None — all AUTPR assertions exercise real `cli/conjure` paths with controlled stubs only for external tooling (gh).

## Self-Check: PASSED

- `tests/run.sh` exists and contains AUTPR section: FOUND
- Commit `8f3bb25` exists: FOUND
- `bash tests/run.sh`: PASS 302 FAIL 0
