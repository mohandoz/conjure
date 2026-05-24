#!/usr/bin/env bash
# PreToolUse hook for Bash matching `git commit` — block if quality gates fail.
# EXIT 2 = BLOCK. Quick checks only (< 5s); long checks belong in CI.

set -uo pipefail

CMD="${1:-}"
echo "$CMD" | grep -qE '^git[[:space:]]+commit' || exit 0

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
[ -z "$REPO_ROOT" ] && exit 0
cd "$REPO_ROOT"

# 1. Secret scan on staged files (gitleaks if installed)
if command -v gitleaks >/dev/null 2>&1; then
  if ! gitleaks protect --staged --no-banner --redact 2>/dev/null; then
    cat <<EOF >&2
{"hookSpecificOutput": {"permissionDecision": "deny", "permissionDecisionReason": "Blocked: gitleaks detected secrets in staged files. Remove the secret, rewrite history if already committed, and rotate the credential."}}
EOF
    exit 2
  fi
fi

# 2. Don't commit untracked workbench files
STAGED_PROBLEMATIC=$(git diff --cached --name-only | grep -E '\.(csv|env|pem|key)$|^scratch/|^workbench/' || true)
if [ -n "$STAGED_PROBLEMATIC" ]; then
  cat <<EOF >&2
{"hookSpecificOutput": {"permissionDecision": "deny", "permissionDecisionReason": "Blocked: workbench/secret-pattern files staged for commit: $STAGED_PROBLEMATIC"}}
EOF
  exit 2
fi

# 3. (Optional) Quick lint of staged files — uncomment if your lint is <3s
# command -v eslint >/dev/null && git diff --cached --name-only --diff-filter=ACMR '*.ts' '*.tsx' '*.js' | xargs -r eslint --quiet || { echo "lint failed" >&2; exit 2; }

exit 0
