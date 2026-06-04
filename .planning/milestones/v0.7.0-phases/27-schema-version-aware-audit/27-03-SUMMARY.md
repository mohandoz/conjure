---
phase: 27-schema-version-aware-audit
plan: "03"
subsystem: audit
tags: [bash, jq, json, schm-05, machine-readable, phase29-contract]

requires:
  - phase: 27-01
    provides: SCHM-01 and SCHM-02 audit checks in audit-setup.sh whose results feed the JSON accumulator
  - phase: 27-02
    provides: SCHM-03/04 in check.sh (no conflict; different file)
provides:
  - conjure audit --json emitting a single JSON object {schema_version, status, checks, summary} to stdout
  - SCHM-05 machine-readable output contract for Phase 29 workspace audit aggregation
  - SCHM-STALE >90-day cc-schema.json staleness advisory in JSON checks[] array
  - human() routing function suppressing all human text to stderr in JSON mode
  - json_check() helper appending JSONL check records (no-op in normal mode)
  - --json flag wired in cli/conjure cmd_audit via CONJURE_JSON env var
affects: [phase-29-workspace-audit, conjure-audit-consumers]

tech-stack:
  added: []
  patterns:
    - "JSONL tempfile accumulator: mktemp + jq -cn --slurpfile + EXIT trap (mirrors lib/inventory.sh emit pattern)"
    - "human() router: routes all human-readable output to stderr in JSON mode, stdout in normal mode"
    - "json_check() no-op guard: [ $JSON_MODE != 1 ] && return 0 keeps normal mode unaffected"
    - "Phase 29 JSON contract: schema_version=1, stable check IDs (SCHM-01-skill-field, SCHM-01-skill-unknown, SCHM-02-disablebypass, SCHM-STALE)"

key-files:
  created: []
  modified:
    - scripts/audit-setup.sh
    - cli/conjure

key-decisions:
  - "human() helper pattern: single function routes all output to stdout or stderr based on JSON_MODE; avoids scattered conditional logic across ~20 echo/printf sites"
  - "cmd_preflight routed to stderr in JSON mode: prevents preflight text from polluting stdout JSON stream"
  - "Exit codes preserved unchanged in JSON mode: existing [ FAIL -gt 0 ] && exit 2 and [ WARN -gt 0 ] && exit 1 gates run after JSON emission, same as non-JSON mode"
  - "CHECKS_JSONL tempfile + EXIT trap: POSIX-compatible accumulation without associative arrays; jq --slurpfile wraps each JSON line into array"
  - "SCHM-STALE placed after SCHM-02 block and before summary: consistent placement within schema checks section"

patterns-established:
  - "JSON contract v1: schema_version string not int, stable check IDs, checks[] flat array, summary {pass,warn,fail} ints"
  - "Backward compatibility: CONJURE_JSON defaults to 0; all normal-mode behavior unchanged"

requirements-completed: [SCHM-05]

duration: 15min
completed: 2026-06-03
---

# Phase 27 Plan 03: Schema-Version-Aware Audit Summary

**conjure audit --json emits a stable {schema_version,status,checks,summary} JSON contract to stdout via JSONL tempfile accumulator and human() stderr routing — Phase 29 workspace aggregation ready**

## Performance

- **Duration:** ~15 min
- **Started:** 2026-06-03T13:00:00Z
- **Completed:** 2026-06-03T13:11:20Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- SCHM-05 machine-readable JSON output: single object to stdout, all human text to stderr, exit codes preserved
- SCHM-STALE staleness advisory: >90-day cc-schema.json generates warn entry in checks[] array
- CLI --json flag wired: cmd_audit passes CONJURE_JSON=1 to audit-setup.sh; preflight output routed to stderr
- Full test suite: PASS=521, FAIL=0 — all SCHM-01..05 + SCHM-STALE + SCHM-SCHEMA green

## Task Commits

1. **Task 1: Add CONJURE_JSON mode and json_check() to audit-setup.sh** - `6a7cee0` (feat)
2. **Task 2: Wire --json flag in cli/conjure cmd_audit** - `b30ba06` (feat)

**Plan metadata:** (docs commit pending)

## Files Created/Modified
- `scripts/audit-setup.sh` - JSON mode: human(), json_check(), CHECKS_JSONL accumulator, SCHM-STALE, JSON emission block, cost/retire stderr routing
- `cli/conjure` - cmd_audit: do_json=0, --json case, CONJURE_JSON env forward, preflight stderr redirect in JSON mode

## Decisions Made
- human() helper over scattered `[ "$JSON_MODE" = "1" ] && ... >&2` conditionals: single routing point is cleaner and less error-prone across the ~20 human-text output sites
- Preflight output redirected to stderr via `>/dev/stderr 2>&1` in JSON mode: preflight text is human-readable and must not contaminate the JSON stdout stream
- Exit code gates remain AFTER the JSON emission block: `[ "$FAIL" -gt 0 ] && exit 2` runs last, same as non-JSON mode — T-27-05 threat (CI gate bypass) mitigated
- SCHM-STALE placed as a freestanding check after SCHM-02 block and before the Summary section — keeps schema checks colocated

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Phase 27 complete: SCHM-01..05 all implemented and green across all test cases
- `conjure audit --json` output is the stable Phase 29 aggregation contract
- Phase 29 `conjure workspace audit` can call `conjure audit --json` per repo and parse stdout via `jq -s '.'`
- Schema check IDs (SCHM-01-skill-field, SCHM-01-skill-unknown, SCHM-02-disablebypass, SCHM-STALE) are stable and additive-only going forward

---
*Phase: 27-schema-version-aware-audit*
*Completed: 2026-06-03*
