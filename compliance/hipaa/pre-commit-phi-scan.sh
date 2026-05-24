#!/usr/bin/env bash
# Pre-commit PHI scan hook — block commits containing obvious PHI patterns.
# Heuristic only; NOT a substitute for a proper data-loss-prevention tool.
# EXIT 2 to block.
set -uo pipefail

CMD="${1:-}"
echo "$CMD" | grep -qE '^git[[:space:]]+commit' || exit 0

cd "$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0

# Patterns (heuristic — tune for your domain)
PATTERNS=(
  '\b[0-9]{3}-[0-9]{2}-[0-9]{4}\b'                          # SSN
  '\b(MRN|mrn)[[:space:]]*[:=][[:space:]]*[0-9]{6,}'         # MRN
  '\bDOB[[:space:]]*[:=]'                                    # date of birth label
  '\b[0-9]{1,2}/[0-9]{1,2}/(19|20)[0-9]{2}\b'                # date in PHI context
  '\b[A-Za-z0-9._%+-]+@(gmail|yahoo|hotmail|outlook)\.com\b' # personal email
)

HITS=""
for p in "${PATTERNS[@]}"; do
  M=$(git diff --cached -U0 | grep -nE "$p" 2>/dev/null | head -3) || true
  [ -n "$M" ] && HITS+="$M"$'\n'
done

if [ -n "$HITS" ]; then
  cat >&2 <<EOF
{"hookSpecificOutput": {"permissionDecision": "deny", "permissionDecisionReason": "PHI pattern in staged diff. Review:\n$HITS"}}
EOF
  exit 2
fi
exit 0
