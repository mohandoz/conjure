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
source "$CONJURE_HOME/lib/log.sh"        # snapshot.sh log_step integration
source "$CONJURE_HOME/lib/snapshot.sh"   # backup-before-mutate (CLAUDE.md safety invariant)
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

# Backup-before-mutate (CLAUDE.md safety invariant): snapshot the target before the
# first write that can overwrite pre-existing manifests / settings. Live mode only —
# snapshot_create no-ops the copy under DRY_RUN=1. Skipped when nothing would be
# overwritten (clean emit into a repo with no prior plugin.json/marketplace.json/settings).
if [ "${DRY_RUN:-0}" != "1" ] && { [ -f "$TARGET/.claude-plugin/plugin.json" ] || \
   [ -f "$TARGET/.claude-plugin/marketplace.json" ] || \
   [ -f "$TARGET/.claude/settings.json" ]; }; then
  snapshot_create "$TARGET" "$TARGET/.conjure-adopt-backups"
  echo "▸ backup created: $CONJURE_SNAPSHOT_PATH"
fi

# Write plugin.json
mutate_mkdir "$TARGET/.claude-plugin"
mutate_write "$TARGET/.claude-plugin/plugin.json" "$PLUGIN_JSON"

# --marketplace path (D-13: only when --marketplace is passed)
if [ "$DO_MARKETPLACE" = "1" ]; then
  # Step 1: Derive marketplace name
  if [ -z "$MKT_NAME" ]; then
    # Attempt auto-detect from git remote
    OWNER_REPO="$(detect_github_source "$TARGET" 2>/dev/null)" || OWNER_REPO=""
    if [ -n "$OWNER_REPO" ]; then
      # Derive from repo basename: lowercase, replace _ and . with -, strip other non-alphanum
      MKT_NAME="$(basename "$OWNER_REPO" | tr '[:upper:]' '[:lower:]' | tr '_.' '-' | tr -cd 'a-z0-9-')"
    else
      # Fallback: use basename of TARGET directory, kebab-cased
      MKT_NAME="$(basename "$TARGET" | tr '[:upper:]' '[:lower:]' | tr '_.' '-' | tr -cd 'a-z0-9-')"
    fi
  fi
  # Validate kebab-case — aligned with marketplace.schema.json `name` pattern
  # (^[a-z][a-z0-9-]{0,63}$): leading LETTER only, max 64 chars. Rejecting here
  # avoids writing a manifest that passes the emitter but fails schema validation
  # downstream (WR-01).
  # shellcheck disable=SC2016
  if ! printf '%s' "$MKT_NAME" | grep -qE '^[a-z][a-z0-9-]{0,63}$'; then
    echo "✗ Marketplace name '$MKT_NAME' must start with a letter and be ≤64 chars (a-z, 0-9, hyphens)" >&2
    exit 2
  fi

  # Step 2: Reserved-name guard (D-07, PLUG-02) — BEFORE any writes
  reserved_name_check "$MKT_NAME" || exit 2

  # Step 3: Derive owner name
  OWNER_REPO="${OWNER_REPO:-$(detect_github_source "$TARGET" 2>/dev/null || echo "")}"
  OWNER_NAME="$(git -C "$TARGET" config user.name 2>/dev/null || echo "")"
  if [ -z "$OWNER_NAME" ] && [ -n "$OWNER_REPO" ]; then
    OWNER_NAME="$(dirname "$OWNER_REPO" | tr '/' '\n' | tail -1)"
  fi
  OWNER_NAME="${OWNER_NAME:-unknown}"

  # Step 4: Build marketplace JSON
  MKT_JSON="$(plugin_build_marketplace_json "$TARGET" "$MKT_NAME" "$RESOLVED_VERSION" "$OWNER_NAME")" || exit 2

  # Step 5: Security gates (D-08) — scan full manifest before ANY write
  secret_scan "$MKT_JSON" "marketplace.json" || exit 2
  validate_marketplace_json "$MKT_JSON" || exit 2

  # Step 6: Write marketplace.json
  mutate_write "$TARGET/.claude-plugin/marketplace.json" "$MKT_JSON"

  # Step 7: Settings.json wiring (D-13, D-14, D-15)
  # Extract source object from marketplace.json plugins[0].source for the wire
  SOURCE_OBJ="$(printf '%s' "$MKT_JSON" | jq -c '.plugins[0].source')"
  PLUGIN_KEY="${MKT_NAME}@${MKT_NAME}"
  plugin_wire_settings "$TARGET/.claude/settings.json" "$MKT_NAME" "$SOURCE_OBJ" "$PLUGIN_KEY" "$DO_ENABLE"
fi

# --validate: run_cli_validate (exits 2 if claude absent per D-10)
if [ "$DO_VALIDATE" = "1" ]; then
  run_cli_validate "$TARGET"
fi

# Success report (D-04): print files written + copy-pasteable verification commands
echo "▸ conjure publish-plugin: files written"
echo "  ✓ .claude-plugin/plugin.json"
if [ "$DO_MARKETPLACE" = "1" ]; then
  echo "  ✓ .claude-plugin/marketplace.json"
  if [ "$DO_ENABLE" = "1" ]; then
    echo "  ✓ .claude/settings.json (enabledPlugins)"
  else
    echo "  ✓ .claude/settings.json (extraKnownMarketplaces — use --enable to activate)"
  fi
fi
echo ""
echo "▸ To verify the plugin loads:"
echo "  claude plugin validate ."
echo "  claude plugin list"

mutate_summary
exit 0
