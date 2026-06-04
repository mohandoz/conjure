---
phase: 27-schema-version-aware-audit
plan: "00"
subsystem: schema-audit
tags: [schema, cc-schema, fixtures, test-infrastructure, wave-0, graceful-red]
dependency_graph:
  requires: []
  provides:
    - lib/cc-schema.json
    - tests/fixtures/_schema-audit/valid/harness/
    - tests/fixtures/_schema-audit-badfield/harness/
    - tests/fixtures/_schema-audit-disablebypass/harness/
    - tests/fixtures/_schema-audit-hookevent/harness/
    - tests/fixtures/_schema-audit-stale/cc-schema-stale.json
    - tests/run.sh Phase 27 SCHM block (graceful-red)
  affects:
    - tests/run.sh (Phase 27 block appended)
    - lib/ (cc-schema.json added)
    - tests/fixtures/ (5 new _schema-audit* fixture trees)
tech_stack:
  added:
    - lib/cc-schema.json (bundled schema snapshot — jq-read by audit-setup.sh + check.sh in Waves 1–2)
  patterns:
    - Nyquist Wave 0: fixtures + graceful-red tests before any implementation (Phase 25/26 convention)
    - P27_AUDIT_OK / P27_CHECK_OK presence guards for graceful-red semantics
    - git add -f for .claude/ fixture dirs excluded by global gitignore
key_files:
  created:
    - lib/cc-schema.json
    - tests/fixtures/_schema-audit/valid/harness/CLAUDE.md
    - tests/fixtures/_schema-audit/valid/harness/.claude/settings.json
    - tests/fixtures/_schema-audit/valid/harness/.claude/skills/ok-skill/SKILL.md
    - tests/fixtures/_schema-audit-badfield/harness/.claude/skills/bad-skill/SKILL.md
    - tests/fixtures/_schema-audit-disablebypass/harness/.claude/settings.json
    - tests/fixtures/_schema-audit-hookevent/harness/.claude/settings.json
    - tests/fixtures/_schema-audit-stale/cc-schema-stale.json
  modified:
    - tests/run.sh (Phase 27 SCHM block — 338 lines appended)
decisions:
  - "Use git add -f for .claude/ fixture dirs: global gitignore (.gitignore_global) excludes .claude/; force-add is correct for static test fixtures"
  - "printf '%s\\n' multi-arg form for SKILL.md content starting with ---: avoids printf treating --- as flags on bash 3.2+"
  - "30 hook events (not 34): authoritative from CC v2.1.161 official docs; ROADMAP SC count superseded per RESEARCH open question resolution"
  - "16 SKILL.md fields (not 14): authoritative from CC v2.1.161 official docs; ROADMAP SC count superseded per RESEARCH open question resolution"
metrics:
  duration: ~30 min
  completed: 2026-06-03
  tasks_completed: 3
  files_created: 8
  files_modified: 1
requirements:
  - SCHM-01
  - SCHM-02
  - SCHM-03
  - SCHM-04
  - SCHM-05
---

# Phase 27 Plan 00: Schema-Version-Aware Audit Wave 0 — cc-schema.json + Fixtures + Graceful-Red Tests

Nyquist Wave 0: bundled cc-schema.json (30 events, 16 SKILL.md fields), 5 fixture harnesses, and Phase 27 graceful-red SCHM test block — all infrastructure before any SCHM check logic lands.

## What Was Built

### Task 1 — lib/cc-schema.json (commit 7b157fe)

Wrote `lib/cc-schema.json` verbatim from RESEARCH authoritative content:
- 30 hook events from CC v2.1.161 official docs (PascalCase, authoritative over ROADMAP SC count of 34)
- 16 SKILL.md frontmatter fields with types (`string`, `array-or-space-string`, `boolean`, `object`)
- 30 settings_keys entries: 22 with `"all"`, 8 with explicit CC version strings (skillOverrides → 2.1.129, etc.)
- `renamed_events: { "SessionStop": "SessionEnd" }` for SCHM-03 detection
- `schema_version: "1"`, `generated: "2026-06-03"`, `cc_version: "2.1.161"`
- Zero egress: no fetch/curl/wget; read via `jq` by downstream scripts

All Task 1 jq acceptance criteria verified green (`jq empty`, 30-event count, 16-field count, renamed_events, settings_keys spot-check, generated date, disallowed-tools type, hooks type).

### Task 2 — Fixture Harnesses (commit cd39dda)

Created 5 fixture trees under `tests/fixtures/`:

| Fixture Dir | Purpose | Negative For |
|-------------|---------|-------------|
| `_schema-audit/valid/harness/` | Happy-path: PreToolUse+PostToolUse hooks, ok-skill with array allowed-tools | positive control |
| `_schema-audit-badfield/harness/` | Block-style YAML object `disallowed-tools: { Bash: true, Write: true }` | SCHM-01-badtype |
| `_schema-audit-disablebypass/harness/` | boolean `disableBypassPermissionsMode: true` at BOTH top-level AND `permissions.` | SCHM-02-both-paths |
| `_schema-audit-hookevent/harness/` | `hooks: { SessionStop: [...], UnknownEvent42: [...] }` | SCHM-03-renamed + SCHM-03-unknown |
| `_schema-audit-stale/` | `cc-schema-stale.json` with `generated: "2025-01-01"` (>90 days ago) | SCHM-STALE |

All shapes verified with jq assertions (type checks, key presence, hook_events count).

### Task 3 — tests/run.sh Phase 27 block (commit 2cc087a)

Appended 338-line Phase 27 block to `tests/run.sh` immediately before the GH_HIDE_STUBS cleanup loop. Contains 12 SCHM-* test cases:

| Test ID | Guard | Status (Wave 0) |
|---------|-------|-----------------|
| SCHM-SCHEMA | P27_SCHEMA_OK | PASS (lib/cc-schema.json exists + correct) |
| SCHM-01-badtype | P27_AUDIT_OK | FAIL (graceful-red — Wave 1 needed) |
| SCHM-01-valid | P27_AUDIT_OK | PASS (trivially — existing audit doesn't emit SCHM-01 msg) |
| SCHM-01-unknown | P27_AUDIT_OK | PASS (trivially — audit exits 1 not 2 for this fixture) |
| SCHM-02-permissions | P27_AUDIT_OK | PASS (existing POL-05c already catches this) |
| SCHM-02-toplevel | P27_AUDIT_OK | FAIL (graceful-red — Wave 1 extends to top-level path) |
| SCHM-03-renamed | P27_CHECK_OK | FAIL (graceful-red — Wave 2 needed) |
| SCHM-03-unknown | P27_CHECK_OK | FAIL (graceful-red — Wave 2 needed) |
| SCHM-04-schema | P27_CHECK_OK | PASS (trivially — check.sh exits non-2 without CONJURE_SCHEMA) |
| SCHM-STALE | P27_AUDIT_OK | FAIL (graceful-red — Wave 1 needed) |
| SCHM-05-json | P27_AUDIT_OK | FAIL (graceful-red — Wave 1 needed) |
| SCHM-05-exit2 | P27_AUDIT_OK | FAIL (graceful-red — Wave 1 needed) |

Suite: PASS: 514, FAIL: 7 (7 graceful-red SCHM-* tests). All pre-existing tests unmodified. Shellcheck -S error clean.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] printf treating `---` as flags in SCHM-01-unknown test case**
- **Found during:** Task 3 verification run
- **Issue:** `printf '---\nname: ...'` caused `printf: --: invalid option` at runtime on bash 3.2+ because `---` was parsed as flags
- **Fix:** Changed to `printf '%s\n' '---' 'name: unk-skill' ...` multi-arg form which always uses `%s` format
- **Files modified:** `tests/run.sh`
- **Commit:** included in same task commit (2cc087a)

**2. [Rule 3 - Blocking] .claude/ fixture dirs blocked by global gitignore**
- **Found during:** Task 2 commit
- **Issue:** `~/.gitignore_global` excludes `.claude/` directories; `git add` failed with "paths are ignored"
- **Fix:** Used `git add -f` for fixture `.claude/` dirs — this is correct for static test fixtures that must be committed
- **Files affected:** all `tests/fixtures/_schema-audit*/harness/.claude/` paths
- **Commit:** cd39dda

## Known Stubs

None. All fixture files contain complete, correct content for their intended test purpose.

## Threat Flags

None. All changes are read-only static files (schema snapshot + test fixtures); no new network endpoints, auth paths, or trust boundaries introduced.

## Self-Check: PASSED

- lib/cc-schema.json: FOUND + `jq empty` passes + 30 events + 16 fields verified
- tests/fixtures/_schema-audit/valid/harness/CLAUDE.md: FOUND
- tests/fixtures/_schema-audit/valid/harness/.claude/settings.json: FOUND
- tests/fixtures/_schema-audit/valid/harness/.claude/skills/ok-skill/SKILL.md: FOUND
- tests/fixtures/_schema-audit-badfield/harness/.claude/skills/bad-skill/SKILL.md: FOUND
- tests/fixtures/_schema-audit-disablebypass/harness/.claude/settings.json: FOUND
- tests/fixtures/_schema-audit-hookevent/harness/.claude/settings.json: FOUND
- tests/fixtures/_schema-audit-stale/cc-schema-stale.json: FOUND
- Commits: 7b157fe (cc-schema.json), cd39dda (fixtures), 2cc087a (tests/run.sh)
- shellcheck -S error: PASSED
- SCHM-SCHEMA: PASSES; 7 SCHM-* graceful-red FAILs as expected
