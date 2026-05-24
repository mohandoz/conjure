#!/usr/bin/env bash
# polyglot — minimal overlay for multi-language projects.
set -uo pipefail
TARGET="${1:-$(pwd)}"
DRY="${2:-0}"
PROFILE_DIR="$(cd "$(dirname "$0")" && pwd)"
echo "▸ Applying profile: polyglot → $TARGET"
if [ -f "$TARGET/CLAUDE.md" ] && [ -f "$PROFILE_DIR/CLAUDE.md.fragment" ]; then
  if ! grep -q "<!-- profile:polyglot -->" "$TARGET/CLAUDE.md"; then
    [ "$DRY" = 0 ] && cat "$PROFILE_DIR/CLAUDE.md.fragment" >> "$TARGET/CLAUDE.md"
    echo "  ✓ appended CLAUDE.md fragment"
  fi
fi
echo "✓ Profile polyglot applied"
echo "  ℹ Consider adding nested CLAUDE.md per language subtree."
