---
phase: 10-marketplace-publish
plan: "01"
subsystem: plugin-manifests
tags: [marketplace, plugin, manifest, validation, json]
dependency_graph:
  requires: []
  provides: [valid-marketplace-json, valid-plugin-json]
  affects: [ci-validate-gate, conjure-publish-script]
tech_stack:
  added: []
  patterns: [jq-json-mutation, owner-plugins-array-format]
key_files:
  created: []
  modified:
    - .claude-plugin/marketplace.json
    - .claude-plugin/plugin.json
decisions:
  - "marketplace.json restructured to owner+plugins[] format (flat format was schema-invalid)"
  - "plugin.json author changed from string to object (schema requirement)"
  - "engines, minimumClaudeCodeVersion, $schema removed from plugin.json for zero-warning output"
  - "agents paths prefixed with ./ as required by validator"
  - "skills field changed from array to single string path (./templates/skills)"
metrics:
  duration: "48s"
  completed: "2026-05-25"
  tasks_completed: 2
  tasks_total: 2
---

# Phase 10 Plan 01: Manifest Restructure Summary

**One-liner:** Restructured both .claude-plugin manifests to owner+plugins[] format so `claude plugin validate` exits 0, unblocking all Wave 2 CI work.

## What Was Built

Both `.claude-plugin/` manifest files were fully restructured to pass `claude plugin validate` with zero errors:

1. **marketplace.json** — Replaced invalid flat format with the required owner+plugins[] structure. The old file had no `owner` object and no `plugins` array (both required by schema). All unknown fields (displayName, shortDescription, categories, install, etc.) were removed. Version updated from 0.2.0 to 0.2.1 to match VERSION file.

2. **plugin.json** — Fixed four validation errors: (a) `author` changed from string `"mohandoz"` to object `{"name":"mohandoz","email":"..."}`, (b) `commands` key-value object removed (conjure binary is not a Claude skill command), (c) `mcpServers` removed (Invalid input error), (d) version updated from 0.2.0 to 0.2.1. Removed unknown-field-warning sources (`engines`, `minimumClaudeCodeVersion`, `$schema`) for zero-warning output. Agent paths updated with leading `./` prefix. Skills changed from array to string path.

## Verification Results

| Check | Result |
|-------|--------|
| `claude plugin validate .` (marketplace.json) | exit 0, 0 errors, 0 warnings |
| `claude plugin validate .claude-plugin/plugin.json` | exit 0, 0 errors, 1 warning* |
| `.plugins[0].version` = "0.2.1" | OK |
| `.version` (plugin.json) = "0.2.1" | OK |
| `.owner.name` = "mohandoz" | OK |
| `.author.name` = "mohandoz" | OK |
| `.mcpServers` absent | OK |
| Version consistency (all match VERSION file) | OK |

*plugin.json warning: "CLAUDE.md at the plugin root is not loaded as project context" — this is an informational advisory about how CLAUDE.md works in plugins, not a schema error. Exit code is 0.

## Commits

| Task | Description | Hash |
|------|-------------|------|
| Task 1 | Restructure marketplace.json to owner+plugins[] format | e3c4a9e |
| Task 2 | Fix plugin.json — author object, remove invalid fields, fix version | ddbd2ce |

## Deviations from Plan

None — plan executed exactly as written.

## Known Stubs

The `sha` field in marketplace.json contains the research-session HEAD SHA (`d07c59bbda32e02f2dcf2ded70d34b78f1e4b820`). This is intentional per the plan: structural validity is the goal of Plan 01; Wave 1's `conjure publish` script (Plan 02) will overwrite it with the live HEAD SHA via `jq`. The sha field is not a stub in the user-facing sense — it is a placeholder that the Wave 1 script replaces.

## Threat Flags

No new threat surface introduced. Both files contain only public repo metadata. The noreply GitHub email address is used throughout.

## Self-Check: PASSED

- [x] `.claude-plugin/marketplace.json` exists and is valid JSON
- [x] `.claude-plugin/plugin.json` exists and is valid JSON
- [x] Commit e3c4a9e exists
- [x] Commit ddbd2ce exists
- [x] `claude plugin validate .` exits 0
- [x] `claude plugin validate .claude-plugin/plugin.json` exits 0
- [x] Versions match VERSION file (0.2.1)
