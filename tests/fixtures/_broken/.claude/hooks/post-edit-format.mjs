#!/usr/bin/env node
// Cross-platform PostToolUse hook for Edit|Write|MultiEdit.
// Format the changed file using whichever formatter is installed.
// Must finish in <2s.

import { existsSync } from 'node:fs';
import { execSync } from 'node:child_process';
import path from 'node:path';

const file = process.argv[2] || process.env.CLAUDE_FILE_PATH;
if (!file || !existsSync(file)) process.exit(0);

const ext = path.extname(file).toLowerCase();

const tryRun = (cmd) => {
  try {
    execSync(cmd, { stdio: 'ignore', timeout: 1500 });
    return true;
  } catch { return false; }
};

const has = (bin) => {
  try { execSync(process.platform === 'win32' ? `where ${bin}` : `command -v ${bin}`, { stdio: 'ignore' }); return true; }
  catch { return false; }
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
