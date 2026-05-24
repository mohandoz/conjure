#!/usr/bin/env bash
# PreToolUse hook for Bash — block obviously destructive commands.
# EXIT 2 = BLOCK. EXIT 0 = ALLOW. Do NOT use exit 1 (non-blocking).
# Augment the deny[] list in settings.json — this catches dynamic constructions.

set -uo pipefail

CMD="${1:-}"
[ -z "$CMD" ] && exit 0

# Patterns to block (extend as needed)
BLOCK_PATTERNS=(
  'rm -rf /'
  'rm -rf ~'
  'rm -rf \$HOME'
  '> /dev/sda'
  ':(){:\|:&};:'
  'curl[[:space:]].*\|[[:space:]]*sh'
  'curl[[:space:]].*\|[[:space:]]*bash'
  'wget[[:space:]].*\|[[:space:]]*sh'
  'git[[:space:]]push[[:space:]].*--force'
  'git[[:space:]]push[[:space:]].*-f([[:space:]]|$)'
  'git[[:space:]]reset[[:space:]].*--hard[[:space:]]+(origin/)?main'
  'git[[:space:]]reset[[:space:]].*--hard[[:space:]]+(origin/)?master'
  'git[[:space:]]reset[[:space:]].*--hard[[:space:]]+(origin/)?develop'
  'DROP[[:space:]]+DATABASE'
  'DROP[[:space:]]+SCHEMA[[:space:]]+public'
  'TRUNCATE[[:space:]]+TABLE'
  'chmod[[:space:]]+-R[[:space:]]+777'
)

for pattern in "${BLOCK_PATTERNS[@]}"; do
  if echo "$CMD" | grep -qE "$pattern"; then
    cat <<EOF >&2
{"hookSpecificOutput": {"permissionDecision": "deny", "permissionDecisionReason": "Blocked by pre-bash-block-destructive hook: matches pattern '$pattern'. If this is intentional, run it manually."}}
EOF
    exit 2
  fi
done

# Block workbench files from `git add`
if echo "$CMD" | grep -qE '^git[[:space:]]+add'; then
  if echo "$CMD" | grep -qE '\.(csv|sql|env|pem|key)(\s|$)|/secrets/|/scratch/|workbench/'; then
    cat <<EOF >&2
{"hookSpecificOutput": {"permissionDecision": "deny", "permissionDecisionReason": "Blocked: attempting to git add a workbench/secret/scratch file. Add the specific file explicitly if intentional."}}
EOF
    exit 2
  fi
fi

exit 0
