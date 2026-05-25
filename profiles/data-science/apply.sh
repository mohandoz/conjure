#!/usr/bin/env bash
set -uo pipefail
TARGET="${1:-$(pwd)}"
PROFILE_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$CONJURE_HOME/lib/mutate.sh"
echo "▸ Applying profile: data-science → $TARGET"
if [ -f "$TARGET/CLAUDE.md" ] && [ -f "$PROFILE_DIR/CLAUDE.md.fragment" ]; then
  if ! grep -q "<!-- profile:data-science -->" "$TARGET/CLAUDE.md"; then
    mutate_write "$TARGET/CLAUDE.md" "$(cat "$PROFILE_DIR/CLAUDE.md.fragment")" "--append"
    echo "  ✓ appended CLAUDE.md fragment"
  fi
fi
mutate_summary
echo "✓ Profile data-science applied"
