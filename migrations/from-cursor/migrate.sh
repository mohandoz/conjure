#!/usr/bin/env bash
# Migrate from Cursor (.cursorrules or .cursor/rules/*.mdc) to Conjure.
# Preserves rule text as comments; converts to trigger-action format.

set -uo pipefail
TARGET="${1:-$(pwd)}"
DRY="${DRY_RUN:-0}"
KIT="${CONJURE_HOME:-/u01/conjure}"

REPORT="$TARGET/.claude/MIGRATION-REPORT-cursor.md"
mkdir -p "$TARGET/.claude"
[ "$DRY" = 0 ] && : > "$REPORT"

note() { echo "  $1"; [ "$DRY" = 0 ] && echo "$1" >> "$REPORT"; }

note "# Conjure migration — from-cursor"
note "Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
note ""

SOURCES=()
[ -f "$TARGET/.cursorrules" ] && SOURCES+=(".cursorrules")
[ -d "$TARGET/.cursor/rules" ] && SOURCES+=(".cursor/rules/")

if [ ${#SOURCES[@]} -eq 0 ]; then
  echo "✗ No Cursor config found at $TARGET (.cursorrules or .cursor/rules/)"
  exit 1
fi

note "## Detected sources"
for s in "${SOURCES[@]}"; do note "- $s"; done

# Build draft CLAUDE.md
DRAFT="$TARGET/.claude/CLAUDE.md.draft"
if [ "$DRY" = 0 ]; then
cat > "$DRAFT" <<EOF
# <PROJECT_NAME> — Claude Working Notes
<!-- Migrated from Cursor. Original rules preserved as HTML comments. -->
<!-- Generated $(date -u +%Y-%m-%dT%H:%M:%SZ) by conjure migrate from-cursor -->

## NON-NEGOTIABLE RULES

<!-- TODO: review rules below; convert each to "WHEN X, DO Y" or "NEVER X" form. -->

EOF

  if [ -f "$TARGET/.cursorrules" ]; then
    echo "<!-- ORIGINAL: .cursorrules -->" >> "$DRAFT"
    sed 's/^/<!-- /; s/$/ -->/' "$TARGET/.cursorrules" >> "$DRAFT"
    echo "" >> "$DRAFT"
  fi

  if [ -d "$TARGET/.cursor/rules" ]; then
    for rule in "$TARGET"/.cursor/rules/*.mdc; do
      [ -f "$rule" ] || continue
      name=$(basename "$rule" .mdc)
      echo "<!-- ORIGINAL: .cursor/rules/$(basename "$rule") -->" >> "$DRAFT"
      sed 's/^/<!-- /; s/$/ -->/' "$rule" >> "$DRAFT"
      echo "" >> "$DRAFT"
      note "  ▸ Per-glob rule '$name' → review for promotion to skill if scoped to specific paths"
    done
  fi

  cat >> "$DRAFT" <<EOF

## Build, test, run
<!-- TODO: fill these in (Cursor doesn't carry build commands explicitly) -->

## Routing
<!-- See .claude/skills/ — Claude will populate during 'init existing' -->

## Conventions
<!-- TODO: extract from above HTML comments into concrete rules -->
EOF

  note ""
  note "## Output"
  note "- Draft CLAUDE.md written to: $DRAFT"
  note "- Original .cursorrules preserved (RENAME to .cursorrules.deprecated after review)"
fi

# Rename source files to .deprecated (preserve, don't delete)
if [ "$DRY" = 0 ]; then
  for s in "${SOURCES[@]}"; do
    SRC="$TARGET/$s"
    if [ -e "$SRC" ] && [ ! -e "${SRC}.deprecated" ]; then
      mv "$SRC" "${SRC}.deprecated"
      note "- Renamed: $s → ${s}.deprecated (delete after 1 week of confidence)"
    fi
  done
fi

# Run base scaffold
if [ "$DRY" = 0 ]; then
  bash "$KIT/scripts/init-project.sh" existing "$TARGET" 2>&1 | sed 's/^/  /' | tee -a "$REPORT"
  echo "$(cat "$KIT/VERSION")" > "$TARGET/.claude/.conjure-version"
fi

echo
echo "✓ Cursor → Conjure migration draft complete."
echo "  Review draft: $DRAFT"
echo "  When happy, rename: mv $DRAFT $TARGET/CLAUDE.md"
echo "  Report: $REPORT"
