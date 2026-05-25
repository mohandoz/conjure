---
phase: 04-regression-suite-dry-run-proof
fixed_at: 2026-05-25T00:00:00Z
review_path: .planning/phases/04-regression-suite-dry-run-proof/04-REVIEW.md
iteration: 2
findings_in_scope: 7
fixed: 7
skipped: 0
status: all_fixed
---

# Phase 04: Code Review Fix Report

**Fixed at:** 2026-05-25
**Source review:** .planning/phases/04-regression-suite-dry-run-proof/04-REVIEW.md
**Iteration:** 2

**Summary:**
- Findings in scope: 7 (3 Critical + 4 Warning across both iterations)
- Fixed: 7
- Skipped: 0

## Fixed Issues — Iteration 1 (prior review)

### CR-01: EXIT trap chain overwrites TMPDIR_TARGET cleanup

**Files modified:** `tests/run.sh`
**Commit:** e350a98
**Applied fix:** Added explicit `rm -rf "$TMPDIR_TARGET"` and `trap - EXIT` immediately after the dry-run section ends (before the first `sandbox_setup` call). Since `bash trap EXIT` is not additive, the subsequent `sandbox_setup` trap would silently overwrite the TMPDIR_TARGET cleanup, leaking the directory on every normal run. Cleaning up eagerly before that point eliminates the leak without requiring an additive trap wrapper.

---

### CR-02: `trap RETURN` bypassed by `exit 1` in `regen_profile`

**Files modified:** `scripts/regen-fixtures.sh`
**Commit:** 8526500
**Applied fix:** Changed `exit 1` to `return 1` inside `regen_profile` on the audit-failure path. `trap RETURN` only fires on `return` or function fallthrough, not on `exit`. The `return 1` lets the trap fire and clean `$seed`, then the main loop propagates the failure with `if ! regen_profile "$p"; then exit 1; fi`.

---

### WR-01: Sandbox PATH strips nvm/fnm node installations

**Files modified:** `tests/lib/sandbox.sh`
**Commit:** a8e02c0
**Applied fix:** In `sandbox_setup`, resolve the node binary's parent directory at call time via `dirname "$(command -v node)"` and include it in PATH with the `${_node_dir:+$_node_dir:}` idiom. Falls back gracefully to empty (no-op) when node is not in PATH. The conjure CLI directory still takes precedence. Updated the header comment to reflect the new PATH composition.

---

### WR-02: CI shellcheck silences SC2086 and SC2046 globally

**Files modified:** `.github/workflows/ci.yml`, `cli/conjure`, `scripts/regen-fixtures.sh`, `migrations/from-claude/migrate.sh`, `tests/run.sh`
**Commit:** 45bf5be
**Applied fix:** Identified all four legitimate use-sites of SC2086/SC2046 across the scanned scripts — intentional word-splitting on `$PROFILES` in `regen-fixtures.sh`, and three `for f in $(find ...)` / `for i in $(seq ...)` loops in `cli/conjure`, `migrations/from-claude/migrate.sh`, and `tests/run.sh`. Added `# shellcheck disable=SC2046` or `# shellcheck disable=SC2086` inline at each site, then removed both codes from the global `-e` exclusion list in `ci.yml`.

---

### WR-03: Unquoted `$GITHUB_WORKSPACE` in CI `run` blocks

**Files modified:** `.github/workflows/ci.yml`
**Commit:** d7ee3c7
**Applied fix:** Quoted all three unquoted `$GITHUB_WORKSPACE` occurrences in the `audit-on-fixture` job's `run` blocks (lines 44, 49, 51 in original). The `CONJURE_HOME="$GITHUB_WORKSPACE"` assignment in `windows-hook-wiring` was already correctly quoted.

---

### WR-04: Windows CI job writes to `/tmp/fixture`

**Files modified:** `.github/workflows/ci.yml`
**Commit:** 269b597
**Applied fix:** Replaced all four `/tmp/fixture` references in the `windows-hook-wiring` job with `"$RUNNER_TEMP/fixture"`. `$RUNNER_TEMP` is always available on GitHub Actions across all OS runners; `/tmp` availability is not guaranteed in all Git Bash (MINGW) versions on Windows.

---

## Fixed Issues — Iteration 2 (re-review)

### CR-03: `regen_profile` destroys committed fixture on audit failure

**Files modified:** `scripts/regen-fixtures.sh`
**Applied fix:** Moved `bash audit-setup.sh` to run against `$seed` (the temp dir) BEFORE the `rm -rf "${FIXTURES_DIR:?}/$p"` + `cp -r` sequence. Previously, the committed fixture was deleted and replaced first; an audit failure left `$FIXTURES_DIR/$p` holding the new broken content with no restoration path. Now the committed fixture is only replaced after the seed passes audit. The error message was updated to `committed fixture unchanged` to reflect the new invariant.

---

## Verification

All fixes verified with:
- **Tier 1:** Re-read of modified file sections confirming fix text present and surrounding code intact.
- **Tier 2:** `bash -n` syntax check on all modified `.sh` files (all passed).

---

_Fixed: 2026-05-25_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 2_
