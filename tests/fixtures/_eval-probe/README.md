# Eval Integration Probe — A1/A2/A3 Resolution

This directory documents the resolution of three open questions from
Phase 28 research about the `anthropic:claude-agent-sdk` provider integration.
The probe is SKIPPED in automated CI (no live promptfoo invocation in tests/run.sh).

---

## A1 — Auto-install of @anthropic-ai/claude-agent-sdk

**Question:** Does `npx --yes promptfoo@0.121.14` auto-install `@anthropic-ai/claude-agent-sdk`
as an optional peer dependency when the `anthropic:claude-agent-sdk` provider is selected?

**Resolution:** [ASSUMED] — auto-install not explicitly verified in promptfoo docs for the
npx + optional peer dep combination. Behavioral verification requires:
- A live network connection
- Node.js >= 20.20.0
- promptfoo 0.121.14 installed or accessible via npx
- The Anthropic API credential set in the environment

**Wave 0 disposition:** This probe is DOCUMENTATION-ONLY in Wave 0. No live promptfoo
invocation is made in tests/run.sh. The probe result would be written to
tests/fixtures/_eval-probe/A1-result.txt if the probe were run.

**If auto-install fails at runtime:** scripts/eval.sh must surface a human-readable
error message and exit 2. The eval run path should detect whether the SDK is available
via `node -e "require('@anthropic-ai/claude-agent-sdk')"` and emit:

  conjure eval: @anthropic-ai/claude-agent-sdk not found
    Run: npm install --no-save @anthropic-ai/claude-agent-sdk@0.3.161
    Or upgrade promptfoo: npx --yes promptfoo@0.121.14 (auto-installs peer deps)

**CI gate:** SKIPPED — requires the Anthropic API credential (not available in automated CI).

---

## A2 — working_dir: . points to project root

**Question:** Does `working_dir: .` in the provider config correctly point to the
project root where `.claude/` and `CLAUDE.md` live?

**Resolution:** VERIFIED BY YAML STRUCTURE ONLY — the golden config
`tests/fixtures/_eval/expected-promptfooconfig.yaml` encodes `working_dir: .`
as expected by the promptfoo claude-agent-sdk provider docs.

**Live correctness:** Whether skills are actually discovered with a real Claude SDK
run is Manual-Only verification (requires the Anthropic API credential and a real
promptfoo run). See VALIDATION.md for the manual verification procedure.

**Automated gate:** The EVAL-01 fixture test verifies the generated YAML contains
`working_dir: .` — not live behavior.

---

## A3 — setting_sources: ['project'] discovers .claude/skills/

**Question:** Does `setting_sources: ['project']` discover `.claude/skills/*/SKILL.md`
without requiring `setting_sources: 'local'`?

**Resolution:** VERIFIED BY YAML STRUCTURE ONLY — same disposition as A2. The golden
config `tests/fixtures/_eval/expected-promptfooconfig.yaml` captures the correct
`setting_sources: ['project']` configuration as documented in
https://www.promptfoo.dev/docs/providers/claude-agent-sdk/

**Live correctness:** Actual skill discovery behavior during a real Claude run is
Manual-Only. The fixture tests validate YAML structure only.

**Note on setting_sources vs setting-sources:** The provider config uses `setting_sources`
(snake_case) as documented in the promptfoo provider reference. This matches the
`--setting-sources project` CLI flag behavior.

---

## Probe Environment Requirements

To run the live probe (Manual-Only):

1. Node.js >= 20.20.0: `node --version`
2. npx available: `command -v npx`
3. Set the Anthropic API credential in your environment
4. Internet access for npx to fetch promptfoo@0.121.14

Run from within `tests/fixtures/_eval/harness/`:

```sh
cd tests/fixtures/_eval/harness
npx --yes promptfoo@0.121.14 eval \
  -c .conjure/eval/promptfooconfig.yaml \
  --no-cache --verbose
```

Expected: promptfoo installs @anthropic-ai/claude-agent-sdk automatically,
discovers audit-helper and code-review skills, runs the eval prompt, and
outputs skill-used assertion results.

---

## Automated CI Disposition

All three open questions (A1/A2/A3) are resolved at the YAML structure level
in Wave 0. Live behavioral verification is deferred to manual testing.
The `tests/run.sh` EVAL block does NOT invoke promptfoo — it only tests
scripts/eval.sh (the Conjure CLI wrapper) against fixture inputs.
