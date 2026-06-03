---
phase: 28-promptfoo-eval-context-budget-linter
reviewed: 2026-06-03T17:12:52Z
depth: standard
files_reviewed: 3
files_reviewed_list:
  - scripts/eval.sh
  - scripts/audit-setup.sh
  - cli/conjure
findings:
  critical: 1
  warning: 4
  info: 3
  total: 8
status: issues_found
---

# Phase 28: Code Review Report

**Reviewed:** 2026-06-03T17:12:52Z
**Depth:** standard
**Files Reviewed:** 3
**Status:** issues_found

## Summary

Phase 28 adds the `conjure eval` worker (`scripts/eval.sh`: init / run / --emit-workflow)
and the `--budget`/`--porcelain` context-budget linter + EVAL-05 coverage-gap report in
`scripts/audit-setup.sh`, wired through `cmd_eval`/`cmd_audit` in `cli/conjure`.

Empirically verified and **passing**: the security-critical DECOUPLING invariant (no
`npx`/`promptfoo` reference anywhere in audit/check paths — the only `eval` token in
audit-setup.sh is the config-file path string; audit exit code is unaffected by promptfoo
presence); `--budget --porcelain` emits pure JSON on stdout and counts only `SKILL.md`
indexes (rules/*.md excluded); over-threshold (≥25k) preserves `err`→exit 2 in both human
and porcelain modes; single combined `_audit_cleanup` EXIT trap covers `BUDGET_TMP` with no
second trap registered; emit-workflow produces valid YAML with `fail-on-threshold: 80`
(integer, no float `0.8`), `repeat: 3`/`repeat-min-pass: 2`, and `${{ }}` expressions
left unexpanded; eval-run exit-code passthrough works (npx exit 7 → script exit 7) and
npx-absent exits 2 (not 127); `shellcheck -S error -e SC2164,SC2044,SC2034,SC2155` is clean;
`dependencies:{}` stays empty (promptfoo via npx only).

Two correctness defects found by tracing edge cases: a **YAML-injection BLOCKER** (the
single-quote escaper uses shell-style `'\''` instead of YAML `''` doubling, corrupting the
generated config whenever a CLAUDE.md rule line or skill name contains a `'`), and a
**WARNING** path-doubling bug in EVAL-05 that produces a silent false-negative ("no eval
config") for relative target arguments.

## Critical Issues

### CR-01: `_yaml_escape_single` uses shell-style escaping, corrupting generated YAML (YAML injection)

**File:** `scripts/eval.sh:85-87`
**Issue:** `_yaml_escape_single` escapes a single quote as `'\''` (the shell idiom for
breaking out of a single-quoted string). YAML single-quoted scalars do **not** use backslash
escaping — the only escape is a **doubled** single quote (`''`). The current sed produces
output that is valid *shell* but **invalid YAML**, so any CLAUDE.md rule line (or skill name)
containing an apostrophe corrupts `promptfooconfig.yaml` and breaks the entire eval run.

Empirically reproduced with a CLAUDE.md rule line `- Rule with 'single quotes' inside`:

```
  - description: 'rule: - Rule with '\''single quotes'\'' inside'   # generated
```

`python3 -c "import yaml; yaml.safe_load(open('promptfooconfig.yaml'))"` →
`yaml.parser.ParserError: while parsing a block mapping ... expected <block end>, but found '<scalar>'`.
Confirmed independently: YAML accepts `'it''s'` (doubling) but rejects `'it'\''s'` (shell-style).

This is the exact YAML-injection vector the phase brief called out. The `_validate_skill_name`
allowlist blocks `'` in skill names, but rule lines flow through unfiltered — apostrophes are
extremely common in prose CLAUDE.md content ("don't", "doesn't", "user's").

**Fix:** Replace shell-style escaping with YAML quote-doubling:
```bash
_yaml_escape_single() {
  # YAML single-quoted scalar: the ONLY escape is a doubled single quote.
  printf '%s' "$1" | sed "s/'/''/g"
}
```
After the fix, re-run the python `yaml.safe_load` check against a config generated from a
CLAUDE.md containing apostrophes, colons, and leading dashes to confirm it parses.

## Warnings

### WR-01: EVAL-05 path-doubling — relative target silently reports "no eval config"

**File:** `scripts/audit-setup.sh:512` (also affects any post-`cd` use of `$TARGET/...`)
**Issue:** Line 19 runs `cd "$TARGET"`, but `$TARGET` retains its original (possibly
**relative**) value. Line 512 then resolves `_eval_cfg="$TARGET/.conjure/eval/promptfooconfig.yaml"`
from *inside* the target, doubling the path (e.g. `evaltest/evaltest/.conjure/...`).

Reproduced: `audit-setup.sh evaltest` (relative) → "no eval config — run `conjure eval init`"
even though `evaltest/.conjure/eval/promptfooconfig.yaml` exists. With an **absolute** path
(`/tmp/evaltest`) EVAL-05 works and correctly flags the gap. The default from `cmd_audit`
is `$(pwd)` (absolute), so the common path is fine — but `conjure audit ./myrepo` (relative
user arg) silently disables the entire coverage-gap report and prints a misleading
"run conjure eval init" note. Same latent pattern exists in the pre-existing OVERLAY_MARKER
block (line 329), but EVAL-05 is new in this phase.

**Fix:** Reference the config relative to the now-current directory (cwd is already `$TARGET`),
matching the sibling `find .claude/skills` call on line 521 which correctly uses a cwd-relative path:
```bash
_eval_cfg=".conjure/eval/promptfooconfig.yaml"
```
Or canonicalize `TARGET` to an absolute path once, right after the `cd` on line 19.

### WR-02: Node version gate diverges from the requested `^20.20.0 || >=22.22.0` envelope

**File:** `scripts/eval.sh:17-18, 39-45`
**Issue:** The phase brief specifies the gate `^20.20.0 || >=22.22.0` — i.e. the 20.x line
from 20.20 up, **excluding** 21.x and excluding 22.0–22.21 (the documented promptfoo
Node-version support matrix). The implementation is a single floor `>=20.20.0`, so it
**accepts** 21.x and 22.21.0, which the requested envelope rejects. Verified by exercising the
comparison: `20.19.0→REJECT`, `20.20.0→ACCEPT`, `21.5.0→ACCEPT`, `22.21.0→ACCEPT`,
`22.22.0→ACCEPT`. The lower boundary (20.19 vs 20.20) is handled correctly; the gap is the
missing upper exclusion of the 21.x / early-22.x range.

If the single-floor `>=20.20.0` is intentional (simpler, and promptfoo may in practice run on
21.x), this is a doc/spec mismatch rather than a runtime bug — but it should be reconciled so
CI does not later "tighten" the gate and start rejecting environments the comment implies are
supported. **Fix:** either (a) update the gate to reject the `21 <= major` / `major==22 &&
minor<22` band to match the brief, or (b) update the comment and plan to record that a single
`>=20.20.0` floor was deliberately chosen over the `||`-range.

### WR-03: EVAL-05 skill-used awk extraction is order-fragile (false-negative gaps)

**File:** `scripts/audit-setup.sh:497-510`
**Issue:** `_eval_extract_skill_used` only captures `value:` on the line **immediately**
following `type: skill-used`; the `!/value:/ { found=0 }` clause resets state if any other key
(e.g. `description:`) is interleaved. A hand-edited or differently-ordered config:
```yaml
- type: skill-used
  description: routing check
  value: 's1'
```
yields **no** extraction, so `comm -23` reports `s1` as an unasserted gap even though it is
asserted — a false-negative coverage warning. Self-generated configs always emit `value:`
immediately after `type:`, so the happy path is fine; the risk is user-edited configs.
Separately, commented assertion lines leak into extraction (a `#   value: 'ghost'` line is
captured as `#   value: ghost`); the `#` prefix prevents it from matching a real skill name,
so it does not currently suppress a gap, but the extractor is matching comment text it should
ignore. Advisory-only (note, exit 0), so no CI impact — but the warning can mislead.

**Fix:** Anchor extraction to the assertion key regardless of intervening lines (track until
the next list item `- ` or dedent), and skip comment lines:
```bash
awk '
  /^[[:space:]]*#/ { next }
  /type:[[:space:]]*skill-used/ { in_assert=1; next }
  in_assert && /value:[[:space:]]*/ {
    sub(/^[[:space:]]*value:[[:space:]]*/, ""); gsub(/^['"'"'"]|['"'"'"][[:space:]]*$/, ""); print; in_assert=0
  }
  /^[[:space:]]*-[[:space:]]/ { in_assert=0 }
' "$1"
```

### WR-04: `--budget --porcelain` exit code is governed by unrelated audit warnings

**File:** `scripts/audit-setup.sh:660-674` (interaction with budget porcelain path)
**Issue:** In `--budget --porcelain` mode the script still runs the full audit and returns the
summary gate exit code: `[ "$FAIL" -gt 0 ] && exit 2; [ "$WARN" -gt 0 ] && exit 1`. So a
machine consumer that parses the budget JSON and also inspects `$?` sees **exit 1** purely
because of unrelated warnings (missing `.claudeignore`, missing `docs/`, etc.) even when the
budget itself is well under threshold (`over: false`). Verified: a fixture with `over:false`
returned exit 1. The JSON `over` field is the authoritative budget signal, but the exit code
conflates budget status with whole-harness health, which is surprising for a scoped
`--budget --porcelain` query and can produce false CI failures if a caller gates on the exit
code rather than the `over` field.

**Fix:** Document explicitly that `--budget --porcelain` consumers must branch on the JSON
`over` field, not the process exit code (the exit code remains the holistic audit verdict).
If a budget-scoped exit code is intended, gate it solely on `TOTAL_BUDGET_TOKENS` vs the
thresholds rather than the global `FAIL`/`WARN` counters.

## Info

### IN-01: `cmd_eval` accepts only the first subcommand and silently ignores extras

**File:** `cli/conjure:555-568`
**Issue:** The `while`/`case` loop assigns `subcmd="$1"` on each match, so `conjure eval init run`
silently uses `run` (last wins) with no error. Minor UX sharp edge; low impact since the
dispatch downstream is single-subcommand.
**Fix:** Reject a second subcommand token, or document first-wins/last-wins behavior.

### IN-02: `_extract_rule_lines` filters are heuristic and may include/exclude unintended lines

**File:** `scripts/eval.sh:54-66`
**Issue:** Rule extraction strips headings, tables, rules, fences, blockquotes, and `@`-lines
via stacked greps. Content *inside* a fenced code block (between ``` fences) is not tracked
statefully, so code-block body lines that don't start with an excluded marker become
llm-rubric assertions. For the project's own CLAUDE.md this is acceptable, but the rubric set
can include noise lines. Not a correctness defect.
**Fix:** Consider tracking fence state to drop code-block bodies, or document that only
prose/bullet lines should live outside fences in CLAUDE.md.

### IN-03: `cmd_eval` `--emit-workflow` arg can be shadowed by target parsing

**File:** `cli/conjure:557-564`
**Issue:** `--emit-workflow` is matched as a subcommand in the `case`, but any unrecognized
token falls through to `target="$1"`. A user typo like `conjure eval emit-workflow` (missing
`--`) is silently treated as the *target directory* `emit-workflow`, then fails the `[ -z
"$subcmd" ]` guard with a generic usage message. Cosmetic; the guard does catch it.
**Fix:** Emit a more specific "unknown eval subcommand" message for non-target-looking tokens.

---

_Reviewed: 2026-06-03T17:12:52Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
