---
phase: 07-skill-firing-telemetry
reviewed: 2026-05-25T00:00:00Z
depth: standard
files_reviewed: 6
files_reviewed_list:
  - cli/conjure
  - scripts/audit-setup.sh
  - templates/.gitignore.tmpl
  - templates/hooks-nodejs/skill-telemetry.mjs
  - templates/settings.json.tmpl
  - tests/run.sh
findings:
  critical: 1
  warning: 6
  info: 3
  total: 10
status: issues_found
---

# Phase 07: Code Review Report

**Reviewed:** 2026-05-25T00:00:00Z
**Depth:** standard
**Files Reviewed:** 6
**Status:** issues_found

## Summary

Reviewed the six files introduced or modified in phase 07 (skill-firing telemetry). The
hook implementation (`skill-telemetry.mjs`) is solid in its opt-in/DNT logic and its
safety-first `process.exit(0)` contract. The broader issues are in the surrounding
infrastructure: a silent data-loss path in the hook when `p.cwd` is absent, a dead-code
branch in the retire-list feature (its core purpose is unreachable by construction), temp-
file leaks across fixture-loop iterations in `tests/run.sh`, and an `awk` injection
surface when the price model lookup returns empty in `audit-setup.sh`.

---

## Critical Issues

### CR-01: `awk` expression injection when price-model lookup returns empty string

**File:** `scripts/audit-setup.sh:165`
**Issue:** `PRICE_INPUT` is populated by a `jq` select that returns nothing (empty
string) when the default model name is not found in `prices.json` — e.g. if
`prices.json` is deleted, edited, or the `default_model` key points to a model not in
the `models` array. Because the script runs under `set -uo pipefail` (no `-e`), the
empty assignment is not fatal. The value is then spliced directly into an `awk`
arithmetic expression:

```bash
TOTAL_COST=$(awk "BEGIN {printf \"%.2f\", $TOKENS_TO_USE * $PRICE_INPUT / 1000000}")
```

With `PRICE_INPUT=""` this becomes:

```awk
BEGIN {printf "%.2f", 1234 *  / 1000000}
```

`awk` exits nonzero with a parse error printed to stderr, `TOTAL_COST` is set to empty,
and the subsequent `printf` at line 193 emits a broken line. The same unexpanded
variable also appears at lines 174 and 182, affecting per-file cost rows. While the
`PRICE_FILE` itself exists in the shipped kit, any operator who renames or removes it,
or adds a new model without updating `default_model`, triggers silent, corrupt output
with no user-visible diagnostic.

**Fix:** Guard `PRICE_FILE` existence and validate that the model lookup succeeded
before proceeding:

```bash
if [ ! -f "$PRICE_FILE" ]; then
  echo "  [--cost] prices.json missing at $PRICE_FILE"
elif ! command -v jq >/dev/null 2>&1; then
  echo "  [--cost] jq not installed — install jq to use cost estimation"
else
  MODEL=$(jq -r '.default_model // empty' "$PRICE_FILE")
  PRICE_INPUT=$(jq -r --arg m "$MODEL" \
    '.models[] | select(.model==$m) | .input_per_mtok' "$PRICE_FILE")
  if [ -z "$PRICE_INPUT" ]; then
    echo "  [--cost] model '$MODEL' not found in prices.json — skipping cost estimate"
  else
    # existing awk expressions are now safe
    ...
  fi
fi
```

---

## Warnings

### WR-01: `p.cwd` used without null guard — silent data loss for `UserPromptExpansion` events

**File:** `templates/hooks-nodejs/skill-telemetry.mjs:54,59`
**Issue:** Both usages of `p.cwd` are unguarded. When the hook fires for a
`UserPromptExpansion` event, the Claude Code runtime may not include a `cwd` field in
the payload (the field is documented for tool-use events; its presence in prompt-
expansion events is not guaranteed). `path.join(undefined, ...)` throws a
`TypeError: The "path" argument must be of type string` in Node.js ≥18. The outer
`try/catch` at line 58 silently swallows this, so the JSONL record is never written —
telemetry for every `UserPromptExpansion` event is silently dropped without any
diagnostic. Additionally, when `p.cwd` is `undefined`, `JSON.stringify` omits the
`project_cwd` field from the record, violating the documented TELEMETRY.md schema even
if the write somehow succeeded.

```js
// Lines 54 and 59 — both lack a null guard
project_cwd: p.cwd          // undefined → field omitted from JSON
const logDir = path.join(p.cwd, '.claude', 'telemetry');  // throws TypeError
```

**Fix:** Derive a safe working directory with a fallback, and apply it consistently:

```js
const cwd = p.cwd ?? process.cwd();

const record = JSON.stringify({
  ts: new Date().toISOString(),
  session_id: p.session_id,
  event: eventType,
  skill: skillName,
  project_cwd: cwd
});

const logDir = path.join(cwd, '.claude', 'telemetry');
```

---

### WR-02: `[retire?]` status branch is dead code — retire-list feature cannot fulfil its purpose

**File:** `scripts/audit-setup.sh:229-236`
**Issue:** The retire-list is built by running `jq | sort | uniq -c | sort -rn` against
the telemetry JSONL. `uniq -c` only emits lines where the item appeared at least once,
so every `count` in `RETIRE_TMP` is guaranteed to be ≥ 1. The `else` branch at line 234
(`status="[retire?]"`) can therefore never be reached. More critically, the feature's
stated purpose — identifying skills that have gone unused and could be retired — is
structurally impossible with the current implementation: skills that fired zero times in
30 days do not appear in the JSONL log at all and are entirely invisible in the output.

```bash
# count from uniq -c is always >= 1; this branch never fires
if [ "${count:-0}" -gt 0 ]; then
  status="[active]"
else
  status="[retire?]"   # dead code
fi
```

**Fix:** Cross-reference the telemetry counts against the actual installed skills from
`.claude/skills/`:

```bash
# List all installed skills
while IFS= read -r skill_path; do
  name=$(basename "$(dirname "$skill_path")")
  count=$(grep -c "\"skill\":\"$name\"" "$LOG" 2>/dev/null || echo 0)
  if [ "$count" -gt 0 ]; then status="[active]"; else status="[retire?]"; fi
  printf "  %-35s %6s %8s\n" "$name" "$count" "$status"
done < <(find "$TARGET/.claude/skills" -name SKILL.md 2>/dev/null)
```

---

### WR-03: Sandbox temp directories leaked across fixture-loop iterations in `tests/run.sh`

**File:** `tests/run.sh:254-266,292-308`
**Issue:** `sandbox_setup` registers `trap 'rm -rf "$SANDBOX_DIR"' EXIT` each time it
is called. Because bash `trap` is not additive — each new registration overwrites the
previous — and `SANDBOX_DIR` is a global that is mutated on each loop iteration, only
the final iteration's sandbox directory is cleaned up on exit. Every preceding
iteration's temp directory is leaked for the lifetime of the OS session. With ~9
fixtures in two loops this produces ~16 leaked temp directories per test run.

The `run.sh` comment at line 219 explicitly identifies this pattern as a bug for the
dry-run block and manually cleans up before calling `sandbox_setup`. The same fix is not
applied to the fixture loops.

**Fix:** Explicitly clean up at the end of each loop iteration rather than relying on
the EXIT trap:

```bash
for fx in "$CONJURE_HOME/tests/fixtures"/[^_]*/; do
  prof=$(basename "$fx")
  sandbox_setup "$fx"
  AUDIT_OUT="$(bash "$CONJURE_HOME/scripts/audit-setup.sh" "$SANDBOX_DIR" 2>&1)"
  AUDIT_RC=$?
  # ... assertions ...
  rm -rf "$SANDBOX_DIR"   # explicit per-iteration cleanup
  trap - EXIT             # clear trap so next sandbox_setup can register cleanly
done
```

---

### WR-04: `source lib/mutate.sh` failure is silently ignored — `cmd_init` continues with undefined functions

**File:** `cli/conjure:65`
**Issue:** `cmd_init` sources `lib/mutate.sh` to load `mutate_write`, `mutate_mkdir`,
and `mutate_summary`. The script runs under `set -uo pipefail` but not `set -e`. A
failed `source` (missing or unreadable file) does not abort execution — verified:
`bash -c 'set -uo pipefail; source /nonexistent; echo "still running"'` prints "still
running". The function then proceeds to call `mutate_write` (line 86) and
`mutate_summary` (line 87). Without `-e`, undefined function calls print a "command not
found" error to stderr but the script continues and exits 0 — giving the user a false
success signal after the `conjure init` run failed silently.

**Fix:** Guard the source call explicitly:

```bash
source "$CONJURE_HOME/lib/mutate.sh" \
  || { echo "✗ Failed to load lib/mutate.sh — check CONJURE_HOME ($CONJURE_HOME)"; return 1; }
```

---

### WR-05: `UserPromptExpansion` hook path not covered by any test

**File:** `tests/run.sh:486-556`
**Issue:** The TLMY-02 test only exercises the `PreToolUse/Skill` code path with
`SKILL_PAYLOAD`. The `UserPromptExpansion` branch (lines 35-39 of
`skill-telemetry.mjs`) — which handles the `command_name` field and sets
`eventType='skill_typed'` — is never tested. This branch is live in
`templates/settings.json.tmpl` (the `UserPromptExpansion` hook entry at line 98-107).
As a result, the silent data-loss bug described in WR-01 (missing `cwd`) was not
caught by tests, and the `skill_typed` event type is entirely unvalidated.

**Fix:** Add a TLMY-02b test exercising the `UserPromptExpansion` payload:

```bash
UPE_PAYLOAD='{"hook_event_name":"UserPromptExpansion","command_name":"/test-skill","session_id":"sess-002","cwd":"'"$SANDBOX_DIR"'"}'
printf '%s' "$UPE_PAYLOAD" | CONJURE_TELEMETRY=1 node "$TLMY_HOOK" >/dev/null 2>&1
JSONL_COUNT=$(wc -l < "$SANDBOX_DIR/.claude/telemetry/skill-events.jsonl" | tr -d ' ')
if [ "$JSONL_COUNT" -ge 2 ]; then pass "UserPromptExpansion path writes JSONL (TLMY-02b)"
else fail "UserPromptExpansion path did NOT write JSONL (TLMY-02b)"
fi
```

---

### WR-06: Description-length check in `audit-setup.sh` silently misses unquoted descriptions

**File:** `scripts/audit-setup.sh:62`
**Issue:** The regex `'^description: ".\{0,30\}"$'` only matches descriptions wrapped
in double quotes. Frontmatter values without quotes (e.g. `description: Short text`) do
not match, so a short unquoted description silently passes the length gate without a
warning. The tests in `tests/run.sh` line 56-57 have an independent off-by-one: `echo
"$desc_line" | wc -c` counts the trailing newline that `echo` appends, so a 29-character
description yields `desc_len=30` and passes the `< 30` threshold check.

**Fix for audit-setup.sh:**
```bash
# Match both quoted and unquoted descriptions
elif head -10 "$skill" | grep -qE '^description: "?.{0,29}"?$'; then
  warn "Skill '$name': description very short (<30 chars) — likely won't fire correctly"
```

**Fix for run.sh line 56:**
```bash
# Use printf to avoid trailing newline from echo
desc_len=$(printf '%s' "$desc_line" | sed 's/^description: //;s/^"//;s/"$//' | wc -c | tr -d ' ')
```

---

## Info

### IN-01: Misleading comment in `settings.json.tmpl` — hook entries are already active, not commented out

**File:** `templates/settings.json.tmpl:41`
**Issue:** The `_comment_telemetry` field reads: *"Uncomment to enable opt-in skill-
firing telemetry"*. But the `PreToolUse/Skill` and `UserPromptExpansion` hook entries
are already present and active in the template — nothing is commented out. The actual
activation mechanism is `CONJURE_TELEMETRY=1` in the `env` block, which is itself only
described in a nested `_comment` key with no ready-to-use example value.

**Fix:** Update the comment to accurately describe the activation mechanism:
```json
"_comment_telemetry": "Hook entries are always active but write nothing unless CONJURE_TELEMETRY=1 is set in the env block below. See TELEMETRY.md for the full schema."
```
And add an example in the env block:
```json
"env": {
  "_comment": "Uncomment the line below to enable skill-firing telemetry (see TELEMETRY.md)",
  "CONJURE_TELEMETRY": "0"
}
```

---

### IN-02: Path traversal in `--profile` and migrate `source` arguments (local CLI, low risk)

**File:** `cli/conjure:80-83,95`
**Issue:** The `$profile` and `$source` values are used directly in file paths
(`$CONJURE_HOME/profiles/$profile/apply.sh`, `$CONJURE_HOME/migrations/$source/migrate.sh`)
without sanitization. A value like `../../etc` would traverse outside the `profiles/`
directory. The `-d` check (for profiles) and `-f` check (for migrations) mean that an
actual exploit requires a malicious file already present at the resolved path. Since
`conjure` is a local developer CLI (not a server), the practical risk is low, but the
pattern is worth noting.

**Fix:** Validate that the argument contains no path-separator components:
```bash
# Profile check in cmd_init
if [[ "$profile" == */* || "$profile" == *..* ]]; then
  echo "✗ Invalid profile name: $profile"; return 1
fi
# Same pattern for source in cmd_migrate
```

---

### IN-03: `tests/run.sh` TEST-05 dry-run snapshot loop does not register an EXIT trap — temp dirs unguarded on failure

**File:** `tests/run.sh:311-326`
**Issue:** The `dry-run byte-identical snapshot` loop (lines 311-326) creates two temp
directories per iteration with `mktemp -d` (`DRY_ORIG`, `DRY_SNAP`) and cleans them
with `rm -rf` at line 325. However there is no `trap ... EXIT` for these directories,
so if the loop body exits early (e.g. from `set -u` triggering on an unbound variable),
the temp dirs are leaked. The other loops in the file consistently use `trap` for
cleanup.

**Fix:** Add a trap scoped to each iteration or use a per-loop guard:
```bash
for fx in ...; do
  DRY_ORIG="$(mktemp -d)"
  DRY_SNAP="$(mktemp -d)"
  trap 'rm -rf "$DRY_ORIG" "$DRY_SNAP"' EXIT
  # ... test body ...
  rm -rf "$DRY_ORIG" "$DRY_SNAP"
  trap - EXIT
done
```

---

_Reviewed: 2026-05-25T00:00:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
