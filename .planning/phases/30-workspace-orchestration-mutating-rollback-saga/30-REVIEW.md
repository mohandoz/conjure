---
phase: 30-workspace-orchestration-mutating-rollback-saga
reviewed: 2026-06-04T00:00:00Z
depth: standard
files_reviewed: 3
files_reviewed_list:
  - lib/workspace.sh
  - scripts/workspace.sh
  - cli/conjure
findings:
  critical: 4
  warning: 5
  info: 4
  total: 13
status: issues_found
---

# Phase 30: Code Review Report

**Reviewed:** 2026-06-04T00:00:00Z
**Depth:** standard
**Files Reviewed:** 3
**Status:** issues_found

## Summary

Phase 30 implements the workspace mutating + rollback saga — the highest-risk
feature of v0.7.0. The saga skeleton is sound: PHASE A snapshots all repos before
PHASE B applies any (invariant holds), all state writes route through
`workspace_state_write` (no raw redirections found), state writes are atomic
(`jq > tmp.$$` + `mv`), dry-run takes zero writes, and the per-repo traversal
re-checks are present at validate/snapshot/apply/restore time. The du gate math is
correct (`2097152 KiB = 2 GiB`).

However, adversarial tracing surfaced **four BLOCKER defects** in the rollback /
verification path that defeat the saga's core promise of byte-faithful, complete,
idempotent rollback:

1. The orphan-eviction `pkill` pattern interpolates the repo path as an **unanchored
   regex**, which over-matches sibling repos (`repo-a` kills `repo-abc`) and can kill
   unrelated processes — including the test harness or a *concurrently adopting
   sibling repo's* subprocess.
2. The sha256 zero-diff verify **mis-parses any path containing two consecutive
   spaces**, fabricating mismatches and failing otherwise-clean rollbacks.
3. A repo that **failed in PHASE A** (status=`failed` + empty `snapshot_ref`) is
   mis-classified by rollback as a real restore failure → spurious `exit 2`, breaking
   rollback idempotency for the most common partial-failure case.
4. The per-file **pre-hash enumeration runs after `snapshot_create`** and does not
   exclude the in-tree backup dir, so it hashes the snapshot's own copy of the repo —
   inflating the verify set and coupling rollback verification to the snapshot's
   internal layout.

Plus a destructive-op **consent-gate gap**: `--rollback` deletes adopt-created files
and overwrites the working tree with no `--yes`/TTY check.

## Critical Issues

### CR-01: Orphan-eviction `pkill` pattern over-matches sibling repos and unrelated processes

**File:** `scripts/workspace.sh:843-844`
**Issue:** The pre-restore orphan kill interpolates the absolute repo path directly
into a `pkill -f` regex:
```bash
pkill -9 -f "conjure adopt.*$rb_abs" 2>/dev/null || true
pkill -9 -f "adopt\\.sh.*$rb_abs" 2>/dev/null || true
```
`$rb_abs` is treated as a **regex, not a literal**, and the match is **unanchored**.
Two concrete failures, both empirically reproduced:
- **Suffix over-match:** repo `.../repo-a`'s pattern `conjure adopt.*/…/repo-a` matches
  a live command line `bash conjure adopt /…/repo-abc`. Rolling back `repo-a` will
  `kill -9` the in-flight adopt subprocess of `repo-abc` (a sibling that is *not* being
  rolled back), corrupting that repo mid-mutation.
- **Metachar/broad match:** every path contains `.` (matches any char) and may contain
  `+`, `(`, etc. A path that is a prefix of another, or a short path, can match a wide
  range of command lines — potentially the test harness or an unrelated `conjure adopt`
  on a different workspace. The pattern can kill innocent processes.

The 50ms sleep + double-pass does nothing to bound *which* processes are killed — it
only bounds the file-deletion TOCTOU window.
**Fix:** Anchor and literal-escape. Prefer killing by recorded PID (capture `$!` of the
PHASE B subprocess into state) rather than by command-line pattern. If pattern-matching
must stay, anchor to end-of-string and escape regex metacharacters:
```bash
# Escape regex metachars in the path, then anchor to end-of-line.
rb_abs_re="$(printf '%s' "$rb_abs" | sed 's/[.[\*^$()+?{|]/\\&/g')"
pkill -9 -f "conjure adopt.*${rb_abs_re}\$" 2>/dev/null || true
pkill -9 -f "adopt\.sh.*${rb_abs_re}\$" 2>/dev/null || true
```
Better: record the apply PID in state during PHASE B and `kill -9 "$pid"` at rollback.

### CR-02: sha256 zero-diff verify mis-parses paths containing double spaces → fabricated rollback failure

**File:** `scripts/workspace.sh:920-922` (parse) and `:612-614` (hash-file format)
**Issue:** The pre-hash file is written as `printf '%s  %s\n' "<hash>" "<relpath>"`
(two-space separator). The verify loop reconstructs the relative path with:
```bash
_h="${line%%  *}"; _frel="${line##*  }"
```
`${line##*  }` strips the **longest** leading `*<two-spaces>` match, so any filename that
itself contains two consecutive spaces is truncated to only its final segment.
Empirically: a line `abc123  ./file  with  spaces.txt` yields `_frel="spaces.txt"`
instead of `./file  with  spaces.txt`. The verify then hashes a non-existent path,
`_now` comes back empty/`MISSING`, the hashes differ, and `rb_mismatch` increments —
the repo is marked `failed` and rollback returns `exit 2` even though the tree was
restored byte-perfectly. Filenames with double spaces are unusual but legal, and this
is a safety-critical verification step that must not produce false negatives.
**Fix:** Use a delimiter that cannot occur in a path (NUL or tab), or split on the
*first* separator only. Minimal fix — split on first two-space run from the left:
```bash
_h="${line%%  *}"
_frel="${line#*  }"   # strip only the FIRST '  ' run, keep the rest verbatim
```
(`#*  ` removes the shortest leading `*<two-spaces>`, preserving embedded double spaces.)

### CR-03: PHASE-A-failed repo (empty snapshot_ref) is mis-classified as a rollback failure → breaks idempotency

**File:** `scripts/workspace.sh:788-833`
**Issue:** When PHASE A fails for a repo (bad path, out-of-bounds, or `snapshot_create`
returns non-zero), `ws_do_adopt` sets `status="failed"` while `snapshot_ref` stays
empty (lines 552-606). That repo was **never mutated** (snapshot failed, adopt never
ran). But in `ws_do_rollback`, a `failed` status with empty `snapshot_ref` matches none
of the safe-skip branches:
- not `rolled_back` (line 780)
- not `snapshotting` + empty (line 788 — status is `failed`, not `snapshotting`)
- not `pending` (line 797)

so it falls through to the snapshot_ref guard at line 823, hits `[ -z "$rb_snap_ref" ]`,
sets `any_rb_failed=1`, and the whole rollback returns `exit 2`. This is a spurious
failure for a never-mutated repo, and it **breaks the documented idempotency contract**:
a re-run will keep reporting `exit 2` because the repo is never advanced to
`rolled_back`. The most common partial-failure case (one repo's snapshot failed,
aborting the saga) cannot be cleanly rolled back.
**Fix:** Treat `failed` + empty `snapshot_ref` as never-mutated, identical to the
`snapshotting`/`pending` branches — mark `rolled_back` and continue:
```bash
if [ -z "$rb_snap_ref" ]; then
  printf '  rollback: %s status=%s + no snapshot_ref — never mutated, skip\n' "$rb_name" "$rb_status"
  workspace_state_write "$state_path" \
    '.repos = [.repos[] | if .name == $n then .status = "rolled_back" else . end]' \
    --arg n "$rb_name" || true
  continue
fi
```
Place this before the `[ ! -d "$rb_snap_ref" ]` hard-failure check.

### CR-04: Pre-hash enumeration runs after snapshot and hashes the in-tree snapshot copy

**File:** `scripts/workspace.sh:594-614`
**Issue:** `backup_root="$repo_abs/.conjure-adopt-backups"` places the snapshot **inside
the repo tree**, and `snapshot_create` `mkdir -p`s it and copies the repo into
`.conjure-adopt-backups/conjure-adopt-<ts>/` *before* control returns. The per-file
pre-hash then enumerates with only `.git` excluded:
```bash
( cd "$repo_abs" && find . -type f -not -path './.git/*' | sort | while ...
```
This includes every file under `.conjure-adopt-backups/conjure-adopt-<ts>/` — i.e. the
snapshot's own copy of the repo. Consequences:
- The verify set is roughly doubled and now contains the snapshot's internal layout, so
  rollback's zero-diff verification is coupled to snapshot internals rather than the
  user's tree.
- `snapshot_create` itself (`cd target && tar -cf … .`) archives `.conjure-adopt-backups`
  (only `.git`/`node_modules` are excluded), so the snapshot contains a partial copy of
  the backups dir — a self-referential nesting that grows on repeated runs and that
  rollback then re-extracts.

Rollback's *deletion* passes correctly exclude `.conjure-adopt-backups/*` (lines 889,
906), but the *hash* set does not, so the two passes disagree about which files are
in scope. This is fragile and can mask or fabricate diffs.
**Fix:** Exclude the conjure-internal dirs from the pre-hash enumeration so it matches
the rollback deletion scope, and ideally compute the hash *before* `snapshot_create`:
```bash
( cd "$repo_abs" && find . -type f \
    -not -path './.git/*' \
    -not -path './.conjure-adopt-backups/*' \
    -not -path './.conjure-archive-*/*' \
    -not -path './.conjure-adopt-state/*' \
    | sort | while IFS= read -r f; do
      printf '%s  %s\n' "$(ws_sha_of "$f")" "$f"
    done ) > "$hash_file" 2>/dev/null || true
```
Also add `--exclude='./.conjure-adopt-backups'` to `snapshot_create`'s tar (lib/snapshot.sh:47).

## Warnings

### WR-01: `--rollback` is destructive but has no consent gate (`yes` param accepted and ignored)

**File:** `scripts/workspace.sh:730-733` (and dispatch `:1143`)
**Issue:** `ws_do_rollback` takes `yes` as `$3` but never references it. Rollback
deletes adopt-created files (lines 885-887), prunes directories (line 904), and
overwrites the working tree via `snapshot_rollback` — all destructive — yet there is no
`--yes`/TTY consent check, unlike `ws_do_adopt` (lines 435-440) and `workspace init`
(lines 987-992). Project convention (CLAUDE.md) requires `/dev/tty` + non-TTY `--yes`
consent for mutating ops. A non-interactive `conjure workspace adopt --rollback` mutates
many repos with zero confirmation.
**Fix:** Mirror the adopt consent gate at the top of `ws_do_rollback`:
```bash
if [ "$yes" -eq 0 ] && ! [ -t 0 ]; then
  echo "✗ Not a TTY. Use --yes for non-interactive rollback." >&2
  return 2
fi
```

### WR-02: `workspace_state_write` tmp orphans are never cleaned (dead cleanup wiring)

**File:** `lib/workspace.sh:172`, `scripts/workspace.sh:34-38`
**Issue:** `workspace_state_write` writes to a **local** `tmp="${state_path}.tmp.$$"`.
The script-level `_ws_cleanup` trap removes `WS_STATE_TMP`, but `workspace_state_write`
never assigns its tmp path to `WS_STATE_TMP` — so `WS_STATE_TMP` is always empty and the
trap cleans nothing here. On SIGKILL between `jq > tmp` and `mv` (the documented
durability window), the orphan `.conjure-workspace-state.json.tmp.<pid>` is left in the
workspace root indefinitely. State is never corrupted (mv is atomic), but orphans
accumulate and the advertised cleanup is dead code.
**Fix:** Assign before writing so the trap can reclaim it:
```bash
WS_STATE_TMP="${state_path}.tmp.$$"
local tmp="$WS_STATE_TMP"
```
(or have rollback/adopt sweep `"$manifest_dir"/.conjure-workspace-state.json.tmp.*` on
entry). Note: with concurrent runs `$$` differs per process, so a global single-slot
`WS_STATE_TMP` only tracks the last write — a glob sweep is the more complete fix.

### WR-03: `ws_sha_of` returns empty (not `MISSING`) for absent files → false hash match

**File:** `lib/workspace.sh:208-214`, used at `scripts/workspace.sh:921`
**Issue:** The verify line relies on `ws_sha_of … || echo MISSING` to flag a deleted
file. But `ws_sha_of` pipes `sha256sum 2>/dev/null | cut … | tr …`; on a missing file
`sha256sum` fails silently and the pipe still exits 0 (final stage `tr` succeeds with
empty input), so `ws_sha_of` returns `""` with exit 0. The `|| echo MISSING` never
fires; `_now=""`. If a pre-hash line ever has an empty hash field (`_h=""`, e.g. a file
that was unreadable at hash time), it then matches `_now=""` and the diff is silently
treated as clean. A truly-deleted file produces `_h=<real hash>` vs `_now=""`, which
correctly mismatches — so the common case is caught — but the empty-vs-empty path is a
latent false-clean.
**Fix:** Make the missing-file sentinel explicit inside the verify, independent of
`ws_sha_of`'s exit status:
```bash
if [ ! -e "$rb_abs/$_frel" ]; then _now="MISSING"; else _now="$(ws_sha_of "$rb_abs/$_frel")"; fi
[ "$_h" = "$_now" ] || rb_mismatch=$((rb_mismatch+1))
```

### WR-04: PHASE B partial-apply failure leaves earlier repos mutated with no auto-rollback

**File:** `scripts/workspace.sh:692-699`
**Issue:** PHASE B applies repos serially. If repo N fails, the function returns 2
(stop-on-fail) leaving repos 1..N-1 with `status="applied"` — i.e. **actually mutated**.
The saga does not auto-roll-back the already-applied repos; the operator must notice the
failure and manually run `--rollback`. This is arguably by design (state records
`applied`, and `--rollback` will restore them), but the summary/exit gives no explicit
instruction that the workspace is now in a *partially-mutated* state requiring rollback,
and a non-interactive caller that ignores the exit code is left with a half-adopted
workspace. The SC promise of "all-or-nothing" is not enforced — only recoverable.
**Fix:** On PHASE B failure, either invoke the rollback path automatically, or emit an
explicit, machine-greppable instruction before returning:
```bash
echo "✗ PARTIAL ADOPT: repos before $repo_name are applied. Run: conjure workspace adopt --rollback $manifest_path" >&2
```

### WR-05: Sidecar scan reads stale TMPERR / single-file reuse across repos

**File:** `scripts/workspace.sh:351,377-383`
**Issue:** `TMPERR` is a single mktemp file reused for every repo (`>"$TMPERR"`
truncates each iteration). The conflict-sidecar scan (line 378) reads `"$TMPERR"` only
when `repo_rc -eq 1`, which is correct for the current iteration. But because TMPERR is
shared and only truncated by the next `update` invocation, any code path that reads it
out of order (or a future refactor that scans after the loop) would see the last repo's
output. Lower risk today, but the shared-mutable-tempfile pattern is brittle for a
per-repo aggregate. Also note `update` here calls `conjure update` with **no `--apply`**
(line 351), so it is read-only `--check` — the `yes` param (`$4`) is entirely unused
dead weight and the "mutating op" framing in the header comment is misleading.
**Fix:** Either document that `ws_do_update` is read-only and drop the unused `yes`
param, or, if it is meant to apply, pass `--apply` and add a consent gate. For the
tempfile, prefer a per-repo `mktemp` or scan immediately after each invocation (current
behavior is acceptable but should be commented as iteration-local).

## Info

### IN-01: `workspace_state_read` is defined but never called

**File:** `lib/workspace.sh:196-200`
**Issue:** `workspace_state_read` is a documented helper but no caller in
`scripts/workspace.sh` uses it (all reads use inline `jq -r`). Dead export.
**Fix:** Remove it, or route the inline state reads (e.g. lines 649-650, 772-774)
through it for consistency.

### IN-02: `repo_real`/`manifest_root` resolution duplicated across five functions

**File:** `scripts/workspace.sh:70-106, 166-207, 300-346, 562-581, 805-820`
**Issue:** The identical "resolve manifest_root via `cd && pwd -P`, then per-repo
`cd && pwd -P` + `case` boundary re-check + skip" block is copy-pasted in
`ws_do_check`, `ws_do_audit`, `ws_do_update`, `ws_do_adopt` (PHASE A and B), and
`ws_do_rollback`. Five+ near-identical copies make a future boundary-logic fix
error-prone (a fix in one is easily missed in another).
**Fix:** Extract a `ws_resolve_under_root <repo_abs> <manifest_root>` helper in
lib/workspace.sh that prints the resolved path or returns non-zero, and call it from all
five sites.

### IN-03: PHASE A `phase_a_failed` `break` leaves trailing repos `pending` but never reports them

**File:** `scripts/workspace.sh:553-631`
**Issue:** When PHASE A fails for repo K, it `break`s, leaving repos K+1..N at
`status="pending"`. These are correctly skipped by rollback, but the adopt summary
(lines 712-716) only counts `applied`/`snapshotted` and never surfaces the `pending`
remainder, so the operator gets no signal that the run stopped early mid-list beyond the
single error line. Minor observability gap.
**Fix:** Add a `pending`/`failed` count to the adopt summary.

### IN-04: Magic number `2097152` lacks a named constant

**File:** `scripts/workspace.sh:489`
**Issue:** The du gate uses the bare literal `2097152`. It is correct (2 GiB in KiB) and
commented, but a named `readonly WS_SNAPSHOT_MAX_KIB=2097152` would make the threshold
self-documenting and adjustable in one place.
**Fix:** Hoist to a named constant at the top of the script.

---

_Reviewed: 2026-06-04T00:00:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
