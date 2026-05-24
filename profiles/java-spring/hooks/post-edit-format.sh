#!/usr/bin/env bash
# Java-aware post-edit formatter. Skips slow tools.
set -euo pipefail
FILE="${1:-}"
[ -z "$FILE" ] && exit 0
[ ! -f "$FILE" ] && exit 0

case "$FILE" in
  *.java)
    command -v google-java-format >/dev/null && \
      google-java-format -i "$FILE" 2>/dev/null || true
    ;;
  *.kt)
    command -v ktlint >/dev/null && ktlint --format "$FILE" 2>/dev/null || true
    ;;
  *.json|*.yml|*.yaml|*.md)
    command -v prettier >/dev/null && \
      prettier --write --log-level error "$FILE" 2>/dev/null || true
    ;;
  *.sh)
    command -v shfmt >/dev/null && shfmt -w "$FILE" 2>/dev/null || true
    ;;
esac
exit 0
