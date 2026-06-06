---
phase: 28-promptfoo-eval-context-budget-linter
verified: 2026-06-03T21:00:00Z
status: human_needed
score: 5/5 must-haves verified
overrides_applied: 0
human_verification:
  - test: "EVAL-03 enforcement-not-disposition behavioral check"
    expected: "A deliberately-broken hook binary (e.g. PreToolUse exits 2 unconditionally) causes the promptfoo eval suite to FAIL when run with live promptfoo and ANTHROPIC_API_KEY set"
    why_human: "Requires live LLM API call via npx promptfoo@0.121.14; cannot be automated in CI without ANTHROPIC_API_KEY and live network; only the structural half (YAML correctness) is automatable"
---

# Phase 28: promptfoo Eval + Context-Budget Linter Verification Report

**Phase Goal:** Developers can scaffold, run, and CI-gate a promptfoo-based prompt-adherence eval suite, and `conjure audit` statically measures harness context load.
**Verified:** 2026-06-03T21:00:00Z
**Status:** human_needed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | `conjure eval init` scaffolds `.conjure/eval/promptfooconfig.yaml` with provider `anthropic:claude-agent-sdk`, `evaluateOptions.repeat:3` at config level, one `skill-used` assertion per installed skill, one `llm-rubric` per CLAUDE.md rule line (EVAL-01) | VERIFIED | `scripts/eval.sh` implements `cmd_eval_init`; behavioral check on `_eval/harness` produces 2 `skill-used` + 4 `llm-rubric` assertions; golden fixture has 2 skill-used + 3 llm-rubric; `EVAL-01-init/skills/rubrics/noskills` all PASS in test suite (541/0) |
| 2 | `conjure eval run` shells `npx --yes promptfoo@0.121.14` with Node `^20.20.0\|\|>=22.22.0` preflight, passes exit code through; `conjure audit` with promptfoo absent exits 0; `conjure eval` with promptfoo absent exits 2 (EVAL-02) | VERIFIED | `_eval_check_node` in `scripts/eval.sh` exits 2 with human-readable message for v19.0.0; `EVAL-02-node-absent` PASS; `EVAL-02-audit-decoupled` PASS; no `npx`/`promptfoo` in `scripts/audit-setup.sh` |
| 3 | `conjure eval --emit-workflow` generates `.github/workflows/conjure-eval.yml` with `pull_request` trigger, `promptfoo/promptfoo-action@v1`, `fail-on-threshold: 80` (integer), `repeat: 3`, `repeat-min-pass: 2`, path-filtered on `.claude/**` and `CLAUDE.md` (EVAL-03 structural half) | VERIFIED | Runtime emission confirmed: all 11 YAML structural checks PASS; `EVAL-03-emit` test PASS; `FAIL_ON_THRESHOLD=80` constant in `eval.sh` line 25, emitted via `"fail-on-threshold: ${FAIL_ON_THRESHOLD}"` — emitted value is `fail-on-threshold: 80` |
| 4 | `conjure audit --budget` measures chars/4 tokens for CLAUDE.md + always-loaded SKILL.md indexes, flags >=25k with err() (exit 2), flags >=15k with warn(), lists top contributors, supports `--porcelain` JSON (EVAL-04) | VERIFIED | `BUDGET_THRESHOLD_ERR=25000` in `audit-setup.sh`; overbudget fixture (101133 chars = ~25283 tokens) produces exit 2; porcelain JSON has `total_tokens`, `contributors` array, `over` field; `EVAL-04-budget-ok/err/porcelain` all PASS |
| 5 | `conjure audit` reports installed skills with no `skill-used` assertion as note() advisory (exit 0); skill added after eval init appears in gap report (EVAL-05) | VERIFIED | `_eval_extract_skill_used` awk two-line lookahead in `audit-setup.sh`; `comm -23` diff; gap fixture correctly reports `code-review` as uncovered; no-config advisory verified behaviorally; `EVAL-05-gap/noconfig` both PASS |

**Score:** 5/5 truths verified

### Deferred Items

None.

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `scripts/eval.sh` | eval subcommand worker: cmd_eval_init + cmd_eval_run + cmd_eval_emit_workflow | VERIFIED | Exists, executable (-rwxr-xr-x), shellcheck clean, contains all required functions and constants |
| `cli/conjure` | cmd_eval function + eval) dispatch case + --budget/--porcelain in cmd_audit | VERIFIED | cmd_eval present with CONJURE_EVAL_CMD forwarding; eval) dispatch at line 597; --budget/--porcelain wired in cmd_audit |
| `scripts/audit-setup.sh` | --budget linter (EVAL-04) + EVAL-05 coverage diff + BUDGET_TMP in _audit_cleanup | VERIFIED | All three additions confirmed; no second EXIT trap; shellcheck clean |
| `tests/fixtures/_eval/harness/` | 2-skill harness with CLAUDE.md (3 rule lines) | VERIFIED | CLAUDE.md with 3 imperative rule lines; audit-helper + code-review SKILL.md files present |
| `tests/fixtures/_eval/expected-promptfooconfig.yaml` | Golden config: anthropic:claude-agent-sdk, evaluateOptions.repeat:3, 2 skill-used, 3 llm-rubric | VERIFIED | All structural checks pass; no minPassCount; no fail-on-threshold float |
| `tests/fixtures/_eval-coverage-gap/harness/.conjure/eval/promptfooconfig.yaml` | Pre-seeded config with only audit-helper skill-used (no code-review) | VERIFIED | Contains audit-helper assertion; grep -qv "code-review" PASS |
| `tests/fixtures/_eval-overbudget/harness/CLAUDE.md` | >=100000 chars to trigger err() at 25k tokens | VERIFIED | 101133 total chars (CLAUDE.md + bigskill/SKILL.md) |
| `tests/fixtures/_eval-probe/README.md` | A1/A2/A3 resolution documentation | VERIFIED | Documents A1 (ASSUMED, live probe skipped), A2 (YAML-structure only), A3 (YAML-structure only) |
| `tests/run.sh` | Phase 28 EVAL block with all 12 EVAL-* test cases | VERIFIED | All 12 tags present; 541 PASS / 0 FAIL in full suite |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `cli/conjure eval)` dispatch | `scripts/eval.sh` | `cmd_eval()` calls `bash "$CONJURE_HOME/scripts/eval.sh"` with CONJURE_EVAL_CMD | WIRED | Line 597 dispatch; cmd_eval() body at lines 189-201 |
| `scripts/eval.sh` `_list_installed_skills` | `.claude/skills` directory under target_dir | `find "$target_dir/.claude/skills" -name SKILL.md` | WIRED | Absolute target-arg form confirmed; no cwd drift |
| `scripts/eval.sh` `cmd_eval_init` | `lib/mutate.sh mutate_write_file` | Write `.conjure/eval/promptfooconfig.yaml` via tempfile | WIRED | `mutate_write_file "$eval_dir/promptfooconfig.yaml" "$tmpfile"` |
| `scripts/eval.sh` `cmd_eval_run` | `npx --yes promptfoo@0.121.14` | Shell-out with exit passthrough | WIRED | `npx --yes "promptfoo@${PROMPTFOO_VERSION}" eval -c "$config_file"` |
| `scripts/eval.sh` `cmd_eval_emit_workflow` | `lib/mutate.sh mutate_write_file` | Write `.github/workflows/conjure-eval.yml` via tempfile | WIRED | `mutate_write_file` confirmed in emit function |
| `scripts/audit-setup.sh` `_audit_cleanup` | BUDGET_TMP tempfile | `_audit_cleanup() { rm -f "${CHECKS_JSONL:-}" "${COST_TMP:-}" "${BUDGET_TMP:-}"; }` | WIRED | Single-line _audit_cleanup; no second trap; WR-03 lesson preserved |
| `scripts/audit-setup.sh` EVAL-05 block | `_eval_extract_skill_used` awk two-line lookahead | Parses `type: skill-used` / `value:` lines from promptfooconfig.yaml | WIRED | Function defined before call site; `comm -23` diff for coverage gap |
| `cli/conjure` `cmd_audit --budget` | `scripts/audit-setup.sh` via CONJURE_BUDGET=1 | env var forwarding | WIRED | `--budget` sets `do_budget=1`; forwarded as `CONJURE_BUDGET="$do_budget"` |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|--------------------|--------|
| `scripts/eval.sh` `cmd_eval_init` | `promptfooconfig.yaml` content | `_list_installed_skills` (find .claude/skills) + `_extract_rule_lines` (grep CLAUDE.md) | Yes — filesystem-derived skill names and rule lines | FLOWING |
| `scripts/audit-setup.sh` --budget block | `TOTAL_BUDGET_TOKENS` | `wc -c` on CLAUDE.md + SKILL.md files; awk arithmetic | Yes — actual file char counts | FLOWING |
| `scripts/audit-setup.sh` EVAL-05 block | coverage gap | `_eval_extract_skill_used` awk on .conjure/eval/promptfooconfig.yaml; `comm -23` diff vs find .claude/skills | Yes — real filesystem state | FLOWING |
| Emitted `.github/workflows/conjure-eval.yml` | YAML content | `printf '%s\n'` per line with `PROMPTFOO_VERSION` and `FAIL_ON_THRESHOLD` constants | Yes — constants baked at emit time | FLOWING |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| `conjure eval init` on 2-skill harness produces correct config | `CONJURE_HOME=. CONJURE_EVAL_CMD=init bash scripts/eval.sh tests/fixtures/_eval/harness` (copy) | skill-used=2, llm-rubric=4, anthropic:claude-agent-sdk present | PASS |
| `conjure eval run` with node v19 exits 2 with human-readable message | PATH=fake-node CONJURE_EVAL_CMD=run bash scripts/eval.sh | Exit 2, stderr contains "^20.20.0" message | PASS |
| `conjure eval --emit-workflow` emits correct YAML | `CONJURE_EVAL_CMD=--emit-workflow bash scripts/eval.sh <tmpdir>` | fail-on-threshold:80, repeat:3, repeat-min-pass:2, .claude/**, 0.121.14 | PASS |
| `conjure audit --budget` on overbudget fixture exits 2 | `bash cli/conjure audit --budget tests/fixtures/_eval-overbudget/harness` | Exit 2, "~25283 tokens (>=25000)" | PASS |
| `conjure audit --budget --porcelain` emits valid JSON | `bash cli/conjure audit --budget --porcelain tests/fixtures/_eval/harness 2>/dev/null \| jq -e '.total_tokens'` | Exit 0, total_tokens=140, contributors array present | PASS |
| `conjure audit` on coverage-gap fixture reports code-review | `bash cli/conjure audit tests/fixtures/_eval-coverage-gap/harness 2>&1` | "[eval] skill 'code-review' has no skill-used assertion" | PASS |
| `conjure audit` with no eval config emits advisory and exits 0 | CONJURE_HOME=. bash scripts/audit-setup.sh (no .conjure/eval/) | "no eval config — run `conjure eval init` (EVAL-05)", exit 0 | PASS |
| Full test suite | `bash tests/run.sh` | PASS: 541 / FAIL: 0 | PASS |

### Probe Execution

Step 7c: No `scripts/*/tests/probe-*.sh` files exist for this phase. The `tests/fixtures/_eval-probe/README.md` is documentation-only by explicit design (A1 live-probe requires ANTHROPIC_API_KEY and live network). Probe execution is SKIPPED by plan design.

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|---------|
| EVAL-01 | 28-00, 28-01 | `conjure eval init` scaffolds promptfooconfig.yaml with skill-used + llm-rubric assertions | SATISFIED | `scripts/eval.sh` cmd_eval_init; 4 EVAL-01 tests all PASS |
| EVAL-02 | 28-01 | `conjure eval run` with pinned promptfoo, Node preflight, exit passthrough; audit decoupled | SATISFIED | `_eval_check_node`; `npx --yes promptfoo@0.121.14`; audit never calls npx; EVAL-02 tests PASS |
| EVAL-03 | 28-02 | `conjure eval --emit-workflow` generates PR-gate GitHub Actions workflow | SATISFIED (structural) | cmd_eval_emit_workflow; all YAML structural assertions pass; behavioral half is Human-UAT |
| EVAL-04 | 28-03 | `conjure audit --budget` context linter with thresholds and --porcelain JSON | SATISFIED | BUDGET_THRESHOLD_ERR=25000; overbudget exits 2; JSON shape valid; EVAL-04 tests PASS |
| EVAL-05 | 28-03 | `conjure audit` reports skill coverage gaps vs eval config | SATISFIED | `_eval_extract_skill_used`; `comm -23` diff; advisory note() only; EVAL-05 tests PASS |

All 5 EVAL requirements (EVAL-01 through EVAL-05) declared in plans map correctly to implementations. No orphaned requirements found in REQUIREMENTS.md for Phase 28.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| (none) | — | — | — | — |

No TBD/FIXME/XXX markers, no TODO/HACK/PLACEHOLDER, no stub implementations found in any modified file. All shellcheck gates pass (SC2164, SC2044, SC2034, SC2155 suppressed per project convention).

### Human Verification Required

#### 1. EVAL-03 Enforcement-Not-Disposition Behavioral Check

**Test:** In a test repo: (a) run `conjure eval --emit-workflow`, (b) deliberately break a hook binary so a PreToolUse hook exits 2 unconditionally, (c) set ANTHROPIC_API_KEY, (d) run `conjure eval run`.

**Expected:** The promptfoo eval suite FAILS — at minimum one assertion fails due to the broken hook behavior. The PR-gate workflow (with `fail-on-threshold: 80`) would block the PR.

**Why human:** Requires a live LLM API call via `npx --yes promptfoo@0.121.14` with a real ANTHROPIC_API_KEY. Cannot be automated in CI without network and credential access. The structural half (correct YAML: fail-on-threshold:80, repeat:3, repeat-min-pass:2, path filters) is verified — only the behavioral correctness of the enforcement gate requires a human to confirm.

### Gaps Summary

No automated gaps found. All 5 must-haves are VERIFIED against the actual codebase. The full test suite runs clean at 541 PASS / 0 FAIL.

The single human-needed item is the EVAL-03 enforcement-not-disposition behavioral guarantee — this was explicitly planned as a Manual-UAT obligation from the start (documented in 28-02-PLAN.md must_haves, 28-VALIDATION.md, and printed by `conjure eval --emit-workflow` at invocation time). It is not a gap in implementation; it is a test that requires live API credentials to verify.

---

_Verified: 2026-06-03T21:00:00Z_
_Verifier: Claude (gsd-verifier)_
