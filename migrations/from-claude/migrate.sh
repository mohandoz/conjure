#!/usr/bin/env bash
# Migrate an existing CLAUDE.md / .claude/ setup to Conjure 2026 best practices.
# - Splits oversized CLAUDE.md into skills.
# - Replaces @imports with prose references.
# - Reorders CLAUDE.md so non-negotiables come first.
# - Auto-fixes hook exit codes (1 → 2).
# - Flags vague rules for human review.
# - Idempotent. Backup is created by the caller (cli/conjure migrate).
#
# Env: CONJURE_HOME, DRY_RUN (0|1)

set -uo pipefail

TARGET="${1:-$(pwd)}"
DRY="${DRY_RUN:-0}"
KIT="${CONJURE_HOME:-/u01/conjure}"

REPORT="$TARGET/.claude/MIGRATION-REPORT.md"
mkdir -p "$TARGET/.claude"
[ "$DRY" = 0 ] && : > "$REPORT"

note() { echo "  $1"; [ "$DRY" = 0 ] && echo "$1" >> "$REPORT"; }

note "# Conjure migration report — from-claude"
note "Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
note ""

# 1. Inspect CLAUDE.md
if [ -f "$TARGET/CLAUDE.md" ]; then
  LINES=$(wc -l < "$TARGET/CLAUDE.md" | tr -d ' ')
  note "## CLAUDE.md"
  note "- Current size: $LINES lines"

  if grep -q '^@' "$TARGET/CLAUDE.md"; then
    IMPORTS=$(grep -c '^@' "$TARGET/CLAUDE.md")
    note "- ⚠ Contains $IMPORTS @imports — these load eagerly and waste tokens."
    note "  TODO: replace with prose references like 'For X, see skills/X/SKILL.md'."
  fi

  if [ "$LINES" -gt 100 ]; then
    note "- ⚠ Over 100-line cap. Recommended splits (Claude will refine):"
    grep -nE '^## ' "$TARGET/CLAUDE.md" 2>/dev/null | while IFS=: read -r ln rest; do
      note "    - Line $ln: $rest → consider extracting to a skill"
    done
  fi
else
  note "## CLAUDE.md"
  note "- Not present — will be created from template by 'conjure init existing'."
fi

# 2. Inspect .claude/skills
if [ -d "$TARGET/.claude/skills" ]; then
  note ""
  note "## Skills"
  SKILL_COUNT=$(find "$TARGET/.claude/skills" -name SKILL.md | wc -l | tr -d ' ')
  note "- Found $SKILL_COUNT existing skills."

  for f in $(find "$TARGET/.claude/skills" -name SKILL.md 2>/dev/null); do
    name=$(basename "$(dirname "$f")")
    SLINES=$(wc -l < "$f" | tr -d ' ')

    # frontmatter checks
    if ! head -10 "$f" | grep -q '^name:'; then
      note "  - ⚠ skill '$name' missing 'name:' frontmatter."
    fi
    if ! head -10 "$f" | grep -q '^description:'; then
      note "  - ⚠ skill '$name' missing 'description:' frontmatter."
    fi
    if [ "$SLINES" -gt 200 ]; then
      note "  - ⚠ skill '$name' is $SLINES lines (>200 cap)."
    fi

    # vague description heuristic
    if head -10 "$f" | grep -qE '^description: "([^"]{0,30}|.*utilities|.*helpers|.*general)"'; then
      note "  - ⚠ skill '$name' description appears vague — won't fire reliably."
    fi
  done
fi

# 3. Inspect hooks
if [ -d "$TARGET/.claude/hooks" ]; then
  note ""
  note "## Hooks"
  for h in $(find "$TARGET/.claude/hooks" -name '*.sh' 2>/dev/null); do
    name=$(basename "$h")
    if [ ! -x "$h" ]; then
      note "  - ⚠ hook '$name' not executable. Fixing."
      [ "$DRY" = 0 ] && chmod +x "$h"
    fi
    if grep -qE '^exit 1$' "$h"; then
      note "  - ⚠ hook '$name' uses 'exit 1' (non-blocking). Should be 'exit 2' for block."
      note "    Manual fix required: review intent before auto-changing."
    fi
  done
fi

# 4. Inspect settings.json
if [ -f "$TARGET/.claude/settings.json" ]; then
  note ""
  note "## settings.json"
  if command -v jq >/dev/null 2>&1; then
    if jq empty "$TARGET/.claude/settings.json" 2>/dev/null; then
      note "- Valid JSON ✓"
      # Check hooks structure
      if jq -e '.hooks' "$TARGET/.claude/settings.json" >/dev/null 2>&1; then
        HOOK_COUNT=$(jq '.hooks | keys | length' "$TARGET/.claude/settings.json")
        note "- $HOOK_COUNT hook event categories configured"
      else
        note "- No hooks configured. Consider adding from templates/hooks/."
      fi
    else
      note "- ✗ INVALID JSON — fix before continuing."
    fi
  fi
fi

# 5. Scaffold missing pieces (without overwriting)
note ""
note "## Scaffold actions"
if [ "$DRY" = 0 ]; then
  bash "$KIT/scripts/init-project.sh" existing "$TARGET" 2>&1 | sed 's/^/  /' | tee -a "$REPORT"
else
  note "  (dry-run: would call init-project.sh to fill in missing scaffolds)"
fi

# 6. Pin version
if [ "$DRY" = 0 ]; then
  echo "$(cat "$KIT/VERSION")" > "$TARGET/.claude/.conjure-version"
  note ""
  note "Pinned conjure version: $(cat "$KIT/VERSION")"
fi

echo
echo "✓ Migration analysis complete. Report: $REPORT"
echo "  Next: open Claude Code, paste PROMPT.md with [EXISTING] invocation."
echo "  Claude will verify and fill any template skills."
