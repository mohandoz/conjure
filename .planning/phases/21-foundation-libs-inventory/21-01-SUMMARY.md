---
phase: 21-foundation-libs-inventory
plan: "01"
subsystem: test-infrastructure
tags:
  - test-fixture
  - json-schema
  - brownfield
  - wave-0
dependency_graph:
  requires: []
  provides:
    - tests/fixtures/brownfield-simple (representative brownfield fixture for INV-01..INV-04 unit tests)
    - adopt-manifest.schema.json (JSON Schema draft-07 validating manifest contract)
    - Phase 21 test block in tests/run.sh (stub coverage for all Req IDs)
  affects:
    - tests/run.sh (appended Phase 21 test block)
    - All Plans 02-04 (depend on this fixture and test infrastructure)
tech_stack:
  added: []
  patterns:
    - POSIX bash test fixture with CLAUDE.md + skill + agent + docs + planning-doc
    - JSON Schema draft-07 for manifest validation
    - Graceful-skip test stub pattern (fail with informative message when lib absent)
key_files:
  created:
    - tests/fixtures/brownfield-simple/CLAUDE.md
    - tests/fixtures/brownfield-simple/.claude/skills/git/SKILL.md
    - tests/fixtures/brownfield-simple/.claude/agents/deploy.md
    - tests/fixtures/brownfield-simple/.claude/settings.json
    - tests/fixtures/brownfield-simple/docs/README.md
    - tests/fixtures/brownfield-simple/docs/ARCHITECTURE.md
    - tests/fixtures/brownfield-simple/docs/RUNBOOK.md
    - tests/fixtures/brownfield-simple/.planning/21-PLAN.md
    - tests/fixtures/brownfield-simple/symlink-target.md
    - tests/fixtures/brownfield-simple/generate-large.sh
    - tests/fixtures/brownfield-simple/EXPECT
    - tests/fixtures/brownfield-simple/.claudeignore
    - tests/fixtures/brownfield-simple/.env.example
    - tests/fixtures/brownfield-simple/docs/adr/
    - adopt-manifest.schema.json
  modified:
    - tests/run.sh (Phase 21 test block appended — 611 lines added)
decisions:
  - Fixture includes .claudeignore + docs/adr/ + .env.example so audit-setup.sh exits 0 (no warnings)
  - generate-large.sh uses POSIX while loop (not seq) for bash 3.2 compatibility
  - Phase 21 test stubs use env-var injection pattern for complex quoting in bash -c subshells
  - EXPECT golden file contains 9 patterns matching audit-setup.sh check marks
  - adopt-manifest.schema.json uses additionalProperties:true at top level for Phase 22 forward compat
metrics:
  duration: ~12 minutes
  completed: "2026-05-28"
  tasks_completed: 2
  tasks_total: 2
  files_created: 15
  files_modified: 1
---

# Phase 21 Plan 01: Wave 0 Test Infrastructure Summary

Wave 0 test infrastructure: brownfield-simple fixture + adopt-manifest.schema.json + Phase 21 test block scaffolded in tests/run.sh, enabling all subsequent Wave 1 plans to run tests immediately after implementation.

## What Was Built

### Task 1: brownfield-simple fixture + adopt-manifest.schema.json (commit 6d93802)

Created `tests/fixtures/brownfield-simple/` with all 9 required files + symlink + 2 extra files needed for audit exit 0:

| File | Purpose |
|------|---------|
| `CLAUDE.md` | 21-line core-bucket file, passes audit (≤100 lines, no @imports) |
| `.claude/skills/git/SKILL.md` | skill-bucket file with valid frontmatter (name + 30+ char description) |
| `.claude/agents/deploy.md` | agent-bucket file (16 lines, under 80-line cap) |
| `.claude/settings.json` | `{"hooks":{}}` — satisfies audit-setup.sh settings.json check |
| `docs/README.md` | reference-doc bucket target |
| `docs/ARCHITECTURE.md` | required by audit-setup.sh line 109 (or audit warns) |
| `docs/RUNBOOK.md` | required by audit-setup.sh line 110 (or audit warns) |
| `.planning/21-PLAN.md` | planning-doc bucket target |
| `symlink-target.md` | symlink → docs/README.md for M-2 symlink skip test |
| `generate-large.sh` | executable POSIX bash script creating 510 .md files for INV-03 cap test |
| `EXPECT` | 9 golden patterns matching audit-setup.sh check marks |
| `.claudeignore` | prevents audit warning about generated files |
| `docs/adr/` | prevents audit warning about missing ADR directory |
| `.env.example` | prevents audit warning about missing .env.example |

`adopt-manifest.schema.json` created at repo root:
- JSON Schema draft-07 (`$schema: http://json-schema.org/draft-07/schema#`)
- 6-bucket classification enum (D-01): `core`, `skill`, `agent`, `planning-doc`, `reference-doc`, `unknown`
- `size_cap_exceeded` field name (D-09), not `cap_exceeded`
- `summary.scan_capped` + `summary.total_found` fields for D-08 overflow semantics
- `size_cap_limit` accepts `oneOf: [integer, null]` for non-cap buckets
- `additionalProperties: true` at top level for Phase 22 additions (snapshot_path, at_imports_detected)

### Task 2: Phase 21 test block in tests/run.sh (commit e048774)

Appended 611 lines to `tests/run.sh` covering all 8 requirement groups:

1. `Phase 21 — lib/caps.sh (SC-5)` — tests CLAUDE_MD_CAP/SKILL_MD_CAP/AGENT_MD_CAP constants
2. `Phase 21 — lib/log.sh (ADOPT-03/SC-1)` — DRY_RUN=1 dry-run + live log_init/log_step tests
3. `Phase 21 — lib/snapshot.sh (SC-2)` — DRY_RUN=1 + live snapshot_create tests
4. `Phase 21 — lib/inventory.sh (INV-01..INV-04)` — classify, emit_manifest, symlink skip, cap, size_cap tests
5. `Phase 21 — mutate_archive (SAFE-03)` — DRY_RUN=1 + live move + sha256 mismatch abort tests
6. `Phase 21 — audit-setup.sh caps (SC-5)` — verifies audit-setup.sh uses $CLAUDE_MD_CAP var
7. `Phase 21 — manifest schema (SC-4)` — jq validates schema + Pattern 7 sample
8. `Phase 21 — perf gate (CR-7)` — times inventory on 510-file fixture, asserts < 30s

## Verification Results

```
bash tests/run.sh 2>&1 | tail -5
→ PASS: 315    FAIL: 7
→ rc=1  (not 2 — no crashes)

bash scripts/audit-setup.sh tests/fixtures/brownfield-simple
→ PASS: 14    WARN: 0    FAIL: 0
→ rc=0

jq empty adopt-manifest.schema.json && echo "schema ok"
→ schema ok

test -L tests/fixtures/brownfield-simple/symlink-target.md && echo "symlink present"
→ symlink present

generate-large.sh → 510 files in generated-docs/
```

The 7 failures are all Phase 21 test stubs failing gracefully (informative messages) because libs from Plans 02-04 don't exist yet. All 315 pre-existing tests pass unaffected.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Files] Added .claudeignore, docs/adr/, .env.example to fixture**
- **Found during:** Task 1 verification — `bash scripts/audit-setup.sh` exited 1 (warnings) for missing `.claudeignore`, `docs/adr/`, and `.env.example`
- **Issue:** Plan said "brownfield-simple fixture passes audit-setup.sh with exit 0" but without these three files, audit exits 1 (warnings)
- **Fix:** Added empty `.claudeignore`, empty `docs/adr/` directory, and empty `.env.example` to match what audit-setup.sh requires for exit 0
- **Files modified:** `tests/fixtures/brownfield-simple/.claudeignore`, `tests/fixtures/brownfield-simple/docs/adr/`, `tests/fixtures/brownfield-simple/.env.example`
- **Commit:** 6d93802

**2. [Rule 3 - Blocking] Force-added .claude/ fixture files**
- **Found during:** Task 1 commit staging — global `~/.gitignore_global` ignores `.claude/` directories, blocking `git add` for the fixture's `.claude/` files
- **Fix:** Used `git add -f` for the three files inside `tests/fixtures/brownfield-simple/.claude/` — these are test fixtures that must be committed, not the project's own `.claude/`
- **Files affected:** `.claude/skills/git/SKILL.md`, `.claude/agents/deploy.md`, `.claude/settings.json`
- **Commit:** 6d93802

**3. [Rule 3 - Blocking] Fixed subshell quoting in test block for bash -c calls**
- **Found during:** Task 2 syntax check — `bash -n tests/run.sh` revealed EOF errors where variable interpolation inside `bash -c '...' ` strings was ending the outer command substitution `$(` prematurely
- **Fix:** Replaced `"'"$VAR"'"` interpolation inside bash -c strings with env-var injection: `_VAR="$VAR" bash -c '... $_ VAR ...'`
- **Pattern:** `DRY_RUN=1 _P21_SNAP_TARGET="$BF_FIXTURE" bash -c '... $_ P21_SNAP_TARGET ...'`
- **Commits:** e048774

## Self-Check: PASSED

All created files found:
- `tests/fixtures/brownfield-simple/CLAUDE.md` — FOUND
- `tests/fixtures/brownfield-simple/.claude/skills/git/SKILL.md` — FOUND
- `tests/fixtures/brownfield-simple/.claude/agents/deploy.md` — FOUND
- `tests/fixtures/brownfield-simple/.claude/settings.json` — FOUND
- `tests/fixtures/brownfield-simple/docs/README.md` — FOUND
- `tests/fixtures/brownfield-simple/docs/ARCHITECTURE.md` — FOUND
- `tests/fixtures/brownfield-simple/docs/RUNBOOK.md` — FOUND
- `tests/fixtures/brownfield-simple/.planning/21-PLAN.md` — FOUND
- `tests/fixtures/brownfield-simple/generate-large.sh` — FOUND
- `tests/fixtures/brownfield-simple/EXPECT` — FOUND
- `tests/fixtures/brownfield-simple/symlink-target.md` (symlink) — FOUND
- `adopt-manifest.schema.json` — FOUND

Commits verified:
- `e048774`: feat(21-01): scaffold Phase 21 test block in tests/run.sh — FOUND
- `6d93802`: feat(21-01): create brownfield-simple fixture and adopt-manifest.schema.json — FOUND
