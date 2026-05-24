#!/usr/bin/env bash
# monorepo profile — adds nested CLAUDE.md scaffolds per package.
set -uo pipefail
TARGET="${1:-$(pwd)}"
DRY="${2:-0}"
PROFILE_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "▸ Applying profile: monorepo → $TARGET"

# Detect package directories
DETECTED=()
[ -d "$TARGET/packages" ] && DETECTED+=("packages")
[ -d "$TARGET/apps" ] && DETECTED+=("apps")
[ -d "$TARGET/services" ] && DETECTED+=("services")
[ -d "$TARGET/libs" ] && DETECTED+=("libs")

if [ ${#DETECTED[@]} -eq 0 ]; then
  echo "  ⚠ no monorepo dirs detected (packages/, apps/, services/, libs/)"
  exit 1
fi

for dir in "${DETECTED[@]}"; do
  for pkg in "$TARGET/$dir"/*; do
    [ -d "$pkg" ] || continue
    name=$(basename "$pkg")

    if [ ! -f "$pkg/CLAUDE.md" ]; then
      if [ "$DRY" = 0 ]; then
        cat > "$pkg/CLAUDE.md" <<EOF
# $dir/$name — Local Working Notes

<!-- This nested CLAUDE.md loads automatically when Claude reads files here. -->
<!-- ≤50 lines. Override root rules ONLY where this package differs. -->

## Local rules

- <package-specific rule>

## Build/test (this package only)

| Goal | Command |
| --- | --- |
| Build | \`<cmd>\` |
| Test | \`<cmd>\` |

## Notes

- Owner: <name>
- Type: <library | service | app>
EOF
      fi
      echo "  ✓ scaffolded $dir/$name/CLAUDE.md"
    else
      echo "  • $dir/$name/CLAUDE.md exists — skipping"
    fi
  done
done

# Append monorepo fragment to root CLAUDE.md
if [ -f "$TARGET/CLAUDE.md" ] && [ -f "$PROFILE_DIR/CLAUDE.md.fragment" ]; then
  if ! grep -q "<!-- profile:monorepo -->" "$TARGET/CLAUDE.md"; then
    [ "$DRY" = 0 ] && cat "$PROFILE_DIR/CLAUDE.md.fragment" >> "$TARGET/CLAUDE.md"
    echo "  ✓ appended monorepo fragment to root CLAUDE.md"
  fi
fi

echo "✓ Profile monorepo applied"
