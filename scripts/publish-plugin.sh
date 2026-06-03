#!/usr/bin/env bash
# publish-plugin.sh — Worker script for conjure publish.
# Updates .claude-plugin/marketplace.json and plugin.json with HEAD SHA and current version.
# Optionally writes .claude-plugin/submit-entry.json (--submit flag).
#
# Usage:
#   bash scripts/publish-plugin.sh [--submit] [--dry-run]
#   CONJURE_SUBMIT=1 DRY_RUN=1 bash scripts/publish-plugin.sh
#
# Exit codes:
#   0 = success
#   1 = validation error (bad arg, JSON parse failure, missing file)
#   2 = hard prerequisite failure (dirty tree, missing dep, missing VERSION)

set -euo pipefail

CONJURE_HOME="$(cd "$(dirname "$0")/.." && pwd)"
source "$CONJURE_HOME/lib/mutate.sh"
source "$CONJURE_HOME/lib/plugin-helpers.sh"   # shared jq transforms + guards

# Env defaults — both env var and flag paths work
DRY_RUN="${DRY_RUN:-0}"
CONJURE_SUBMIT="${CONJURE_SUBMIT:-0}"

# Arg parsing
while [ $# -gt 0 ]; do
  case "$1" in
    --submit)    CONJURE_SUBMIT=1 ;;
    --dry-run)   DRY_RUN=1 ;;
    -h|--help)
      echo "Usage: conjure publish [--submit] [--dry-run]"
      echo ""
      echo "  --submit    Also write .claude-plugin/submit-entry.json and print checklist"
      echo "  --dry-run   Print mutations without writing files"
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
  shift
done

# Prerequisite checks
if ! command -v jq >/dev/null 2>&1; then
  echo "✗ jq not installed" >&2
  exit 2
fi

if ! command -v git >/dev/null 2>&1; then
  echo "✗ git not installed" >&2
  exit 2
fi

PLUGIN_DIR="$CONJURE_HOME/.claude-plugin"

if [ ! -f "$PLUGIN_DIR/marketplace.json" ]; then
  echo "✗ $PLUGIN_DIR/marketplace.json not found" >&2
  exit 2
fi

# Dirty-tree abort (exit 2 — hard prerequisite failure, not validation error)
if ! git -C "$CONJURE_HOME" diff --quiet || ! git -C "$CONJURE_HOME" diff --cached --quiet; then
  echo "✗ Working tree has uncommitted changes — commit or stash before publishing." >&2
  exit 2
fi

# Version + SHA reads
CURRENT_VERSION="$(cat "$CONJURE_HOME/VERSION" 2>/dev/null || echo unknown)"
[ "$CURRENT_VERSION" = "unknown" ] && { echo "✗ VERSION file missing" >&2; exit 2; }
CURRENT_SHA="$(git -C "$CONJURE_HOME" rev-parse HEAD)"

# Pre-write jq validation
if ! jq empty "$PLUGIN_DIR/marketplace.json" 2>/dev/null; then
  echo "✗ $PLUGIN_DIR/marketplace.json is not valid JSON — fix before publishing." >&2
  exit 1
fi

if ! jq empty "$PLUGIN_DIR/plugin.json" 2>/dev/null; then
  echo "✗ $PLUGIN_DIR/plugin.json is not valid JSON — fix before publishing." >&2
  exit 1
fi

# Build updated JSON in variables
NEW_MKT="$(jq --arg sha "$CURRENT_SHA" --arg ver "$CURRENT_VERSION" \
  '.plugins[0].source.sha = $sha | .plugins[0].version = $ver' \
  "$PLUGIN_DIR/marketplace.json")"

printf '%s' "$NEW_MKT" | jq empty 2>/dev/null || {
  echo "✗ jq produced invalid JSON for marketplace.json" >&2
  exit 1
}

NEW_PLG="$(jq --arg ver "$CURRENT_VERSION" \
  '.version = $ver' \
  "$PLUGIN_DIR/plugin.json")"

printf '%s' "$NEW_PLG" | jq empty 2>/dev/null || {
  echo "✗ jq produced invalid JSON for plugin.json" >&2
  exit 1
}

# Write via mutate_write
echo "▸ conjure publish: updating marketplace.json (version=$CURRENT_VERSION sha=${CURRENT_SHA:0:12}...)"
mutate_write "$PLUGIN_DIR/marketplace.json" "$NEW_MKT"
echo "✓ marketplace.json updated"
mutate_write "$PLUGIN_DIR/plugin.json" "$NEW_PLG"
echo "✓ plugin.json updated"

# Submit path
if [ "$CONJURE_SUBMIT" = "1" ]; then
  SUBMIT_JSON="$(jq -n \
    --arg sha "$CURRENT_SHA" \
    --arg ver "$CURRENT_VERSION" \
    '{
      "name": "conjure",
      "description": "Production-grade init kit for Claude Code. Lazy-loaded skills, deterministic hooks, isolated subagents, knowledge graph, stack profiles, compliance overlays, safe migration.",
      "source": {
        "source": "github",
        "repo": "mohandoz/conjure",
        "ref": "main",
        "sha": $sha
      },
      "version": $ver,
      "homepage": "https://github.com/mohandoz/conjure",
      "category": "developer-tools"
    }')"

  printf '%s' "$SUBMIT_JSON" | jq empty 2>/dev/null || {
    echo "✗ jq produced invalid JSON for submit-entry.json" >&2
    exit 1
  }

  mutate_write "$PLUGIN_DIR/submit-entry.json" "$SUBMIT_JSON"
  echo "✓ submit-entry.json written"

  echo ""
  echo "▸ conjure publish --submit checklist:"
  echo "  [ ] Run: claude plugin validate . && claude plugin validate .claude-plugin/plugin.json"
  echo "  [ ] Commit marketplace.json, plugin.json, and submit-entry.json"
  echo "  [ ] Push branch and create a release tag"
  echo "  [ ] Re-run 'conjure publish' after tagging to update SHA to tag commit"
  echo "  [ ] Visit: https://claude.ai/settings/plugins/submit"
  echo "  [ ] Paste the contents of .claude-plugin/submit-entry.json into the submission form"
  echo "  NOTE: Direct PRs to anthropics/claude-plugins-community are auto-closed."
  echo "        Use the web form at the URL above."
fi

mutate_summary
exit 0
