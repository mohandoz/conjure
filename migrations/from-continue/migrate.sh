#!/usr/bin/env bash
# Migrate from Continue (.continue/config.json) to Conjure.
# Continue's value is mostly MCP-style integrations; map them to Claude Code MCP config.
set -uo pipefail
TARGET="${1:-$(pwd)}"
DRY="${DRY_RUN:-0}"
KIT="${CONJURE_HOME:-/u01/conjure}"

REPORT="$TARGET/.claude/MIGRATION-REPORT-continue.md"
mkdir -p "$TARGET/.claude"
[ "$DRY" = 0 ] && : > "$REPORT"
note() { echo "  $1"; [ "$DRY" = 0 ] && echo "$1" >> "$REPORT"; }

note "# Conjure migration — from-continue"
note ""

CONFIG="$TARGET/.continue/config.json"
if [ ! -f "$CONFIG" ]; then
  echo "✗ No Continue config at $CONFIG"
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "✗ jq required for Continue migration (brew install jq)"
  exit 1
fi

note "## Detected Continue config"
note ""
note "### Models"
jq -r '.models[]? | "- \(.title // .model) (\(.provider))"' "$CONFIG" | while read -r line; do note "$line"; done
note "  Note: not migrated. Claude Code uses its own model selection."

note ""
note "### Custom commands → candidate slash commands"
jq -r '.customCommands[]? | "- /\(.name): \(.description)"' "$CONFIG" 2>/dev/null | while read -r line; do
  note "$line"
done
note "  → Convert to .claude/skills/ or Claude Code custom commands (review descriptions for skill-fire match)."

note ""
note "### Context providers (MCP-like)"
jq -r '.contextProviders[]? | "- \(.name)"' "$CONFIG" 2>/dev/null | while read -r line; do
  note "$line"
done
note "  → Map equivalents from reference/MCP-SERVERS.md (database, codebase, search)."

note ""
note "### MCP servers (explicit, if any)"
jq -r '.experimental.modelContextProtocolServers[]? | "- \(.name): \(.command)"' "$CONFIG" 2>/dev/null | while read -r line; do
  note "$line"
done

# Rename source
if [ "$DRY" = 0 ]; then
  if [ -d "$TARGET/.continue" ] && [ ! -d "$TARGET/.continue.deprecated" ]; then
    mv "$TARGET/.continue" "$TARGET/.continue.deprecated"
    note ""
    note "Renamed: .continue/ → .continue.deprecated/"
  fi
  bash "$KIT/scripts/init-project.sh" existing "$TARGET" 2>&1 | sed 's/^/  /' | tee -a "$REPORT"
  echo "$(cat "$KIT/VERSION")" > "$TARGET/.claude/.conjure-version"
fi

echo "✓ Continue → Conjure report: $REPORT"
echo "  Action items: review MCP candidates → bash $KIT/scripts/install-mcp-stack.sh"
