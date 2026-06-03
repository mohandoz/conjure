---
phase: 26-sandbox-managed-settings-mdm
plan: "03"
subsystem: policy-audit
tags: [wave-3, audit, pol-05, exit-2, advisory, note, tempfile-pattern, posix-bash]
dependency_graph:
  requires:
    - "26-02"
  provides:
    - scripts/audit-setup.sh (Phase 26 POL-05 policy check block: 05a/05b/05c + advisory)
  affects:
    - tests/run.sh (POL-05a, POL-05b, POL-05c, POL-05-advisory now PASS; FAIL 4→0)
tech_stack:
  added: []
  patterns:
    - "err() for hard correctness bugs (POL-05a/b/c) — increments FAIL, triggers exit 2 at summary gate"
    - "note() for advisory findings (POL-05-advisory) — no counter, exit 0"
    - "tempfile pattern for POSIX-safe FAIL counter propagation out of while-loop subshell (POL-05b)"
    - "separate variable assignments for jq type reads (SC2155 compliance)"
    - "unconditional POL-05c (disableBypassPermissionsMode type check fires regardless of overlay state)"
key_files:
  created: []
  modified:
    - scripts/audit-setup.sh
decisions:
  - "POL-05c fires unconditionally — a boolean disableBypassPermissionsMode is always wrong regardless of compliance overlay presence"
  - "POL-05b uses a mktemp tempfile to collect while-loop errors, then drains via main-shell err() calls — avoids subshell FAIL counter loss"
  - "Advisory uses note() not warn() — follows Phase 25 lesson: warn() increments WARN and flips exit code to 1, breaking the advisory-only exit 0 guarantee"
  - "POL-05-advisory detection keys off REPLACE_WITH_ORG_UUID grep -qF only (RESEARCH.md Open Questions RESOLVED Q1: _conjure_unreviewed not emitted)"
  - "jq-absent case for POL-05a/b: note() advisory 'jq not found — policy checks skipped' (T-26-15 mitigation)"
metrics:
  duration: "~10 min"
  tasks_completed: 1
  files_created: 0
  files_modified: 1
  completed: "2026-06-03T00:00:00Z"
---

# Phase 26 Plan 03: Wave 3 — POL-05 policy audit checks in audit-setup.sh Summary

Wave 3 closes the Phase 26 audit loop: `scripts/audit-setup.sh` now verifies the artifacts emitted by Waves 1–2 are present and internally correct. Four checks are inserted in a new Phase 26 block between the existing Phase 25 plugin-reconciliation advisory section and the summary gate. Three hard-fail checks use `err()` (increments FAIL, triggers exit 2); one advisory check uses `note()` (no counter, exit 0). Full suite: 502 PASS / 0 FAIL.

## What Was Built

**Phase 26 POL-05 policy check block in scripts/audit-setup.sh (57 lines inserted)**

Insertion point: immediately after the `extraKnownMarketplaces` ref-without-sha advisory block, before the summary echo. The existing `note/ok/warn/err` function definitions, counter initializations, and the `[ "$FAIL" -gt 0 ] && exit 2` summary gate are unchanged.

**Overlay detection:**
```bash
_pol_regime="$(grep -oE '<!-- compliance:(hipaa|soc2|gdpr|pci) -->' CLAUDE.md 2>/dev/null \
  | sed 's/<!-- compliance://;s/ -->//' | head -1)"
```
Same marker as emitted by `compliance/<regime>/apply.sh`.

**POL-05c (unconditional — no overlay gate):**
Reads `jq -r '.permissions.disableBypassPermissionsMode | type'` and `jq -r '.permissions.disableBypassPermissionsMode // empty'` into separate variables (SC2155-safe). If type is `"boolean"`, calls `err()`. Fires even with no compliance overlay — a boolean value is always wrong.

**POL-05a (gated on `_pol_regime`):**
Reads `jq -r '.sandbox.enabled // false'`. If not `"true"`, calls `err()` with the specific regime in the message. Handles jq-absent case with `note()` advisory ("jq not found — policy checks skipped") to satisfy T-26-15.

**POL-05b (gated on `_pol_regime`) — tempfile pattern:**
Reads all `sandbox.filesystem.denyRead` entries and all `permissions.deny` entries into variables. Iterates denyRead paths in a while-loop (which runs in a subshell in POSIX bash). Instead of calling `err()` directly from the subshell (which would lose the FAIL counter increment), writes error messages to a `mktemp` tempfile. After the loop, if the tempfile is non-empty, drains it via `while IFS= read -r _msg; do err "$_msg"; done < "$_pol_b_errs"` in the main shell. Tempfile is removed with `rm -f`.

**POL-05-advisory (note(), exit 0):**
`grep -qF "REPLACE_WITH_ORG_UUID" conjure-policy/managed-settings.json`. If found, calls `note()` (not `warn()`). Does NOT check `._conjure_unreviewed` (per RESEARCH.md Q1 RESOLVED: emitted files carry no such marker).

## Verification Results

```
bash tests/run.sh 2>&1 | grep POL
  ✓ emit-policy merges sandbox block into settings.json (POL-01)
  ✓ emit-policy is idempotent: re-run produces identical settings.json (POL-01-idem)
  ✓ emit-policy mirrors denyRead paths into permissions.deny (POL-02)
  ✓ emit-policy produces managed-settings.json with correct keys and types (POL-03)
  ✓ disableBypassPermissionsMode is STRING 'disable' not boolean (POL-03-type)
  ✓ emit-policy produces macOS plist with correct XML (POL-04-macos)
  ✓ emit-policy produces Windows ps1 with correct path (no deprecated ProgramData) (POL-04-win)
  ✓ audit-setup fails when overlay active but sandbox.enabled missing (POL-05a)
  ✓ audit-setup fails when denyRead path has no mirrored permissions.deny Read() entry (POL-05b)
  ✓ audit-setup fails when disableBypassPermissionsMode is boolean (POL-05c)
  ✓ audit-setup issues advisory note (exit != 2) for unreviewed template with REPLACE_WITH_ORG_UUID (POL-05-advisory)
  ✓ emit-policy --dry-run prints mutations but writes no files (POL-dryrun)

PASS: 502    FAIL: 0
```

shellcheck clean: `shellcheck -S error -e SC2164,SC2044,SC2034,SC2155 scripts/audit-setup.sh` exits 0.

## Deviations from Plan

None — plan executed exactly as written.

## Known Stubs

None — all Phase 26 POL-05 audit checks are fully implemented. Phase 26 is complete.

## Threat Flags

None — all T-26-14 through T-26-17 mitigations from the plan's threat register are implemented:
- T-26-14: Accept — POL-05b uses original denyRead path for grep; known limitation documented in audit output
- T-26-15: `note()` advisory when jq absent ("jq not found — policy checks skipped") before POL-05a/b gate
- T-26-16: Accept — rogue overlay marker in CLAUDE.md at worst triggers false audit failure on a correctly-configured harness; requires repo access
- T-26-17: Advisory uses `note()` exclusively; grep-verified: new lines contain no `warn()` calls

## Commits

| Hash | Description |
|------|-------------|
| 087282f | feat(26-03): add Phase 26 POL-05 policy check block to audit-setup.sh |

## Self-Check: PASSED
