#!/usr/bin/env bash
set -uo pipefail
TARGET="${1:-$(pwd)}"
PROFILE_DIR="$(cd "$(dirname "$0")" && pwd)"
echo "▸ Applying compliance overlay: SOC 2 → $TARGET"
if [ -f "$TARGET/CLAUDE.md" ] && ! grep -q "<!-- compliance:soc2 -->" "$TARGET/CLAUDE.md"; then
  cat "$PROFILE_DIR/CLAUDE.md.fragment" >> "$TARGET/CLAUDE.md"
fi
echo "✓ SOC 2 overlay applied"
