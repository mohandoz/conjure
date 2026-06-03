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

# Create output directory
mutate_mkdir "$OUTPUT_DIR"

# Emit VERIFY.txt with testable verification assertions
VERIFY_CONTENT="$(printf '%s\n' \
  "=== conjure emit-policy ($REGIME) — Verification ===" \
  "" \
  "1. Sandbox enabled in project settings:" \
  "   jq '.sandbox.enabled' .claude/settings.json   # must return: true" \
  "" \
  "2. denyRead paths present:" \
  "   jq '.sandbox.filesystem.denyRead | length' .claude/settings.json   # must be > 0" \
  "" \
  "3. permissions.deny Read() entries present:" \
  "   jq '.permissions.deny | length' .claude/settings.json   # must be > 0" \
  "" \
  "4. denyRead paths mirrored in permissions.deny:" \
  "   jq '[.sandbox.filesystem.denyRead // [], .permissions.deny // []]' .claude/settings.json" \
  "" \
  "5. Managed settings active (after deploying conjure-policy/managed-settings.json):" \
  "   claude /status   # look for 'Enterprise managed settings (file)' in Setting sources" \
  "" \
  "Compliance disclaimer: this configuration reduces non-compliant output risks" \
  "but does NOT make your project compliant. Engage your compliance officer.")"

printf '%s\n' "$VERIFY_CONTENT"
mutate_write "$OUTPUT_DIR/VERIFY.txt" "$VERIFY_CONTENT"

# Wave 2 stubs (managed-settings.json + MDM artifacts — implemented in Phase 26 Plan 02)
if [ "${MANAGED_ONLY:-0}" = "1" ] || [ "${MDM_ONLY:-0}" != "1" ]; then
  # managed-settings.json — implemented in Wave 2
  echo "  (managed-settings.json: implemented in Wave 2)" >&2
fi

# Success report
echo "▸ conjure emit-policy ($REGIME): files written"
echo "  ✓ .claude/settings.json (sandbox block merged)"
echo "  ✓ $OUTPUT_DIR/VERIFY.txt"
echo ""
echo "▸ See $OUTPUT_DIR/VERIFY.txt for testable verification commands."
mutate_summary
exit 0
