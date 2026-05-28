---
phase: 17-drift-detection
plan: "02"
subsystem: drift-detection
tags: [bash, cli-wiring, regression-tests, porcelain, drift]
dependency_graph:
  requires: [17-01]
  provides: [cli/conjure cmd_check, tests/run.sh DRIFT section]
  affects: [cli/conjure, tests/run.sh]
tech_stack:
  added: []
  patterns: [cmd-dispatch-pattern, mktemp-sandbox-tests, trap-cleanup]
key_files:
  created: []
  modified:
    - cli/conjure
    - tests/run.sh
decisions:
  - "cmd_check passes CONJURE_PORCELAIN as env var and TARGET as positional arg to scripts/check.sh"
  - "No cmd_preflight call in cmd_check — read-only command needs no mutation guards"
  - "DRIFT tests use per-sandbox trap/reset pattern to prevent temp dir leaks on failure"
  - "Round-trip test (fresh init → check exit 0) validates full cmd_check→check.sh pipeline"
metrics:
  duration: "~1m"
  completed: "2026-05-26T03:21:00Z"
  tasks_completed: 2
  files_created: 0
  files_modified: 2
requirements:
  - DRIFT-01
  - DRIFT-02
---

# Phase 17 Plan 02: CLI Wiring + Regression Tests Summary

**One-liner:** Thin cmd_check dispatcher in cli/conjure calling scripts/check.sh via CONJURE_PORCELAIN env var, validated by 4 DRIFT regression tests covering exit codes and porcelain output format.

## What Was Built

**cli/conjure** — three targeted edits:
1. Usage line `conjure check [--porcelain] [target]` added to usage() heredoc
2. `cmd_check()` function inserted after `cmd_audit()` — parses `--porcelain` flag, passes `CONJURE_PORCELAIN` env var to `scripts/check.sh`, passes `$target` as positional arg
3. `check)` dispatch entry added between `update)` and `refresh-graph)` in main case block

**tests/run.sh** — DRIFT section appended before summary block:
- DRIFT-01a: fresh init → check exits 0 on fully-current harness
- DRIFT-01b: modified `.claude/settings.json` → exits 1 + `--porcelain` emits `M .claude/settings.json`
- DRIFT-01c: deleted `.claude/hooks/post-edit-format.mjs` → exits 1 + `--porcelain` emits `R .claude/hooks/post-edit-format.mjs`
- DRIFT-02: `--porcelain` exits 0 on current harness

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Wire cmd_check into cli/conjure | 85501be | cli/conjure (modified) |
| 2 | Add DRIFT regression tests to tests/run.sh | ee02a10 | tests/run.sh (modified) |

## Acceptance Criteria Verification

| # | Criterion | Result |
|---|-----------|--------|
| 1 | cli/conjure contains cmd_check() function | PASS |
| 2 | Dispatch case contains `check) shift; cmd_check "$@" ;;` | PASS |
| 3 | usage() contains `conjure check [--porcelain] [target]` | PASS |
| 4 | cmd_check passes CONJURE_PORCELAIN env var | PASS |
| 5 | cmd_check passes TARGET as positional $1 to check.sh | PASS |
| 6 | shellcheck -S error -e SC2155 cli/conjure exits 0 | PASS |
| 7 | `cli/conjure help` includes "check" subcommand | PASS |
| 8 | DRIFT section header in tests/run.sh | PASS |
| 9 | All 6 DRIFT assertions pass | PASS |
| 10 | bash tests/run.sh exits 0 (PASS: 283 FAIL: 0) | PASS |
| 11 | No temp dirs leaked (each sandbox uses mktemp + trap reset) | PASS |
| 12 | shellcheck passes on scripts/check.sh | PASS |

## Deviations from Plan

None — plan executed exactly as written.

## Threat Model Coverage

| Threat ID | Status |
|-----------|--------|
| T-17-04: CLI check dispatch spoofing | Accepted — dispatches only to scripts/check.sh; no privilege escalation |
| T-17-05: tests/run.sh DRIFT section repudiation | Accepted — local test framework; no audit log needed |
| T-17-SC: package installs | N/A — zero package installs |

## Known Stubs

None — cmd_check is a complete implementation. The full round-trip (init → check → exit 0) is validated in the regression test suite.

## Self-Check: PASSED

- [x] cli/conjure contains cmd_check: `grep -q 'cmd_check' cli/conjure`
- [x] cli/conjure contains check) dispatch: `grep -q 'check)' cli/conjure`
- [x] tests/run.sh DRIFT section present: `grep -q 'Drift detection tests' tests/run.sh`
- [x] Commit 85501be exists: `git log --oneline | grep 85501be`
- [x] Commit ee02a10 exists: `git log --oneline | grep ee02a10`
- [x] bash tests/run.sh: PASS: 283 FAIL: 0
