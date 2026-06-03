---
phase: 28
plan: "02"
subsystem: eval-worker
tags: [eval, promptfoo, github-actions, emit-workflow, EVAL-03, POSIX-bash]
dependency_graph:
  requires:
    - 28-01 (scripts/eval.sh with PROMPTFOO_VERSION + FAIL_ON_THRESHOLD constants)
  provides:
    - scripts/eval.sh cmd_eval_emit_workflow (EVAL-03 --emit-workflow implementation)
    - .github/workflows/conjure-eval.yml (emitted into target repo via mutate_write_file)
  affects:
    - tests/run.sh EVAL-03-emit test (now GREEN)
tech_stack:
  added: []
  patterns:
    - per-line printf YAML construction with single-quote-protected ${{ }} expressions (T-28-03b)
    - mutate_write_file byte-exact file copy (Pitfall 6: no trailing-newline strip)
    - mutate_mkdir for .github/workflows/ directory creation (backup-before-mutate)
    - FAIL_ON_THRESHOLD=80 integer constant (D-28-THRESH: maps CONTEXT.md 0.8 → action integer 80)
    - repeat:3 / repeat-min-pass:2 as GitHub Action inputs (SC reconciliation)
key_files:
  created: []
  modified:
    - scripts/eval.sh
decisions:
  - "fail-on-threshold: 80 (integer) — CONTEXT.md 0.8 maps to integer 80 in promptfoo-action per D-28-THRESH; emitting 0.8 would make the gate never fail (Pitfall 9)"
  - "repeat:3 + repeat-min-pass:2 in GitHub Action with: block — not in promptfooconfig.yaml assertion keys (SC reconciliation from RESEARCH)"
  - "Single-quote wrapping for all ${{ }} GitHub Actions expressions — bash does not expand inside single quotes; eliminates T-28-03b tampering threat"
  - "mutate_write_file (byte-exact cp) over mutate_write($(cat)) — preserves trailing newline per Pitfall 6"
  - "Manual-UAT enforcement obligation printed at invocation time — enforcement-not-disposition cannot be automated (requires live API); surfaced visibly, not buried in docs"
metrics:
  duration_minutes: 15
  completed_date: "2026-06-03T20:00:00Z"
  tasks_completed: 1
  files_created: 0
  files_modified: 1
---

# Phase 28 Plan 02: conjure eval --emit-workflow (EVAL-03) Summary

Wave 2 implementation: `cmd_eval_emit_workflow` in scripts/eval.sh emitting a correctly-structured GitHub Actions PR-gate workflow using promptfoo/promptfoo-action@v1, with fail-on-threshold integer 80 (per D-28-THRESH), repeat:3/repeat-min-pass:2 action inputs, and path filters on .claude/** and CLAUDE.md.

## What Was Built

### Task 1: scripts/eval.sh — cmd_eval_emit_workflow (EVAL-03)

Replaced the Wave 1 stub (`echo "Use conjure eval --emit-workflow (Wave 2)" >&2; exit 2`) with a full implementation.

**Function: cmd_eval_emit_workflow `<target_dir>`**

1. Validates `target_dir` exists
2. `mutate_mkdir "$target_dir/.github/workflows"` — creates directory (backup-before-mutate)
3. Builds workflow YAML into a tempfile using `printf '%s\n'` per line — no heredoc variable expansion (Pitfall 3 / T-28-03b: all `${{ }}` GitHub Actions expressions are inside single-quoted strings so bash does NOT expand them)
4. `mutate_write_file` to `"$wf_dir/conjure-eval.yml"` — byte-exact copy (Pitfall 6: preserves trailing newline)
5. Prints three output lines:
   - Confirmation: `▸ conjure eval --emit-workflow: wrote .github/workflows/conjure-eval.yml`
   - Verification note: how to activate the gate (repo secrets + PR trigger)
   - Manual-UAT obligation: `break a hook binary and confirm the eval suite FAILS (requires live promptfoo + ANTHROPIC_API_KEY)`

**Emitted workflow structure:**
- `name: Conjure Eval`
- `on: pull_request` with `paths: ['.claude/**', 'CLAUDE.md']`
- `jobs.eval` on `ubuntu-latest` with `contents:read / pull-requests:write` permissions
- `steps:` actions/checkout@v4, actions/cache@v4 (with config-hash keying to avoid repeat-caching Pitfall 8), promptfoo/promptfoo-action@v1
- `with:` block: `fail-on-threshold: 80` (integer — D-28-THRESH; not 0.8 float), `repeat: 3`, `repeat-min-pass: 2`, `promptfoo-version: '0.121.14'` (PROMPTFOO_VERSION constant), `cache-path: ~/.cache/promptfoo`, `github-token: ${{ secrets.GITHUB_TOKEN }}`
- `env: ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}` (via env: block, not action input)

**Dispatch update:** `--emit-workflow)` case now calls `cmd_eval_emit_workflow "$TARGET"` (was `echo + exit 2`).

## Test Results

Wave 2 results: PASS: 532, FAIL: 4 (up from Wave 1's PASS: 531, FAIL: 5).

New PASSes from Wave 2 (1 gained):
- EVAL-03-emit: PASS (emit-workflow creates conjure-eval.yml with correct shape)

Remaining failures (Wave 3 stubs — expected):
- EVAL-04-porcelain: Wave 3 (audit --budget --porcelain JSON)
- EVAL-05-gap: Wave 3 (audit coverage diff)
- EVAL-05-noconfig: Wave 3 (audit no eval config advisory)

## Deviations from Plan

None — plan executed exactly as written.

## Known Stubs

None — cmd_eval_emit_workflow is fully implemented. Wave 3 (28-03) implements --budget (EVAL-04) and EVAL-05 coverage report.

## Threat Flags

None found — cmd_eval_emit_workflow writes a static workflow YAML to the user's target repo. All STRIDE threats from the plan's threat model are mitigated:

- T-28-03a (wrong fail-on-threshold value): `FAIL_ON_THRESHOLD=80` constant + acceptance criteria grep assert both `fail-on-threshold: 80` AND `grep -qv "fail-on-threshold: 0\."` — MITIGATED
- T-28-03b (${{ }} bash expansion): single-quote wrapping of all GitHub Actions expressions — MITIGATED
- T-28-03c (enforcement-not-disposition silent pass): structural half automated (EVAL-03-emit asserts correct YAML); behavioral half documented as explicit Manual-UAT obligation printed at invocation time — MITIGATED (structural) + documented (behavioral)
- T-28-03d (unpinned promptfoo version): PROMPTFOO_VERSION constant `0.121.14` used — MITIGATED

## EVAL-03 Manual-UAT Obligation (enforcement-not-disposition)

The emitted workflow is structurally verified to be CONFIGURED to enforce (correct fail-on-threshold, correct triggers, correct path filters). The behavioral guarantee — that a deliberately-broken hook binary MUST cause the eval suite to FAIL when run with live promptfoo + ANTHROPIC_API_KEY — cannot be automated in CI. It is:
1. Documented in must_haves as an explicit HUMAN-UAT obligation
2. Surfaced in acceptance_criteria as a manual step
3. Printed by the command itself at invocation time
4. Recorded in VALIDATION.md manual-only section

This is NOT silently accepted. Phase verification must confirm this step was performed.

## Self-Check: PASSED

Files verified:
- `/Users/mohandoz/u01/innovate/conjure/scripts/eval.sh` — FOUND (cmd_eval_emit_workflow implemented)

Commits verified:
- `dc56be8`: feat(28-02): implement conjure eval --emit-workflow (EVAL-03) — FOUND

EVAL-03-emit test: PASS confirmed in test output (532 PASS total, EVAL-03-emit green).
