<!-- Covers: TECH-02f | TLMY-01, TLMY-02, TLMY-02b, TLMY-03, TLMY-04, TLMY-05 -->
# Phase 07 VALIDATION

## Verify skill-telemetry.mjs hook file exists (TLMY-01)

```bash
[ -f templates/hooks-nodejs/skill-telemetry.mjs ] && echo "PASS: exists" || echo "FAIL: missing"
```

**Expected:** `PASS: exists`

## Verify hook contains no network egress patterns (TLMY-03)

```bash
grep -cE 'curl|fetch|http|socket|XMLHttpRequest|require\(.https.\)|require\(.http.\)|import.*https|import.*http|net\.Socket' templates/hooks-nodejs/skill-telemetry.mjs || true
```

**Expected:** `0` (zero egress patterns)

## Verify hook exits 0 silently when CONJURE_TELEMETRY is unset (TLMY-01)

```bash
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT
printf '{}' | CONJURE_TELEMETRY="" node templates/hooks-nodejs/skill-telemetry.mjs >/dev/null 2>&1; echo "exit: $?"
[ -f "$TMPDIR/.claude/telemetry/skill-events.jsonl" ] && echo "FAIL: file written" || echo "PASS: no file"
```

**Expected:** `exit: 0` and `PASS: no file`

## Verify DO_NOT_TRACK=1 suppresses JSONL writes (TLMY-01)

```bash
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT
PAYLOAD='{"hook_event_name":"PreToolUse","tool_name":"Skill","tool_input":{"skill_name":"test-skill"},"session_id":"sess-001","cwd":"'"$TMPDIR"'"}'
printf '%s' "$PAYLOAD" | DO_NOT_TRACK=1 CONJURE_TELEMETRY=1 node templates/hooks-nodejs/skill-telemetry.mjs >/dev/null 2>&1; echo "exit: $?"
[ -f "$TMPDIR/.claude/telemetry/skill-events.jsonl" ] && echo "FAIL: file written" || echo "PASS: suppressed"
```

**Expected:** `exit: 0` and `PASS: suppressed`

## Verify hook writes JSONL with required fields when CONJURE_TELEMETRY=1 (TLMY-02)

```bash
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT
SKILL_PAYLOAD='{"hook_event_name":"PreToolUse","tool_name":"Skill","tool_input":{"skill_name":"test-skill"},"session_id":"sess-001","cwd":"'"$TMPDIR"'"}'
printf '%s' "$SKILL_PAYLOAD" | CONJURE_TELEMETRY=1 node templates/hooks-nodejs/skill-telemetry.mjs >/dev/null 2>&1
cat "$TMPDIR/.claude/telemetry/skill-events.jsonl"
```

**Expected:** JSON line containing `skill_invoke`, `test-skill`, `session_id`, `project_cwd`

## Verify UserPromptExpansion path writes skill_typed event (TLMY-02b)

```bash
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT
SKILL_PAYLOAD='{"hook_event_name":"PreToolUse","tool_name":"Skill","tool_input":{"skill_name":"test-skill"},"session_id":"sess-001","cwd":"'"$TMPDIR"'"}'
printf '%s' "$SKILL_PAYLOAD" | CONJURE_TELEMETRY=1 node templates/hooks-nodejs/skill-telemetry.mjs >/dev/null 2>&1
UPE_PAYLOAD='{"hook_event_name":"UserPromptExpansion","command_name":"/test-skill","session_id":"sess-002","cwd":"'"$TMPDIR"'"}'
printf '%s' "$UPE_PAYLOAD" | CONJURE_TELEMETRY=1 node templates/hooks-nodejs/skill-telemetry.mjs >/dev/null 2>&1
tail -1 "$TMPDIR/.claude/telemetry/skill-events.jsonl"
```

**Expected:** JSON line containing `skill_typed`, `test-skill`, `project_cwd`

## Verify retire-list section renders when CONJURE_RETIRE=1 (TLMY-04)

```bash
CONJURE_HOME=$(pwd)
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT
cp -r tests/fixtures/python-fastapi/. "$TMPDIR/"
CONJURE_HOME=$(pwd) CONJURE_RETIRE=1 bash scripts/audit-setup.sh "$TMPDIR" 2>&1 | grep '── Skill Retire-List ──'
```

**Expected:** line containing `── Skill Retire-List ──`

## Verify TELEMETRY.md exists with required schema fields (TLMY-05)

```bash
[ -f TELEMETRY.md ] && echo "PASS: exists" || echo "FAIL: missing"
grep -c 'session_id\|project_cwd\|DO_NOT_TRACK' TELEMETRY.md
```

**Expected:** `PASS: exists` and count >= 3
