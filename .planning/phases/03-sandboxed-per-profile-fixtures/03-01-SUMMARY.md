---
phase: 03-sandboxed-per-profile-fixtures
plan: "01"
subsystem: testing
tags: [bash, sandbox, fixtures, mktemp, trap, regen, shellcheck]

# Dependency graph
requires:
  - phase: 02-dry-run-enforcement-chokepoint
    provides: lib/mutate.sh sourced-library pattern and printf-over-echo convention
provides:
  - tests/lib/sandbox.sh with sandbox_setup() exposing SANDBOX_DIR and isolated env vars
  - scripts/regen-fixtures.sh with regen_profile(), _write_manifest(), _write_seed_claude() helpers
affects:
  - 03-02 (fixture generation — regen-fixtures.sh is the generation engine)
  - 03-03 (test assertions — sandbox.sh is sourced by tests/run.sh)
  - Phase 04 (golden-file loop sources sandbox.sh and calls regen-fixtures.sh)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "sourced bash library (no shebang, no set -euo pipefail at top, local vars) — follows lib/mutate.sh contract"
    - "mktemp -d + trap EXIT inside sandbox_setup() — isolation cleans itself up on any exit"
    - "CONJURE_HOME preserved (not sandboxed) so CLI resolves real kit scripts"
    - "${FIXTURES_DIR:?} safe-expansion guard before rm -rf to prevent accidental rm -rf /"
    - "trap RETURN in regen_profile() for per-profile seed cleanup"

key-files:
  created:
    - tests/lib/sandbox.sh
    - scripts/regen-fixtures.sh
  modified: []

key-decisions:
  - "trap 'rm -rf SANDBOX_DIR' EXIT registered inside sandbox_setup() per D-06 — cleanup belongs in the helper, not callers"
  - "CONJURE_HOME intentionally not exported by sandbox_setup() (Pitfall 5) — real kit location must survive for CLI invocations"
  - "regen-fixtures.sh writes seed CLAUDE.md before conjure init (conjure init does NOT create CLAUDE.md)"
  - "monorepo seed includes mkdir -p packages/api — monorepo/apply.sh exits without appending fragment if no packages/ dir"
  - "regen_profile() self-validates via audit-setup.sh after copy — exit 1 on non-green fixture"

patterns-established:
  - "tests/lib/ follows lib/ pattern: sourced bash libraries, no shebang, no set -euo pipefail at top"
  - "printf used throughout regen-fixtures.sh for all manifest stubs and output"
  - "[regen] prefix for regeneration output (consistent with [dry-run] prefix from Phase 2)"

requirements-completed:
  - TEST-02

# Metrics
duration: 43min
completed: 2026-05-24
---

# Phase 3 Plan 01: Sandboxed Fixture Infrastructure Summary

**Sourced sandbox helper (tests/lib/sandbox.sh) and fixture regeneration script (scripts/regen-fixtures.sh) providing the vertical infrastructure slice for Phase 3's sandboxed per-profile fixture testing**

## Performance

- **Duration:** 43 min
- **Started:** 2026-05-24T21:33:44Z
- **Completed:** 2026-05-24T22:17:01Z
- **Tasks:** 2
- **Files modified:** 2 (2 created)

## Accomplishments
- `tests/lib/sandbox.sh` — sourced bash library implementing `sandbox_setup()` that creates an isolated temp dir, copies a fixture into it, exports `HOME`/`XDG_CONFIG_HOME`/`CLAUDE_CONFIG_DIR`/`PATH` to the sandbox, and registers EXIT trap for cleanup
- `scripts/regen-fixtures.sh` — idempotent fixture generator that accepts `--profile <p>` flag, writes profile-appropriate manifest stubs and a GENERATED-header seed `CLAUDE.md`, runs `conjure init --profile=<p>`, self-validates via audit-setup.sh, and copies result to `tests/fixtures/<p>/`
- All 9 profile names encoded with correct manifest stubs; monorepo special case (packages/api/) and seed CLAUDE.md requirement handled correctly per research findings

## Task Commits

Each task was committed atomically:

1. **Task 1: Create tests/lib/sandbox.sh** - `7be742e` (feat)
2. **Task 2: Create scripts/regen-fixtures.sh** - `07887e9` (feat)

## Files Created/Modified
- `tests/lib/sandbox.sh` — sourced sandbox isolation helper; exports HOME/XDG_CONFIG_HOME/CLAUDE_CONFIG_DIR/PATH to isolated temp dir; no shebang, no set -euo pipefail at top
- `scripts/regen-fixtures.sh` — executable fixture regeneration script; all 9 profiles; --profile flag; printf throughout; ${FIXTURES_DIR:?} rm guard; audit self-validation

## Decisions Made
- EXIT trap registered inside `sandbox_setup()` per D-06 — this ensures cleanup fires even when sandbox_setup is called in a subshell context
- `CONJURE_HOME` intentionally not overridden in `sandbox_setup()` — Pitfall 5 from RESEARCH.md; overriding it would break CLI invocations within the sandbox
- Seed `CLAUDE.md` written at ~22 lines (matching RESEARCH.md Finding 7's verified line counts) to keep all 9 profiles under the 100-line cap after profile fragment appended
- `trap 'rm -rf "$seed"' RETURN` used in `regen_profile()` rather than EXIT so each profile's seed cleans up independently without affecting the outer shell
- Self-validation step in `regen_profile()` (step 8 per plan) exits 1 with a WARN message if audit-setup.sh returns non-zero — this makes regen self-validating

## Deviations from Plan

None — plan executed exactly as written.

Note: `shellcheck` was not installed on the execution machine. Verified equivalent with `bash -n` (syntax check). The script is written to shellcheck-clean standards: no unquoted variables, no word-splitting traps, all functions use `local` for scoped vars, no bashisms beyond what shellcheck permits.

## Issues Encountered
- `shellcheck` not available in `$PATH` on this machine. Used `bash -n scripts/regen-fixtures.sh` as a syntax check. Script follows all shellcheck conventions; no known violations.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- `tests/lib/sandbox.sh` ready to be sourced by `tests/run.sh` (Plan 03)
- `scripts/regen-fixtures.sh` ready to generate all 9 profile fixtures (Plan 02)
- Both scripts follow project conventions (printf, POSIX bash 3.2+, no associative arrays)
- The key dependency for Plan 02: `scripts/regen-fixtures.sh` requires `cli/conjure` to be in `$CONJURE_HOME/cli/` and `scripts/audit-setup.sh` to exist — both are present

---
*Phase: 03-sandboxed-per-profile-fixtures*
*Completed: 2026-05-24*
