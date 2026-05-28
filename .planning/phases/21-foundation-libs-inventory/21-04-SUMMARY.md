---
phase: 21-foundation-libs-inventory
plan: "04"
subsystem: foundation-libs
tags:
  - audit-setup
  - caps
  - call-site-change
  - wave-3
  - adopt-03
  - sc-5
dependency_graph:
  requires:
    - 21-02 (lib/caps.sh created with CLAUDE_MD_CAP/SKILL_MD_CAP/AGENT_MD_CAP)
    - 21-03 (lib/snapshot.sh, lib/inventory.sh, brownfield-simple fixture complete)
  provides:
    - scripts/audit-setup.sh (call-site updated to source lib/caps.sh and use cap variables)
  affects:
    - tests/run.sh (SC-5 assertion now passes — no code changes needed)
tech_stack:
  added: []
  patterns:
    - CONJURE_HOME resolution guard (": ${CONJURE_HOME:=...}") before source call, same pattern as lines 183/249 already in file
    - "# shellcheck source=lib/caps.sh" annotation enables shellcheck -x to follow sourced file
    - cap variables from lib/caps.sh replace literals 100/200/80 throughout audit-setup.sh cap comparisons
key_files:
  created: []
  modified:
    - scripts/audit-setup.sh (CONJURE_HOME resolution + source lib/caps.sh + 3 literal-to-variable replacements)
decisions:
  - "Call-site change only — behavior is identical; CLAUDE_MD_CAP=100, SKILL_MD_CAP=200, AGENT_MD_CAP=80 in lib/caps.sh match the literals they replace exactly"
  - "CONJURE_HOME set at top of file before source call; later lazy-sets at lines 183/249 become harmless no-ops (idempotent := guard)"
  - "shellcheck -S error passes; SC1091 info (not following sourced file) removed by # shellcheck source= annotation + -x flag"
metrics:
  duration: ~8 minutes
  completed: "2026-05-28"
  tasks_completed: 2
  tasks_total: 2
  files_created: 0
  files_modified: 1
---

# Phase 21 Plan 04: audit-setup.sh call-site cap variable extraction Summary

Extracted hardcoded cap literals (100/200/80) from scripts/audit-setup.sh to use CLAUDE_MD_CAP/SKILL_MD_CAP/AGENT_MD_CAP variables sourced from lib/caps.sh — completing Phase 21's integration gate with all four libs in place and all test assertions green.

## What Was Built

### Task 1: Extract cap literals from audit-setup.sh to use lib/caps.sh (commit 5c36550)

**scripts/audit-setup.sh** — Three targeted changes (call-site only; behavior unchanged):

**CHANGE 1 — Add CONJURE_HOME resolution + source lib/caps.sh at top of file:**
```bash
: "${CONJURE_HOME:="$(cd "$(dirname "$0")/.." && pwd)"}"
# shellcheck source=lib/caps.sh
source "${CONJURE_HOME}/lib/caps.sh"
```
Inserted after `set -uo pipefail`, before the TARGET/cd lines. Ensures CONJURE_HOME is set before
caps.sh is sourced regardless of how audit-setup.sh is called. The `:=` guard makes subsequent
lazy-sets at lines 183/249 harmless no-ops.

**CHANGE 2 — Replace literal 100/200 in CLAUDE.md size check:**
- `"$LINES" -le 100` → `"$LINES" -le "${CLAUDE_MD_CAP}"`
- `"$LINES" -le 200` → `"$LINES" -le "${SKILL_MD_CAP}"`
- Display string `≤100` → `≤${CLAUDE_MD_CAP}`

**CHANGE 3 — Replace literal 200 in skill size check and literal 80 in agent size check:**
- `"$LINES" -gt 200` → `"$LINES" -gt "${SKILL_MD_CAP}"`
- `"$LINES" -gt 80` → `"$LINES" -gt "${AGENT_MD_CAP}"`

### Task 2: Checkpoint auto-approved (all Phase 21 assertions green)

Full test suite run confirmed all acceptance criteria:
- `shellcheck -S error` passes (0 errors; SC1091 info removed by annotation)
- `grep -v '^#' scripts/audit-setup.sh | grep -c 'CLAUDE_MD_CAP'` returns 1 (variable used)
- `grep -v '^#' scripts/audit-setup.sh | grep -c '\[ "$LINES" -le 100'` returns 0 (literal removed)
- `grep -v '^#' scripts/audit-setup.sh | grep -c '\[ "$LINES" -gt 200'` returns 0 (literal removed)
- `grep -v '^#' scripts/audit-setup.sh | grep -c '\[ "$LINES" -gt 80'` returns 0 (literal removed)
- `bash scripts/audit-setup.sh tests/fixtures/brownfield-simple` exits 0 (behavior unchanged)
- `bash tests/run.sh` exits 0 with PASS: 355, FAIL: 0

## Verification Results

```
shellcheck -S error -e SC2164,SC2044,SC2034,SC2155 scripts/audit-setup.sh
→ exits 0 (no errors)

bash scripts/audit-setup.sh tests/fixtures/brownfield-simple
→ exits 0 — PASS: 14  WARN: 0  FAIL: 0

bash tests/run.sh 2>&1 | tail -3
→ PASS: 355    FAIL: 0
→ rc=0

Phase 21 assertions (all ✓):
  SC-5: caps.sh CLAUDE_MD_CAP=100, SKILL_MD_CAP=200, AGENT_MD_CAP=80
  SC-1: log.sh DRY_RUN tests (3 assertions)
  SC-2: snapshot.sh DRY_RUN + live tests
  INV-01..INV-04: inventory classify/emit/symlink/cap/size_cap tests (14 assertions)
  SAFE-03: mutate_archive DRY_RUN + live + abort tests
  SC-5 (audit): audit-setup.sh uses CLAUDE_MD_CAP variable
  SC-4: adopt-manifest.schema.json valid JSON with 6-value classification enum
  CR-7: inventory_emit_manifest on 510-file fixture completed in 5-6s (< 30s)

jq empty adopt-manifest.schema.json && echo "schema JSON valid"
→ schema JSON valid (exits 0)

Pre-existing tests: 0 regressions (355 pass vs 354 pass before Plan 04)
```

## Deviations from Plan

None — plan executed exactly as written. The three targeted edits to audit-setup.sh were mechanical and went in cleanly on first attempt. No behavior changes, no regressions.

## Known Stubs

None — all deliverables are fully wired with real behavior. The call-site change is complete; cap variables flow from lib/caps.sh to audit-setup.sh, adopt.sh (Phase 22), and inventory.sh without inconsistencies.

## Threat Flags

No new threat surface. T-21-12 (CONJURE_HOME path injection) mitigated as designed: `: "${CONJURE_HOME:=...}"` only sets if unset; fallback uses `dirname "$0"` which is script-relative, not user-controllable. T-21-13 (behavior change) accepted: cap values in lib/caps.sh are identical to replaced literals.

## Self-Check: PASSED

All modified files found:
- `scripts/audit-setup.sh` — FOUND

Commits verified:
- `5c36550`: feat(21-04): source lib/caps.sh in audit-setup.sh; replace cap literals with variables — FOUND
