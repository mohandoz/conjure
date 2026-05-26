#!/usr/bin/env bash
# scripts/check.sh — compare installed harness against upstream kit snapshot.
# Usage: CONJURE_HOME=<path> CONJURE_PORCELAIN=<0|1> bash check.sh [target]
# Exit codes: 0 = harness is current, 1 = drift detected, 2 = bad args
# Read-only: no mutations, no lib/mutate.sh required.

set -uo pipefail

TARGET="${1:-$(pwd)}"
CONJURE_HOME="${CONJURE_HOME:-$(cd "$(dirname "$0")/.." && pwd)}"
PORCELAIN="${CONJURE_PORCELAIN:-0}"

# Validate target directory (T-17-01: prevent path traversal on invalid arg)
[ -d "$TARGET" ] || { echo "✗ target is not a directory: $TARGET" >&2; exit 2; }

# sha256_file <path> — cross-platform sha256 hash of a single file.
# D-cross-platform: sha256sum on Linux; shasum -a 256 on macOS fallback.
sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

# Build manifest (relative harness paths) into a temp file.
# bash 3.2 compatible: no declare -A, no mapfile, no local -n.
MANIFEST="$(mktemp)"
trap 'rm -f "$MANIFEST"' EXIT

# Root dotfiles (3)
printf '%s\n' ".editorconfig" ".gitattributes" ".claudeignore" >> "$MANIFEST"

# Core config (1) — harness path strips .tmpl suffix
printf '%s\n' ".claude/settings.json" >> "$MANIFEST"

# Hooks (6 — *.mjs only; README.md excluded by glob)
for hook in "$CONJURE_HOME"/templates/hooks-nodejs/*.mjs; do
  printf '%s\n' ".claude/hooks/$(basename "$hook")" >> "$MANIFEST"
done

# Skills (19 — one SKILL.md per skill directory)
for skill_dir in "$CONJURE_HOME"/templates/skills/*/; do
  printf '%s\n' ".claude/skills/$(basename "$skill_dir")/SKILL.md" >> "$MANIFEST"
done

# Agents (6)
for agent in "$CONJURE_HOME"/templates/agents/*.md; do
  printf '%s\n' ".claude/agents/$(basename "$agent")" >> "$MANIFEST"
done

# Classify kit files: modified or removed
modified="" removed="" added=""

while IFS= read -r rel; do
  # Resolve kit source file — settings.json strips .tmpl; others map directly.
  case "$rel" in
    .claude/settings.json)
      kit_file="$CONJURE_HOME/templates/settings.json.tmpl" ;;
    .claude/hooks/*)
      kit_file="$CONJURE_HOME/templates/hooks-nodejs/$(basename "$rel")" ;;
    .claude/skills/*/SKILL.md)
      skill_name="${rel#.claude/skills/}"
      skill_name="${skill_name%/SKILL.md}"
      kit_file="$CONJURE_HOME/templates/skills/$skill_name/SKILL.md" ;;
    .claude/agents/*)
      kit_file="$CONJURE_HOME/templates/agents/$(basename "$rel")" ;;
    .editorconfig|.gitattributes|.claudeignore)
      kit_file="$CONJURE_HOME/templates/$rel" ;;
    *) continue ;;
  esac

  harness_file="$TARGET/$rel"
  if [ ! -f "$harness_file" ]; then
    removed="$removed$rel\n"
  else
    kit_hash="$(sha256_file "$kit_file")"
    harness_hash="$(sha256_file "$harness_file")"
    if [ "$kit_hash" != "$harness_hash" ]; then
      modified="$modified$rel\n"
    fi
  fi
done < "$MANIFEST"

# Detect added files: in harness .claude/ but not in kit manifest.
# Skip conjure-internal state files (Pitfall 6).
while IFS= read -r harness_file; do
  rel="${harness_file#$TARGET/}"
  case "$rel" in
    .claude/.conjure-*) continue ;;
    .claude/COMPOUND-CANDIDATES.md) continue ;;
    .claude/docs/*) continue ;;
  esac
  if ! grep -qF "$rel" "$MANIFEST" 2>/dev/null; then
    added="$added$rel\n"
  fi
done < <(find "$TARGET/.claude" -type f 2>/dev/null | sort)

# Determine drift flag
drift=0
if [ -n "$modified" ] || [ -n "$removed" ] || [ -n "$added" ]; then
  drift=1
fi

# Output report
if [ "$PORCELAIN" = "1" ]; then
  # Machine-readable: one line per file, "<M|R|A> <path>", no headers
  printf '%b' "$modified" | while IFS= read -r f; do [ -n "$f" ] && printf 'M %s\n' "$f"; done
  printf '%b' "$removed"  | while IFS= read -r f; do [ -n "$f" ] && printf 'R %s\n' "$f"; done
  printf '%b' "$added"    | while IFS= read -r f; do [ -n "$f" ] && printf 'A %s\n' "$f"; done
else
  if [ "$drift" -eq 0 ]; then
    echo "Harness is current."
  else
    mod_count=$(printf '%b' "$modified" | grep -c '[^[:space:]]' || true)
    rem_count=$(printf '%b' "$removed"  | grep -c '[^[:space:]]' || true)
    add_count=$(printf '%b' "$added"    | grep -c '[^[:space:]]' || true)
    total=$((mod_count + rem_count + add_count))
    echo "Drift detected: $total file(s) differ from upstream kit"
    echo "Note: modified files may include user customizations"
    echo
    if [ -n "$modified" ]; then
      echo "Modified ($mod_count):"
      printf '%b' "$modified" | while IFS= read -r f; do [ -n "$f" ] && echo "  $f"; done
    fi
    if [ -n "$removed" ]; then
      echo "Removed ($rem_count):"
      printf '%b' "$removed" | while IFS= read -r f; do [ -n "$f" ] && echo "  $f"; done
    fi
    if [ -n "$added" ]; then
      echo "Added ($add_count):"
      printf '%b' "$added" | while IFS= read -r f; do [ -n "$f" ] && echo "  $f"; done
    fi
  fi
fi

exit "$drift"
