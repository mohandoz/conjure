---
phase: quick-260605-tlg
plan: "01"
subsystem: graphify-integration
tags: [graphify, backend-autodetect, shell, settings-template]
dependency_graph:
  requires: []
  provides: [TLG-01, TLG-02, TLG-03, TLG-04]
  affects: [scripts/refresh-graph.sh, templates/settings.json.tmpl, cli/conjure]
tech_stack:
  added: []
  patterns: [POSIX bash 3.2+ arg parsing, exit-2-never-1, failure-tolerant subcommand guards]
key_files:
  created: []
  modified:
    - scripts/refresh-graph.sh
    - templates/settings.json.tmpl
    - cli/conjure
decisions:
  - "Claude backend probe uses read-only python3 -c 'import anthropic' then falls through to OPENAI detection if missing (not abort)"
  - "--setup steps individually guarded with || { warn; } so one failure never aborts remaining steps"
  - "SessionStart graphify hook uses command -v guard + 2>/dev/null + || true — never blocks session start (T-tlg-04 mitigate)"
  - "--backend value passed as quoted variable to graphify extract — no eval, no injection surface (T-tlg-01 mitigate)"
metrics:
  duration: "15min"
  completed: "2026-06-05"
  tasks_completed: 2
  files_modified: 3
---

# Phase quick-260605-tlg Plan 01: Upgrade Graphify Integration — Backend Auto-detect Summary

**One-liner:** Backend auto-detect in refresh-graph.sh (GEMINI→claude→openai→deepseek→kimi priority, anthropic probe, AST-only fallback with hint) plus SessionStart freshness hook and updated CLI usage.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Rewrite refresh-graph.sh with backend auto-detect and --setup flag | 9ccc8fb | scripts/refresh-graph.sh |
| 2 | Add SessionStart graphify hook and update CLI usage lines | 960101a | templates/settings.json.tmpl, cli/conjure |

## What Was Built

### Task 1 — scripts/refresh-graph.sh

Complete rewrite of the graphify integration script. Key changes:

- **POSIX arg parsing**: sequential scan of `$@`, no getopt, no associative arrays — bash 3.2+ compatible
- **Backend detection** (`detect_backend`): priority order GEMINI_API_KEY → ANTHROPIC_API_KEY → OPENAI_API_KEY → DEEPSEEK_API_KEY → MOONSHOT_API_KEY; sets `DETECTED_BACKEND` in caller scope
- **Claude probe**: `python3 -c "import anthropic"` read-only check; if missing, prints one-line warning and re-runs detection skipping claude entry
- **`--ast-only` flag**: bypasses all detection, forces `graphify update .`
- **`--backend` flag**: overrides auto-detection entirely
- **Build dispatch**: full build uses `graphify extract . --backend "$DETECTED_BACKEND"` when backend found, else `graphify update .` with export hint; incremental always uses `graphify update .`
- **`--setup` flag** (4 idempotent steps, each individually failure-tolerant):
  1. Appends `graphify-out/` to `.git/info/exclude` (idempotency via `grep -qF`)
  2. `graphify global add` with repo basename as tag
  3. `graphify claude install`
  4. `graphify hook install`
- **exit 2 throughout** (never exit 1), `set -euo pipefail`

Smoke test results (all passing):
- No API keys → `graphify update .` (AST-only path) with tip
- `GEMINI_API_KEY` set → `graphify extract . --backend gemini`
- `--ast-only` with keys set → forced `graphify update .`
- `--backend claude` without anthropic package → fallback warning + AST-only path
- No graphify in PATH → exit 2 with install hint

### Task 2 — templates/settings.json.tmpl + cli/conjure

**settings.json.tmpl:**
- `SessionStart.hooks` array gains second entry: graphify check-update one-liner with `command -v` guard, `2>/dev/null`, and `|| true` — never blocks session start
- `permissions.allow` gains `"Bash(graphify check-update:*)"` alongside existing graphify entries

**cli/conjure:**
- Top comment block (line ~14): `refresh-graph` usage updated to include `[--backend <name>] [--ast-only] [--setup]`
- `usage()` function: same update to the `conjure refresh-graph` line
- No functional changes; `cmd_refresh_graph` already passes `$@` through unchanged

## Deviations from Plan

None — plan executed exactly as written.

## Verification Results

| Check | Result |
|-------|--------|
| `shellcheck -S error -e SC2164,SC2044,SC2034,SC2155 scripts/refresh-graph.sh` | PASS |
| `jq empty templates/settings.json.tmpl` | PASS |
| No-graphify → exit 2 with install hint | PASS |
| `graphify check-update` in template (SessionStart hook + permissions.allow) | 2 matches |
| `--setup`, `--backend`, `--ast-only` in cli/conjure (comment + usage) | 2 matches each |

## Known Stubs

None.

## Threat Surface Scan

No new network endpoints, auth paths, or schema changes beyond what was declared in the plan's threat model. All T-tlg-01 through T-tlg-SC dispositions honored:
- `--backend` value quoted, no eval (T-tlg-01 mitigate)
- `graphify check-update` fully guarded with `|| true` and `2>/dev/null` (T-tlg-04 mitigate)

## Self-Check: PASSED

- `scripts/refresh-graph.sh` exists and shellcheck-clean
- `templates/settings.json.tmpl` is valid JSON with 2 graphify check-update occurrences
- `cli/conjure` has --setup/--backend/--ast-only in both usage locations
- Commits 9ccc8fb and 960101a both exist in git log
