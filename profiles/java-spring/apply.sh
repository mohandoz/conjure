#!/usr/bin/env bash
# profiles/java-spring/apply.sh — overlay for Java 17 + Spring Boot + Gradle.
set -uo pipefail
TARGET="${1:-$(pwd)}"
DRY="${2:-0}"

PROFILE_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "▸ Applying profile: java-spring → $TARGET"

# Append CLAUDE.md fragment
if [ -f "$TARGET/CLAUDE.md" ] && [ -f "$PROFILE_DIR/CLAUDE.md.fragment" ]; then
  if ! grep -q "<!-- profile:java-spring -->" "$TARGET/CLAUDE.md"; then
    [ "$DRY" = 0 ] && cat "$PROFILE_DIR/CLAUDE.md.fragment" >> "$TARGET/CLAUDE.md"
    echo "  ✓ appended CLAUDE.md fragment"
  fi
fi

# Override post-edit-format hook for Java
if [ -d "$TARGET/.claude/hooks" ] && [ -f "$PROFILE_DIR/hooks/post-edit-format.sh" ]; then
  [ "$DRY" = 0 ] && cp "$PROFILE_DIR/hooks/post-edit-format.sh" "$TARGET/.claude/hooks/post-edit-format.sh"
  [ "$DRY" = 0 ] && chmod +x "$TARGET/.claude/hooks/post-edit-format.sh"
  echo "  ✓ installed Java-aware format hook"
fi

# Pre-flight
"$PROFILE_DIR/preflight.sh" || echo "  ⚠ preflight had warnings; continuing"

echo "✓ Profile java-spring applied"
