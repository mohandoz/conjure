---
phase: 06-cost-estimator
plan: "02"
subsystem: cost-estimator
tags:
  - cost-estimator
  - audit
  - posix-bash
  - ascii-table
dependency_graph:
  requires:
    - lib/prices.json (Plan 01)
    - lib/exact-count.mjs (Plan 01)
    - cli/conjure cmd_audit CONJURE_COST/CONJURE_EXACT env interface (Plan 01)
  provides:
    - scripts/audit-setup.sh cost section (guarded by CONJURE_COST=1)
  affects:
    - scripts/audit-setup.sh (extended with 61 lines after the summary separator)
tech_stack:
  added: []
  patterns:
    - CONJURE_COST/CONJURE_EXACT guard pattern (opt-in section, POSIX :=  self-derivation)
    - awk "BEGIN {printf %.2f}" for float dollar arithmetic (never bash integer division)
    - mktemp + trap EXIT for per-file temp table (POSIX 3.2, no associative arrays)
    - sort -t' ' -k4 -rn for BSD/GNU portable cost-descending sort
    - bare echo/printf inside post-summary section (no ok()/warn()/err() calls)
key_files:
  created: []
  modified:
    - scripts/audit-setup.sh (cost section: 61 lines inserted after summary separator)
decisions:
  - "TOKENS_TO_USE defaults to EST_TOKENS (already computed); --exact overrides if node call succeeds"
  - "EXACT_TOKENS exit-code check uses $? captured immediately after node call (not in subshell)"
  - "Per-file table rows written to mktemp file; sort reads the file; avoids bash 3.2 associative array restriction"
  - "EST_TOKENS guarded with :- 0 default in case .claude/ dir was absent (line 123 guard)"
metrics:
  duration_minutes: 18
  tasks_completed: 2
  tasks_total: 2
  files_created: 1
  files_modified: 1
  completed_at: "2026-05-25T03:35:00Z"
requirements_satisfied:
  - COST-01
  - COST-02
  - COST-03
---

# Phase 06 Plan 02: Cost Estimator Section — Summary

**One-liner:** Per-file cost breakdown table with awk float math, CONJURE_HOME self-derivation, and --exact fallback advisory injected into audit-setup.sh after the PASS/WARN/FAIL separator, guarded by CONJURE_COST=1.

## What Was Built

### Task 1: Cost section skeleton (D-01, D-08)

Inserted a CONJURE_COST=1 guard block in `scripts/audit-setup.sh` after the third echo line of the summary block (after the second `────` separator line) and before the `[ "$FAIL" -gt 0 ]` exit guard. Inside the block:

- `CONJURE_HOME` is self-derived from `$0` via POSIX `:=` assignment (guards against the env var not being set when the script is invoked directly rather than through `cmd_audit`)
- `PRICE_FILE` is set to `$CONJURE_HOME/lib/prices.json`
- `jq` availability is checked; a bare `echo` advisory is printed if absent (no `ok()`/`warn()`/`err()` to avoid corrupting the already-printed tally)
- `MODEL`, `PRICE_INPUT`, `PRICING_DATE`, `BAND_PCT` are read from prices.json via `jq --arg m "$MODEL" '.models[] | select(.model==$m)'`
- `TOKENS_TO_USE` is initialized to `${EST_TOKENS:-0}`
- `── Cost Estimate ──` header is echoed

Baseline audit output (no `--cost` flag) is completely unchanged — the block is gated at the top by `[ "${CONJURE_COST:-0}" = "1" ]`.

### Task 2: Per-file breakdown table, label line, --exact integration (D-06, D-07, D-10)

Extended the cost section inside the jq-available branch with:

**A. --exact integration:**
- Checks `CONJURE_EXACT=1`, then checks `ANTHROPIC_API_KEY` — if absent, prints advisory and continues with heuristic
- If node + exact-count.mjs are available, calls `node "$CONJURE_HOME/lib/exact-count.mjs" "$TARGET"` and captures stdout
- Uses `$?` exit code check to detect failure; falls back to EST_TOKENS with advisory if non-zero or empty output

**B. Total cost calculation:**
- `TOTAL_COST=$(awk "BEGIN {printf \"%.2f\", $TOKENS_TO_USE * $PRICE_INPUT / 1000000}")` — awk-only, no bash integer arithmetic

**C. Per-file breakdown table:**
- `mktemp` temp file with `trap 'rm -f "$COST_TMP"' EXIT` for cleanup
- Iterates CLAUDE.md and .claude/settings.json (with `[ -f ]` guard), then finds all SKILL.md files under .claude/skills/
- Per file: `wc -c` char count, bash `$((chars / 4))` token estimate (integer division is fine here — dollar amounts always use awk), `awk "%.6f"` cost
- Lines written to temp file as space-delimited `name chars tokens cost`
- Sorted with `sort -t' ' -k4 -rn` (BSD/GNU portable) and printed with `printf "  %-30s %8s %8s  $%10.6f\n"` format
- TOTAL row uses `printf "  %-30s %8s %8s  $%10.2f\n"` with `$TOTAL_COST`

**D. Label line:**
- `echo "  Estimate: \$$TOTAL_COST ±${BAND_PCT}% (chars/4 heuristic · prices: $PRICING_DATE · model: $MODEL)"`

## Commits

| Task | Commit | Description |
|------|--------|-------------|
| Task 1 | 62e8d49 | feat(06-02): insert cost section skeleton in audit-setup.sh (D-01, D-08) |
| Task 2 | e6fe5d6 | feat(06-02): implement per-file breakdown table, label line, --exact integration (D-06, D-07, D-10) |

## Verification Results

All 5 plan-level verification checks pass:

1. `CONJURE_COST=1 bash scripts/audit-setup.sh <target>` — outputs `Estimate: $1.29 ±20% (chars/4 heuristic · prices: 2026-05 · model: claude-sonnet-4-6)` — PASS
2. `bash scripts/audit-setup.sh <target> | grep -c "Cost Estimate"` — 0 (no cost section without flag) — PASS
3. `CONJURE_COST=1 CONJURE_EXACT=1 ANTHROPIC_API_KEY=""` — prints `ANTHROPIC_API_KEY not set` advisory, exits ≤ 2 — PASS
4. `grep -v '^#' scripts/audit-setup.sh | grep -cE "^[[:space:]]*(curl|fetch|http)"` — 0 (no network calls) — PASS
5. `bash tests/run.sh` — PASS: 177, FAIL: 0 — PASS

## Deviations from Plan

None — plan executed exactly as written. All constraints observed:
- No `ok()`/`warn()`/`err()` calls in the cost section
- All dollar arithmetic via `awk "BEGIN {printf ...}"` (never `$((... ))`)
- POSIX bash 3.2: no `declare -A`, no `mapfile`, no `[[` with regex
- `sort -t' '` for BSD/GNU compatibility
- `CONJURE_HOME` self-derived inside the cost block via `:=` POSIX assignment

## Known Stubs

None. The cost section is fully implemented:
- Per-file breakdown table populated from real `wc -c` counts
- Label line uses live data from prices.json
- --exact path wired to lib/exact-count.mjs

## Threat Flags

No new threat surface beyond the plan's threat model (T-06-11 through T-06-SC). The cost section:
- Makes zero network calls in the default path (grep confirmed)
- Derives CONJURE_HOME from `$0` (trusted; absolute path always set by cli/conjure)
- Does not echo the ANTHROPIC_API_KEY value in any output path

## Self-Check: PASSED

- `scripts/audit-setup.sh` — FOUND and modified (61 lines added)
- Commit 62e8d49 — FOUND (git log confirms)
- Commit e6fe5d6 — FOUND (git log confirms)
- `CONJURE_COST=1 bash scripts/audit-setup.sh <target> | grep "── Cost Estimate ──"` — FOUND
- `bash scripts/audit-setup.sh <target> | grep -c "Cost Estimate"` — 0 (no false positive)
- `bash tests/run.sh` — PASS: 177, FAIL: 0
