# Phase 7: Skill-Firing Telemetry - Research

**Researched:** 2026-05-25
**Domain:** Claude Code hook events, JSONL append logging, bash CLI flag parsing, retire-list aggregation
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** Telemetry activated via `CONJURE_TELEMETRY=1` env var in target project's `.claude/settings.json` `env` block. Matches `CONJURE_COST=1` pattern from Phase 6.
- **D-02:** Hook exits 0 silently when `CONJURE_TELEMETRY` is unset or `!= "1"`. `DO_NOT_TRACK=1` suppresses all writes (checked before the env-var check).
- **D-03:** Two hooks in `templates/hooks-nodejs/skill-telemetry.mjs`: `PreToolUse` with matcher `Skill`, and `UserPromptExpansion` (no matcher). Same `.mjs` file branches on `hook_event_name`.
- **D-04:** Hook wired in `settings.json.tmpl` with `_comment_telemetry` comment block explaining opt-in. Entries present, env-var gate means zero writes unless opted in.
- **D-05:** JSONL schema: `{"ts":"…","session_id":"…","event":"skill_invoke|skill_typed","skill":"name","project_cwd":"…"}`. No args (PII risk). `project_cwd` is already in env.
- **D-06:** Log path: `{target}/.claude/telemetry/skill-events.jsonl`. Directory created by hook on first write. Append-only (`>>`).
- **D-07:** `conjure audit --retire-list` flag (separate from `--cost`). Reads target's JSONL. Absent file prints advisory and skips.
- **D-08:** Retire-list output: count-sorted `Skill | Sessions | Loads | Status` table after PASS/WARN/FAIL summary. Skills with 0 loads = `[retire?]`, ≥1 = `[active]`.
- **D-09:** Section header `── Skill Retire-List ──`. Events within last 30 days (default). If no events: `  No telemetry data in last 30 days.`
- **D-10:** `cli/conjure cmd_audit()` parses `--retire-list` flag → passes `CONJURE_RETIRE=1` to `scripts/audit-setup.sh`. Same pattern as `CONJURE_COST=1`.
- **D-11:** `tests/run.sh` gains "Telemetry no-egress" section. Greps `templates/hooks-nodejs/skill-telemetry.mjs` for: `curl`, `fetch`, `http`, `socket`, `XMLHttpRequest`, `require('https')`, `require('http')`, `import.*https`, `import.*http`, `net.Socket`.
- **D-12:** New files: `templates/hooks-nodejs/skill-telemetry.mjs`, `TELEMETRY.md` (repo root).
- **D-13:** Modified files: `templates/settings.json.tmpl`, `scripts/audit-setup.sh`, `cli/conjure`, `tests/run.sh`.

### Claude's Discretion

- Exact column widths in the retire-list ASCII table
- Whether session count is derived from unique `session_id` values or just presence of any event per day
- Whether `CONJURE_RETIRE_DAYS` env override is implemented in v0.3.0 or deferred (simple cutoff acceptable)
- Exact wording in `TELEMETRY.md` beyond what requirements specify

### Deferred Ideas (OUT OF SCOPE)

- Aggregate retire-list across multiple projects (requires a central store — local-only by design)
- Auto-prune skills with 0 loads (`conjure prune-skills`) — v0.4.0 feature
- Telemetry dashboard / visualization — out of scope for v0.3.0
- `CONJURE_RETIRE_DAYS` env override — acceptable to hardcode 30 days for now

</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| TLMY-01 | Skill-firing telemetry is opt-in (off by default) and PII-free | D-01/D-02: env-var gate + DO_NOT_TRACK; D-05: log skill name only, no args |
| TLMY-02 | Telemetry writes local-only append-only JSONL the user owns (`.claude/telemetry/`) with zero network egress | D-03/D-05/D-06: hook writes to local path via `>>`, no HTTP imports; stdlib only |
| TLMY-03 | A build/CI test greps all shipped hooks to assert no network egress from telemetry | D-11: grep pattern in tests/run.sh; verified hook file content strategy |
| TLMY-04 | Conjure produces a skill "retire-list" from the local telemetry event log | D-07/D-08/D-09/D-10: `--retire-list` flag, jq parsing, count-sorted table |
| TLMY-05 | `TELEMETRY.md` schema ships in the same change as the hook, and telemetry honors `DO_NOT_TRACK` | D-02: DO_NOT_TRACK checked first; D-12: TELEMETRY.md at repo root |

</phase_requirements>

---

## Summary

Phase 7 ships the final v0.3.0 feature: local-only, opt-in, PII-free skill-firing telemetry that feeds a retire-list in `conjure audit`. All user decisions are locked (CONTEXT.md D-01 through D-13). Research confirms the implementation strategy is sound and internally consistent with prior phases.

The core technical discovery: **Claude Code delivers hook payloads via stdin as JSON**, not via `process.argv` or environment variables. The existing hooks in `templates/hooks-nodejs/` do not read stdin because they use legacy/complementary env vars (`CLAUDE_COMMAND`, `CLAUDE_FILE_PATH`) that predate or supplement the JSON-on-stdin protocol. The skill-telemetry hook will be the first hook in this kit to read stdin — this is correct behavior for event-driven hooks that need `session_id`, `skill_name`, and `cwd` from the structured payload.

The retire-list aggregation follows the exact pattern established by the cost estimator in Phase 6: `jq` parses the JSONL log, a `mktemp`-based accumulator builds the table, `printf` renders it after the PASS/WARN/FAIL summary. No new dependencies are introduced — this phase is pure bash + Node.js stdlib + `jq`.

**Primary recommendation:** Ship the hook first (Wave 1), then the audit integration (Wave 2), then tests (Wave 3) — same wave structure as Phase 6.

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Skill-fire event capture | Hook (node .mjs) | — | PreToolUse/UserPromptExpansion run in Claude Code process; only the hook can intercept at fire-time |
| JSONL log persistence | Hook (node .mjs) | — | Hook owns the write; audit only reads. Append-only in hook avoids coordination |
| Retire-list aggregation | CLI (audit-setup.sh) | — | Aggregation is a batch read/count operation; fits audit's existing summary pattern |
| Opt-in gate | Hook (env-var check) + CLI (flag parse) | — | Hook gates writes; CLI gates reading. Both must honor the same convention |
| No-egress enforcement | Test (tests/run.sh) | CI | Grep-based assertion turns a promise into a broken-build invariant |
| Schema documentation | Docs (TELEMETRY.md) | — | Ships alongside hook; static doc with grep-verify instruction |

---

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Node.js stdlib (`node:fs`, `node:path`, `node:process`) | ≥18 LTS (v24.15.0 on dev machine) | Hook implementation — stdin read, directory create, file append | Already the universal hook runtime; zero new deps; cross-platform |
| `jq` | system (v1.8.1 confirmed) | JSONL parsing in retire-list aggregation | Already a preflight dependency; used in cost estimator pattern |
| bash | POSIX 3.2+ | `audit-setup.sh` retire-list section, flag parsing in `cli/conjure` | Existing script language; no new tooling |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `mktemp` | stdlib | Temp file for retire-list accumulator | Same pattern as cost estimator's `COST_TMP` |
| `awk` | stdlib | Date arithmetic for 30-day cutoff | Same pattern as cost estimator's cost computation |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| jq for JSONL parsing | sqlite3 | sqlite is a native dep; out of scope for zero-dep requirement |
| node:fs appendFileSync | bash `>>` in hook | Either works; node is correct since hook is already .mjs; sync append is safe for single-line events |
| 30-day hardcoded cutoff | `CONJURE_RETIRE_DAYS` env var | Env var is Claude's discretion; hardcode for now per deferred decision |

**Installation:** No new packages. This phase has zero new npm or OS-level dependencies. `[VERIFIED: npm registry]` — not applicable; no packages to install.

---

## Package Legitimacy Audit

> Phase 7 installs zero external packages. All implementation uses Node.js stdlib and system tools already declared as preflight dependencies.

| Package | Registry | Age | Downloads | Source Repo | slopcheck | Disposition |
|---------|----------|-----|-----------|-------------|-----------|-------------|
| (none) | — | — | — | — | N/A | No packages installed |

**Packages removed due to slopcheck [SLOP] verdict:** none
**Packages flagged as suspicious [SUS]:** none

---

## Architecture Patterns

### System Architecture Diagram

```
Claude Code session
       │
       ├─ User types /skillname ──► UserPromptExpansion event (stdin JSON)
       │                                    │
       └─ Claude invokes Skill tool ──► PreToolUse (matcher:"Skill") event (stdin JSON)
                                               │
                                    ┌──────────▼──────────────┐
                                    │  skill-telemetry.mjs    │
                                    │  1. Read stdin JSON      │
                                    │  2. Check DO_NOT_TRACK   │
                                    │  3. Check CONJURE_       │
                                    │     TELEMETRY=1          │
                                    │  4. Extract skill name   │
                                    │  5. Append JSONL line    │
                                    └──────────┬──────────────┘
                                               │ appendFileSync (>>)
                              .claude/telemetry/skill-events.jsonl
                                               │
                              ┌────────────────▼────────────────────┐
                              │  conjure audit --retire-list         │
                              │  (audit-setup.sh, CONJURE_RETIRE=1) │
                              │  1. Read JSONL with jq               │
                              │  2. Filter last 30 days              │
                              │  3. Count loads per skill            │
                              │  4. Join against known skills        │
                              │  5. Render table (retire?/active)   │
                              └─────────────────────────────────────┘
```

### Recommended Project Structure

```
templates/
├── hooks-nodejs/
│   └── skill-telemetry.mjs      # NEW: PreToolUse(Skill) + UserPromptExpansion
├── settings.json.tmpl            # MODIFIED: add hook entries + _comment_telemetry
scripts/
└── audit-setup.sh                # MODIFIED: add retire-list section after cost section
cli/
└── conjure                       # MODIFIED: add --retire-list flag in cmd_audit()
tests/
└── run.sh                        # MODIFIED: add telemetry test section
TELEMETRY.md                      # NEW: schema doc at repo root
```

### Pattern 1: Hook Reads Stdin — the correct Claude Code hook protocol

**What:** Claude Code delivers a JSON payload on stdin. The hook reads stdin to end, parses the JSON, then acts.

**When to use:** Any hook that needs structured data from the event (`session_id`, `tool_input.skill_name`, `command_name`, `cwd`). Required for skill-telemetry.

**Why existing hooks don't use this:** The existing hooks (`pre-bash-block-destructive.mjs`, `pre-commit-quality-gate.mjs`) access command info via `CLAUDE_COMMAND` env var or `process.argv[2]` — these are complementary mechanisms for simpler cases. When you need `session_id` or `tool_input` fields, stdin JSON is the authoritative source.

**Example:**
```javascript
// Source: https://code.claude.com/docs/en/hooks (official CC hooks docs)
// Pattern: read stdin → parse JSON → act → exit 0
let raw = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', chunk => { raw += chunk; });
process.stdin.on('end', () => {
  let payload;
  try { payload = JSON.parse(raw); } catch { process.exit(0); }
  // payload.hook_event_name, payload.session_id, payload.cwd,
  // payload.tool_input.skill_name (PreToolUse/Skill)
  // payload.command_name (UserPromptExpansion)
  process.exit(0);
});
```

### Pattern 2: Dual-Event in One .mjs File — branch on hook_event_name

**What:** A single `.mjs` file handles two event types by branching on `payload.hook_event_name`.

**When to use:** When two events produce the same logical output (a JSONL record) and share all auth/gate logic. Avoids duplicate opt-in checking and file path logic.

**Example:**
```javascript
// Source: Claude Code hook docs + stop-compound-engineering.mjs pattern
process.stdin.on('end', () => {
  const p = JSON.parse(raw);
  const event = p.hook_event_name;

  let skillName = null;
  let eventType = null;

  if (event === 'PreToolUse' && p.tool_name === 'Skill') {
    skillName = p.tool_input?.skill_name ?? null;
    eventType = 'skill_invoke';
  } else if (event === 'UserPromptExpansion') {
    skillName = p.command_name ?? null;
    eventType = 'skill_typed';
  }

  if (!skillName) { process.exit(0); } // not a skill event — silent pass

  const record = JSON.stringify({
    ts: new Date().toISOString(),
    session_id: p.session_id,
    event: eventType,
    skill: skillName,
    project_cwd: p.cwd
  });

  // mkdirSync + appendFileSync — same pattern as stop-compound-engineering.mjs
  import { mkdirSync, appendFileSync } from 'node:fs';
  import path from 'node:path';
  const logDir = path.join(p.cwd, '.claude', 'telemetry');
  mkdirSync(logDir, { recursive: true });
  appendFileSync(path.join(logDir, 'skill-events.jsonl'), record + '\n');
  process.exit(0);
});
```

### Pattern 3: Retire-List Aggregation — jq + mktemp table (mirrors cost estimator)

**What:** Parse JSONL with `jq`, count per-skill with `sort | uniq -c`, join against discovered skills list, render printf table.

**When to use:** Batch aggregation of append-only log files; same as cost estimator pattern in `audit-setup.sh`.

**Example:**
```bash
# Source: audit-setup.sh cost section (lines 138–196), adapted for retire-list
if [ "${CONJURE_RETIRE:-0}" = "1" ]; then
  LOG_FILE="$TARGET/.claude/telemetry/skill-events.jsonl"
  if [ ! -f "$LOG_FILE" ]; then
    echo "  [--retire-list] No telemetry data at $LOG_FILE — enable with CONJURE_TELEMETRY=1"
  else
    CUTOFF=$(date -u -v-30d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
             || date -u -d '30 days ago' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
             || echo "0000-00-00")  # graceful fallback

    RETIRE_TMP=$(mktemp)
    trap 'rm -f "$RETIRE_TMP"' EXIT

    jq -r --arg cutoff "$CUTOFF" \
      'select(.ts >= $cutoff) | .skill' "$LOG_FILE" \
      | sort | uniq -c | sort -rn >> "$RETIRE_TMP"

    echo
    echo "── Skill Retire-List ──────────────────────────────────"
    printf "  %-30s %6s %8s %10s\n" "Skill" "Loads" "Sessions" "Status"
    printf "  %-30s %6s %8s %10s\n" "-----" "-----" "--------" "------"
    # ... render from RETIRE_TMP; join 0-load skills from .claude/skills/
  fi
fi
```

### Pattern 4: settings.json.tmpl Hook Entries — UserPromptExpansion block

**What:** `UserPromptExpansion` is a top-level key in `hooks` (not nested under `PreToolUse`). No `matcher` field needed when you want to fire on all slash commands.

**When to use:** Capturing typed `/skillname` commands via UserPromptExpansion event.

**Verified payload:** `payload.command_name` holds the skill name; `payload.expansion_type` is `"slash_command"`.

**Example:**
```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Skill",
        "hooks": [
          {
            "type": "command",
            "command": "node .claude/hooks/skill-telemetry.mjs"
          }
        ]
      }
    ],
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
  }
}
```

### Anti-Patterns to Avoid

- **Reading process.argv for skill data:** The skill name is in `tool_input.skill_name` (PreToolUse) or `command_name` (UserPromptExpansion) — these fields are only accessible via stdin JSON. `process.argv` only gets args passed on the command line, which CC does not use for these events.
- **Exit 2 from telemetry hook:** Telemetry must never block. Exit 2 would prevent Claude from using the skill. Always `process.exit(0)`.
- **Writing to stdout in the hook:** Any stdout at exit 0 is parsed by Claude Code as JSON context. Telemetry writes only to the JSONL file; stdout must stay empty (or emit `{"suppressOutput": true}`).
- **Using `date` BSD vs GNU portability gap:** `date -v-30d` is BSD (macOS); `date -d '30 days ago'` is GNU (Linux). Must handle both in `audit-setup.sh`. Use `2>/dev/null || fallback` pattern.
- **Hardcoding path separator in the hook:** Use `path.join(p.cwd, '.claude', 'telemetry')` — never string concat with `/`.
- **Not guarding `JSON.parse` on stdin:** If stdin is empty or malformed, `JSON.parse` throws. Wrap in try/catch and exit 0 on parse failure — hook must never crash.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| JSONL parsing in bash | `while read line; do echo $line | cut...` | `jq -r 'select(.ts >= $cutoff)'` | jq handles escaping, Unicode, nested fields; cut breaks on any quoted comma |
| Skill count aggregation | awk accumulator | `sort \| uniq -c \| sort -rn` | Two-liner; already proven pattern in project |
| Date arithmetic for 30-day window | Pure bash epoch math | `date -v-30d` (BSD) / `date -d '30 days ago'` (GNU) with graceful fallback | Epoch arithmetic in bash is error-prone across DST and leap-second boundaries |
| Cross-platform directory creation | Conditional `mkdir` | `mkdirSync(dir, { recursive: true })` | `recursive: true` is idempotent and correct on all platforms; avoids EEXIST errors |
| Structured event log | Custom binary format | JSONL (`>>` append) | Append-safe, jq-readable, human-inspectable, crash-safe (partial last line is ignored by `jq`) |

**Key insight:** The retire-list aggregation is `jq select | sort | uniq -c` — it is not complex enough to warrant a separate script or data structure. Inline in `audit-setup.sh` just like the cost section.

---

## Common Pitfalls

### Pitfall 1: Writing to stdout — silent data injection into Claude's context

**What goes wrong:** Any non-empty stdout at exit 0 from a hook is parsed by Claude Code as a JSON hook response. If the telemetry hook writes the JSONL record to stdout instead of the file, or if a debug `console.log` leaks, CC tries to parse it as hook output and produces an error or unexpected behavior.

**Why it happens:** Developers new to the hook protocol conflate "write the event data" with "output to terminal." The correct channel for the JSONL record is `appendFileSync` to the log file; stdout is the CC protocol channel.

**How to avoid:** The hook must write only to the log file. Keep stdout completely empty (or emit `{"suppressOutput": true}` at the very end if you must confirm opt-in state). Use `process.stderr.write()` only for debug output that should appear in CC's debug log.

**Warning signs:** `jq: parse error` appearing in Claude's context after skill invocations; hook appearing to "block" though it exits 0.

### Pitfall 2: date command portability — BSD vs GNU

**What goes wrong:** `date -v-30d` (BSD/macOS) fails on Linux with "illegal time format." `date -d '30 days ago'` (GNU/Linux) fails on macOS. The 30-day cutoff in the retire-list aggregation must work on both.

**Why it happens:** The kit runs on macOS (developer) and Linux (CI — ubuntu-latest). `audit-setup.sh` already has this exact issue at line 116 (`stat -f %m 2>/dev/null || stat -c %Y`).

**How to avoid:**
```bash
CUTOFF=$(date -u -v-30d '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null \
         || date -u -d '30 days ago' '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null \
         || echo "0000-00-00T00:00:00Z")
```
The fallback `0000-00-00` means "include everything" — safe degradation.

**Warning signs:** Test passes on macOS dev machine, fails on `ubuntu-latest` CI with `illegal time format`.

### Pitfall 3: stdin read race — hook exits before stdin is fully received

**What goes wrong:** If the hook does not wait for the `'end'` event on `process.stdin` before calling `process.exit(0)`, it may exit before reading the full payload and silently log nothing (or partial data).

**Why it happens:** Node's stdin is an async stream. Any synchronous code after setting up the listener finishes before data arrives. If the hook does work synchronously after registering the handler, it may exit prematurely.

**How to avoid:** All hook logic must be inside the `process.stdin.on('end', () => { ... })` callback. Do not call `process.exit()` outside of that callback. This is the canonical pattern shown in CC docs.

**Warning signs:** JSONL file is never created even when `CONJURE_TELEMETRY=1`; log file exists but is always empty.

### Pitfall 4: UserPromptExpansion fires for non-skill slash commands

**What goes wrong:** `UserPromptExpansion` fires for ALL slash commands — not just skills. A user running `/gsd-quick` or any built-in command will also trigger the hook. The hook must filter to skill invocations only, or it will log non-skill commands as "skills."

**Why it happens:** No `matcher` on UserPromptExpansion means it fires on every expansion. The `expansion_type` field distinguishes `"slash_command"` from `"mcp_prompt"`, but all slash commands are `"slash_command"`.

**How to avoid:** Use `payload.command_source` to filter. Skills installed in `.claude/skills/` have `command_source: "project"` or `"plugin"`. Built-in Claude Code commands have a different source. Alternatively, check if `payload.command_name` matches a known skill directory in `.claude/skills/`. The simplest safe approach: log everything from UserPromptExpansion with `event: "skill_typed"` and let the retire-list aggregator compare against discovered skills.

**Warning signs:** Retire-list shows commands like `help`, `clear`, `init` as skills.

### Pitfall 5: JSONL line with args captured — PII leak

**What goes wrong:** `tool_input` for a PreToolUse/Skill event contains `skill_args` in addition to `skill_name`. If the hook logs `skill_args`, it captures whatever the user or Claude passed — potentially file paths, query strings, or other PII.

**Why it happens:** Logging the full `tool_input` is simpler than extracting one field.

**How to avoid:** Log `p.tool_input?.skill_name` only — never `p.tool_input?.skill_args`. For UserPromptExpansion, log `p.command_name` only — never `p.command_args`. This is already specified in D-05 but must be enforced in code review.

**Warning signs:** JSONL lines contain paths, SQL queries, or user-typed text after the skill name.

### Pitfall 6: `.claude/telemetry/` accidentally committed

**What goes wrong:** The JSONL log contains internal project data (which skills are being used). It should never be committed to git. If `.gitignore.tmpl` doesn't include it, generated projects will accidentally commit telemetry logs.

**Why it happens:** `init-project.sh` copies `.gitignore.tmpl` into the target. If `templates/.gitignore.tmpl` doesn't have `.claude/telemetry/`, users on `git add -A` will include it.

**How to avoid:** Add `.claude/telemetry/` to `templates/.gitignore.tmpl`. Also mentioned in D-12 context — this is an implied required change.

**Warning signs:** Telemetry JSONL appearing in `git status` after opt-in; users asking "why is this file tracked?"

---

## Code Examples

### Reading stdin in a Node.js hook

```javascript
// Source: https://code.claude.com/docs/en/hooks (official CC hooks documentation)
// Confirmed payload fields: hook_event_name, session_id, cwd, tool_name,
// tool_input.skill_name (PreToolUse/Skill), command_name (UserPromptExpansion)

import { mkdirSync, appendFileSync } from 'node:fs';
import path from 'node:path';

// DO_NOT_TRACK check FIRST, per Unix convention
if (process.env.DO_NOT_TRACK === '1') process.exit(0);
if (process.env.CONJURE_TELEMETRY !== '1') process.exit(0);

let raw = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', chunk => { raw += chunk; });
process.stdin.on('end', () => {
  let p;
  try { p = JSON.parse(raw); } catch { process.exit(0); }

  const event = p.hook_event_name;
  let skillName = null;
  let eventType = null;

  if (event === 'PreToolUse' && p.tool_name === 'Skill') {
    skillName = p.tool_input?.skill_name ?? null;
    eventType = 'skill_invoke';
  } else if (event === 'UserPromptExpansion') {
    skillName = p.command_name ?? null;
    eventType = 'skill_typed';
  }

  if (!skillName) process.exit(0);

  const record = JSON.stringify({
    ts: new Date().toISOString(),
    session_id: p.session_id,
    event: eventType,
    skill: skillName,
    project_cwd: p.cwd
  });

  try {
    const logDir = path.join(p.cwd, '.claude', 'telemetry');
    mkdirSync(logDir, { recursive: true });
    appendFileSync(path.join(logDir, 'skill-events.jsonl'), record + '\n');
  } catch { /* silent fail — telemetry must never block */ }

  process.exit(0);
});
```

### Retire-list aggregation in audit-setup.sh

```bash
# Source: audit-setup.sh cost section pattern (lines 138–196)
if [ "${CONJURE_RETIRE:-0}" = "1" ]; then
  LOG="$TARGET/.claude/telemetry/skill-events.jsonl"

  if [ ! -f "$LOG" ]; then
    echo
    echo "── Skill Retire-List ──────────────────────────────────"
    echo "  No telemetry data. Enable with CONJURE_TELEMETRY=1 in .claude/settings.json env."
  elif ! command -v jq >/dev/null 2>&1; then
    echo "  [--retire-list] jq not installed — install jq to use retire-list"
  else
    CUTOFF=$(date -u -v-30d '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null \
             || date -u -d '30 days ago' '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null \
             || echo "0000-00-00T00:00:00Z")

    RETIRE_TMP=$(mktemp)
    trap 'rm -f "$RETIRE_TMP"' EXIT

    # Count loads per skill in last 30 days
    jq -r --arg c "$CUTOFF" 'select(.ts >= $c) | .skill' "$LOG" \
      | sort | uniq -c | sort -rn > "$RETIRE_TMP"

    echo
    echo "── Skill Retire-List ──────────────────────────────────"
    printf "  %-35s %6s %8s\n" "Skill" "Loads" "Status"
    printf "  %-35s %6s %8s\n" "-----" "-----" "------"

    # Skills found in telemetry
    while IFS= read -r line; do
      count=$(echo "$line" | awk '{print $1}')
      name=$(echo "$line" | awk '{$1=""; print $0}' | xargs)
      status="[active]"
      [ "$count" -eq 0 ] && status="[retire?]"
      printf "  %-35s %6s %8s\n" "$name" "$count" "$status"
    done < "$RETIRE_TMP"

    # TODO: join against .claude/skills/ to show 0-load skills
  fi
fi
```

### No-egress grep test in tests/run.sh

```bash
# Source: tests/run.sh cost section pattern (lines 417–422)
echo
echo "▸ Telemetry no-egress (TLMY-03)"

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

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Hook inputs via argv/env vars | Structured JSON on stdin | CC ≥2.1.117 | All event fields (session_id, tool_input, cwd) now accessible in hooks; argv/env still work for backward compat |
| `InstructionsLoaded` for skill capture | `PreToolUse` with `matcher: "Skill"` | CC ≥2.1.117 | `InstructionsLoaded` fires on CLAUDE.md loads, NOT skill invocations — was an incorrect assumption in early research; PreToolUse/Skill is the correct event |
| Bash-only hooks (.sh files) | Node.js .mjs hooks | Phase 1 of this project | Cross-platform; Windows support without WSL |

**Deprecated/outdated:**
- `InstructionsLoaded` for skill-fire detection: This event fires when CLAUDE.md/rules load eagerly — not when a skill is invoked. The STACK.md research mentioned it alongside PreToolUse but it is NOT a skill-invocation signal. Use only `PreToolUse/Skill` + `UserPromptExpansion`. [VERIFIED: official CC hooks docs]
- Bash-only hook wiring in `settings.json.tmpl`: Resolved in Phase 1; all hooks now use `node .mjs`.

---

## Hook Event Verification

The following was confirmed directly from the official Claude Code hooks documentation at `https://code.claude.com/docs/en/hooks`: [VERIFIED: code.claude.com/docs/en/hooks]

### PreToolUse with tool_name "Skill"

```json
{
  "hook_event_name": "PreToolUse",
  "session_id": "abc123",
  "cwd": "/path/to/project",
  "tool_name": "Skill",
  "tool_input": {
    "skill_name": "gsd-execute-phase",
    "skill_args": "optional arguments"
  },
  "tool_use_id": "unique-id"
}
```

Field holding skill name: `tool_input.skill_name` [VERIFIED: code.claude.com/docs/en/hooks]

### UserPromptExpansion

```json
{
  "hook_event_name": "UserPromptExpansion",
  "session_id": "abc123",
  "cwd": "/path/to/project",
  "expansion_type": "slash_command",
  "command_name": "gsd-execute-phase",
  "command_args": "7",
  "command_source": "plugin",
  "prompt": "/gsd-execute-phase 7"
}
```

Field holding skill name: `command_name` [VERIFIED: code.claude.com/docs/en/hooks]

### Common Fields (all events)

`session_id`, `transcript_path`, `cwd`, `hook_event_name`, `permission_mode` [VERIFIED: code.claude.com/docs/en/hooks]

### Exit Code Semantics

- Exit 0: allow, CC parses stdout as JSON if non-empty
- Exit 2: block (must NOT use in telemetry hook)
- Exit 1 or other: non-blocking error, execution continues [VERIFIED: code.claude.com/docs/en/hooks]

---

## Implied Required Changes (not in D-12/D-13 but needed)

These are derived from research and must be addressed in the plan:

| Change | File | Reason |
|--------|------|--------|
| Add `.claude/telemetry/` to gitignore template | `templates/.gitignore.tmpl` | Telemetry JSONL must not be committed; without this entry, `git add -A` on an opted-in project includes it |
| Add `CONJURE_TELEMETRY=1` env example comment | `templates/settings.json.tmpl` | D-01 specifies env block; users need to know WHERE to set it; the `env: {}` block in settings.json.tmpl needs a commented example |

---

## Open Questions

1. **Session count vs load count in retire-list**
   - What we know: D-08 says columns are `Skill | Sessions | Loads | Status`. D-09 says "0 loads across all recorded sessions."
   - What's unclear: Claude's discretion is whether "Sessions" = unique session_id values or events-per-day. The implementation needs to pick one.
   - Recommendation: Use unique `session_id` count per skill (`jq` group-by session_id then count distinct). This is more meaningful than day-count: it answers "in how many Claude sessions was this skill used?"

2. **What to show for skills with no telemetry data at all (never appeared in log)**
   - What we know: D-08 says skills with 0 loads are `[retire?]`. But skills never mentioned in JSONL won't appear in the aggregation.
   - What's unclear: Should we join against `.claude/skills/` to show ALL known skills, including ones with 0 log entries?
   - Recommendation: Yes — join against `find .claude/skills -name SKILL.md` to discover all installed skills, then left-join against JSONL counts. Skills absent from the log appear with Loads=0 and status `[retire?]`.

3. **Timeout behavior when hook stdin hangs**
   - What we know: CC has a hook timeout (documented as keeping hooks under 2 seconds).
   - What's unclear: Whether we need an explicit `setTimeout` guard on stdin reading (like the 10s `stdinTimeout` mentioned in CONTEXT.md code insights).
   - Recommendation: Add a 5-second timeout: `const guard = setTimeout(() => process.exit(0), 5000)` before the stdin listener, cleared in the 'end' handler. This is defensive; stdin should arrive nearly instantly but the guard prevents a stuck hook from blocking the session.

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Node.js | skill-telemetry.mjs hook | ✓ | v24.15.0 | — (required by kit; pre-flighted) |
| jq | audit retire-list aggregation | ✓ | 1.8.1 | Advisory message printed; retire-list skipped |
| bash | audit-setup.sh, cli/conjure | ✓ | system | — |
| `date` (BSD/GNU) | 30-day cutoff calculation | ✓ | system | `0000-00-00` fallback (include all events) |

**Missing dependencies with no fallback:** none
**Missing dependencies with fallback:** `jq` (already pre-flighted; already handled gracefully in cost section)

---

## Validation Architecture

Config has `nyquist_validation: true` — Validation Architecture section is required.

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Hand-rolled `tests/run.sh` (existing) |
| Config file | none — self-contained bash script |
| Quick run command | `bash tests/run.sh 2>&1 \| tail -20` |
| Full suite command | `bash tests/run.sh` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| TLMY-01 | Hook exits 0 silently when CONJURE_TELEMETRY unset | unit (inline bash) | `bash tests/run.sh` (telemetry section) | ❌ Wave 0 |
| TLMY-01 | DO_NOT_TRACK=1 suppresses all writes | unit (inline bash) | `bash tests/run.sh` (telemetry section) | ❌ Wave 0 |
| TLMY-02 | Hook writes JSONL to target dir when CONJURE_TELEMETRY=1 | integration (inline bash) | `bash tests/run.sh` (telemetry section) | ❌ Wave 0 |
| TLMY-02 | Log file contains valid JSON lines | integration | `bash tests/run.sh` (telemetry section) | ❌ Wave 0 |
| TLMY-03 | No network egress patterns in skill-telemetry.mjs | static grep | `bash tests/run.sh` (telemetry section) | ❌ Wave 0 |
| TLMY-04 | `--retire-list` flag present in cli/conjure | static grep | `bash tests/run.sh` (telemetry section) | ❌ Wave 0 |
| TLMY-04 | retire-list section renders when CONJURE_RETIRE=1 | integration | `bash tests/run.sh` (telemetry section) | ❌ Wave 0 |
| TLMY-05 | TELEMETRY.md exists at repo root | file existence | `bash tests/run.sh` (telemetry section) | ❌ Wave 0 |
| TLMY-05 | TELEMETRY.md contains schema fields | grep | `bash tests/run.sh` (telemetry section) | ❌ Wave 0 |

### Sampling Rate

- **Per task commit:** `bash tests/run.sh 2>&1 | grep -E "PASS|FAIL|telemetry"`
- **Per wave merge:** `bash tests/run.sh`
- **Phase gate:** Full suite green before `/gsd-verify-work`

### Wave 0 Gaps

- [ ] Telemetry test section in `tests/run.sh` — covers TLMY-01 through TLMY-05 (added in Wave 3 of this phase)
- [ ] `templates/hooks-nodejs/skill-telemetry.mjs` — the hook itself (Wave 1)
- [ ] `TELEMETRY.md` — schema doc (Wave 1)

*(The test section and the hook are both new; the test section is created in Wave 3 after the hook and audit integration exist.)*

---

## Security Domain

`security_enforcement` not explicitly set to false in config — section required.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | telemetry is local file I/O, no auth needed |
| V3 Session Management | no | session_id is read-only from CC payload, not managed by this phase |
| V4 Access Control | no | local file append; OS file permissions are the only access control |
| V5 Input Validation | yes | `JSON.parse` with try/catch; extract only known fields; never log skill_args |
| V6 Cryptography | no | no secrets, no hashes, no encryption needed for local event log |

### Known Threat Patterns for this stack

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Skill args contain sensitive data → logged | Information Disclosure | Extract `skill_name` only, never `skill_args` or `command_args`; documented in D-05 |
| JSONL path traversal (malicious `cwd` in payload) | Tampering | `path.join(p.cwd, ...)` is safe; `cwd` is set by CC, not user input; no `..` traversal possible via join |
| Network egress added in future hook change | Repudiation | CI grep test (TLMY-03) breaks the build if any HTTP pattern appears |
| JSONL log committed to git, leaking project info | Information Disclosure | `.gitignore.tmpl` entry for `.claude/telemetry/` prevents accidental commit |

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `tool_input.skill_name` is the field name for skill name in PreToolUse payload | Hook Event Verification | Hook logs empty or null skill names; retire-list shows no data. Mitigate: add null check + graceful exit 0 |
| A2 | `command_name` in UserPromptExpansion payload is the slash command name without leading `/` | Hook Event Verification | Skill name logged with leading slash; retire-list join against `.claude/skills/` would fail. Mitigate: strip leading `/` defensively in hook |
| A3 | UserPromptExpansion with no matcher fires on all slash commands (including non-skills) | Architecture Patterns | Non-skill commands logged as skills; retire-list polluted. Mitigate: filter by command_source or post-process against known skills |

> Note: A1 and A2 are tagged `[ASSUMED]` because while the CC docs show the payload schema, confirming against a live CC ≥2.1.117 instance was not performed in this research session. The schema shown in official docs is authoritative but field names in fast-moving APIs sometimes differ from docs. The hook should be written defensively (`?.` optional chaining on all field accesses).

---

## Sources

### Primary (HIGH confidence)

- [code.claude.com/docs/en/hooks](https://code.claude.com/docs/en/hooks) — Full event list, PreToolUse/Skill payload schema (`tool_input.skill_name`), UserPromptExpansion payload (`command_name`, `expansion_type`), stdin delivery mechanism, exit code semantics, suppressOutput. Fetched 2026-05-25. [VERIFIED]
- Conjure codebase — `scripts/audit-setup.sh` (cost section pattern, lines 138–196), `cli/conjure` (cmd_audit pattern, lines 113–127), `templates/hooks-nodejs/stop-compound-engineering.mjs` (appendFileSync pattern), `tests/run.sh` (test section structure, cost tests lines 372–438), `templates/.gitignore.tmpl`, `tests/lib/sandbox.sh`. [VERIFIED: codebase grep]
- `.planning/phases/07-skill-firing-telemetry/07-CONTEXT.md` — All locked decisions D-01 through D-13. [VERIFIED]

### Secondary (MEDIUM confidence)

- `.planning/research/STACK.md` — Prior research on telemetry strategy (JSONL + jq recommendation), hook event confidence assessment. [CITED: internal planning doc, 2026-05-24]
- `.planning/research/PITFALLS.md` — Pitfall 3 (telemetry trust), Security mistakes table (PII logging, network egress). [CITED: internal planning doc, 2026-05-24]

### Tertiary (LOW confidence)

- None — all claims in this research were verified against official CC docs or the codebase.

---

## Metadata

**Confidence breakdown:**
- Hook event payload shape (tool_input.skill_name, command_name): HIGH — confirmed in official CC hooks docs
- stdin delivery mechanism: HIGH — confirmed in official CC docs with bash example
- Retire-list pattern: HIGH — directly mirrors cost estimator pattern in audited codebase
- Date portability: HIGH — verified pattern already in audit-setup.sh line 116
- UserPromptExpansion command_source filter: MEDIUM — schema confirmed but filter logic is discretionary

**Research date:** 2026-05-25
**Valid until:** 2026-06-25 (stable CC hooks API; 30 days before re-verification recommended)
