---
phase: 28
plan: "00"
subsystem: eval-fixtures
tags: [eval, promptfoo, fixtures, tdd, wave-0]
dependency_graph:
  requires: []
  provides:
    - tests/fixtures/_eval/harness (2-skill + 3-rule-line harness fixture)
    - tests/fixtures/_eval/expected-promptfooconfig.yaml (golden config for EVAL-01)
    - tests/fixtures/_eval-coverage-gap/harness (EVAL-05 negative fixture)
    - tests/fixtures/_eval-overbudget/harness (EVAL-04 over-budget fixture)
    - tests/fixtures/_eval-probe/README.md (A1/A2/A3 resolution docs)
    - tests/run.sh Phase 28 EVAL block (graceful-red, 12 test cases)
  affects:
    - tests/run.sh (new Phase 28 EVAL section appended)
tech_stack:
  added: []
  patterns:
    - golden-config-fixture (expected-promptfooconfig.yaml mirrors Wave 1 output)
    - graceful-red-test-block (EVAL block fails until Wave 1 ships eval.sh)
    - presence-guard-pattern (P28_EVAL_OK / P28_AUDIT_OK gates)
key_files:
  created:
    - tests/fixtures/_eval/harness/CLAUDE.md
    - tests/fixtures/_eval/harness/.claude/skills/audit-helper/SKILL.md
    - tests/fixtures/_eval/harness/.claude/skills/code-review/SKILL.md
    - tests/fixtures/_eval/expected-promptfooconfig.yaml
    - tests/fixtures/_eval-coverage-gap/harness/CLAUDE.md
    - tests/fixtures/_eval-coverage-gap/harness/.claude/skills/audit-helper/SKILL.md
    - tests/fixtures/_eval-coverage-gap/harness/.claude/skills/code-review/SKILL.md
    - tests/fixtures/_eval-coverage-gap/harness/.conjure/eval/promptfooconfig.yaml
    - tests/fixtures/_eval-overbudget/harness/CLAUDE.md
    - tests/fixtures/_eval-overbudget/harness/.claude/skills/bigskill/SKILL.md
    - tests/fixtures/_eval-probe/README.md
  modified:
    - tests/run.sh (Phase 28 EVAL block inserted before GH_HIDE_STUBS cleanup)
decisions:
  - "golden config encodes anthropic:claude-agent-sdk provider (RESEARCH-determined; exec/claude -p cannot supply skill-used assertion metadata)"
  - "evaluateOptions.repeat:3 at TOP LEVEL of promptfooconfig.yaml (not per-assertion — SC reconciliation: per-assertion repeat keys cause YAML parse errors)"
  - "minPassCount is NOT in promptfooconfig.yaml (it is a GitHub Action input, not a YAML key)"
  - "fail-on-threshold encoded as integer 80 in EVAL-03 test (not float 0.8 — action expects 0-100 integer per D-28-THRESH)"
  - "_eval-overbudget CLAUDE.md uses repeated # padding lines only (9901+ lines for 101000 chars, triggering 25k-token err() threshold)"
  - "gap fixture promptfooconfig.yaml comment avoids mentioning skill name to prevent false-positive grep-qv check"
metrics:
  duration_minutes: 23
  completed_date: "2026-06-03T15:21:22Z"
  tasks_completed: 2
  files_created: 11
  files_modified: 1
---

# Phase 28 Plan 00: Eval Fixtures + Golden Config + Graceful-Red EVAL Block Summary

Wave 0 TDD infrastructure: golden promptfooconfig.yaml with anthropic:claude-agent-sdk provider + evaluateOptions.repeat:3 at top level, 3 fixture trees, integration probe docs, and 12-test graceful-red EVAL block in tests/run.sh.

## What Was Built

### Task 1: Eval Fixture Harnesses and Golden Config

**_eval/harness/** — Happy-path fixture for EVAL-01. Contains:
- `CLAUDE.md` with 3 imperative rule lines (shellcheck, exit 2, backup-before-mutate)
- `audit-helper/SKILL.md` (allowed-tools: Bash) and `code-review/SKILL.md` (allowed-tools: Read, Bash)

**_eval/expected-promptfooconfig.yaml** — Golden config that `conjure eval init` must produce:
- Provider: `id: anthropic:claude-agent-sdk` with `working_dir: .`, `setting_sources: ['project']`, `skills: all`
- `evaluateOptions.repeat: 3` at the TOP LEVEL (SC reconciliation: not per-assertion)
- 2 `skill-used` assertions (one per installed skill)
- 3 `llm-rubric` assertions (one per CLAUDE.md rule line, threshold: 0.8)
- NO `minPassCount` (GitHub Action input, not YAML key)
- NO `fail-on-threshold` float (integer 80 lives in emitted workflow YAML, not promptfooconfig.yaml)

**_eval-coverage-gap/harness/** — EVAL-05 negative fixture. Two skills installed, config only
asserts `audit-helper` (code-review added after `eval init`, creating coverage gap).

**_eval-overbudget/harness/** — EVAL-04 over-budget fixture. `CLAUDE.md` has 10100 `# padding`
lines (101000 chars). Total chars = 101133 (> 100000 = 25000 tokens at chars/4, triggering err()).

**_eval-probe/README.md** — Documents A1/A2/A3 open question resolutions:
- A1 (auto-install of @anthropic-ai/claude-agent-sdk): ASSUMED; probe is documentation-only
- A2 (working_dir: .): YAML structure verified via golden fixture; live behavior is manual-only
- A3 (setting_sources: ['project']): same as A2

### Task 2: Phase 28 Graceful-Red EVAL Test Block

Inserted 334 lines into `tests/run.sh` immediately before the GH_HIDE_STUBS cleanup loop.

**Presence guards:**
- `P28_EVAL_OK=1` if `scripts/eval.sh` exists (absent in Wave 0)
- `P28_AUDIT_OK=1` if `scripts/audit-setup.sh` exists (present but without EVAL extensions)

**12 test cases:**
- EVAL-01-init, EVAL-01-skills, EVAL-01-rubrics, EVAL-01-noskills (eval.sh gated)
- EVAL-02-node-absent (eval.sh gated), EVAL-02-audit-decoupled (audit.sh, passes)
- EVAL-03-emit (eval.sh gated)
- EVAL-04-budget-ok (audit.sh, passes), EVAL-04-budget-err (audit.sh, passes), EVAL-04-porcelain (audit.sh, fails — EVAL section absent)
- EVAL-05-gap (audit.sh, fails — EVAL section absent), EVAL-05-noconfig (audit.sh, fails — EVAL section absent)

**Results after Wave 0:** PASS: 526, FAIL: 9 (all 9 failures are graceful-red EVAL stubs)

## Deviations from Plan

**1. [Rule 1 - Bug] Gap fixture comment avoided skill name**
- **Found during:** Task 1
- **Issue:** The gap fixture's promptfooconfig.yaml initially included "code-review" in a comment line, causing `grep -qv "code-review"` acceptance check to fail
- **Fix:** Rewrote comment to say "the new skill" instead of naming it
- **Files modified:** tests/fixtures/_eval-coverage-gap/harness/.conjure/eval/promptfooconfig.yaml

**2. [Rule 1 - Bug] .claude dirs require git add -f**
- **Found during:** Task 1 commit
- **Issue:** Global gitignore (`~/.gitignore_global`) excludes `.claude/` directories; staged adds were rejected
- **Fix:** Used `git add -f` for `.claude/` paths inside fixtures (mirrors how existing `_schema-audit` fixtures are tracked)
- **Files modified:** N/A (git staging behavior)

**3. [Rule 2 - Missing] Overbudget fixture initial char count too low**
- **Found during:** Task 1 verification
- **Issue:** Initial 9901 lines produced 99143 total chars (< 100001 threshold)
- **Fix:** Increased to 10100 lines (101133 total chars, well above 100000)
- **Files modified:** tests/fixtures/_eval-overbudget/harness/CLAUDE.md

## Known Stubs

None — this plan creates only fixtures and test stubs. The EVAL tests fail gracefully (they are the stubs, by design). Wave 1 will implement `scripts/eval.sh` to turn EVAL-01/02/03 green.

## Threat Flags

None found — all new files are fixture YAML/Markdown under `_`-prefixed dirs excluded from generic audit loops. No network endpoints, auth paths, or trust boundaries introduced.

## Self-Check: PASSED

All created files exist. Both task commits confirmed in git log:
- `37fddf5`: feat(28-00): create eval fixture harnesses and golden promptfooconfig.yaml
- `a047879`: feat(28-00): add Phase 28 graceful-red EVAL test block to tests/run.sh
