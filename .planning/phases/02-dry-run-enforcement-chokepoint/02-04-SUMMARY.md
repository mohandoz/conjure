---
phase: 02-dry-run-enforcement-chokepoint
plan: "04"
subsystem: compliance
tags: [bash, dry-run, mutation-chokepoint, compliance, posix, hipaa, gdpr, soc2, pci]

# Dependency graph
requires:
  - "02-01: lib/mutate.sh — mutation chokepoint library"
provides:
  - "compliance/gdpr/apply.sh: dry-run protected via mutate_write"
  - "compliance/soc2/apply.sh: dry-run protected via mutate_write"
  - "compliance/pci/apply.sh: dry-run protected via mutate_write"
  - "compliance/hipaa/apply.sh: dry-run protected via mutate_mkdir + mutate_cp + mutate_write + inline DRY_RUN chmod guard"
  - "SAFE-02 compliance leg: all 4 overlay scripts route mutations through lib/mutate.sh chokepoint"
  - "SAFE-01 compliance leg: DRY_RUN=1 suppresses all filesystem mutations in all compliance overlays"
affects:
  - 02-06  # integration test (Wave 3) — verifies compliance overlay dry-run via tests/run.sh

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Uniform 3-step migration for append-only scripts: source mutate.sh + mutate_write --append + mutate_summary"
    - "Inline DRY_RUN chmod guard per D-02: [ \"${DRY_RUN:-0}\" = \"1\" ] || chmod +x ... — chmod excluded from mutate_* API"
    - "mutate_cp with explicit dest path: compliance/hipaa drops the trailing / from cp destination for precision"

key-files:
  created: []
  modified:
    - compliance/gdpr/apply.sh
    - compliance/soc2/apply.sh
    - compliance/pci/apply.sh
    - compliance/hipaa/apply.sh

key-decisions:
  - "hipaa drops || true from cp calls — PATTERNS.md states source-missing is caught by test suite; explicit destination path is cleaner"
  - "mutate_summary placed before final echo in all 4 scripts — consistent tail placement matches pattern established in Wave 1"

requirements-completed: [SAFE-01, SAFE-02]

# Metrics
duration: 12min
completed: 2026-05-24
---

# Phase 2 Plan 04: Retrofit All 4 compliance/*/apply.sh Summary

**Uniform 3-step migration routes all compliance overlay mutations through lib/mutate.sh chokepoint; DRY_RUN=1 suppresses all writes in every overlay; 121 tests pass with zero regressions**

## Performance

- **Duration:** ~12 min
- **Started:** 2026-05-24
- **Completed:** 2026-05-24
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments

- Migrated all 4 compliance overlay scripts to source and use lib/mutate.sh
- gdpr, soc2, pci: 3-step migration (source + mutate_write --append + mutate_summary)
- hipaa: 6-operation migration (mutate_write + 2x mutate_mkdir + 2x mutate_cp + inline chmod guard + mutate_summary)
- DRY_RUN=1 confirmed to suppress all mutations with no filesystem side-effects
- SAFE-01 verified: `[ ! -d "$TMPD/.claude" ]` passes after `DRY_RUN=1 bash compliance/hipaa/apply.sh`
- SAFE-02 compliance leg closed: all writes route through mutate_* chokepoint
- 121 tests pass (no regressions)

## Task Commits

1. **Task 1: Migrate gdpr, soc2, pci overlays** - `ef055dc` (feat)
2. **Task 2: Migrate hipaa overlay** - `b0fbd35` (feat)

## Files Created/Modified

- `compliance/gdpr/apply.sh` — Added source line, replaced bare cat >> with mutate_write --append, added mutate_summary before final echo
- `compliance/soc2/apply.sh` — Same 3-step migration as gdpr
- `compliance/pci/apply.sh` — Same 3-step migration as gdpr
- `compliance/hipaa/apply.sh` — Added source line; replaced cat >> with mutate_write --append; replaced 2x mkdir with mutate_mkdir; replaced 2x cp (with || true) with mutate_cp (explicit destination paths); replaced bare chmod with inline DRY_RUN guard per D-02; added mutate_summary before final echo

## Decisions Made

1. **hipaa drops || true from cp calls** — The plan specifies dropping `|| true` from the cp calls and using mutate_cp with explicit destination paths. If the source file is missing, the test suite catches it. The explicit destination (`$TARGET/.claude/hooks/pre-commit-phi-scan.sh` rather than `$TARGET/.claude/hooks/`) is cleaner and matches the mutate_cp signature.

2. **Inline DRY_RUN chmod guard (D-02)** — chmod uses `[ "${DRY_RUN:-0}" = "1" ] || chmod +x ...` per the D-02 decision that excludes mutate_chmod from the API. This is the same pattern applied in profiles/java-spring/apply.sh.

## Deviations from Plan

None — plan executed exactly as written. All 3 simple overlays followed the uniform migration pattern. hipaa followed all 6 replacement instructions from PATTERNS.md. No bugs found, no missing functionality discovered.

## Issues Encountered

None.

## User Setup Required

None.

## Next Phase Readiness

- All 4 compliance overlay scripts now route mutations through lib/mutate.sh
- Wave 2 (02-05: cli/conjure cmd_init wiring) can proceed — the compliance leg of SAFE-01/SAFE-02 is closed
- Wave 3 (02-06: integration tests in tests/run.sh) can add dry-run regression coverage for compliance overlays

## Self-Check

- [x] `compliance/gdpr/apply.sh` — modified, committed in ef055dc
- [x] `compliance/soc2/apply.sh` — modified, committed in ef055dc
- [x] `compliance/pci/apply.sh` — modified, committed in ef055dc
- [x] `compliance/hipaa/apply.sh` — modified, committed in b0fbd35
- [x] All 4 bash -n syntax checks pass
- [x] No bare cat >>/ mkdir/ cp remain in compliance scripts
- [x] SAFE-01 smoke test passes (DRY_RUN=1 leaves filesystem unchanged)
- [x] 121 tests pass

## Self-Check: PASSED

---
*Phase: 02-dry-run-enforcement-chokepoint*
*Completed: 2026-05-24*
