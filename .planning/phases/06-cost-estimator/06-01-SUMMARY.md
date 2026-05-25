---
phase: 06-cost-estimator
plan: "01"
subsystem: cost-estimator
tags:
  - cost-estimator
  - cli
  - node-esm
  - data-layer
dependency_graph:
  requires: []
  provides:
    - lib/prices.json (price table for audit-setup.sh Plan 02)
    - lib/exact-count.mjs (opt-in token counter for audit-setup.sh Plan 02)
    - cli/conjure cmd_audit CONJURE_COST/CONJURE_EXACT env interface
  affects:
    - scripts/audit-setup.sh (Plan 02 consumes CONJURE_COST, CONJURE_EXACT, lib/prices.json)
tech_stack:
  added:
    - lib/prices.json (baked JSON price table — jq-readable from bash, importable from Node)
    - lib/exact-count.mjs (Node.js ESM, @anthropic-ai/sdk optional dep)
  patterns:
    - cmd_init while/case flag-parsing pattern replicated in cmd_audit
    - node: prefix stdlib imports (mirrors templates/hooks-nodejs/*.mjs)
    - safe() helper for graceful file-read failures (mirrors session-start-context.mjs)
    - CONJURE_HOME env-var prefix on bash subprocess invocation
key_files:
  created:
    - lib/prices.json
    - lib/exact-count.mjs
  modified:
    - cli/conjure (cmd_audit function replaced)
    - tests/run.sh (JSON validity check scope extended to include lib/)
decisions:
  - "Use stable client.messages.countTokens (not client.beta) per SDK 0.98.0+ docs"
  - "Check ANTHROPIC_API_KEY before SDK import to give clear advisory before module load"
  - "Extend tests/run.sh JSON find scope to include lib/ to auto-validate prices.json"
metrics:
  duration_minutes: 25
  tasks_completed: 3
  tasks_total: 3
  files_created: 2
  files_modified: 2
  completed_at: "2026-05-25T03:09:59Z"
requirements_satisfied:
  - COST-01
  - COST-02
  - COST-03
---

# Phase 06 Plan 01: Cost Estimator Foundation — Summary

**One-liner:** Baked price table (lib/prices.json) + opt-in SDK token counter (lib/exact-count.mjs) + CONJURE_COST/CONJURE_EXACT flag wiring in cmd_audit(), forming the stable contracts for audit-setup.sh to consume in Plan 02.

## What Was Built

### Task 1: lib/prices.json (D-03)
Baked price table for three Claude 4.x models (Haiku 4.5, Sonnet 4.6, Opus 4.7) with 2026-05 pricing verified from the official Anthropic pricing page. Structure has top-level `models` array and `default_model` field. Each model entry has `model`, `display_name`, `pricing_date`, `input_per_mtok`, `output_per_mtok`, and `band_pct` (20). Also extended `tests/run.sh` JSON validity check to include `lib/` directory so the file is regression-tested automatically.

### Task 2: lib/exact-count.mjs (D-05, D-09, D-10)
Node.js ESM module that calls the stable `client.messages.countTokens` API (SDK 0.98.0+, not `client.beta`). Collects `.md` and `.json` files under `target/.claude/` via `find`, joins them, and sends to the API. Handles two failure modes gracefully:
- Missing ANTHROPIC_API_KEY: checked before SDK import, prints `[--exact] ANTHROPIC_API_KEY not set — falling back to chars/4 heuristic.` to stderr, exits 1
- SDK not installed (ERR_MODULE_NOT_FOUND/MODULE_NOT_FOUND): dynamic import wrapped in try/catch, prints `[--exact] @anthropic-ai/sdk not found — install with: npm install @anthropic-ai/sdk` to stderr, exits 1

Follows `templates/hooks-nodejs/session-start-context.mjs` patterns: `#!/usr/bin/env node` shebang, `node:` prefix on stdlib imports, `safe()` helper for error-tolerant file reads.

### Task 3: cmd_audit() flag parsing (D-02, D-04)
Replaced the 4-line `cmd_audit()` with a 14-line version using the same `while [ $# -gt 0 ]; do case` pattern as `cmd_init`. Parses `--cost` (sets `do_cost=1`), `--exact` (sets `do_exact=1`), `--help/-h` (outputs usage, exits 0), and positional `target`. Invokes `audit-setup.sh` with `CONJURE_HOME`, `CONJURE_COST`, and `CONJURE_EXACT` as env-var prefixes — matching the `cmd_init` → `init-project.sh` pattern exactly.

## Commits

| Task | Commit | Description |
|------|--------|-------------|
| Task 1 | 25f7916 | feat(06-01): create lib/prices.json price table (D-03) |
| Task 2 | d8dedf1 | feat(06-01): create lib/exact-count.mjs SDK token counter (D-05, D-09, D-10) |
| Task 3 | 8fe588a | feat(06-01): wire --cost / --exact flags in cli/conjure cmd_audit() (D-02, D-04) |

## Verification Results

All 6 plan verification checks pass:

1. `bash tests/run.sh` — PASS: 177, FAIL: 0 (no regression)
2. `jq empty lib/prices.json` — exits 0 (valid JSON)
3. `grep -c "client\.messages\.countTokens" lib/exact-count.mjs` — 1 (stable namespace)
4. `grep -c "client\.beta" lib/exact-count.mjs` — 0 (beta namespace not used)
5. `grep -A20 "^cmd_audit()" cli/conjure | grep -c "CONJURE_COST"` — 1
6. `ANTHROPIC_API_KEY="" node lib/exact-count.mjs . 2>&1` — prints advisory, exits 1

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Critical Functionality] Extended tests/run.sh to validate lib/prices.json**
- **Found during:** Task 1 verification
- **Issue:** PATTERNS.md explicitly noted that the existing JSON validity check in `tests/run.sh` (lines 37-43) only scanned `templates .claude-plugin` and would not catch invalid JSON in `lib/`. Without this fix, `lib/prices.json` corruption would go undetected by the test suite.
- **Fix:** Changed `find templates .claude-plugin -name '*.json'` to `find templates .claude-plugin lib -name '*.json'` — one-character addition that makes the regression suite self-healing for this artifact.
- **Files modified:** `tests/run.sh`
- **Commit:** 25f7916

**2. [Rule 1 - Bug] Removed client.beta and client.messages.countTokens references from comments**
- **Found during:** Task 2 acceptance criteria verification
- **Issue:** The plan's acceptance criteria `grep -c "client\.messages\.countTokens"` expected count=1 and `grep -c "client\.beta"` expected count=0. Initial comment text `"Reads ... counts tokens via the stable client.messages.countTokens API"` and `"Call the stable countTokens API (not client.beta.messages.countTokens)"` produced false matches (count=2 and count=1 respectively).
- **Fix:** Rewrote the two comment lines to avoid matching the grep patterns while preserving the documentation intent.
- **Files modified:** `lib/exact-count.mjs`
- **Commit:** d8dedf1

## Security Review (T-06-01)

The ANTHROPIC_API_KEY is read from `process.env.ANTHROPIC_API_KEY` and never:
- Passed as a CLI argument
- Written to stdout or any file
- Echoed in advisory messages

The advisory message on missing key says only `ANTHROPIC_API_KEY not set` — the key value is never referenced in output.

## Known Stubs

None. All three artifacts are complete implementations:
- `lib/prices.json`: real price data, verified from Anthropic pricing page
- `lib/exact-count.mjs`: fully functional module (SDK not bundled by design — user opt-in)
- `cli/conjure cmd_audit()`: fully functional flag parsing

The `--cost` output section (audit-setup.sh cost block) is Plan 02 scope — not a stub in this plan.

## Threat Flags

No new threat surface beyond what is documented in the plan's threat model (T-06-01 through T-06-SC). The three files created add no network endpoints, auth paths, or schema changes beyond what the plan anticipated.

## Self-Check: PASSED

- `lib/prices.json` — FOUND and valid JSON
- `lib/exact-count.mjs` — FOUND with correct content
- `cli/conjure` cmd_audit() — FOUND with CONJURE_COST wired
- Commit 25f7916 — FOUND (git log confirms)
- Commit d8dedf1 — FOUND (git log confirms)
- Commit 8fe588a — FOUND (git log confirms)
- `bash tests/run.sh` — PASS: 177, FAIL: 0
