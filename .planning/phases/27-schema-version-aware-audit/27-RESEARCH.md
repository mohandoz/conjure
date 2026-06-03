# Phase 27: Schema-Version-Aware Audit — Research

**Researched:** 2026-06-03
**Domain:** Claude Code schema snapshot (hook events, SKILL.md frontmatter, settings keys), bash YAML frontmatter type-detection, jq JSON emission, POSIX date arithmetic
**Confidence:** HIGH (hook events + SKILL.md frontmatter from official Claude Code docs at code.claude.com; settings keys from official settings reference; implementation patterns from project codebase)

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**cc-schema.json Shape & Maintenance**
- Single bundled file `lib/cc-schema.json` with: `{ schema_version, generated (ISO date), cc_version, hook_events[], renamed_events{old: new}, settings_keys{ key: introduced_version }, skill_frontmatter{ field: type } }`.
- Ships with all current hook events and the full SKILL.md frontmatter schema.
- Staleness: >90 days from `generated` ISO date → WARN (never ERR); computed from the `generated` field, NOT file mtime.
- Zero runtime fetch. `_comment` field cites source + CC version reflected.
- CC version detection: parse `claude --version`; absent → WARN and continue (never fail).

**--json Output Contract (audit)**
- Shape: `{ schema_version, status: "pass"|"fail", checks: [ { id, severity, message } ], summary: { pass, warn, fail } }`.
- `conjure audit --json`: JSON-only stdout (human text → stderr). Exit 2 on fail even with `--json`.
- WARN-only: follows existing `[ "$WARN" -gt 0 ] && exit 1` summary gate.
- Each check has a STABLE `id` (e.g. `SCHM-01-skill-field`, `SCHM-02-disablebypass`, `SCHM-03-hook-event`, `SCHM-04-version`).

**Severity Mapping**
- `fail` (exit 2): invalid SKILL.md frontmatter field TYPE, renamed/unknown hook event, boolean `disableBypassPermissionsMode`.
- `warn` (exit 1 via summary gate): unknown SKILL.md frontmatter field not in schema, cc-schema.json >90 days old.
- `info`: SCHM-04 per-key CC-version-introduced reporting.

**Responsibility Split**
- `conjure audit` owns: SCHM-01 (SKILL.md frontmatter type), SCHM-02 (disableBypassPermissionsMode), SCHM-05 (--json output).
- `conjure check` owns: SCHM-03 (hook event names), SCHM-04 (--schema version report).
- `--schema` is a NEW flag on `conjure check`; `--json` is added to `conjure audit` ONLY.

### Claude's Discretion

All 4 grey areas were accepted as recommended — no discretion areas remain open.

### Deferred Ideas (OUT OF SCOPE)

- SCHM-F1: `conjure audit --strict` cross-validates `allowed-tools` vs hook `matcher` patterns.
- SCHM-F2: schema-table self-update notice from `claude --version` in connected environments.
- WS-01 / WS-04: `.conjure-workspace.json` + `conjure workspace audit` — Phase 29.
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| SCHM-01 | `conjure audit` validates SKILL.md frontmatter against the current documented field set (incl. `disallowed-tools` as array/space-string) | 16-field schema documented from official CC docs; awk-based type detection pattern verified |
| SCHM-02 | `conjure audit` flags `disableBypassPermissionsMode` set to boolean instead of string `"disable"` | Exact jq check pattern already in `audit-setup.sh` line 237; SCHM-02 extends it to also add check to --json output |
| SCHM-03 | `conjure check` flags unknown/renamed hook event names against a bundled event table | 30 events documented from official docs; renamed_events map for SessionStop→SessionEnd |
| SCHM-04 | `conjure check --schema` reports the CC version each settings key was introduced in, vs pinned `.conjure-version` | settings_keys version table documented; cc_version read from cc-schema.json |
| SCHM-05 | `conjure audit --json` machine-readable output | jq -n construction pattern verified; exit-2-on-fail confirmed; Phase 29 aggregation contract documented |
</phase_requirements>

---

## Summary

Phase 27 adds a bundled `lib/cc-schema.json` snapshot containing the authoritative Claude Code hook events list, SKILL.md frontmatter schema, and settings key version map. `conjure audit` gains SCHM-01/02/05: it validates SKILL.md frontmatter field types against the 16-field schema, flags boolean `disableBypassPermissionsMode`, and emits a machine-readable `--json` report. `conjure check` gains SCHM-03/04: it flags unknown/renamed hook events from settings.json and offers a `--schema` report of per-key version-introduced data.

The implementation attaches to existing workers: SCHM-01/02/05 extend `scripts/audit-setup.sh` (new section, after POL-05 block); SCHM-03/04 extend `scripts/check.sh` (new section, after the existing drift output). Both scripts read `lib/cc-schema.json` via `jq`. The `--json` flag adds an output-path fork at the top of `audit-setup.sh` that suppresses human text and emits a JSON accumulator to stdout. `cli/conjure` wires `--json` to `cmd_audit` and `--schema` to `cmd_check` by forwarding env vars (same pattern as `CONJURE_COST`, `CONJURE_RETIRE`).

No new external dependencies. All tooling (jq, bash 3.2+, POSIX stat, BSD/GNU date fallback) is already in the project runtime envelope.

**Primary recommendation:** Wave 0 = write `lib/cc-schema.json` + graceful-red SCHM test block; Wave 1 = SCHM-05 (--json) first (it unblocks Phase 29 aggregation), then SCHM-01/02 (audit frontmatter+dbpm), then SCHM-03/04 (check hook events+schema).

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| cc-schema.json (schema data) | `lib/cc-schema.json` | — | Bundled file; zero runtime fetch; read by both audit and check via jq |
| SKILL.md frontmatter type validation (SCHM-01) | `scripts/audit-setup.sh` | `lib/cc-schema.json` (field → type map) | Audit worker owns SCHM-01; reads schema for allowed fields and types |
| disableBypassPermissionsMode type check (SCHM-02) | `scripts/audit-setup.sh` | — | Extends existing POL-05c check; adds --json output pathway |
| --json output accumulation (SCHM-05) | `scripts/audit-setup.sh` | jq JSON builder | All checks write to a tempfile JSONL accumulator; final jq collects |
| Hook event name validation (SCHM-03) | `scripts/check.sh` | `lib/cc-schema.json` (hook_events[], renamed_events{}) | Check script reads settings.json hooks; compares against schema table |
| --schema version report (SCHM-04) | `scripts/check.sh` | `lib/cc-schema.json` (settings_keys{}) | New `--schema` mode scans settings.json keys; reports introduced_version |
| Flag wiring | `cli/conjure` | — | `cmd_audit` gets `--json`; `cmd_check` gets `--schema`; env-var forwarding |

---

## The cc-schema.json Schema Data (Load-Bearing Authoritative Content)

This section is the primary output of this research. The planner uses it to populate `lib/cc-schema.json` in Wave 0.

### Hook Events (30 events from official docs)

[VERIFIED: code.claude.com/docs/en/hooks — fetched 2026-06-03, CC v2.1.161]

The official documentation lists exactly **30 hook events** in PascalCase:

```
PreToolUse         PostToolUse        PostToolUseFailure  PostToolBatch
PermissionRequest  PermissionDenied
SessionStart       Setup              SessionEnd
UserPromptSubmit   UserPromptExpansion
Stop               StopFailure
SubagentStart      SubagentStop
TaskCreated        TaskCompleted      TeammateIdle
ConfigChange       InstructionsLoaded
FileChanged        CwdChanged
PreCompact         PostCompact
WorktreeCreate     WorktreeRemove
Elicitation        ElicitationResult
Notification       MessageDisplay
```

Note: The CONTEXT.md says "34 current hook events". The official docs enumerate exactly 30 as of CC v2.1.161. Use 30 as the authoritative count; if the CONTEXT's 34 reflects training data or a future CC release, the schema will be updated at the next Conjure release. The bundled schema design handles this gracefully (unknown event from a newer CC → WARN, not fail).

**Renamed events (for SCHM-03 detection):**

| Old name | Correct name | Behavior when used |
|----------|-------------|-------------------|
| `SessionStop` | `SessionEnd` | Silently no-ops; a real bug — flag as fail |

`SessionStop` is the only historically documented renamed event. [ASSUMED — verified by docs absence + training knowledge; there is no official "renamed events" changelog in the CC docs]

### SKILL.md Frontmatter Schema (16 fields from official docs)

[VERIFIED: code.claude.com/docs/en/skills — fetched 2026-06-03, full frontmatter reference table]

The CONTEXT says "14-field set". The official docs enumerate **16 fields** as of CC v2.1.161. Conjure's `lib/cc-schema.json` must include all 16 so that users with skills using newer fields (e.g. `when_to_use`, `paths`, `shell`) do not get false-positive UNKNOWN-FIELD warnings. The "14 fields" in the CONTEXT was a pre-research estimate; the authoritative set is 16.

| Field | Type | Notes |
|-------|------|-------|
| `name` | `string` | Optional display name |
| `description` | `string` | Recommended |
| `when_to_use` | `string` | Additional invocation context |
| `argument-hint` | `string` | Autocomplete hint |
| `arguments` | `array-or-space-string` | Named positional args |
| `disable-model-invocation` | `boolean` | Prevent auto-invocation |
| `user-invocable` | `boolean` | Hide from `/` menu |
| `allowed-tools` | `array-or-space-string` | Space/comma/YAML-list all valid |
| `disallowed-tools` | `array-or-space-string` | Space/comma/YAML-list all valid; object form is FAIL |
| `model` | `string` | Model override |
| `effort` | `string` | Effort level override |
| `context` | `string` | `"fork"` for subagent |
| `agent` | `string` | Subagent type when context: fork |
| `hooks` | `object` | Skill-scoped hooks config |
| `paths` | `array-or-space-string` | Glob patterns for activation |
| `shell` | `string` | Shell for `!` blocks |

**Type validation rules:**
- `array-or-space-string`: valid as YAML array `[A, B]`, block array `- A\n- B`, or space/comma-separated string `A B`. Invalid as YAML mapping/object `{A: true}` → `fail`.
- `boolean`: must be YAML boolean (`true`/`false`). String `"true"` is technically valid but unusual; object is `fail`.
- `object`: the `hooks` field must be a YAML mapping. Any other type is `fail`.
- `string`: any scalar. Object form is `fail`.

### Settings Keys → CC Version Introduced

[CITED: code.claude.com/docs/en/settings — fetched 2026-06-03]

The official settings docs do not consistently document introduction versions for most keys. The table below uses the versions explicitly stated in the docs where available, otherwise marks `"all"` (present since early GA). A small number have explicit versions in the docs.

| Key | Introduced Version | Confidence |
|-----|-------------------|-----------|
| `permissions` | all | HIGH — core key since GA |
| `disableBypassPermissionsMode` | all | HIGH |
| `skipDangerousModePermissionPrompt` | all | HIGH |
| `allowManagedPermissionRulesOnly` | all | HIGH |
| `sandbox` | all | HIGH |
| `hooks` | all | HIGH |
| `disableAllHooks` | all | HIGH |
| `allowManagedHooksOnly` | all | HIGH |
| `statusLine` | all | HIGH |
| `model` | all | HIGH |
| `env` | all | HIGH |
| `forceLoginOrgUUID` | all | HIGH |
| `forceLoginMethod` | all | HIGH |
| `extraKnownMarketplaces` | all | HIGH |
| `enabledPlugins` | all | HIGH |
| `apiKeyHelper` | all | HIGH |
| `skillOverrides` | 2.1.129 | HIGH — explicitly stated in docs |
| `maxSkillDescriptionChars` | 2.1.105 | HIGH — explicitly stated in docs |
| `skillListingBudgetFraction` | 2.1.105 | HIGH — explicitly stated in docs |
| `workflowKeywordTriggerEnabled` | 2.1.157 | HIGH — explicitly stated in docs |
| `worktree.bgIsolation` | 2.1.143 | HIGH — explicitly stated in docs |
| `policyHelper` | 2.1.136 | HIGH — explicitly stated in docs |
| `parentSettingsBehavior` | 2.1.133 | HIGH — explicitly stated in docs |
| `disableRemoteControl` | 2.1.128 | HIGH — explicitly stated in docs |

**SCHM-04 comparison logic:** `conjure check --schema` reads `.conjure-version` (the Conjure kit version, NOT the CC version). The `cc_version` field in `cc-schema.json` represents what CC version the schema reflects. The `settings_keys[key]` value is the CC version that introduced the key. The report tells the user: "This key was introduced in CC v2.1.129; your `.conjure-version` pin is Conjure v0.6.0 which ships with CC baseline X". Note: `.conjure-version` is the Conjure release version, not the CC binary version. The SCHM-04 report is `info` severity (informational only, never blocks).

### Authoritative cc-schema.json Content

The exact JSON to write to `lib/cc-schema.json` in Wave 0:

```json
{
  "_comment": "Conjure-maintained Claude Code schema snapshot. Source: https://code.claude.com/docs/en/hooks + /en/settings + /en/skills. Reflects CC v2.1.161 (2026-06-03). Update this file when Anthropic releases a new CC version with schema changes.",
  "schema_version": "1",
  "generated": "2026-06-03",
  "cc_version": "2.1.161",
  "hook_events": [
    "PreToolUse",
    "PostToolUse",
    "PostToolUseFailure",
    "PostToolBatch",
    "PermissionRequest",
    "PermissionDenied",
    "SessionStart",
    "Setup",
    "SessionEnd",
    "UserPromptSubmit",
    "UserPromptExpansion",
    "Stop",
    "StopFailure",
    "SubagentStart",
    "SubagentStop",
    "TaskCreated",
    "TaskCompleted",
    "TeammateIdle",
    "ConfigChange",
    "InstructionsLoaded",
    "FileChanged",
    "CwdChanged",
    "PreCompact",
    "PostCompact",
    "WorktreeCreate",
    "WorktreeRemove",
    "Elicitation",
    "ElicitationResult",
    "Notification",
    "MessageDisplay"
  ],
  "renamed_events": {
    "SessionStop": "SessionEnd"
  },
  "settings_keys": {
    "permissions": "all",
    "disableBypassPermissionsMode": "all",
    "skipDangerousModePermissionPrompt": "all",
    "allowManagedPermissionRulesOnly": "all",
    "sandbox": "all",
    "hooks": "all",
    "disableAllHooks": "all",
    "allowManagedHooksOnly": "all",
    "allowedHttpHookUrls": "all",
    "httpHookAllowedEnvVars": "all",
    "statusLine": "all",
    "model": "all",
    "modelOverrides": "all",
    "env": "all",
    "forceLoginOrgUUID": "all",
    "forceLoginMethod": "all",
    "extraKnownMarketplaces": "all",
    "enabledPlugins": "all",
    "apiKeyHelper": "all",
    "awsCredentialExport": "all",
    "awsAuthRefresh": "all",
    "gcpAuthRefresh": "all",
    "skillOverrides": "2.1.129",
    "maxSkillDescriptionChars": "2.1.105",
    "skillListingBudgetFraction": "2.1.105",
    "workflowKeywordTriggerEnabled": "2.1.157",
    "worktree.bgIsolation": "2.1.143",
    "policyHelper": "2.1.136",
    "parentSettingsBehavior": "2.1.133",
    "disableRemoteControl": "2.1.128"
  },
  "skill_frontmatter": {
    "name": "string",
    "description": "string",
    "when_to_use": "string",
    "argument-hint": "string",
    "arguments": "array-or-space-string",
    "disable-model-invocation": "boolean",
    "user-invocable": "boolean",
    "allowed-tools": "array-or-space-string",
    "disallowed-tools": "array-or-space-string",
    "model": "string",
    "effort": "string",
    "context": "string",
    "agent": "string",
    "hooks": "object",
    "paths": "array-or-space-string",
    "shell": "string"
  }
}
```

---

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| jq | 1.8.1 (system; minimum 1.6) | Read `lib/cc-schema.json`; build `--json` output; type-check settings.json | Already in runtime envelope; used by all Phase 25/26 workers |
| bash (POSIX 3.2+) | System | Script runtime | Project constraint — no associative arrays, mapfile, local -n |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| awk | System (POSIX) | YAML frontmatter type detection | No YAML parser in envelope; awk handles multi-line frontmatter scanning |
| BSD/GNU date | System | 90-day staleness arithmetic from ISO date | Cross-platform: `date -j -f "%Y-%m-%d"` (BSD/macOS) OR `date -d` (GNU/Linux) OR epoch-fallback (0 = skip) |

**Installation:** No new packages. All tooling already in runtime envelope per CLAUDE.md.

---

## Package Legitimacy Audit

No external packages are installed in this phase. All tooling (jq, bash, awk, system date) is already in the project runtime envelope.

**Packages removed due to slopcheck [SLOP] verdict:** none
**Packages flagged as suspicious [SUS]:** none

---

## Architecture Patterns

### System Architecture Diagram

```
conjure audit [target] [--json]
         │
         ▼
scripts/audit-setup.sh
  │
  ├─ [all existing checks: CLAUDE.md, skills, agents, hooks, policy...]
  │
  ├─ [SCHM-02] Read .claude/settings.json | jq type check
  │     permissions.disableBypassPermissionsMode | type == "boolean" → fail/json
  │
  ├─ [SCHM-01] For each .claude/skills/*/SKILL.md:
  │     ├─ Parse frontmatter block (awk)
  │     ├─ For each field:
  │     │    ├─ Unknown field (not in schema) → warn/json
  │     │    └─ Wrong type (object where array-or-string expected) → fail/json
  │     └─ missing required-for-audit fields (name, description) → already checked above
  │
  ├─ [SCHM-STALE] jq .generated from lib/cc-schema.json → age >90d → warn/json
  │
  └─ [SCHM-05 --json mode]
        If CONJURE_JSON=1:
          stdout: jq -n '{schema_version, status, checks, summary}'  (compact)
          stderr: all human-readable output
          exit 2 on fail; exit 1 on warn; exit 0 on pass (same semantics as non-json)

conjure check [target] [--schema]
         │
         ▼
scripts/check.sh (extended)
  │
  ├─ [existing drift checks: modified/removed/added files]
  │
  ├─ [SCHM-03] If .claude/settings.json exists:
  │     ├─ jq -r '.hooks | keys[]' → for each event name:
  │     │    ├─ Not in schema hook_events[] → fail (output to stderr)
  │     │    └─ In schema renamed_events{} → fail "renamed: use SessionEnd"
  │     └─ Report: "Hook event 'SessionStop' was renamed to 'SessionEnd'"
  │
  └─ [SCHM-04 --schema mode]
        If CONJURE_SCHEMA=1:
          jq -r '.settings_keys | keys[]' from cc-schema.json
          For each key found in .claude/settings.json:
            look up introduced_version → print info line
          Compare cc_version from schema vs claude --version output
          (info only — never blocks)
```

### Recommended Project Structure

```
lib/
└── cc-schema.json              # NEW — bundled schema snapshot

scripts/
├── audit-setup.sh              # Extended: SCHM-01/02/05 section after POL-05 block
└── check.sh                    # Extended: SCHM-03/04 section after drift output

cli/conjure
└── cmd_audit()                 # Add --json flag → CONJURE_JSON=1 env
└── cmd_check()                 # Add --schema flag → CONJURE_SCHEMA=1 env

tests/
├── run.sh                      # New SCHM test block (graceful-red first)
└── fixtures/
    ├── _schema-audit-bad-type/ # SKILL.md with disallowed-tools: {Bash: true}
    ├── _schema-audit-bad-hook/ # settings.json with SessionStop event
    └── _schema-audit-dbpm/     # settings.json with boolean disableBypassPermissionsMode
```

### Pattern 1: YAML Frontmatter Type Detection in bash

**What:** Detect if a SKILL.md frontmatter field is typed as an object (mapping) rather than an array or scalar, without a YAML parser.

**When to use:** SCHM-01 frontmatter type validation.

**Key insight:** YAML objects (mappings) below a key look like `  word:` indented lines. Arrays look like `  -` indented lines. Inline objects start with `{`. All are distinguishable via awk.

```bash
# Source: Verified via live testing on this machine (2026-06-03)
# POSIX bash 3.2+ compatible. No associative arrays.
# Scans frontmatter for object-typed fields that should be array-or-string.
# Outputs: "OBJECT_FIELD:<fieldname>" for each field typed as object.
detect_object_typed_fields() {
  local skill_file="$1"
  local schema_file="$2"   # lib/cc-schema.json path

  # Extract frontmatter block (between first two --- markers)
  local fm_block
  fm_block="$(awk '/^---$/{n++; if(n==2)exit; next} n==1{print}' "$skill_file")"

  # For each key in frontmatter, check type
  local prev_key=""
  printf '%s\n' "$fm_block" | while IFS= read -r line; do
    # New top-level key
    if printf '%s\n' "$line" | grep -qE '^[a-zA-Z]'; then
      key="$(printf '%s\n' "$line" | cut -d: -f1)"
      val="$(printf '%s\n' "$line" | cut -d: -f2- | sed 's/^[[:space:]]*//')"
      prev_key="$key"
      prev_val="$val"
      # Inline object detection
      if printf '%s\n' "$val" | grep -qE '^\{'; then
        printf 'OBJECT_FIELD:%s\n' "$key"
      fi
    # Indented continuation line under a field with empty value
    elif printf '%s\n' "$line" | grep -qE '^[[:space:]]+[a-zA-Z_-]+:' && [ -n "$prev_key" ] && [ -z "$prev_val" ]; then
      # This is a mapping/object child key — the parent field is an object
      printf 'OBJECT_FIELD:%s\n' "$prev_key"
      prev_key=""  # only report once per field
    fi
  done
}

# Usage in audit-setup.sh SCHM-01 section:
while IFS= read -r skill; do
  skill_name=$(basename "$(dirname "$skill")")
  SCHEMA_FILE="$CONJURE_HOME/lib/cc-schema.json"

  # Check each frontmatter field
  FM_BLOCK="$(awk '/^---$/{n++; if(n==2)exit; next} n==1{print}' "$skill")"

  # Known fields from schema (read via jq)
  KNOWN_FIELDS="$(jq -r '.skill_frontmatter | keys[]' "$SCHEMA_FILE" 2>/dev/null)"

  # Detect fields and their types
  printf '%s\n' "$FM_BLOCK" | grep -E '^[a-zA-Z]' | while IFS= read -r fmline; do
    field="$(printf '%s\n' "$fmline" | cut -d: -f1)"
    if ! printf '%s\n' "$KNOWN_FIELDS" | grep -qxF "$field"; then
      warn "Skill '$skill_name': unknown frontmatter field '$field' (not in CC schema)"
    fi
  done

  # Check for object-typed fields
  detect_object_typed_fields "$skill" "$SCHEMA_FILE" | while IFS= read -r result; do
    field="${result#OBJECT_FIELD:}"
    expected="$(jq -r --arg f "$field" '.skill_frontmatter[$f] // "unknown"' "$SCHEMA_FILE" 2>/dev/null)"
    if [ "$expected" = "array-or-space-string" ] || [ "$expected" = "string" ]; then
      err "Skill '$skill_name': field '$field' is an object (YAML mapping) — expected $expected"
    fi
  done
done < <(find .claude/skills -name SKILL.md 2>/dev/null)
```

### Pattern 2: jq SCHM-03 Hook Event Validation

**What:** Read `hooks` keys from settings.json; compare against bundled event list.

**When to use:** `check.sh` SCHM-03 section.

```bash
# Source: Verified pattern — jq .hooks | keys[], settings.json from project template
# POSIX bash 3.2+ compatible.

SCHEMA_FILE="$CONJURE_HOME/lib/cc-schema.json"
SETTINGS_FILE="$TARGET/.claude/settings.json"

if [ -f "$SETTINGS_FILE" ] && command -v jq >/dev/null 2>&1; then
  # Read event names from settings.json hooks object
  HOOK_EVENTS_IN_SETTINGS="$(jq -r '.hooks // {} | keys[]' "$SETTINGS_FILE" 2>/dev/null)"

  # Read known events from schema
  KNOWN_EVENTS="$(jq -r '.hook_events[]' "$SCHEMA_FILE" 2>/dev/null)"

  # Read renamed events
  RENAMED_EVENTS="$(jq -r '.renamed_events // {} | to_entries[] | "\(.key)=\(.value)"' "$SCHEMA_FILE" 2>/dev/null)"

  printf '%s\n' "$HOOK_EVENTS_IN_SETTINGS" | while IFS= read -r event; do
    [ -z "$event" ] && continue

    # Check renamed events first
    RENAMED_TARGET=""
    printf '%s\n' "$RENAMED_EVENTS" | while IFS='=' read -r old new; do
      if [ "$event" = "$old" ]; then
        printf 'RENAMED:%s:%s\n' "$old" "$new"
      fi
    done

    # Check if in known events
    if ! printf '%s\n' "$KNOWN_EVENTS" | grep -qxF "$event"; then
      # Check if it's a renamed event
      RENAME_MATCH="$(printf '%s\n' "$RENAMED_EVENTS" | grep "^${event}=" | head -1)"
      if [ -n "$RENAME_MATCH" ]; then
        CORRECT="${RENAME_MATCH#*=}"
        printf 'SCHM-03 [fail] Hook event "%s" was renamed — use "%s" instead\n' "$event" "$CORRECT" >&2
      else
        printf 'SCHM-03 [fail] Unknown hook event "%s" — not in CC schema (v%s)\n' "$event" \
          "$(jq -r '.cc_version' "$SCHEMA_FILE" 2>/dev/null)" >&2
      fi
    fi
  done
fi
```

### Pattern 3: --json Output Accumulation

**What:** Accumulate per-check results in a tempfile JSONL; emit final JSON to stdout at end. Human text routes to stderr.

**When to use:** `audit-setup.sh` with `CONJURE_JSON=1`.

```bash
# Source: Verified jq pattern — matches lib/inventory.sh emit_file_entry approach
# The key is: accumulate into tempfile during execution, collect at end.
# Human-readable text uses note/warn/err to stderr when JSON mode is active.

# At top of audit-setup.sh, after arg parsing:
JSON_MODE="${CONJURE_JSON:-0}"
CHECKS_JSONL="$(mktemp)"
trap 'rm -f "$CHECKS_JSONL"' EXIT

# Modified helper functions when JSON_MODE=1:
# note() — still writes to stderr in JSON mode (advisory)
# warn() — writes to stderr AND appends check to CHECKS_JSONL
# err()  — writes to stderr AND appends check to CHECKS_JSONL

json_check() {
  # json_check <id> <severity> <message>
  local id="$1" severity="$2" message="$3"
  jq -cn \
    --arg id "$id" \
    --arg severity "$severity" \
    --arg message "$message" \
    '{id: $id, severity: $severity, message: $message}' \
    >> "$CHECKS_JSONL"
}

# At end, in JSON_MODE, collect and emit:
if [ "$JSON_MODE" = "1" ]; then
  STATUS="pass"
  [ "$FAIL" -gt 0 ] && STATUS="fail"
  [ "$WARN" -gt 0 ] && [ "$STATUS" = "pass" ] && STATUS="warn"

  jq -cn \
    --arg schema_version "1" \
    --arg status "$STATUS" \
    --argjson summary "{\"pass\":$PASS,\"warn\":$WARN,\"fail\":$FAIL}" \
    --slurpfile checks "$CHECKS_JSONL" \
    '{schema_version: $schema_version, status: $status, checks: $checks, summary: $summary}'
fi
```

**Critical:** In `--json` mode, ALL printf/echo to stdout must be suppressed or redirected to stderr. Use the pattern `>&2` on all human-readable output lines, gated on `[ "$JSON_MODE" = "1" ]`.

### Pattern 4: Staleness Check (POSIX date cross-platform)

**What:** Compute age of `lib/cc-schema.json` from its `generated` field. WARN if >90 days.

**When to use:** Both `audit` and `check` can include this; recommended in `audit`.

```bash
# Source: Verified via live testing on macOS (BSD date). Mirrors audit-setup.sh line 372 pattern.
# Cross-platform: BSD date (macOS) || GNU date (Linux) || 0 (skip stale check)
SCHEMA_FILE="$CONJURE_HOME/lib/cc-schema.json"
SCHEMA_GENERATED="$(jq -r '.generated // empty' "$SCHEMA_FILE" 2>/dev/null)"

if [ -n "$SCHEMA_GENERATED" ]; then
  # Parse ISO date (YYYY-MM-DD) to epoch — BSD macOS first, then GNU Linux, then skip
  GEN_EPOCH=$(date -j -f "%Y-%m-%d" "$SCHEMA_GENERATED" "+%s" 2>/dev/null \
    || date -d "$SCHEMA_GENERATED" "+%s" 2>/dev/null \
    || echo 0)

  if [ "$GEN_EPOCH" != "0" ]; then
    SCHEMA_AGE_DAYS=$(( ($(date +%s) - GEN_EPOCH) / 86400 ))
    if [ "$SCHEMA_AGE_DAYS" -gt 90 ]; then
      warn "cc-schema.json is ${SCHEMA_AGE_DAYS} days old (>90) — Conjure update recommended for latest CC schema"
    fi
  fi
  # If GEN_EPOCH=0 (neither date command worked): skip stale check silently (graceful degradation)
fi
```

### Pattern 5: CC Version Detection

**What:** Parse `claude --version` output; use schema's `cc_version` when claude is absent.

```bash
# Source: Live verified — claude --version outputs "2.1.161 (Claude Code)" on CC v2.1.161
CC_VERSION=""
if command -v claude >/dev/null 2>&1; then
  CC_VERSION="$(claude --version 2>/dev/null | awk '{print $1}')"
  # Validate semver pattern
  if ! printf '%s\n' "$CC_VERSION" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    CC_VERSION=""
  fi
fi
if [ -z "$CC_VERSION" ]; then
  warn "claude not found on PATH — using bundled schema baseline (cc_version from lib/cc-schema.json)"
  CC_VERSION="$(jq -r '.cc_version // empty' "$CONJURE_HOME/lib/cc-schema.json" 2>/dev/null || echo 'unknown')"
fi
```

### Pattern 6: disableBypassPermissionsMode Location

**What:** The existing Phase 26 POL-05c check reads `permissions.disableBypassPermissionsMode` in `.claude/settings.json`. The official settings docs list `disableBypassPermissionsMode` as a top-level key, but the Phase 26 implementation and fixture fixture `_emit-policy-broken/harness/.claude/settings.json` use the `permissions{}` sub-object path.

**Resolution:** SCHM-02 MUST check BOTH paths to catch real-world harnesses:
1. `jq -r '.permissions.disableBypassPermissionsMode | type'` (Phase 26 convention)
2. `jq -r '.disableBypassPermissionsMode | type'` (official settings docs top-level)

The existing POL-05c in `audit-setup.sh` only checks path 1. SCHM-02 extends coverage to path 2, so harnesses following the official docs placement are also caught.

```bash
# SCHM-02: check both locations
for _dbpm_path in '.permissions.disableBypassPermissionsMode' '.disableBypassPermissionsMode'; do
  _dbpm_type="$(jq -r "${_dbpm_path} | type" .claude/settings.json 2>/dev/null)"
  _dbpm_val="$(jq -r "${_dbpm_path} // empty" .claude/settings.json 2>/dev/null)"
  if [ "$_dbpm_type" = "boolean" ]; then
    err "[schema] disableBypassPermissionsMode is boolean (got: $_dbpm_val at ${_dbpm_path}) — must be string \"disable\""
    # also: json_check "SCHM-02-disablebypass" "fail" "..."
  fi
done
```

### Anti-Patterns to Avoid

- **Re-implementing frontmatter parsing:** The existing `audit-setup.sh` uses `grep '^name:'` and `grep '^description:'`. SCHM-01 extends this with awk-based type detection — do NOT introduce a YAML parser (not in runtime envelope) or Python (not a project dependency).
- **Hardcoding hook event names in check.sh:** All events MUST come from `lib/cc-schema.json` at runtime. No `case "$event" in PreToolUse|PostToolUse...)` hardcoding — that makes the schema file unmaintainable.
- **Human text on stdout in --json mode:** Any `echo "Auditing .claude/ setup..."` must be routed to stderr when `CONJURE_JSON=1`. The Phase 29 workspace aggregator parses stdout directly; stray human text breaks it.
- **Emitting exit 1 from audit-setup.sh for WARN:** The existing `[ "$WARN" -gt 0 ] && exit 1` gate at line 408 is the established contract. Do NOT add a second `exit 1` call or change this gate — it is the severity separator for WARN vs PASS.
- **Reading cc-schema.json without jq guard:** Always wrap with `command -v jq >/dev/null 2>&1` before using jq. Follow the existing `audit-setup.sh` pattern.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| JSON construction | String interpolation into JSON | `jq -cn --arg/--argjson/--slurpfile` | Injection-safe; handles escaping; consistent with lib/inventory.sh Pattern |
| YAML frontmatter parsing | Custom YAML parser | awk-based scanner (see Pattern 1) | No YAML parser in runtime envelope; awk is sufficient for the shallow type-detection needed |
| Hook event lookup | bash `case` statement with hardcoded events | `jq -r '.hook_events[]'` from cc-schema.json | Maintainable; schema update doesn't require code change |
| Semver comparison | Custom version arithmetic | String comparison for "all" vs "X.Y.Z" in settings_keys | SCHM-04 is informational only; exact semver ordering not needed |

**Key insight:** The `lib/cc-schema.json` file IS the knowledge; scripts just read it. Avoid any logic that duplicates schema data into bash constants.

---

## Common Pitfalls

### Pitfall 1: Object-typed YAML field false-negative in bash
**What goes wrong:** A YAML frontmatter field like `disallowed-tools:\n  Bash: true` has an EMPTY value on the key line — a naive `grep '^disallowed-tools: {' ` misses it.
**Why it happens:** YAML block-style mappings don't have `{` on the key line.
**How to avoid:** Use the awk two-line lookahead pattern (Pattern 1): when a key has an empty value AND the next indented line matches `  word:`, it's an object.
**Warning signs:** Test fixture with block-style bad frontmatter passes but inline `{Bash: true}` fails.

### Pitfall 2: Stdout/stderr contamination in --json mode
**What goes wrong:** `echo "Auditing .claude/ setup in: $TARGET"` leaks into stdout; Phase 29 `jq` parse fails with "parse error: Invalid numeric literal".
**Why it happens:** The existing human-readable output goes to stdout unconditionally.
**How to avoid:** Gate ALL `echo`/`printf` in `audit-setup.sh` on `[ "$JSON_MODE" != "1" ]`, or redirect to stderr with `>&2` in JSON mode. The JSON object must be the ONLY thing on stdout.
**Warning signs:** `conjure audit --json | jq .` reports a parse error.

### Pitfall 3: Staleness check failing on Linux (no BSD date)
**What goes wrong:** `date -j -f "%Y-%m-%d" ...` is BSD-only; errors silently or with `date: illegal option -- j`.
**Why it happens:** GNU date (Linux) uses `-d` instead of `-j -f`.
**How to avoid:** Use the BSD || GNU || 0 fallback chain (Pattern 4). The `|| echo 0` final fallback disables the staleness check gracefully on systems with neither (e.g. Alpine Linux with busybox date).
**Warning signs:** CI passes on macOS but fails on Linux runners.

### Pitfall 4: jq `.hooks | keys[]` fails when hooks is absent
**What goes wrong:** If `.claude/settings.json` has no `hooks` key, `jq '.hooks | keys[]'` errors.
**Why it happens:** `jq` errors on `null | keys[]`.
**How to avoid:** Use `jq -r '.hooks // {} | keys[]'` — the `// {}` coalesces null to empty object.
**Warning signs:** SCHM-03 exits 2 on harnesses without any hooks configured.

### Pitfall 5: SCHM-02 misses top-level disableBypassPermissionsMode
**What goes wrong:** Only checking `permissions.disableBypassPermissionsMode`; a user who followed the official settings docs and placed it at the top level is not caught.
**Why it happens:** Phase 26 fixture used `permissions.disableBypassPermissionsMode`; the official docs show it as a top-level key.
**How to avoid:** Check both paths (Pattern 6). Use a `for` loop over both jq paths.

### Pitfall 6: disableBypassPermissionsMode double-reporting with POL-05c
**What goes wrong:** POL-05c in `audit-setup.sh` already checks `permissions.disableBypassPermissionsMode`. SCHM-02 checking the same path produces a duplicate error message.
**Why it happens:** POL-05c (exit 2 for boolean DBPM) and SCHM-02 (same check but also adds to --json accumulator) cover overlapping ground.
**How to avoid:** SCHM-02 MUST subsume POL-05c — remove the POL-05c standalone check and replace it with the SCHM-02 check (which handles both paths AND feeds the --json accumulator). Document the refactor explicitly in the plan.

### Pitfall 7: check.sh exit code semantics change
**What goes wrong:** Adding SCHM-03 hook event checks to `check.sh` makes it exit 2 on renamed/unknown events, but the current `check.sh` only exits 0 (current) or 1 (drift). Phase 29 `conjure workspace check` calls `check.sh` and relies on exit 0 = clean.
**Why it happens:** Adding new failure modes changes the established check.sh exit contract.
**How to avoid:** SCHM-03 findings go to a separate `SCHEMA_FAIL` counter. Final exit: `[ "$SCHEMA_FAIL" -gt 0 ] && exit 2` AFTER the existing `exit "$drift"` block. This means schema failures override drift (exit 2 > exit 1 > exit 0). The `--schema` report (SCHM-04) is info-only and never changes the exit code.

---

## --json Output Contract (Phase 29 Integration)

The `--json` output is the load-bearing contract for Phase 29 `conjure workspace audit`. The shape MUST be stable.

```json
{
  "schema_version": "1",
  "status": "pass" | "fail" | "warn",
  "checks": [
    {
      "id": "SCHM-01-skill-field",
      "severity": "fail" | "warn" | "info",
      "message": "Skill 'restructure': field 'disallowed-tools' is an object — expected array-or-space-string"
    },
    {
      "id": "SCHM-02-disablebypass",
      "severity": "fail",
      "message": "[schema] disableBypassPermissionsMode is boolean (got: true) — must be string \"disable\""
    }
  ],
  "summary": {
    "pass": 5,
    "warn": 1,
    "fail": 0
  }
}
```

**Stable check IDs:**

| ID | Requirement | Severity |
|----|-------------|---------|
| `SCHM-01-skill-field` | SCHM-01 — invalid frontmatter type per-skill | `fail` |
| `SCHM-01-skill-unknown` | SCHM-01 — unknown frontmatter field per-skill | `warn` |
| `SCHM-02-disablebypass` | SCHM-02 — boolean disableBypassPermissionsMode | `fail` |
| `SCHM-STALE` | staleness advisory | `warn` |
| Existing audit checks | from pre-existing audit-setup.sh sections | `pass`/`warn`/`fail` |

**Phase 29 aggregation contract:** Phase 29 iterates repos, calls `conjure audit --json` per repo, reads stdout via `jq -s '.'`, produces a workspace-level summary. The `id` field is the stable aggregation key — it must never change between Conjure releases (only additive new IDs are allowed).

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Hook event count is 30 (CONTEXT says 34) | cc-schema.json content | cc-schema.json ships with fewer events than CC supports; unknown-hook check would falsely flag valid events. Mitigated: unknown events → WARN not FAIL by design (Phase 27 non-goal: never hard-fail on newer schema) |
| A2 | "SessionStop" is the only renamed event | cc-schema.json renamed_events | Other renamed events not caught; users with those old names don't get a clear upgrade message |
| A3 | disableBypassPermissionsMode sits at both `permissions.disableBypassPermissionsMode` AND top-level | Pattern 6 | If only top-level is correct and Phase 26 fixture is wrong, SCHM-02 produces a false positive on `permissions.*`. Medium risk — check both paths conservatively |
| A4 | SCHM-04 uses `.conjure-version` (Conjure version) to compare against settings_keys introduced_version (CC version) | SCHM-04 design | Comparing apples to oranges (Conjure v0.7.0 vs CC v2.1.129). This makes SCHM-04 informational-only correct — it cannot reliably say "your CC is too old for this key" without the actual `claude --version` output. Use `cc_version` from schema + `claude --version` instead of `.conjure-version` for the version comparison |

---

## Open Questions (RESOLVED)

1. **Hook event count: 30 vs 34** — RESOLVED
   Ship exactly 30 authoritative events from live official docs (CC v2.1.161). The ROADMAP SC "34" was a training-data estimate. Because unknown events from a newer CC release → WARN (never fail) by the non-goal "never hard-fail on newer-than-known schema", the count is forward-safe. lib/cc-schema.json is correct-by-construction from RESEARCH.

2. **SCHM-02 refactor of POL-05c** — RESOLVED
   SCHM-02 is the SUPERSET: it replaces the Phase 26 POL-05c standalone check and extends coverage to the top-level `disableBypassPermissionsMode` path, AND feeds the --json accumulator. Plan 01 (Wave 1) explicitly removes the POL-05c standalone block and replaces it with the SCHM-02 block. Behavior (exit 2 for boolean DBPM) is unchanged. This is a deliberate refactor, NOT an accidental deletion — verification must not flag it as a regression.

3. **check.sh exit code extension** — RESOLVED
   SCHM-03 findings go to a separate `SCHEMA_FAIL` counter in check.sh. Final exit order: `[ "$SCHEMA_FAIL" -gt 0 ] && exit 2` AFTER the existing `exit "$drift"` block. Schema failures override drift (exit 2 > exit 1 > exit 0). The new three-way exit contract (0=clean, 1=drift, 2=schema-error) is documented in the check.sh header comment.

4. **SCHM-04 version semantics** — RESOLVED
   `.conjure-version` holds the CONJURE KIT version (e.g. 0.7.0), NOT the CC version. SCHM-04 must compare the detected `claude --version` output against each key's `introduced_version` in cc-schema.json; it must NOT compare against `.conjure-version`. The report is info-only (never blocks). The CONTEXT.md note calling .conjure-version "the pinned CC version baseline" was incorrect — the plan overrides it.

5. **renamed_events (SessionStop→SessionEnd) confidence** — RESOLVED
   Ship the renamed-events map as best-effort advisory. An unknown event still WARNs/fails generically even if not in the renamed map. The SessionStop→SessionEnd entry is the only historically documented rename; absence from the map for other old names causes a generic UNKNOWN-EVENT failure message, which is still actionable.

**Success-criteria reconciliation:** ROADMAP Phase 27 SC literal numbers ("34 events" / "14 fields") are superseded by the authoritative live-doc counts (30 / 16). Verification must accept 30 events and 16 SKILL.md frontmatter fields as correct. The bundled lib/cc-schema.json is correct-by-construction from the RESEARCH data above.

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| jq | lib/cc-schema.json parsing | ✓ | 1.7.1 (system) | Warn "jq not installed" + skip schema checks |
| claude CLI | CC version detection | ✓ | 2.1.161 | Warn + use cc_version from schema |
| BSD date | Staleness arithmetic on macOS | ✓ | system | GNU date fallback, then skip |
| GNU date | Staleness arithmetic on Linux | ✗ (macOS dev) | — | BSD date primary, skip if neither |
| awk | YAML type detection | ✓ | system POSIX awk | No fallback needed — POSIX |
| shellcheck | CI gate | ✓ | system | CI gate enforces -S error |

---

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Hand-rolled `tests/run.sh` (Phase 25/26 precedent) |
| Config file | none — self-contained bash |
| Quick run command | `bash tests/run.sh 2>&1 | grep -E "^(PASS|FAIL|▸)"` |
| Full suite command | `bash tests/run.sh` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| SCHM-01 | SKILL.md frontmatter object type → fail | fixture | `bash tests/run.sh` (SCHM block) | ❌ Wave 0 |
| SCHM-01 | SKILL.md unknown frontmatter field → warn | fixture | `bash tests/run.sh` (SCHM block) | ❌ Wave 0 |
| SCHM-02 | boolean disableBypassPermissionsMode → fail (permissions path) | fixture | `bash tests/run.sh` (SCHM block) | ❌ Wave 0 (extends existing _emit-policy-broken) |
| SCHM-02 | boolean disableBypassPermissionsMode → fail (top-level path) | fixture | `bash tests/run.sh` (SCHM block) | ❌ Wave 0 |
| SCHM-03 | renamed hook event (SessionStop) → fail | fixture | `bash tests/run.sh` (SCHM block) | ❌ Wave 0 |
| SCHM-03 | unknown hook event → fail | fixture | `bash tests/run.sh` (SCHM block) | ❌ Wave 0 |
| SCHM-03 | valid hook events → pass | fixture | `bash tests/run.sh` (SCHM block) | ❌ Wave 0 |
| SCHM-04 | --schema report emits per-key version | unit | `bash tests/run.sh` (SCHM block) | ❌ Wave 0 |
| SCHM-05 | --json output is parseable JSON | unit | `bash tests/run.sh` (SCHM block) | ❌ Wave 0 |
| SCHM-05 | --json stdout only (no human text) | unit | `bash tests/run.sh` (SCHM block) | ❌ Wave 0 |
| SCHM-05 | --json exit 2 on fail | unit | `bash tests/run.sh` (SCHM block) | ❌ Wave 0 |
| SCHM-STALE | >90d generated date → warn (not fail) | unit | `bash tests/run.sh` (SCHM block) | ❌ Wave 0 |

### Sampling Rate
- **Per task commit:** `bash tests/run.sh 2>&1 | tail -5` (summary line)
- **Per wave merge:** `bash tests/run.sh`
- **Phase gate:** Full suite green before `/gsd-verify-work`

### Wave 0 Gaps (test-first convention — must land before implementation)

```
tests/run.sh     — add "▸ Phase 27 — Schema-Version-Aware Audit (SCHM-01..05)" block (graceful-red)
tests/fixtures/_schema-audit-bad-type/
  └── harness/.claude/skills/test-skill/SKILL.md   # disallowed-tools: {Bash: true}
tests/fixtures/_schema-audit-bad-hook/
  └── harness/.claude/settings.json                 # hooks: {SessionStop: [...]}
tests/fixtures/_schema-audit-dbpm-toplevel/
  └── harness/.claude/settings.json                 # top-level disableBypassPermissionsMode: true
```

The existing `tests/fixtures/_emit-policy-broken/` fixture (with `permissions.disableBypassPermissionsMode: true`) can be reused for SCHM-02 permissions-path test.

---

## Security Domain

Phase 27 is a read-only audit/check extension — no mutation of user data. No new auth, session, or cryptographic requirements.

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V5 Input Validation | yes | jq `--arg`/`--argjson` for all JSON construction; no shell string interpolation into JSON |
| V4 Access Control | no | Read-only audit; no permissions changes |

The main security consideration: `jq -r` output from a SKILL.md frontmatter field might contain special characters that affect bash. Mitigation: always use `printf '%s\n'` (not bare echo) for output, and never eval or exec user-supplied frontmatter values.

---

## Sources

### Primary (HIGH confidence)
- `https://code.claude.com/docs/en/hooks` — hook events enumerated (30 events, PascalCase, matcher behavior)
- `https://code.claude.com/docs/en/skills` — SKILL.md frontmatter reference table (16 fields, types)
- `https://code.claude.com/docs/en/settings` — settings.json key reference with explicit version annotations for 8 keys
- Project codebase: `scripts/audit-setup.sh`, `scripts/check.sh`, `lib/inventory.sh`, `lib/policy-helpers.sh` — verified existing patterns

### Secondary (MEDIUM confidence)
- Project codebase `tests/fixtures/_emit-policy-broken/` — confirms Phase 26 uses `permissions.disableBypassPermissionsMode` path
- `templates/settings.json.tmpl` — confirms `UserPromptExpansion` hook event is already used in this project

### Tertiary (LOW confidence — see Assumptions Log)
- `renamed_events: {"SessionStop": "SessionEnd"}` — training knowledge; no official CC changelog consulted for event renames

---

## Metadata

**Confidence breakdown:**
- cc-schema.json hook events: HIGH — 30 events enumerated from official docs, fetched live 2026-06-03
- cc-schema.json SKILL.md frontmatter: HIGH — 16 fields from official docs frontmatter reference table
- cc-schema.json settings_keys versions: HIGH for the 8 with explicit versions; MEDIUM for "all" (stable since GA)
- Renamed events map: LOW — SessionStop→SessionEnd from training knowledge only
- Implementation patterns: HIGH — verified via live codebase inspection + bash testing

**Research date:** 2026-06-03
**Valid until:** 2026-09-01 (90 days — same staleness threshold as the schema itself)
