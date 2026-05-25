---
phase: 03-sandboxed-per-profile-fixtures
plan: "02"
subsystem: testing
tags: [bash, fixtures, regen, audit, profiles, conjure-init, GENERATED]

# Dependency graph
requires:
  - phase: 03-01
    provides: scripts/regen-fixtures.sh and tests/lib/sandbox.sh
provides:
  - tests/fixtures/ts-next/ (audited green)
  - tests/fixtures/java-spring/ (audited green)
  - tests/fixtures/rust-axum/ (audited green)
  - tests/fixtures/go-gin/ (audited green)
  - tests/fixtures/python-fastapi/ (audited green)
  - tests/fixtures/node-nest/ (audited green)
  - tests/fixtures/monorepo/ (audited green, packages/api/ present)
  - tests/fixtures/polyglot/ (audited green)
  - tests/fixtures/data-science/ (audited green)
affects:
  - 03-03 (test assertions — fixture corpus is the reference for regression suite)
  - Phase 04 (golden-file loop sources these fixtures)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "printf '%s\n' '- text' form used for strings starting with dash to avoid bash printf flag interpretation"
    - "regen-fixtures.sh self-validates each fixture via audit-setup.sh before copy"
    - "All 9 profile fixtures generated (not hand-crafted) from conjure init output"

key-files:
  created:
    - tests/fixtures/ts-next/
    - tests/fixtures/java-spring/
    - tests/fixtures/rust-axum/
    - tests/fixtures/go-gin/
    - tests/fixtures/python-fastapi/
    - tests/fixtures/node-nest/
    - tests/fixtures/monorepo/
    - tests/fixtures/polyglot/
    - tests/fixtures/data-science/
  modified:
    - scripts/regen-fixtures.sh (printf bug fix — dash-starting string)

key-decisions:
  - "Fixed printf bug in _write_seed_claude: '- POSIX bash...' string interpreted as printf flag; changed to printf '%s\\n' '...' form (Rule 1 auto-fix)"
  - "No manual edits to fixture files — all fixtures generated via regen-fixtures.sh per RESEARCH.md anti-pattern guidance"
  - "java-spring fixture includes legacy post-edit-format.sh alongside .mjs hooks — acceptable per RESEARCH.md Finding 5; audit passes"

patterns-established:
  - "tests/fixtures/<profile>/ layout: CLAUDE.md + .claude/ (settings.json, hooks/*.mjs, skills/, agents/) + docs/ + manifest file"
  - "monorepo fixture includes packages/api/ CLAUDE.md — appended by monorepo/apply.sh profile logic"
  - "All 9 CLAUDE.md files: 32-47 lines — well within 100-line hard cap"

requirements-completed:
  - TEST-01

# Metrics
duration: 25min
completed: 2026-05-25
---

# Phase 3 Plan 02: Generate and Verify All 9 Profile Fixtures Summary

**All 9 conjure stack-profile fixtures generated under tests/fixtures/ via regen-fixtures.sh and verified individually green (PASS: 17, WARN: 0, FAIL: 0) by audit-setup.sh**

## Performance

- **Duration:** ~25 min
- **Started:** 2026-05-25T22:00:00Z
- **Completed:** 2026-05-25T22:23:25Z
- **Tasks:** 2
- **Files modified:** 390 (389 created, 1 modified)

## Accomplishments

- Ran `scripts/regen-fixtures.sh` to generate all 9 per-profile fixture directories under `tests/fixtures/`
- Each fixture contains: GENERATED-header `CLAUDE.md`, `.claude/` (settings.json + 5 .mjs hooks + 19 skills + 6 agents), `docs/` (ARCHITECTURE.md, RUNBOOK.md, adr/), and profile manifest stub
- All 9 fixtures audit green: `bash scripts/audit-setup.sh tests/fixtures/<profile>` exits 0 for every profile
- CLAUDE.md line counts: 32-47 lines per profile — all well within 100-line cap and within 30-45 target range
- monorepo fixture contains `packages/api/` with its own `CLAUDE.md` (appended by monorepo/apply.sh)
- ts-next fixture `settings.json` contains 5 `node .mjs` references (SAFE-03 verified)
- No fixture contains `@imports` or `graphify-out/`
- Verified all 9 fixtures meet exact audit output: PASS: 17, WARN: 0, FAIL: 0

## Task Commits

Each task was committed atomically:

1. **Task 1: Run regen-fixtures.sh to generate all 9 green profile fixtures** - `e35f1e9` (feat)
2. **Task 2: Verify all 9 fixtures audit green** — no files changed (pure verification); result confirmed in Task 1 commit

## Files Created/Modified

- `scripts/regen-fixtures.sh` — fixed `printf` bug (dash-starting string in `_write_seed_claude`)
- `tests/fixtures/ts-next/` — TypeScript/Next.js profile fixture (47 lines CLAUDE.md)
- `tests/fixtures/java-spring/` — Java/Spring Boot profile fixture, includes legacy post-edit-format.sh (46 lines)
- `tests/fixtures/rust-axum/` — Rust/Axum profile fixture (46 lines)
- `tests/fixtures/go-gin/` — Go/Gin profile fixture (45 lines)
- `tests/fixtures/python-fastapi/` — Python/FastAPI profile fixture (47 lines)
- `tests/fixtures/node-nest/` — Node.js/NestJS profile fixture (43 lines)
- `tests/fixtures/monorepo/` — Monorepo profile fixture with packages/api/ (34 lines)
- `tests/fixtures/polyglot/` — Polyglot profile fixture (32 lines)
- `tests/fixtures/data-science/` — Data science profile fixture (44 lines)

## Decisions Made

- Used `printf '%s\n' '...'` form for dash-prefixed strings in shell scripts — prevents bash built-in `printf` from treating the `-` as a flag
- Did not hand-edit any fixture file — all content flows through `regen-fixtures.sh` → `conjure init` pipeline to keep fixtures authoritative

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed printf flag interpretation in _write_seed_claude**
- **Found during:** Task 1 — first `bash scripts/regen-fixtures.sh` invocation failed immediately
- **Issue:** `printf '- POSIX bash + Node.js .mjs hooks.\n'` — bash's built-in `printf` treated the leading `-` as an option flag, causing `printf: usage: printf [-v var] format [arguments]` and exit 2
- **Fix:** Changed to `printf '%s\n' '- POSIX bash + Node.js .mjs hooks.'` using explicit format string to prevent flag interpretation
- **Files modified:** `scripts/regen-fixtures.sh` line 71
- **Commit:** `e35f1e9` (included in Task 1 commit)

## Known Stubs

None — all 9 fixtures are generated output from `conjure init --profile=<p>` with real harness content. No placeholder or mock data.

## Threat Surface Scan

No new network endpoints, auth paths, file access patterns, or schema changes introduced. Fixtures are static committed files. The SAFE-03 regression check (T-03-05) passed: `grep -c 'node.*\.mjs' tests/fixtures/ts-next/.claude/settings.json` = 5.

## Self-Check: PASSED

- [x] tests/fixtures/ts-next/ exists and contains CLAUDE.md
- [x] tests/fixtures/monorepo/packages/api exists
- [x] tests/fixtures/java-spring/.claude/settings.json exists
- [x] Commit e35f1e9 exists: `git log --oneline | grep e35f1e9`
- [x] All 9 fixtures audit green (PASS: 17, WARN: 0, FAIL: 0)
- [x] No @imports in any fixture CLAUDE.md
- [x] No graphify-out/ in any fixture

---
*Phase: 03-sandboxed-per-profile-fixtures*
*Completed: 2026-05-25*
