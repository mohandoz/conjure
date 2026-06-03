---
phase: 28
plan: "01"
subsystem: eval-worker
tags: [eval, promptfoo, eval-init, eval-run, POSIX-bash, EVAL-01, EVAL-02]
dependency_graph:
  requires:
    - 28-00 (eval fixtures + golden config + graceful-red test block)
  provides:
    - scripts/eval.sh (cmd_eval_init EVAL-01 + cmd_eval_run EVAL-02)
    - cli/conjure cmd_eval function + eval) dispatch
  affects:
    - tests/run.sh (EVAL-01-noskills grep -c || printf '0' → || true fix)
tech_stack:
  added: []
  patterns:
    - CONJURE_EVAL_CMD env var forwarding (mirrors cmd_adopt / cmd_emit_policy pattern)
    - target-arg find form (_list_installed_skills uses find "$target_dir/.claude/skills", NOT find .claude/skills relative to pwd)
    - mutate_write_file byte-exact (avoids trailing-newline strip from command substitution)
    - per-line printf YAML construction (never large heredoc with variable expansion — T-28-01 mitigation)
    - POSIX bash 3.2+ version parse (${ver%%.*} / ${ver#*.} / ${rest%%.*} — no arrays)
key_files:
  created:
    - scripts/eval.sh
  modified:
    - cli/conjure
    - tests/run.sh
decisions:
  - "CONJURE_EVAL_CMD env var OR $1 positional fallback for direct invocation (test harness passes subcmd as first arg; cli/conjure sets env var)"
  - "anthropic:claude-agent-sdk is the only provider for Conjure evals — exec/claude -p cannot supply metadata.skillCalls needed for skill-used assertions"
  - "evaluateOptions.repeat:3 at TOP LEVEL of generated YAML — not per-assertion (SC reconciliation confirmed in RESEARCH Pattern 3)"
  - "minPassCount absent from generated YAML — it is a GitHub Action input only (Wave 2)"
  - "_yaml_escape_single for YAML injection prevention (T-28-01 mitigate)"
  - "_validate_skill_name [a-zA-Z0-9_-]+ guard for skill name path traversal (T-28-02 mitigate)"
  - "Wave 2 stub: --emit-workflow exits 2 with message (to be implemented in 28-02)"
metrics:
  duration_minutes: 30
  completed_date: "2026-06-03T19:15:00Z"
  tasks_completed: 2
  files_created: 1
  files_modified: 2
---

# Phase 28 Plan 01: scripts/eval.sh (EVAL-01 + EVAL-02) + cli/conjure cmd_eval Summary

Wave 1 implementation: scripts/eval.sh with cmd_eval_init (EVAL-01 promptfooconfig.yaml generation via mutate_write_file) and cmd_eval_run (EVAL-02 Node >=20.20.0 preflight + npx --yes promptfoo@0.121.14 exit passthrough), wired into cli/conjure as cmd_eval with eval) dispatch.

## What Was Built

### Task 1: scripts/eval.sh

New POSIX bash 3.2+ worker implementing the `conjure eval` subcommand backend.

**File constants at top:**
- `PROMPTFOO_VERSION="0.121.14"` — single pinned constant used by both eval run and (Wave 2) --emit-workflow
- `PROMPTFOO_NODE_MIN_MAJOR=20`, `PROMPTFOO_NODE_MIN_MINOR=20` — Node requirement
- `FAIL_ON_THRESHOLD=80` — integer 80 = 0.8 fractional for GitHub Action (Wave 2)

**Functions implemented:**
- `_eval_check_node` — POSIX bash 3.2+ version parse without arrays; exits 2 with human-readable message including install URL and version requirement
- `_extract_rule_lines <claude_md>` — extracts imperative/bullet lines from CLAUDE.md; filters headings, table rows, horizontal rules, code fences, blockquotes, @-imports, blank lines
- `_list_installed_skills <target_dir>` — uses `find "$target_dir/.claude/skills" -name SKILL.md` (absolute target-arg form, no cwd drift) + sed to produce skill directory names
- `_yaml_escape_single <string>` — escapes `'` → `'\''` for single-quoted YAML scalars (T-28-01 mitigation)
- `_validate_skill_name <name>` — validates against `[a-zA-Z0-9_-]+` (T-28-02 mitigation)
- `_build_promptfooconfig <target_dir> <outfile>` — per-line printf construction (no heredoc variable expansion); writes header, provider block, evaluateOptions.repeat:3, prompts, defaultTest, then skill-used and llm-rubric test blocks
- `cmd_eval_init <target_dir>` — EVAL-01 implementation; mutate_mkdir + _build_promptfooconfig → mutate_write_file (byte-exact)
- `cmd_eval_run <target_dir>` — EVAL-02 implementation; _eval_check_node + npx availability + config existence + ANTHROPIC_API_KEY advisory (warn only) + exit passthrough

**Dispatch logic:** Reads `CONJURE_EVAL_CMD` env var (set by cli/conjure); falls back to `$1` for direct invocation (test harness pattern). Wave 2 stub: `--emit-workflow` exits 2 with message.

### Task 2: cli/conjure

Added `cmd_eval()` function after `cmd_emit_policy` — thin wrapper that parses subcommand and optional target, forwards via `CONJURE_EVAL_CMD` env var to `scripts/eval.sh`. Added usage line `conjure eval init|run|--emit-workflow [target]`. Added `eval)` dispatch case between `emit-policy)` and `version)`.

## Test Results

Wave 1 results: PASS: 531, FAIL: 5 (up from Wave 0's PASS: 526, FAIL: 9).

New PASSes from Wave 1 (5 gained):
- EVAL-01-init: PASS
- EVAL-01-skills: PASS (2 skill-used assertions for 2-skill harness)
- EVAL-01-rubrics: PASS (>=1 llm-rubric assertions)
- EVAL-01-noskills: PASS (0 skill-used when no skills)
- EVAL-02-node-absent: PASS (exit 2 with "node"/"20.20" message)

Remaining failures (Wave 2/3 stubs):
- EVAL-03-emit: Wave 2 (--emit-workflow not yet implemented)
- EVAL-04-porcelain: Wave 3 (audit --budget --porcelain)
- EVAL-05-gap: Wave 3 (audit coverage diff)
- EVAL-05-noconfig: Wave 3 (audit no eval config advisory)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] EVAL-01-noskills grep -c || printf '0' produced '0\n0' on macOS**
- **Found during:** Task 1 verification
- **Issue:** `grep -c` exits 1 when match count is 0. The test harness pattern `P28_NOSK_COUNT="$(grep -c "type: skill-used" ... 2>/dev/null || printf '0')"` causes grep to print "0" then exit 1, then `|| printf '0'` fires and appends another "0", giving `0\n0`. The subsequent `[ "$P28_NOSK_COUNT" -eq 0 ]` fails with "integer expression expected: 0\n0" on macOS bash.
- **Fix:** Changed `|| printf '0'` to `|| true` in the EVAL-01-noskills test. When grep exits 1, `|| true` fires but prints nothing, so `P28_NOSK_COUNT` correctly holds grep's printed "0". GNU/BSD grep both print "0" to stdout for zero matches (they always print the count; exit code indicates match presence).
- **Files modified:** tests/run.sh (line 5308)
- **Commit:** fb6d865

## Known Stubs

- `--emit-workflow` exits 2 with "Use conjure eval --emit-workflow (Wave 2)" message. Wave 2 (28-02) will implement the full GitHub Actions workflow emission.
- `FAIL_ON_THRESHOLD=80` constant is defined but only used in Wave 2's emitted workflow YAML.

## Threat Flags

None found — eval.sh is an offline YAML generator (eval init) and a thin npx shim (eval run). No new network endpoints, auth paths, or trust boundaries beyond what the PLAN's threat model already covers.

## Self-Check: PASSED

Files verified:
- `/Users/mohandoz/u01/innovate/conjure/scripts/eval.sh` — FOUND
- `/Users/mohandoz/u01/innovate/conjure/cli/conjure` — FOUND (modified)
- `/Users/mohandoz/u01/innovate/conjure/tests/run.sh` — FOUND (modified)

Commits verified in git log:
- `fb6d865`: feat(28-01): implement scripts/eval.sh — FOUND
- `b21a0fd`: feat(28-01): wire cmd_eval + eval) dispatch in cli/conjure — FOUND
