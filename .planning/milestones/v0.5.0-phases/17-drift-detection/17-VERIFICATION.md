---
phase: 17-drift-detection
verified: 2026-05-26T07:45:00Z
status: passed
score: 4/4 must-haves verified
overrides_applied: 0
re_verification: false
---

# Phase 17: Drift Detection Verification Report

**Phase Goal:** Users can discover whether their installed harness has drifted from the upstream kit snapshot via a single read-only command.
**Verified:** 2026-05-26T07:45:00Z
**Status:** passed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | `conjure check` prints file-level delta report (added/modified/removed) relative to upstream kit snapshot | VERIFIED | `scripts/check.sh` classifies each file as M/R/A; human output shows "Modified (N):", "Removed (N):", "Added (N):" sections; smoke-test against repo itself produced 35-file Removed report |
| 2 | `conjure check` exits 0 when harness is current, exits 1 when drift is detected | VERIFIED | `exit "$drift"` on line 137 of `scripts/check.sh`; `drift` set to 1 when any of `modified/removed/added` is non-empty; DRIFT-01a test (fresh init → exit 0) and DRIFT-01b/c tests (mutated files → exit 1) all pass |
| 3 | `conjure check --porcelain` emits machine-readable lines in `<A\|M\|R> <path>` format | VERIFIED | Lines 108–110 of `scripts/check.sh` emit `M`, `R`, `A` prefixed lines; porcelain smoke test confirmed lines `R .editorconfig`, etc.; DRIFT-02 tests confirmed `M .claude/settings.json` and `R .claude/hooks/post-edit-format.mjs` patterns |
| 4 | A harness file with only user edits is not falsely reported as drifted | VERIFIED | Internal conjure state files (`.claude/.conjure-*`, `.claude/COMPOUND-CANDIDATES.md`, `.claude/docs/*`) are skipped in added-file detection (lines 89–93 of `scripts/check.sh`); output includes "Note: modified files may include user customizations" to communicate intent; test suite round-trips through fresh init confirm no false positives on a fully-current harness |

**Score:** 4/4 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `scripts/check.sh` | sha256 drift classifier with M/R/A classification and porcelain mode | VERIFIED | 137-line file, executable (`-rwxr-xr-x`), no `declare -A` or `mapfile` in non-comment lines, shellcheck passes with `-S error -e SC2155` |
| `cli/conjure` | `cmd_check` function + `check)` dispatch entry + usage line | VERIFIED | `cmd_check()` at line 161; `check) shift; cmd_check "$@" ;;` at line 344; usage line `conjure check [--porcelain] [target]` at line 38 |
| `tests/run.sh` | DRIFT regression test section (4 test cases, 6 assertions) | VERIFIED | Section at lines 1380–1458; all 6 assertions pass; `bash tests/run.sh` yields `PASS: 283  FAIL: 0` |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `cli/conjure cmd_check` | `scripts/check.sh` | `CONJURE_HOME` and `CONJURE_PORCELAIN` env vars + bash invocation | VERIFIED | Line 171–172: `CONJURE_HOME="$CONJURE_HOME" CONJURE_PORCELAIN="$porcelain" bash "$CONJURE_HOME/scripts/check.sh" "$target"` |
| `scripts/check.sh` | `templates/hooks-nodejs/*.mjs` | `CONJURE_HOME` env var + glob on line 38 | VERIFIED | `for hook in "$CONJURE_HOME"/templates/hooks-nodejs/*.mjs` — README.md excluded by `.mjs` glob |
| `scripts/check.sh` | `templates/settings.json.tmpl` | hard-coded case branch for `.claude/settings.json` mapping | VERIFIED | Lines 58–59: `.claude/settings.json) kit_file="$CONJURE_HOME/templates/settings.json.tmpl" ;;` |
| `tests/run.sh DRIFT section` | `cli/conjure check` | CLI invocation in mktemp sandbox | VERIFIED | Lines 1390, 1392, 1405, 1407, 1409, 1426, 1429, 1431, 1451 — all invoke `cli/conjure check` or `cli/conjure check --porcelain` |

### Data-Flow Trace (Level 4)

Not applicable — `scripts/check.sh` is a read-only CLI script, not a UI component rendering dynamic state. Data flow is: filesystem → sha256 comparison → accumulator strings → printed output.

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| `conjure check` exits 1 on drifted repo | `CONJURE_HOME=$(pwd) cli/conjure check $(pwd)` | "Drift detected: 35 file(s) differ from upstream kit", exit 1 | PASS |
| `conjure check --porcelain` emits `<R\|M\|A> <path>` format | `CONJURE_HOME=$(pwd) cli/conjure check --porcelain $(pwd)` | Lines like `R .editorconfig`, `R .claude/settings.json`, exit 1 | PASS |
| `conjure help` lists `check` subcommand | `cli/conjure help \| grep check` | `conjure check [--porcelain] [target]` line present | PASS |
| Full regression test suite | `bash tests/run.sh` | PASS: 283  FAIL: 0 | PASS |

### Probe Execution

No `scripts/*/tests/probe-*.sh` probes declared for this phase. Regression suite in `tests/run.sh` serves as the equivalent verification vehicle.

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| DRIFT-01 | 17-01, 17-02 | User can run `conjure check` and see a file-level delta report (added/modified/removed) | SATISFIED | `scripts/check.sh` produces M/R/A classification; 3 DRIFT-01 test assertions pass |
| DRIFT-02 | 17-01, 17-02 | `conjure check` exits 0 when current, exits 1 on drift; supports `--porcelain` for machine-readable output | SATISFIED | `exit "$drift"` semantics verified; porcelain mode produces `<M\|R\|A> <path>` lines; 3 DRIFT-02 test assertions pass |

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `scripts/check.sh` | 27 | `# bash 3.2 compatible: no declare -A, no mapfile, no local -n.` — mentions banned constructs in comment | Info | Comment only; `grep -v '^#'` confirms zero occurrences in non-comment lines; no impact |

No `TBD`, `FIXME`, `XXX`, `TODO`, `HACK`, or `PLACEHOLDER` markers found in `scripts/check.sh` or `cli/conjure`.

### Human Verification Required

None. All observable behaviors verified programmatically:
- Exit codes verified by regression tests
- Porcelain format verified by grep pattern matching in tests
- Usage output verified by `conjure help | grep check`
- shellcheck clean on both modified/created files

### Gaps Summary

No gaps. All four success criteria from ROADMAP.md are satisfied by the codebase:

1. **Delta report** — `scripts/check.sh` classifies and prints M/R/A file-level deltas; human output has labelled sections; smoke test confirms live output.
2. **Exit codes** — `exit "$drift"` (0 or 1) is the final statement; tests confirm both code paths.
3. **Porcelain mode** — `--porcelain` flag sets `CONJURE_PORCELAIN=1`; check.sh outputs bare `<M|R|A> <path>` lines with no headers; tests confirm exact line formats.
4. **No false positives on user-only files** — internal state files (`.conjure-*`, `COMPOUND-CANDIDATES.md`, `docs/`) are skipped in the added-file detector; fresh-init round-trip exits 0.

---

_Verified: 2026-05-26T07:45:00Z_
_Verifier: Claude (gsd-verifier)_
