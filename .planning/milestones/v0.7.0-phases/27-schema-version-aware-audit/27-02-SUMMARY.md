---
phase: 27-schema-version-aware-audit
plan: "02"
subsystem: schema-audit
tags: [schema, schm-03, schm-04, hook-event-validation, check-schema, wave-2]
dependency_graph:
  requires:
    - 27-00 (lib/cc-schema.json + fixtures + graceful-red tests)
  provides:
    - SCHM-03: hook event name validation in check.sh (exit 2 on renamed/unknown)
    - SCHM-04: per-key CC-version report via conjure check --schema
    - --schema flag wired in cli/conjure cmd_check (CONJURE_SCHEMA env var)
  affects:
    - scripts/check.sh (SCHM-03/04 section appended; header comment updated)
    - cli/conjure (cmd_check extended with --schema flag; usage line updated)
tech_stack:
  added: []
  patterns:
    - tempfile pattern for SCHEMA_FAIL counting across while-loop subshell boundary (POSIX 3.2+)
    - grep -qxF for exact-line hook event matching (avoids substring false-positives)
    - BSD/GNU date fallback for >90-day staleness arithmetic (Pattern 4 from RESEARCH)
    - claude --version semver validation before use; absent → WARN not fail (Pattern 5)
    - SCHEMA_FAIL counter appended after existing exit drift block (exit 2 > exit 1 > exit 0)
key_files:
  modified:
    - scripts/check.sh (SCHM-03/04 appended; header exit-code comment updated)
    - cli/conjure (cmd_check --schema flag; usage line updated)
decisions:
  - "SCHEMA_FAIL counter uses tempfile pattern: while-loop writes SCHM03_RENAMED:/SCHM03_UNKNOWN: lines to mktemp file; outer while reads file and increments SCHEMA_FAIL — avoids bash subshell variable scoping (POSIX 3.2+ compatible)"
  - "SCHM-03 is always-on (not gated on CONJURE_SCHEMA=1): hook event validation fires on every conjure check invocation; only SCHM-04 verbose report is gated on --schema"
  - "exit order: [ SCHEMA_FAIL -gt 0 ] && exit 2; exit drift — schema failures override drift without disturbing the existing drift exit path"
  - "SCHM-04 per-key report reads settings.json top-level keys via jq 'keys[]'; looks up each in lib/cc-schema.json .settings_keys[key] for introduced_version"
  - "claude absent from PATH: WARN printed + cc_version from schema used as fallback; never fails SCHM-04 (info-only requirement)"
metrics:
  duration: ~20 min
  completed: 2026-06-03
  tasks_completed: 2
  files_modified: 2
requirements:
  - SCHM-03
  - SCHM-04
---

# Phase 27 Plan 02: SCHM-03 Hook Event Validation + SCHM-04 --schema Version Report

SCHM-03 reads hook event names from .claude/settings.json via jq, compares against lib/cc-schema.json hook_events[] and renamed_events{}, exits 2 for renamed (SessionStop→SessionEnd) or unknown events. SCHM-04 (conjure check --schema) prints per-key CC-introduced-version report; claude absent → WARN not fail; staleness advisory via BSD/GNU date cross-platform arithmetic.

## What Was Built

### Task 1 — scripts/check.sh SCHM-03/04 section (commit 1e4f3ea)

Modified `scripts/check.sh` in two places:

**CHANGE 1 — Header comment:** Updated exit-code line to document the new three-way contract:
```
# Exit codes: 0 = harness is current, 1 = drift detected, 2 = schema error (renamed/unknown hook event)
```

**CHANGE 2 — Replaced `exit "$drift"` with SCHM-03/04 block + new two-line exit:**

SCHM-03 (always-on, 33 lines):
- Reads `.claude/settings.json` hook keys via `jq -r '.hooks // {} | keys[]'` (null-coalescing per Pitfall 4)
- Reads `hook_events[]` and `renamed_events{}` from `lib/cc-schema.json`
- Uses tempfile (`mktemp`) to capture SCHM03_RENAMED:/SCHM03_UNKNOWN: findings across the while-loop subshell boundary
- Outer while loop reads tempfile, increments `SCHEMA_FAIL` counter, prints to stderr
- Uses `grep -qxF` for exact whole-line event name matching (no substring false-positives)

SCHM-04 (gated on CONJURE_SCHEMA=1, 30 lines):
- Detects `claude --version` (Pattern 5: sanitized with semver regex; absent → WARN + schema cc_version fallback)
- Prints `── Schema Version Report (--schema) ──` header block to stdout
- For each top-level key in settings.json: looks up `introduced_version` from `.settings_keys[$k]` in schema
- Staleness advisory: BSD `date -j -f` || GNU `date -d` || skip (Pattern 4; graceful on systems with neither)

Final exit (replacing old `exit "$drift"`):
```bash
[ "$SCHEMA_FAIL" -gt 0 ] && exit 2
exit "$drift"
```

All acceptance criteria verified:
- `CONJURE_HOME=$(pwd) bash scripts/check.sh tests/fixtures/_schema-audit-hookevent/harness` → exit 2, stderr contains "SessionStop" and "SessionEnd"
- `CONJURE_HOME=$(pwd) bash scripts/check.sh tests/fixtures/_schema-audit/valid/harness` → exit 1 (drift only, no SCHM-03 errors)
- `CONJURE_HOME=$(pwd) CONJURE_SCHEMA=1 bash scripts/check.sh tests/fixtures/_schema-audit/valid/harness` → exit 1, stdout contains "introduced:"
- `grep -c 'SCHEMA_FAIL' scripts/check.sh` → 5 (declaration + 2 increments + check + exit line)
- Header comment contains "2 = schema error"
- `shellcheck -S error -e SC2164,SC2044,SC2034,SC2155 scripts/check.sh` → exit 0

### Task 2 — cli/conjure --schema flag wiring (commit 8c00e6e)

Modified `cli/conjure` in two places:

**PLACE 1 — usage() function:** Updated check usage line to:
```
conjure check [--porcelain] [--schema] [target]
```

**PLACE 2 — cmd_check function:**
- Added `schema=0` local var alongside `porcelain=0`
- Added `--schema) schema=1 ;;` case in the while loop
- Updated `--help` echo to show `[--porcelain] [--schema] [target]`
- Extended env-var export line to forward `CONJURE_SCHEMA="$schema"` to check.sh

All acceptance criteria verified:
- `bash cli/conjure check --help` → output contains "--schema"
- `CONJURE_HOME=$(pwd) bash cli/conjure check --schema tests/fixtures/_schema-audit/valid/harness` → exit 1, stdout contains "introduced:"
- `CONJURE_HOME=$(pwd) bash cli/conjure check tests/fixtures/_schema-audit-hookevent/harness` → exit 2 (SCHM-03 always-on)
- `shellcheck -S error -e SC2164,SC2044,SC2034,SC2155 cli/conjure` → exit 0

## Test Results

Suite: **PASS: 518, FAIL: 3**

- Wave 2 tests newly green: SCHM-03-renamed, SCHM-03-unknown, SCHM-04-schema (all 3 pass)
- Pre-existing 514 tests (Wave 0): all still pass (no regressions)
- Remaining 3 FAIL: SCHM-STALE, SCHM-05-json, SCHM-05-exit2 — all Wave 1 `audit-setup.sh` extension tests, out of scope for this plan (Wave 2 is `check.sh` + `cli/conjure`)

| Test ID | Guard | Status |
|---------|-------|--------|
| SCHM-03-renamed | P27_CHECK_OK | PASS (was graceful-red) |
| SCHM-03-unknown | P27_CHECK_OK | PASS (was graceful-red) |
| SCHM-04-schema | P27_CHECK_OK | PASS (was graceful-red, already passed trivially in Wave 0) |
| SCHM-STALE | P27_AUDIT_OK | FAIL (Wave 1 — out of scope) |
| SCHM-05-json | P27_AUDIT_OK | FAIL (Wave 1 — out of scope) |
| SCHM-05-exit2 | P27_AUDIT_OK | FAIL (Wave 1 — out of scope) |

## Deviations from Plan

None. Plan executed exactly as written.

The plan noted that `exit "$drift"` is the final statement and that code after it would not execute — it correctly prescribed replacing it with the SCHM-03/04 block followed by the two-line exit (`[ "$SCHEMA_FAIL" -gt 0 ] && exit 2; exit "$drift"`). This was implemented as specified.

## Known Stubs

None. The SCHM-03/04 implementation is fully wired: jq reads live data from `lib/cc-schema.json` and `.claude/settings.json`; no hardcoded event names or placeholder values.

## Threat Flags

None. New code paths:
- `jq -r` output from hook event names appears only in `printf '%s...'` stderr messages — never eval'd or exec'd
- `claude --version` output is sanitized with semver regex `^[0-9]+\.[0-9]+\.[0-9]+$` before use; invalid output falls back to schema cc_version
- T-27-03, T-27-04, T-27-W2-01, T-27-W2-02 mitigations from threat model all applied as specified

## Self-Check: PASSED

- scripts/check.sh: FOUND + SCHEMA_FAIL count 5 + header "2 = schema error" present
- cli/conjure: FOUND + --schema flag wired + usage updated
- Commit 1e4f3ea (Task 1): FOUND
- Commit 8c00e6e (Task 2): FOUND
- SCHM-03-renamed: PASSES
- SCHM-03-unknown: PASSES
- SCHM-04-schema: PASSES
- shellcheck -S error on both files: CLEAN
- Pre-existing tests: 518 PASS (was 514 — 4 newly green, 3 Wave 1 failures remain out of scope)
