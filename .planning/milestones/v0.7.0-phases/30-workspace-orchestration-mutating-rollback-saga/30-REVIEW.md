---
phase: 30-workspace-orchestration-mutating-rollback-saga
reviewed: 2026-06-04T02:20:00Z
depth: standard
files_reviewed: 4
files_reviewed_list:
  - lib/workspace.sh
  - scripts/workspace.sh
  - lib/snapshot.sh
  - cli/conjure
findings:
  critical: 0
  warning: 0
  info: 1
  total: 1
status: clean
---

# Phase 30: Code Review Report (Re-review — Iteration 2)

**Reviewed:** 2026-06-04T02:20:00Z
**Depth:** standard (adversarial fix-verification)
**Files Reviewed:** 4
**Status:** clean

## Summary

Iteration-2 re-review of the workspace orchestration / mutating rollback saga after
the fixer resolved 4 BLOCKERs + 5 WARNINGs across commits `57fe1f1..fed27e3`
(9 commits). Each fix was verified **empirically** against fixtures in
`tests/fixtures/_workspace-trio` and with purpose-built attack scripts, not by
reading the diff alone.

**Verdict:** All 9 fixes hold under adversarial probing. No NEW Critical or Warning
defects were introduced by the fix commits. One Info-level observation is recorded
(WR-02 cross-writer tmp sweep) — a documented pre-existing single-writer design
boundary, not a regression.

### Gate results (all green)

- `bash tests/run.sh` → **579 PASS / 0 FAIL**.
- SIGKILL segment (13 assertions incl. orphan-evict + zero-diff) → green **3× consecutively** (no flake).
- `shellcheck -S error -e SC2164,SC2044,SC2034,SC2155` on all four files → **exit 0**.
- Other `snapshot_create` callers (adopt.sh Phase 22/24, emit-policy, emit-plugin) snapshot+rollback tests → green (no regression from the lib/snapshot.sh tar `--exclude` change).

### Per-fix empirical verification

**CR-01 (pkill anchoring)** — pattern built in `scripts/workspace.sh:909-911`.
Confirmed: the path is regex-escaped via `sed 's/[].[*^$()+?{}|\\]/\\&/g'` (covers
every ERE metachar: `. [ ] ( ) { } * + ? | ^ $ \`) and end-anchored with `$`.
`repo-a` pattern does **not** over-match a `repo-abc` command line; a full-metachar
path (`/a.b[c]d(e)f{g}h*i+j?k|l^m$n\o`) escapes cleanly, self-matches, and does not
over-match a regex-expansion sibling. The original SIGKILL orphan-evict flake fix
does not regress (SIGKILL test green 3×).

**CR-02 (sha256 verify parse — SAFETY-CRITICAL)** — `scripts/workspace.sh:994-995`.
The first-split `_h="${line%%  *}"` / `_frel="${line#*  }"` parse round-trips
**byte-exact** for: embedded double-spaces, leading space, trailing space, tab,
unicode. End-to-end test: building the hash file exactly as `ws_do_adopt` does
(line 638), then tampering a file whose path contains `"  "` (double space), the
verify loop produces **exactly 1 mismatch** (no false-pass) while clean files
round-trip (no false-fail). The MISSING sentinel (WR-03) is now an explicit
`[ ! -e ... ]` existence probe (line 1000), independent of `ws_sha_of` exit status —
an empty pre-hash can no longer false-match an absent file.

**CR-03 (failed+empty snapshot_ref skip)** — `scripts/workspace.sh:854-860`. Both
branches verified live: (a) `failed` + empty `snapshot_ref` → marked `rolled_back`,
exit 0 (never-mutated skip); (b) `failed` WITH `snapshot_ref` → restored
(file content reverted, adopt-created file deleted), exit 0. Idempotent re-run after
completion → "all repos already rolled_back — no-op", exit 0 (no spurious exit 2).

**CR-04 (pre-hash scope alignment)** — `scripts/workspace.sh:632-639` (hash walk)
and `:948-959` (deletion pass). Confirmed the hash manifest contains **no**
`.conjure-adopt-backups` paths, and the deletion-pass case-statement exclusion
(`.conjure-adopt-backups/*|.conjure-archive-*/*|.conjure-adopt-state/*`) matches the
hash-walk exclusion exactly — the two passes agree on scope. The `lib/snapshot.sh`
tar `--exclude='./.conjure-adopt-backups'` (line 47) is defense-in-depth for the
workspace direct-call path; adopt.sh's `snapshot_guarded` already stashes prior
backups aside (adopt.sh:210) before snapshotting into a temp root, so the exclude
does not alter adopt.sh/emit behavior — their snapshot+rollback tests stay green.

**WR-01 (rollback non-TTY consent gate)** — `scripts/workspace.sh:770-773`. Non-TTY
`--rollback` without `--yes` → "Not a TTY" + exit 2 (verified with `</dev/null`).
With `--yes` the destructive path runs. TTY/`--yes` semantics mirror `ws_do_adopt`.

**WR-02 (state tmp orphan sweep)** — `lib/workspace.sh:181-185`. Glob sweep on entry
reclaims `${state_path}.tmp.*` orphans; the dead `WS_STATE_TMP` slot was correctly
removed (`scripts/workspace.sh:34-37`). See Info IN-01 for the single-writer note.

## Narrative Findings (AI reviewer)

## Info

### IN-01: state-tmp glob sweep assumes single-writer-per-workspace

**File:** `lib/workspace.sh:181-185`
**Issue:** `workspace_state_write` sweeps `"${state_path}".tmp.*` on entry, which
matches tmp files belonging to ANY process (`.tmp.<other_pid>`), not just the current
run's `.tmp.$$`. If two saga runs operated on the **same** `state_path` concurrently,
writer A's entry-time sweep could `rm` writer B's in-flight tmp in the narrow window
between B's `jq > tmp` and B's `mv`, and B's `mv` exit is unchecked (so B would
silently fail to persist while returning 0). This is **not** a new defect from the
9 fix commits: the saga contract is single-writer-per-workspace (one `run_id`, one
state file per adopt run), the comment at lines 176-179 documents the concurrent-`$$`
reasoning, and the prior `WS_STATE_TMP` slot cleaned nothing — so correctness for the
supported scenario is unchanged or improved. Recording for traceability only.
**Fix (optional hardening, not required to ship):** if cross-writer safety is ever
needed, narrow the sweep to age-gated orphans (e.g. skip tmps modified within the
last few seconds), or check `mv`'s exit and re-attempt; alternatively assert
single-writer via an advisory lock file at saga entry.

---

_Reviewed: 2026-06-04T02:20:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard (adversarial fix-verification)_
