---
phase: quick-260605-sv6
plan: "01"
subsystem: templates/fixtures
tags: [bugfix, settings-json, schema-validation, permissions]
dependency_graph:
  requires: []
  provides: [valid-settings-json-template, consistent-fixtures]
  affects: [templates/settings.json.tmpl, tests/fixtures/*/settings.json]
tech_stack:
  added: []
  patterns: []
key_files:
  created: []
  modified:
    - templates/settings.json.tmpl
    - tests/fixtures/data-science/.claude/settings.json
    - tests/fixtures/go-gin/.claude/settings.json
    - tests/fixtures/java-spring/.claude/settings.json
    - tests/fixtures/monorepo/.claude/settings.json
    - tests/fixtures/node-nest/.claude/settings.json
    - tests/fixtures/polyglot/.claude/settings.json
    - tests/fixtures/python-fastapi/.claude/settings.json
    - tests/fixtures/rust-axum/.claude/settings.json
    - tests/fixtures/ts-next/.claude/settings.json
decisions:
  - "Use Bash(:*) as the deny rule for colon-prefix commands: covers fork-bomb start tokens without parentheses that break Claude Code's permission rule parser"
  - "Correct schema URL is https://json.schemastore.org/claude-code-settings.json (not schemastore.org without the json. subdomain)"
metrics:
  duration: "8 min"
  completed: "2026-06-05"
  tasks_completed: 3
  files_modified: 10
---

# Phase quick-260605-sv6 Plan 01: Fix Invalid settings.json Template Schema Summary

**One-liner:** Fixed wrong $schema URL (schemastore.org -> json.schemastore.org) and replaced parser-breaking fork-bomb deny rule with Bash(:*) in template and all 9 non-underscore fixtures, restoring the Claude Code permission harness to functional status.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Fix template: correct schema URL and deny rule | f0f3bb8 | templates/settings.json.tmpl |
| 2 | Propagate fix to all 9 non-underscore stack fixtures | 432409a | 9 fixture settings.json files |
| 3 | Run template-lint checks, confirm no regressions | (no code change) | — |

## What Was Fixed

**Bug 1 — Wrong $schema URL:**
- Old: `"$schema": "https://schemastore.org/claude-code-settings.json"`
- New: `"$schema": "https://json.schemastore.org/claude-code-settings.json"`
- Impact: Claude Code validates an exact string match for the schema URL. The wrong subdomain caused Claude Code to silently discard the entire settings file, making ALL allow/deny rules dead.

**Bug 2 — Parser-breaking deny rule:**
- Old: `"Bash(:(){:|:&};:)"` — parentheses and braces in the rule string crash the Claude Code permission parser
- New: `"Bash(:*)"` — colon-prefix glob that covers fork-bomb start tokens without parser-breaking characters; the pre-bash-block-destructive.mjs hook provides defense-in-depth for the actual fork-bomb pattern

## Verification Results

- `jq empty` on all 10 modified files: PASS (all valid JSON)
- `grep -rn 'schemastore.org/claude-code' templates/ tests/fixtures/ | grep -v json.schemastore | grep -v /_broken/`: empty (PASS)
- `grep -rn ':(){' templates/ tests/fixtures/ | grep -v /_broken/`: only pre-existing hit in `templates/hooks/pre-bash-block-destructive.sh` (detection logic, not a settings entry) — not introduced by this fix
- Template-lint: no bash hooks in template (PASS), node hooks present (PASS)
- `tests/fixtures/_broken/` untouched (confirmed via git status)

## Deviations from Plan

None — plan executed exactly as written.

## Known Stubs

None.

## Threat Flags

None — no new network endpoints, auth paths, or trust-boundary changes introduced.

## Self-Check

- [x] templates/settings.json.tmpl modified and committed (f0f3bb8)
- [x] All 9 non-underscore fixture settings.json files modified and committed (432409a)
- [x] _broken fixture unchanged
- [x] All JSON files pass `jq empty` validation
- [x] Template-lint checks pass

## Self-Check: PASSED
