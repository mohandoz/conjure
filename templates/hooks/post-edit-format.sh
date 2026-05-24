#!/usr/bin/env bash
# PostToolUse hook for Edit|Write|MultiEdit — format the changed file.
# Exit codes: 0 = ok (continue), non-zero = warning (does NOT block).
# Hooks must finish in <2s; keep formatters fast.

set -euo pipefail

FILE="${1:-}"
[ -z "$FILE" ] && exit 0
[ ! -f "$FILE" ] && exit 0

case "$FILE" in
  *.ts|*.tsx|*.js|*.jsx|*.json|*.md|*.html|*.css|*.scss)
    command -v prettier >/dev/null && prettier --write --log-level error "$FILE" 2>/dev/null || true
    ;;
  *.py)
    command -v ruff >/dev/null && ruff format "$FILE" 2>/dev/null || true
    ;;
  *.go)
    command -v gofmt >/dev/null && gofmt -w "$FILE" 2>/dev/null || true
    ;;
  *.rs)
    command -v rustfmt >/dev/null && rustfmt "$FILE" 2>/dev/null || true
    ;;
  *.java|*.kt)
    # Java/Kotlin formatters are slow. Defer to CI / pre-commit.
    ;;
  *.sh|*.bash)
    command -v shfmt >/dev/null && shfmt -w "$FILE" 2>/dev/null || true
    ;;
esac

exit 0
