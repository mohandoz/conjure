---
phase: 09-3-way-merge
plan: "02"
subsystem: cli
tags: [merge, cli, bash, cmd_init, cmd_update, snapshot, 3-way-merge]
dependency_graph:
  requires: [lib/merge.sh, lib/mutate.sh]
  provides: [cmd_init snapshot write, cmd_update --apply real merge]
  affects: [cli/conjure]
tech_stack:
  added: []
  patterns: [source-lib-inside-function, backup-before-mutate, mutate_cp-for-snapshot]
key_files:
  created: []
  modified:
    - cli/conjure
decisions:
  - "Sourced lib/mutate.sh + lib/merge.sh inside --apply branch (not at script top) — matches plan spec and avoids sourcing overhead on --check path"
  - "local merge_rc=$? is SC2155-safe because $? is variable expansion, not command substitution"
  - "Backup cp -R not guarded by DRY_RUN — cmd_update has no --dry-run flag; matches cmd_migrate pattern"
  - "MERGE-04: only settings.json.tmpl taken unconditionally; .conjure-version stamped via mutate_write at clean-run end"
metrics:
  duration: "~10 min"
  completed: "2026-05-25"
  tasks_completed: 3
  files_created: 0
  files_modified: 1
requirements:
  - MERGE-01
  - MERGE-02
  - MERGE-03
  - MERGE-04
---

# Phase 09 Plan 02: CLI Integration Summary

**One-liner:** Modified cli/conjure with cmd_init snapshot write (5 mutate_* calls into .conjure-templates-VERSION/) and cmd_update --apply real 3-way merge (sources lib/merge.sh, D-01 abort, MERGE-04 passthrough, merge_user_files, D-06 conflict reporting).

## What Was Built

### cmd_init snapshot write (MERGE-02, D-03)

After `mutate_write "$target/.claude/.conjure-version"` and before `mutate_summary`, inserted:

```bash
local snap_dir="$target/.claude/.conjure-templates-${CONJURE_VERSION}"
mutate_mkdir "$snap_dir"
mutate_cp "$CONJURE_HOME/templates/CLAUDE.md.tmpl" "$snap_dir/CLAUDE.md.tmpl"
mutate_cp "$CONJURE_HOME/templates/skills"          "$snap_dir/skills"
mutate_cp "$CONJURE_HOME/templates/agents"          "$snap_dir/agents"
mutate_cp "$CONJURE_HOME/templates/hooks-nodejs"    "$snap_dir/hooks"
echo "▸ Snapshot written: $snap_dir"
```

Scope: user-owned files only (CLAUDE.md.tmpl, skills/, agents/, hooks/). NOT settings.json or .conjure-version (per D-03). DRY_RUN safety automatic via mutate_mkdir/mutate_cp.

### cmd_update --apply real merge (MERGE-01, MERGE-03, MERGE-04, D-01, D-06)

Replaced the 3-line placeholder with full implementation:

1. Sources `lib/mutate.sh` then `lib/merge.sh` (mutate.sh first — merge.sh depends on mutate_write)
2. D-01: checks `$target/.claude/.conjure-templates-${pinned}/` exists — aborts with correct message if missing
3. Backup: `cp -R "$target/.claude" "$backup"` (timestamp-suffixed, always live — no dry-run flag on cmd_update)
4. MERGE-04: `mutate_cp settings.json.tmpl → .claude/settings.json` unconditionally (generated file, no ancestor)
5. MERGE-01: calls `merge_user_files "$target" "$snap_dir" "$CONJURE_VERSION" "$pinned"` from lib/merge.sh
6. rc=2: abort with error message, return 2
7. D-06: if `CONJURE_MERGE_CONFLICT_COUNT > 0`: print list of sidecar paths, instructions, exit 1
8. Clean: `mutate_write .conjure-version "$CONJURE_VERSION"`, `mutate_summary`, exit 0

## Smoke Test Results

| Test | Result |
|------|--------|
| `conjure init /tmp/test` creates `.conjure-templates-0.2.1/` | PASS |
| Snapshot contains CLAUDE.md.tmpl, skills/, agents/, hooks/ | PASS |
| `conjure update --apply` with missing snapshot prints D-01 message | PASS |
| Stub "Interactive update not yet implemented" absent | PASS |

## Deviations from Plan

None — plan executed exactly as written.

## Shellcheck Compliance

Shellcheck not installed locally (darwin; CI-only as documented in 09-01-SUMMARY.md). Manual review confirmed:

- No SC2155 violations: `local ts; ts="$(date ...)"` two-line form used for command substitution
- `local merge_rc=$?` is SC2155-safe — `$?` is variable expansion, not command substitution
- No SC2044 violations: no new find loops in this plan
- No SC2034 violations: all locals (`snap_dir`, `ts`, `backup`, `merge_rc`) are referenced
- No SC2164 violations: no `cd` calls in new code
- Existing violations (e.g., line 53: `local ... target="$(pwd)"`) are pre-existing and out-of-scope per scope boundary rule

## Threat Model Check

- T-09-04 (snap_dir path injection): accepted — `pinned` read from `.conjure-version`, used only as directory suffix, not executed
- T-09-05 (backup cp -R): accepted — copies existing `.claude/`, no new secret surface
- T-09-06 (sidecar placement): accepted — sidecars placed next to originals, no new disclosure

## Known Stubs

None — cmd_update --apply stub fully replaced; cmd_init snapshot write fully implemented.

## Self-Check: PASSED

| Check | Result |
|-------|--------|
| `grep -n 'conjure-templates' cli/conjure` shows lines 90, 191 | PASS |
| `grep -n 'No base snapshot' cli/conjure` shows line 195 | PASS |
| `grep -n 'merge_user_files' cli/conjure` shows line 216 | PASS |
| stub "Interactive update not yet implemented" absent | PASS |
| git log shows commit b04cd1e with cli/conjure | PASS |
| Smoke test: snapshot dir created with 4 expected subdirs/files | PASS |
| Smoke test: D-01 abort message printed correctly | PASS |
