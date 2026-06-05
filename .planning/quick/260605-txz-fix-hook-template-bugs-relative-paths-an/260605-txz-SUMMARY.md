---
phase: quick
plan: 260605-txz
subsystem: hooks/templates
tags: [bug-fix, hooks, templates, telemetry]
dependency_graph:
  requires: []
  provides: [correct-hook-paths, UserPromptSubmit-event]
  affects: [templates/settings.json.tmpl, templates/hooks-nodejs/skill-telemetry.mjs]
tech_stack:
  added: []
  patterns: [CLAUDE_PROJECT_DIR absolute path, UserPromptSubmit prompt-field parsing]
key_files:
  created: []
  modified:
    - templates/settings.json.tmpl
    - templates/hooks-nodejs/skill-telemetry.mjs
    - tests/run.sh
    - TELEMETRY.md
decisions:
  - "Use CLAUDE_PROJECT_DIR env var (set by Claude Code runtime) for absolute hook paths"
  - "Parse skill name from leading slash-token of p.prompt string; discard arguments per T-txz-01 PII mitigation"
metrics:
  duration: 18min
  completed: 2026-06-05
---

# Phase quick Plan 260605-txz: Fix Hook Template Bugs (Relative Paths and UserPromptExpansion) Summary

Fixed two dead-on-arrival hook bugs in templates/settings.json.tmpl: all 7 `node` hook commands now use absolute paths via `"$CLAUDE_PROJECT_DIR"` and `UserPromptExpansion` is replaced with `UserPromptSubmit` with correct `p.prompt` field parsing.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Fix relative hook paths in settings.json.tmpl | 65c95f1 | templates/settings.json.tmpl |
| 2 | Rename UserPromptExpansion to UserPromptSubmit across template, hook, tests, docs | 58caa39 | templates/settings.json.tmpl, templates/hooks-nodejs/skill-telemetry.mjs, tests/run.sh, TELEMETRY.md |

## What Was Built

**Bug 1 — Absolute hook paths:** Every `node .claude/hooks/<x>.mjs` command in the settings template now uses `node "$CLAUDE_PROJECT_DIR"/.claude/hooks/<x>.mjs`. The graphify SessionStart command now uses `"$CLAUDE_PROJECT_DIR"` instead of `.` as its target. All 7 hook commands plus the graphify line are fixed. Harnesses generated with `conjure init` will no longer ship broken hooks that fail when Claude navigates subdirectories.

**Bug 2 — UserPromptSubmit event:** `UserPromptExpansion` was wrong; the correct Claude Code event is `UserPromptSubmit`. The hook now matches `UserPromptSubmit`, reads the skill name by extracting the first whitespace-delimited token from `p.prompt` when it starts with `/`, and strips the leading slash. Arguments are silently discarded per T-txz-01 PII mitigation. `p.cwd` fallback retained. The test block (TLMY-02b), doc table, and template event key are all updated.

## Deviations from Plan

None — plan executed exactly as written.

## Verification Results

| Check | Result |
|-------|--------|
| `jq empty templates/settings.json.tmpl` | PASS |
| `node --check templates/hooks-nodejs/skill-telemetry.mjs` | PASS |
| Zero `UserPromptExpansion` in template/hook/test/docs | PASS |
| Zero `node .claude/hooks/` relative paths in template | PASS |
| TLMY-02b exits 0 (UserPromptSubmit path) | PASS |
| TLMY-02b JSONL write test | FAIL (pre-existing env constraint: `mktemp -d` creates sandbox in `/var/folders/...` which is blocked by sandbox security policy; hook writes correctly to `$TMPDIR`-based paths as verified manually) |

**TLMY-02b JSONL note:** The hook writes correctly when `cwd` resolves to `$TMPDIR`-accessible paths (verified manually: `printf '...' | CONJURE_TELEMETRY=1 node skill-telemetry.mjs` correctly produces JSONL in `$TMPDIR/.../.claude/telemetry/skill-events.jsonl`). The test framework's `mktemp -d` creates sandboxes in `/var/folders/...` which is restricted in this execution environment. TLMY-02 (PreToolUse path) also fails for the same reason — pre-existing.

## Known Stubs

None.

## Threat Flags

None — no new network endpoints, auth paths, or trust boundaries introduced.

## Self-Check: PASSED

- `templates/settings.json.tmpl` exists and passes `jq empty`
- `templates/hooks-nodejs/skill-telemetry.mjs` exists and passes `node --check`
- `tests/run.sh` updated (TLMY-02b block + template lint assertion)
- `TELEMETRY.md` updated (event schema table)
- Commits 65c95f1 and 58caa39 exist in git log
