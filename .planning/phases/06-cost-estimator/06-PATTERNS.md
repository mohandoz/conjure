# Phase 6: Cost Estimator - Pattern Map

**Mapped:** 2026-05-25
**Files analyzed:** 5 (2 modified, 2 created, 1 verified)
**Analogs found:** 5 / 5

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `cli/conjure` (cmd_audit) | CLI dispatcher | request-response | `cli/conjure` cmd_init (lines 52-89) | exact — same file, same flag-parsing pattern |
| `scripts/audit-setup.sh` (cost section) | script / utility | batch, request-response | `scripts/audit-setup.sh` lines 122-130 (token estimate block) | exact — extends existing block in same file |
| `lib/prices.json` | config / data | — | `lib/mutate.sh` (lib/ convention only) | directory-convention match |
| `lib/exact-count.mjs` | utility / Node.js ESM | request-response | `templates/hooks-nodejs/session-start-context.mjs` | role-match — same Node ESM + safe() wrapper pattern |
| `tests/run.sh` | test | batch | `tests/run.sh` lines 93-102 (audit self-test block) | exact — extend same file, same pass/fail helpers |

---

## Pattern Assignments

### `cli/conjure` — modify `cmd_audit()` (lines 113-117)

**Analog:** `cli/conjure` `cmd_init()` (lines 52-89)

**Flag-parsing loop pattern** (lines 54-63):
```bash
cmd_init() {
  local mode="existing" profile="" dryrun=0 target="$(pwd)"
  while [ $# -gt 0 ]; do
    case "$1" in
      new|existing|migrate) mode="$1" ;;
      --profile=*)          profile="${1#--profile=}" ;;
      --dry-run)            dryrun=1 ;;
      --help|-h)            grep -A3 '^  conjure init' <<<"$(usage)"; return 0 ;;
      *)                    target="$1" ;;
    esac
    shift
  done
```

**Env-var prefix pass-through pattern** (line 77):
```bash
  CONJURE_HOME="$CONJURE_HOME" DRY_RUN="$dryrun" bash "$CONJURE_HOME/scripts/init-project.sh" "$mode" "$target"
```

**New `cmd_audit()` must replicate this exactly** — local vars `do_cost` and `do_exact`, while/case loop, then env-var prefix on the bash invocation:
```bash
cmd_audit() {
  local target="$(pwd)" do_cost=0 do_exact=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --cost)    do_cost=1 ;;
      --exact)   do_exact=1 ;;
      --help|-h) grep -A3 '^  conjure audit' <<<"$(usage)"; return 0 ;;
      *)         target="$1" ;;
    esac
    shift
  done
  cmd_preflight || return 1
  CONJURE_HOME="$CONJURE_HOME" CONJURE_COST="$do_cost" CONJURE_EXACT="$do_exact" \
    bash "$CONJURE_HOME/scripts/audit-setup.sh" "$target"
}
```

**Current cmd_audit** (lines 113-117) — the entire function to replace:
```bash
cmd_audit() {
  local target="${1:-$(pwd)}"
  cmd_preflight || return 1
  bash "$CONJURE_HOME/scripts/audit-setup.sh" "$target"
}
```

---

### `scripts/audit-setup.sh` — cost section (insert after line 139)

**Analog:** `scripts/audit-setup.sh` token estimate block (lines 122-130) + skills loop (lines 51-65)

**Token estimate block to extend from** (lines 122-130):
```bash
# Total token estimate
if [ -d .claude ]; then
  TOTAL_CHARS=$(find .claude -type f \( -name '*.md' -o -name '*.json' \) -exec cat {} + 2>/dev/null | wc -c | tr -d ' ')
  EST_TOKENS=$((TOTAL_CHARS / 4))
  if [ "$EST_TOKENS" -lt 15000 ]; then ok ".claude/ token estimate: ~$EST_TOKENS (well-tuned)"
  elif [ "$EST_TOKENS" -lt 25000 ]; then warn ".claude/ token estimate: ~$EST_TOKENS (acceptable, watch for growth)"
  else err ".claude/ token estimate: ~$EST_TOKENS (over budget — prune)"
  fi
fi
```
`TOTAL_CHARS` and `EST_TOKENS` are already set here. The cost section reads them directly — no recomputation.

**Output helpers** (lines 14-17):
```bash
note() { echo "  $1"; }
ok()   { note "✓ $1"; PASS=$((PASS+1)); }
warn() { note "⚠ $1"; WARN=$((WARN+1)); }
err()  { note "✗ $1"; FAIL=$((FAIL+1)); }
```
CRITICAL: The cost section runs AFTER the summary line (line 135). Never call `ok()`/`warn()`/`err()` inside the cost section — they would increment counters that are already printed. Use `echo` or `printf` directly.

**jq usage pattern** (line 86-87) — use this form for prices.json reads:
```bash
if command -v jq >/dev/null 2>&1; then
  if jq empty .claude/settings.json 2>/dev/null; then
```

**Skills find loop pattern** (lines 51-65) — for the per-file breakdown loop:
```bash
while IFS= read -r skill; do
  name=$(basename "$(dirname "$skill")")
  LINES=$(wc -l < "$skill" | tr -d ' ')
  ...
done < <(find .claude/skills -name SKILL.md)
```

**Summary and exit block** (lines 132-139) — cost section inserts BEFORE the final exits but AFTER the separator:
```bash
# Summary
echo
echo "─────────────────────────────────────"
echo "PASS: $PASS    WARN: $WARN    FAIL: $FAIL"
echo "─────────────────────────────────────"
[ "$FAIL" -gt 0 ] && exit 2
[ "$WARN" -gt 0 ] && exit 1
exit 0
```
Insert cost block between the separator echo and the `[ "$FAIL" -gt 0 ]` guard.

**CONJURE_HOME self-derivation pattern** — from `cli/conjure` line 24 (same derivation idiom):
```bash
: "${CONJURE_HOME:="$(cd "$(dirname "$0")/.." && pwd)"}"
```
Place at the top of the cost section block, inside the `if [ "${CONJURE_COST:-0}" = "1" ]` guard.

**Float arithmetic pattern** — never use bash `$((...))` for dollars. Use awk:
```bash
TOTAL_COST=$(awk "BEGIN {printf \"%.4f\", $EST_TOKENS * $PRICE_INPUT / 1000000}")
```

**Per-file char count pattern** — matches existing wc -c usage (lines 124-125):
```bash
chars=$(wc -c < "$file" | tr -d ' ')
tokens=$((chars / 4))
```

---

### `lib/prices.json` — new file

**Analog:** `lib/mutate.sh` — establishes lib/ as shared helpers/data; no JSON file exists yet.

**Directory convention** (`lib/mutate.sh` line 1):
```bash
#!/usr/bin/env bash
# lib/mutate.sh — sourced mutation chokepoint for Conjure.
```
Same `lib/` directory, same pattern of a single-purpose shared resource.

**JSON structure** (from RESEARCH.md Pattern 3):
```json
{
  "models": [
    {
      "model":            "claude-haiku-4-5",
      "display_name":     "Claude Haiku 4.5",
      "pricing_date":     "2026-05",
      "input_per_mtok":   1,
      "output_per_mtok":  5,
      "band_pct":         20
    },
    {
      "model":            "claude-sonnet-4-6",
      "display_name":     "Claude Sonnet 4.6",
      "pricing_date":     "2026-05",
      "input_per_mtok":   3,
      "output_per_mtok":  15,
      "band_pct":         20
    },
    {
      "model":            "claude-opus-4-7",
      "display_name":     "Claude Opus 4.7",
      "pricing_date":     "2026-05",
      "input_per_mtok":   5,
      "output_per_mtok":  25,
      "band_pct":         20
    }
  ],
  "default_model": "claude-sonnet-4-6"
}
```

**jq read pattern** (from RESEARCH.md Example 3 + existing audit-setup.sh line 86):
```bash
MODEL=$(jq -r '.default_model' "$PRICE_FILE")
PRICE_INPUT=$(jq -r --arg m "$MODEL" '.models[] | select(.model==$m) | .input_per_mtok' "$PRICE_FILE")
PRICING_DATE=$(jq -r --arg m "$MODEL" '.models[] | select(.model==$m) | .pricing_date' "$PRICE_FILE")
BAND_PCT=$(jq -r --arg m "$MODEL" '.models[] | select(.model==$m) | .band_pct' "$PRICE_FILE")
```

This file must also be registered in the JSON validity loop in `tests/run.sh` (lines 37-43):
```bash
if command -v jq >/dev/null 2>&1; then
  while IFS= read -r json; do
    if jq empty "$json" >/dev/null 2>&1; then pass "json valid: $json"
    else fail "json INVALID: $json"
    fi
  done < <(find templates .claude-plugin -name '*.json' 2>/dev/null)
fi
```
Note: the current find scope (`templates .claude-plugin`) does not include `lib/`. Either extend the find to include `lib/` or add an explicit JSON validity check for `lib/prices.json`.

---

### `lib/exact-count.mjs` — new file

**Analog:** `templates/hooks-nodejs/session-start-context.mjs` (lines 1-41)

**Shebang + module-level imports pattern** (lines 1-8):
```javascript
#!/usr/bin/env node
// Cross-platform SessionStart hook — inject dynamic context.
// Output to stdout becomes additional session context. Must finish in <2s.

import { execSync, spawnSync } from 'node:child_process';
import { existsSync, statSync } from 'node:fs';
import path from 'node:path';
```
Copy: `#!/usr/bin/env node`, `node:` prefix on stdlib imports, single-line comment header.

**Safe wrapper pattern** (lines 9-12 of session-start-context.mjs):
```javascript
const safe = (cmd) => {
  try { return execSync(cmd, { stdio: ['ignore', 'pipe', 'ignore'] }).toString().trim(); }
  catch { return ''; }
};
```
For `lib/exact-count.mjs`, adapt to file-reading: `const safe = (fn) => { try { return fn(); } catch { return ''; } };`

**process.argv input pattern** (from post-edit-format.mjs line 10):
```javascript
const file = process.argv[2] || process.env.CLAUDE_FILE_PATH;
if (!file || !existsSync(file)) process.exit(0);
```
For exact-count.mjs: `const target = process.argv[2] || process.cwd();`

**stdout output + exit pattern** (session-start-context.mjs lines 30-41):
```javascript
process.stdout.write(`## Dynamic session context\n...`);
process.exit(0);
```
For exact-count.mjs: `process.stdout.write(String(response.input_tokens) + "\n"); process.exit(0);`

**Error handling pattern** — destructive.mjs (lines 32-36) shows clean stderr + exit for failures:
```javascript
const reason = (msg) => {
  process.stderr.write(JSON.stringify({...}) + '\n');
  process.exit(2);
};
```
For exact-count.mjs, use a simpler advisory form: wrap the SDK call in try/catch, write advisory to stderr, exit non-zero so audit-setup.sh detects failure and falls back.

**SDK import and countTokens call** (from RESEARCH.md Pattern 4 — verified against SDK 0.98.0):
```javascript
import Anthropic from "@anthropic-ai/sdk";
// ...
const client = new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY });
const response = await client.messages.countTokens({
  model: "claude-sonnet-4-6",
  messages: [{ role: "user", content }],
});
process.stdout.write(String(response.input_tokens) + "\n");
process.exit(0);
```
Note: stable namespace `client.messages.countTokens` (NOT `client.beta.messages.countTokens`).

**SDK absence handling** — must catch MODULE_NOT_FOUND before any SDK call and print advisory:
```javascript
// Check before import attempt — wrap dynamic import or catch at top level
try {
  const { default: Anthropic } = await import("@anthropic-ai/sdk");
  // ... SDK call
} catch (e) {
  if (e.code === "ERR_MODULE_NOT_FOUND" || e.code === "MODULE_NOT_FOUND") {
    process.stderr.write("[--exact] @anthropic-ai/sdk not found — install with: npm install @anthropic-ai/sdk\n");
    process.exit(1);
  }
  throw e;
}
```

---

### `tests/run.sh` — extend with cost section tests (do not break existing)

**Analog:** `tests/run.sh` audit self-test block (lines 93-102)

**Audit self-test pattern to extend from** (lines 93-102):
```bash
echo
echo "▸ Audit script self-test (must not crash)"
bash scripts/audit-setup.sh "$CONJURE_HOME" >/dev/null 2>&1
rc=$?
if [ "$rc" -le 2 ]; then pass "audit-setup.sh ran (rc=$rc, expected 0|1|2)"
else fail "audit-setup.sh crashed (rc=$rc)"
fi
```

**Grep-based assertion pattern** (lines 163-168, template lint section):
```bash
if grep -q 'bash .claude/hooks/' templates/settings.json.tmpl 2>/dev/null; then
  fail "settings.json.tmpl: bash hook commands present (SAFE-03 regression)"
else pass "settings.json.tmpl: no bash hook commands"
fi
```
Copy this form for cost section assertions: run audit with `CONJURE_COST=1`, capture output, grep for `Cost Estimate` header and the label format `±20%` and `prices:`.

**Fixture + sandbox pattern** (lines 253-266):
```bash
for fx in "$CONJURE_HOME/tests/fixtures"/[^_]*/; do
  prof=$(basename "$fx")
  sandbox_setup "$fx"
  trap 'rm -rf "$SANDBOX_DIR"' EXIT
  AUDIT_OUT="$(bash "$CONJURE_HOME/scripts/audit-setup.sh" "$SANDBOX_DIR" 2>&1)"
  AUDIT_RC=$?
  ...
done
```
For the cost section test, run `CONJURE_COST=1 bash "$CONJURE_HOME/scripts/audit-setup.sh" "$SANDBOX_DIR"` and grep the output.

**Section header pattern** (lines 24, 47, 63, etc.):
```bash
echo
echo "▸ Cost estimator tests (COST-01, COST-02, COST-03)"
```

---

## Shared Patterns

### CONJURE_HOME Environment Variable
**Source:** `cli/conjure` line 24 (definition) and `tests/run.sh` line 6 (self-derivation)
**Apply to:** `scripts/audit-setup.sh` cost section, `lib/exact-count.mjs`

In `cli/conjure` (already set at top level):
```bash
CONJURE_HOME="$(cd "$(dirname "$0")/.." && pwd)"
```

In `scripts/audit-setup.sh` cost section (self-derivation fallback — POSIX `:=` assignment):
```bash
: "${CONJURE_HOME:="$(cd "$(dirname "$0")/.." && pwd)"}"
```

### jq Availability Guard
**Source:** `scripts/audit-setup.sh` lines 86-87
**Apply to:** cost section in `scripts/audit-setup.sh`
```bash
if command -v jq >/dev/null 2>&1; then
  if jq empty .claude/settings.json 2>/dev/null; then
```
For cost section: `if ! command -v jq >/dev/null 2>&1; then` echo advisory and skip entire cost section.

### node Availability Guard
**Source:** `tests/run.sh` lines 118-119 (node detection)
**Apply to:** `--exact` path in `scripts/audit-setup.sh` cost section
```bash
if command -v node >/dev/null 2>&1; then
```

### POSIX wc -c Char Count
**Source:** `scripts/audit-setup.sh` line 124
**Apply to:** per-file breakdown loop in cost section
```bash
TOTAL_CHARS=$(find .claude -type f \( -name '*.md' -o -name '*.json' \) -exec cat {} + 2>/dev/null | wc -c | tr -d ' ')
```
Per-file variant: `chars=$(wc -c < "$file" | tr -d ' ')`

### Node ESM Shebang + `node:` Imports
**Source:** `templates/hooks-nodejs/session-start-context.mjs` lines 1-8
**Apply to:** `lib/exact-count.mjs`
```javascript
#!/usr/bin/env node
import { readFileSync } from 'node:fs';
import path from 'node:path';
```

### pass/fail Test Helpers
**Source:** `tests/run.sh` lines 15-16
**Apply to:** new cost test section in `tests/run.sh`
```bash
pass() { echo "  ✓ $1"; PASS=$((PASS+1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL+1)); }
```

---

## No Analog Found

No files in this phase are fully without analog. All have at least a role-match or directory-convention match.

| File | Role | Why no closer match |
|------|------|---------------------|
| `lib/prices.json` | config/data | No JSON data files exist in lib/ yet; `lib/mutate.sh` provides only the directory convention |

---

## Critical Constraints Summary

| Constraint | Source | Applies to |
|------------|--------|------------|
| POSIX bash 3.2+ — no `declare -A`, no `mapfile`, no `[[` beyond 3.2 | CLAUDE.md | `scripts/audit-setup.sh` cost section |
| Never call `ok()`/`warn()`/`err()` after the PASS/WARN/FAIL summary line | `audit-setup.sh` lines 133-135 | cost section |
| Float arithmetic via `awk "BEGIN {printf...}"`, never bash `$((...))` | RESEARCH.md Pitfall 3 | cost section dollar calculations |
| `node:` prefix on stdlib imports | existing .mjs hooks pattern | `lib/exact-count.mjs` |
| `client.messages.countTokens` (stable, not `client.beta.messages.countTokens`) | RESEARCH.md State of the Art | `lib/exact-count.mjs` |
| `@anthropic-ai/sdk` not bundled — check for MODULE_NOT_FOUND at runtime | CLAUDE.md `dependencies: {}` | `lib/exact-count.mjs` |
| sort: use `-t' '` explicitly for BSD/GNU compatibility | RESEARCH.md Pitfall 4 | cost section sort |

---

## Metadata

**Analog search scope:** `cli/`, `scripts/`, `lib/`, `templates/hooks-nodejs/`, `tests/`
**Files read:** 7 (cli/conjure, scripts/audit-setup.sh, lib/mutate.sh, templates/hooks-nodejs/pre-bash-block-destructive.mjs, templates/hooks-nodejs/session-start-context.mjs, templates/hooks-nodejs/post-edit-format.mjs, tests/run.sh)
**Pattern extraction date:** 2026-05-25
