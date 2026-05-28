---
phase: 19-auto-pr
plan: 01
subsystem: cli
tags: [bash, gh, git, github-actions, conjure-update]

# Dependency graph
requires:
  - phase: 17-drift-detection
    provides: conjure check --porcelain output format (<M|R|A> <path>)
  - phase: 18-conflict-resolution
    provides: conjure update --apply (3-way merge used inside --pr branch)
provides:
  - conjure update --pr: full git branch + gh pr create flow with zero-drift guard and idempotency
  - conjure update --cron: writes .github/workflows/conjure-update.yml with weekly Monday schedule
affects: [19-02-tests, phase-20-final-release]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "early action dispatch: --pr and --cron branches evaluated before version-comparison block"
    - "cross-platform sha256: sha256sum (Linux) with shasum -a 256 (macOS) fallback"
    - "deterministic branch name: sha256 of kit version string, first 7 chars"

key-files:
  created: []
  modified:
    - cli/conjure

key-decisions:
  - "Add --pr and --cron dispatch before the pinned/CONJURE_VERSION comparison block so those flags bypass the version early-exit"
  - "Add --help|-h to cmd_update arg parser so help output is accessible without running version logic"
  - "pr_body built via printf + while heredoc to avoid subshell variable scoping issues with local"

patterns-established:
  - "cmd_update --pr pattern: gh guard → zero-drift check → idempotency via gh pr list → porcelain body → git branch/apply/commit/push → gh pr create"
  - "cmd_update --cron pattern: mkdir -p workflow_dir → cat heredoc to wf_file → print confirmation"

requirements-completed: [AUTPR-01, AUTPR-02]

# Metrics
duration: 2min
completed: 2026-05-26
---

# Phase 19 Plan 01: Auto-PR Summary

**`conjure update --pr` (AUTPR-01) and `conjure update --cron` (AUTPR-02) added to cmd_update with gh prerequisite guard, zero-drift guard, deterministic branch naming, and idempotency via `gh pr list`**

## Performance

- **Duration:** 2 min
- **Started:** 2026-05-26T03:56:59Z
- **Completed:** 2026-05-26T03:59:15Z
- **Tasks:** 1
- **Files modified:** 1

## Accomplishments

- `--pr` branch: exits 2 if `gh` absent; exits 0 with "Harness is current" if no drift; checks for existing open PR (idempotency); builds markdown table PR body from porcelain output; creates git branch, applies drift via `--apply`, commits, pushes, opens PR with `gh pr create`
- `--cron` branch: writes `.github/workflows/conjure-update.yml` with `cron: '0 9 * * 1'` + `workflow_dispatch`, idempotent (can overwrite safely)
- `--help|-h` added to `cmd_update` arg parser so `conjure update --help` shows `--pr|--cron` in usage
- usage() updated to `conjure update [--check|--apply|--pr|--cron] [target]`

## Task Commits

1. **Task 1: Add --pr and --cron arg parsing to cmd_update** - `f670ba3` (feat)

**Plan metadata:** (pending docs commit)

## Files Created/Modified

- `cli/conjure` - Added `--pr` and `--cron` action branches to `cmd_update`; updated arg parser and usage string

## Decisions Made

- Early dispatch for `--pr` and `--cron` placed before the `pinned == CONJURE_VERSION` version check so those flags are not short-circuited by the "up to date" early-exit path
- `--help|-h` handling added to `cmd_update` (deviation: plan didn't specify, but the acceptance criterion required `conjure update --help | grep -q 'pr'` to pass — Rule 2 correctness)
- `pr_body` construction uses `printf` header lines + `while` loop reading `drift_lines` via here-string to avoid subshell scoping with `local` declarations

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Critical] Added --help|-h handler to cmd_update**
- **Found during:** Task 1 (verification step)
- **Issue:** The acceptance criterion `CONJURE_HOME=$(pwd) cli/conjure update --help 2>&1 | grep -q 'pr'` failed because `--help` was falling through to the `target` assignment. The plan did not explicitly add `--help|-h` to `cmd_update`'s arg parser but the acceptance criterion required it.
- **Fix:** Added `--help|-h) echo "Usage: conjure update [--check|--apply|--pr|--cron] [target]"; return 0 ;;` to the while-loop arg parser
- **Files modified:** cli/conjure
- **Verification:** `CONJURE_HOME=$(pwd) cli/conjure update --help 2>&1 | grep -q 'pr'` passes
- **Committed in:** f670ba3

---

**Total deviations:** 1 auto-fixed (Rule 2 - missing correctness requirement)
**Impact on plan:** Minor; all acceptance criteria now pass including the --help test. No scope creep.

## Issues Encountered

None - implementation proceeded cleanly. All 9 acceptance criteria passed after the `--help` handler addition.

## Threat Surface Scan

No new network endpoints or auth paths introduced. The `--pr` branch introduces `gh pr create` and `git push origin` (external I/O), but these are in the plan's threat register (T-19-02, T-19-03) and marked `accept`. The `--cron` branch writes a YAML file to the target repo's `.github/workflows/`; T-19-05 covers this and is accepted. No new threats beyond the plan's threat model.

## User Setup Required

None - no external service configuration required beyond having `gh` authenticated (existing prerequisite for GitHub CLI users).

## Next Phase Readiness

- Plan 01 complete: both `--pr` and `--cron` branches in `cmd_update`, shellcheck clean
- Plan 02 (regression tests) can now write `bats` tests for zero-drift guard, idempotency, missing-gh exit 2, and cron template content

---
*Phase: 19-auto-pr*
*Completed: 2026-05-26*
