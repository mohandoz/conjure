---
phase: 08-nyquist-compliance-backfill
plan: "03"
subsystem: documentation
tags: [nyquist, validation, cost-estimator, telemetry, verify-blocks]
dependency_graph:
  requires: []
  provides:
    - .planning/phases/06-cost-estimator/06-VALIDATION.md
    - .planning/phases/07-skill-firing-telemetry/07-VALIDATION.md
  affects: []
tech_stack:
  added: []
  patterns:
    - standalone-verify-blocks
    - inline-tmpdir-setup
    - copy-paste-runnable-documentation
key_files:
  created:
    - .planning/phases/07-skill-firing-telemetry/07-VALIDATION.md
  modified:
    - .planning/phases/06-cost-estimator/06-VALIDATION.md
decisions:
  - "07-VALIDATION.md uses 8 sections (not 7): TELEMETRY.md check kept as a separate section for independence and clarity"
  - "06-VALIDATION.md completely replaced: prior file was a planning strategy doc, not verify-block format"
metrics:
  duration_min: 10
  completed_date: "2026-05-25"
  tasks_completed: 2
  tasks_total: 2
  files_created: 1
  files_modified: 1
---

# Phase 08 Plan 03: Nyquist VALIDATION.md for Cost Estimator and Telemetry Summary

## One-liner

Standalone copy-paste-runnable verify blocks for Phase 06 (cost estimator) and Phase 07 (skill-firing telemetry), closing TECH-02e and TECH-02f Nyquist gaps.

## What Was Built

Two VALIDATION.md files with standalone shell verify blocks that confirm shipped behavior without requiring the reader to understand source code.

**06-VALIDATION.md** — 4 ## Verify sections:
1. Cost section header present when CONJURE_COST=1 (COST-01)
2. Cost label has ±20% band and pricing date (COST-02)
3. No network calls in default audit path — static grep (COST-03)
4. --exact advisory when ANTHROPIC_API_KEY absent (COST-03)

**07-VALIDATION.md** — 8 ## Verify sections:
1. skill-telemetry.mjs hook file exists (TLMY-01)
2. Hook contains no network egress patterns — static grep (TLMY-03)
3. Hook exits 0 silently when CONJURE_TELEMETRY unset (TLMY-01)
4. DO_NOT_TRACK=1 suppresses JSONL writes (TLMY-01)
5. Hook writes JSONL with required fields when CONJURE_TELEMETRY=1 (TLMY-02)
6. UserPromptExpansion path writes skill_typed event (TLMY-02b)
7. Retire-list section renders when CONJURE_RETIRE=1 (TLMY-04)
8. TELEMETRY.md exists with required schema fields (TLMY-05)

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Create 06-VALIDATION.md for Phase 06 (Cost Estimator) | a773424 | .planning/phases/06-cost-estimator/06-VALIDATION.md |
| 2 | Create 07-VALIDATION.md for Phase 07 (Skill-Firing Telemetry) | a32eebb | .planning/phases/07-skill-firing-telemetry/07-VALIDATION.md |

## Deviations from Plan

### Auto-fixed Issues

None.

### Context-Driven Adjustments

**06-VALIDATION.md full replacement:** The existing file was a planning strategy document (frontmatter with `nyquist_compliant: false`, tables for test infrastructure) rather than the Nyquist-compliant verify-block format. It was replaced in full with the correct format. This is not a deviation from intent — the plan explicitly called for creating the file with the correct format.

**07-VALIDATION.md: 8 sections instead of 7:** The plan offered a choice between 7 or 8 sections for TELEMETRY.md coverage. Section 8 was added as a standalone section titled "Verify TELEMETRY.md exists with required schema fields (TLMY-05)" rather than merging it with Section 1. This keeps each section independently testable.

## Known Stubs

None — all verify blocks reference real files and real env vars shipped in v0.3.0.

## Threat Flags

None — VALIDATION.md files are read-only documentation; no new network endpoints, auth paths, or schema changes introduced.

## Self-Check: PASSED

Files exist:
- FOUND: .planning/phases/06-cost-estimator/06-VALIDATION.md
- FOUND: .planning/phases/07-skill-firing-telemetry/07-VALIDATION.md

Commits exist:
- FOUND: a773424 (docs(08-03): create 06-VALIDATION.md with 4 standalone verify blocks)
- FOUND: a32eebb (docs(08-03): create 07-VALIDATION.md with 8 standalone verify blocks)

All 6 VALIDATION.md files present across phases 01, 02, 04, 05, 06, 07.
