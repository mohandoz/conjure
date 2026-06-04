---
phase: 30-workspace-orchestration-mutating-rollback-saga
verified: 2026-06-04T00:00:00Z
status: passed
score: 12/12
overrides_applied: 0
---

# Phase 30: Workspace Orchestration — Mutating + Rollback Saga Verification Report

**Phase Goal:** Developers can run mutating harness operations (update, adopt) across many repos in one command, with a saga-pattern rollback that survives SIGKILL and restores every repo to its pre-run state.
**Verified:** 2026-06-04
**Status:** PASSED
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths (from ROADMAP Success Criteria)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | `workspace update`: serial per-repo conjure update; per-repo merge/conflict status; stop-on-first-error default; --continue-on-error; conflict sidecars surfaced in aggregate [WS-05] | VERIFIED | `ws_do_update` in scripts/workspace.sh lines 278-416: CONTINUE_ON_ERROR flag, `return 2` at first failure, grep TMPERR for `*.conjure-conflict-*` sidecar paths, aggregate report with counts |
| 2 | `workspace adopt` with optional --tag filter: ALL repos snapshotted before ANY apply (saga invariant); .conjure-workspace-state.json written atomically before each op; disk estimate >2GB warns + exit 2 unless --allow-large-snapshots [WS-06] | VERIFIED | `ws_do_adopt` in scripts/workspace.sh: two-phase loop (PHASE A snapshot-all, PHASE B apply-all); `workspace_state_write` atomic jq>tmp.$$+mv before+after each op; du -sk sum vs 2097152 KiB gate at lines 484-510; --allow-large-snapshots bypasses |
| 3 | `workspace adopt --rollback`: per-repo independent restore from pre-run snapshot; state persists across SIGKILL [WS-07] | VERIFIED | `ws_do_rollback` in scripts/workspace.sh lines 753-1044: iterates repos from state; `snapshot_rollback` per repo; `continue` on per-repo failure (independence); atomic state writes |
| 4 | Saga proof (CI fixture): SIGKILL mid-batch on _workspace-trio → --rollback → per-repo sha256 zero-diff [WS-07] | VERIFIED | SIGKILL test block in tests/run.sh lines 6432-6540 passes: poll on `[.repos[] | select(.status == "applied")] | length > 0`, kill -9, rollback, sha256 zero-diff + diff -r zero-diff for all 3 repos. Suite: PASS 579 / FAIL 0 |
| 5 | --dry-run: all preflight + snapshot-size checks, zero files written; exit 2 only if a preflight itself fails [WS-06] | VERIFIED | DRY_RUN path at lines 513-527: du gate runs first, then `if [ "$dry_run" -eq 1 ]` returns 0 with [dry-run] output; no state file, no snapshots written. WS-06-DRY-RUN test passes. |

**Score:** 5/5 ROADMAP truths verified

### Plan-Level Must-Haves (consolidated)

| # | Must-Have | Status | Evidence |
|---|-----------|--------|----------|
| 1 | _workspace-trio fixture: 3 adoptable repos (alpha/beta/gamma) with .claude/ content and tags | VERIFIED | `find tests/fixtures/_workspace-trio -type f` returns 10 files; manifest has 3 repos with tags team-a/team-b; alpha has git/SKILL.md, beta has docs/SKILL.md, gamma has post-tool.mjs hook |
| 2 | Phase 30 graceful-red test block in tests/run.sh covering WS-05, WS-06, WS-07, SAGA | VERIFIED | Lines 6212-6540 in tests/run.sh; all 4 sections present and now green (579 PASS / 0 FAIL) |
| 3 | workspace_state_write creates .conjure-workspace-state.json atomically (jq>tmp.$$+mv) | VERIFIED | lib/workspace.sh lines 172-202: `local tmp="${state_path}.tmp.$$"`, create-vs-update branches, mv on success, rm -f on failure |
| 4 | workspace_state_read never exits non-zero | VERIFIED | lib/workspace.sh line 211: `jq -r "${jq_expr} // empty" "$state_path" 2>/dev/null || true` |
| 5 | workspace_state_validate exits 2 on missing/malformed state; accepts "snapshotting" as valid status | VERIFIED | lib/workspace.sh lines 231-265: checks -f, jq empty, .run_id, .phase, .repos array; documented to NOT reject "snapshotting" per inline comment |
| 6 | ws_do_update: serial per-repo loop, CR-02 traversal re-check, stop-on-first-error, --continue-on-error, non-TTY gate | VERIFIED | scripts/workspace.sh lines 278-416: manifest_root pwd -P (line 309), CR-02 re-check per repo (line 334), CONTINUE_ON_ERROR=0 default (line 398), non-TTY guard (line 449) |
| 7 | cmd_workspace dispatches update|adopt tokens | VERIFIED | cli/conjure line 580: `init|check|audit|update|adopt` in subcommand dispatch; line 582 and 586 usage strings updated |
| 8 | ws_do_adopt: two-phase saga with snapshotting sentinel, snapshot_create two-arg API, CONJURE_ADOPT_REUSE_SNAPSHOT=1, du gate, --tag filter, --dry-run zero-write | VERIFIED | scripts/workspace.sh: `snapshotting` pre-write sentinel (line 600); `snapshot_create "$repo_abs" "$backup_root"` (line 608); `CONJURE_SNAPSHOT_PATH` capture (line 610); `CONJURE_ADOPT_REUSE_SNAPSHOT=1` in PHASE B (line 709); du gate (lines 484-510); tag filter jq select (line 471); DRY_RUN branch (lines 513-527) |
| 9 | ws_sha_of in lib/workspace.sh: cross-platform sha256 | VERIFIED | lib/workspace.sh lines 221-229: sha256sum or shasum -a 256 with `tr -d '\r'` |
| 10 | ws_do_rollback: independent per-repo restore, sha256 zero-diff verify, idempotent skip, snapshotting+empty-ref skip, archive-is-copy, CR-02 re-check | VERIFIED | scripts/workspace.sh lines 753-1044: independence via `continue` not exit; sha256 loop lines 978-1006; idempotent check lines 792-799; snapshotting+empty skip lines 828-830; archive cp lines 1036-1037 (COPY, original stays) |
| 11 | No-state-file → exit 2 "nothing to roll back"; all-rolled-back → exit 0 no-op | VERIFIED | Line 778: `echo "✗ ws_do_rollback: no .conjure-workspace-state.json found — nothing to roll back"`; lines 792-798: `if [ "$all_rolled_back" = '"yes"' ] → return 0` |
| 12 | shellcheck passes on lib/workspace.sh, scripts/workspace.sh, cli/conjure | VERIFIED | `shellcheck -S error -e SC2164,SC2044,SC2034,SC2155 scripts/workspace.sh lib/workspace.sh cli/conjure` exits 0 with no output |

**Score:** 12/12 plan-level must-haves verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `tests/fixtures/_workspace-trio/.conjure-workspace.json` | 3-repo workspace manifest with tags | VERIFIED | Valid JSON; 3 repos; alpha/beta tagged team-a, gamma tagged team-b |
| `tests/fixtures/_workspace-trio/repos/alpha/.claude/skills/git/SKILL.md` | Adoptable harness content | VERIFIED | File exists (10 files total in fixture tree) |
| `tests/fixtures/_workspace-trio/repos/gamma/.claude/hooks/post-tool.mjs` | Adoptable hook | VERIFIED | File exists |
| `tests/run.sh` | Phase 30 graceful-red block appended | VERIFIED | Lines 6212-6540; all WS-05/06/07/SAGA sections present and passing |
| `lib/workspace.sh` | workspace_state_write, workspace_state_read, workspace_state_validate, ws_sha_of | VERIFIED | grep -c count = 14 for state helpers; ws_sha_of present |
| `scripts/workspace.sh` | ws_do_update, ws_do_adopt, ws_do_rollback + adopt/update dispatch | VERIFIED | ws_do_update: 3 refs; ws_do_adopt: 8 refs; ws_do_rollback: 11 refs |
| `cli/conjure` | cmd_workspace dispatches update and adopt | VERIFIED | Line 580: `init|check|audit|update|adopt` |

### Key Link Verification

| From | To | Via | Status | Details |
|------|-----|-----|--------|---------|
| cli/conjure cmd_workspace | scripts/workspace.sh update/adopt dispatch | bash workspace.sh update/adopt $@ | WIRED | cli/conjure line 580 token match; workspace.sh `update)` and `adopt)` case branches present |
| ws_do_adopt PHASE A | lib/snapshot.sh snapshot_create | snapshot_create "$repo_abs" "$backup_root" | WIRED | scripts/workspace.sh line 608; CONJURE_SNAPSHOT_PATH capture line 610 |
| ws_do_adopt PHASE B | cli/conjure adopt per-repo | CONJURE_ADOPT_REUSE_SNAPSHOT=1 bash $CONJURE_HOME/cli/conjure adopt $repo_abs | WIRED | scripts/workspace.sh line 709 |
| ws_do_adopt state writes | .conjure-workspace-state.json | workspace_state_write (atomic jq>tmp.$$+mv) | WIRED | workspace_state_write called before+after each op throughout ws_do_adopt |
| ws_do_rollback sha256 verify | sha256_pre_ref hash file | workspace_state_read .repos[].sha256_pre_ref → read hash file | WIRED | lines 978-1006; reads sha256_pre_ref path from state, compares ws_sha_of per file |
| ws_do_rollback archive | .conjure-workspace-state-<timestamp>.json | cp state_path archive_name | WIRED | line 1037: `cp "$state_path" "$archive_name"` |

### Data-Flow Trace (Level 4)

| Component | Data | Source | Produces Real Data | Status |
|-----------|------|--------|--------------------|--------|
| ws_do_adopt | repos_json (filtered) | jq from manifest file | Yes — reads real _workspace-trio fixture with 3 repos | FLOWING |
| ws_do_adopt state writes | .conjure-workspace-state.json | workspace_state_write atomic writes | Yes — confirmed by WS-06-SAGA-INVARIANT test passing | FLOWING |
| ws_do_rollback | repo entries from state | jq -c '.repos[]' from state_path | Yes — reads post-adopt state with snapshot_ref paths | FLOWING |
| SIGKILL test | per-repo sha256 pre-run hashes | p30_sha of each file in fixture repos | Yes — file-level hashes compared post-rollback; 0 mismatches | FLOWING |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| workspace update --help | `CONJURE_HOME=... bash cli/conjure workspace update --help` | "Usage: conjure workspace update [--continue-on-error] [--yes] <manifest_path>" | PASS |
| workspace --help shows update\|adopt | `CONJURE_HOME=... bash cli/conjure workspace --help` | "Usage: conjure workspace init\|check\|audit\|update\|adopt [args]" | PASS |
| shellcheck clean | `shellcheck -S error -e SC2164,SC2044,SC2034,SC2155 scripts/workspace.sh lib/workspace.sh cli/conjure` | exit 0, no output | PASS |
| Full test suite | `bash tests/run.sh` | PASS: 579 FAIL: 0 | PASS |

### Probe Execution

| Probe | Command | Result | Status |
|-------|---------|--------|--------|
| tests/run.sh (full suite including SIGKILL) | `bash tests/run.sh` | PASS: 579 FAIL: 0 | PASS |

### Requirements Coverage

| Requirement | Description | Status | Evidence |
|-------------|-------------|--------|---------|
| WS-05 | `conjure workspace update` per-repo serial update, conflict status, --continue-on-error | SATISFIED | ws_do_update in scripts/workspace.sh; WS-05 test block in run.sh passes |
| WS-06 | `conjure workspace adopt` across repos, saga invariant (all-snapshot-before-apply), state file, --tag filter, du gate | SATISFIED | ws_do_adopt two-phase saga; WS-06 tests (SAGA-INVARIANT, DRY-RUN, DU-GATE, DU-GATE-bypass) all pass |
| WS-07 | `conjure workspace adopt --rollback` per-repo independent restore; SIGKILL-mid-batch → rollback → sha256 zero-diff | SATISFIED | ws_do_rollback with independence, sha256 verify, archive-is-copy; SIGKILL saga CI test passes (4/4 assertions green) |

### Anti-Patterns Found

| File | Pattern | Severity | Impact |
|------|---------|----------|--------|
| None found | — | — | — |

Scanned: scripts/workspace.sh, lib/workspace.sh, cli/conjure, tests/run.sh. No TBD/FIXME/XXX markers in phase-modified files. No placeholder returns. No hardcoded-empty data flowing to rendering. All Phase 30 stubs were deliberate Wave N+1 markers that are now resolved (confirmed by 579 PASS / 0 FAIL).

### Human Verification Required

None. All success criteria are programmatically verifiable and verified by the test suite.

### Gaps Summary

No gaps. All 5 ROADMAP success criteria verified against the codebase. All 12 plan-level must-haves verified. The test suite runs PASS: 579 / FAIL: 0 including the SIGKILL saga proof (4 assertions, all green). Shellcheck passes on all modified files.

---

_Verified: 2026-06-04T00:00:00Z_
_Verifier: Claude (gsd-verifier)_
