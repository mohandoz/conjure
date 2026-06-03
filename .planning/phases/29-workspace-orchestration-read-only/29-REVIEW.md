---
phase: 29-workspace-orchestration-read-only
reviewed: 2026-06-04T00:00:00Z
depth: standard
files_reviewed: 3
files_reviewed_list:
  - lib/workspace.sh
  - scripts/workspace.sh
  - cli/conjure
findings:
  critical: 0
  warning: 0
  info: 1
  total: 1
status: clean
---

# Phase 29: Code Review Report (Iteration 2 — Security Re-Review)

**Reviewed:** 2026-06-04T00:00:00Z
**Depth:** standard (security-focused adversarial)
**Files Reviewed:** 3
**Status:** clean

## Summary

Re-review of the path-traversal boundary fix (CR-01, CR-02) plus five warning
fixes (WR-01..WR-05) landed across commits `e5ea6f2`, `9ade713`, `4a68fe0`,
`fc67b7b`, `f7925e9`. I adversarially attacked the corrected boundary with
crafted manifests and direct function drives. **All attacks were repelled; no
new Critical or Warning defects were introduced by the five fix commits.**

### CR-01 — validate-time boundary (lib/workspace.sh:42-83) — VERIFIED FIXED

The boundary now resolves the manifest dir with `cd "$manifest_dir" && pwd -P`
and compares each resolved repo path with `case "$resolved" in "$root"|"$root/"*)`.
Adversarial results (all REJECT/exit 2 unless noted):

- `../ws-evil` (sibling escape) → rejected.
- `./../ws-evil` (dot-dot escape) → rejected.
- `good/../../ws-evil` (mid-path escape) → rejected.
- **Prefix attack** `root=/private/tmp/wstest/ws` vs target `/private/tmp/wstest/ws-evil`
  → rejected. The trailing `/` in the `"$root/"*` pattern prevents the `ws-evil`
  (and `wsevil`) name from matching `ws/` — confirmed both via end-to-end run and
  isolated `case` unit test.
- **Symlink inside workspace pointing outside** (`linkout -> /tmp/wstest/outside`)
  → rejected, because `pwd -P` resolves through the symlink to the real outside
  target before comparison.
- **Legit symlinked workspace ROOT** (manifest reached via `ws-link -> ws`)
  → accepted (exit 0): the base is `pwd -P`-resolved first, so it matches the
  resolved repo paths.
- Degenerate values `""`, `.`, `..`, `"null"`, and a missing `path` key (jq emits
  `"null"`) → all rejected (WR-04).
- Spaces in path (`my repo`) and glob chars (`a[b]`) for legit under-root dirs
  → accepted, no word-splitting or glob expansion (paths are quoted throughout).

### CR-02 — execution-time re-check (scripts/workspace.sh:79-97, 178-198) — VERIFIED FIXED

Drove `ws_do_check` and `ws_do_audit` directly with manifests that bypass
validate-time guards (out-of-bounds symlink repo and literal `good/../../ws-evil`):

- Out-of-bounds repo → row printed as `SKIP / out-of-bounds`, stderr emits
  `⚠ SECURITY: skipping ...: escapes workspace root`, and **no `conjure check`/
  `conjure audit` subprocess executes against the out-of-bounds path.**
- In-bounds repos in the same manifest still execute normally (observed real
  `drift`/`FAIL` results).
- Counts appear in the table: check sets `overall_rc=1`; audit increments
  `skip_count` and bumps `overall_rc` to ≥1. Audit summary `Skip:` reflects it.

### Warning fixes — all VERIFIED

- **WR-01** symlinked-sibling discovery warning: `init` emits
  `⚠ skipping symlinked repo (not added to manifest): .../linkout` to stderr while
  stdout stays canonical. Empty parent dir produces no spurious warning under
  bash 3.2 (literal glob `/dir/*` fails `[ -L ]`).
- **WR-02** `workspace <sub> --help` forwarding: `init`/`check`/`audit --help`
  each print their subcommand-specific usage (rc 0); bare `workspace --help`
  prints the wrapper usage.
- **WR-03** dry-run init: prints `(dry-run) would write N repo(s) to ...` and
  writes **no** file (confirmed manifest absent after run).
- **WR-04** degenerate paths rejected (covered under CR-01 above).
- **WR-05** init self-validation: generated manifest is re-run through
  `workspace_manifest_validate`; on failure it is `rm -f`'d and exit 2. The
  `rm -f "$MANIFEST_PATH"` is correctly bounded to the just-written path.

### Re-confirmation of unchanged invariants

- **Aggregate exit semantics:** check 0/1 fail-tolerant; audit 0/1/2 with
  `--fail-fast` aborting at first fail (rc 2). Verified via suite tests
  `WS-04-audit-failfast`, `WS-03-check-fail-tolerant`.
- **Single `_ws_cleanup` EXIT trap:** registered once at script top (line 30);
  `ws_do_audit` adds no trap of its own and reuses script-level `TMPJSON`.
- **No tempfile leak:** `TMPJSON` allocated only inside `ws_do_audit`, removed by
  `_ws_cleanup` on EXIT (including the `--fail-fast` early `return 2`).
- **POSIX bash 3.2+:** no associative arrays / `mapfile` / `local -n` / `readarray`
  in any changed file; verified executing under system `bash 3.2.57`.
- **shellcheck `-S error -e SC2164,SC2044,SC2034,SC2155`:** clean (rc 0) across
  all three files.
- **Full suite:** 562 PASS / 0 FAIL, including the new `WS-SEC-*`, `WS-DISC-*`,
  `WS-INIT-*`, and `WS-CLI-subhelp` cases.

## Info

### IN-01: Bad-path `-d` guard precedes the traversal re-check (defense-in-depth ordering)

**File:** `scripts/workspace.sh:72`, `scripts/workspace.sh:171`
**Issue:** In both `ws_do_check` and `ws_do_audit` the `[ ! -d "$repo_abs" ]`
existence guard runs *before* the `pwd -P` traversal re-check. This is not a
vulnerability — a non-existent path is skipped as `bad-path` and never executed,
and any existing out-of-bounds path still reaches and is caught by the re-check
(verified). The note is only that the existence check is evaluated against the
unresolved `repo_abs`; the security decision correctly lives in the subsequent
`pwd -P` comparison, so ordering is safe. No change required.
**Fix:** None needed; documented for reviewer awareness. Optionally add an inline
comment clarifying that the `-d` guard is a UX convenience and the boundary
decision is the `pwd -P` re-check immediately following.

---

_Reviewed: 2026-06-04T00:00:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard (security re-review)_
