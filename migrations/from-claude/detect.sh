#!/usr/bin/env bash
# Detect existing CLAUDE.md / .claude/ artifacts in a target repo.
# Exit codes: 0 = found, 1 = none.
set -uo pipefail
TARGET="${1:-$(pwd)}"

FOUND=()
[ -f "$TARGET/CLAUDE.md" ]             && FOUND+=("CLAUDE.md")
[ -d "$TARGET/.claude" ]               && FOUND+=(".claude/")
[ -f "$TARGET/.claude/settings.json" ] && FOUND+=(".claude/settings.json")
[ -d "$TARGET/.claude/skills" ]        && FOUND+=(".claude/skills/")
[ -d "$TARGET/.claude/agents" ]        && FOUND+=(".claude/agents/")
find "$TARGET" -maxdepth 3 -name 'CLAUDE.md' -not -path "$TARGET/CLAUDE.md" 2>/dev/null | while read -r f; do
  echo "nested: $f"
done

if [ ${#FOUND[@]} -eq 0 ]; then
  echo "no existing Claude config"
  exit 1
fi

printf 'Existing artifacts: %s\n' "${FOUND[*]}"
exit 0
