---
phase: 03-sandboxed-per-profile-fixtures
reviewed: 2026-05-25T00:00:00Z
depth: standard
files_reviewed: 9
files_reviewed_list:
  - tests/lib/sandbox.sh
  - scripts/regen-fixtures.sh
  - tests/fixtures/_broken/CLAUDE.md
  - tests/fixtures/_broken/.claudeignore
  - tests/fixtures/_broken/.editorconfig
  - tests/fixtures/_broken/.env.example
  - tests/fixtures/_broken/.gitattributes
  - tests/fixtures/_broken/package.json
  - tests/run.sh
findings:
  critical: 2
  warning: 3
  info: 2
  total: 7
status: issues_found
---

# Phase 03: Code Review Report

**Reviewed:** 2026-05-25T00:00:00Z
**Depth:** standard
**Files Reviewed:** 9
**Status:** issues_found

## Summary

Reviewed the sandboxed per-profile fixture infrastructure: the sandbox helper library,
the fixture regeneration script, the broken fixture corpus, and the main test runner.
The fixture data files (`.claudeignore`, `.editorconfig`, `.env.example`, `.gitattributes`,
`package.json`) are clean configuration stubs with no issues.

The core infrastructure has two blockers. First, `sandbox_setup()` has no guard on its
`fixture_dir` argument — an empty string causes `cp -r "/." "$SANDBOX_DIR/"`, copying the
root filesystem into the temp dir. Second, `tests/run.sh` leaks `$TMPDIR_TARGET` because
every call to `sandbox_setup()` (and the duplicate trap lines in the loop) replaces the
previous `EXIT` trap rather than stacking it, so the dry-run temp dir registered at line 189
is silently orphaned when the fixture loop begins at line 250.

Three warnings cover: EXIT traps being overwritten in the loop leaving earlier sandboxes
un-cleaned, a description-length off-by-one that allows 29-char descriptions to pass a
>=30-char check, and an invalid-profile name being silently ignored by `regen-fixtures.sh`.

## Critical Issues

### CR-01: Unguarded empty-argument in `sandbox_setup()` copies root filesystem

**File:** `tests/lib/sandbox.sh:36`
**Issue:** `sandbox_setup()` does not validate its `$1` argument. If the caller passes an
empty string or an unset variable, `fixture_dir` becomes `""` and the `cp` on line 36
expands to `cp -r "/." "$SANDBOX_DIR/"` — attempting to copy the entire root filesystem
into the temp dir. In a CI environment with broad permissions this will exhaust disk space
or copy sensitive files; on a restrictive system it will spray permission errors while
leaving `SANDBOX_DIR` in an undefined partial state. The subsequent `export HOME="$SANDBOX_DIR"`
then points the test process's HOME at that polluted directory for the remainder of the run.

**Fix:**
```bash
sandbox_setup() {
  local fixture_dir="${1:?sandbox_setup requires a fixture_dir argument}"
  if [ ! -d "$fixture_dir" ]; then
    printf 'sandbox_setup: fixture_dir does not exist: %s\n' "$fixture_dir" >&2
    return 1
  fi
  SANDBOX_DIR="$(mktemp -d)"
  trap 'rm -rf "$SANDBOX_DIR"' EXIT
  cp -r "$fixture_dir/." "$SANDBOX_DIR/"
  export HOME="$SANDBOX_DIR"
  export XDG_CONFIG_HOME="$SANDBOX_DIR"
  export CLAUDE_CONFIG_DIR="$SANDBOX_DIR"
  export PATH="$CONJURE_HOME/cli:/usr/local/bin:/usr/bin:/bin"
}
```

---

### CR-02: `$TMPDIR_TARGET` is never cleaned — EXIT trap overwritten by fixture loop

**File:** `tests/run.sh:189,250-251`
**Issue:** `bash` replaces (not stacks) the `EXIT` trap on each `trap ... EXIT` call.
The dry-run section registers cleanup for `$TMPDIR_TARGET` at line 189. At line 250,
`sandbox_setup()` registers a new `EXIT` trap for `$SANDBOX_DIR`, silently discarding
the `TMPDIR_TARGET` trap. Line 251 immediately overwrites it again. The result: `TMPDIR_TARGET`
is never removed when the test runner exits. On a CI agent that runs thousands of tests, the
leaked directories accumulate until disk space is exhausted.

This can be confirmed by the bash semantics: `bash -c "trap 'echo first' EXIT; trap 'echo second' EXIT"` prints only `second`.

Additionally, because `$SANDBOX_DIR` is a global variable late-bound in the trap string
(single-quoted), all earlier iterations of the fixture loop also have their sandbox dirs
leaked — only the final `$SANDBOX_DIR` value at exit time is cleaned.

**Fix:** Use an additive cleanup pattern. Replace isolated trap statements with a shared
cleanup function that accumulates paths:

```bash
# At the top of run.sh, after set -uo pipefail:
_CLEANUP_DIRS=()
_cleanup() {
  for d in "${_CLEANUP_DIRS[@]+"${_CLEANUP_DIRS[@]}"}"; do
    rm -rf "$d"
  done
}
trap '_cleanup' EXIT

# Replace all: trap 'rm -rf "$VAR"' EXIT
# With:        _CLEANUP_DIRS+=("$VAR")
```

In `sandbox.sh`, replace the EXIT trap with either an exported function reference or
document that callers must use the accumulator pattern above.

---

## Warnings

### WR-01: Fixture loop EXIT traps overwrite each other — earlier sandboxes leak until process exit

**File:** `tests/run.sh:250-251`
**Issue:** (Closely related to CR-02 but distinct scope.) Within the fixture loop, each
iteration calls `sandbox_setup "$fx"` which registers a new `EXIT` trap. Line 251
immediately registers another one. Because bash replaces traps, only the last loop
iteration's `SANDBOX_DIR` value is cleaned at exit. All earlier iterations' sandbox dirs
remain on disk until the process terminates (at which point only the last one is cleaned).
With 9 profile fixtures each creating a `mktemp -d`, up to 8 temp dirs are leaked per test
run. This is a separate concern from CR-02 (which is about `TMPDIR_TARGET`); both are
caused by the same design gap.

**Fix:** Apply the additive cleanup pattern from CR-02. In `sandbox_setup()`, push to
`_CLEANUP_DIRS` instead of registering a new EXIT trap.

---

### WR-02: Description-length check has an off-by-one — 29-char descriptions pass silently

**File:** `tests/run.sh:56-57`
**Issue:** The description length check uses `wc -c` (byte count) on the output of `echo`,
which appends a trailing newline. A 29-character description string produces `wc -c = 30`.
The guard `[ "$desc_len" -lt 30 ]` evaluates `30 < 30` which is false, so the check
passes — but the description is one character short of the required 30-char minimum. Any
skill with a 29-byte ASCII description silently evades the length gate.

```
# Demonstration:
$ python3 -c "print('a'*29)" | wc -c
30   # 29 chars + 1 newline byte
```

**Fix:** Either use `printf '%s'` to suppress the trailing newline before piping to `wc -c`,
or shift the threshold by 1:

```bash
# Option A — suppress trailing newline (semantically correct):
desc_len=$(printf '%s' "$desc_line" | sed 's/^description: //;s/^"//;s/"$//' | wc -c | tr -d ' ')
if [ "$desc_len" -lt 30 ]; then fail "description too short ($desc_len chars): $skill"; fi

# Option B — adjust threshold to account for newline:
if [ "$desc_len" -lt 31 ]; then fail "description too short ($desc_len chars): $skill"; fi
```

Option A is preferred because it makes the byte count semantically match "character count"
for ASCII input and avoids confusion when reading the threshold number.

---

### WR-03: `--profile <invalid>` is silently ignored in `regen-fixtures.sh`

**File:** `scripts/regen-fixtures.sh:113-117`
**Issue:** When `--profile` is given an unrecognized name (e.g., `--profile typo`), the
`PROFILE_FILTER` is set but no profile ever matches in the loop, so the script iterates
over all 9 profiles, skips each one, and exits 0 with no output and no fixtures regenerated.
The caller receives no indication that the profile name was invalid. This makes typos
completely invisible and is especially dangerous in CI where the exit code 0 signals
success.

**Fix:** Validate `PROFILE_FILTER` against the known `PROFILES` list immediately after
argument parsing:

```bash
if [ -n "$PROFILE_FILTER" ]; then
  case " $PROFILES " in
    *" $PROFILE_FILTER "*) ;;
    *)
      printf 'Unknown profile: %s\nValid profiles: %s\n' "$PROFILE_FILTER" "$PROFILES" >&2
      exit 1
      ;;
  esac
fi
```

---

## Info

### IN-01: `$CONJURE_HOME` unvalidated in `sandbox_setup()` — no guard against unset caller

**File:** `tests/lib/sandbox.sh:40`
**Issue:** `sandbox_setup()` uses `$CONJURE_HOME` in the `PATH` export on line 40 without
checking whether the variable is set. The file header notes "CONJURE_HOME is intentionally
NOT overridden" but does not mandate it be non-empty. If a caller sources `sandbox.sh`
without first setting `CONJURE_HOME`, the `PATH` export silently becomes
`:/usr/local/bin:/usr/bin:/bin` (colon-prefixed) — which adds the current working directory
to `PATH`, a security concern for any subsequent command lookup. Under `set -u` this would
error, but `sandbox.sh` has no `set` options and inherits its caller's settings.

**Fix:** Add a guard at the top of `sandbox_setup()`:

```bash
sandbox_setup() {
  : "${CONJURE_HOME:?sandbox_setup requires CONJURE_HOME to be set}"
  ...
}
```

---

### IN-02: Unquoted `$PROFILES` expansion in `for` loop

**File:** `scripts/regen-fixtures.sh:113`
**Issue:** `for p in $PROFILES` relies on word-splitting the unquoted variable. While this
works correctly because profile names contain no IFS characters, shellcheck (SC2086) flags
it and it is fragile against future profile names with spaces or against IFS changes. The
project uses shellcheck as a quality gate.

**Fix:** Use an array or a here-string approach:

```bash
# Option A — iterate via read and a here-string (array-free, POSIX-safe):
while IFS= read -r p; do
  ...
done <<EOF
$(printf '%s\n' $PROFILES)
EOF

# Option B — quote the variable (only safe if profiles have no spaces, which is enforced):
for p in $PROFILES; do  # shellcheck disable=SC2086 — profiles are space-separated by design
  ...
done
```

The simplest fix for the shellcheck gate is the inline disable comment with a justification.

---

_Reviewed: 2026-05-25T00:00:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
