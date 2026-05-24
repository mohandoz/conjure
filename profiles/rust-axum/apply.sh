#!/usr/bin/env bash
set -uo pipefail
TARGET="${1:-$(pwd)}"
DRY="${2:-0}"
PROFILE_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "▸ Applying profile: rust-axum → $TARGET"

if [ -f "$TARGET/CLAUDE.md" ] && [ -f "$PROFILE_DIR/CLAUDE.md.fragment" ]; then
  if ! grep -q "<!-- profile:rust-axum -->" "$TARGET/CLAUDE.md"; then
    [ "$DRY" = 0 ] && cat "$PROFILE_DIR/CLAUDE.md.fragment" >> "$TARGET/CLAUDE.md"
    echo "  ✓ appended CLAUDE.md fragment"
  fi
fi

"$PROFILE_DIR/preflight.sh" || echo "  ⚠ preflight had warnings"
echo "✓ Profile rust-axum applied"
