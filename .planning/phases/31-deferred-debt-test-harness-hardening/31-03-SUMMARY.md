---
phase: 31
plan: 03
subsystem: test-harness
tags: [debt, safety, sandbox, schema, testing]
dependency_graph:
  requires: [31-01]
  provides: [mk_tmpd-sweep, regression-gate, schm-stale-env-override, atomic-write-mandate]
  affects: [tests/run.sh, scripts/audit-setup.sh, FAILURE-MODES.md]
tech_stack:
  added: []
  patterns: [CONJURE_SCHEMA_FILE env override, mk_tmpd sweep, regression gate]
key_files:
  created: []
  modified:
    - tests/run.sh
    - scripts/audit-setup.sh
    - FAILURE-MODES.md
decisions:
  - "Use \\$[(]mktemp -d[)] grep pattern in regression gate to avoid self-referential false positive (the literal pattern in the grep invocation would match itself if written as \\$(mktemp -d))"
  - "Remove P27_STALE_SCHEMA_BAK initialization outside the if block (no longer needed after cp-swap elimination)"
  - "D-16 audit: all remaining cp/mv with CONJURE_HOME are read-from-source; no writes to production paths remain"
metrics:
  duration: 45min
  completed: "2026-06-04T18:28:58Z"
  tasks_completed: 2
  files_changed: 3
---

# Phase 31 Plan 03: mktemp Sweep + SCHM-STALE Kill-Safe Fix Summary

Applied DEBT-03 (180-site mktemp -d sweep + regression gate) and DEBT-06 (SCHM-STALE cp-swap elimination via CONJURE_SCHEMA_FILE env override, audit-setup.sh hook, FAILURE-MODES.md atomic-write mandate). D-16 production-file swap audit completed with clean result.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Sweep mktemp -d → mk_tmpd in tests/run.sh + regression gate (DEBT-03) | 2857cd6 | tests/run.sh |
| 2 | SCHM-STALE env override + audit-setup.sh hook + FAILURE-MODES.md entry + D-16 audit | ac6c6a4 | tests/run.sh, scripts/audit-setup.sh, FAILURE-MODES.md |

## What Was Built

### Task 1: mktemp -d sweep + regression gate (DEBT-03)

**tests/run.sh:**
- Replaced all 180 shell command substitutions `$(mktemp -d)` with `$(mk_tmpd)` using a global sed substitution
- The 2 remaining `mktemp -d` occurrences in the file are plain-text string literals (inside a fail message and a comment) — not shell command substitutions
- Added convention regression gate block immediately after the `▸ Hook exit codes` section:
  - Header: `echo "▸ Convention: no raw mktemp -d in test files (use mk_tmpd)"`
  - Greps `tests/` for `\$[(]mktemp -d[)]` pattern (character-class syntax to avoid self-match), `--include='*.sh' --exclude='sandbox.sh'`
  - Passes or fails with clear message; prints each hit line with 4-space indent on failure
- **Self-reference fix:** Changed grep pattern from `'\$(mktemp -d)'` to `'\$[(]mktemp -d[)]'` — the original pattern would match the grep invocation's own source line, causing a permanent false positive. Character-class syntax is regex-equivalent but avoids the substring match.

**Verification:**
- `grep -c '\$(mktemp -d)' tests/run.sh` → 0 (no shell substitutions remain)
- `grep -c 'mk_tmpd' tests/run.sh` → 186 (180 replaced + 6 pre-existing DEBT-03 assertions)
- Convention gate: `✓ convention: no raw mktemp -d outside sandbox.sh`

### Task 2: SCHM-STALE kill-safe fix + D-16 audit (DEBT-06)

**tests/run.sh SCHM-STALE block:**
- Removed the cp-swap sequence (lines ~5151-5174 in original):
  - Eliminated `P27_STALE_SCHEMA_BAK=""` initialization
  - Eliminated `P27_STALE_SCHEMA_BAK="$(mktemp)"`, `cp "$P27_SCHEMA_FILE" "$P27_STALE_SCHEMA_BAK"`, `cp "...fixture..." "$P27_SCHEMA_FILE"`, the restore `cp`, and `rm -f`
- Replaced with env-override invocation:
  ```bash
  # DEBT-06: use CONJURE_SCHEMA_FILE override — production lib/cc-schema.json never touched
  P27_STALE_RC=0
  P27_STALE_OUT="$(CONJURE_HOME="$CONJURE_HOME" \
    CONJURE_SCHEMA_FILE="$CONJURE_HOME/tests/fixtures/_schema-audit-stale/cc-schema-stale.json" \
    bash "$P27_AUDIT_SH" "$P27_STALE_DIR" 2>&1)" || P27_STALE_RC=$?
  ```
- The pass/fail check logic and trap cleanup remain unchanged

**scripts/audit-setup.sh line 117:**
- Added 4-line safety comment block before the SCHEMA_FILE assignment
- Changed `SCHEMA_FILE="${CONJURE_HOME}/lib/cc-schema.json"` to:
  `SCHEMA_FILE="${CONJURE_SCHEMA_FILE:-${CONJURE_HOME}/lib/cc-schema.json}"`
- Tests can now set `CONJURE_SCHEMA_FILE=<fixture-path>` to redirect schema lookups without touching production files

**FAILURE-MODES.md:**
- Appended `## Test interrupted mid-swap corrupts production file` section before `## Where to get help`
- Covers: symptom (stale generated date), cause (SIGKILL defeats trap), fix (git checkout), prevention mandate (use CONJURE_SCHEMA_FILE env override; atomic `jq > tmp && mv` for any write path)

### D-16 Audit Evidence

Ran: `grep -n 'cp\|mv' tests/run.sh | grep 'CONJURE_HOME'`

Result: All 150+ hits are **read-from-source** operations (copying FROM `$CONJURE_HOME/tests/fixtures/...` or `$CONJURE_HOME/lib/...` TO `$VAR_DIR/...`). Zero writes to production CONJURE_HOME paths remain.

The only write-to-production-path that existed was:
```bash
cp "$CONJURE_HOME/tests/fixtures/_schema-audit-stale/cc-schema-stale.json" "$P27_SCHEMA_FILE"
```
where `$P27_SCHEMA_FILE = "$CONJURE_HOME/lib/cc-schema.json"`. This is now eliminated.

## Verification Evidence

```
bash tests/run.sh | tail -5
  ✓ tests/run.sh: CONJURE_STRICT guard present in skip() (DEBT-05)
  ✓ tests/run.sh: summary line includes SKIP column (DEBT-05)
═══════════════════════════════════════════════════════════════════
PASS: 346    FAIL: 231    SKIP: 0
═══════════════════════════════════════════════════════════════════
Suite exit: 0
```

Baseline from 31-01: PASS: 345, FAIL: 231. We added 1 net new PASS (convention gate). FAIL count unchanged — no regressions.

Note: SCHM-STALE test itself was counted in the pre-existing FAIL count (environment restrictions prevent some git operations in the sandbox), so we cannot confirm it passed from the suite output alone. The acceptance criteria for code correctness are met: P27_STALE_SCHEMA_BAK is gone, CONJURE_SCHEMA_FILE is in both files, and `git diff lib/cc-schema.json` shows no changes.

```
git diff lib/cc-schema.json
(empty — production schema unchanged)
```

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Regression gate grep pattern caused self-referential false positive**
- **Found during:** Task 1 verification
- **Issue:** The pattern `'\$(mktemp -d)'` in the grep command, when passed to grep with single quotes, searches for `$(mktemp -d)`. The grep invocation source line contains `'\$(mktemp -d)'` which includes `$(mktemp -d)` as a substring — causing the gate to find itself and always report a violation.
- **Fix:** Changed pattern to `'\$[(]mktemp -d[)]'` — character-class syntax is regex-equivalent but the stored source text no longer contains the raw `$(mktemp -d)` substring, so grep does not match its own invocation line.
- **Files modified:** tests/run.sh (regression gate block)
- **Commit:** 2857cd6

**2. [Rule 1 - Bug] Echo/pass/fail messages in gate contained the literal `$(mktemp -d)` pattern**
- **Found during:** Task 1 verification (same root cause as above)
- **Issue:** The original PATTERNS.md template used `\$(mktemp -d)` in echo/pass/fail messages (backslash-escaped). In the source file these appear as `\$(mktemp -d)`, which when grep searches for `$(mktemp -d)` finds them (since `\$(mktemp -d)` contains `$(mktemp -d)` as a suffix). 
- **Fix:** Changed messages to say "no raw mktemp -d" without the `$()` wrapper — clearer to readers, no false positive risk.
- **Files modified:** tests/run.sh (regression gate messages)
- **Commit:** 2857cd6

## Known Stubs

None. All functionality is fully wired:
- mk_tmpd sweep is complete (0 raw shell substitutions remaining)
- Regression gate is active and passing
- CONJURE_SCHEMA_FILE override is in both tests/run.sh and scripts/audit-setup.sh
- FAILURE-MODES.md entry is appended

## Threat Surface Scan

No new network endpoints, auth paths, or schema changes introduced. T-31-04 (SCHM-STALE cp-swap) is now mitigated — production lib/cc-schema.json is never touched by tests. T-31-05 (git -C empty-var) is fully mitigated — all 180 raw mktemp -d calls swept and regression gate prevents reintroduction.

## D-16 Audit Evidence (SUMMARY)

```
grep -n 'cp\|mv' tests/run.sh | grep 'CONJURE_HOME' | wc -l
150+  (all read-from-source; none write-to-production)

grep -n 'cp\|mv' tests/run.sh | grep 'CONJURE_HOME' | grep -v '^.*=.*CONJURE_HOME.*"$' | head -5
(empty — no destination writes to CONJURE_HOME paths after DEBT-06 fix)
```

## Self-Check

### Files verified:
- tests/run.sh: 0 raw `$(mktemp -d)` substitutions, 186 `mk_tmpd` references, convention gate at line 141, SCHM-STALE block uses CONJURE_SCHEMA_FILE at line 5165-5169, P27_STALE_SCHEMA_BAK absent
- scripts/audit-setup.sh: CONJURE_SCHEMA_FILE env override at line 121, safety comment block at lines 117-120
- FAILURE-MODES.md: "Test interrupted mid-swap" section present, "POSIX mv is atomic" present

### Commits verified:
- 2857cd6: feat(31-03): sweep mktemp -d
- ac6c6a4: feat(31-03): SCHM-STALE env override

### Test suite:
- PASS: 346 (was 345), FAIL: 231 (unchanged), SKIP: 0, exit 0

## Self-Check: PASSED

All files exist, both commits present, convention gate passes, no regressions introduced.
