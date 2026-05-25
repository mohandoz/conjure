---
phase: 04-regression-suite-dry-run-proof
plan: 02
subsystem: infra
tags: [ci, github-actions, windows, safe-03, hook-wiring, test-06]

# Dependency graph
requires:
  - phase: 01-safe-03-hook-wiring
    provides: node .mjs hook templates baked into settings.json (SAFE-03 fix)
provides:
  - CI windows-hook-wiring job that validates node .mjs wiring on windows-latest
affects: [phase-verification, ci, test-06]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "shell: bash on every step in a windows-latest GitHub Actions job invokes Git Bash (not PowerShell)"
    - "CONJURE_HOME=$GITHUB_WORKSPACE pattern for CI init calls — matches audit-on-fixture job"
    - "Negative grep assertion pattern: if grep <pattern> <file>; then echo FAIL && exit 1; fi"

key-files:
  created: []
  modified:
    - .github/workflows/ci.yml

key-decisions:
  - "D-10: windows-hook-wiring job on windows-latest — targeted smoke test, not full test suite"
  - "D-11: shell: bash on every step (Git Bash); no apt-get/choco/npm install/setup-node"
  - "D-12: Three assertions — node --version exits 0; grep node in settings.json; no bash .claude/hooks in settings.json"
  - "Do NOT run bash tests/run.sh on windows-latest — shellcheck not pre-installed (RESEARCH Pitfall 4)"

patterns-established:
  - "Pattern 4: Windows CI Job — shell: bash, CONJURE_HOME=$GITHUB_WORKSPACE, /tmp/fixture, grep assertions only"

requirements-completed: [TEST-06]

# Metrics
duration: 1min
completed: 2026-05-24
---

# Phase 4 Plan 02: Windows CI Hook Wiring Job Summary

**windows-hook-wiring job on windows-latest that proves SAFE-03 node .mjs hook wiring is intact in CI via three targeted grep assertions**

## Performance

- **Duration:** 1 min
- **Started:** 2026-05-24T23:57:47Z
- **Completed:** 2026-05-24T23:58:36Z
- **Tasks:** 1
- **Files modified:** 1

## Accomplishments
- Added `windows-hook-wiring` job to `.github/workflows/ci.yml` as the third CI job alongside `test` and `audit-on-fixture`
- Job runs on `windows-latest` with `shell: bash` on all 4 steps (invokes Git Bash, not PowerShell)
- Three D-12 assertions: `node --version` exits 0, `grep 'node' settings.json` succeeds, negative assertion confirms no `bash .claude/hooks` regression
- No extra dependencies installed — job uses only what is pre-installed on `windows-latest` (Node, Git Bash, grep)
- Existing ubuntu jobs (`test`, `audit-on-fixture`) completely unchanged

## Task Commits

Each task was committed atomically:

1. **Task 1: Add windows-hook-wiring job to .github/workflows/ci.yml (D-10, D-11, D-12)** - `cde1aff` (feat)

**Plan metadata:** (docs commit below)

## Files Created/Modified
- `.github/workflows/ci.yml` - Added `windows-hook-wiring` job (lines 54-79); 26 lines inserted after `audit-on-fixture` job

## Decisions Made
- Followed all locked decisions D-10/D-11/D-12 from CONTEXT.md exactly
- `shell: bash` on all 4 steps as required (the `uses: actions/checkout@v4` step has no shell context)
- Used `CONJURE_HOME="$GITHUB_WORKSPACE"` (not `$PWD`) matching the pattern in the existing `audit-on-fixture` job
- Used `/tmp/fixture` as target directory (same convention as `audit-on-fixture`)
- Did NOT add `bash tests/run.sh` in the windows job per RESEARCH.md Pitfall 4 (shellcheck not pre-installed on windows-latest)

## Deviations from Plan

None — plan executed exactly as written. All acceptance criteria pass:
- `grep -q 'windows-hook-wiring'` exits 0
- `grep -c 'shell: bash'` outputs 4
- `grep -q 'runs-on: windows-latest'` exits 0
- `grep -q 'node --version'` exits 0
- `grep -q 'SAFE-03 regression'` exits 0
- YAML is valid (python3 yaml.safe_load exits 0)
- No new dep installs (no choco/npm install/setup-node)
- Existing ubuntu jobs untouched (ubuntu-latest count still 2)

## Issues Encountered

None.

## User Setup Required

None — no external service configuration required. The Windows CI job runs automatically on push/PR to main or develop.

## Next Phase Readiness
- TEST-06 is delivered: CI now enforces SAFE-03 hook wiring on Windows in every push/PR
- Full CI verification requires a push to GitHub (local static verification confirmed; Windows runner behavior confirmed via assumptions A1/A2 in RESEARCH.md)
- Phase 4 Plan 01 (run.sh sections + EXPECT files) completes the regression suite; this plan (02) is independent and ready to merge

---
*Phase: 04-regression-suite-dry-run-proof*
*Completed: 2026-05-24*
