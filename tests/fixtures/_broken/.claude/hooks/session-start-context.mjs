#!/usr/bin/env node
// Cross-platform SessionStart hook — inject dynamic context.
// Output to stdout becomes additional session context. Must finish in <2s.

import { execSync, spawnSync } from 'node:child_process';
import { existsSync, statSync } from 'node:fs';
import path from 'node:path';

const safe = (cmd) => {
  try { return execSync(cmd, { stdio: ['ignore', 'pipe', 'ignore'] }).toString().trim(); }
  catch { return ''; }
};

const repoRoot = safe('git rev-parse --show-toplevel') || process.cwd();
process.chdir(repoRoot);

const branch  = safe('git rev-parse --abbrev-ref HEAD') || 'unknown';
const dirty   = safe('git status --porcelain').split('\n').filter(Boolean).length;
const lastCommits = safe('git log -5 --oneline');

let graphNote = '';
const graphPath = path.join(repoRoot, 'graphify-out', 'graph.json');
if (existsSync(graphPath)) {
  const ageDays = Math.floor((Date.now() - statSync(graphPath).mtimeMs) / 86_400_000);
  if (ageDays > 7) {
    graphNote = `\n⚠️ graphify-out/graph.json is ${ageDays} days old — consider \`conjure refresh-graph\`.`;
  }
}

process.stdout.write(`## Dynamic session context

- Branch: \`${branch}\`
- Uncommitted changes: ${dirty} files
- Recent commits:
\`\`\`
${lastCommits}
\`\`\`${graphNote}
`);

process.exit(0);
