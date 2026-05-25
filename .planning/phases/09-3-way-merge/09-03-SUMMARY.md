---
phase: 09-3-way-merge
plan: "03"
subsystem: audit-tests
tags: [merge, audit, tests, regression, shellcheck, bash]
dependency_graph:
  requires: [lib/merge.sh, cli/conjure (09-01, 09-02)]
  provides: [MERGE-05 conflict detection in audit-setup.sh, MERGE-01/02/03/04/05 regression tests]
  affects: [scripts/audit-setup.sh, tests/run.sh]
tech_stack:
  added: []
  patterns: [grep-rl-conflict-detection, mktemp-per-test-isolation, non-adjacent-merge-fixture]
key_files:
  created: []
  modified:
    - scripts/audit-setup.sh
    - tests/run.sh
decisions:
  - "MERGE-01 fixture uses non-adjacent lines (lineA + lineH separated by 6 lines) — adjacent lines are grouped into a single conflict hunk by git merge-file, breaking the clean-merge assertion"
  - "MERGE-04 uses pinned version 0.0.1 (not CONJURE_VERSION) to bypass the up-to-date guard in cmd_update"
  - "CONJURE_MERGE_CONFLICT_COUNT and CONJURE_MERGE_CONFLICT_FILES reset before each direct lib call to prevent carry-over between test blocks"
  - "audit-setup.sh uses err() not warn() for conflict markers — conflicts are a hard FAIL causing exit 2"
metrics:
  duration: "~4 min"
  completed: "2026-05-25"
  tasks_completed: 3
  files_created: 0
  files_modified: 2
requirements:
  - MERGE-01
  - MERGE-02
  - MERGE-03
  - MERGE-04
  - MERGE-05
---

# Phase 09 Plan 03: Audit + Regression Tests Summary

**One-liner:** Added MERGE-05 grep-based conflict marker detection to audit-setup.sh (exits 2 on unresolved markers, excludes .conjure-conflict-* sidecars) and five MERGE regression test blocks to tests/run.sh (all 216 tests pass, FAIL: 0).

## What Was Built

### Task 1: Conflict marker detection in scripts/audit-setup.sh (MERGE-05)

Inserted the following block immediately before the `# Summary` comment (the last check before the summary output):

```bash
# Conflict markers — detect unresolved 3-way merge conflicts (MERGE-05)
if [ -d .claude ]; then
  CONFLICT_FILES="$(grep -rl '^<<<<<<<' .claude/ 2>/dev/null \
    | grep -v '\.conjure-conflict-' || true)"
  if [ -n "$CONFLICT_FILES" ]; then
    err "Unresolved merge conflicts found in .claude/ — resolve and delete .conjure-conflict-* sidecars"
    printf '%s\n' "$CONFLICT_FILES" | while IFS= read -r cf; do
      [ -z "$cf" ] && continue
      note "  conflict markers: $cf"
    done
  else
    ok ".claude/: no unresolved conflict markers"
  fi
fi
```

Key implementation choices:
- Uses `err()` (not `warn()`) — conflict markers are a hard error, causing `FAIL++` and `exit 2`
- `grep -v '\.conjure-conflict-'` filter prevents false positives on sidecar files that intentionally contain markers (RESEARCH.md Pitfall 6)
- `CONFLICT_FILES` is an unqualified assignment (not `local`) — script top-level, not inside a function
- `printf '%s\n'` pipe form avoids heredoc — shellcheck-friendly

### Task 2: MERGE-01 through MERGE-05 regression tests in tests/run.sh (D-07, D-08)

Added a `▸ 3-way merge tests` section immediately before the `# Summary` block:

**MERGE-01 (clean merge):** Sources lib/mutate.sh and lib/merge.sh, creates synthetic test fixture with non-adjacent changed lines (lineA at top, lineH at bottom), calls `merge_file_3way` directly, asserts rc=0, merged file contains both user and upstream edits, no sidecar written.

**MERGE-02 (conflict):** Creates fixture where both user and upstream changed the same `conflict_line`, asserts rc=1, original file is untouched (no `<<<<<<<` in original — D-05 compliance), sidecar written at expected encoded path `.conjure-conflict-skills_testskill_SKILL.md`, sidecar contains conflict markers.

**MERGE-03 (missing snapshot):** Creates target with `.conjure-version` pointing to `0.1.0` but no `.conjure-templates-0.1.0/` directory, runs `cli/conjure update --apply` with a single invocation capturing both stdout and exit code, asserts non-zero exit and correct D-01 message "No base snapshot for v0.1.0".

**MERGE-04 (generated file passthrough):** Uses pinned version `0.0.1` (not `CONJURE_VERSION`) to bypass the up-to-date guard, creates stale `settings.json` with unique key `conjure_test_stale_key`, runs `conjure update --apply`, asserts the stale key is gone (replaced by upstream template) and no sidecar written for settings.json.

**MERGE-05 (audit detection):** Creates a real skill file (not a sidecar) with conflict markers, runs `audit-setup.sh` on the directory, asserts non-zero exit and "Unresolved merge conflicts" message.

### Task 3: Full suite validation

All verification checks confirmed:
- Conflict marker detection: `bash scripts/audit-setup.sh <dir-with-markers>` → exits 2, prints "Unresolved merge conflicts"
- Sidecar exclusion: `bash scripts/audit-setup.sh <dir-with-sidecar-only>` → no "Unresolved merge conflicts" output
- Full suite: `bash tests/run.sh` → PASS: 216, FAIL: 0

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed MERGE-01 test fixture: non-adjacent lines required for clean merge**

- **Found during:** Task 2 initial test run
- **Issue:** The plan's test fixture had `line3: UPSTREAM_EDIT` and `line4: USER_EDIT` as adjacent lines. `git merge-file` groups adjacent changed lines into a single conflict hunk, so it reported a conflict (exit 1) even though the changes were logically non-overlapping. The clean merge test failed.
- **Fix:** Changed fixture to use `lineA` (position 3) and `lineH` (position 10), separated by 6 unchanged lines. `git merge-file` treats these as separate hunks and merges cleanly (exit 0).
- **Files modified:** tests/run.sh
- **Commit:** 3d3f911

**2. [Rule 1 - Bug] Fixed MERGE-04 test: use older pinned version to bypass up-to-date guard**

- **Found during:** Task 2 initial test run (unbound variable `CONJURE_VERSION` crash, then logic failure)
- **Issue 1:** The plan used `$CONJURE_VERSION` in the test, but this variable is only defined inside `cli/conjure` (not exported). Using it in `tests/run.sh` caused an `unbound variable` error under `set -u`.
- **Issue 2 (after fixing issue 1):** When `pinned == CONJURE_VERSION`, `cmd_update` exits early ("Up to date") before running the merge. The settings.json was never replaced.
- **Fix:** Use pinned version `0.0.1` and create `.conjure-templates-0.0.1/` snapshot dir. Since `0.0.1 != 0.2.1`, the update proceeds to run the merge. Read version via `cat VERSION` into a local variable `MERGE_CONJURE_VERSION`, then simplified to use the literal `0.0.1`.
- **Files modified:** tests/run.sh
- **Commit:** 3d3f911

## Shellcheck Compliance

Shellcheck is not installed locally (darwin CI-only, as documented in prior summaries). Manual review confirmed for the new code in both files:

**scripts/audit-setup.sh additions:**
- No SC2155: `CONFLICT_FILES="$(cmd)"` is at script top-level (not in a function), unqualified — correct
- No SC2044: no new find loops; `grep -rl` used instead
- No SC2034: `CONFLICT_FILES` is used in the if-branch
- No SC2164: no cd calls

**tests/run.sh additions:**
- SC1090 disable comments added for the `source "$CONJURE_HOME/lib/..."` dynamic paths
- No SC2155: all `local var; var="$(cmd)"` two-line forms; `MERGE_DIR="$(mktemp -d)"` and `MERGE_OUT="$(cmd)"` are unqualified top-level assignments
- No SC2044: all find calls use `-name` glob, output checked via `-z`/`-f` not loops
- No SC2034: all declared variables are referenced (MERGE_RC, MERGE_OUT, SIDECAR, AUDIT_OUT, AUDIT_RC)
- No SC2164: no cd calls in new code

## Threat Model Check

- T-09-07 (grep output lists conflict file paths): accepted — paths are from the repo owner's own `.claude/` directory
- T-09-08 (grep -rl on large .claude/): accepted — `.claude/` is bounded by 25,000 token audit check
- T-09-09 (test block re-sources lib/merge.sh): mitigated — `CONJURE_MERGE_CONFLICT_COUNT=0` and `CONJURE_MERGE_CONFLICT_FILES=""` explicitly reset before each `merge_file_3way` call

## Known Stubs

None — all MERGE test blocks make real assertions with real lib/merge.sh calls and real CLI invocations.

## Threat Flags

None — no new network endpoints, auth paths, file access patterns, or schema changes introduced.

## Self-Check: PASSED

| Check | Result |
|-------|--------|
| `grep -n 'conjure-conflict' scripts/audit-setup.sh` shows lines 135,137 | PASS |
| `grep -c 'MERGE-0[1-5]' tests/run.sh` returns 33 | PASS |
| `bash tests/run.sh` → PASS: 216, FAIL: 0 | PASS |
| Conflict detection: audit exits 2 on .claude/ with markers | PASS |
| Sidecar exclusion: audit does NOT flag .conjure-conflict-* files | PASS |
| git log shows c170ecc (audit-setup.sh) and 3d3f911 (tests/run.sh) | PASS |
| No unexpected file deletions in either commit | PASS |
