#!/usr/bin/env node
// Cross-platform PreToolUse hook for `git commit` — block bad commits.
// Exit 2 = BLOCK.

import { execSync } from 'node:child_process';

const cmd = process.argv[2] || process.env.CLAUDE_COMMAND || '';
if (!/^git\s+commit/.test(cmd)) process.exit(0);

let repoRoot;
try { repoRoot = execSync('git rev-parse --show-toplevel', { stdio: ['ignore', 'pipe', 'ignore'] }).toString().trim(); }
catch { process.exit(0); }
process.chdir(repoRoot);

const deny = (msg) => {
  process.stderr.write(JSON.stringify({
    hookSpecificOutput: { permissionDecision: 'deny', permissionDecisionReason: msg }
  }) + '\n');
  process.exit(2);
};

// 1. Secret scan via gitleaks (if installed)
try {
  execSync('gitleaks protect --staged --no-banner --redact', { stdio: 'ignore' });
} catch (e) {
  if (e.status !== undefined) {
    deny('gitleaks detected secrets in staged files. Remove + rotate before committing.');
  }
  // gitleaks not installed → skip
}

// 2. Workbench file detection
const staged = (() => {
  try { return execSync('git diff --cached --name-only', { stdio: ['ignore', 'pipe', 'ignore'] }).toString().split('\n'); }
  catch { return []; }
})();

const bad = staged.filter(f => /\.(csv|env|pem|key)$|^scratch\/|^workbench\//.test(f));
if (bad.length) deny(`Workbench/secret files staged: ${bad.join(', ')}`);

process.exit(0);
