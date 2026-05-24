#!/usr/bin/env bash
# Stop hook — compound engineering loop.
# At session end, append a candidate CLAUDE.md edit based on the session's
# transcript (corrections, reverted edits, repeated mistakes).
#
# This DOES NOT modify CLAUDE.md automatically. It appends a suggestion to
# .claude/COMPOUND-CANDIDATES.md for human review.

set -uo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
CANDIDATES="$REPO_ROOT/.claude/COMPOUND-CANDIDATES.md"
mkdir -p "$(dirname "$CANDIDATES")"

# Lightweight heuristic: look at the last hour of session activity for
# common "correction" signals. Replace with a real LLM call if you wire
# Claude API access here.

TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
cat >>"$CANDIDATES" <<EOF

## Session $TS

<!--
Review candidate CLAUDE.md / skill edits from this session.
If a rule appeared during conversation, promote it here.

Check:
- Were there repeated corrections? → CLAUDE.md rule
- Was a specific workflow performed? → new skill
- Was a destructive action attempted? → new hook
-->

EOF

exit 0
