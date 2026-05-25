#!/usr/bin/env node
// Cross-platform Stop hook — compound-engineering loop scaffold.
// Appends a session marker to .claude/COMPOUND-CANDIDATES.md for human review.

import { execSync } from 'node:child_process';
import { mkdirSync, appendFileSync } from 'node:fs';
import path from 'node:path';

let repoRoot;
try { repoRoot = execSync('git rev-parse --show-toplevel', { stdio: ['ignore', 'pipe', 'ignore'] }).toString().trim(); }
catch { repoRoot = process.cwd(); }

const candidatesDir = path.join(repoRoot, '.claude');
const candidatesFile = path.join(candidatesDir, 'COMPOUND-CANDIDATES.md');

mkdirSync(candidatesDir, { recursive: true });

const ts = new Date().toISOString();
appendFileSync(candidatesFile, `

## Session ${ts}

<!--
Review candidate CLAUDE.md / skill edits from this session.
- Repeated corrections? → CLAUDE.md rule
- Specific workflow? → new skill
- Destructive action attempted? → new hook
-->
`);

process.exit(0);
