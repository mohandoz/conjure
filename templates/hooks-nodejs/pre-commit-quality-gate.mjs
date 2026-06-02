#!/usr/bin/env node
// Cross-platform PreToolUse hook for `git commit` — block bad commits.
// Reads the command from stdin JSON (Claude Code canonical delivery method).
// Falls back to process.argv[2] / CLAUDE_COMMAND for manual CLI invocation.
// Exit 2 = BLOCK. Exit 0 = ALLOW.

import { execSync } from 'node:child_process';
import { existsSync } from 'node:fs';

// 5-second stdin guard — prevents stuck hook from blocking Claude session (T-302-02)
const guard = setTimeout(() => process.exit(0), 5000);

let raw = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', chunk => { raw += chunk; });
process.stdin.on('end', () => {
  clearTimeout(guard);

  let p = {};
  try { p = JSON.parse(raw); } catch { /* invalid JSON — fall through to argv/env */ }

  // Prefer stdin JSON; fall back to argv[2] / env for manual CLI invocation
  const cmd = (p.tool_input?.command) || process.argv[2] || process.env.CLAUDE_COMMAND || '';

  // Only intercept git commit commands
  if (!/^git\s+commit/.test(cmd)) process.exit(0);

  let repoRoot;
  try {
    repoRoot = execSync('git rev-parse --show-toplevel', { stdio: ['ignore', 'pipe', 'ignore'] }).toString().trim();
  } catch {
    process.exit(0);
  }
  process.chdir(repoRoot);

  const deny = (msg) => {
    process.stderr.write(JSON.stringify({
      hookSpecificOutput: { permissionDecision: 'deny', permissionDecisionReason: msg }
    }) + '\n');
    process.exit(2);
  };

  // 1. Secret scan via gitleaks (if installed)
  // FIX-02: only block on exit status === 1 (confirmed finding).
  // Other non-zero codes are tool/config errors — surface diagnostics but do not block.
  try {
    execSync('gitleaks protect --staged --no-banner --redact', { stdio: 'ignore' });
  } catch (e) {
    if (e.status === 1) {
      // Confirmed finding — block the commit
      deny('gitleaks detected secrets in staged files. Remove + rotate before committing.');
    } else if (e.signal) {
      // gitleaks was killed by a signal — surface as tool error but do not block
      process.stderr.write(JSON.stringify({
        hookSpecificOutput: {
          permissionDecision: 'deny',
          permissionDecisionReason: `gitleaks terminated by signal ${e.signal} — not blocking, but investigate`
        }
      }) + '\n');
      // Safe default: do NOT block on tool error (could mask real work); emit stderr diagnostic only
      process.exit(0);
    } else if (e.status !== null && e.status !== undefined) {
      // Non-zero, non-1 exit (tool/config error) — surface but do not block
      process.stderr.write(JSON.stringify({
        hookSpecificOutput: {
          permissionDecision: 'deny',
          permissionDecisionReason: `gitleaks exited ${e.status} (tool/config error) — not blocking`
        }
      }) + '\n');
      process.exit(0);
    }
    // status === null (gitleaks not found or spawn failed) — skip gracefully
  }

  // 2. Workbench file detection
  const staged = (() => {
    try {
      return execSync('git diff --cached --name-only', { stdio: ['ignore', 'pipe', 'ignore'] }).toString().split('\n');
    } catch { return []; }
  })();

  const bad = staged.filter(f => /\.(csv|env|pem|key)$|^scratch\/|^workbench\//.test(f));
  if (bad.length) deny(`Workbench/secret files staged: ${bad.join(', ')}`);

  process.exit(0);
});
