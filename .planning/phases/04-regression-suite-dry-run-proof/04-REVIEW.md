---
phase: 04-regression-suite-dry-run-proof
reviewed: 2026-05-25T12:00:00Z
depth: standard
files_reviewed: 4
files_reviewed_list:
  - tests/run.sh
  - scripts/regen-fixtures.sh
  - .github/workflows/ci.yml
  - tests/lib/sandbox.sh
findings:
  critical: 1
  warning: 0
  info: 4
  total: 5
status: issues_found
---

# Phase 04: Code Review Report (Re-review)

**Reviewed:** 2026-05-25
**Depth:** standard
**Files Reviewed:** 4
**Status:** issues_found

## Summary

This is a re-review of Phase 04. The prior review identified 10 issues (CR-01, CR-02,
WR-01 through WR-04, IN-01 through IN-04). All 6 critical and warning findings were
addressed in subsequent commits, confirmed below. The 4 Info findings were not addressed
and carry forward. One new Critical finding is identified: `regen_profile` in
`scripts/regen-fixtures.sh` destroys the committed fixture for a profile when `conjure
init` succeeds but `audit-setup.sh` fails — the old fixture is deleted, the new one is
not re-committed, and the RETURN trap does not restore it.

### Prior Fix Confirmation

| Finding | Description | Status |
|---------|-------------|--------|
| CR-01 | EXIT trap chain leaked TMPDIR_TARGET | Fixed — `rm -rf "$TMPDIR_TARGET"` + `trap - EXIT` added at line 221-222 of `tests/run.sh` before first `sandbox_setup` call |
| CR-02 | `exit 1` in `regen_profile` bypassed `trap RETURN` | Fixed — changed to `return 1` at `regen-fixtures.sh:127`; caller uses `exit 1` at line 146 |
| WR-01 | Sandbox PATH omitted nvm/fnm node dir | Fixed — `tests/lib/sandbox.sh` now resolves node via `command -v node` and appends its directory to PATH |
| WR-02 | SC2086/SC2046 suppressed globally in shellcheck | Fixed — removed from global CI exclusion; inline disables added at `tests/run.sh:340`, `regen-fixtures.sh:137`, `cli/conjure:157`, `migrations/from-claude/migrate.sh:58,85` |
| WR-03 | Unquoted `$GITHUB_WORKSPACE` in CI | Fixed — all four uses are now quoted |
| WR-04 | `/tmp/fixture` on Windows runner | Fixed — `windows-hook-wiring` job now uses `$RUNNER_TEMP/fixture` throughout |

---

## Critical Issues

### CR-03: `regen_profile` destroys committed fixture on audit failure — irrecoverable data loss

**File:** `scripts/regen-fixtures.sh:123-127`

**Issue:** `regen_profile` deletes the existing committed fixture directory at line 123
(`rm -rf "${FIXTURES_DIR:?}/$p"`) before verifying the new fixture passes audit. The
new content is then copied in at line 124. Only at line 125 does the audit run. If the
audit fails, the function does `return 1` at line 127 — the RETURN trap fires and cleans
up `$seed`, but `$FIXTURES_DIR/$p` already holds the new failing content and is not
cleaned up or restored. The caller (`exit 1` at line 146) aborts, leaving the repository
with a corrupt or empty fixture for that profile.

This is a data-loss risk: running `bash scripts/regen-fixtures.sh --profile ts-next`
when a `conjure init` profile change produces a fixture that fails audit will silently
trash the previously-committed `tests/fixtures/ts-next/` and replace it with a broken
copy. The developer must notice the partial state via `git diff` and manually restore.

**Fix:** Audit in the seed directory before clobbering the committed fixture. Only
replace the committed fixture after the audit passes:

```bash
regen_profile() {
  local p="$1"
  printf '[regen] %s\n' "$p"
  local seed
  seed="$(mktemp -d)"
  trap 'rm -rf "$seed"' RETURN
  _write_manifest "$p" "$seed"
  _write_seed_claude "$seed"
  CONJURE_HOME="$CONJURE_HOME" "$CONJURE_HOME/cli/conjure" init --profile="$p" "$seed" >/dev/null
  # Audit in the seed dir BEFORE touching the committed fixture.
  if ! bash "$CONJURE_HOME/scripts/audit-setup.sh" "$seed" >/dev/null 2>&1; then
    printf '[regen] WARN: %s fixture fails audit — committed fixture unchanged\n' "$p" >&2
    return 1
  fi
  rm -rf "${FIXTURES_DIR:?}/$p"
  cp -r "$seed/." "$FIXTURES_DIR/$p/"
  _write_expect "$p"
  printf '[regen] %s done\n' "$p"
}
```

---

## Warnings

No warnings. All prior WR findings confirmed fixed.

---

## Info

### IN-01: Redundant EXIT trap registrations in `tests/run.sh`

**File:** `tests/run.sh:257, 274, 301, 382, 495`

**Issue:** `sandbox_setup` (in `tests/lib/sandbox.sh:36`) already registers
`trap 'rm -rf "$SANDBOX_DIR"' EXIT` internally. Every call-site in `run.sh` immediately
re-registers the identical trap on the very next line (lines 257, 274, 301, 382, 495).
The second registration is harmless (same command, same signal), but it is misleading —
it implies traps are additive when they are not, and it will silently lose any other EXIT
trap registered between the `sandbox_setup` call and the redundant line.

Note: the corresponding `trap - EXIT` lines that follow are load-bearing and must remain,
because `sandbox_setup` does not clear the trap when it is done. Only the registrations
immediately after `sandbox_setup` are redundant.

**Fix:** Remove the five redundant `trap 'rm -rf "$SANDBOX_DIR"' EXIT` lines from
`run.sh` (lines 257, 274, 301, 382, 495). The trap from inside `sandbox_setup` is
sufficient for cleanup on abnormal exit; the caller's explicit `rm -rf "$SANDBOX_DIR"`
handles the normal-exit cleanup path.

---

### IN-02: Dead CI step — `bash scripts/audit-setup.sh . || true` always passes

**File:** `.github/workflows/ci.yml:37`

**Issue:** The `test` job contains:

```yaml
- name: Audit script smoke
  run: bash scripts/audit-setup.sh . || true
```

`|| true` means the step always exits 0 regardless of the audit result. This step
provides zero CI signal: no crash or regression in `audit-setup.sh` itself can cause
CI to fail here. The `audit-on-fixture` job already tests `audit-setup.sh` more
rigorously; this step is either dead code or incorrectly written.

**Fix:** Either remove the step entirely, or replace with a version that accepts
known-good exit codes (0=pass, 1=warnings, 2=CLAUDE.md missing) but fails on crashes:

```yaml
- name: Audit script smoke
  run: |
    bash scripts/audit-setup.sh . ; rc=$?
    [ "$rc" -le 2 ] || exit "$rc"
```

---

### IN-03: `tests/run.sh` missing `set -e` for setup section

**File:** `tests/run.sh:4`

**Issue:** The script uses `set -uo pipefail` but omits `set -e`. Intentionally dropping
`-e` for the test body is reasonable (individual assertion failures should not abort the
run). However, the same laxness applies to the setup section: if `source
"$CONJURE_HOME/tests/lib/sandbox.sh"` fails, or if the `cd "$CONJURE_HOME"` fails, bash
continues silently with an undefined `CONJURE_HOME` context and the test run produces
results that are entirely meaningless.

**Fix:** Use strict mode during the setup phase and relax it only for the test body:

```bash
set -euo pipefail   # strict during setup

CONJURE_HOME="$(cd "$(dirname "$0")/.." && pwd)"
cd "$CONJURE_HOME"
source "$CONJURE_HOME/tests/lib/sandbox.sh"

set +e              # allow test failures without aborting suite
PASS=0
FAIL=0
```

---

### IN-04: `--profile` accepts invalid profile names silently in `regen-fixtures.sh`

**File:** `scripts/regen-fixtures.sh:138-149`

**Issue:** When `--profile invalid-name` is passed, the main loop iterates all 9 known
profiles, skips every one (because none matches `PROFILE_FILTER`), produces no output,
and exits 0. A developer with a typo (`ts_next` instead of `ts-next`) gets no indication
that nothing was regenerated.

**Fix:** After the loop, detect that a filter was active but nothing was processed:

```bash
PROCESSED=0
for p in $PROFILES; do
  if [ -n "$PROFILE_FILTER" ] && [ "$p" != "$PROFILE_FILTER" ]; then
    continue
  fi
  PROCESSED=$((PROCESSED + 1))
  if [ -n "${UPDATE_EXPECT:-}" ]; then
    _write_expect "$p"
  else
    if ! regen_profile "$p"; then
      exit 1
    fi
  fi
done

if [ -n "$PROFILE_FILTER" ] && [ "$PROCESSED" -eq 0 ]; then
  printf 'Unknown profile: %s\nValid profiles: %s\n' "$PROFILE_FILTER" "$PROFILES" >&2
  exit 1
fi
```

---

_Reviewed: 2026-05-25_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
