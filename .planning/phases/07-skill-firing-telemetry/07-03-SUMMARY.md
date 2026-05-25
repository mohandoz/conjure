---
phase: "07-skill-firing-telemetry"
plan: "03"
subsystem: "telemetry"
tags: [telemetry, testing, regression, bash, jsonl, hooks, nodejs]
dependency_graph:
  requires:
    - "07-01"
    - "07-02"
  provides:
    - telemetry-test-coverage
    - tlmy-01-tests
    - tlmy-02-tests
    - tlmy-03-tests
    - tlmy-04-tests
    - tlmy-05-tests
  affects:
    - tests/run.sh
tech_stack:
  added: []
  patterns:
    - test section insertion (matches cost estimator section structure exactly)
    - mock stdin pipe (printf | node hook) for hook integration testing
    - static egress grep pattern for CI no-network enforcement
    - sandbox_setup + trap + cleanup lifecycle (mirrors cost section)
key_files:
  created: []
  modified:
    - tests/run.sh
decisions:
  - "Static TLMY-03 and TLMY-05 assertions placed before sandbox block to avoid sandbox overhead for file checks"
  - "Sandbox reuses python-fastapi fixture (has .claude/ structure needed for audit-setup.sh)"
  - "SKILL_PAYLOAD shared between TLMY-01 DNT test and TLMY-02 write test for DRY stdin reuse"
  - "TLMY-04 retire-list render test uses SANDBOX_DIR from same sandbox block — no second sandbox needed"
metrics:
  duration_seconds: 180
  completed_date: "2026-05-25"
  tasks_completed: 1
  files_created: 0
  files_modified: 1
---

# Phase 7 Plan 3: Telemetry Test Section (Wave 3 — Proof Layer) Summary

**One-liner:** Extend tests/run.sh with 15 assertions covering TLMY-01 through TLMY-05 (hook opt-in gate, JSONL write, no-egress guarantee, retire-list CLI, TELEMETRY.md schema) — all 200 suite tests pass with FAIL: 0.

## What Was Built

One deliverable: the telemetry test section inserted into `tests/run.sh` after the cost section cleanup (line 439) and before the Summary block.

**`tests/run.sh`** (modified, 134 lines inserted) — New telemetry test section with 15 assertions:

**Static assertions (no sandbox):**
- TLMY-01: `templates/hooks-nodejs/skill-telemetry.mjs` file existence check
- TLMY-03: egress pattern grep on hook file (`curl|fetch|http|socket|XMLHttpRequest|require('https')|require('http')|import.*https|import.*http|net.Socket`) — expect zero matches
- TLMY-05: `TELEMETRY.md` file existence check; `session_id`, `project_cwd`, and `DO_NOT_TRACK` field presence
- TLMY-04 (static): `--retire-list` flag presence in `cli/conjure` source

**Sandbox-based assertions (sandbox_setup + trap lifecycle):**
- TLMY-01 (3 assertions): hook exits 0 when `CONJURE_TELEMETRY` unset; no JSONL written when unset; hook exits 0 with `DO_NOT_TRACK=1`; no JSONL written with `DO_NOT_TRACK=1`
- TLMY-02 (4 assertions): hook exits 0 when writing JSONL (`CONJURE_TELEMETRY=1` + mock `PreToolUse/Skill` stdin payload); JSONL file created; `jq empty` validates JSON; JSONL record contains `skill_invoke`, `test-skill`, `session_id`, `project_cwd` fields
- TLMY-04 (2 assertions): `CONJURE_RETIRE=1 bash audit-setup.sh` output contains `── Skill Retire-List ──` header; exit code ≤ 2

## Commits

| Task | Commit | Description |
|------|--------|-------------|
| Task 1 | f203170 | feat(07-03): add telemetry test section to tests/run.sh (TLMY-01 through TLMY-05) |

## Test Results

Full suite run after insertion:

```
PASS: 200    FAIL: 0
```

All 15 new telemetry assertions pass. No regressions in existing 185 assertions.

## Deviations from Plan

None — plan executed exactly as written. The section structure, sandbox lifecycle, assertion order, and insertion point all match the plan specification. The only minor ordering choice was placing static assertions (TLMY-01 file existence, TLMY-03, TLMY-05, TLMY-04 flag grep) before the sandbox block to reduce overhead for pure file/grep checks, which matches the plan's "TLMY-03: static — no sandbox needed" note.

## Threat Surface Scan

No new network endpoints, auth paths, file access patterns, or schema changes. The test section pipes test-controlled mock JSON to the hook via `printf` (trust boundary: test → hook stdin, noted in plan threat model T-07-09, T-07-10). `sandbox_setup` provides isolated `SANDBOX_DIR` with no leakage to real `HOME`. No threat flags beyond what was already in the plan threat model.

## Self-Check

Checking commit exists:
- `f203170` — `git log --oneline | grep f203170` — FOUND

Checking modified file:
- `tests/run.sh` — MODIFIED (committed f203170, 134 insertions)

Automated verification:
- `bash -n tests/run.sh` — PASSES (syntax valid)
- `grep -q "Telemetry tests" tests/run.sh` — PASSES (line 442)
- All 5 TLMY IDs (01-05) present — PASSES
- `EGRESS_PATTERNS` present — PASSES
- `DO_NOT_TRACK` present — PASSES
- `retire-list` present — PASSES
- `TELEMETRY.md` present — PASSES
- Telemetry section (line 442) < Summary section (line 578) — PASSES
- `bash tests/run.sh` — PASS: 200  FAIL: 0

## Self-Check: PASSED
