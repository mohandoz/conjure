# Phase 7: Skill-Firing Telemetry - Pattern Map

**Mapped:** 2026-05-25
**Files analyzed:** 7 (2 new, 5 modified)
**Analogs found:** 7 / 7

---

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `templates/hooks-nodejs/skill-telemetry.mjs` | hook | event-driven + file-I/O | `templates/hooks-nodejs/stop-compound-engineering.mjs` | role-match (same mkdirSync+appendFileSync pattern; new stdin-read behavior) |
| `TELEMETRY.md` | doc | — | `templates/hooks-nodejs/README.md` (conventions doc) | doc (no code analog needed) |
| `templates/settings.json.tmpl` | config | — | `templates/settings.json.tmpl` (self — add new blocks) | self-modification |
| `scripts/audit-setup.sh` | script | batch + transform | `scripts/audit-setup.sh` lines 138–196 (cost section) | exact (same file, same pattern) |
| `cli/conjure` | CLI entrypoint | request-response | `cli/conjure` lines 113–127 (`cmd_audit`) | exact (same file, same pattern) |
| `tests/run.sh` | test | batch | `tests/run.sh` lines 372–438 (cost estimator section) | exact (same file, same pattern) |
| `templates/.gitignore.tmpl` | config | — | `templates/.gitignore.tmpl` (self — append entry) | self-modification |

---

## Pattern Assignments

---

### `templates/hooks-nodejs/skill-telemetry.mjs` (hook, event-driven + file-I/O)

**Primary analog:** `templates/hooks-nodejs/stop-compound-engineering.mjs`
**Secondary analog:** `templates/hooks-nodejs/post-edit-format.mjs` (env-var guard pattern)

**Shebang + imports pattern** (from `stop-compound-engineering.mjs` lines 1–7 and research Pattern 1):
```javascript
#!/usr/bin/env node
// Cross-platform PreToolUse(Skill) + UserPromptExpansion hook — skill-firing telemetry.
// Appends one JSONL line per skill invocation. Opt-in via CONJURE_TELEMETRY=1.
// Exit 0 always — telemetry NEVER blocks.

import { mkdirSync, appendFileSync } from 'node:fs';
import path from 'node:path';
```

**Opt-in gate pattern** (D-01, D-02 — checked BEFORE stdin read, per `pre-bash-block-destructive.mjs` lines 5–6 guard pattern):
```javascript
// DO_NOT_TRACK check FIRST, per Unix convention (D-02)
if (process.env.DO_NOT_TRACK === '1') process.exit(0);
if (process.env.CONJURE_TELEMETRY !== '1') process.exit(0);
```

**Stdin read + parse pattern** (RESEARCH.md Pattern 1 — this is the first stdin-reading hook in the kit):
```javascript
// All hook logic INSIDE the 'end' callback — never call process.exit() outside it.
const guard = setTimeout(() => process.exit(0), 5000); // defensive timeout
let raw = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', chunk => { raw += chunk; });
process.stdin.on('end', () => {
  clearTimeout(guard);
  let p;
  try { p = JSON.parse(raw); } catch { process.exit(0); }
  // ... all work here
  process.exit(0);
});
```

**Dual-event branch pattern** (RESEARCH.md Pattern 2, D-03):
```javascript
const event = p.hook_event_name;
let skillName = null;
let eventType = null;

if (event === 'PreToolUse' && p.tool_name === 'Skill') {
  skillName = p.tool_input?.skill_name ?? null;   // A1: defensive ?.
  eventType = 'skill_invoke';
} else if (event === 'UserPromptExpansion') {
  skillName = p.command_name ?? null;              // A2: strip leading / defensively
  if (skillName) skillName = skillName.replace(/^\//, '');
  eventType = 'skill_typed';
}

if (!skillName) process.exit(0); // not a skill event — silent pass
```

**JSONL record + file-write pattern** (mirrors `stop-compound-engineering.mjs` lines 16–29):
```javascript
// From stop-compound-engineering.mjs:
//   mkdirSync(candidatesDir, { recursive: true });
//   appendFileSync(candidatesFile, `...`);
// Same pattern here, with JSON.stringify instead of template literal:

const record = JSON.stringify({
  ts: new Date().toISOString(),
  session_id: p.session_id,
  event: eventType,
  skill: skillName,          // skill name ONLY — never skill_args (PII, D-05)
  project_cwd: p.cwd
});

try {
  const logDir = path.join(p.cwd, '.claude', 'telemetry');
  mkdirSync(logDir, { recursive: true });          // idempotent, cross-platform
  appendFileSync(path.join(logDir, 'skill-events.jsonl'), record + '\n');
} catch { /* silent fail — telemetry must never block */ }

process.exit(0);
```

**Critical anti-patterns to avoid** (from RESEARCH.md):
- Never write to stdout — stdout at exit 0 is parsed by CC as JSON context
- Never exit 2 — telemetry must never block
- Never log `skill_args` or `command_args` — PII risk
- All logic must be inside the `'end'` callback

---

### `TELEMETRY.md` (doc)

**No code analog.** This is a schema documentation file at repo root alongside `README.md`.

**Required content per D-05, D-02, TLMY-05:**
- JSONL schema: all five fields (`ts`, `session_id`, `event`, `skill`, `project_cwd`)
- Opt-in instructions: `CONJURE_TELEMETRY=1` in `.claude/settings.json` `env` block
- `DO_NOT_TRACK` suppression documented
- No-egress guarantee with verifiable grep: `grep -E 'curl|fetch|http' templates/hooks-nodejs/skill-telemetry.mjs`
- Log path: `{project}/.claude/telemetry/skill-events.jsonl`
- Append-only semantics stated

---

### `templates/settings.json.tmpl` (config, self-modification)

**Analog:** `templates/settings.json.tmpl` lines 41–88 (existing hooks block)

**Existing PreToolUse block** (lines 53–67) — new Skill matcher entry appended into this array:
```json
"PreToolUse": [
  {
    "matcher": "Bash",
    "hooks": [
      { "type": "command", "command": "node .claude/hooks/pre-bash-block-destructive.mjs" },
      { "type": "command", "command": "node .claude/hooks/pre-commit-quality-gate.mjs" }
    ]
  }
  // ADD after this existing entry:
]
```

**New Skill matcher entry pattern** (mirrors Bash matcher entry above, D-04):
```json
{
  "matcher": "Skill",
  "hooks": [
    {
      "type": "command",
      "command": "node .claude/hooks/skill-telemetry.mjs"
    }
  ]
}
```

**New UserPromptExpansion top-level key** (RESEARCH.md Pattern 4 — no matcher needed):
```json
"UserPromptExpansion": [
  {
    "hooks": [
      {
        "type": "command",
        "command": "node .claude/hooks/skill-telemetry.mjs"
      }
    ]
  }
]
```

**Comment block pattern** (mirrors `_comment_permissions` line 4, `_comment_hooks` line 40, `_comment_env` line 90):
```json
"_comment_telemetry": "Uncomment to enable opt-in skill-firing telemetry (set CONJURE_TELEMETRY=1 in env block below)",
```

**env block update** (line 91 currently `"env": {}`) — add commented example:
```json
"env": {
  "_comment": "Set CONJURE_TELEMETRY=1 here to enable skill-firing telemetry (see TELEMETRY.md)"
}
```

---

### `scripts/audit-setup.sh` (script, batch + transform — retire-list section)

**Analog:** `scripts/audit-setup.sh` lines 138–196 (cost section — exact same structure)

**Guard pattern** (line 138 — copy verbatim, swap variable name):
```bash
# ANALOG (line 138):
if [ "${CONJURE_COST:-0}" = "1" ]; then

# NEW retire-list guard (place BEFORE line 198 exit block — same position as cost section):
if [ "${CONJURE_RETIRE:-0}" = "1" ]; then
```

**jq availability guard** (lines 142–144 — copy verbatim):
```bash
  if ! command -v jq >/dev/null 2>&1; then
    echo "  [--retire-list] jq not installed — install jq to use retire-list"
  else
```

**mktemp + trap pattern** (lines 167–168 — copy verbatim, rename variable):
```bash
    RETIRE_TMP=$(mktemp)
    trap 'rm -f "$RETIRE_TMP"' EXIT
```

**Date portability pattern** (line 116 — `stat` portability already uses same `2>/dev/null || fallback` pattern):
```bash
    # From audit-setup.sh line 116:
    #   $(stat -f %m ... 2>/dev/null || stat -c %Y ...)
    # Same two-variant pattern for date:
    CUTOFF=$(date -u -v-30d '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null \
             || date -u -d '30 days ago' '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null \
             || echo "0000-00-00T00:00:00Z")
```

**jq + sort/uniq aggregation** (mirrors cost loop lines 170–184):
```bash
    LOG="$TARGET/.claude/telemetry/skill-events.jsonl"

    if [ ! -f "$LOG" ]; then
      echo
      echo "── Skill Retire-List ──────────────────────────────────"
      echo "  No telemetry data. Enable with CONJURE_TELEMETRY=1 in .claude/settings.json env."
    else
      jq -r --arg c "$CUTOFF" 'select(.ts >= $c) | .skill' "$LOG" \
        | sort | uniq -c | sort -rn > "$RETIRE_TMP"
```

**printf ASCII table pattern** (mirrors lines 187–194):
```bash
      echo
      echo "── Skill Retire-List ──────────────────────────────────"
      printf "  %-35s %6s %8s\n" "Skill" "Loads" "Status"
      printf "  %-35s %6s %8s\n" "-----" "-----" "------"

      while IFS= read -r line; do
        count=$(echo "$line" | awk '{print $1}')
        name=$(echo "$line" | awk '{$1=""; print $0}' | xargs)
        status="[active]"
        [ "$count" -eq 0 ] && status="[retire?]"
        printf "  %-35s %6s %8s\n" "$name" "$count" "$status"
      done < "$RETIRE_TMP"
    fi
  fi
fi
```

**Placement:** The retire-list block goes between the cost section end (line 196) and the exit block (line 198 `[ "$FAIL" -gt 0 ] && exit 2`). Same position as cost section.

---

### `cli/conjure` (CLI entrypoint — `cmd_audit` modification)

**Analog:** `cli/conjure` lines 113–127 (`cmd_audit` function — exact same file)

**Current cmd_audit** (lines 113–127):
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

**Modification — add `--retire-list` flag** (insert after `--exact` case, add to env block):
```bash
cmd_audit() {
  local target="$(pwd)" do_cost=0 do_exact=0 do_retire=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --cost)         do_cost=1 ;;
      --exact)        do_exact=1 ;;
      --retire-list)  do_retire=1 ;;                    # NEW
      --help|-h)      grep -A3 '^  conjure audit' <<<"$(usage)"; return 0 ;;
      *)              target="$1" ;;
    esac
    shift
  done
  cmd_preflight || return 1
  CONJURE_HOME="$CONJURE_HOME" CONJURE_COST="$do_cost" CONJURE_EXACT="$do_exact" \
    CONJURE_RETIRE="$do_retire" \                       # NEW
    bash "$CONJURE_HOME/scripts/audit-setup.sh" "$target"
}
```

**Pattern rule:** `CONJURE_RETIRE` follows `CONJURE_COST` / `CONJURE_EXACT` exactly — same local var, same case entry, same env export on line 125–126.

---

### `tests/run.sh` (test, batch — telemetry section)

**Analog:** `tests/run.sh` lines 372–438 (cost estimator section — exact same structure)

**Section header pattern** (line 372):
```bash
echo
echo "▸ Telemetry tests (TLMY-01 through TLMY-05)"
```

**sandbox_setup usage pattern** (lines 374–376):
```bash
# Reuse python-fastapi fixture (has .claude/skills/ for retire-list join)
TLMY_FX="$CONJURE_HOME/tests/fixtures/python-fastapi"
sandbox_setup "$TLMY_FX"
trap 'rm -rf "$SANDBOX_DIR"' EXIT
```

**No-egress grep test** (TLMY-03 — static analysis, no sandbox needed):
```bash
HOOK_FILE="$CONJURE_HOME/templates/hooks-nodejs/skill-telemetry.mjs"
if [ ! -f "$HOOK_FILE" ]; then
  fail "skill-telemetry.mjs not found (TLMY-02)"
else
  EGRESS_PATTERNS='curl|fetch|http|socket|XMLHttpRequest|require\(.https.\)|require\(.http.\)|import.*https|import.*http|net\.Socket'
  if grep -qE "$EGRESS_PATTERNS" "$HOOK_FILE" 2>/dev/null; then
    fail "skill-telemetry.mjs contains network egress pattern (TLMY-03)"
  else
    pass "skill-telemetry.mjs: no network egress (TLMY-03)"
  fi
fi
```

**CONJURE_RETIRE=1 invoke pattern** (mirrors CONJURE_COST=1 invocation at line 378):
```bash
RETIRE_OUT="$(CONJURE_RETIRE=1 bash "$CONJURE_HOME/scripts/audit-setup.sh" "$SANDBOX_DIR" 2>&1)"
RETIRE_RC=$?
```

**pass/fail assertion pattern** (lines 382–390 — copy structure):
```bash
if printf '%s' "$RETIRE_OUT" | grep -q "── Skill Retire-List ──"; then
  pass "retire-list section header present (TLMY-04)"
else
  fail "retire-list section header missing (TLMY-04)"
fi

if [ "$RETIRE_RC" -le 2 ]; then
  pass "retire-list section exit code ≤ 2 (TLMY-04)"
else
  fail "retire-list section crashed (rc=$RETIRE_RC) (TLMY-04)"
fi
```

**Cleanup pattern** (lines 438–439 — copy verbatim):
```bash
rm -rf "$SANDBOX_DIR"
trap - EXIT
```

**Full test IDs to cover:**
- TLMY-01: hook file exists; hook exits 0 when CONJURE_TELEMETRY unset; DO_NOT_TRACK suppresses
- TLMY-02: JSONL written when CONJURE_TELEMETRY=1 (invoke hook with mock stdin)
- TLMY-03: no-egress grep on skill-telemetry.mjs (static)
- TLMY-04: `--retire-list` flag present in cli/conjure; retire-list section renders
- TLMY-05: TELEMETRY.md exists at repo root; contains schema fields

---

### `templates/.gitignore.tmpl` (config, self-modification)

**Analog:** `templates/.gitignore.tmpl` lines 1–19 (self — append new entry)

**Existing pattern** (lines 4–6 show the `.claude/` runtime state block):
```gitignore
# Conjure-managed runtime state (per-project, not portable)
.claude/COMPOUND-CANDIDATES.md
.claude/MIGRATION-REPORT*.md
.claude/.session-context
```

**New entry** — append under the same block comment (telemetry log is runtime state, not portable):
```gitignore
.claude/telemetry/
```

**Placement:** Append to the `# Conjure-managed runtime state` block (after line 6), before the backups block.

---

## Shared Patterns

### Env-var opt-in gate
**Source:** `templates/hooks-nodejs/pre-bash-block-destructive.mjs` lines 5–6 (early-exit pattern)
**Apply to:** `skill-telemetry.mjs` — first two lines of executable code after imports
```javascript
if (process.env.DO_NOT_TRACK === '1') process.exit(0);
if (process.env.CONJURE_TELEMETRY !== '1') process.exit(0);
```

### mkdirSync + appendFileSync file-write
**Source:** `templates/hooks-nodejs/stop-compound-engineering.mjs` lines 16–29
**Apply to:** `skill-telemetry.mjs` write block
```javascript
mkdirSync(candidatesDir, { recursive: true });
appendFileSync(candidatesFile, `\n## Session ${ts}\n...`);
process.exit(0);
```

### Date portability (BSD/GNU)
**Source:** `scripts/audit-setup.sh` line 116 (`stat -f %m 2>/dev/null || stat -c %Y`)
**Apply to:** retire-list section in `scripts/audit-setup.sh`
```bash
# Established pattern in this file:
$(stat -f %m graphify-out/graph.json 2>/dev/null || stat -c %Y graphify-out/graph.json)
# Mirror for date:
CUTOFF=$(date -u -v-30d '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null \
         || date -u -d '30 days ago' '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null \
         || echo "0000-00-00T00:00:00Z")
```

### mktemp + trap cleanup
**Source:** `scripts/audit-setup.sh` lines 167–168
**Apply to:** retire-list section mktemp in `scripts/audit-setup.sh`
```bash
COST_TMP=$(mktemp)
trap 'rm -f "$COST_TMP"' EXIT
```

### CLI flag + env-var pass-through
**Source:** `cli/conjure` lines 113–127 (`cmd_audit`)
**Apply to:** `--retire-list` flag addition in same function
```bash
CONJURE_HOME="$CONJURE_HOME" CONJURE_COST="$do_cost" CONJURE_EXACT="$do_exact" \
  bash "$CONJURE_HOME/scripts/audit-setup.sh" "$target"
```

### Test section structure
**Source:** `tests/run.sh` lines 372–438 (cost estimator section)
**Apply to:** new telemetry test section in same file
```bash
sandbox_setup "$FX"
trap 'rm -rf "$SANDBOX_DIR"' EXIT
OUT="$(ENV_VAR=1 bash "$CONJURE_HOME/scripts/audit-setup.sh" "$SANDBOX_DIR" 2>&1)"
RC=$?
if printf '%s' "$OUT" | grep -q "pattern"; then pass "..."; else fail "..."; fi
rm -rf "$SANDBOX_DIR"
trap - EXIT
```

---

## No Analog Found

All files have close analogs in the codebase. No entries.

| File | Role | Data Flow | Reason |
|------|------|-----------|--------|
| (none) | — | — | All 7 files have codebase analogs |

---

## Metadata

**Analog search scope:** `templates/hooks-nodejs/`, `scripts/`, `cli/`, `tests/`, `templates/`
**Files scanned:** 10 source files read in full
**Pattern extraction date:** 2026-05-25

**Key implementation notes:**
1. `skill-telemetry.mjs` is the first hook in this kit that reads stdin — all existing hooks use `process.argv[2]` or env vars. The stdin pattern comes from official CC hooks docs (RESEARCH.md Pattern 1), not from existing hook files.
2. The retire-list section in `audit-setup.sh` must be placed BEFORE line 198 (`[ "$FAIL" -gt 0 ] && exit 2`) — same constraint as the cost section (which correctly sits at lines 138–196).
3. The `trap 'rm -f "$RETIRE_TMP"' EXIT` in the retire-list section will conflict with the cost section's identical trap if both run. The planner should note that the retire-list trap should reset (`trap - EXIT` first) or use a unique variable name, or combine both traps. The cost section already uses `COST_TMP` — retire-list should use `RETIRE_TMP` and register a separate trap, or combine: `trap 'rm -f "$COST_TMP" "$RETIRE_TMP"' EXIT`.
