#!/usr/bin/env bash
# Migrate from Windsurf (.windsurfrules) to Conjure. Simple rule promotion.
set -uo pipefail
TARGET="${1:-$(pwd)}"
DRY="${DRY_RUN:-0}"
KIT="${CONJURE_HOME:-/u01/conjure}"

SRC="$TARGET/.windsurfrules"
[ ! -f "$SRC" ] && { echo "✗ No .windsurfrules found"; exit 1; }

REPORT="$TARGET/.claude/MIGRATION-REPORT-windsurf.md"
mkdir -p "$TARGET/.claude"
DRAFT="$TARGET/.claude/CLAUDE.md.draft"

[ "$DRY" = 0 ] && : > "$REPORT"
echo "# Conjure migration — from-windsurf" > "$REPORT"
echo "Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$REPORT"

if [ "$DRY" = 0 ]; then
cat > "$DRAFT" <<EOF
# <PROJECT_NAME> — Claude Working Notes
<!-- Migrated from Windsurf. -->

## NON-NEGOTIABLE RULES
<!-- TODO: convert each Windsurf rule below into "WHEN X, DO Y" / "NEVER X" form. -->

<!-- ORIGINAL: .windsurfrules -->
EOF
  sed 's/^/<!-- /; s/$/ -->/' "$SRC" >> "$DRAFT"
  echo "" >> "$DRAFT"
cat >> "$DRAFT" <<EOF

## Build, test, run
<!-- TODO: fill -->

## Routing
<!-- Claude will populate during 'init existing' -->
EOF

  mv "$SRC" "${SRC}.deprecated"
  bash "$KIT/scripts/init-project.sh" existing "$TARGET" >> "$REPORT" 2>&1
  echo "$(cat "$KIT/VERSION")" > "$TARGET/.claude/.conjure-version"
fi

echo "✓ Windsurf → Conjure migration draft complete. Review: $DRAFT"
