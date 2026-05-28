---
phase: 22-conjure-adopt-cli-core-rollback
reviewed: 2026-05-29T00:00:00Z
depth: standard
files_reviewed: 5
files_reviewed_list:
  - scripts/adopt.sh
  - cli/conjure
  - lib/inventory.sh
  - tests/run.sh
  - tests/fixtures/_adopt-restructure-steps/adopt-manifest.json
findings:
  critical: 2
  warning: 5
  info: 4
  total: 11
status: issues_found
---

# Phase 22: Code Review Report

**Reviewed:** 2026-05-29T00:00:00Z
**Depth:** standard
**Files Reviewed:** 5
**Status:** issues_found

## Summary

Reviewed the `conjure adopt` pipeline (`scripts/adopt.sh`), its CLI wrapper
(`cmd_adopt` in `cli/conjure`), the inventory scanner (`lib/inventory.sh`), the
Phase 22 test block in `tests/run.sh`, and the restructure-steps fixture. The
orchestration of snapshot/inventory/scaffold/audit, the atomic state writes, the
path-traversal guard (`resolve_under`), and injection-safe jq construction are
generally sound and `shellcheck -S error` clean (verified with the CI flag set).

However, the `--apply-step` op-executor — the seam the Phase 23 skill drives — has
two correctness defects that ship untested by the Phase 22 suite:

1. **The `write` op corrupts staged content**: it pipes the staging file through
   `"$(cat ...)"`, which strips the trailing newline. Every applied file loses its
   final newline, so the destination never byte-matches the proposed content, and
   the `mutated[].after` sha recorded in state is the hash of the corrupted file.
2. **The `extract` op archives the wrong file**: it archives the *new* staging
   source (and deletes it) instead of the *old* destination, so the original
   content `extract` is meant to preserve is overwritten and lost. This op has no
   test coverage in `tests/run.sh`.

Secondary issues: `--apply-step` mutates the destination *before* recording state
(breaking the project's crash-durability invariant for that path), `--resume`
re-runs the dirty-tree gate without re-propagating `--force` (deadlocks recovery
after a forced run), rollback's whole-tree restore silently truncates the durable
audit log, and `--apply-step` accepts a `dest` anywhere under the target (it can
clobber `.git/` or the snapshot backups). Details below.

## Critical Issues

### CR-01: `--apply-step` write op strips the trailing newline from staged content

**File:** `scripts/adopt.sh:500`
**Issue:** `apply_write_op` writes the staged source into the destination with:
```bash
mutate_write "$dest_abs" "$(cat "$abs_src")"
```
Command substitution `$(...)` strips *all* trailing newlines. Virtually every
text file (including the test fixture `staging/CLAUDE.md`, which ends `...content.\n`)
ends in a newline, so the destination is written without it. The result:

- The applied file does not byte-match the content the Phase 23 skill staged. This
  is a silent data-integrity defect on the primary skill seam (D-05/D-07).
- The `mutated[].after` hash recorded at line 503 is `sha_of "$dest_abs"` — the
  hash of the *corrupted* file — so any downstream verification that compares the
  destination against the staging source (the natural integrity check for an
  apply step) will fail.
- It violates the POSIX "text file ends with newline" convention for every file
  conjure writes via this path.

Reproduced: a 12-byte `line1\nline2\n` staging file round-trips to an 11-byte
`line1\nline2` destination (sha differs).

The existing test (`tests/run.sh:2769`) only checks that the sha *changed*, not
that it matches the staged content, so it passes despite the corruption.

**Fix:** Read the file directly into `mutate_write` without the lossy command
substitution. Either teach `mutate_write` a "copy file" mode, or write the bytes
verbatim. Minimal in-place fix using a here-mode-free copy:
```bash
# Preserve exact bytes (incl. trailing newline) instead of $(cat).
if [ "${DRY_RUN:-0}" = "1" ]; then
  echo "[dry-run] would write $dest_abs (from $abs_src)"
  CONJURE_DRY_MUTATION_COUNT=$((CONJURE_DRY_MUTATION_COUNT + 1))
else
  cp "$abs_src" "$dest_abs"
fi
```
(or add a `mutate_write_file <dest> <src>` chokepoint so the mutation still routes
through `lib/mutate.sh`). Then record `state_add_mutated`/`state_add_created` as
before.

### CR-02: `extract` op archives the new staging source, not the old destination — original content is lost

**File:** `scripts/adopt.sh:536` (with `apply_archive_op`, lines 511-531)
**Issue:** The `extract` op is documented as "write-new + archive-old composed"
(line 536), i.e. write the condensed content to `dest` while preserving the
original `dest` content in the archive. But the composition is:
```bash
extract) apply_write_op; apply_archive_op ;;
```
Both halves operate on the *same* `src` (the staging file), because
`apply_archive_op` archives `$src`, not `$dest`:
- `apply_write_op` overwrites `dest` with the staging content (original `dest`
  content is now gone).
- `apply_archive_op` then `mutate_archive`s the *staging* file — and
  `mutate_archive` deletes its source after copying (`rm -f "${src}"`,
  `lib/mutate.sh:130`). So the archive contains the new staged content and the
  staging file is destroyed.

Net effect: the original destination content `extract` exists to preserve is
silently overwritten and never archived; the archive instead holds a copy of the
new content. This is the opposite of the intended safety behavior and is a
data-loss bug. The `extract` op has **no test** in the Phase 22 block (only
`write` and `archive` are exercised), so it ships broken.

**Fix:** Archive the *old destination* before the write overwrites it, and never
archive the staging source:
```bash
extract)
  # Preserve the existing dest content first, then write the new content.
  if [ -n "$dest" ] && [ -f "$target_abs/$dest" ]; then
    src="$dest" apply_archive_op   # archive the OLD dest
  fi
  apply_write_op                   # then write staging -> dest
  ;;
```
Refactor `apply_archive_op` so the source it archives is passed explicitly rather
than reading the outer `$src`, to avoid the two halves sharing one variable.

## Warnings

### WR-01: `--apply-step` mutates the destination before recording state (crash-durability gap)

**File:** `scripts/adopt.sh:498-507`
**Issue:** The phase invariant (and the forward pipeline's design, per the
"write state BEFORE each mutating step" comments) is that durable state is written
*before* a mutation so a `kill -9` mid-op is recoverable. In `apply_write_op` the
order is inverted: `mutate_write "$dest_abs" ...` (the mutation, line 500) runs
*before* `state_add_mutated`/`state_add_created` (lines 501-507). If the process is
killed between the write and the state record, the destination is mutated but
`created[]`/`mutated[]` has no entry, so `--rollback` will neither delete the new
file nor verify/restore the overwritten one — the mutation is invisible to
recovery. `apply_archive_op` has the same shape (archive then `ARCHIVED_COUNT++`,
though archive at least leaves a ledger).

**Fix:** Record the intent in state *before* mutating. For an overwrite, capture
`before_sha` and append a `mutated[]` entry (with a placeholder/`pending` after-hash)
before `mutate_write`, then update the after-hash; for a new file, append to a
`pending_created[]` (or `created[]`) before the write. Mirror the forward pipeline's
"state_set_step ... started" → mutate → "completed" pattern.

### WR-02: `--resume` re-runs the dirty-tree gate without re-propagating `--force` — recovery deadlock

**File:** `scripts/adopt.sh:361-368` (and `570`), `cli/conjure:206-220`
**Issue:** `resume_pipeline` calls `run_pipeline`, which unconditionally calls
`precondition_git` (line 570). Consider the supported flow: a user runs
`conjure adopt --force` on a dirty tree, it partially completes (scaffold has
already added untracked harness files, making the tree *dirtier*), then crashes.
On `conjure adopt --resume`, `CONJURE_ADOPT_FORCE` defaults to `0` (the user did not
re-pass `--force`, and `cmd_adopt` always exports the parsed value), so
`precondition_git` finds the dirty tree and `exit 2`s — blocking the very recovery
the resume flow is meant to provide. The user cannot resume without also passing
`--force`, which is undocumented and non-obvious.

**Fix:** On resume, skip the dirty-tree gate (state already exists and the snapshot
already captured the tree), or read the original `--force` decision back from
`state.json` and honor it. E.g. gate `precondition_git` on
`[ "${CONJURE_ADOPT_REUSE_SNAPSHOT:-0}" != "1" ]`, since resume legitimately
continues an already-snapshotted run.

### WR-03: rollback's whole-tree restore truncates the durable audit log (SAFE-07 / D-04)

**File:** `scripts/adopt.sh:278-285`
**Issue:** The snapshot is taken at the "snapshot" step, *after* `log_init` writes
`RESTRUCTURE-LOG.md` but *before* the INVENTORY/SCAFFOLD/AUDIT entries are appended.
So the snapshot's copy of `RESTRUCTURE-LOG.md` contains only the header + the
SNAPSHOT entry. In `rollback_path`, `snapshot_rollback` does a whole-tree
`cp -a snapshot/. target/`, which overwrites the *live* log (carrying the full
forward-run trail) with that stale copy; the subsequent `log_step ROLLBACK` then
appends to the truncated file. The forward-run INVENTORY/SCAFFOLD/AUDIT history is
lost from the durable audit trail that D-04 explicitly says to preserve. The header
comment carefully captures `created[]`/`mutated[]` into temp files before the
restore for exactly this reason, but did not account for the log.

**Fix:** Before `snapshot_rollback`, copy the live `RESTRUCTURE-LOG.md` aside (like
`created_list`/`mutated_list`); after the restore, move it back (or append the
preserved entries) so the trail is `[forward entries] ... [ROLLBACK]`. The test
(`tests/run.sh:2594`) only asserts a `[ROLLBACK]` line exists, so it does not catch
the lost history.

### WR-04: `--apply-step` accepts a `dest` anywhere under the target, including `.git/` and the snapshot backups

**File:** `scripts/adopt.sh:493-496`
**Issue:** `apply_write_op` validates `dest` only via `resolve_under "$target_abs"
"$d_rel"`, which permits any path under the target (no `..`, no escape). A manifest
step (skill-authored content in Phase 23) can therefore set `dest` to
`.conjure-adopt-backups/conjure-adopt-<ts>/CLAUDE.md`, `.git/hooks/pre-commit`,
`.conjure-adopt-state/state.json`, etc. Writing into `.conjure-adopt-backups/`
corrupts the very snapshot rollback depends on; writing into `.git/hooks/` is a
code-execution foot-gun on a tool that mutates arbitrary user repos. The `src`
side is correctly constrained to live under `staging/`, but the `dest` side has no
equivalent denylist.

**Fix:** Reject `dest` paths that resolve under conjure's own control dirs
(`.conjure-adopt-backups/`, `.conjure-adopt-state/`, `.conjure-archive-*/`) and
under `.git/`. Add a containment check after `resolve_under`:
```bash
case "$dest_abs/" in
  "$target_abs/.git/"*|"$target_abs/.conjure-adopt-backups/"*|\
  "$target_abs/.conjure-adopt-state/"*|"$target_abs/.conjure-archive-"*)
    echo "✗ adopt.sh: --apply-step: write dest '$d_rel' targets a protected dir (rejected)" >&2
    exit 2 ;;
esac
```

### WR-05: `update_manifest` does not validate the `op` field against the allowlist

**File:** `scripts/adopt.sh:404-409`
**Issue:** `update_manifest` validates only that the proposed step is an object with
`id`, `op`, and `status`. It does **not** check that `op` is one of
{write, archive, extract}, so an arbitrary `op` value (e.g.
`{"id":"x","op":"delete","status":"proposed"}`) is appended to
`restructure_steps[]`. The op-type allowlist is enforced only later in
`apply_step` (lines 455-458). While that does prevent execution of an unknown op,
defense-in-depth on the inbound half is cheap and the phase context lists the
op-allowlist as a manifest-write safety property. A persisted invalid op is also a
latent confusion for the Phase 23 skill and any schema validation.

**Fix:** Extend the validation predicate to assert the allowlist at write time:
```bash
if ! printf '%s' "$step_json" | jq -e '
  type=="object" and has("id") and has("op") and has("status")
  and (.op=="write" or .op=="archive" or .op=="extract")' >/dev/null 2>&1; then
  echo "✗ adopt.sh: --update-manifest: malformed step — requires {id, op∈{write,archive,extract}, status}" >&2
  exit 2
fi
```

## Info

### IN-01: `update_manifest` `cat`s stdin with no guard — blocks indefinitely on an interactive TTY

**File:** `scripts/adopt.sh:396-399`
**Issue:** When `CONJURE_ADOPT_STEP_JSON` is unset, `update_manifest` falls back to
`step_json="$(cat)"`. If a user runs `conjure adopt --update-manifest` interactively
without piping anything in, `cat` blocks forever on the terminal with no prompt or
hint. The intended caller is the Phase 23 skill (which pipes JSON), but a human
invocation hangs silently.
**Fix:** Detect a TTY on stdin and emit usage instead of blocking:
```bash
if [ -z "$step_json" ]; then
  if [ -t 0 ]; then
    echo "✗ adopt.sh: --update-manifest: pass step JSON via stdin or CONJURE_ADOPT_STEP_JSON" >&2
    exit 2
  fi
  step_json="$(cat)"
fi
```

### IN-02: `manifest_write_atomic` does not pre-check that the manifest exists

**File:** `scripts/adopt.sh:373-383`
**Issue:** Unlike `state_record` (which handles the create-vs-update split),
`manifest_write_atomic` always runs `jq "$@" "$filter" "$MANIFEST_PATH"`. If
`$MANIFEST_PATH` is missing, jq fails and the function `exit 2`s with a generic
"failed to update manifest" message. Both callers (`update_manifest`, `apply_step`)
do guard `[ -f "$MANIFEST_PATH" ]` first, so this is not currently reachable, but
the helper is fragile if reused. Consider a clearer error or an explicit existence
check inside the helper.

### IN-03: `extract` op is entirely untested

**File:** `tests/run.sh:2750-2810`
**Issue:** The `--apply-step` test section exercises `write` (step-1) and `archive`
(step-2) but never `extract`. Combined with CR-02, the `extract` op shipped broken
and undetected. Add a fixture step with `op: extract` plus assertions that (a) the
old destination content lands in `.conjure-archive-*/`, (b) the new content lands at
`dest`, and (c) the staging file is consumed correctly.

### IN-04: `cli/conjure` failure paths use `return 1`, conflicting with the exit-2 convention

**File:** `cli/conjure:288, 290, 294, 389` (and others)
**Issue:** Project convention reserves `exit 1` for unknown-command dispatch; hard
failures should `exit 2`. Several `cmd_update` failure branches (`git checkout -b
failed`, `git push failed`, `conjure update --apply failed`, `Backup failed`) and
load-failure branches `return 1`, which propagates to a script `exit 1` via the
dispatch table. These are pre-existing (not introduced by Phase 22 — the new
`cmd_adopt` correctly uses `cmd_preflight || return 1` mirroring its siblings), but
since `cli/conjure` is in scope: the failure-path `return 1`s should be `return 2`
to honor the convention. Note `cmd_update --pr` already correctly uses `return 2`
for the missing-`gh` case (line 240), so the file is internally inconsistent.

---

_Reviewed: 2026-05-29T00:00:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
