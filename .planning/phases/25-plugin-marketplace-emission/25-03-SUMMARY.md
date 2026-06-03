---
phase: "25"
plan: "03"
subsystem: plugin-emission
tags: [wave-2, audit-advisory, plugin-reconciliation, ref-without-sha, exit-0]
dependency_graph:
  requires:
    - 25-01 (scripts/emit-plugin.sh + cli dispatch)
    - 25-02 (--marketplace + extraKnownMarketplaces wiring)
  provides:
    - scripts/audit-setup.sh (plugin reconciliation + ref-without-sha advisory sections)
  affects:
    - tests/run.sh (PLUG-REC + PLUG-REFSHA fixture fixes)
tech_stack:
  added: []
  patterns:
    - Advisory-only audit section using note() (not warn()) to preserve exit 0 (D-12)
    - jq-based reconciliation check with 2>/dev/null + || true guards (T-25-12, T-25-13)
    - POSIX heredoc while-read loop for iterating jq newline-separated output (bash 3.2+)
    - Test fixture using full audit-clean base (go-gin copy) + overlay of specific drift condition
key_files:
  created: []
  modified:
    - scripts/audit-setup.sh
    - tests/run.sh
decisions:
  - "Used note() instead of warn() for both advisory sections: warn() increments WARN counter causing audit to exit 1, but D-12 and test requirements mandate exit 0. note() prints the advisory message (with a warning symbol prefix) without incrementing WARN — preserving exit 0."
  - "Fixed PLUG-REC and PLUG-REFSHA test fixtures: original minimal fixtures caused audit to exit 2 (missing .claude/, missing CLAUDE.md causing FAIL > 0). Switched to go-gin as audit-clean base with overlay of specific drift condition. This is the only fixture structure that produces exit 0 with the advisory note visible."
  - "Placed both new sections immediately before the summary block (after overlay drift check) — the natural position for advisory sections that do not affect the main audit flow."
metrics:
  duration: 10
  completed: "2026-06-03T03:17:53Z"
  tasks: 1
  files: 2
---

# Phase 25 Plan 03: Plugin Reconciliation + ref-without-sha Audit Advisory Sections Summary

Two advisory-only audit sections added to audit-setup.sh: plugin.json drift detection and extraKnownMarketplaces ref-without-sha check — both using note() to preserve exit 0 per D-12.

## What Was Built

**Task 1: Plugin reconciliation and ref-without-sha advisory sections in scripts/audit-setup.sh**

Added two new sections immediately before the summary block (after the org overlay drift check):

**Section 1 — Plugin reconciliation (D-12 / PLUG-04):**
- Fires when `.claude-plugin/plugin.json` exists and `jq` is available
- Reads `plugin.json .skills` path: if set and directory exists but has 0 SKILL.md — advisory note
- If skills path set but directory not found — advisory note
- If no skills path but `.claude/skills` has skills — advisory note
- Uses `note()` (not `warn()`) to preserve advisory-only exit 0 (D-12)
- Message includes "re-run: conjure publish-plugin" for PLUG-REC test grep

**Section 2 — extraKnownMarketplaces ref-without-sha check (D-12 / D-16):**
- Fires when `.claude/settings.json` exists and `jq` is available
- Iterates `extraKnownMarketplaces` entries: selects those with `ref` but no `sha`
- Uses POSIX-safe heredoc while-read loop (bash 3.2+ compatible)
- Each matching entry emits note advisory with "re-run: conjure publish-plugin --marketplace"
- Uses `note()` (not `warn()`) to preserve advisory-only exit 0

Both sections include `2>/dev/null || true` guards on jq calls (T-25-12, T-25-13 mitigations): malformed JSON produces empty output, section silently skips rather than crashing audit.

**tests/run.sh — PLUG-REC and PLUG-REFSHA fixture fixes:**

The original minimal fixtures (just a `.claude-plugin/plugin.json` or `.claude/settings.json`) caused audit to exit 2 due to missing `.claude/` directory and `CLAUDE.md`. Fixed by:
- PLUG-REC: copy go-gin fixture (complete audit-clean harness), remove all SKILL.md files from `.claude/skills/` (so skills dir exists but has 0 skills), add `.claude-plugin/plugin.json` with skills path
- PLUG-REFSHA: copy go-gin fixture, overlay `.claude/settings.json` with `extraKnownMarketplaces` entry having `ref` but no `sha` via jq merge

## Test Results

**Before:** 481 PASS / 2 FAIL (PLUG-REC and PLUG-REFSHA failing)
**After:** 483 PASS / 0 FAIL

All 13 PLUG-* tests pass:
- PLUG-01, PLUG-01-merge, PLUG-05, PLUG-04, PLUG-04-secret, PLUG-04-absent, PLUG-02, PLUG-02-reserved, PLUG-02-badpath, PLUG-03, PLUG-03-idem: unchanged (still PASS)
- PLUG-REC: PASS (advisory note with "publish-plugin" emitted, audit exits 0)
- PLUG-REFSHA: PASS (advisory note with "ref" emitted, audit exits 0)

Existing ADIT-* and fixture audit tests: no regression (all fixture audits remain green).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Plan specified warn() but exit 0 is required — used note() instead**
- **Found during:** Task 1 implementation analysis
- **Issue:** The plan action said "Both use warn() and ok() only — never err()". But `warn()` increments the WARN counter, and `[ "$WARN" -gt 0 ] && exit 1` at the end of audit-setup.sh means any call to `warn()` causes exit 1, not exit 0. The must_have truths and D-12 both mandate exit 0. The test checks `rc -eq 0` strictly.
- **Fix:** Used `note()` with warning symbol prefix for both advisory sections. `note()` prints the message without incrementing WARN, preserving exit 0. This correctly implements D-12: "advisory, exit 0 — does not break CI gate."
- **Files modified:** `scripts/audit-setup.sh`
- **Commit:** 6be13f8

**2. [Rule 1 - Bug] PLUG-REC and PLUG-REFSHA test fixtures were insufficient — caused audit to exit 2**
- **Found during:** Task 1 analysis and initial test run
- **Issue:** The original test fixtures created only `.claude-plugin/plugin.json` (PLUG-REC) or `.claude/settings.json` (PLUG-REFSHA). Audit exits 2 when `.claude/` is missing or when CLAUDE.md is absent (err() increments FAIL). Both original fixtures triggered exit 2 from unrelated audit checks, making the test's exit-0 condition impossible to satisfy.
- **Fix:** Changed both test fixtures to copy the `go-gin` fixture (complete audit-clean harness, exits 0 from all standard checks), then overlay the specific drift condition being tested:
  - PLUG-REC: Remove SKILL.md files from `.claude/skills/` + add `.claude-plugin/plugin.json` with skills path
  - PLUG-REFSHA: Merge `extraKnownMarketplaces` ref-without-sha entry into existing settings.json via jq
- **Files modified:** `tests/run.sh`
- **Commit:** 6be13f8

## Known Stubs

None — both advisory sections are fully implemented with no stubs.

## Threat Surface

No new threat surface beyond what was documented in the plan's threat model. Mitigations are implemented:

| Flag | File | Description |
|------|------|-------------|
| threat_flag: tampering | `scripts/audit-setup.sh` | jq parsing of user-supplied settings.json and plugin.json; mitigated by `2>/dev/null || true` guards — malformed JSON produces empty output, sections skip gracefully (T-25-12, T-25-13) |

## Self-Check: PASSED

- [x] `shellcheck -S error -e SC2164,SC2044,SC2034,SC2155 scripts/audit-setup.sh` exits 0
- [x] `grep -q "conjure publish-plugin" scripts/audit-setup.sh` exits 0
- [x] `grep -q "extraKnownMarketplaces" scripts/audit-setup.sh` exits 0
- [x] `bash tests/run.sh 2>&1 | grep "PLUG-REC"` shows PASS
- [x] `bash tests/run.sh 2>&1 | grep "PLUG-REFSHA"` shows PASS
- [x] Full suite: 483 PASS / 0 FAIL
- [x] Commit 6be13f8 exists (Task 1)
