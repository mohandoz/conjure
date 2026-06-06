---
phase: 31-deferred-debt-test-harness-hardening
plan: "02"
subsystem: testing
tags: [manual-uat, mdm, managed-settings, claude-plugin-validate, checklist]

# Dependency graph
requires: []
provides:
  - "tests/MANUAL-UAT.md with four UAT checklist sections (UAT-25, UAT-26a, UAT-26b, UAT-26c)"
  - "MDM hardware deploy instructions for macOS plist and Windows PS1"
  - "managed-settings.json deploy checklist"
  - "live claude plugin validate smoke test instructions"
affects: [31-deferred-debt-test-harness-hardening]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Manual UAT checklist format: prerequisites, numbered steps, expected result, checkboxes, date/version field"

key-files:
  created:
    - tests/MANUAL-UAT.md
  modified: []

key-decisions:
  - "Four UAT sections (UAT-25, UAT-26a, UAT-26b, UAT-26c) ordered by deferred phase (25 first, then 26a/26b/26c)"
  - "21 checkbox items distributed across 4 sections, exceeding the 18-item minimum"
  - "Notes section directs operators to run automated gates first before manual UAT"

patterns-established:
  - "Manual UAT checklist: one H2 section per scenario with prerequisites, numbered steps, expected result, checkboxes, and Verified date/version field"

requirements-completed:
  - UAT-03

# Metrics
duration: 5min
completed: "2026-06-04"
---

# Phase 31 Plan 02: Manual UAT Checklists Summary

**tests/MANUAL-UAT.md with four MDM + managed-settings + claude plugin validate UAT checklists closing Phase 25 and Phase 26 deferred HUMAN-UAT items**

## Performance

- **Duration:** ~5 min
- **Started:** 2026-06-04T17:00:00Z
- **Completed:** 2026-06-04T17:01:43Z
- **Tasks:** 1/1
- **Files modified:** 1

## Accomplishments

- Created `tests/MANUAL-UAT.md` with four complete UAT checklist sections
- UAT-25: live `claude plugin validate` smoke test (closes Phase 25 deferred HUMAN-UAT)
- UAT-26a/26b: MDM hardware deploy for macOS plist and Windows PS1 (closes Phase 26 MDM deferred item)
- UAT-26c: managed-settings.json deploy to `~/.claude/` (closes Phase 26 managed-settings deferred item)
- 21 checkbox items across 4 sections; all sections follow D-10 format mandate

## Task Commits

Each task was committed atomically:

1. **Task 1: Create tests/MANUAL-UAT.md with three UAT checklists** - `1304aaa` (docs)

**Plan metadata:** see final commit below

## Files Created/Modified

- `tests/MANUAL-UAT.md` - Four-section manual UAT checklist document (275 lines): UAT-25 (claude plugin validate), UAT-26a (macOS MDM plist), UAT-26b (Windows PS1 registry), UAT-26c (managed-settings.json)

## Decisions Made

- Ordered sections by deferred phase (UAT-25 before UAT-26a/b/c) to match investigation sequence
- Used 21 checkbox items (>= 18 required) for thorough manual verification coverage
- Notes section explicitly references automated gate invocation (`CONJURE_LIVE_TEST=1 bash tests/run.sh`) and strict mode, tying manual UAT to automated prerequisites

## Deviations from Plan

None — plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None — no external service configuration required. The UAT checklist itself documents the manual hardware/environment prerequisites for operators.

## Known Stubs

None — this plan creates a documentation artifact (checklist), not executable code. All checklist items are specific and actionable; no placeholder text.

## Threat Flags

None — the MANUAL-UAT.md document instructs operators with explicit safety notes (e.g., `Set-ExecutionPolicy` note for Windows, MDM push requires admin console access). The PowerShell steps are documentation only; operators review before executing. No new network endpoints or auth paths introduced.

## Next Phase Readiness

- UAT-03 closed: `tests/MANUAL-UAT.md` provides the manual checklist document for MDM + managed-settings UAT
- Operators can now follow the documented steps to complete manual UAT on real hardware
- Automated gate prerequisites (UAT-01, UAT-02) are implemented in separate plan (31-03 or 31-01)
- Phase 31 remaining plans: DEBT-03 (`git -C` empty-var guard), DEBT-04 (preflight exit 2), DEBT-05 (skip counter), DEBT-06 (SCHM-STALE kill-safety), UAT-01/02 gated live tests

---
*Phase: 31-deferred-debt-test-harness-hardening*
*Completed: 2026-06-04*

## Self-Check: PASSED

- `tests/MANUAL-UAT.md` exists: FOUND
- Task commit `1304aaa` exists: verified by `git rev-parse --short HEAD` output
- Acceptance criteria verified: 4 UAT sections, 21 checkboxes, 4 Verified fields, Prerequisites/Expected result blocks present
