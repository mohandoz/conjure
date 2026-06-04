---
phase: 29-workspace-orchestration-read-only
fixed_at: 2026-06-04T00:00:00Z
review_path: .planning/phases/29-workspace-orchestration-read-only/29-REVIEW.md
iteration: 1
findings_in_scope: 7
fixed: 7
skipped: 0
status: all_fixed
---

# Phase 29: Code Review Fix Report

**Fixed at:** 2026-06-04
**Source review:** .planning/phases/29-workspace-orchestration-read-only/29-REVIEW.md
**Iteration:** 1

**Summary:**
- Findings in scope: 7 (2 BLOCKER/Critical + 5 Warning)
- Fixed: 7
- Skipped: 0
- Test suite: 553 PASS / 0 FAIL → 562 PASS / 0 FAIL (+9 new security/regression tests)
- shellcheck `-S error -e SC2164,SC2044,SC2034,SC2155`: clean across all touched files

## Fixed Issues

### CR-01: Path-traversal guard computes `workspace_root` one level too high

**Files modified:** `lib/workspace.sh`, `tests/fixtures/_workspace-badpath/.conjure-workspace.json`, `tests/run.sh`
**Commit:** e5ea6f2
**Status:** fixed: requires human verification (security-critical boundary logic)
**Applied fix:** Anchored the traversal boundary to the resolved manifest directory itself
(`workspace_root="$(cd "$manifest_dir" && pwd -P)"`) instead of its parent
(`$manifest_dir/..`). Repo paths are now resolved against this resolved root and must be the
root or under it (`case "$resolved" in "$workspace_root"|"$workspace_root/"*) ;; *) reject;;`).
This (1) rejects `../sibling` escapes that previously passed, and (2) accepts legitimate
symlinked workspaces that were previously falsely rejected (resolving the comparison base via
`pwd -P` makes it match the resolved repo paths). Bundled WR-04 here (same case block):
degenerate path values `""`, `.`, `..`, and literal `null` (missing `path` key) are now
rejected with exit 2 before resolution.

**Fixture/test coherence:** The committed `_workspace-badpath` fixture previously relied on a
`../_workspace/...` traversal path that the CORRECTED guard must now reject. The fixture was
updated so all three repo paths are in-bounds (`repos/alpha`, `repos/beta`,
`repos/nonexistent-repo`) — keeping it a genuine bad-path (nonexistent in-bounds repo) case.
The two badpath tests (`WS-03-check-badpath`, `WS-04-audit-badpath`) were updated to create
`repos/alpha` and `repos/beta` in-bounds instead of out-of-bounds `_workspace/...` dirs.

**New regression tests added:**
- `WS-SEC-traversal-escape` — asserts a `../sibling` manifest is rejected with exit 2.
- `WS-SEC-symlink-accept` — asserts a workspace reached via a symlink with in-bounds repos
  validates (exit 0).
- `WS-SEC-degenerate-paths` — asserts empty/`.`/`..`/`null` paths are rejected (WR-04).

### CR-02: check/audit run per-repo commands without re-applying the traversal guard

**Files modified:** `scripts/workspace.sh`, `tests/run.sh`
**Commit:** 9ade713
**Status:** fixed: requires human verification (security-critical execution-time gate)
**Applied fix:** Added a defense-in-depth boundary re-check inside both `ws_do_check` and
`ws_do_audit`. Each function resolves the workspace root once (`pwd -P`) and, for every repo,
re-confirms the resolved `repo_abs` is the root or under it before invoking any command. An
out-of-bounds repo is skipped with a `SECURITY` warning and an `out-of-bounds` table row, never
executed, and counts toward partial-success (exit 1) like a bad-path skip. This keeps the
orchestrator safe even if a future caller bypasses `workspace_manifest_load`.

**New regression tests added:**
- `WS-SEC-no-exec-out-of-bounds` — drives `check` and `audit` through the normal CLI path with
  an escaping manifest; both exit 2 at load time (manifest rejected before any per-repo command).
- `WS-SEC-defense-in-depth` — extracts `ws_do_check` into a sourceable harness (bypassing
  load-time validation) and proves the execution-time re-check skips the out-of-bounds repo with
  a SECURITY/out-of-bounds message and never reports it as drift/clean.

### WR-01: Symlinked sibling repos silently dropped from `init` discovery

**Files modified:** `lib/workspace.sh`, `tests/run.sh`
**Commit:** 4a68fe0
**Applied fix:** Chose the lower-risk option (explicit warning over silent drop, and over
`find -L` which would re-introduce symlink-escape risk). `workspace_discover_siblings` now scans
direct children of the parent, and for any symlinked child containing `.claude/` emits an
explicit `⚠ skipping symlinked repo (not added to manifest): <path>` warning to **stderr**.
stdout remains strictly canonical paths (respects IN-02). Test `WS-DISC-symlink-warn` asserts
the warning appears on stderr, the real repo appears on stdout, and the symlinked repo does not.

### WR-02: `--help` after a subcommand prints generic usage

**Files modified:** `cli/conjure`, `tests/run.sh`
**Commit:** fc67b7b
**Applied fix:** In `cmd_workspace`, once a subcommand is captured the wrapper now `shift; break`s
out of the parse loop and forwards the remainder verbatim to `scripts/workspace.sh`. As a result
`workspace init|check|audit --help` reaches the worker's per-subcommand usage handlers instead of
the wrapper's own `--help` arm. Wrapper-level `--dry-run` placed before the subcommand still works.
Test `WS-CLI-subhelp` asserts `workspace check --help` prints the check-specific usage; verified
`init`/`check` both forward correctly.

### WR-03: DRY_RUN init prints "✓ written" although nothing was written

**Files modified:** `scripts/workspace.sh`, `tests/run.sh`
**Commit:** f7925e9
**Applied fix:** The init success messaging is now gated on `DRY_RUN`. Under `DRY_RUN=1` it prints
`(dry-run) would write N repo(s) to <path>` and no false `✓ written`. Test `WS-INIT-dryrun-msg`
asserts no file is created and the output says "would write" but not "✓ Workspace manifest written".

### WR-04: Empty / `.` / `null` repo paths target the workspace root

**Files modified:** `lib/workspace.sh`, `tests/run.sh` (bundled into commit e5ea6f2 with CR-01)
**Commit:** e5ea6f2
**Applied fix:** `workspace_manifest_validate` now rejects `""`, `.`, `..`, and `null` (missing
`path` key → jq emits literal `null`) repo path values with exit 2 before path resolution. This is
in the same `case` block as the CR-01 guard, which is why the review explicitly couples the two;
they were committed together. Covered by the `WS-SEC-degenerate-paths` regression test.

### WR-05: init doesn't validate its own generated manifest

**Files modified:** `scripts/workspace.sh`, `tests/run.sh`
**Commit:** f7925e9
**Applied fix:** After `mutate_write`, in the non-dry-run branch, init now runs the freshly written
manifest through `workspace_manifest_validate`. If its own output fails the same traversal guard
that check/audit rely on, init removes the file and exits 2 rather than leaving an unsafe manifest
on disk. Bundled with WR-03 because both edits live in the same init success-messaging if/else
block. Test `WS-INIT-self-validate` asserts an init-generated manifest passes validation.

## Notes

- **Bundled findings:** CR-01+WR-04 share the same `case` block in the path-traversal guard and
  were committed together (e5ea6f2). WR-03+WR-05 share the same init success-messaging if/else and
  were committed together (f7925e9). All other findings have dedicated atomic commits.
- **Human verification flag:** CR-01 and CR-02 are security-critical boundary-logic fixes. Although
  all 9 new regression tests pass and the full suite is green, please manually confirm the boundary
  semantics (root-or-under-root acceptance, `pwd -P` resolution, SECURITY-skip on escape) before the
  phase proceeds to verification.
- **Conventions verified:** single `_ws_cleanup` EXIT trap retained; no literal `exit 1` statements
  (only the documented SC-mandated aggregate-exit comments/messages); `mutate_write` still used for
  manifest writes; POSIX bash 3.2+; shellcheck `-S error -e SC2164,SC2044,SC2034,SC2155` clean.
- **Suite:** 562 PASS / 0 FAIL (baseline 553, +9 new tests). No pre-existing test regressed.

---

_Fixed: 2026-06-04_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
