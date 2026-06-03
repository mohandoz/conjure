---
phase: 28-promptfoo-eval-context-budget-linter
fixed_at: 2026-06-03T00:00:00Z
review_path: .planning/phases/28-promptfoo-eval-context-budget-linter/28-REVIEW.md
iteration: 1
findings_in_scope: 5
fixed: 5
skipped: 0
status: all_fixed
---

# Phase 28: Code Review Fix Report

**Fixed at:** 2026-06-03
**Source review:** .planning/phases/28-promptfoo-eval-context-budget-linter/28-REVIEW.md
**Iteration:** 1

**Summary:**
- Findings in scope: 5 (1 BLOCKER + 4 WARNINGs; Info findings out of scope)
- Fixed: 5
- Skipped: 0

Baseline before fixes: 536 PASS / 0 FAIL. After fixes: **541 PASS / 0 FAIL**
(5 new regression tests added, zero existing tests regressed). All touched files
pass `shellcheck -S error -e SC2164,SC2044,SC2034,SC2155`.

## Fixed Issues

### CR-01: `_yaml_escape_single` uses shell-style escaping, corrupting generated YAML (YAML injection)

**Files modified:** `scripts/eval.sh`, `tests/run.sh`
**Commit:** 6576ced
**Applied fix:** Replaced the shell-style `sed "s/'/'\\''/g"` escaper with the
correct YAML single-quoted-scalar escape `sed "s/'/''/g"` (apostrophes doubled,
not backslash-escaped). Added regression test `CR-01-yaml-apostrophe`: a CLAUDE.md
rule line `- Don't log PHI in plaintext.` now generates a config that
`python3 yaml.safe_load` parses and the rubric value round-trips verbatim
(structural grep fallback when python3/yaml is unavailable). Manually confirmed
the generated config parses: `value: '- Don''t log PHI in plaintext.'`.

### WR-01: EVAL-05 path-doubling — relative target silently reports "no eval config"

**Files modified:** `scripts/audit-setup.sh`, `tests/run.sh`
**Commit:** babad68
**Applied fix:** Changed `_eval_cfg="$TARGET/.conjure/eval/promptfooconfig.yaml"`
to the cwd-relative `_eval_cfg=".conjure/eval/promptfooconfig.yaml"` (cwd is
already `$TARGET` after the `cd` on line 19), matching the sibling
`find .claude/skills` call. Added regression test `WR-01-eval05-relative-target`
invoking audit with a relative target arg; pre-fix this misreported "no eval
config", now it reports full coverage. Manually verified: relative target prints
"eval coverage: all installed skills have skill-used assertions".

### WR-02: Node version gate diverges from `^20.20.0 || >=22.22.0` envelope

**Files modified:** `scripts/eval.sh`, `tests/run.sh`
**Commit:** 2bcba41
**Applied fix:** Replaced the single floor `>=20.20.0` with a two-range check
(POSIX bash arithmetic on major/minor): accept iff `(major==20 && minor>=20)` or
`(major==22 && minor>=22)` or `major>=23`. 21.x and 22.0–22.21 are now rejected
with a clear exit-2 message naming the envelope. Added regression test
`WR-02-node-envelope` exercising 20.19→reject, 20.20→accept, 21.5→reject,
22.21→reject, 22.22→accept via a stubbed `node`/`npx` on PATH (asserts on the
gate MESSAGE, since accepted versions exit 2 later on the missing config).
Manually verified all five boundaries match the expected envelope.

**Note:** This is a logic/algorithm change (version-range comparison). Tier 1+2
verification confirms syntax and the five tested boundaries; the developer should
confirm the range semantics match the intended promptfoo support matrix before
the phase proceeds. Status: **fixed: requires human verification**.

### WR-03: EVAL-05 skill-used awk extraction is order-fragile (false-negative gaps)

**Files modified:** `scripts/audit-setup.sh`, `tests/run.sh`
**Commit:** 1ec9ed4
**Applied fix:** Rewrote `_eval_extract_skill_used` awk to (a) skip `#` comment
lines, (b) anchor on `type: skill-used` and stay in-block (`in_assert`) until the
next list item `- `, tolerating intervening keys like `description:`, and
(c) capture the first `value:` within the block. Added regression test
`WR-03-skill-extract-robust` with a reordered block (description between type and
value) plus a commented `# value: 'ghost'` line; pre-fix s1 was falsely reported
as an unasserted gap and the comment leaked. Manually verified extraction now
yields only `s1`.

### WR-04: `--budget --porcelain` exit code is governed by unrelated audit warnings

**Files modified:** `scripts/audit-setup.sh`, `tests/run.sh`
**Commit:** 4d4627f
**Applied fix:** Per the review's guidance, the exit-code behaviour (holistic
audit-summary gate) is intentionally LEFT UNCHANGED — that is the established
contract. The contract is now made explicit: the porcelain budget JSON carries a
new `_comment` field stating that budget status is the `over` field and the
process exit code is the holistic audit verdict, not budget status. A code
comment documents the same. Added regression test `WR-04-porcelain-contract`
asserting the JSON has a `_comment` mentioning `over`. Manually verified the
field is emitted.

## Skipped Issues

None — all 5 in-scope findings were fixed.

The 3 Info findings (IN-01, IN-02, IN-03) were out of scope (`fix_scope:
critical_warning`) and were not attempted.

---

_Fixed: 2026-06-03_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
