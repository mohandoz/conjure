#!/usr/bin/env bash
# emit-policy.sh — Worker script for conjure emit-policy.
# Emits sandbox block into .claude/settings.json + managed-settings.json (Wave 2) +
# MDM artifacts (Wave 2) + VERIFY.txt to --output DIR.
# Called by cli/conjure cmd_emit_policy.
#
# Usage: bash scripts/emit-policy.sh [options]
# Options: --regime hipaa|soc2|gdpr|pci  --output DIR  --managed-only  --mdm-only  --dry-run
# Exit codes: 0 = success; 2 = hard failure
#
# shellcheck shell=bash

set -euo pipefail

CONJURE_HOME="$(cd "$(dirname "$0")/.." && pwd)"
source "$CONJURE_HOME/lib/log.sh"
source "$CONJURE_HOME/lib/snapshot.sh"
source "$CONJURE_HOME/lib/mutate.sh"
source "$CONJURE_HOME/lib/policy-helpers.sh"

# Env defaults — cli/conjure sets these; script also accepts CLI flags for direct invocation
DRY_RUN="${DRY_RUN:-0}"
TARGET="${CONJURE_POLICY_TARGET:-}"
REGIME="${CONJURE_POLICY_REGIME:-}"
OUTPUT_DIR="${CONJURE_POLICY_OUTPUT:-}"
MANAGED_ONLY="${CONJURE_POLICY_MANAGED_ONLY:-0}"
MDM_ONLY="${CONJURE_POLICY_MDM_ONLY:-0}"

# Arg parsing
while [ $# -gt 0 ]; do
  case "$1" in
    --regime)       shift; REGIME="${1:-}" ;;
    --regime=*)     REGIME="${1#--regime=}" ;;
    --output)       shift; OUTPUT_DIR="${1:-}" ;;
    --output=*)     OUTPUT_DIR="${1#--output=}" ;;
    --path)         shift; TARGET="${1:-}" ;;
    --path=*)       TARGET="${1#--path=}" ;;
    --managed-only) MANAGED_ONLY=1 ;;
    --mdm-only)     MDM_ONLY=1 ;;
    --dry-run)      DRY_RUN=1 ;;
    -h|--help)
      echo "Usage: conjure emit-policy --regime hipaa|soc2|gdpr|pci [--output DIR] [--managed-only|--mdm-only] [--dry-run]"
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 2
      ;;
  esac
  shift
done

# Regime validation (T-26-03: enum guard before any source call)
if [ -z "$REGIME" ]; then
  echo "✗ --regime is required. Usage: conjure emit-policy --regime hipaa|soc2|gdpr|pci" >&2
  exit 2
fi
case "$REGIME" in
  hipaa|soc2|gdpr|pci) ;;
  *) echo "✗ Unsupported regime: $REGIME. Must be one of: hipaa, soc2, gdpr, pci" >&2; exit 2 ;;
esac

# TARGET resolution: explicit > env > parent(output_dir) > pwd
if [ -z "$TARGET" ]; then
  if [ -n "$OUTPUT_DIR" ]; then
    # Derive target from output dir parent so callers can pass --output $DIR/conjure-policy
    # and have .claude/settings.json written in $DIR
    TARGET="$(dirname "$OUTPUT_DIR")"
  else
    TARGET="$(pwd)"
  fi
fi

# Output dir default
if [ -z "$OUTPUT_DIR" ]; then
  OUTPUT_DIR="$TARGET/conjure-policy"
fi

# jq preflight
if ! command -v jq >/dev/null 2>&1; then
  echo "✗ jq not installed" >&2
  exit 2
fi

# Source regime data (REGIME already validated against enum — no path injection risk)
# shellcheck disable=SC1090
source "$CONJURE_HOME/compliance/$REGIME/policy.sh"

# Shared baseline deny paths (all regimes)
BASELINE_DENY_READ="
~/.aws
~/.aws/credentials
~/.ssh
~/.gnupg
~/.config/gcloud
.env
**/.env
**/.env.*
**/secrets
**/credentials
**/*.pem
**/*.key
**/*.p12
**/*.pfx
"

BASELINE_DENY_WRITE="
~/.ssh
~/.gnupg
~/.aws
"

# Build combined deny arrays (baseline + regime delta), deduplicated
# Convert POSIX newline-strings to JSON arrays via jq
COMBINED_DENY_READ="$(printf '%s\n%s\n' "$BASELINE_DENY_READ" "$REGIME_DENY_READ" \
  | sort -u \
  | jq -R . | jq -sc '[.[] | select(length > 0)]')"

COMBINED_DENY_WRITE="$(printf '%s\n%s\n' "$BASELINE_DENY_WRITE" "$REGIME_DENY_WRITE" \
  | sort -u \
  | jq -R . | jq -sc '[.[] | select(length > 0)]')"

# Build sandbox block
SANDBOX_JSON="$(build_sandbox_block "$COMBINED_DENY_READ" "$COMBINED_DENY_WRITE")"

# Validate before write (T-26-emit: validate-before-write discipline)
validate_sandbox_json "$SANDBOX_JSON" || exit 2

# Secret scan (T-26-04: credential pattern scan)
secret_scan "$SANDBOX_JSON" "sandbox block" || exit 2

# Snapshot before mutate (backup-before-mutate invariant)
if [ "${DRY_RUN:-0}" != "1" ] && [ -f "$TARGET/.claude/settings.json" ]; then
  snapshot_create "$TARGET" "$TARGET/.conjure-adopt-backups"
  echo "▸ backup created: $CONJURE_SNAPSHOT_PATH"
fi

# Merge sandbox block into .claude/settings.json (only when MDM_ONLY != 1)
if [ "${MDM_ONLY:-0}" != "1" ]; then
  # Ensure .claude/ directory exists
  mutate_mkdir "$TARGET/.claude"

  # Merge sandbox block (idempotent array_merge)
  merge_sandbox_block "$TARGET/.claude/settings.json" "$SANDBOX_JSON"

  # Mirror denyRead paths into permissions.deny (POL-02 enforcement gap closure)
  merge_deny_read_permissions "$TARGET/.claude/settings.json" "$COMBINED_DENY_READ"
fi

# Build Read() deny entries JSON array from combined denyRead paths (for managed-settings + plist)
# Filter empties so an empty deny list yields [] — NOT [""] (WR-01).
DENY_ENTRIES_JSON="$(build_deny_read_entries "$COMBINED_DENY_READ" \
  | jq -R . | jq -sc '[.[] | select(length > 0)]')"

# Build managed-settings JSON — always needed (used for managed-settings.json file and ps1 heredoc)
MANAGED_JSON="$(build_managed_settings "$REGIME" "$DENY_ENTRIES_JSON" "$SANDBOX_JSON")"

# Secret scan on managed-settings content before any write (T-26-11)
secret_scan "$MANAGED_JSON" "managed-settings.json" || exit 2

# Type-safety gate: validate disableBypassPermissionsMode is STRING "disable" (T-26-07)
validate_managed_settings_json "$MANAGED_JSON" || exit 2

# Emit managed-settings.json (skip when MDM_ONLY)
if [ "${MDM_ONLY:-0}" != "1" ]; then
  mutate_mkdir "$OUTPUT_DIR"
  mutate_write "$OUTPUT_DIR/managed-settings.json" "$MANAGED_JSON"
fi

# Emit macOS plist (skip when MANAGED_ONLY)
if [ "${MANAGED_ONLY:-0}" != "1" ]; then
  PLIST_XML="$(build_plist_xml "$COMBINED_DENY_READ" "$DENY_ENTRIES_JSON" "$SANDBOX_JSON")"
  [ -z "$PLIST_XML" ] && { echo "✗ build_plist_xml produced empty output" >&2; exit 2; }
  mutate_mkdir "$OUTPUT_DIR"
  mutate_write "$OUTPUT_DIR/com.anthropic.claudecode.plist" "$PLIST_XML"

  # Emit Windows ps1 (skip when MANAGED_ONLY)
  PS1_CONTENT="$(build_ps1_script "$REGIME" "$MANAGED_JSON")"
  [ -z "$PS1_CONTENT" ] && { echo "✗ build_ps1_script produced empty output" >&2; exit 2; }
  mutate_mkdir "$OUTPUT_DIR"
  mutate_write "$OUTPUT_DIR/Set-ClaudeCodePolicy.ps1" "$PS1_CONTENT"
fi

# Emit VERIFY.txt with testable verification assertions (per RESEARCH.md Code Examples)
VERIFY_CONTENT="$(printf '%s\n' \
  "=== conjure emit-policy ($REGIME) — Verification ===" \
  "" \
  "1. Sandbox enabled in project settings:" \
  "   jq '.sandbox.enabled' .claude/settings.json   # must return: true" \
  "" \
  "2. disableBypassPermissionsMode type and value:" \
  "   jq '.permissions.disableBypassPermissionsMode | [type, .]' .claude/settings.json" \
  "   # must return: [\"string\",\"disable\"]" \
  "" \
  "3. Managed settings active (after deploying conjure-policy/managed-settings.json):" \
  "   claude /status   # look for 'Enterprise managed settings (file)' in Setting sources" \
  "" \
  "4. denyRead paths mirrored in permissions.deny:" \
  "   jq '[.sandbox.filesystem.denyRead // [], .permissions.deny // []]' .claude/settings.json" \
  "" \
  "5. Unreviewed template check (must be false before deploying):" \
  "   grep -c REPLACE_WITH_ORG_UUID conjure-policy/managed-settings.json" \
  "   # must return 0 AFTER you replace forceLoginOrgUUID with your org UUID —" \
  "   # a freshly emitted file intentionally returns 1." \
  "" \
  "Compliance disclaimer: this configuration reduces non-compliant output risks" \
  "but does NOT make your project compliant. Engage your compliance officer.")"

mutate_mkdir "$OUTPUT_DIR"
printf '%s\n' "$VERIFY_CONTENT"
mutate_write "$OUTPUT_DIR/VERIFY.txt" "$VERIFY_CONTENT"

# Success report
echo "▸ conjure emit-policy ($REGIME): files written"
if [ "${MDM_ONLY:-0}" != "1" ]; then
  echo "  ✓ .claude/settings.json (sandbox block merged)"
  echo "  ✓ $OUTPUT_DIR/managed-settings.json"
fi
if [ "${MANAGED_ONLY:-0}" != "1" ]; then
  echo "  ✓ $OUTPUT_DIR/com.anthropic.claudecode.plist"
  echo "  ✓ $OUTPUT_DIR/Set-ClaudeCodePolicy.ps1"
fi
echo "  ✓ $OUTPUT_DIR/VERIFY.txt"
echo ""
echo "▸ See $OUTPUT_DIR/VERIFY.txt for testable verification commands."
mutate_summary
exit 0
