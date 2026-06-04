---
phase: 30-workspace-orchestration-mutating-rollback-saga
fixed_at: 2026-06-04T00:00:00Z
review_path: .planning/phases/30-workspace-orchestration-mutating-rollback-saga/30-REVIEW.md
iteration: 1
findings_in_scope: 9
fixed: 9
skipped: 0
status: all_fixed
---

# Phase 30: Code Review Fix Report

**Fixed at:** 2026-06-04T00:00:00Z
**Source review:** .planning/phases/30-workspace-orchestration-mutating-rollback-saga/30-REVIEW.md
**Iteration:** 1

**Summary:**
- Findings in scope: 9 (4 BLOCKER + 5 WARNING; Info findings out of scope per `critical_warning`)
- Fixed: 9
- Skipped: 0

All fixes were applied surgically, each commit verified (re-read + `bash -n` syntax
check + targeted `shellcheck`), and the FULL suite re-run after each. Final state:
**579 PASS / 0 FAIL** (574 baseline + 5 new regression assertions), shellcheck
`-S error -e SC2164,SC2044,SC2034,SC2155` clean across all four touched files. The
SIGKILL WS-07 saga segment was run **3 consecutive times green** (runs A/B/C) to
prove the orphan-eviction pkill change did not regress its known flakiness.

Conventions verified to hold: exit 2 never exit 1 (documented check/audit/update
aggregate exceptions untouched); POSIX bash 3.2+ (no associative arrays / mapfile /
local -n introduced); single `_ws_cleanup` EXIT trap preserved (the dead
`WS_STATE_TMP` slot was removed, not duplicated); rollback independence preserved
(no mid-loop `exit`/`return`, only `continue` + aggregate `any_rb_failed`); saga
invariant (ALL snapshot before ANY apply) untouched.

## Fixed Issues

### CR-01: Orphan-eviction `pkill` pattern over-matches sibling repos

**Files modified:** `scripts/workspace.sh`
**Commit:** 57fe1f1
**Applied fix:** Regex-escaped every metacharacter in `$rb_abs`
(`sed 's/[].[*^$()+?{}|\\]/\\&/g'`) and anchored the `pkill -f` pattern to
end-of-line (`${rb_abs_re}\$`) for both the `conjure adopt` and `adopt.sh` forms.
A path ending `/repo-a` can no longer suffix-match a live `…/repo-abc` command line.
**Proof:** Regression `CR-01` launches a realistic sibling subprocess
(`bash …/cli/conjure adopt …/repo-abc`) and asserts the escaped+anchored `repo-a$`
pattern leaves it alive, while a positive control with the `repo-abc$` pattern kills
it (proving the harness can see the process via `pkill -f`, so survival is real
protection, not a blind spot).

### CR-02: sha256 verify mis-parses double-space paths
### WR-03: `ws_sha_of` empty-vs-empty false-clean

**Files modified:** `scripts/workspace.sh`
**Commit:** c6db943
**Applied fix:** Two coupled fixes in the same verify-parse loop (inseparable lines,
committed together). CR-02: replaced `${line##*  }` (longest trailing match, which
truncated embedded double spaces to the last path segment) with `${line#*  }` (strip
only the FIRST two-space run, preserving the rest verbatim). WR-03: replaced the
`ws_sha_of … || echo MISSING` fallback (which never fired — `ws_sha_of` returns `""`
with exit 0 for a missing file) with an explicit `[ ! -e ]` existence probe setting
`_now=MISSING`, independent of `ws_sha_of`'s exit status.
**Note:** Logic-touching parse change — see human-verification note below.

### CR-03: PHASE-A-failed repo breaks rollback idempotency

**Files modified:** `scripts/workspace.sh`
**Commit:** f85506d
**Applied fix:** Added a `failed` + empty `snapshot_ref` branch before the
snapshot_ref hard-failure guard, mirroring the `snapshotting`/`pending` never-mutated
branches: mark `rolled_back` and `continue`. A `failed` repo WITH a `snapshot_ref`
(failed during PHASE B apply, after it was snapshotted) still falls through and is
restored — the two cases are correctly distinguished.
**Proof:** Regression `CR-03` hand-builds a state file with `alpha` =
`failed`+empty and drives `--rollback`; asserts `alpha` → `rolled_back` and overall
exit 0 (previously spurious exit 2).

### CR-04: Pre-hash enumeration hashes the in-tree snapshot copy

**Files modified:** `scripts/workspace.sh`, `lib/snapshot.sh`
**Commit:** 2482811
**Applied fix:** Excluded the conjure-owned dirs (`.conjure-adopt-backups`,
`.conjure-archive-*`, `.conjure-adopt-state`) from the PHASE-A pre-hash `find`, so the
hash set and the rollback deletion-pass scope agree exactly. Also added
`--exclude='./.conjure-adopt-backups'` to `snapshot_create`'s tar to stop the
self-referential nesting where the snapshot archived a partial copy of the backups dir.
**Proof:** Regression `CR-04` adopts the trio and asserts every recorded
`sha256_pre_ref` hash file contains zero `.conjure-adopt-backups` paths.

### WR-01: `--rollback` has no consent gate

**Files modified:** `scripts/workspace.sh`
**Commit:** e3d2db3
**Applied fix:** Added the standard mutating-op gate at the top of `ws_do_rollback`:
non-TTY without `--yes` returns 2 (mirrors `ws_do_adopt`). Existing rollback tests
already pass `--yes`, so none broke.
**Proof:** Regression `WR-01` runs `--rollback` non-TTY (`</dev/null`) without
`--yes` and asserts exit 2.

### WR-02: `workspace_state_write` tmp orphans never cleaned

**Files modified:** `scripts/workspace.sh`, `lib/workspace.sh`
**Commit:** 27a7c1e
**Applied fix:** Added a best-effort glob sweep of `"${state_path}".tmp.*` on entry to
`workspace_state_write` (a glob is more complete than a single-slot var under
concurrent runs, each with a distinct `$$`), and removed the dead `WS_STATE_TMP`
trap wiring from the script (it was never assigned, so the trap slot cleaned nothing).
The single `_ws_cleanup` EXIT trap is preserved.

### WR-04: PHASE B partial-apply leaves repos mutated with no signal

**Files modified:** `scripts/workspace.sh`
**Commit:** bcf7e9f
**Applied fix:** Emit an explicit, machine-greppable
`✗ PARTIAL ADOPT: … Run: conjure workspace adopt --rollback <manifest>` line before
returning 2 on PHASE B failure, so a non-interactive caller learns the workspace is
partially mutated and how to restore it. (Auto-rollback was deliberately NOT added —
the saga is recoverable-by-design and auto-rollback would change documented behavior.)

### WR-05: ws_do_update read-only / unused `yes` / shared TMPERR

**Files modified:** `scripts/workspace.sh`
**Commit:** 769fddb
**Applied fix:** Documented `ws_do_update` as read-only (it calls `conjure update`
with no `--apply` — drift-check only, never mutates), marked the `yes` param as
intentionally unused (`# shellcheck disable=SC2034`, accepted for 4-arg signature
parity), and commented that the shared `TMPERR` is read immediately after each
invocation (iteration-local) so a future refactor does not move the scan and read a
stale repo's output. No behavioral change.

## Human-Verification Notes

The following fix touches parsing/comparison logic (not just syntax). Syntax and
shellcheck verification pass and a targeted regression was added, but a human should
confirm the semantics before the phase advances to the verifier:

- **CR-02/WR-03** (commit c6db943): the `${line#*  }` first-run split and the explicit
  `MISSING` sentinel change how the safety-critical sha256 zero-diff verify
  reconstructs paths and flags deletions. The new regression (`CR-02`) exercises the
  double-space path through the exact parse, and the existing SIGKILL zero-diff suite
  (4 assertions, green 3× consecutively) exercises the end-to-end verify, but confirm
  the split behaves as intended for any path shape your fixtures do not cover.

## Out-of-Scope (not addressed — `fix_scope: critical_warning`)

The four Info findings (IN-01 dead `workspace_state_read`, IN-02 resolve-helper
duplication, IN-03 PHASE-A pending-count summary, IN-04 magic-number constant) were
not in scope and were left untouched.

---

_Fixed: 2026-06-04T00:00:00Z_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
