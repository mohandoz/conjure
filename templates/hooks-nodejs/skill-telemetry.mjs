#!/usr/bin/env node
// Cross-platform PreToolUse(Skill) + UserPromptSubmit hook — skill-firing telemetry.
// Appends one JSONL line per skill invocation to .claude/telemetry/skill-events.jsonl.
// Opt-in via CONJURE_TELEMETRY=1 in .claude/settings.json env block.
// Exit 0 always — telemetry NEVER blocks Claude.

import { mkdirSync, appendFileSync } from 'node:fs';
import path from 'node:path';

// DO_NOT_TRACK check FIRST, per Unix convention (D-02)
if (process.env.DO_NOT_TRACK === '1') process.exit(0);
// Opt-in gate — silent no-op unless CONJURE_TELEMETRY=1 (D-01)
if (process.env.CONJURE_TELEMETRY !== '1') process.exit(0);

// 5-second stdin guard — prevents stuck hook from blocking Claude session (T-07-05)
const guard = setTimeout(() => process.exit(0), 5000);

let raw = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', chunk => { raw += chunk; });
process.stdin.on('end', () => {
  clearTimeout(guard);

  let p;
  try { p = JSON.parse(raw); } catch { process.exit(0); }

  const event = p.hook_event_name;
  let skillName = null;
  let eventType = null;

  if (event === 'PreToolUse' && p.tool_name === 'Skill') {
    // PreToolUse/Skill: skill name is in tool_input.skill_name (A1: defensive ?.)
    skillName = p.tool_input?.skill_name ?? null;
    eventType = 'skill_invoke';
  } else if (event === 'UserPromptSubmit') {
    // UserPromptSubmit: skill name is the first token of prompt if it starts with /
    const prompt = p.prompt ?? '';
    if (typeof prompt === 'string' && prompt.startsWith('/')) {
      const token = prompt.split(/\s+/)[0];
      skillName = token.replace(/^\//, '') || null;
    }
    eventType = 'skill_typed';
  } else {
    // Not a skill event — silent pass
    process.exit(0);
  }

  // Defensive null guard — exit silently if skill name could not be determined
  if (!skillName) process.exit(0);

  // Derive safe working directory — p.cwd may be absent for UserPromptSubmit events
  const cwd = p.cwd ?? process.cwd();

  // Build JSONL record — skill name ONLY, never tool arguments (PII risk, D-05)
  const record = JSON.stringify({
    ts: new Date().toISOString(),
    session_id: p.session_id,
    event: eventType,
    skill: skillName,
    project_cwd: cwd
  });

  // Write to local log file — fs errors caught silently (telemetry must never block)
  try {
    const logDir = path.join(cwd, '.claude', 'telemetry');
    mkdirSync(logDir, { recursive: true });
    appendFileSync(path.join(logDir, 'skill-events.jsonl'), record + '\n');
  } catch { /* silent fail */ }

  process.exit(0);
});
