---
phase: "25"
plan: "00"
subsystem: tests
tags: [wave-0, test-fixtures, graceful-red, plugin-emission, nyquist]
dependency_graph:
  requires: []
  provides:
    - tests/fixtures/_emit-plugin/harness/
    - tests/fixtures/_emit-plugin/expected-plugin.json
    - tests/fixtures/_emit-plugin/expected-marketplace.json
    - tests/fixtures/_emit-plugin/expected-settings.json
    - tests/fixtures/_emit-plugin-secret/harness/
    - Phase-25-test-block-in-tests/run.sh
  affects:
    - tests/run.sh (appended Phase 25 block)
tech_stack:
  added: []
  patterns:
    - Nyquist Wave 0 graceful-red: fixtures + test block before feature code
    - mktemp sandbox with EXIT-trap per test case
    - P25_EMIT_OK presence guard for graceful-red during feature wave development
key_files:
  created:
    - tests/fixtures/_emit-plugin/harness/CLAUDE.md
    - tests/fixtures/_emit-plugin/harness/.claude/skills/git/SKILL.md
    - tests/fixtures/_emit-plugin/harness/.claude/agents/code-explorer.md
    - tests/fixtures/_emit-plugin/harness/.claude/settings.json
    - tests/fixtures/_emit-plugin/harness/.mcp.json
    - tests/fixtures/_emit-plugin/harness/.conjure-version
    - tests/fixtures/_emit-plugin/expected-plugin.json
    - tests/fixtures/_emit-plugin/expected-marketplace.json
    - tests/fixtures/_emit-plugin/expected-settings.json
    - tests/fixtures/_emit-plugin-secret/harness/.claude/skills/git/SKILL.md
    - tests/fixtures/_emit-plugin-secret/harness/.claude/settings.json
    - tests/fixtures/_emit-plugin-secret/harness/.claude-plugin/plugin.json
  modified:
    - tests/run.sh
decisions:
  - Fixture CLAUDE files force-added with git add -f because global gitignore_global ignores .claude/ dirs
  - Secret fixture uses a clearly-fake 38-char credential value (labeled testonly) to trigger Pattern 5 regex
  - PLUG-REC and PLUG-REFSHA tests verify audit-setup.sh extensions from Wave 1; they fail gracefully (audit-setup.sh not extended yet)
metrics:
  duration: 19
  completed: "2026-06-03T02:05:45Z"
  tasks: 2
  files: 13
---

# Phase 25 Plan 00: Wave 0 Test Infrastructure Summary

Golden fixture harness and graceful-red Phase 25 test block for plugin + marketplace emission, establishing the Nyquist Wave 0 invariant before any feature code.

## What Was Built

**Task 1: Golden fixture harness and expected output files**

Two fixture trees under `tests/fixtures/`:

- `_emit-plugin/harness/`: minimal conjure `.claude/` harness with skill (git/SKILL.md), agent (code-explorer.md), settings.json with hooks + empty `extraKnownMarketplaces`, .mcp.json, and .conjure-version (0.1.0)
- `_emit-plugin/expected-plugin.json`: golden plugin manifest (name: test-plugin, version: 0.1.0, skills, agents, hooks, mcpServers)
- `_emit-plugin/expected-marketplace.json`: golden marketplace manifest (name, owner, plugins[] with local source)
- `_emit-plugin/expected-settings.json`: golden settings after `extraKnownMarketplaces` wiring
- `_emit-plugin-secret/harness/`: secret-pattern fixture with a clearly-fake 38-char value in the api_key field of .claude-plugin/plugin.json to trigger the Pattern 5 secret scan regex (T-25-W0-01 mitigation: labeled "testonly-fake" per threat model)

**Task 2: Phase 25 graceful-red test block in tests/run.sh**

Appended 302 lines before the `GH_HIDE_STUBS` cleanup loop. Section: `# Phase 25 — Plugin + Marketplace Emission (PLUG-01..PLUG-05)`. All 13 PLUG-* test cases implemented with:
- Individual mktemp sandboxes and EXIT-trap cleanup
- P25_EMIT_OK presence guard (emit-plugin.sh absent => graceful FAIL, not crash)
- git-init sandboxes for emit tests requiring a git repo
- POSIX 3.2+ compliant (no associative arrays, no mapfile)

After this plan: `bash tests/run.sh` exits with FAIL: 13 (graceful-red). Pre-existing 467 PASS tests are unaffected.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Global gitignore excludes .claude/ fixture dirs**
- **Found during:** Task 1 staging
- **Issue:** `~/.gitignore_global` has `.claude/` pattern that prevented `git add` on fixture .claude/ directories
- **Fix:** Used `git add -f` to force-add test fixture files (correct behavior — these are committed test artifacts, not the user's own .claude/ config)
- **Files modified:** None (staging fix only)
- **Commit:** 55ebddc

### Known Deviations

**Plan verification command mismatch:** The plan's acceptance criteria says `bash tests/run.sh 2>&1 | grep PLUG | grep FAIL` should produce non-empty output. The `fail()` helper in tests/run.sh outputs `✗ message` (not "FAIL message"), so `grep FAIL` finds no PLUG lines. The actual graceful-red behavior IS correct: 13 PLUG tests fail with `✗` markers, suite exits 1, `PASS: 467    FAIL: 13`. The verification command in the plan was written incorrectly — it should be `grep PLUG | grep "✗"`. This is a documentation issue in the plan, not a code issue.

**PLUG-REC and PLUG-REFSHA fail with rc=2 (expected):** `audit-setup.sh` does not yet have the Phase 25 reconciliation sections. These tests will pass after Wave 1 modifies `scripts/audit-setup.sh`.

## Tests

**Graceful-red state (correct for Wave 0):**
- `bash tests/run.sh` exits 1 (non-zero) — confirmed
- PASS: 467    FAIL: 13 — confirmed
- All 13 PLUG-* tests fail with "emit-plugin.sh not found" or "audit-setup not extended yet" — confirmed
- All pre-existing 467 tests still pass — confirmed
- `shellcheck -S error -e SC2164,SC2044,SC2034,SC2155 tests/run.sh` passes — confirmed
- All fixture JSON files pass `jq empty` — confirmed

## Threat Surface

No new network endpoints, auth paths, or file access patterns introduced. Fixture files are static test data authored by the conjure team (not user input). The secret fixture contains a clearly-labeled fake credential value per T-25-W0-01 threat mitigation.

## Self-Check: PASSED

- [x] tests/fixtures/_emit-plugin/harness/.claude/skills/git/SKILL.md exists
- [x] tests/fixtures/_emit-plugin/expected-plugin.json is valid JSON with name == "test-plugin"
- [x] tests/fixtures/_emit-plugin/expected-marketplace.json is valid JSON with plugins array
- [x] tests/fixtures/_emit-plugin/expected-settings.json is valid JSON with extraKnownMarketplaces object
- [x] tests/fixtures/_emit-plugin-secret/harness/.claude-plugin/plugin.json is valid JSON with api_key value >= 6 chars
- [x] tests/run.sh contains Phase 25 header
- [x] All 13 PLUG-* tags present in tests/run.sh
- [x] bash tests/run.sh exits non-zero with FAIL: 13 (graceful-red)
- [x] Commit 55ebddc exists (Task 1)
- [x] Commit b85c3dd exists (Task 2)
