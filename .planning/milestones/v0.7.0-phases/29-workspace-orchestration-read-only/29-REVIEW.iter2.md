---
phase: 29-workspace-orchestration-read-only
reviewed: 2026-06-03T19:10:00Z
depth: standard
files_reviewed: 3
files_reviewed_list:
  - lib/workspace.sh
  - scripts/workspace.sh
  - cli/conjure
findings:
  critical: 2
  warning: 5
  info: 3
  total: 10
status: issues_found
---

# Phase 29: Code Review Report

**Reviewed:** 2026-06-03T19:10:00Z
**Depth:** standard
**Files Reviewed:** 3
**Status:** issues_found

## Summary

Phase 29 adds read-only workspace orchestration: `conjure workspace init|check|audit`
fanning out per-repo `check --porcelain` / `audit --json` over a `.conjure-workspace.json`
manifest, with an aggregate exit-1 partial-success semantic and a path-traversal guard.

Most of the orchestration is sound and was verified empirically against
`tests/fixtures/_workspace*`:
- Aggregate exit codes propagate correctly (drift/warn → 1, fail/parse-failure → 2).
- Non-JSON / empty-output capture is **not** laundered into a pass — it falls into the
  catch-all `*)` branch → counts as fail → exit 2 (verified with a `.claude`-less repo).
- `--fail-fast` aborts at first failure with no tempfile leak (single `_ws_cleanup` EXIT
  trap; `TMPJSON` is truncated each iteration via `>`, so no stale-read across repos).
- init's non-TTY gate (`</dev/null` without `--yes`) exits 2 and writes **no** partial
  manifest; `--yes` writes via `mutate_write` (backup-before-mutate honored).
- shellcheck (`-S error -e SC2164,SC2044,SC2034,SC2155`) passes; no POSIX-3.2-banned
  constructs; no literal `exit 1` (aggregate exit is via `return "$overall_rc"`).

**However, the security centerpiece — the path-traversal guard — is broken in both
directions**, and is additionally **never applied to the repo paths that check/audit
actually execute against**. These are the two BLOCKERs below. I was able to make the
tool run per-repo commands against an out-of-bounds directory using the committed
`_workspace-badpath` fixture, and separately make it falsely reject a legitimate
symlinked workspace.

## Critical Issues

### CR-01: Path-traversal guard computes `workspace_root` one level too high — accepts `../sibling` escapes AND falsely rejects legit symlinked workspaces

**File:** `lib/workspace.sh:41-45,62-68`
**Issue:**
The guard derives the boundary as the **parent** of the workspace, not the workspace
itself:

```sh
workspace_root="$(cd "$manifest_dir/.." 2>/dev/null && pwd -P)"   # ← manifest_dir/.. is WRONG
...
case "$resolved" in
  "$workspace_root/"*) ;;   # OK
  *) echo "✗ repo path escapes workspace root: ..."; return 2 ;;
esac
```

Because the manifest lives at `<workspace>/.conjure-workspace.json`, `manifest_dir` IS the
workspace root, but `workspace_root` is set to `<workspace>/..`. Consequences (both reproduced):

1. **Escape accepted (security).** The committed fixture
   `tests/fixtures/_workspace-badpath/.conjure-workspace.json` has
   `"path": "../_workspace/repos/alpha"`. That path escapes `_workspace-badpath` into the
   sibling `_workspace` directory, yet `workspace_manifest_validate` returns **0**:
   ```
   $ workspace_manifest_validate tests/fixtures/_workspace-badpath/.conjure-workspace.json; echo $?
   0
   ```
   Any `../<sibling>` (and deeper, as long as it lands under the grandparent) is accepted.
   A symlink inside the workspace pointing outside resolves via `pwd -P` and can likewise
   slip under the (too-high) root.

2. **Legit setup falsely rejected (CI false-negative).** A workspace reached through a
   symlinked path makes `pwd -P` resolve `manifest_dir/..` to the wrong real parent, so a
   perfectly valid `repos/alpha` is rejected with exit 2:
   ```
   ✗ repo path escapes workspace root: repos/alpha (resolved: /private/var/.../repos/alpha)
   rc=2
   ```

**Fix:** Anchor the boundary to the (resolved) manifest directory itself, and resolve
`manifest_dir` with `pwd -P` so the comparison base matches the resolved repo paths:
```sh
local workspace_root
workspace_root="$(cd "$manifest_dir" 2>/dev/null && pwd -P)" || {
  echo "✗ cannot resolve workspace root from manifest dir: $manifest_dir" >&2
  return 2
}
...
resolved="$(cd "$workspace_root/$rpath" 2>/dev/null && pwd -P)" || continue
case "$resolved" in
  "$workspace_root"|"$workspace_root/"*) ;;   # repo == root or under root
  *) echo "✗ repo path escapes workspace root: $rpath (resolved: $resolved)" >&2; return 2 ;;
esac
```
After this fix, re-verify against `_workspace-badpath` (must now `return 2`) and against a
symlinked-workspace setup (must now `return 0`). Consider also rejecting empty/`.`/`null`
paths explicitly (see WR-04).

### CR-02: check/audit run per-repo commands without re-applying the traversal guard to repo paths

**File:** `scripts/workspace.sh:61-69,89` and `133-141,189`
**Issue:**
`ws_do_check` and `ws_do_audit` build `repo_abs="$manifest_dir/$repo_relpath"` and gate it
only with `[ ! -d "$repo_abs" ]` (bad-path skip). They never re-run the traversal guard on
the repo path before invoking `cli/conjure check/audit "$repo_abs"`. The only guard is in
`workspace_manifest_load`, and (per CR-01) that guard is permissive — so an escaping path
is executed against. Reproduced end-to-end with the committed fixture:

```
$ CONJURE_HOME=$PWD bash scripts/workspace.sh check tests/fixtures/_workspace-badpath/.conjure-workspace.json
alpha   drift   1     # ← ran conjure check against ../_workspace/repos/alpha (out of bounds)
beta    drift   1
```

The spec requirement ("rejected paths exit 2 and no per-repo command runs against an
out-of-bounds dir") is violated: the command DID run against an out-of-bounds dir.

**Fix:** Even after CR-01 is fixed, `workspace_manifest_load`'s validation is the gate that
makes this safe — so CR-01 is the primary fix. As defense-in-depth, have `ws_do_check` /
`ws_do_audit` re-confirm each `repo_abs` stays under the resolved manifest dir before
invoking, mirroring the validate logic:
```sh
local repo_real
repo_real="$(cd "$repo_abs" 2>/dev/null && pwd -P)" || { ...skip+warn... ; continue; }
case "$repo_real" in
  "$manifest_root"|"$manifest_root/"*) ;;
  *) printf '%-30s %-15s %s\n' "$repo_name" "SKIP" "out-of-bounds"
     printf '  ⚠ skipping %s: escapes workspace root (%s)\n' "$repo_name" "$repo_real" >&2
     overall_rc=1; continue ;;
esac
```
This keeps the orchestrator safe even if a future caller bypasses
`workspace_manifest_load`.

## Warnings

### WR-01: Symlinked sibling repos are silently dropped from `init` discovery

**File:** `lib/workspace.sh:121`
**Issue:** `find "$parent" -maxdepth 2 -name '.claude' -type d` does not descend into
symlinked subdirectories, so a workspace member exposed via a symlink (`ws/linked ->
/elsewhere/repo` containing `.claude`) is omitted from the generated manifest with no
warning. Reproduced: a workspace with one real repo and one symlinked repo produced
`Repos: 1`. Silent omission means an operator believes a repo is covered when it is not —
a false "everything is monitored" signal.
**Fix:** Either document that symlinked repos are intentionally excluded, or add
`-L`/`find -L` handling with an explicit notice when a symlinked candidate is skipped:
```sh
find -L "$parent" -maxdepth 2 -name '.claude' -type d 2>/dev/null ...
```
(weigh against the symlink-escape risk this re-introduces — prefer an explicit warning over
silent drop).

### WR-02: `--help` after a subcommand prints generic usage, never the subcommand-specific help

**File:** `cli/conjure:575-582`
**Issue:** In `cmd_workspace`, the parse loop consumes the subcommand, then a following
`--help` matches the wrapper's own `--help|-h)` arm and returns generic usage before the
arg is forwarded to `scripts/workspace.sh`. Verified:
```
$ conjure workspace check --help
Usage: conjure workspace init|check|audit [args]   # ← not the check-specific help
```
The subcommand-specific `--help` handlers in `scripts/workspace.sh` (lines 217, 304, 321)
are therefore unreachable through the CLI.
**Fix:** Once a subcommand is captured, stop interpreting flags in the wrapper and forward
the remainder verbatim:
```sh
init|check|audit) subcmd="$1"; shift; break ;;
```
so `--help` flows through to the worker.

### WR-03: DRY_RUN init prints "✓ Workspace manifest written" although nothing was written

**File:** `scripts/workspace.sh:294-297`
**Issue:** With `DRY_RUN=1`, `mutate_write` emits `[dry-run] would write ...` (no write),
but the script unconditionally follows with `✓ Workspace manifest written: ...` and a repo
count. Verified — the success line prints and `ls` confirms no file exists. Contradictory
output can mislead automation/operators into believing a manifest exists.
**Fix:** Gate the success messaging on `DRY_RUN`:
```sh
if [ "${DRY_RUN:-0}" = "1" ]; then
  echo "  (dry-run) would write $REPO_COUNT repo(s) to $MANIFEST_PATH"
else
  echo "✓ Workspace manifest written: $MANIFEST_PATH"
  echo "  Repos: $REPO_COUNT"
fi
```

### WR-04: Empty / `.` / `null` repo paths target the workspace root or a literal "null" dir

**File:** `lib/workspace.sh:48-69`, `scripts/workspace.sh:60-61,132-133`
**Issue:** The guard and orchestrators do not reject degenerate path values:
- `"path": ""` → `repo_abs="$manifest_dir/"` → check/audit run against the **workspace root
  itself** (observed STATUS "drift").
- `"path": "."` → same (targets manifest_dir).
- missing `path` key → `jq -r` emits the literal string `null` → `repo_abs=".../null"`
  (treated as a real subdir named "null"; bad-path-skipped only because it happens not to
  exist).
All three pass `workspace_manifest_validate` (rc=0). Running a per-repo audit against the
orchestration root is unintended and could produce misleading aggregate signals.
**Fix:** In the validate loop, reject empty, `.`, `..`, and `null`/missing paths explicitly:
```sh
case "$rpath" in
  ""|.|..|null) echo "✗ invalid repo path value: '$rpath'" >&2; return 2 ;;
esac
```
and validate with `jq -e '.repos[] | select(.path == null or .path == "")' | length == 0`
up front.

### WR-05: init discovery does not enforce the traversal guard on generated relative paths

**File:** `scripts/workspace.sh:244-294`
**Issue:** `init` validates discovered paths only with `[ ! -d "$rpath" ]` and computes the
stored relative path via `rel="${rpath#"$TARGET/"}"`. If a discovered canonical path does
not share the `TARGET/` prefix (e.g. reached across a mount/symlink boundary where `pwd -P`
diverges), the strip leaves an **absolute** path in the manifest, which later `check`/`audit`
treat as an absolute repo path. The init-time path is never run through
`workspace_manifest_validate`, so the manifest it writes is not guaranteed to satisfy the
same guard that `check`/`audit` rely on.
**Fix:** After building `MANIFEST_CONTENT`, validate it before declaring success:
```sh
mutate_write "$MANIFEST_PATH" "$MANIFEST_CONTENT"
if [ "${DRY_RUN:-0}" != "1" ]; then
  workspace_manifest_validate "$MANIFEST_PATH" || {
    echo "✗ generated manifest failed validation — removing" >&2
    rm -f "$MANIFEST_PATH"; exit 2; }
fi
```

## Info

### IN-01: EXIT-column semantics differ between check (raw rc) and audit (rc vs JSON status)

**File:** `scripts/workspace.sh:181`
**Issue:** In `ws_do_audit`, the STATUS column reflects the parsed JSON `.status` while the
EXIT column shows `repo_rc` (the audit process exit). For a `warn` repo, `conjure audit`
exits 0, so the table shows `STATUS=warn EXIT=0` — readable but the two columns can look
inconsistent to a human scanning for the "1" that drove partial-success. Consider labeling
the column "AUDIT-RC" or deriving it from status for clarity.
**Fix:** Documentation/labeling only; no behavioral change required.

### IN-02: `workspace_discover_siblings` emits debug lines to stdout in some shells

**File:** `lib/workspace.sh:121-130`
**Issue:** During testing under this environment the function printed intermediate
`canon_sibling=`/`sibling=` lines (from an apparent set -x or trace context) intermixed with
results. The function itself does not emit these, but the pipeline's reliance on
line-oriented stdout means any stray stdout write (e.g. a future debug echo) corrupts the
manifest path list. Keep this function's stdout strictly to canonical paths.
**Fix:** No code change required now; flag as a robustness note — route any future
diagnostics to `>&2`.

### IN-03: Repo count uses `wc -l` on `printf '%s\n'` — correct but fragile

**File:** `scripts/workspace.sh:296`
**Issue:** `REPO_COUNT="$(printf '%s\n' "$DISCOVERED" | wc -l | tr -d ' ')"` returns the
correct count only because `$DISCOVERED` has no trailing newline and `printf` adds exactly
one. If `DISCOVERED` were ever empty this yields `1` (it can't be empty here due to the
earlier guard, so harmless today). Prefer counting from the same source used to build the
manifest (`jq '.repos | length'` on the written content) to keep one source of truth.
**Fix:** `REPO_COUNT="$(printf '%s' "$MANIFEST_CONTENT" | jq '.repos | length')"`.

---

_Reviewed: 2026-06-03T19:10:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
