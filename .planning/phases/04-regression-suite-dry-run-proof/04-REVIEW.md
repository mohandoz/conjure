---
phase: 04-regression-suite-dry-run-proof
reviewed: 2026-05-25T00:00:00Z
depth: standard
files_reviewed: 3
files_reviewed_list:
  - tests/run.sh
  - scripts/regen-fixtures.sh
  - .github/workflows/ci.yml
findings:
  critical: 2
  warning: 4
  info: 4
  total: 10
status: issues_found
---

# Phase 04: Code Review Report

**Reviewed:** 2026-05-25
**Depth:** standard
**Files Reviewed:** 3
**Status:** issues_found

## Summary

Three files reviewed: the main regression test runner (`tests/run.sh`), the fixture
regeneration helper (`scripts/regen-fixtures.sh`), and the GitHub Actions workflow
(`.github/workflows/ci.yml`). The core test logic is sound and the dry-run enforcement
assertions are well-constructed. However, two critical defects were identified: a bash
`trap EXIT` replacement chain that leaks the `TMPDIR_TARGET` temp directory on every
normal run, and a misuse of `trap RETURN` in `regen-fixtures.sh` that leaks a seed
directory on audit failure. Four warnings cover a narrowed `PATH` in the sandbox that
breaks `nvm`/`fnm` users, two silently suppressed shellcheck codes that guard quoting
safety, an unquoted `$GITHUB_WORKSPACE` in CI YAML, and an unreliable `/tmp` path on
the Windows runner.

---

## Critical Issues

### CR-01: EXIT trap chain overwrites TMPDIR_TARGET cleanup — directory always leaks

**File:** `tests/run.sh:189`

**Issue:** Bash `trap ... EXIT` is not additive — each call replaces the previous
handler. `TMPDIR_TARGET` is created at line 188 and its cleanup trap is registered at
line 189. The very first call to `sandbox_setup` (line 250, inside the
`tests/lib/sandbox.sh` sourced library, at its line 35) registers a new `trap 'rm -rf
"$SANDBOX_DIR"' EXIT` that silently overwrites the `TMPDIR_TARGET` trap. From that
point forward `TMPDIR_TARGET` has no cleanup handler and its directory persists in
`/tmp` for the lifetime of the OS session. This happens on every normal run of
`tests/run.sh` that reaches the fixture-audit section.

**Fix:** Accumulate cleanup commands in a single trap using a wrapper, or explicitly
delete `TMPDIR_TARGET` immediately after the dry-run section ends (before
`sandbox_setup` is first called):

```bash
# After the dry-run section finishes (around line 216), before fixture audits start:
rm -rf "$TMPDIR_TARGET"
trap - EXIT   # clear the now-unnecessary trap

# Then let sandbox_setup manage its own EXIT trap from here on.
```

Alternatively, use an additive trap wrapper that prepends rather than replaces:

```bash
add_exit_trap() {
  local _prev
  _prev=$(trap -p EXIT | sed "s/trap -- '//;s/' EXIT//")
  trap "${_prev:+$_prev; }$1" EXIT
}
```

---

### CR-02: `trap RETURN` bypassed by `exit 1` in `regen_profile` — seed directory leaks

**File:** `scripts/regen-fixtures.sh:119,127`

**Issue:** `regen_profile` registers `trap 'rm -rf "$seed"' RETURN` at line 119 to
clean up its temp seed directory. However, on audit failure the function executes
`exit 1` at line 127. In bash, `trap ... RETURN` fires only when a function returns
via `return` or falls off its end — it does **not** fire on `exit`. As a result, every
time `regen_profile` hits the audit-failure path, the `$seed` directory (containing a
full scaffolded project) is left in `/tmp` until the OS evicts it.

**Fix:** Replace `exit 1` with `return 1` so the RETURN trap fires, then let the
caller decide whether to abort:

```bash
  if ! bash "$CONJURE_HOME/scripts/audit-setup.sh" "$FIXTURES_DIR/$p" >/dev/null 2>&1; then
    printf '[regen] WARN: %s fixture fails audit — check profile output\n' "$p" >&2
    return 1   # triggers 'trap RETURN', cleans $seed
  fi
```

In the main loop, propagate the failure:

```bash
  if ! regen_profile "$p"; then
    exit 1
  fi
```

---

## Warnings

### WR-01: Sandbox PATH strips nvm/fnm node installations — silent false failures on dev machines

**File:** `tests/lib/sandbox.sh:40`

**Issue:** `sandbox_setup` hard-codes `PATH="$CONJURE_HOME/cli:/usr/local/bin:/usr/bin:/bin"`.
Tools installed via `nvm`, `fnm`, `volta`, or Homebrew on Apple Silicon
(`/opt/homebrew/bin`) are omitted. If a developer runs `tests/run.sh` with `node`
coming from one of these managers, fixture audits that internally invoke node hooks
will fail with "command not found" rather than producing a meaningful audit result.
This produces misleading test failures that are unrelated to the code under test.

**Fix:** Preserve the system `PATH` alongside the sandbox prefix, or at minimum include
the resolved `node` parent directory:

```bash
# Preserve existing PATH; just prepend the conjure CLI dir so 'conjure' resolves first
export PATH="$CONJURE_HOME/cli:$PATH"
```

If full isolation is required (e.g., to prevent accidental use of developer-local
tools), append a resolved node path:

```bash
NODE_DIR="$(dirname "$(command -v node 2>/dev/null || true)")"
export PATH="$CONJURE_HOME/cli:${NODE_DIR:+$NODE_DIR:}/usr/local/bin:/usr/bin:/bin"
```

---

### WR-02: CI shellcheck silences SC2086 and SC2046 globally — quoting bugs go unreported

**File:** `.github/workflows/ci.yml:23`

**Issue:** The shellcheck invocation passes `-e SC2086,SC2046,SC2164,SC2044,SC2034,SC2155`.
`SC2086` (unquoted variable expansion, word-splitting risk) and `SC2046` (unquoted
command substitution) are the two shellcheck codes most directly associated with
command-injection and accidental word-splitting bugs. Suppressing them globally means
the lint gate cannot catch new quoting regressions in any of the scripts it covers
(`cli/`, `scripts/`, `migrations/`, `profiles/`, `compliance/`, `templates/hooks/`,
`tests/`).

**Fix:** Remove `SC2086` and `SC2046` from the global exclusion list. Where specific
lines legitimately require an unquoted expansion, suppress inline:

```yaml
find cli scripts migrations profiles compliance templates/hooks tests -name '*.sh' \
  -exec shellcheck -S error -e SC2164,SC2044,SC2034,SC2155 {} +
```

Fix or inline-suppress the resulting findings rather than blanket-ignoring them.

---

### WR-03: Unquoted `$GITHUB_WORKSPACE` in CI `run` blocks — path-with-spaces breaks steps

**File:** `.github/workflows/ci.yml:44,49,51,63`

**Issue:** All four uses of `$GITHUB_WORKSPACE` in the `audit-on-fixture` and
`windows-hook-wiring` job `run` blocks are unquoted:

```yaml
bash $GITHUB_WORKSPACE/scripts/init-project.sh new /tmp/fixture
```

If the workspace path ever contains a space (possible on self-hosted runners or
custom configurations), the shell splits the path, the `bash` invocation fails with a
"no such file" error, and the CI step silently proceeds because the `audit-on-fixture`
job uses `|| true`.

**Fix:** Quote all `$GITHUB_WORKSPACE` references:

```yaml
bash "$GITHUB_WORKSPACE/scripts/init-project.sh" new /tmp/fixture
```

---

### WR-04: Windows CI job writes to `/tmp/fixture` — unreliable on Windows runners

**File:** `.github/workflows/ci.yml:61,63,71,76`

**Issue:** The `windows-hook-wiring` job uses `/tmp/fixture` as a work directory on
`windows-latest`. Even with Git Bash (MINGW), `/tmp` is a virtual mount whose
availability is not guaranteed across Git Bash versions. If the runner's Git Bash does
not create `/tmp`, `mkdir -p /tmp/fixture` succeeds silently on some versions but
`cli/conjure init /tmp/fixture` may write to an unexpected location or fail, causing
the subsequent `grep` assertion to pass vacuously (because `settings.json` was never
created).

**Fix:** Use `$RUNNER_TEMP` (always available on GitHub Actions, all OSes) instead of
a hard-coded `/tmp`:

```yaml
- name: Scaffold fixture
  shell: bash
  run: |
    mkdir -p "$RUNNER_TEMP/fixture"
    CONJURE_HOME="$GITHUB_WORKSPACE" cli/conjure init "$RUNNER_TEMP/fixture"

- name: Assert node hook wiring in settings.json
  shell: bash
  run: grep 'node' "$RUNNER_TEMP/fixture/.claude/settings.json"
```

---

## Info

### IN-01: Redundant EXIT trap registrations in `tests/run.sh`

**File:** `tests/run.sh:251,266,291`

**Issue:** After calling `sandbox_setup` (which already registers `trap 'rm -rf
"$SANDBOX_DIR"' EXIT` internally), `run.sh` immediately re-registers the identical
trap on the next line. This is harmless but adds noise and reinforces a misunderstanding
that traps are additive. It also makes CR-01 harder to reason about.

**Fix:** Remove the three redundant `trap 'rm -rf "$SANDBOX_DIR"' EXIT` lines from
`run.sh` (lines 251, 266, 291) and rely solely on the trap registered inside
`sandbox_setup`.

---

### IN-02: Dead CI step — `bash scripts/audit-setup.sh . || true` always passes

**File:** `.github/workflows/ci.yml:34`

**Issue:** The `test` job includes:

```yaml
- name: Audit script smoke
  run: bash scripts/audit-setup.sh . || true
```

`|| true` means the step always exits 0 regardless of the audit's result. The step
provides zero signal: it cannot cause CI to fail, so any crash or regression in
`audit-setup.sh` itself goes unreported.

**Fix:** Either remove the step entirely (the `audit-on-fixture` job already tests
`audit-setup.sh` more thoroughly), or drop `|| true` and let it fail meaningfully.
Given the repo has no `.claude/` directory, exit 2 ("CLAUDE.md missing") is expected —
accept that code explicitly:

```yaml
- name: Audit script smoke
  run: |
    bash scripts/audit-setup.sh . ; rc=$?
    [ "$rc" -le 2 ] || exit "$rc"
```

---

### IN-03: `tests/run.sh` missing `set -e` — real setup errors swallowed silently

**File:** `tests/run.sh:4`

**Issue:** The script uses `set -uo pipefail` but omits `set -e`. While intentionally
omitting `-e` is reasonable for a test runner (so individual test failures do not abort
the suite), it also means real infrastructure errors — a failed `cd`, a sourced library
that does not exist, or a broken `mktemp` — are swallowed without aborting the run.
The suite then reports potentially meaningless results.

**Fix:** Keep `-e` off for the test body, but guard the setup section (before `PASS=0`)
explicitly:

```bash
set -euo pipefail   # strict during setup

# ... setup: source sandbox, set CONJURE_HOME, etc. ...

set +e              # permit test-assertion failures from here on
PASS=0; FAIL=0
```

---

### IN-04: `--profile` accepts invalid profile names silently

**File:** `scripts/regen-fixtures.sh:138`

**Issue:** When `--profile invalid-name` is passed, the main loop matches nothing,
prints nothing, and exits 0. A developer with a typo (e.g., `ts_next` instead of
`ts-next`) gets no indication that nothing happened.

**Fix:** After the loop, check whether a filter was active and whether any profile was
actually processed:

```bash
PROCESSED=0
for p in $PROFILES; do
  if [ -n "$PROFILE_FILTER" ] && [ "$p" != "$PROFILE_FILTER" ]; then
    continue
  fi
  PROCESSED=$((PROCESSED + 1))
  ...
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
