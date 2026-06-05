---
phase: quick-260605-smk
plan: "01"
subsystem: cli
tags: [bug-fix, symlink, conjure-home, posix, regression-test]
dependency_graph:
  requires: []
  provides: [symlink-safe-conjure-invocation]
  affects: [cli/conjure, tests/run.sh]
tech_stack:
  added: []
  patterns: [portable-while-loop-readlink-resolver]
key_files:
  created: []
  modified:
    - cli/conjure
    - tests/run.sh
decisions:
  - "Use portable while-loop readlink (not readlink -f / realpath) to stay POSIX 3.2+ compatible"
  - "Unset _CONJURE_SOURCE and _CONJURE_DIR after use to avoid SC2034 (unused variable) warnings"
  - "Preserve :- env-override pattern so CONJURE_HOME=... still takes precedence"
metrics:
  duration: "8min"
  completed: "2026-06-05"
  tasks: 2
  files: 2
---

# Phase quick-260605-smk Plan 01: CONJURE_HOME Symlink Resolution Fix Summary

**One-liner:** Portable while-loop readlink resolver replaces `dirname "$0"` in cli/conjure, fixing "conjure unknown" for `make install` symlink users.

## What Was Built

Fixed `CONJURE_HOME` resolution in `cli/conjure` so invoking the binary through a symlink (e.g. `~/.local/bin/conjure -> repo/cli/conjure`) correctly resolves back to the repo root instead of the symlink's parent directory. Added a regression test in `tests/run.sh` that catches this failure class going forward.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Fix CONJURE_HOME resolution in cli/conjure | ad054da | cli/conjure |
| 2 | Add symlink-invocation regression test to tests/run.sh | 6bafa6d | tests/run.sh |

## Implementation Details

### Task 1 — cli/conjure (ad054da)

Replaced line 24:
```bash
CONJURE_HOME="${CONJURE_HOME:-$(cd "$(dirname "$0")/.." && pwd)}"
```

With a portable while-loop resolver:
```bash
_CONJURE_SOURCE="$0"
while [ -h "$_CONJURE_SOURCE" ]; do
  _CONJURE_DIR="$(cd "$(dirname "$_CONJURE_SOURCE")" && pwd)"
  _CONJURE_SOURCE="$(readlink "$_CONJURE_SOURCE")"
  case "$_CONJURE_SOURCE" in /*) ;; *) _CONJURE_SOURCE="$_CONJURE_DIR/$_CONJURE_SOURCE" ;; esac
done
CONJURE_HOME="${CONJURE_HOME:-$(cd "$(dirname "$_CONJURE_SOURCE")/.." && pwd)}"
unset _CONJURE_SOURCE _CONJURE_DIR
```

The loop handles both absolute and relative symlink targets (the `case` block resolves relative targets against the symlink's directory). Multiple levels of symlink chaining are handled by the `while` condition.

### Task 2 — tests/run.sh (6bafa6d)

Added a regression test block immediately before the final cleanup section. The test:
1. Creates a temp symlink pointing to `$CONJURE_HOME/cli/conjure`
2. Invokes `conjure version` through the symlink
3. Asserts output does not contain "unknown"
4. Cleans up temp dir and unsets temp vars
5. Gates on `IS_WINDOWS=1` to skip where `ln -s` is not a real symlink

## Verification

- `shellcheck -S error -e SC2164,SC2044,SC2034,SC2155 cli/conjure`: exits 0 (PASS)
- `grep -c 'while \[ -h' cli/conjure`: returns 1 (patch present)
- Manual symlink test: `conjure version` via symlink prints "conjure 0.5.0" (not "conjure unknown")
- Env override preserved: `CONJURE_HOME=/some/override conjure version` uses /some/override

## Deviations from Plan

None — plan executed exactly as written.

## Known Stubs

None.

## Threat Flags

None. The while-loop resolver reads only filesystem paths through `readlink` (kernel-resolved); no new trust boundaries introduced.

## Self-Check

- [x] cli/conjure modified with while-loop resolver
- [x] tests/run.sh modified with regression block
- [x] Commit ad054da exists
- [x] Commit 6bafa6d exists
- [x] shellcheck passes
- [x] Manual symlink verification passes

## Self-Check: PASSED
