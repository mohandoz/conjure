#!/usr/bin/env bash
# init-overlay.sh — Worker script for conjure init --overlay.
# Clones overlay repo (shallow), copies contents into .claude/, writes marker.
#
# Usage:
#   bash scripts/init-overlay.sh <overlay-url> <target-dir>
#   CONJURE_HOME=... DRY_RUN=1 bash scripts/init-overlay.sh <url> <target>
#
# Exit codes:
#   0 = success
#   1 = validation error (empty URL, clone failure)
#   2 = hard prerequisite failure (git not installed, lib/mutate.sh missing)

set -euo pipefail

CONJURE_HOME="$(cd "$(dirname "$0")/.." && pwd)"
source "$CONJURE_HOME/lib/mutate.sh"

DRY_RUN="${DRY_RUN:-0}"

# Positional args
OVERLAY_URL="${1:-}"
TARGET="${2:-$(pwd)}"

[ -z "$OVERLAY_URL" ] && { echo "✗ Usage: init-overlay.sh <overlay-url> <target>" >&2; exit 1; }

# Prerequisite checks
if ! command -v git >/dev/null 2>&1; then
  echo "✗ git not installed" >&2
  exit 2
fi

if [ ! -f "$CONJURE_HOME/lib/mutate.sh" ]; then
  echo "✗ lib/mutate.sh not found — check CONJURE_HOME ($CONJURE_HOME)" >&2
  exit 2
fi

# Mask URL if it contains an embedded user@ prefix (e.g., https://user@host/repo)
DISPLAY_URL="$(printf '%s' "$OVERLAY_URL" | sed 's|//[^@]*@|//***@|')"

echo "▸ Cloning overlay: $DISPLAY_URL"

CLONE_TMP="$(mktemp -d)"

git clone --depth 1 "$OVERLAY_URL" "$CLONE_TMP" 2>/dev/null \
  || { echo "✗ git clone failed for: $DISPLAY_URL" >&2; rm -rf "$CLONE_TMP"; exit 1; }

CLONE_SHA="$(git -C "$CLONE_TMP" rev-parse HEAD)"

# Copy overlay files — process substitution avoids subshell (preserves mutation counter)
# find -mindepth 1 -maxdepth 1 ! -name '.git' excludes .git from the clone (D-07, Pitfall 1)
while IFS= read -r item; do
  mutate_cp "$item" "$TARGET/.claude/"
done < <(find "$CLONE_TMP" -mindepth 1 -maxdepth 1 ! -name '.git')

rm -rf "$CLONE_TMP"

# Write marker AFTER successful copy (Pitfall 4: never write marker before clone succeeds)
mutate_write "$TARGET/.claude/.conjure-org-overlay" \
  "$(printf 'url=%s\nsha=%s' "$OVERLAY_URL" "$CLONE_SHA")"

echo "▸ Overlay applied from: $DISPLAY_URL"

mutate_summary
exit 0
