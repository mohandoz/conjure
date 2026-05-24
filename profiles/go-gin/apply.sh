#!/usr/bin/env bash
set -uo pipefail
TARGET="${1:-$(pwd)}"
DRY="${2:-0}"
PROFILE_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "▸ Applying profile: go-gin → $TARGET"

if [ -f "$TARGET/CLAUDE.md" ] && [ -f "$PROFILE_DIR/CLAUDE.md.fragment" ]; then
  if ! grep -q "<!-- profile:go-gin -->" "$TARGET/CLAUDE.md"; then
    [ "$DRY" = 0 ] && cat "$PROFILE_DIR/CLAUDE.md.fragment" >> "$TARGET/CLAUDE.md"
    echo "  ✓ appended CLAUDE.md fragment"
  fi
fi

"$PROFILE_DIR/preflight.sh" || echo "  ⚠ preflight had warnings"
echo "✓ Profile go-gin applied"
