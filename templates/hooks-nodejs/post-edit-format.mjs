#!/usr/bin/env node
// Cross-platform PostToolUse hook for Edit|Write|MultiEdit.
// Reads the file path from stdin JSON (Claude Code canonical delivery method).
// Falls back to process.argv[2] / CLAUDE_FILE_PATH for manual CLI invocation.
// Format the changed file using whichever formatter is installed.
// Must finish in <2s.

import { existsSync } from 'node:fs';
import { execSync } from 'node:child_process';
import path from 'node:path';

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
  const file = (p.tool_input?.file_path) || process.argv[2] || process.env.CLAUDE_FILE_PATH || '';
  if (!file || !existsSync(file)) process.exit(0);

  const ext = path.extname(file).toLowerCase();

  const tryRun = (cmd) => {
    try {
      execSync(cmd, { stdio: 'ignore', timeout: 1500 });
      return true;
    } catch { return false; }
  };

  const has = (bin) => {
    try {
      execSync(process.platform === 'win32' ? `where ${bin}` : `command -v ${bin}`, { stdio: 'ignore' });
      return true;
    } catch { return false; }
  };

  const q = (s) => `"${s.replace(/"/g, '\\"')}"`;

  switch (ext) {
    case '.ts': case '.tsx': case '.js': case '.jsx':
    case '.json': case '.md': case '.html': case '.css': case '.scss':
      if (has('prettier')) tryRun(`prettier --write --log-level error ${q(file)}`);
      break;
    case '.py':
      if (has('ruff')) tryRun(`ruff format ${q(file)}`);
      break;
    case '.go':
      if (has('gofmt')) tryRun(`gofmt -w ${q(file)}`);
      break;
    case '.rs':
      if (has('rustfmt')) tryRun(`rustfmt ${q(file)}`);
      break;
    case '.sh': case '.bash':
      if (has('shfmt')) tryRun(`shfmt -w ${q(file)}`);
      break;
  }

  process.exit(0);
});
