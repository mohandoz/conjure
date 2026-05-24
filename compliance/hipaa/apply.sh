#!/usr/bin/env bash
set -uo pipefail
TARGET="${1:-$(pwd)}"
PROFILE_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "▸ Applying compliance overlay: HIPAA → $TARGET"

if [ -f "$TARGET/CLAUDE.md" ] && [ -f "$PROFILE_DIR/CLAUDE.md.fragment" ]; then
  if ! grep -q "<!-- compliance:hipaa -->" "$TARGET/CLAUDE.md"; then
    cat "$PROFILE_DIR/CLAUDE.md.fragment" >> "$TARGET/CLAUDE.md"
    echo "  ✓ appended HIPAA fragment to CLAUDE.md"
  fi
fi

# Hook: pre-commit PHI scan
mkdir -p "$TARGET/.claude/hooks"
cp "$PROFILE_DIR/pre-commit-phi-scan.sh" "$TARGET/.claude/hooks/" 2>/dev/null || true
chmod +x "$TARGET/.claude/hooks/pre-commit-phi-scan.sh" 2>/dev/null

# Add controls checklist
mkdir -p "$TARGET/docs/compliance"
cp "$PROFILE_DIR/CONTROLS.md" "$TARGET/docs/compliance/HIPAA-CONTROLS.md" 2>/dev/null || true

echo "✓ HIPAA overlay applied"
echo "  ⚠ Compliance ≠ Config. Engage your compliance officer."
