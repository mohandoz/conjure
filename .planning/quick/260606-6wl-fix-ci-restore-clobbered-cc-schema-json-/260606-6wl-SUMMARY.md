---
phase: quick-260606-6wl
plan: 01
subsystem: testing
tags: [ci, cc-schema, audit, test-harness, template-lint, mktemp]

# Dependency graph
requires:
  - phase: "31 (test-harness hardening / deferred-debt merge)"
    provides: "audit SCHM-STALE check, no-raw-mktemp-d convention check, settings.json.tmpl node-hook lint"
provides:
  - "Authoritative lib/cc-schema.json restored (cc_version 2.1.161, generated 2026-06-03)"
  - "Convention-clean CONJURE_HOME symlink test (uses mk_tmpd)"
  - "Corrected settings.json.tmpl node-hook template lint"
  - "Green main CI: bash tests/run.sh ends FAIL: 0"
affects: [ci, audit, plugin-recommendation, schema-staleness]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Template-lint greps for JSON-escaped node-hook commands use grep -qF against the literal escaped form"

key-files:
  created: []
  modified:
    - lib/cc-schema.json
    - tests/run.sh

key-decisions:
  - "Restore lib/cc-schema.json from 19ed1cf rather than regenerate, since planning verified only 3 fields drifted"
  - "Use grep -qF (fixed string) for the node-hook template lint instead of BRE, avoiding backslash-escaping ambiguity in the JSON-escaped template form"

patterns-established:
  - "Audit-fixture EXPECT failures and PLUG-REC/PLUG-REFSHA cascades trace back to a single stale lib/cc-schema.json; treat schema staleness as the root cause first"

requirements-completed: [CI-GREEN]

# Metrics
duration: 5min
completed: 2026-06-06
---

# Phase quick-260606-6wl: Restore Clobbered cc-schema.json + Fix Two CI Test Assertions Summary

**Restored the authoritative lib/cc-schema.json (cc_version 2.1.161) clobbered by a checkpoint commit, and fixed a raw-mktemp convention violation plus a template-lint grep that never matched the JSON-escaped node-hook command — main now runs FAIL: 0.**

## Performance

- **Duration:** 5 min
- **Started:** 2026-06-06T02:00:26Z
- **Completed:** 2026-06-06T02:05:27Z
- **Tasks:** 3
- **Files modified:** 2

## Accomplishments
- Reverted the stale-fixture schema content (cc_version 2.1.100 / generated 2025-01-01 / "STALE FIXTURE") that checkpoint commit 62e988d had clobbered into production lib/cc-schema.json, restoring the authoritative snapshot from 19ed1cf. This cleared the SCHM-STALE-on-every-audit failure and its 9 fixture-audit EXPECT failures plus PLUG-REC/PLUG-REFSHA cascades.
- Replaced a raw `$(mktemp -d)` in the CONJURE_HOME symlink-resolution test with the blessed `mk_tmpd` helper, satisfying the suite's own no-raw-mktemp-d convention check.
- Fixed the settings.json.tmpl node-hook template lint, which never matched because the template correctly JSON-escapes the inner quotes; the grep now uses `-qF` against the literal escaped form.
- Full suite verified green: `bash tests/run.sh` → PASS: 595, FAIL: 0, SKIP: 2 (rc=0).

## Task Commits

Each task was committed atomically:

1. **Task 1: Restore authoritative lib/cc-schema.json** - `982f04c` (fix)
2. **Task 2: Fix raw mktemp -d and template-lint grep in tests/run.sh** - `bbc15b2` (fix)
3. **Task 3: Run full test suite to confirm green** - no code change (verification only; result captured at /tmp/conjure-6wl-suite.log)

**Plan metadata:** committed separately (docs: complete plan)

## Files Created/Modified
- `lib/cc-schema.json` - Restored authoritative CC schema snapshot (cc_version 2.1.161, generated 2026-06-03); byte-identical to `git show 19ed1cf:lib/cc-schema.json`.
- `tests/run.sh` - Line 6754 symlink test now uses `mk_tmpd`; line 257 template-lint grep now matches the escaped node-hook command via `grep -qF`.

## Decisions Made
- **grep -qF over BRE for the template lint:** The plan suggested `grep -q 'node \\"$CLAUDE_PROJECT_DIR\\"/.claude/hooks/'`, but empirical testing showed that pattern does NOT match (in a single-quoted BRE, `\\"` collapses and the literal single backslash in the template is not matched). I verified two working forms — `grep -qE 'node \\"\$CLAUDE_PROJECT_DIR\\"...'` and `grep -qF 'node \"$CLAUDE_PROJECT_DIR\"...'` — and chose `-qF` (fixed string) as the most robust and readable, since the template content is literal. The run.sh check now passes ("node hook commands present").
- **Restore from 19ed1cf rather than regenerate:** planning verified only 3 fields drifted, so a direct `git show` restore is exact and lower-risk than regenerating the schema.

## Deviations from Plan

### Adjusted grep pattern (within Task 2 scope)

**1. [Rule 1 - Bug] Corrected the template-lint grep pattern from the plan's literal suggestion**
- **Found during:** Task 2 (template-lint fix)
- **Issue:** The exact pattern proposed in the plan (`grep -q 'node \\"$CLAUDE_PROJECT_DIR\\"/.claude/hooks/'`) was verified to NOT match the template — both it and the original pattern returned NO MATCH. Shipping it would have left the test failing.
- **Fix:** Used `grep -qF 'node \"$CLAUDE_PROJECT_DIR\"/.claude/hooks/'` (fixed-string), which matches the literal JSON-escaped form in templates/settings.json.tmpl. Confirmed the run.sh check passes and no false-positive trips the no-raw-mktemp convention scan.
- **Files modified:** tests/run.sh (line 257)
- **Verification:** Simulated the check (CHECK PASSES), and full suite reports FAIL: 0.
- **Committed in:** `bbc15b2` (Task 2 commit)

---

**Total deviations:** 1 within-scope correction (Rule 1)
**Impact on plan:** The intended outcome (template-lint passes) is achieved; only the literal grep syntax differs from the plan's suggestion. No production code changed, no scope creep. The template itself was left unchanged, as instructed.

## Issues Encountered
- During suite review, one standalone `✗ manifest is not valid JSON: ...` line appears at suite output line 1040. This is the validator's own stderr diagnostic from the negative test `WS-01-manifest-invalid` (which intentionally feeds a malformed manifest), immediately followed by `✓ ... rejects malformed manifest with exit 2`. It is expected output, not a test failure — the suite reports FAIL: 0 and exits 0.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- main CI is green (FAIL: 0). All three diagnosed root causes (clobbered schema, raw mktemp -d, non-matching template lint) are resolved with the minimal intended changes.
- No blockers.

## Self-Check: PASSED
- `lib/cc-schema.json` exists, contains 2.1.161, byte-identical to 19ed1cf — FOUND
- `tests/run.sh` contains `_SYM_TMP="$(mk_tmpd)"` and the `-qF` template lint — FOUND
- Commit `982f04c` (Task 1) — FOUND
- Commit `bbc15b2` (Task 2) — FOUND

---
*Phase: quick-260606-6wl*
*Completed: 2026-06-06*
