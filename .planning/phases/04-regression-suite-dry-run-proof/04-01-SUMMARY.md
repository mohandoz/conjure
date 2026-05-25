---
phase: 04-regression-suite-dry-run-proof
plan: "01"
subsystem: tests
tags: [testing, golden-file, regression, fixtures, TEST-03]
dependency_graph:
  requires: []
  provides: [golden-file-expect-loop, 9-green-expect-files, regen-fixtures-write-expect]
  affects: [tests/run.sh, scripts/regen-fixtures.sh, tests/fixtures/*/EXPECT]
tech_stack:
  added: []
  patterns: [golden-file-comparison, grep-E-pattern-matching, fixture-sandbox]
key_files:
  created:
    - tests/fixtures/ts-next/EXPECT
    - tests/fixtures/java-spring/EXPECT
    - tests/fixtures/rust-axum/EXPECT
    - tests/fixtures/go-gin/EXPECT
    - tests/fixtures/python-fastapi/EXPECT
    - tests/fixtures/node-nest/EXPECT
    - tests/fixtures/monorepo/EXPECT
    - tests/fixtures/polyglot/EXPECT
    - tests/fixtures/data-science/EXPECT
  modified:
    - tests/run.sh
    - scripts/regen-fixtures.sh
decisions:
  - "EXPECT content is a fixed 3-pattern template (PASS: [0-9], WARN: 0, FAIL: 0) — identical for all 9 green profiles, verified by Phase 3 live tests"
  - "_write_expect is called unconditionally during regen_profile (D-03: golden files always regenerated with fixtures)"
  - "--update-expect standalone mode writes EXPECT files without re-running conjure init — fast path for EXPECT-only updates"
metrics:
  duration: "~15 min"
  completed: "2026-05-25"
  tasks_completed: 3
  files_created: 9
  files_modified: 2
---

# Phase 4 Plan 01: Golden-File EXPECT Files and Loop Summary

**One-liner:** 9 committed EXPECT golden files plus the TEST-03 EXPECT loop in tests/run.sh — golden-file regression coverage for all green fixture profiles via 3 grep-E patterns each.

## What Was Built

### Task 1: 9 green-fixture EXPECT files (commit: 5abc863)

Created `tests/fixtures/<profile>/EXPECT` for all 9 green profiles (ts-next, java-spring, rust-axum, go-gin, python-fastapi, node-nest, monorepo, polyglot, data-science). Each file contains 3 grep-E patterns matching the `PASS: 17    WARN: 0    FAIL: 0` summary line that all green fixtures produce. Format matches the existing `_broken/EXPECT` canonical example (comments ignored, one pattern per line). `find tests/fixtures -name EXPECT` now returns 10 (9 green + 1 broken).

### Task 2: EXPECT loop section in tests/run.sh (commit: 9e17d81)

Inserted the `▸ Golden-file EXPECT loop (TEST-03)` section between the `_broken` fixture section and the `# Summary` block. The loop uses `[^_]*/` glob to skip `_broken/`, calls `sandbox_setup` + `audit-setup.sh`, then reads each EXPECT file with a `[ ! -f ]` guard. 27 new PASS lines added (9 fixtures × 3 patterns). Full suite: `PASS: 163    FAIL: 0`.

### Task 3: _write_expect function and --update-expect flag in scripts/regen-fixtures.sh (commit: f3f6ebc)

Added `UPDATE_EXPECT=""` variable and `--update-expect` case to arg parsing. Added `_write_expect()` function that writes the fixed 3-pattern EXPECT template using `printf`. Added call to `_write_expect "$p"` in `regen_profile` after audit verification passes (per D-03: EXPECT always regenerated with fixtures). Replaced main loop with conditional: `--update-expect` mode calls `_write_expect` only, skipping `conjure init` (fast path).

## Verification Results

All 6 success criteria met:

1. `find tests/fixtures -name EXPECT | wc -l` → 10
2. `bash tests/run.sh` → `PASS: 163    FAIL: 0`
3. `grep -q 'Golden-file EXPECT loop (TEST-03)' tests/run.sh` → exit 0
4. `grep -q '_write_expect' scripts/regen-fixtures.sh` → exit 0
5. `bash scripts/regen-fixtures.sh --update-expect --profile ts-next` → exit 0, produces valid EXPECT
6. No EXPECT file contains `/tmp` or `/var/folders` absolute paths

## Deviations from Plan

None — plan executed exactly as written. All three tasks implemented per specifications in PATTERNS.md and CONTEXT.md.

## Known Stubs

None — all EXPECT patterns are wired to live audit output via the sandbox+grep loop. No placeholder data.

## Threat Flags

None — no new network endpoints, auth paths, file access patterns beyond committed test fixtures, or schema changes at trust boundaries introduced.

## Self-Check

- [x] tests/fixtures/ts-next/EXPECT exists
- [x] tests/fixtures/java-spring/EXPECT exists
- [x] tests/fixtures/rust-axum/EXPECT exists
- [x] tests/fixtures/go-gin/EXPECT exists
- [x] tests/fixtures/python-fastapi/EXPECT exists
- [x] tests/fixtures/node-nest/EXPECT exists
- [x] tests/fixtures/monorepo/EXPECT exists
- [x] tests/fixtures/polyglot/EXPECT exists
- [x] tests/fixtures/data-science/EXPECT exists
- [x] Commit 5abc863 exists (Task 1)
- [x] Commit 9e17d81 exists (Task 2)
- [x] Commit f3f6ebc exists (Task 3)

## Self-Check: PASSED
