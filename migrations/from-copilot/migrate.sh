#!/usr/bin/env bash
# Migrate from GitHub Copilot (.github/copilot-instructions.md + per-language files) to Conjure.
set -uo pipefail
TARGET="${1:-$(pwd)}"
DRY="${DRY_RUN:-0}"
KIT="${CONJURE_HOME:-/u01/conjure}"

REPORT="$TARGET/.claude/MIGRATION-REPORT-copilot.md"
mkdir -p "$TARGET/.claude"
[ "$DRY" = 0 ] && : > "$REPORT"
note() { echo "  $1"; [ "$DRY" = 0 ] && echo "$1" >> "$REPORT"; }

note "# Conjure migration — from-copilot"
note ""

MAIN="$TARGET/.github/copilot-instructions.md"
PER_LANG_DIR="$TARGET/.github/instructions"

FOUND=0
[ -f "$MAIN" ] && FOUND=1 && note "- detected: .github/copilot-instructions.md"
[ -d "$PER_LANG_DIR" ] && FOUND=1 && note "- detected: .github/instructions/"

[ $FOUND -eq 0 ] && { echo "✗ No Copilot instruction files found."; exit 1; }

DRAFT="$TARGET/.claude/CLAUDE.md.draft"
if [ "$DRY" = 0 ]; then
cat > "$DRAFT" <<EOF
# <PROJECT_NAME> — Claude Working Notes
<!-- Migrated from GitHub Copilot. Original instructions preserved as comments. -->

## NON-NEGOTIABLE RULES
<!-- TODO: review and convert each rule to "WHEN X, DO Y" or "NEVER X" form. -->

EOF
  if [ -f "$MAIN" ]; then
    echo "<!-- ORIGINAL: .github/copilot-instructions.md -->" >> "$DRAFT"
    sed 's/^/<!-- /; s/$/ -->/' "$MAIN" >> "$DRAFT"
    echo "" >> "$DRAFT"
  fi

  if [ -d "$PER_LANG_DIR" ]; then
    for f in "$PER_LANG_DIR"/*.md; do
      [ -f "$f" ] || continue
      base=$(basename "$f" .md)
      note "  ▸ Per-language file '$base' → candidate for nested CLAUDE.md or skill"
      echo "<!-- ORIGINAL: .github/instructions/$(basename "$f") -->" >> "$DRAFT"
      sed 's/^/<!-- /; s/$/ -->/' "$f" >> "$DRAFT"
      echo "" >> "$DRAFT"
    done
  fi

cat >> "$DRAFT" <<EOF

## Build, test, run
<!-- TODO: fill from existing CI / Makefile -->

## Routing
<!-- Claude will populate during 'init existing' -->
EOF

  note ""
  note "Output: $DRAFT"
  note "Original Copilot files preserved (NOT renamed — Copilot may still be active)."

  bash "$KIT/scripts/init-project.sh" existing "$TARGET" 2>&1 | sed 's/^/  /' | tee -a "$REPORT"
  echo "$(cat "$KIT/VERSION")" > "$TARGET/.claude/.conjure-version"
fi

echo "✓ Copilot → Conjure migration draft complete. Review: $DRAFT"
echo "  Note: Copilot instruction files are preserved — you can run both assistants in parallel."
