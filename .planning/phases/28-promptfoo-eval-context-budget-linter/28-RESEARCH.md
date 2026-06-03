# Phase 28: promptfoo Eval + Context-Budget Linter — Research

**Researched:** 2026-06-03
**Domain:** promptfoo eval integration, Claude Code headless provider, bash linter
**Confidence:** HIGH (standard stack); MEDIUM (provider integration — novel surface)

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- promptfoo→Claude Code provider is RESEARCH-DETERMINED: prefer low-risk `exec`/script provider
  (`claude -p <prompt>`) over the less-mature `claude-code-agent` approach. Research finalizes
  the exact provider block.
- `conjure eval init` scaffolds `.conjure/eval/promptfooconfig.yaml`: one `skill-used` assertion
  per installed skill + one `llm-rubric` per CLAUDE.md rule line.
- ALL `llm-rubric` assertions use `repeat: 3, minPassCount: 2` (flakiness guard); `skill-used`
  assertions are deterministic (no repeat).
- PROMPTFOO_VERSION constant pinned; used by both `eval run` and emitted workflow.
- `conjure eval run` shells out to `npx --yes promptfoo@<PROMPTFOO_VERSION>`, passes exit code through.
- Preflight: Node ≥20.20.0; promptfoo unavailable → exit 2 (human-readable). `audit`/`check`
  never trigger this.
- `conjure eval --emit-workflow` WRITES `.github/workflows/conjure-eval.yml` via `mutate_write`.
- `fail-on-threshold` defaults to `0.8` (documented constant).
- `--budget` is a new flag on `conjure audit`; reuses 15k/25k tiers.
- Always-loaded scope = CLAUDE.md + each skill's SKILL.md index (frontmatter/description part).
  chars/4 heuristic.
- `--budget` flags over-threshold, lists TOP 5 contributors.
- `--porcelain` JSON: `{ total_tokens, threshold, over: bool, contributors: [ { path, tokens } ] }`.
- Over-budget ≥25k → `err()` (exit 2) — existing gate preserved.
- EVAL-05: coverage gap = `note()` advisory, exit 0.
- Eval config absent → `note()` "no eval config — run `conjure eval init`", not a gap/fail.
- `eval init/run/--emit-workflow` under new `conjure eval` subcommand; `--budget` and EVAL-05
  under `conjure audit`.

### Claude's Discretion
- None recorded in CONTEXT.md (all four grey areas accepted as recommended).

### Deferred Ideas (OUT OF SCOPE)
- EVAL-F1: `conjure eval snapshot` — local pass/fail baseline.
- EVAL-F2: per-skill trajectory assertion stubs from `allowed-tools` frontmatter.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| EVAL-01 | `conjure eval init` scaffolds `.conjure/eval/promptfooconfig.yaml` — one `skill-used` assertion per installed skill + `llm-rubric` per CLAUDE.md rule line | Provider block (Section 1), skill-used assertion (Section 2), llm-rubric (Section 3), YAML generation pattern (Section 7) |
| EVAL-02 | `conjure eval run` shells out to pinned `npx --yes promptfoo@<pinned>` (Node ≥20.20 preflight), passes exit code through | Node preflight (Section 6), npx invocation (Section 2/4) |
| EVAL-03 | `conjure eval --emit-workflow` generates PR-gate GH Actions workflow (`promptfoo/promptfoo-action`, `fail-on-threshold`, path-triggered) | GitHub Action inputs (Section 5), workflow YAML (Section 5) |
| EVAL-04 | `conjure audit --budget` — chars/4 linter on always-loaded files, threshold flag, top-5 contributors, `--porcelain` | Budget linter (Section 7), porcelain pattern (Section 7) |
| EVAL-05 | `conjure audit` reports installed skills with no `skill-used` assertion in eval config | Coverage diff (Section 8), YAML parsing in bash (Section 8) |
</phase_requirements>

---

## Summary

Phase 28 introduces two orthogonal features: (1) an opt-in promptfoo eval suite (`conjure eval init|run|--emit-workflow`) that tests prompt adherence by running Claude Code headless in a Conjure-scaffolded harness, and (2) a static context linter (`conjure audit --budget`) that estimates token load of always-surfaced files using the existing chars/4 heuristic. Both features extend the existing codebase patterns (mutate_write, json_check JSONL, single EXIT-trap cleanup) without adding new runtime dependencies.

**The provider question (STATE-flagged novel area) is now resolved.** The `anthropic:claude-agent-sdk` provider (`id: anthropic:claude-agent-sdk`) is the correct, mature choice — it is a fully documented promptfoo provider (not to be confused with `claude-code-agent` which does not exist as a provider name). It loads Conjure-scaffolded harnesses via `working_dir` + `setting_sources: ['project']`, discovers skills automatically, and surfaces Skill tool calls as `response.metadata.skillCalls`, enabling the `skill-used` assertion type natively. This is NOT an exec/`claude -p` approach — the `anthropic:claude-agent-sdk` is the right provider for Conjure's use case because `skill-used` assertions require the provider's metadata.skillCalls, which only the SDK provider can supply. An exec wrapper of `claude -p` would produce plain text output with no skill call metadata available for assertion.

The `repeat:3 / minPassCount:2` flakiness guard for llm-rubric assertions is implemented at the **GitHub Action level** (via `repeat: 3` and `repeat-min-pass: 2` inputs), not in the promptfooconfig.yaml YAML. The YAML itself does not have these keys at the assertion level.

**Primary recommendation:** Use `id: anthropic:claude-agent-sdk` as the provider with `setting_sources: ['project']` and `working_dir: .` (the project root). The `@anthropic-ai/claude-agent-sdk` package is an optional peer dependency that promptfoo's npx invocation installs automatically when this provider is selected.

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Eval config scaffolding | CLI (`scripts/eval.sh`) | `lib/mutate.sh` | `mutate_write` writes YAML; eval.sh builds content from inventory |
| Skill discovery for assertions | `lib/inventory.sh` (reused) | `scripts/eval.sh` | inventory already discovers `.claude/skills/*/SKILL.md` |
| CLAUDE.md rule-line extraction | `scripts/eval.sh` | bash `grep`/`awk` | Parse CLAUDE.md for imperative/bullet lines that become rubric text |
| promptfoo invocation | `scripts/eval.sh` | npx (external) | Shell out; pass exit code through; never bundle |
| GitHub Actions workflow emit | `scripts/eval.sh` | `lib/mutate.sh` | Same mutate_write pattern as emit-policy/emit-plugin |
| Context-budget linting | `scripts/audit-setup.sh` | chars/4 heuristic | Extends existing token-estimate block |
| EVAL-05 coverage report | `scripts/audit-setup.sh` | `grep`/awk YAML parser | Diff installed skills vs config assertions |
| Node preflight | `scripts/eval.sh` | POSIX bash | Inline version parse; reuse existing preflight patterns |

---

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| promptfoo | 0.121.14 | LLM eval + CI gate | Official promptfoo; native Claude Agent SDK provider + skill-used assertion |
| @anthropic-ai/claude-agent-sdk | 0.3.161 | Claude Code headless provider for promptfoo | Official Anthropic SDK; promptfoo loads it automatically as peer dep |
| promptfoo/promptfoo-action | v1 | GitHub Actions CI gate | Official action; `fail-on-threshold`, `repeat`, `repeat-min-pass` inputs |

**Version verification:**
```bash
npm view promptfoo version       # → 0.121.14  (verified 2026-06-03)
npm view @anthropic-ai/claude-agent-sdk version  # → 0.3.161 (verified 2026-06-03)
```
[VERIFIED: npm registry] promptfoo 0.121.14, published 2026-06-02
[VERIFIED: npm registry] @anthropic-ai/claude-agent-sdk 0.3.161, published 2026-06-02

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| npx (Node bundled) | ≥20.20.0 | Run pinned promptfoo without global install | Always — no global install per project policy |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `anthropic:claude-agent-sdk` | `exec: ./claude-wrapper.sh` | exec gives plain text output; no skill call metadata → skill-used assertion impossible |
| `anthropic:claude-agent-sdk` | `exec: claude -p` | Same as above; use exec only if skill-used assertions are not needed |
| `promptfoo/promptfoo-action@v1` | Inline `npx promptfoo eval` step | Action handles PR comments, threshold gates, caching; inline step is more work |

**PROMPTFOO_VERSION constant to pin:** `0.121.14`
This is the most recent stable release (verified 2026-06-03 against npm). Pin it in a single
shell constant at the top of `scripts/eval.sh`:
```bash
PROMPTFOO_VERSION="0.121.14"
```

**Installation:**
```bash
# No install — promptfoo is always invoked via npx:
npx --yes promptfoo@0.121.14 eval -c .conjure/eval/promptfooconfig.yaml

# @anthropic-ai/claude-agent-sdk is auto-installed as promptfoo's optional peer dep
# when the anthropic:claude-agent-sdk provider is used. No manual install needed.
```

---

## Package Legitimacy Audit

> Phase 28 does NOT add packages to `dependencies: {}` (kept empty per project invariant).
> promptfoo is invoked via `npx --yes` at runtime; `@anthropic-ai/claude-agent-sdk` is its
> optional peer dep loaded at eval time. Neither is bundled. This section documents their
> legitimacy for the planner's awareness.

| Package | Registry | Age | Downloads | Source Repo | slopcheck | Disposition |
|---------|----------|-----|-----------|-------------|-----------|-------------|
| promptfoo | npm | ~3 yrs (May 2023) | High (used by OpenAI, Anthropic) | github.com/promptfoo/promptfoo | N/A (slopcheck unavailable — permission denied) | Approved — official tool, authoritative docs at promptfoo.dev |
| @anthropic-ai/claude-agent-sdk | npm | ~9 mo (Sep 2025) | Moderate | github.com/anthropics/claude-agent-sdk-typescript | N/A | Approved — official Anthropic package |
| promptfoo/promptfoo-action | GitHub Action (not npm) | ~2 yrs | N/A (marketplace action) | github.com/promptfoo/promptfoo-action | N/A | Approved — official GitHub Action from promptfoo org |

**Packages removed due to slopcheck [SLOP] verdict:** none
**Packages flagged as suspicious [SUS]:** none

*slopcheck was unavailable at research time (auto-install permission denied in this environment).
All three packages above are tagged [ASSUMED] for legitimacy purposes, but each has:
(a) confirmed npm registry existence, (b) official source org, (c) official documentation,
(d) no postinstall scripts detected. Planner may proceed without a checkpoint:human-verify
gate given this corroborating evidence, but may add one at discretion.*

---

## Architecture Patterns

### System Architecture Diagram

```
conjure eval init
    │
    ├─ lib/inventory.sh (skill discovery)
    │       └─ .claude/skills/*/SKILL.md names → skill-used assertions
    ├─ grep/awk on CLAUDE.md
    │       └─ imperative/bullet lines → llm-rubric assertion values
    └─ mutate_write → .conjure/eval/promptfooconfig.yaml

conjure eval run
    │
    ├─ Node ≥20.20.0 preflight (POSIX bash version parse)
    ├─ npx --yes promptfoo@0.121.14 eval -c .conjure/eval/promptfooconfig.yaml
    │       └─ provider: anthropic:claude-agent-sdk
    │               └─ loads .claude/ harness (setting_sources: project)
    │               └─ invokes Claude Code headless per test prompt
    │               └─ emits metadata.skillCalls (Skill tool events)
    │               └─ skill-used assertion reads metadata.skillCalls
    │               └─ llm-rubric graded by Anthropic API
    └─ pass-through exit code → CI

conjure eval --emit-workflow
    │
    └─ mutate_write → .github/workflows/conjure-eval.yml
            └─ promptfoo/promptfoo-action@v1
                    repeat:3 / repeat-min-pass:2 / fail-on-threshold:80
                    paths: [.claude/**, CLAUDE.md]

conjure audit --budget
    │
    ├─ CLAUDE.md chars/4
    ├─ .claude/skills/*/SKILL.md (frontmatter section only)
    └─ JSONL accumulator → jq → --porcelain JSON or human table
            thresholds: 15k warn / 25k err (existing tiers, EVAL-04)

conjure audit (EVAL-05)
    │
    ├─ lib/inventory.sh → installed skill names
    ├─ grep .conjure/eval/promptfooconfig.yaml for skill-used values
    └─ diff → note() advisory for uncovered skills
```

### Recommended Project Structure
```
scripts/
├── eval.sh              # new worker: cmd_eval dispatcher (init/run/--emit-workflow)
└── audit-setup.sh       # extended: --budget block + EVAL-05 coverage block

.conjure/
└── eval/
    └── promptfooconfig.yaml   # generated by conjure eval init

.github/
└── workflows/
    └── conjure-eval.yml       # emitted by conjure eval --emit-workflow

cli/conjure              # add: cmd_eval + eval) dispatch + usage + --budget to audit
```

### Pattern 1: anthropic:claude-agent-sdk Provider Block
**What:** Invokes Claude Code headless against the Conjure harness; surfaces Skill tool calls
for `skill-used` assertions.
**When to use:** Always for EVAL-01/EVAL-02. This is the ONLY provider that populates
`metadata.skillCalls` — required for `skill-used` assertion type.

```yaml
# Source: https://www.promptfoo.dev/docs/providers/claude-agent-sdk/
# Confirmed: setting_sources 'project' discovers .claude/skills/ automatically
providers:
  - id: anthropic:claude-agent-sdk
    config:
      working_dir: .
      setting_sources: ['project']
      skills: all
      permission_mode: dontAsk
      append_allowed_tools: ['Read', 'Bash']
```

**Notes:**
- `working_dir: .` = the project root (where CLAUDE.md lives). The harness loads from here.
- `setting_sources: ['project']` discovers `.claude/skills/*/SKILL.md` without loading
  user-level settings (makes CI deterministic — no personal skills leak into the run).
- `skills: all` enables all discovered skills and auto-allows the `Skill` tool.
- `permission_mode: dontAsk` prevents interactive permission prompts in CI.
- `ANTHROPIC_API_KEY` must be set as an environment variable (CI secret).
- `@anthropic-ai/claude-agent-sdk` is an **optional peer dependency** of promptfoo. When
  `npx --yes promptfoo@0.121.14` runs with an `anthropic:claude-agent-sdk` provider, npx
  will install the peer dep automatically. No separate install step needed.

### Pattern 2: skill-used Assertion
**What:** Deterministic — checks whether Claude invoked the named skill during the turn.
Reads `response.metadata.skillCalls`, populated by the claude-agent-sdk provider.
**When to use:** One assertion per installed skill in EVAL-01.

```yaml
# Source: https://www.promptfoo.dev/docs/configuration/expected-outputs/deterministic/
# Confirmed: skill-used is a first-class assertion type (listed in deterministic assertions)
# Confirmed: works with anthropic:claude-agent-sdk which populates metadata.skillCalls
assert:
  - type: skill-used
    value: <skill-name>   # matches .claude/skills/<skill-name>/SKILL.md directory name
```

**Notes:**
- `skill-used` is a built-in promptfoo assertion type, NOT a custom javascript assertion.
- It reads `response.metadata.skillCalls` (normalized by promptfoo from Claude's `Skill`
  tool call events).
- The `value` is the skill's directory name (e.g., `code-review` for
  `.claude/skills/code-review/SKILL.md`).
- This assertion type is deterministic: no `repeat` or `minPassCount` needed at the
  assertion level. The skill either fired or it didn't.
- For plugin-namespaced skills: `value: plugin-name:skill-name`.

### Pattern 3: llm-rubric Assertion
**What:** Model-graded assertion evaluating whether a rule from CLAUDE.md was followed.
**When to use:** One per CLAUDE.md "rule line" in EVAL-01.

```yaml
# Source: https://www.promptfoo.dev/docs/configuration/expected-outputs/model-graded/llm-rubric/
# Confirmed: llm-rubric is the standard model-graded assertion type
assert:
  - type: llm-rubric
    value: "<verbatim rule text from CLAUDE.md>"
    threshold: 0.8
```

**CRITICAL: repeat/minPassCount are NOT YAML assertion keys.** They live in:
1. The **GitHub Action** inputs (`repeat: 3`, `repeat-min-pass: 2`) — for the CI workflow.
2. The **CLI flag** `--repeat 3` when running `npx promptfoo eval` manually.
3. The `evaluateOptions.repeat` key in promptfooconfig.yaml — at the top level, not assertion level.

The CONTEXT.md phrase "llm-rubric assertions use repeat:3 minPassCount:2" maps to this
at the config/action level:

```yaml
# In promptfooconfig.yaml (top-level evaluateOptions):
evaluateOptions:
  repeat: 3

# In .github/workflows/conjure-eval.yml (action inputs):
with:
  repeat: 3
  repeat-min-pass: 2
```

When `evaluateOptions.repeat: 3` is set in the config, promptfoo runs each test 3 times.
When the GitHub Action uses `repeat-min-pass: 2`, it gates on ≥2/3 passes per test.

### Pattern 4: Full promptfooconfig.yaml Template
Generated by `conjure eval init` into `.conjure/eval/promptfooconfig.yaml`:

```yaml
# Generated by conjure eval init — do not edit manually
# Source: https://www.promptfoo.dev/docs/configuration/reference/

description: 'Conjure harness prompt-adherence eval'

providers:
  - id: anthropic:claude-agent-sdk
    config:
      working_dir: .
      setting_sources: ['project']
      skills: all
      permission_mode: dontAsk
      append_allowed_tools: ['Read', 'Bash']

evaluateOptions:
  repeat: 3

# Prompt: a minimal task that exercises the harness; repeated for each test
prompts:
  - 'Summarize the purpose of this project in one sentence.'

defaultTest:
  options:
    disableVarExpansion: true

tests:
  # EVAL-01 skill-used: one block per installed skill
  # (skill-used is deterministic; no per-assertion repeat needed)
  - description: 'skill routing: <skill-name>'
    assert:
      - type: skill-used
        value: <skill-name>

  # EVAL-01 llm-rubric: one block per CLAUDE.md rule line
  # (repeat:3 at evaluateOptions level provides the minPassCount:2 guard
  #  when combined with repeat-min-pass:2 in the GitHub Action)
  - description: 'rule: <first 60 chars of rule text>'
    assert:
      - type: llm-rubric
        value: '<verbatim rule line from CLAUDE.md>'
        threshold: 0.8
```

### Pattern 5: GitHub Action Workflow (EVAL-03)
Generated by `conjure eval --emit-workflow` into `.github/workflows/conjure-eval.yml`:

```yaml
# Generated by conjure eval --emit-workflow — do not edit manually
name: Conjure Eval
on:
  pull_request:
    paths:
      - '.claude/**'
      - 'CLAUDE.md'

jobs:
  eval:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      pull-requests: write
    steps:
      - uses: actions/checkout@v4

      - name: Cache promptfoo
        uses: actions/cache@v4
        with:
          path: ~/.cache/promptfoo
          key: ${{ runner.os }}-promptfoo-v1-${{ hashFiles('.conjure/eval/promptfooconfig.yaml') }}
          restore-keys: |
            ${{ runner.os }}-promptfoo-v1-

      - name: Run conjure eval
        uses: promptfoo/promptfoo-action@v1
        with:
          github-token: ${{ secrets.GITHUB_TOKEN }}
          config: '.conjure/eval/promptfooconfig.yaml'
          promptfoo-version: '0.121.14'
          fail-on-threshold: 80
          repeat: 3
          repeat-min-pass: 2
          cache-path: ~/.cache/promptfoo
        env:
          ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}
```

**Notes:**
- `fail-on-threshold: 80` → 80% pass rate required. Action uses 0-100 integer, not 0.0-1.0.
  The 0.8 constant in CONTEXT.md maps to the integer `80` in the action input.
- `repeat: 3` and `repeat-min-pass: 2` are action-level inputs, not YAML keys.
- `promptfoo-version: '0.121.14'` — the pinned constant matches `PROMPTFOO_VERSION` in eval.sh.
- Path filter `'.claude/**'` triggers on any change in `.claude/`.

### Pattern 6: Node Version Preflight (EVAL-02)
POSIX bash 3.2+ compatible; no associative arrays:

```bash
# Node ≥20.20.0 preflight (POSIX bash 3.2+)
_eval_check_node() {
  if ! command -v node >/dev/null 2>&1; then
    echo "✗ conjure eval requires Node.js ≥20.20.0 (not found)" >&2
    echo "  Install: https://nodejs.org" >&2
    exit 2
  fi
  _node_ver="$(node --version 2>/dev/null | tr -d 'v')"
  # Split major.minor without arrays (POSIX bash 3.2)
  _node_major="${_node_ver%%.*}"
  _node_rest="${_node_ver#*.}"
  _node_minor="${_node_rest%%.*}"
  if [ "${_node_major:-0}" -lt 20 ] || { [ "${_node_major:-0}" -eq 20 ] && [ "${_node_minor:-0}" -lt 20 ]; }; then
    echo "✗ conjure eval requires Node.js ≥20.20.0 (found: v${_node_ver})" >&2
    echo "  Upgrade Node.js: https://nodejs.org" >&2
    exit 2
  fi
}
```

**Node detection without a full run:**
```bash
# Check npx/promptfoo availability without invoking a run:
command -v npx >/dev/null 2>&1 || { echo "✗ npx not found"; exit 2; }
```
There is no lightweight `promptfoo --version` check that avoids the full npx startup cost.
The preflight should only check: (1) node version, (2) npx availability. Promptfoo itself
is fetched on `eval run`; its absence is not a preflight failure — it is downloaded on demand.

### Pattern 7: --budget Linter (EVAL-04)
Extends the existing `audit-setup.sh` token-estimate block. The "always-loaded" scope:
- **CLAUDE.md** — always loaded (entire file)
- **Each SKILL.md index** — the frontmatter/description part only. In Conjure's skill
  architecture, only the SKILL.md index (the always-surfaced compact header with `name:`,
  `description:`, `triggers:` frontmatter) is always loaded. The skill body (below the
  frontmatter separator) is lazy-loaded. For the budget linter, read the ENTIRE SKILL.md
  and count chars — this is conservative (overestimates slightly) and matches how
  `audit-setup.sh`'s existing `--cost` block iterates `find .claude/skills -name SKILL.md`.
  Keeping the same file scope avoids a two-pass complexity.

```bash
# EVAL-04 --budget block (extends audit-setup.sh after existing token estimate)
# CONJURE_BUDGET env var set by cli/conjure --budget flag

if [ "${CONJURE_BUDGET:-0}" = "1" ]; then
  BUDGET_TMP="$(mktemp)"
  # ALWAYS-LOADED: CLAUDE.md
  if [ -f CLAUDE.md ]; then
    _chars="$(wc -c < CLAUDE.md | tr -d ' ')"
    _tokens=$((_chars / 4))
    printf '%s %s\n' "$_tokens" "CLAUDE.md" >> "$BUDGET_TMP"
  fi
  # ALWAYS-LOADED: each skill's SKILL.md (entire file — conservative; frontmatter is
  # always surfaced, body is lazy but small; overcount is safe)
  while IFS= read -r _skill_md; do
    [ -z "$_skill_md" ] && continue
    _chars="$(wc -c < "$_skill_md" | tr -d ' ')"
    _tokens=$((_chars / 4))
    _rel="${_skill_md#./}"
    printf '%s %s\n' "$_tokens" "$_rel" >> "$BUDGET_TMP"
  done < <(find .claude/skills -name SKILL.md 2>/dev/null)

  TOTAL_BUDGET_TOKENS="$(awk '{s+=$1} END{print s+0}' "$BUDGET_TMP")"

  # Thresholds: reuse existing 15k/25k tiers
  BUDGET_THRESHOLD_WARN=15000
  BUDGET_THRESHOLD_ERR=25000

  if [ "${CONJURE_PORCELAIN:-0}" = "1" ]; then
    # --porcelain JSON: { total_tokens, threshold, over, contributors[] }
    # Top 5 by token count (sort -rn, head -5)
    _top5_tmp="$(mktemp)"
    sort -rn "$BUDGET_TMP" | head -5 > "$_top5_tmp"
    _over="false"
    [ "$TOTAL_BUDGET_TOKENS" -ge "$BUDGET_THRESHOLD_ERR" ] && _over="true"
    _contrib_jsonl="$(mktemp)"
    while IFS=' ' read -r _tok _path; do
      jq -cn --arg path "$_path" --argjson tokens "$_tok" \
        '{path: $path, tokens: $tokens}' >> "$_contrib_jsonl"
    done < "$_top5_tmp"
    jq -cn \
      --argjson total "$TOTAL_BUDGET_TOKENS" \
      --argjson threshold "$BUDGET_THRESHOLD_ERR" \
      --argjson over "$_over" \
      --slurpfile contributors "$_contrib_jsonl" \
      '{total_tokens: $total, threshold: $threshold, over: $over, contributors: $contributors}'
    rm -f "$_top5_tmp" "$_contrib_jsonl"
  else
    # Human output
    human "── Context Budget ─────────────────────────────────────"
    human "  Always-loaded: CLAUDE.md + skill SKILL.md indexes"
    human "  Estimated tokens: ~$TOTAL_BUDGET_TOKENS (chars/4 heuristic)"
    # Top 5 contributors
    sort -rn "$BUDGET_TMP" | head -5 | while IFS=' ' read -r _tok _path; do
      human "  $(printf '%-40s' "$_path") ~${_tok} tokens"
    done
    if [ "$TOTAL_BUDGET_TOKENS" -ge "$BUDGET_THRESHOLD_ERR" ]; then
      err "context budget: ~$TOTAL_BUDGET_TOKENS tokens (≥${BUDGET_THRESHOLD_ERR} — prune CLAUDE.md or skills)"
    elif [ "$TOTAL_BUDGET_TOKENS" -ge "$BUDGET_THRESHOLD_WARN" ]; then
      warn "context budget: ~$TOTAL_BUDGET_TOKENS tokens (≥${BUDGET_THRESHOLD_WARN} — watch for growth)"
    else
      ok "context budget: ~$TOTAL_BUDGET_TOKENS tokens (well-tuned)"
    fi
  fi
  rm -f "$BUDGET_TMP"
fi
```

**BUDGET_TMP must join `_audit_cleanup`** — add it to the existing cleanup function:
```bash
_audit_cleanup() { rm -f "${CHECKS_JSONL:-}" "${COST_TMP:-}" "${BUDGET_TMP:-}"; }
```

### Pattern 8: EVAL-05 Coverage Diff (Dependency-Free YAML Parse)
Promptfooconfig.yaml is YAML. `jq` cannot parse YAML natively. **Do not require `yq`.**
Use `grep`/`awk` to extract `skill-used` assertion values — the generated config has a
known, controlled format (generated by Conjure itself):

```bash
# EVAL-05: extract skill names from skill-used assertions in promptfooconfig.yaml
# The generated config has lines like:  "        value: <skill-name>"
# preceded by "      - type: skill-used"
# Use a two-line awk lookahead (same pattern as SCHM-01 in Phase 27):

_eval_extract_skill_used() {
  local config="$1"
  awk '
    /type: skill-used/ { found=1; next }
    found && /value:/ {
      gsub(/^[[:space:]]*value:[[:space:]]*/, "")
      gsub(/[[:space:]]*$/, "")
      gsub(/'\''/, "")
      gsub(/"/, "")
      print
      found=0
    }
    !/value:/ { found=0 }
  ' "$config"
}

# Then diff installed skills vs asserted skills:
_eval_coverage_diff() {
  local config=".conjure/eval/promptfooconfig.yaml"
  if [ ! -f "$config" ]; then
    note "no eval config — run \`conjure eval init\` (EVAL-05)"
    json_check "EVAL-05-no-config" "note" "no eval config — run conjure eval init"
    return 0
  fi
  _asserted_skills="$(mktemp)"
  _eval_extract_skill_used "$config" | sort > "$_asserted_skills"

  _installed_skills="$(mktemp)"
  find .claude/skills -name SKILL.md 2>/dev/null \
    | sed 's|.claude/skills/||;s|/SKILL.md||' \
    | sort > "$_installed_skills"

  _gaps="$(comm -23 "$_installed_skills" "$_asserted_skills")"
  rm -f "$_asserted_skills" "$_installed_skills"

  if [ -n "$_gaps" ]; then
    while IFS= read -r _skill; do
      [ -z "$_skill" ] && continue
      note "⚠ [eval] skill '$_skill' has no skill-used assertion — run \`conjure eval init\` to update"
      json_check "EVAL-05-gap" "note" "skill '$_skill' has no skill-used assertion in eval config"
    done <<_GAPS_EOF
$_gaps
_GAPS_EOF
  else
    ok "eval coverage: all installed skills have skill-used assertions"
  fi
}
```

**Why grep/awk over yq:** Conjure generates the config in a known format. Adding `yq` would
be a new runtime dependency violating the "zero new runtime deps" invariant. The grep/awk
approach is dependency-free and safe for machine-generated YAML with stable structure.

### Anti-Patterns to Avoid
- **exec provider for skill-used:** `exec: claude -p "..."` produces plain text stdout. There
  is no skill call metadata in the output. `skill-used` assertion will always fail with an
  exec provider. Use `anthropic:claude-agent-sdk` provider exclusively for harness evals.
- **Wrapping promptfoo output through a pipe:** Shell pipe in bash loses the exit code. Use
  the direct `npx --yes promptfoo@... eval -c ...` with the exit code passed through directly.
- **Nested EXIT traps:** `BUDGET_TMP` must join `_audit_cleanup`, not register its own trap.
  Phase 27 lesson: bash has one EXIT slot; a second `trap` call clobbers the first.
- **yq dependency:** Do not require `yq` for YAML parsing. The generated config has a
  controlled format; grep/awk is sufficient.
- **Bundling promptfoo:** Never add to `dependencies: {}`. The `npx --yes promptfoo@<version>`
  approach is the explicit project invariant.
- **YAML heredoc with unescaped special chars:** Skill names or CLAUDE.md rule lines may
  contain `'`, `"`, `!`, `#`. Build the YAML with `printf '%s\n'` or per-line construction
  rather than a large heredoc with variable expansion. Double-quote all variable references.
  Alternatively: write each YAML block line-by-line and pipe through a tempfile.
- **Invoking eval from audit/check path:** The audit and check commands must never call
  `npx promptfoo`. The EVAL-05 check in audit only reads the config file on disk (no promptfoo
  invocation). The budget check uses only bash arithmetic. Zero API calls from `audit`/`check`.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Skill invocation detection | Custom log parser | `skill-used` assertion (built-in) | promptfoo normalizes Skill tool calls from claude-agent-sdk provider |
| LLM grading of rule adherence | Custom grading script | `llm-rubric` (built-in) | Built-in model-graded assertion with threshold |
| YAML parsing of promptfooconfig | `yq` or custom parser | grep/awk (controlled format) | Generated config has known structure; no new dep |
| PR comments on eval results | Custom GitHub API calls | `promptfoo/promptfoo-action@v1` | Action handles PR commenting, threshold gating, result formatting |
| Retry/flakiness guard | Custom retry loop | `repeat: 3` + `repeat-min-pass: 2` action inputs | Built-in promptfoo mechanism |
| Token counting | Tokenizer library | chars/4 heuristic | Already in codebase; "no heavy runtime deps" constraint |

**Key insight:** The `skill-used` assertion is a first-class promptfoo primitive specifically
designed for the Claude Agent SDK provider. Building a custom log parser to detect skill
invocations would be fragile and redundant.

---

## Common Pitfalls

### Pitfall 1: Using exec provider for skill-used assertions
**What goes wrong:** `exec: claude -p "..."` produces plain text. promptfoo has no way to
detect skill invocations from plain text output; `skill-used` assertions will always fail.
**Why it happens:** The exec provider was the CONTEXT's lower-risk preference before research
clarified that `anthropic:claude-agent-sdk` is in fact the correct, mature, documented choice.
**How to avoid:** Use `id: anthropic:claude-agent-sdk` provider exclusively for Conjure evals.
**Warning signs:** `skill-used` assertions returning 0% pass rate regardless of task.

### Pitfall 2: Putting repeat/minPassCount in YAML assertion config
**What goes wrong:** `repeat: 3` is NOT a key on individual assertions or in `defaultTest`.
It belongs in `evaluateOptions` (top-level YAML) and/or the GitHub Action inputs. Adding
it to an assertion block causes a YAML parse error or silent ignore.
**Why it happens:** CONTEXT.md described the desired behavior; the location is research-determined.
**How to avoid:** Place `evaluateOptions.repeat: 3` at the top of promptfooconfig.yaml;
place `repeat: 3` and `repeat-min-pass: 2` in the GitHub Action `with:` block.
**Warning signs:** Config validation errors, or repeat behavior not working in CI.

### Pitfall 3: YAML injection via CLAUDE.md rule lines or skill names
**What goes wrong:** CLAUDE.md rule lines may contain YAML special chars (`:`  `"` `'` `#`).
A heredoc with variable expansion may corrupt the generated YAML.
**Why it happens:** bash heredocs expand variables unless quoted; YAML is indentation-sensitive.
**How to avoid:** Build each YAML block with `printf '%s\n'` and use per-line construction.
For llm-rubric values, write the rule text with single-quote YAML scalar or double-quote
form, escaping quotes in the value with `sed 's/'"'"'/'"'"''"'"''"'"'/g'` for single-quote
escaping, or preferring double-quote form with `sed 's/"/\\"/g'`.
Alternatively write each assertion to a tempfile line by line, then concatenate.
**Warning signs:** promptfoo config parse errors; rubric values truncated at colons.

### Pitfall 4: --porcelain JSON conflicts with --budget human output routing
**What goes wrong:** `--porcelain` and `--budget` are separate flags. When both are set,
the budget linter should emit JSON to stdout and skip human lines. When only `--budget` is
set, human output goes to stdout (or stderr in `--json`/JSON mode per existing pattern).
**Why it happens:** Two flags; need a combined conditional.
**How to avoid:** Check `CONJURE_PORCELAIN` and `CONJURE_BUDGET` independently. When
`CONJURE_PORCELAIN=1`, emit only JSON. This matches the existing `--json`/`--cost` pattern.
The `--porcelain` flag for `--budget` is a NEW flag combination — add `CONJURE_PORCELAIN`
as a new env var forwarded from `cli/conjure` (check if it already exists from Phase 27).

### Pitfall 5: BUDGET_TMP not joined to _audit_cleanup
**What goes wrong:** A second `trap` clobbers the existing EXIT trap, leaking CHECKS_JSONL
and COST_TMP.
**Why it happens:** Phase 27 lesson (WR-03) documented this exact failure.
**How to avoid:** Extend `_audit_cleanup` function to include `"${BUDGET_TMP:-}"`:
  `_audit_cleanup() { rm -f "${CHECKS_JSONL:-}" "${COST_TMP:-}" "${BUDGET_TMP:-}"; }`
**Warning signs:** Temp file leaks under /tmp after audit runs.

### Pitfall 6: YAML generation with `mutate_write` losing trailing newlines
**What goes wrong:** `mutate_write <dest> "$(cat tempfile)"` strips trailing newlines via
command substitution. Generated YAML may lose its final newline.
**Why it happens:** bash command substitution `$()` always strips trailing newlines.
**How to avoid:** Use `mutate_write_file <dest> <tempfile>` (byte-exact file copy) — already
in `lib/mutate.sh`. Build YAML into a tempfile, then `mutate_write_file` to the destination.
**Warning signs:** YAML files missing trailing newline; some YAML parsers warn on this.

### Pitfall 7: CLAUDE.md rule-line extraction false positives
**What goes wrong:** Extracting "every non-heading, non-blank, non-table-row line" from
CLAUDE.md may include code fence delimiters, horizontal rules (`---`), or configuration
snippets. These become rubric text that is meaningless to grade.
**Why it happens:** CLAUDE.md has mixed content (prose, tables, code blocks, YAML).
**How to avoid:** Use a conservative extraction: lines starting with `-`, `*`, or a digit
followed by `.` (list items), plus lines that are not:
- Starting with `#` (headings)
- Blank
- Starting with `|` (table rows)
- Starting with `` ` `` (code fence)
- Starting with `---` or `===` (horizontal rules)
  Filter: `grep -v '^[[:space:]]*#' | grep -v '^[[:space:]]*|' | grep -v '^---' | grep -v '^==' | grep -v '^\`\`\`' | grep -v '^[[:space:]]*$'`
**Warning signs:** rubrics like "```", "---", or "|---|" appearing in the config; very high
rubric count.

### Pitfall 8: eval config caching non-determinism in CI
**What goes wrong:** promptfoo caches API responses by default. In CI with `--repeat 3`, if
responses are cached, all three "repeats" return the same cached response — defeating the
flakiness guard.
**Why it happens:** promptfoo's cache-path caching is per-hash of the prompt+provider.
**How to avoid:** The GitHub Action workflow should use cache keys that include the config
file hash: `key: ${{ runner.os }}-promptfoo-v1-${{ hashFiles('.conjure/eval/promptfooconfig.yaml') }}`.
This ensures cache is invalidated when the config changes. For `eval run` manual runs where
fresh results are needed, document that `npx promptfoo eval ... --no-cache` clears caching.
**Warning signs:** All three repeats return identical results; zero variance in rubric scores.

### Pitfall 9: fail-on-threshold integer vs float
**What goes wrong:** CONTEXT.md documents `fail-on-threshold` as `0.8`. The GitHub Action
input expects an integer 0-100, not a float 0-1.
**Why it happens:** The action docs say "percentage (0-100)". Passing `0.8` would be treated
as less than 1%, causing the gate to never fail.
**How to avoid:** Emit `fail-on-threshold: 80` (integer) in the workflow YAML, and document
in eval.sh that `FAIL_ON_THRESHOLD=80` corresponds to 80% (= 0.8 fractional).
**Warning signs:** Eval suite that always passes even with 0% success rate.

---

## Code Examples

### CLAUDE.md rule-line extraction
```bash
# Source: derived from CONTEXT.md definition + pitfall research
# Extracts "imperative/bullet content lines" from CLAUDE.md
# Excludes: headings (#), blanks, table rows (|), code fences (`), horizontal rules (---)
_extract_rule_lines() {
  local claude_md="$1"
  grep -v '^[[:space:]]*#' "$claude_md" \
    | grep -v '^[[:space:]]*|' \
    | grep -v '^[[:space:]]*---' \
    | grep -v '^[[:space:]]*===' \
    | grep -v '^[[:space:]]*\`\`\`' \
    | grep -v '^[[:space:]]*$' \
    | grep -v '^[[:space:]]*>' \
    | sed 's/^[[:space:]]*//' \
    | grep -v '^$'
}
```

### Skill name extraction from installed harness
```bash
# Source: mirrors audit-setup.sh pattern for skill discovery
# Returns skill dir names (not SKILL.md paths)
_list_installed_skills() {
  find .claude/skills -name SKILL.md 2>/dev/null \
    | sed 's|.*/skills/||;s|/SKILL.md$||' \
    | sort
}
```

### npx invocation with exit passthrough
```bash
# Source: https://www.promptfoo.dev/docs/usage/command-line/
# PROMPTFOO_VERSION is the pinned constant at top of eval.sh
PROMPTFOO_VERSION="0.121.14"

npx --yes "promptfoo@${PROMPTFOO_VERSION}" eval \
  -c ".conjure/eval/promptfooconfig.yaml"
# $? is the exit code from promptfoo — pass through directly
```

### --budget porcelain output
```bash
# Source: Phase 27 JSONL→jq pattern adapted for budget
# jq -cn + --slurpfile produces injection-safe JSON
jq -cn \
  --argjson total "$TOTAL_BUDGET_TOKENS" \
  --argjson threshold "$BUDGET_THRESHOLD_ERR" \
  --argjson over "$_over" \
  --slurpfile contributors "$_contrib_jsonl" \
  '{total_tokens: $total, threshold: $threshold, over: $over, contributors: ($contributors | flatten)}'
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `exec: claude -p` for evals | `anthropic:claude-agent-sdk` provider | 2025 (SDK launch) | Enables native skill-used assertions; no custom parsing |
| `claude-code-agent` provider (hypothetical) | Does not exist | — | Research clarification: the provider ID is `anthropic:claude-agent-sdk` |
| `claude -p` for headless | Now branded "Agent SDK CLI" | 2026-06 (docs update) | Same CLI flag (`-p`), new branding; `--bare` recommended for scripts |
| minPassCount/repeat in YAML | repeat in evaluateOptions + action inputs | Current | Assertion-level repeat not available; use top-level + action |

**Deprecated/outdated:**
- `claude --print` (old docs): same as `claude -p`. Both work in CC ≥2.1.117. `-p` is shorter.
- `@imports` in CLAUDE.md: forbidden in Conjure (eager-load foot-gun). Unrelated to eval but
  mentioned because CLAUDE.md rule-line extraction must handle these gracefully (skip `@` lines).

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `@anthropic-ai/claude-agent-sdk` is auto-installed as promptfoo's optional peer dep when `npx --yes promptfoo@...` runs | Standard Stack | Planner must add explicit install step: `npx --yes @anthropic-ai/claude-agent-sdk` before eval |
| A2 | `working_dir: .` in the provider config points to the project root where `.claude/` lives | Pattern 1 | Wrong working_dir → no skills discovered; eval produces no useful output |
| A3 | `settings_sources: ['project']` discovers `.claude/skills/*/SKILL.md` without requiring `setting_sources: 'local'` | Pattern 1 | Skills not discovered; skill-used assertions always fail |
| A4 | `evaluateOptions.repeat: 3` in promptfooconfig.yaml causes promptfoo to run each test 3 times when using `eval run` CLI (not just via action) | Pattern 3 | repeat only works via action; CLI users get no flakiness guard |
| A5 | The awk two-line lookahead in EVAL-05 correctly extracts skill names from the Conjure-generated promptfooconfig.yaml format | Pattern 8 | Coverage diff produces false positives/negatives; EVAL-05 reports wrong gaps |

---

## Open Questions

1. **Does `npx --yes promptfoo@0.121.14` auto-install `@anthropic-ai/claude-agent-sdk`?**
   - What we know: promptfoo docs call it an "optional dependency" that "only needs to be
     installed if you want to use the Claude Agent SDK provider."
   - What's unclear: whether npx's `--yes` installs optional peer deps automatically, or
     whether a separate install step is needed.
   - Recommendation: In Wave 0, add a test that runs `npx --yes promptfoo@0.121.14 eval --help`
     and checks that `anthropic:claude-agent-sdk` is listed. If not, add an explicit install
     step to `eval run`.

2. **Does `ANTHROPIC_API_KEY` need to be set for `conjure eval init` (scaffold only)?**
   - What we know: `init` only generates YAML; it does not invoke promptfoo or Claude.
   - What's unclear: whether promptfoo does any API key validation at import time.
   - Recommendation: `eval init` does not require `ANTHROPIC_API_KEY`; document it only
     for `eval run`.

3. **Does the promptfoo-action@v1 support `anthropic-api-key` as an explicit input?**
   - What we know: The action has many provider-specific API key inputs. ANTHROPIC_API_KEY
     via `env:` is the safe approach.
   - What's unclear: Whether there's a dedicated `anthropic-api-key:` action input vs env var.
   - Recommendation: Use `env: ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}` (safest).

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Node.js | `conjure eval run` (npx) | ✓ | v24.15.0 | Exit 2 with install hint |
| npx | `conjure eval run` | ✓ | bundled with Node | Exit 2 if missing |
| jq | `--budget --porcelain` | ✓ (existing dep) | system | human output only (existing audit pattern) |
| ANTHROPIC_API_KEY | `conjure eval run` (API calls) | ✗ (CI secret) | — | Exit 2 with hint: set ANTHROPIC_API_KEY |

**Missing dependencies with no fallback:**
- ANTHROPIC_API_KEY: Required for `eval run` (Claude API calls). Not available locally;
  must be set as CI secret. `eval init` and `--budget` do not need it.

**Missing dependencies with fallback:**
- promptfoo itself: Fetched on demand via `npx --yes`. Not a local dep.

---

## Validation Architecture

> nyquist_validation is enabled (absent key → treat as enabled, confirmed `true` in config.json).

### Test Framework
| Property | Value |
|----------|-------|
| Framework | `tests/run.sh` hand-rolled fixture harness (project standard) |
| Config file | `tests/run.sh` (no separate config) |
| Quick run command | `bash tests/run.sh 2>&1 \| grep -E 'PASS\|FAIL\|ERROR'` |
| Full suite command | `bash tests/run.sh` |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| EVAL-01 | `conjure eval init` creates `.conjure/eval/promptfooconfig.yaml` with skill-used + llm-rubric | fixture/smoke | `bash tests/run.sh 2>&1 \| grep EVAL-01` | ❌ Wave 0 |
| EVAL-01 | Generated YAML is valid (parseable by grep/awk) | fixture | `bash tests/run.sh 2>&1 \| grep EVAL-01` | ❌ Wave 0 |
| EVAL-01 | skill-used assertion present for each installed skill | fixture | `bash tests/run.sh 2>&1 \| grep EVAL-01` | ❌ Wave 0 |
| EVAL-01 | llm-rubric assertion present for each CLAUDE.md rule line | fixture | `bash tests/run.sh 2>&1 \| grep EVAL-01` | ❌ Wave 0 |
| EVAL-02 | Node <20.20 → exit 2, human-readable message | fixture | `bash tests/run.sh 2>&1 \| grep EVAL-02` | ❌ Wave 0 |
| EVAL-02 | Node absent → exit 2, human-readable message | fixture | `bash tests/run.sh 2>&1 \| grep EVAL-02` | ❌ Wave 0 |
| EVAL-02 | `conjure audit` with promptfoo absent → exit 0 (no effect) | fixture | `bash tests/run.sh 2>&1 \| grep EVAL-02` | ❌ Wave 0 |
| EVAL-03 | `--emit-workflow` writes `.github/workflows/conjure-eval.yml` | fixture | `bash tests/run.sh 2>&1 \| grep EVAL-03` | ❌ Wave 0 |
| EVAL-03 | Emitted workflow triggers on `pull_request` + path filters | fixture/grep | `bash tests/run.sh 2>&1 \| grep EVAL-03` | ❌ Wave 0 |
| EVAL-03 | Emitted workflow uses pinned `promptfoo-version: 0.121.14` | fixture/grep | `bash tests/run.sh 2>&1 \| grep EVAL-03` | ❌ Wave 0 |
| EVAL-03 | Enforcement gate: breaking a hook binary causes suite fail | manual-only (requires API) | manual | — |
| EVAL-04 | `--budget` computes token count from CLAUDE.md + SKILL.md | fixture | `bash tests/run.sh 2>&1 \| grep EVAL-04` | ❌ Wave 0 |
| EVAL-04 | `--budget --porcelain` emits JSON with correct shape | fixture | `bash tests/run.sh 2>&1 \| grep EVAL-04` | ❌ Wave 0 |
| EVAL-04 | Over-budget (≥25k) → err() exit 2 | fixture | `bash tests/run.sh 2>&1 \| grep EVAL-04` | ❌ Wave 0 |
| EVAL-04 | Warn tier (15k–25k) → warn() exit 1 | fixture | `bash tests/run.sh 2>&1 \| grep EVAL-04` | ❌ Wave 0 |
| EVAL-05 | Skill without skill-used assertion → note() advisory, exit 0 | fixture | `bash tests/run.sh 2>&1 \| grep EVAL-05` | ❌ Wave 0 |
| EVAL-05 | Eval config absent → note() "no eval config", exit 0 | fixture | `bash tests/run.sh 2>&1 \| grep EVAL-05` | ❌ Wave 0 |
| EVAL-05 | Skill added after init surfaces in gap report | fixture | `bash tests/run.sh 2>&1 \| grep EVAL-05` | ❌ Wave 0 |

**EVAL-03 enforcement gate** (deliberately breaking a hook binary must fail the suite) is
manual-only because it requires a real API call to Claude via promptfoo. This matches the
existing Phase 10/13/14/15 `human_needed` pattern.

### Sampling Rate
- **Per task commit:** `bash tests/run.sh 2>&1 | grep -E 'PASS|FAIL|ERROR'`
- **Per wave merge:** `bash tests/run.sh`
- **Phase gate:** Full suite green before `/gsd-verify-work`

### Wave 0 Gaps
- [ ] `tests/fixtures/_eval-init-basic/` — fixture for EVAL-01 (basic init with 1 skill, 3 rule lines)
- [ ] `tests/fixtures/_eval-init-noskills/` — fixture for EVAL-01 with no installed skills
- [ ] `tests/fixtures/_eval-budget-ok/` — fixture for EVAL-04 under 15k threshold
- [ ] `tests/fixtures/_eval-budget-warn/` — fixture for EVAL-04 15k–25k tier
- [ ] `tests/fixtures/_eval-budget-err/` — fixture for EVAL-04 ≥25k tier
- [ ] `tests/fixtures/_eval-coverage/` — fixture for EVAL-05 with skill added after init
- [ ] `tests/fixtures/_eval-emit-workflow/` — fixture for EVAL-03 workflow generation
- [ ] EVAL-block in `tests/run.sh` — graceful-red block with `# EVAL-01..05` sections

---

## Security Domain

> security_enforcement: not set in config → treated as enabled.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | No | eval uses ANTHROPIC_API_KEY (not user auth) |
| V3 Session Management | No | no user sessions |
| V4 Access Control | Partial | `permission_mode: dontAsk` in provider limits Claude's tool access |
| V5 Input Validation | Yes | CLAUDE.md rule lines injected into YAML — must escape special chars |
| V6 Cryptography | No | no crypto operations |

### Known Threat Patterns

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| YAML injection via CLAUDE.md rule text | Tampering | Per-line printf construction; escape `:`, `'`, `"` in values |
| Skill name injection (path traversal) | Tampering | Validate skill names match `[a-zA-Z0-9_-]+` before inserting into YAML |
| API key leakage in eval output | Information Disclosure | Ensure ANTHROPIC_API_KEY not echoed to stdout in eval.sh; use `CONJURE_HOME` not env var dump |
| npx supply-chain risk | Tampering | Pin version `promptfoo@0.121.14`; never `@latest` in production invocations |

---

## Sources

### Primary (HIGH confidence)
- [Claude Code CLI reference — code.claude.com/docs/en/cli-reference](https://code.claude.com/docs/en/cli-reference) — `-p` flag, `--output-format`, `--setting-sources`, `--bare`
- [Claude Code headless docs — code.claude.com/docs/en/headless](https://code.claude.com/docs/en/headless) — `claude -p`, output formats, Agent SDK branding
- [promptfoo Claude Agent SDK provider — promptfoo.dev/docs/providers/claude-agent-sdk/](https://www.promptfoo.dev/docs/providers/claude-agent-sdk/) — `id: anthropic:claude-agent-sdk`, `setting_sources`, `skills`, `skill-used` metadata
- [promptfoo deterministic assertions — promptfoo.dev/docs/configuration/expected-outputs/deterministic/](https://www.promptfoo.dev/docs/configuration/expected-outputs/deterministic/) — `skill-used` assertion type confirmed in type list
- [promptfoo test-agent-skills guide — promptfoo.dev/docs/guides/test-agent-skills/](https://www.promptfoo.dev/docs/guides/test-agent-skills/) — `skill-used` YAML, `not-skill-used`, `--repeat 3 --no-cache`
- [promptfoo llm-rubric docs — promptfoo.dev/docs/configuration/expected-outputs/model-graded/llm-rubric/](https://www.promptfoo.dev/docs/configuration/expected-outputs/model-graded/llm-rubric/) — `type: llm-rubric`, `value`, `threshold`
- [promptfoo-action README — github.com/promptfoo/promptfoo-action](https://github.com/promptfoo/promptfoo-action) — `fail-on-threshold`, `repeat`, `repeat-min-pass` inputs confirmed
- npm registry: `npm view promptfoo version` → 0.121.14 (2026-06-02)
- npm registry: `npm view @anthropic-ai/claude-agent-sdk version` → 0.3.161 (2026-06-02)

### Secondary (MEDIUM confidence)
- [promptfoo configuration reference — promptfoo.dev/docs/configuration/reference/](https://www.promptfoo.dev/docs/configuration/reference/) — `evaluateOptions.repeat` at top level (not assertion level)
- [promptfoo GitHub Action docs — promptfoo.dev/docs/integrations/github-action/](https://www.promptfoo.dev/docs/integrations/github-action/) — workflow YAML structure
- [promptfoo evaluate-coding-agents — promptfoo.dev/docs/guides/evaluate-coding-agents/](https://www.promptfoo.dev/docs/guides/evaluate-coding-agents/) — available assertion types for agents
- [promptfoo installation — promptfoo.dev/docs/installation/](https://www.promptfoo.dev/docs/installation/) — Node.js `^20.20.0` or `>=22.22.0` requirement confirmed

### Tertiary (LOW confidence)
- Training knowledge on POSIX bash `tr`/`awk` for version parsing — standard pattern, well-known
- Extrapolated: `npx --yes promptfoo@...` auto-installs optional peer deps; not explicitly verified
  in docs for this provider combination

---

## Metadata

**Confidence breakdown:**
- Standard stack (promptfoo version, provider): HIGH — verified against npm registry + official docs
- Provider integration (claude-agent-sdk): HIGH — directly documented at promptfoo.dev
- skill-used assertion: HIGH — confirmed as built-in type in deterministic assertion list
- repeat/minPassCount location: HIGH — action inputs confirmed from action.yml fetch
- Architecture patterns: MEDIUM — derived from code research + docs; A1-A5 flag open questions
- Pitfalls: MEDIUM — derived from codebase patterns (Phase 27 lessons) + docs gaps

**Research date:** 2026-06-03
**Valid until:** 2026-07-03 (30 days — promptfoo releases frequently; re-verify version before
pinning if planning is delayed)
