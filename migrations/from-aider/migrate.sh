#!/usr/bin/env bash
# Migrate from Aider (.aider.conf.yml + CONVENTIONS.md) to Conjure.
set -uo pipefail
TARGET="${1:-$(pwd)}"
DRY="${DRY_RUN:-0}"
KIT="${CONJURE_HOME:-/u01/conjure}"

REPORT="$TARGET/.claude/MIGRATION-REPORT-aider.md"
mkdir -p "$TARGET/.claude"
[ "$DRY" = 0 ] && : > "$REPORT"
note() { echo "  $1"; [ "$DRY" = 0 ] && echo "$1" >> "$REPORT"; }

note "# Conjure migration — from-aider"
note "Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
note ""

FOUND=0
[ -f "$TARGET/.aider.conf.yml" ] && FOUND=1 && note "- detected: .aider.conf.yml"
[ -f "$TARGET/CONVENTIONS.md" ]  && FOUND=1 && note "- detected: CONVENTIONS.md"
[ -f "$TARGET/.aider.input.history" ] && note "- detected: .aider.input.history (will not migrate)"

if [ $FOUND -eq 0 ]; then
  echo "✗ No Aider config found."
  exit 1
fi

DRAFT="$TARGET/.claude/CLAUDE.md.draft"
if [ "$DRY" = 0 ]; then
cat > "$DRAFT" <<EOF
# <PROJECT_NAME> — Claude Working Notes
<!-- Migrated from Aider. Conventions promoted; model/voice settings NOT migrated. -->

## NON-NEGOTIABLE RULES
<!-- TODO: extract from CONVENTIONS.md below into trigger-action format. -->

EOF

  if [ -f "$TARGET/CONVENTIONS.md" ]; then
    echo "<!-- ORIGINAL: CONVENTIONS.md -->" >> "$DRAFT"
    sed 's/^/<!-- /; s/$/ -->/' "$TARGET/CONVENTIONS.md" >> "$DRAFT"
    echo "" >> "$DRAFT"
  fi

  if [ -f "$TARGET/.aider.conf.yml" ]; then
    note ""
    note "## Aider config translation"
    note "- model:        not migrated (Claude Code picks model per session)"
    note "- map-tokens:   not migrated (Claude Code manages context automatically)"
    note "- read-only:    review and convert to .claudeignore patterns"
    note "- gitignore:    Conjure respects .gitignore + .claudeignore by default"
  fi

  cat >> "$DRAFT" <<EOF

## Build, test, run
<!-- TODO: fill from CONVENTIONS.md or project Makefile -->

## Routing
<!-- Claude will populate during 'init existing' -->
EOF

  note ""
  note "Output: $DRAFT"

  # Rename source
  for s in .aider.conf.yml CONVENTIONS.md; do
    SRC="$TARGET/$s"
    if [ -e "$SRC" ] && [ ! -e "${SRC}.deprecated" ]; then
      mv "$SRC" "${SRC}.deprecated"
      note "Renamed: $s → ${s}.deprecated"
    fi
  done

  bash "$KIT/scripts/init-project.sh" existing "$TARGET" 2>&1 | sed 's/^/  /' | tee -a "$REPORT"
  echo "$(cat "$KIT/VERSION")" > "$TARGET/.claude/.conjure-version"
fi

echo "✓ Aider → Conjure migration draft complete. Review: $DRAFT"
