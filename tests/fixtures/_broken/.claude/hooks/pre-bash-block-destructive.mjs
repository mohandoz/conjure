#!/usr/bin/env node
// Cross-platform PreToolUse hook for Bash — block destructive commands.
// Exit 2 = BLOCK. Exit 0 = ALLOW.

const cmd = process.argv[2] || process.env.CLAUDE_COMMAND || '';
if (!cmd) process.exit(0);

const BLOCK_PATTERNS = [
  /rm\s+-rf\s+\/(?!\w)/,
  /rm\s+-rf\s+~/,
  /rm\s+-rf\s+\$HOME/,
  /:\(\)\{\s*:\|:&\s*\};:/,                  // fork bomb
  /curl\s+[^|]*\|\s*(sh|bash)/,
  /wget\s+[^|]*\|\s*(sh|bash)/,
  /git\s+push\s+.*--force(?!-with-lease)/,
  /git\s+push\s+.*-f(\s|$)/,
  /git\s+reset\s+.*--hard\s+(origin\/)?(main|master|develop|trunk)/,
  /DROP\s+DATABASE/i,
  /DROP\s+SCHEMA\s+public/i,
  /TRUNCATE\s+TABLE/i,
  /chmod\s+-R\s+777/,
  />\s*\/dev\/sda/,
];

const WORKBENCH_PATTERNS = [
  /^git\s+add\s+.*\.(csv|env|pem|key)(\s|$)/,
  /^git\s+add\s+.*\/secrets\//,
  /^git\s+add\s+.*\/scratch\//,
  /^git\s+add\s+.*workbench\//,
];

const reason = (msg) => {
  process.stderr.write(JSON.stringify({
    hookSpecificOutput: { permissionDecision: 'deny', permissionDecisionReason: msg }
  }) + '\n');
  process.exit(2);
};

for (const p of BLOCK_PATTERNS) {
  if (p.test(cmd)) reason(`Blocked by pre-bash-block-destructive: matches ${p}. Run manually if intentional.`);
}
for (const p of WORKBENCH_PATTERNS) {
  if (p.test(cmd)) reason(`Blocked: attempting to git-add a workbench/secret/scratch file. Add specific files explicitly if intentional.`);
}

process.exit(0);
