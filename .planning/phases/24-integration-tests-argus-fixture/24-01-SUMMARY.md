---
phase: 24-integration-tests-argus-fixture
plan: 01
subsystem: testing
tags: [bash, fixture-generator, brownfield, adopt, symlink, at-import, shellcheck]

# Dependency graph
requires:
  - phase: 22-adopt-pipeline
    provides: "scripts/adopt.sh report() (the Scaffolded line this plan deviates), the live adopt/snapshot/scaffold pipeline the generator feeds"
  - phase: 23-restructure-skill
    provides: "templates/skills/restructure/gates/audit-staged.sh @import block (the @import seed file targets it in Plan 02)"
provides:
  - "tests/fixtures/_brownfield-argus/generate-argus.sh — 500-file brownfield fixture generator (bulk .md + real ln -s symlink + oversized CLAUDE.md + @import seed) materialized into a passed target dir"
  - "scripts/adopt.sh report() emits the literal ROADMAP criterion-3 phrase 'nothing to scaffold' on a zero-scaffold (idempotent) re-run (O-1 deviation)"
affects: [24-02-PLAN, integration-tests, e2e-adopt]

# Tech tracking
tech-stack:
  added: []  # zero new deps — printf/mkdir/ln/while only (CLAUDE.md dependencies:{} lock honored)
  patterns:
    - "Generator-script fixture (mirror generate-large.sh): materialize bulk + distinctive files at test time, commit only the generator — keeps the repo lean for 500-file fixtures"
    - "_-prefixed fixture dir to dodge the generic tests/fixtures/[^_]*/ sweep loops (run.sh:326/368/390)"
    - "Real symlinks created via ln -s at generation time, never committed (portable across cp -r/git/Windows)"

key-files:
  created:
    - tests/fixtures/_brownfield-argus/generate-argus.sh
  modified:
    - scripts/adopt.sh

key-decisions:
  - "O-1: report() emits the literal 'nothing to scaffold' on a zero-scaffold run via a single ADDITIVE conditional echo — the existing 'Scaffolded: 0 layer files' count line is preserved (no test asserts the literal count line, but the additive form is non-regressive by construction)"
  - "Fixture is a generator (509 .md generated at test time) not 500 committed files — repo-lean, matches the generate-large.sh precedent"
  - "exit 2 (never exit 1) on the generator's usage error, overriding generate-large.sh's exit 1, per the project lock"
  - "Symlink is a genuine ln -s (docs/linked.md -> real.md, relative target) — the existing brownfield-simple/symlink-target.md is unreliable, so a real symlink is created at gen time"

patterns-established:
  - "Generator-script fixture: commit the generator, materialize bulk + distinctive files into a passed mktemp -d target at test time"
  - "Additive report() deviation: ADD a phrase line, never replace the machine-readable count line, so existing assertions cannot regress"

requirements-completed: []  # verification phase — no REQ-* IDs (gated by the 5 ROADMAP criteria)

# Metrics
duration: 4min
completed: 2026-05-29
---

# Phase 24 Plan 01: Argus Fixture Generator + criterion-3 report() Deviation Summary

**A `_brownfield-argus` generator that materializes 509 `.md` + a real `ln -s` symlink + a 127-line oversized CLAUDE.md + an `@import` seed into any target dir, plus a 1-line additive `report()` deviation so an idempotent adopt re-run emits the literal ROADMAP phrase "nothing to scaffold" — full suite stays PASS 429/0.**

## Performance

- **Duration:** 4 min
- **Started:** 2026-05-29T03:17:17Z
- **Completed:** 2026-05-29T03:20:35Z
- **Tasks:** 2
- **Files modified:** 2 (1 created, 1 modified)

## Accomplishments
- `tests/fixtures/_brownfield-argus/generate-argus.sh` — materializes a representative 500-file brownfield repo (509 `.md` across `docs/`+`generated-docs/`, a genuine `ln -s` symlink at `docs/linked.md`, a 127-line oversized `CLAUDE.md`, and a `with-import.md` `@import` seed) into a passed target dir; dependency-free, shellcheck-clean, `exit 2` on usage error, zero `exit 1`.
- `scripts/adopt.sh` `report()` now emits the literal `nothing to scaffold` on a zero-scaffold (idempotent) re-run via one additive conditional `echo`, satisfying ROADMAP criterion 3's exact wording while preserving the `Scaffolded:  0 layer files` count line.
- Both deliverables verified; the full `tests/run.sh` suite stays at PASS 429 / FAIL 0 (no regression — Plan 01 adds the fixture/source, Plan 02 adds the consuming assertions).

## Task Commits

Each task was committed atomically:

1. **Task 1: Write _brownfield-argus/generate-argus.sh (500-file fixture generator)** - `8e1ba88` (test)
2. **Task 2: Add criterion-3 "nothing to scaffold" report() deviation (O-1)** - `66d19ff` (feat)

**Plan metadata:** (docs commit — see final commit)

## Files Created/Modified
- `tests/fixtures/_brownfield-argus/generate-argus.sh` (NEW) - 500-file brownfield fixture generator: `set -uo pipefail`, `exit 2` usage guard, `mkdir -p`, printf/while loops for the oversized CLAUDE.md + 509 bulk `.md`, a real `ln -s` symlink, and an `@import` seed; final summary echo with the materialized count.
- `scripts/adopt.sh` (MODIFY) - one additive line in `report()`: `[ "${created_count:-0}" -eq 0 ] && echo "  Scaffolded:  nothing to scaffold"` immediately after the existing Scaffolded count line.

## Decisions Made
- **O-1 resolution (do BOTH):** keep the machine-readable `Scaffolded:  0 layer files` count line AND additively emit the literal `nothing to scaffold` — so the ROADMAP criterion-3 text and the test signal agree without breaking any count-line consumer.
- **Generator over committed files:** 509 `.md` are generated at test time (repo-lean, matches `generate-large.sh`); only the generator script is committed.
- **`exit 2` not `exit 1`:** the generator overrides `generate-large.sh`'s `exit 1` usage error to honor the project "exit 2 never exit 1" lock (a fixture generator is not a hook, but the lock is project-wide).
- **Genuine `ln -s` symlink:** `docs/linked.md -> real.md` (relative target) is created at generation time; never a committed regular file (the existing `brownfield-simple/symlink-target.md` survives `cp -r`/git/Windows inconsistently).

## Deviations from Plan

The `scripts/adopt.sh` `report()` change IS the planned O-1 deviation (the single intentional product-code touch in this otherwise test-only verification phase, mandated by Task 2 and ROADMAP criterion 3's exact wording). It is documented here per the plan's `<output>` requirement:

### Planned O-1 Source Deviation (Task 2)

**1. [O-1 — criterion-3 wording] report() emits "nothing to scaffold" on a zero-scaffold re-run**
- **Found during:** Task 2 (planned, not discovered — O-1 was resolved during planning, see 24-VALIDATION.md)
- **Issue:** ROADMAP criterion 3 requires the idempotent re-run to report the literal "nothing to scaffold", but shipped `report()` only printed `Scaffolded: 0 layer files` — the literal phrase existed nowhere in the codebase.
- **Fix:** Added a single additive conditional `echo` after the Scaffolded count line — when `created_count` is 0, also emit `Scaffolded:  nothing to scaffold`. The count line is unchanged.
- **Files modified:** `scripts/adopt.sh` (`report()`, +1 line)
- **Verification:** Idempotent re-run (state cleared between runs) prints BOTH `Scaffolded:  0 layer files` and `nothing to scaffold`; a fresh run that scaffolds 47 layers does NOT emit the phrase (correctly conditional); `git diff` shows only the report() line; shellcheck clean; no `exit 1`; full suite PASS 429/0.
- **Committed in:** `66d19ff` (Task 2 commit)

---

**Total deviations:** 1 planned O-1 source deviation (no unplanned auto-fixes).
**Impact on plan:** The deviation is exactly the planned, minimal (+1 line) additive product-code touch; it does not regress the 429 existing assertions. No scope creep — no other adopt.sh / gate / skill behavior was touched.

## Issues Encountered
None — both tasks executed exactly as written. Baseline (PASS 429/0) confirmed before changes; full suite re-confirmed PASS 429/0 after both tasks.

## Threat Surface
No new attack surface. The generator writes only into a passed `mktemp -d` target; the `report()` deviation is an output-only stdout echo (no new input path). Matches the plan's `<threat_model>` (T-24-01 mitigate — additive echo, 429-green proof; T-24-SC accept — zero external packages). No threat flags raised.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Plan 02 (Wave 2) can now wire the `▸ Phase 24` test block: the generator is present (presence-guard `P24_ARGUS_OK` will pass) and the `nothing to scaffold` phrase is emittable for criterion-3 signal (d).
- No blockers. The generator existing adds no assertions yet (the consuming block lands in Plan 02), so the suite stays at 429 until Plan 02.

## Self-Check: PASSED

- FOUND: `tests/fixtures/_brownfield-argus/generate-argus.sh`
- FOUND: `.planning/phases/24-integration-tests-argus-fixture/24-01-SUMMARY.md`
- FOUND: commit `8e1ba88` (Task 1)
- FOUND: commit `66d19ff` (Task 2)
- FOUND: literal `nothing to scaffold` in `scripts/adopt.sh`

---
*Phase: 24-integration-tests-argus-fixture*
*Completed: 2026-05-29*
