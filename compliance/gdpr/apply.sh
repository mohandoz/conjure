#!/usr/bin/env bash
set -uo pipefail
TARGET="${1:-$(pwd)}"
PROFILE_DIR="$(cd "$(dirname "$0")" && pwd)"
echo "▸ Applying compliance overlay: GDPR → $TARGET"
if [ -f "$TARGET/CLAUDE.md" ] && ! grep -q "<!-- compliance:gdpr -->" "$TARGET/CLAUDE.md"; then
  cat "$PROFILE_DIR/CLAUDE.md.fragment" >> "$TARGET/CLAUDE.md"
fi
echo "✓ GDPR overlay applied"
