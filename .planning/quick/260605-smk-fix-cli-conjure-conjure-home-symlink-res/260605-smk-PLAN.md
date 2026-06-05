---
phase: quick-260605-smk
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - cli/conjure
  - tests/run.sh
autonomous: true
requirements:
  - CONJURE_HOME symlink resolution (bug fix — no formal REQ ID)
must_haves:
  truths:
    - "conjure version invoked via symlink prints a real version string, not 'conjure unknown'"
    - "CONJURE_HOME resolves to the repo root even when $0 is a symlink"
    - "The existing CONJURE_HOME env-override still works (unmodified when set)"
  artifacts:
    - path: cli/conjure
      provides: "Symlink-safe CONJURE_HOME resolution using portable while-loop readlink"
      contains: "while [ -h"
    - path: tests/run.sh
      provides: "Regression test: symlink invocation of conjure version"
      contains: "symlink.*version\|version.*symlink"
  key_links:
    - from: cli/conjure
      to: lib/mutate.sh
      via: "CONJURE_HOME must resolve to repo root so sourced libs are found"
      pattern: "source.*CONJURE_HOME.*mutate"
---

<objective>
Fix cli/conjure CONJURE_HOME resolution so it follows symlinks before computing the
home path. When `make install` symlinks `~/.local/bin/conjure → repo/cli/conjure`,
the current `$(dirname "$0")` expands to `~/.local/bin`, making CONJURE_HOME point
at `~/.local` instead of the repo — causing every lib source to fail.

Purpose: Unblock users who install via `make install`; also fixes the "conjure unknown"
version string that results from CONJURE_HOME being wrong.

Output: Patched cli/conjure with a portable POSIX 3.2-compatible while-loop symlink
resolver, plus a regression test in tests/run.sh that would have caught this.
</objective>

<execution_context>
@$HOME/.claude/get-shit-done/workflows/execute-plan.md
@$HOME/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/STATE.md
@.planning/PROJECT.md
</context>

<tasks>

<task type="auto">
  <name>Task 1: Fix CONJURE_HOME resolution in cli/conjure</name>
  <files>cli/conjure</files>
  <action>
Replace line 24 of cli/conjure — the single-line CONJURE_HOME assignment — with the
portable while-loop symlink resolver, then re-derive CONJURE_HOME from the resolved
path. The replacement block must go between `set -uo pipefail` and the first use of
`CONJURE_HOME` (which is line 25, the VERSION read).

Replace:
  CONJURE_HOME="${CONJURE_HOME:-$(cd "$(dirname "$0")/.." && pwd)}"

With (verbatim — do NOT use readlink -f or realpath; plain readlink IS portable):
  _CONJURE_SOURCE="$0"
  while [ -h "$_CONJURE_SOURCE" ]; do
    _CONJURE_DIR="$(cd "$(dirname "$_CONJURE_SOURCE")" && pwd)"
    _CONJURE_SOURCE="$(readlink "$_CONJURE_SOURCE")"
    case "$_CONJURE_SOURCE" in /*) ;; *) _CONJURE_SOURCE="$_CONJURE_DIR/$_CONJURE_SOURCE" ;; esac
  done
  CONJURE_HOME="${CONJURE_HOME:-$(cd "$(dirname "$_CONJURE_SOURCE")/.." && pwd)}"
  unset _CONJURE_SOURCE _CONJURE_DIR

Preserve the existing env-override behavior: the assignment uses `:-` so a
pre-set CONJURE_HOME env var is still honored without modification.

After editing, run: shellcheck -S error -e SC2164,SC2044,SC2034,SC2155 cli/conjure
to confirm zero new shellcheck errors. The `unset` ensures the private temp vars
don't pollute the script's env and avoids SC2034 (unused variable) warnings.
  </action>
  <verify>
    <automated>shellcheck -S error -e SC2164,SC2044,SC2034,SC2155 cli/conjure && grep -c 'while \[ -h' cli/conjure | grep -q '^1$' && echo "patch present and shellcheck clean"</automated>
  </verify>
  <done>cli/conjure passes shellcheck with zero errors; the while-loop resolver block is present; CONJURE_HOME still accepts env override.</done>
</task>

<task type="auto">
  <name>Task 2: Add symlink-invocation regression test to tests/run.sh</name>
  <files>tests/run.sh</files>
  <action>
Append a new test block immediately before the "Clean up any gh-hiding stub dirs"
comment near the bottom of tests/run.sh (the line: `# ──── ... Clean up ...`).

The block must follow the graceful-red pattern used throughout the file: create
a temp dir, run the assertion, pass/fail, then clean up. Gate on IS_WINDOWS so
the test is skipped on platforms where `ln -s` creates plain files.

Insert this block (verbatim):

  # CONJURE_HOME symlink resolution: invoking conjure via a symlink must resolve
  # CONJURE_HOME to the repo root, not the symlink's parent dir.
  echo
  echo "▸ CONJURE_HOME symlink resolution"
  if [ "$IS_WINDOWS" = "1" ]; then
    pass "conjure version via symlink: N/A on Windows (no real symlinks)"
  else
    _SYM_TMP="$(mktemp -d)"
    ln -s "$CONJURE_HOME/cli/conjure" "$_SYM_TMP/conjure"
    _SYM_OUT="$("$_SYM_TMP/conjure" version 2>&1 || true)"
    rm -rf "$_SYM_TMP"
    unset _SYM_TMP
    if printf '%s' "$_SYM_OUT" | grep -qv 'unknown'; then
      pass "conjure version via symlink: resolved correctly ($_SYM_OUT)"
    else
      fail "conjure version via symlink: got '$_SYM_OUT' — CONJURE_HOME not resolved through symlink"
    fi
    unset _SYM_OUT
  fi

The `echo "▸ CONJURE_HOME symlink resolution"` header follows the same section
header style used throughout the file (see line 63: `echo "▸ Smoke tests"`).

Do NOT modify any existing test, helper function, or the final summary block.
  </action>
  <verify>
    <automated>bash tests/run.sh 2>&1 | grep -E "symlink resolution|conjure version via symlink"</automated>
  </verify>
  <done>tests/run.sh includes the symlink regression block; running it on a non-Windows host prints "✓ conjure version via symlink: resolved correctly (conjure X.Y.Z)".</done>
</task>

</tasks>

<threat_model>
## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| filesystem → shell | $0 is attacker-controlled only if the shell itself is compromised; not a new surface |

## STRIDE Threat Register

| Threat ID | Category | Component | Disposition | Mitigation Plan |
|-----------|----------|-----------|-------------|-----------------|
| T-smk-01 | Tampering | readlink output | accept | readlink output is a filesystem path resolved by the kernel; no untrusted data enters the path-resolution loop |
| T-smk-SC | Tampering | npm/pip/cargo installs | accept | No new package installs in this fix |
</threat_model>

<verification>
1. `shellcheck -S error -e SC2164,SC2044,SC2034,SC2155 cli/conjure` exits 0
2. `bash tests/run.sh 2>&1 | grep "conjure version via symlink"` shows a PASS line
3. Manually: `ln -s $(pwd)/cli/conjure /tmp/conjure-test && /tmp/conjure-test version` prints "conjure X.Y.Z" (not "conjure unknown")
4. `CONJURE_HOME=/some/override cli/conjure version` still uses /some/override (env override preserved)
</verification>

<success_criteria>
- cli/conjure resolves CONJURE_HOME correctly when invoked via symlink on macOS and Linux
- No regression: direct invocation and CONJURE_HOME env-override continue to work
- tests/run.sh passes with the new symlink regression block emitting PASS
- shellcheck reports zero errors on cli/conjure
</success_criteria>

<output>
Create `.planning/quick/260605-smk-fix-cli-conjure-conjure-home-symlink-res/260605-smk-SUMMARY.md` when done.
</output>
