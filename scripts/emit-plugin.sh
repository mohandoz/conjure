#!/usr/bin/env bash
# emit-plugin.sh — Worker script for conjure publish-plugin.
# Emits .claude-plugin/plugin.json + optional marketplace.json from the target
# repo's .claude/ harness. Called by cli/conjure cmd_publish_plugin.
#
# Usage: bash scripts/emit-plugin.sh [options]
# Options: --path <dir>  --marketplace  --enable  --validate  --dry-run
# Exit codes: 0 = success; 2 = hard failure (missing dep, reserved name, secret, invalid schema)
#
# shellcheck shell=bash

set -euo pipefail

CONJURE_HOME="$(cd "$(dirname "$0")/.." && pwd)"
source "$CONJURE_HOME/lib/mutate.sh"
source "$CONJURE_HOME/lib/plugin-helpers.sh"

# Env defaults — cli/conjure sets these; script also accepts CLI flags for direct invocation
DRY_RUN="${DRY_RUN:-0}"
TARGET="${CONJURE_PLUGIN_PATH:-$(pwd)}"
DO_MARKETPLACE="${CONJURE_PLUGIN_MARKETPLACE:-0}"
DO_ENABLE="${CONJURE_PLUGIN_ENABLE:-0}"
DO_VALIDATE="${CONJURE_PLUGIN_VALIDATE:-0}"
MKT_NAME="${CONJURE_PLUGIN_MKT_NAME:-}"

# Arg parsing
while [ $# -gt 0 ]; do
  case "$1" in
    --path)       shift; TARGET="${1:-}" ;;
    --path=*)     TARGET="${1#--path=}" ;;
    --marketplace) DO_MARKETPLACE=1 ;;
    --enable)     DO_ENABLE=1 ;;
    --validate)   DO_VALIDATE=1 ;;
    --dry-run)    DRY_RUN=1 ;;
    -h|--help)
      echo "Usage: conjure publish-plugin [--path <dir>] [--marketplace] [--enable] [--validate] [--dry-run]"
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 2
      ;;
  esac
  shift
done

# jq/git preflight
if ! command -v jq >/dev/null 2>&1; then
  echo "✗ jq not installed" >&2
  exit 2
fi

if ! command -v git >/dev/null 2>&1; then
  echo "✗ git not installed" >&2
  exit 2
fi

# Prerequisite check: .claude/ directory absent
if [ ! -d "$TARGET/.claude" ]; then
  echo "✗ .claude/ not found in $TARGET — run: conjure init" >&2
  exit 2
fi

# D-06: target-repo emit warns on dirty tree; does NOT exit 2.
# CONTRAST: scripts/publish-plugin.sh (self-publish) exits 2 on dirty tree — intentional asymmetry.
if command -v git >/dev/null 2>&1; then
  if ! git -C "$TARGET" diff --quiet 2>/dev/null || ! git -C "$TARGET" diff --cached --quiet 2>/dev/null; then
    echo "WARN: working tree has uncommitted changes — sha may not reflect emitted contents" >&2
  fi
fi

# Version resolution: .conjure-version → git SHA → 0.0.0
RESOLVED_VERSION="$(resolve_version "$TARGET")"

# Plugin.json build
PLUGIN_JSON="$(plugin_build_plugin_json "$TARGET" "$RESOLVED_VERSION")" || exit 2

# Secret scan before write (D-08)
secret_scan "$PLUGIN_JSON" "plugin.json" || exit 2

# Bundled schema validation before write (D-09)
validate_plugin_json "$PLUGIN_JSON" || exit 2

# Write plugin.json
mutate_mkdir "$TARGET/.claude-plugin"
mutate_write "$TARGET/.claude-plugin/plugin.json" "$PLUGIN_JSON"

# --marketplace path: implemented in Phase 25 Plan 02
# DO_MARKETPLACE and DO_ENABLE variables are parsed and stored but the marketplace
# emit block is a stub that prevents unknown-argument errors during Wave 1 tests.
if [ "$DO_MARKETPLACE" = "1" ]; then
  # --marketplace path implemented in Phase 25 Plan 02
  # Stub: prevent unknown-argument error when flag is passed during Wave 1 tests
  echo "WARN: --marketplace emit not yet implemented (Phase 25 Plan 02)" >&2
fi

# --validate: run_cli_validate (exits 2 if claude absent per D-10)
if [ "$DO_VALIDATE" = "1" ]; then
  run_cli_validate "$TARGET"
fi

# Success report (D-04): print files written + copy-pasteable verification commands
echo "▸ conjure publish-plugin: files written"
echo "  ✓ .claude-plugin/plugin.json"
echo ""
echo "▸ To verify the plugin loads:"
echo "  claude plugin validate ."
echo "  claude plugin list"

mutate_summary
exit 0
