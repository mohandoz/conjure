---
phase: quick
plan: 260605-txz
type: execute
wave: 1
depends_on: []
files_modified:
  - templates/settings.json.tmpl
  - templates/hooks-nodejs/skill-telemetry.mjs
  - tests/run.sh
  - TELEMETRY.md
autonomous: true
requirements: [BUG-HOOK-PATH, BUG-EVENT-NAME]

must_haves:
  truths:
    - "All hook commands in settings.json.tmpl use absolute paths via $CLAUDE_PROJECT_DIR, never relative"
    - "No UserPromptExpansion hook event appears in settings.json.tmpl"
    - "skill-telemetry.mjs matches on UserPromptSubmit and reads skill name from prompt field"
    - "TLMY-02b test passes with UserPromptSubmit payload shape"
    - "jq empty passes on templates/settings.json.tmpl"
    - "node --check passes on templates/hooks-nodejs/skill-telemetry.mjs"
    - "Zero occurrences of UserPromptExpansion outside .planning/ and _-prefixed fixtures"
  artifacts:
    - path: "templates/settings.json.tmpl"
      provides: "Corrected hook commands with CLAUDE_PROJECT_DIR and UserPromptSubmit event"
    - path: "templates/hooks-nodejs/skill-telemetry.mjs"
      provides: "UserPromptSubmit event handling, prompt-field skill detection"
    - path: "tests/run.sh"
      provides: "Updated TLMY-02b block with UserPromptSubmit payload; updated template lint assertion"
    - path: "TELEMETRY.md"
      provides: "Updated event name in doc table"
  key_links:
    - from: "templates/settings.json.tmpl"
      to: "templates/hooks-nodejs/skill-telemetry.mjs"
      via: "hook event name must match what the .mjs handles"
      pattern: "UserPromptSubmit"
---

<objective>
Fix two bugs in the scaffolded hook template that cause every generated harness to ship broken hooks.

Bug 1 — Relative hook paths: all 7 `node .claude/hooks/<x>.mjs` commands in
templates/settings.json.tmpl resolve against the shell's cwd, which drifts when Claude
navigates directories. Fix: prefix every hook node command with
`node "$CLAUDE_PROJECT_DIR"/.claude/hooks/` and change the graphify SessionStart
one-liner's `.` target to `"$CLAUDE_PROJECT_DIR"`.

Bug 2 — Invalid event name: `UserPromptExpansion` is the wrong event name for detecting
typed slash commands. The correct event is `UserPromptSubmit`, whose payload carries a
`prompt` field (not `command_name`). Fix in template, hook implementation, tests, and docs.

Purpose: Every repo scaffolded with `conjure init` currently ships dead-on-arrival hooks.
Output: Corrected template + hook + tests + doc; tests/run.sh TLMY-02b passes.
</objective>

<execution_context>
@$HOME/.claude/get-shit-done/workflows/execute-plan.md
@$HOME/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/STATE.md
</context>

<tasks>

<task type="auto">
  <name>Task 1: Fix relative hook paths in settings.json.tmpl</name>
  <files>templates/settings.json.tmpl</files>
  <action>
In templates/settings.json.tmpl, fix every hook `command` value that uses a relative path.

Seven `node` hook commands currently look like:
  `node .claude/hooks/<x>.mjs`

Change ALL of them to:
  `node "$CLAUDE_PROJECT_DIR"/.claude/hooks/<x>.mjs`

The double-quoted `$CLAUDE_PROJECT_DIR` must appear inside the JSON string value —
JSON does not require escaping `$` or `"` inside double-quoted strings when the
quotes are part of a shell command value, but the JSON itself must remain valid.
Verify with `jq empty templates/settings.json.tmpl` — it must exit 0.

The affected hook commands are (by hook file name):
  - post-edit-format.mjs (PostToolUse)
  - pre-bash-block-destructive.mjs (PreToolUse/Bash, first)
  - pre-commit-quality-gate.mjs (PreToolUse/Bash, second)
  - skill-telemetry.mjs (PreToolUse/Skill)
  - stop-compound-engineering.mjs (Stop)
  - session-start-context.mjs (SessionStart, first)
  - skill-telemetry.mjs (UserPromptExpansion, second — but this key is being renamed in Task 2)

Also fix the graphify SessionStart one-liner at line ~99. It currently ends with `. 2>/dev/null || true`. Change the `.` positional argument to `"$CLAUDE_PROJECT_DIR"`:
  Before: `command -v graphify >/dev/null 2>&1 && graphify check-update . 2>/dev/null || true`
  After:  `command -v graphify >/dev/null 2>&1 && graphify check-update "$CLAUDE_PROJECT_DIR" 2>/dev/null || true`

After edits: `jq empty templates/settings.json.tmpl` must pass (exit 0).

NOTE: Do NOT rename UserPromptExpansion to UserPromptSubmit in this task — Task 2 handles the event rename. Apply the path fix to the existing UserPromptExpansion block so it is consistent before Task 2 renames it.
  </action>
  <verify>
    <automated>jq empty /Users/mohandoz/u01/innovate/conjure/templates/settings.json.tmpl && echo "JSON valid"</automated>
  </verify>
  <done>
    - Every `node` hook command in settings.json.tmpl uses `node "$CLAUDE_PROJECT_DIR"/.claude/hooks/...`
    - The graphify check-update line uses `"$CLAUDE_PROJECT_DIR"` instead of `.`
    - `jq empty templates/settings.json.tmpl` exits 0
    - No occurrence of `node .claude/hooks/` remains in the file
  </done>
</task>

<task type="auto">
  <name>Task 2: Rename UserPromptExpansion to UserPromptSubmit across template, hook, tests, and docs</name>
  <files>
    templates/settings.json.tmpl,
    templates/hooks-nodejs/skill-telemetry.mjs,
    tests/run.sh,
    TELEMETRY.md
  </files>
  <action>
Four coordinated changes. Apply in this order:

**A. templates/settings.json.tmpl**

Rename the top-level hook event key from `"UserPromptExpansion"` to `"UserPromptSubmit"`.
The block currently at line ~103 becomes:
  `"UserPromptSubmit": [`
Everything else in that block (the single skill-telemetry.mjs command entry) remains except
the command path was already fixed to `node "$CLAUDE_PROJECT_DIR"/.claude/hooks/skill-telemetry.mjs`
in Task 1. Verify `jq empty` still passes.

**B. templates/hooks-nodejs/skill-telemetry.mjs**

The file comment on line 2 mentions `UserPromptExpansion` — update it to `UserPromptSubmit`.

In the stdin `end` handler, the `else if` branch currently matches:
  `} else if (event === 'UserPromptExpansion') {`

Change the event match to `UserPromptSubmit`:
  `} else if (event === 'UserPromptSubmit') {`

The `UserPromptSubmit` payload carries a `prompt` field (a string containing the raw user
message, e.g. `/test-skill some args`). It does NOT have `command_name`. Update skill
extraction: parse the leading slash-command token from `p.prompt`:

Replace:
  ```
  skillName = p.command_name ?? null;
  if (skillName) skillName = skillName.replace(/^\//, '');
  ```

With logic that:
1. Reads `p.prompt` (string or undefined)
2. If `p.prompt` starts with `/`, extracts the first whitespace-delimited token as the
   slash-command name, then strips the leading `/`
3. If `p.prompt` does not start with `/`, sets skillName = null (not a skill invocation —
   the hook silently exits via the existing null guard below)

Example: `p.prompt = "/test-skill foo bar"` → skillName = `"test-skill"`, eventType = `"skill_typed"`.
Example: `p.prompt = "Hello Claude"` → skillName = null → hook exits 0 silently.

Keep the `eventType = 'skill_typed'` assignment unchanged.
Keep the `cwd = p.cwd ?? process.cwd()` fallback — `UserPromptSubmit` does carry `cwd`.
Keep all other behavior (DO_NOT_TRACK, opt-in gate, stdin guard, silent fail on write error).

After edit: `node --check templates/hooks-nodejs/skill-telemetry.mjs` must exit 0.

**C. tests/run.sh — TLMY-02b block (lines ~655–678)**

The TLMY-02b block tests the `UserPromptExpansion` path. Update it for `UserPromptSubmit`:

1. Block comment line 655: change `UserPromptExpansion path` to `UserPromptSubmit path`

2. Payload variable `UPE_PAYLOAD` (line 656): change from:
     `{"hook_event_name":"UserPromptExpansion","command_name":"/test-skill",...}`
   To:
     `{"hook_event_name":"UserPromptSubmit","prompt":"/test-skill foo","session_id":"sess-002","cwd":"'"$TLMY_CWD"'"}`
   (Use `"prompt"` key with a value that starts with a slash-command so the hook extracts
   the skill name. Retain `session_id` and `cwd`.)

3. All `pass`/`fail` message strings that say `"UserPromptExpansion"`: change to `"UserPromptSubmit"`.
   There are three such strings at lines ~660, ~666, ~675.

4. The grep check at lines ~672–674 that verifies the JSONL record:
   It currently greps for `'"skill_typed"'`, `'"test-skill"'`, and `'"project_cwd"'`.
   These remain correct — no change needed there.

Also update the template lint assertion at line 209:
  Before: `if grep -q 'node .claude/hooks/' templates/settings.json.tmpl 2>/dev/null; then`
  After:  `if grep -q 'node "$CLAUDE_PROJECT_DIR"/.claude/hooks/' templates/settings.json.tmpl 2>/dev/null; then`
(The old literal `node .claude/hooks/` will no longer appear after Task 1.)

**D. TELEMETRY.md**

In the Event Schema table (~line 47), the `event` field description currently reads:
  `skill_invoke` = PreToolUse/Skill tool call; `skill_typed` = UserPromptExpansion slash command

Update to:
  `skill_invoke` = PreToolUse/Skill tool call; `skill_typed` = UserPromptSubmit slash command

No other changes to TELEMETRY.md.
  </action>
  <verify>
    <automated>
      cd /Users/mohandoz/u01/innovate/conjure && \
      jq empty templates/settings.json.tmpl && \
      node --check templates/hooks-nodejs/skill-telemetry.mjs && \
      grep -c "UserPromptExpansion" templates/settings.json.tmpl templates/hooks-nodejs/skill-telemetry.mjs TELEMETRY.md && echo "FAIL: UserPromptExpansion still present" || echo "PASS: UserPromptExpansion absent from template+hook+docs" && \
      grep -q "UserPromptSubmit" templates/settings.json.tmpl && echo "PASS: UserPromptSubmit in template" && \
      grep -q "UserPromptSubmit" templates/hooks-nodejs/skill-telemetry.mjs && echo "PASS: UserPromptSubmit in hook" && \
      grep -q "UserPromptSubmit" TELEMETRY.md && echo "PASS: UserPromptSubmit in docs"
    </automated>
  </verify>
  <done>
    - `"UserPromptSubmit"` is the event key in settings.json.tmpl (not UserPromptExpansion)
    - skill-telemetry.mjs matches `UserPromptSubmit` and parses skill name from `p.prompt` leading token
    - TLMY-02b test block sends UserPromptSubmit payload with `prompt` field
    - TELEMETRY.md doc table says UserPromptSubmit
    - Template lint assertion in run.sh checks for the new CLAUDE_PROJECT_DIR path pattern
    - `jq empty templates/settings.json.tmpl` exits 0
    - `node --check templates/hooks-nodejs/skill-telemetry.mjs` exits 0
    - Zero occurrences of `UserPromptExpansion` in templates/settings.json.tmpl, templates/hooks-nodejs/skill-telemetry.mjs, TELEMETRY.md, or tests/run.sh
  </done>
</task>

</tasks>

<threat_model>
## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| stdin → hook process | UserPromptSubmit payload piped to skill-telemetry.mjs; untrusted prompt string |

## STRIDE Threat Register

| Threat ID | Category | Component | Disposition | Mitigation Plan |
|-----------|----------|-----------|-------------|-----------------|
| T-txz-01 | Information Disclosure | skill-telemetry.mjs prompt parsing | mitigate | Extract only the first token (skill name) from prompt; never log full prompt or arguments (existing D-05 PII risk mitigation) |
| T-txz-02 | Tampering | CLAUDE_PROJECT_DIR env var | accept | CLAUDE_PROJECT_DIR is set by the Claude Code runtime; a compromised env is outside hook scope |
| T-txz-SC | Tampering | npm/pip/cargo installs | accept | No new package installs in this fix; stdlib-only .mjs unchanged |
</threat_model>

<verification>
Run from repo root after both tasks complete:

```bash
# JSON validity
jq empty templates/settings.json.tmpl

# Hook syntax
node --check templates/hooks-nodejs/skill-telemetry.mjs

# Zero UserPromptExpansion outside .planning/ and _-prefixed fixtures
grep -r "UserPromptExpansion" . \
  --include="*.mjs" --include="*.sh" --include="*.md" --include="*.tmpl" \
  --exclude-dir=".planning" --exclude-dir=".git" --exclude-dir="worktrees" \
  | grep -v "tests/fixtures/_" \
  | grep -v "cc-schema.json"

# TLMY-02b: run the telemetry test block
bash tests/run.sh 2>&1 | grep -E "TLMY-02b|PASS|FAIL" | grep "TLMY-02b"

# No relative hook paths remain
grep -c '"node \.claude/hooks/' templates/settings.json.tmpl || echo "PASS: no relative paths"
```
</verification>

<success_criteria>
- All 7 hook node commands in templates/settings.json.tmpl use `node "$CLAUDE_PROJECT_DIR"/.claude/hooks/...`
- graphify check-update command uses `"$CLAUDE_PROJECT_DIR"` not `.`
- `UserPromptSubmit` replaces `UserPromptExpansion` in template, hook, tests, and docs
- skill-telemetry.mjs parses skill name from `p.prompt` leading slash-token
- `jq empty templates/settings.json.tmpl` exits 0
- `node --check templates/hooks-nodejs/skill-telemetry.mjs` exits 0
- TLMY-02b passes (3 pass lines, 0 fail lines for that block)
- `grep -r UserPromptExpansion` returns no hits in template/hook/test/doc files
</success_criteria>

<output>
Create `.planning/quick/260605-txz-fix-hook-template-bugs-relative-paths-an/260605-txz-SUMMARY.md` when done.
</output>
