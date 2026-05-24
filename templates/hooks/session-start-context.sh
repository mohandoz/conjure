#!/usr/bin/env bash
# SessionStart hook — inject dynamic context that doesn't belong in CLAUDE.md.
# Output to stdout becomes additional context for the session.
# Must finish in <2s.

set -uo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$REPO_ROOT"

# Current branch
BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)"

# Uncommitted changes count
DIRTY="$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')"

# graphify freshness check
GRAPH_NOTE=""
if [ -f "graphify-out/graph.json" ]; then
  GRAPH_AGE_DAYS=$(( ($(date +%s) - $(stat -f %m graphify-out/graph.json 2>/dev/null || stat -c %Y graphify-out/graph.json 2>/dev/null || echo 0)) / 86400 ))
  if [ "$GRAPH_AGE_DAYS" -gt 7 ]; then
    GRAPH_NOTE="⚠️ graphify-out/graph.json is $GRAPH_AGE_DAYS days old — consider \`graphify . --update\`."
  fi
fi

cat <<EOF
## Dynamic session context

- Branch: \`$BRANCH\`
- Uncommitted changes: $DIRTY files
- Recent commits: \`git log -5 --oneline\`
$GRAPH_NOTE

EOF

exit 0
