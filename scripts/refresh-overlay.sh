#!/usr/bin/env bash
# refresh-overlay.sh — Re-pull org overlay and re-apply to .claude/.
# Reads marker .claude/.conjure-org-overlay, backs up, reclones, re-applies.
#
# Usage:
#   bash scripts/refresh-overlay.sh [target-dir]
#   CONJURE_HOME=... DRY_RUN=1 bash scripts/refresh-overlay.sh [target]
#
# Exit codes:
#   0 = success
#   1 = user-fixable error (no marker configured, clone failure)
#   2 = hard prerequisite failure (git not installed, lib/mutate.sh missing)

set -euo pipefail

CONJURE_HOME="$(cd "$(dirname "$0")/.." && pwd)"

if [ ! -f "$CONJURE_HOME/lib/mutate.sh" ]; then
  echo "✗ lib/mutate.sh not found — check CONJURE_HOME ($CONJURE_HOME)" >&2
  exit 2
fi
source "$CONJURE_HOME/lib/mutate.sh"

DRY_RUN="${DRY_RUN:-0}"
TARGET="${1:-$(pwd)}"

# Prerequisite checks
if ! command -v git >/dev/null 2>&1; then
  echo "✗ git not installed" >&2
  exit 2
fi

# Marker-not-found guard (D-04: exit 1, not 2)
OVERLAY_MARKER="$TARGET/.claude/.conjure-org-overlay"
if [ ! -f "$OVERLAY_MARKER" ]; then
  echo "✗ No org overlay configured. Run conjure init --overlay <git-url> first." >&2
  exit 1
fi

OVERLAY_URL="$(grep '^url=' "$OVERLAY_MARKER" | cut -d= -f2-)"

# Mask URL if it contains an embedded user@ prefix (e.g., https://user@host/repo)
DISPLAY_URL="$(printf '%s' "$OVERLAY_URL" | sed 's|//[^@]*@|//***@|')"

# Backup-before-mutate (Pitfall 5): skip backup in dry-run mode
if [ "${DRY_RUN:-0}" = "0" ]; then
  if [ -d "$TARGET/.claude" ]; then
    ts="$(date +%Y%m%d-%H%M%S)"
    backup="$TARGET/.claude.backup-${ts}"
    echo "▸ Backing up existing .claude/ → $backup"
    cp -R "$TARGET/.claude" "$backup" \
      || { echo "✗ Backup failed — aborting" >&2; exit 1; }
  fi
fi

CLONE_TMP="$(mktemp -d)"
trap 'rm -rf "$CLONE_TMP"' EXIT
echo "▸ Re-cloning overlay: $DISPLAY_URL"

git clone --depth 1 -- "$OVERLAY_URL" "$CLONE_TMP" 2>/dev/null \
  || { echo "✗ git clone failed for: $DISPLAY_URL" >&2; exit 1; }

NEW_SHA="$(git -C "$CLONE_TMP" rev-parse HEAD)"

# Copy overlay files — process substitution avoids subshell (preserves mutation counter)
# find -mindepth 1 -maxdepth 1 ! -name '.git' excludes .git from the clone (D-07, Pitfall 1)
while IFS= read -r item; do
  mutate_cp "$item" "$TARGET/.claude/"
done < <(find "$CLONE_TMP" -mindepth 1 -maxdepth 1 ! -name '.git')

# Write marker AFTER successful copy (Pitfall 4: never write marker before clone succeeds)
mutate_write "$TARGET/.claude/.conjure-org-overlay" \
  "$(printf 'url=%s\nsha=%s' "$OVERLAY_URL" "$NEW_SHA")"

echo "▸ Overlay refreshed from: $DISPLAY_URL"

mutate_summary
exit 0
