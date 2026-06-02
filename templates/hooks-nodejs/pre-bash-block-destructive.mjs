#!/usr/bin/env node
// Cross-platform PreToolUse hook for Bash — block destructive commands.
// Reads the command from stdin JSON (Claude Code canonical delivery method).
// Falls back to process.argv[2] / CLAUDE_COMMAND for manual CLI invocation.
// Exit 2 = BLOCK. Exit 0 = ALLOW.

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
  if (!cmd) process.exit(0);

  const reason = (msg) => {
    process.stderr.write(JSON.stringify({
      hookSpecificOutput: { permissionDecision: 'deny', permissionDecisionReason: msg }
    }) + '\n');
    process.exit(2);
  };

  // FIX-06: hardened rm-rf detector that covers rm -rf, rm -fr, rm -r -f, rm -Rf, etc.
  // Checks for presence of both r-family and f-family flags, then a path starting with / ~ $HOME.
  function isDestructiveRm(command) {
    // Match `rm` word boundary followed by flags and a path
    const rmMatch = command.match(/\brm\b((?:\s+-\S+)+)\s+(\S+)/);
    if (!rmMatch) return false;
    const flagsStr = rmMatch[1];
    const pathArg = rmMatch[2];

    // Collect individual flag tokens (e.g. "-rf", "-r", "-f", "--recursive", "--force")
    const flagTokens = flagsStr.match(/-\S+/g) || [];

    let hasR = false;
    let hasF = false;
    for (const token of flagTokens) {
      if (token === '--recursive') { hasR = true; continue; }
      if (token === '--force')     { hasF = true; continue; }
      if (token.startsWith('--')) continue; // skip other long flags
      // Short flag group: strip leading '-' and check individual letters
      const letters = token.slice(1);
      if (/[rR]/.test(letters)) hasR = true;
      if (/[f]/.test(letters))  hasF = true;
    }

    if (!hasR || !hasF) return false;

    // Only block absolute/home paths to avoid false positives on relative paths
    return /^[/~$]/.test(pathArg);
  }

  // Check hardened rm-rf pattern first (FIX-06)
  if (isDestructiveRm(cmd)) {
    reason('Blocked by pre-bash-block-destructive: destructive rm targeting absolute/home path. Run manually if intentional.');
  }

  const BLOCK_PATTERNS = [
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

  for (const pat of BLOCK_PATTERNS) {
    if (pat.test(cmd)) reason(`Blocked by pre-bash-block-destructive: matches ${pat}. Run manually if intentional.`);
  }
  for (const pat of WORKBENCH_PATTERNS) {
    if (pat.test(cmd)) reason(`Blocked: attempting to git-add a workbench/secret/scratch file. Add specific files explicitly if intentional.`);
  }

  process.exit(0);
});
