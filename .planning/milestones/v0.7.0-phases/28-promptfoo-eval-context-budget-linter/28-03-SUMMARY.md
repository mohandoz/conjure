---
phase: 28
plan: "03"
subsystem: audit-eval
tags: [audit, eval, budget-linter, coverage-gap, EVAL-04, EVAL-05, POSIX-bash]
dependency_graph:
  requires:
    - 28-00 (eval fixtures + _eval-overbudget + _eval-coverage-gap test fixtures)
    - 28-01 (scripts/eval.sh providing EVAL-01/02; cli/conjure cmd_eval dispatch)
  provides:
    - scripts/audit-setup.sh --budget block (EVAL-04)
    - scripts/audit-setup.sh EVAL-05 coverage gap block
    - cli/conjure cmd_audit --budget and --porcelain flags
  affects:
    - scripts/eval.sh (chmod +x auto-fix from 28-01 missing executable bit)
tech_stack:
  added: []
  patterns:
    - CONJURE_BUDGET env var gate for optional audit blocks (mirrors CONJURE_COST pattern)
    - CONJURE_PORCELAIN env var routes human() to stderr + emits JSON to stdout (independent reuse — separate process scope from cmd_check path)
    - BUDGET_TMP joins existing _audit_cleanup EXIT trap — NO second trap registered (WR-03 lesson preserved)
    - jq -cn --argjson + --slurpfile for injection-safe porcelain JSON output
    - awk two-line lookahead for dependency-free YAML parse (controlled Conjure-generated format)
    - comm -23 sorted tempfile diff for coverage gap detection
key_files:
  created: []
  modified:
    - scripts/audit-setup.sh
    - cli/conjure
decisions:
  - "CONJURE_PORCELAIN=1 modifies human() routing to stderr globally when set — guarantees clean JSON-only stdout without per-call guards in each human() call site"
  - "BUDGET_TMP declared at top-level (empty string) before _audit_cleanup function body so :- expansion is always safe regardless of CONJURE_BUDGET value"
  - "_eval_extract_skill_used defined as function immediately before call site in EVAL-05 block — no forward reference ambiguity"
  - "EVAL-05 block always runs (no gate condition) — advisory note() only; never increments FAIL counter; never exits 2"
  - "Rule 1 auto-fix: chmod +x scripts/eval.sh — missing executable bit from 28-01 caused 1 FAIL in the smoke test suite"
metrics:
  duration_min: 25
  completed_date: "2026-06-03"
  tasks: 2
  files_modified: 3
---

# Phase 28 Plan 03: Context Budget Linter + Eval Coverage Gap Summary

**One-liner:** chars/4 budget linter (EVAL-04) measuring CLAUDE.md + SKILL.md always-loaded tokens with porcelain JSON, plus EVAL-05 skill coverage gap diff via awk YAML parse — all wired through CONJURE_BUDGET/CONJURE_PORCELAIN env vars with no new EXIT traps.

## Tasks Completed

| # | Task | Commit | Files |
|---|------|--------|-------|
| 1 | Add --budget linter (EVAL-04) + EVAL-05 coverage gap to scripts/audit-setup.sh | ccc0329 | scripts/audit-setup.sh, scripts/eval.sh |
| 2 | Wire --budget and --porcelain flags in cli/conjure cmd_audit | 1860ae9 | cli/conjure |

## What Was Built

### EVAL-04: Context Budget Linter (`conjure audit --budget`)

Added to `scripts/audit-setup.sh` (after existing total-token-estimate block):

- **`_audit_cleanup` extended**: `rm -f "${CHECKS_JSONL:-}" "${COST_TMP:-}" "${BUDGET_TMP:-}"` — BUDGET_TMP cleanup folded into the single existing EXIT trap; no second trap registered (WR-03 lesson).
- **Always-loaded scope**: CLAUDE.md (entire file) + each `.claude/skills/*/SKILL.md` (entire file, conservative overcount).
- **Thresholds** reuse existing tiers: `>=15000` → `warn()`, `>=25000` → `err()` (exit 2).
- **Top-5 contributors**: `sort -rn | head -5` from BUDGET_TMP tempfile.
- **Porcelain JSON**: `{total_tokens, threshold, over: bool, contributors: [{path, tokens}]}` via `jq -cn --slurpfile contributors | flatten` (injection-safe).
- **Human routing**: `CONJURE_PORCELAIN=1` causes `human()` to write to stderr globally, keeping stdout clean for JSON output.

### EVAL-05: Eval Coverage Gap Report (`conjure audit`)

Always runs (no gate). Uses dependency-free grep/awk to parse Conjure's generated promptfooconfig.yaml:

- **`_eval_extract_skill_used`**: awk two-line lookahead (`/type: skill-used/ → found; found && /value:/ → print`) defined before call site.
- **`comm -23` diff**: installed skills (find .claude/skills) vs asserted skills (from YAML parse) — gap skills reported as `note()` advisory (exit 0 only).
- **Config absent**: `note "no eval config — run \`conjure eval init\` (EVAL-05)"` — never an error.

### cli/conjure cmd_audit

- Added `--budget` and `--porcelain` flags to the flag-parsing while loop.
- Forwards `CONJURE_BUDGET="$do_budget"` and `CONJURE_PORCELAIN="$do_porcelain"` to audit-setup.sh.
- Routes `cmd_preflight` to stderr when `--porcelain` is set (stdout reserved for JSON).
- Updated `usage()` and `--help` to include `[--budget] [--porcelain]`.

## Test Results

All EVAL-01..05 tests GREEN:

```
PASS: 536    FAIL: 0
```

EVAL-04 specific:
- `EVAL-04-budget-ok`: PASS
- `EVAL-04-budget-err`: PASS (>=25k tokens → exit 2)
- `EVAL-04-porcelain`: PASS (JSON shape valid)

EVAL-05 specific:
- `EVAL-05-gap`: PASS (code-review skill reported as gap)
- `EVAL-05-noconfig`: PASS (advisory note on absent config)

Phase 27 SCHM-* tests: all 12 GREEN — no regressions.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Missing executable bit on scripts/eval.sh**
- **Found during:** Full suite run (1 FAIL: "NOT executable: scripts/eval.sh")
- **Issue:** scripts/eval.sh was committed in 28-01 without the executable bit set; the smoke test `find scripts -name '*.sh' | [ -x "$script" ]` caught this.
- **Fix:** `chmod +x scripts/eval.sh`
- **Files modified:** scripts/eval.sh (mode change 100644 → 100755)
- **Commit:** ccc0329

**2. [Rule 2 - Missing critical functionality] CONJURE_PORCELAIN must also route human() to stderr**
- **Found during:** Task 1 verification (porcelain test showed mixed JSON + human text on stdout)
- **Issue:** The plan said "Do NOT emit any human() lines in [porcelain] mode" inside the budget block, but human() calls outside the budget block still wrote to stdout when CONJURE_PORCELAIN=1.
- **Fix:** Modified `human()` to check `CONJURE_PORCELAIN` in addition to `JSON_MODE`, routing to stderr in both cases. Also added `CONJURE_PORCELAIN` initialization near JSON_MODE at the top of audit-setup.sh (before the cleanup function's BUDGET_TMP reference could cause issues).
- **Files modified:** scripts/audit-setup.sh
- **Commit:** ccc0329

**3. [Rule 2 - Missing critical functionality] cmd_preflight must route to stderr when --porcelain**
- **Found during:** Task 2 verification (CLI end-to-end test showed preflight output contaminating stdout)
- **Issue:** cmd_audit only routed preflight to stderr for `--json`. With `--porcelain`, preflight output mixed into stdout alongside the budget JSON.
- **Fix:** Extended the preflight routing condition: `if [ "$do_json" = "1" ] || [ "$do_porcelain" = "1" ]`
- **Files modified:** cli/conjure
- **Commit:** 1860ae9

## Known Stubs

None. Both EVAL-04 and EVAL-05 are fully wired with real functionality.

## Threat Surface Scan

No new network endpoints, auth paths, or file-write paths introduced. EVAL-05 is read-only (awk parse of .conjure/eval/promptfooconfig.yaml). EVAL-04 reads CLAUDE.md and SKILL.md files (read-only). All jq output uses --argjson/--arg/--slurpfile (injection-safe). Threat T-28-04b (BUDGET_TMP cleanup) fully mitigated via _audit_cleanup extension.

## Self-Check

- [x] scripts/audit-setup.sh modified and shellcheck clean
- [x] cli/conjure modified and shellcheck clean
- [x] scripts/eval.sh chmod fix committed
- [x] Commits exist: ccc0329 (audit-setup.sh + eval.sh), 1860ae9 (cli/conjure)
- [x] Full suite: PASS 536, FAIL 0
- [x] EVAL-04-budget-err, EVAL-04-porcelain, EVAL-05-gap, EVAL-05-noconfig all PASS

## Self-Check: PASSED
