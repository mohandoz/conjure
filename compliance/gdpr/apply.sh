#!/usr/bin/env bash
set -uo pipefail
TARGET="${1:-$(pwd)}"
PROFILE_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$CONJURE_HOME/lib/mutate.sh"
echo "▸ Applying compliance overlay: GDPR → $TARGET"
if [ -f "$TARGET/CLAUDE.md" ] && ! grep -q "<!-- compliance:gdpr -->" "$TARGET/CLAUDE.md"; then
  mutate_write "$TARGET/CLAUDE.md" "$(cat "$PROFILE_DIR/CLAUDE.md.fragment")" "--append"
fi
mutate_summary
echo "✓ GDPR overlay applied"
