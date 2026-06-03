# shellcheck shell=bash
# lib/policy-helpers.sh — shared jq builders, validators, and merge logic for policy emission.
# Source this file; do not execute directly.
# Requires: lib/mutate.sh already sourced (for mutate_write, dry-run awareness).
# Requires: lib/snapshot.sh already sourced (for snapshot_create, backup-before-mutate).
# POSIX bash 3.2+. No associative arrays, no mapfile, no local -n.

# secret_scan(content, label)
# Returns 0 if no credential patterns found, 1 if a pattern matches.
# Caller must: secret_scan "$CONTENT" "managed-settings.json" || exit 2
secret_scan() {
  local content="$1"
  local label="${2:-emitted manifest}"
  # POSIX ERE: use [[:space:]], not \s. \s is a GNU/PCRE extension and matches a
  # literal 's' under BSD/macOS `grep -E` — silently defeating the credential gate
  # on the platform this project targets.
  # shellcheck disable=SC2016
  local patterns
  patterns='sk-ant-[A-Za-z0-9_-]{10,}|sk-[A-Za-z0-9_-]{32,}|AKIA[0-9A-Z]{16}|"(api_key|secret_key|private_key|access_token|auth_token)"[[:space:]]*:[[:space:]]*"[^"]{6,}"'
  if printf '%s' "$content" | grep -qiE "$patterns" 2>/dev/null; then
    echo "BLOCK: $label appears to contain a credential pattern — remove before emitting." >&2
    return 1
  fi
  return 0
}

# validate_sandbox_json(content)
# Returns 0 if content is a valid sandbox block, 1 if invalid.
# Caller must: validate_sandbox_json "$SANDBOX_JSON" || exit 2
validate_sandbox_json() {
  local content="$1"
  local errors=0

  if ! printf '%s' "$content" | jq -e '(.enabled | type) == "boolean"' >/dev/null 2>&1; then
    echo "✗ sandbox: 'enabled' must be a boolean" >&2
    errors=$((errors + 1))
  fi

  if ! printf '%s' "$content" | jq -e '(.filesystem.denyRead | type) == "array"' >/dev/null 2>&1; then
    echo "✗ sandbox: 'filesystem.denyRead' must be an array" >&2
    errors=$((errors + 1))
  fi

  if ! printf '%s' "$content" | jq -e '(.network.allowedDomains | type) == "array"' >/dev/null 2>&1; then
    echo "✗ sandbox: 'network.allowedDomains' must be an array" >&2
    errors=$((errors + 1))
  fi

  [ "$errors" -gt 0 ] && return 1
  return 0
}

# build_sandbox_block(deny_read_json, deny_write_json)
# Arguments: JSON arrays (strings). Prints sandbox object JSON to stdout.
# Caller captures: SANDBOX_JSON="$(build_sandbox_block "$DENY_READ_JSON" "$DENY_WRITE_JSON")"
build_sandbox_block() {
  local deny_read_json="$1"
  local deny_write_json="$2"

  jq -n \
    --argjson deny_read "$deny_read_json" \
    --argjson deny_write "$deny_write_json" \
    '{
      enabled: true,
      failIfUnavailable: true,
      allowUnsandboxedCommands: false,
      filesystem: {
        denyRead: $deny_read,
        denyWrite: $deny_write
      },
      network: {
        allowedDomains: []
      }
    }'
}

# build_deny_read_entries(deny_read_json)
# Argument: JSON array of denyRead paths.
# Prints one Read(<path>) entry per line to stdout.
# Path prefix convention (RESEARCH.md Pattern 2):
#   ~/path  → Read(~/path)      home-relative: keep as-is
#   /path   → Read(//path)      absolute: prepend extra / (double-slash)
#   ./path  → Read(/path)       project-relative: strip leading dot
#   bare    → Read(bare)        bare: pass through
build_deny_read_entries() {
  local deny_read_json="$1"
  printf '%s' "$deny_read_json" | jq -r '.[]' | while IFS= read -r path; do
    case "$path" in
      ~/*)  printf 'Read(%s)\n' "$path" ;;
      /*)   printf 'Read(/%s)\n' "$path" ;;
      ./*)  printf 'Read(%s)\n' "${path#.}" ;;
      *)    printf 'Read(%s)\n' "$path" ;;
    esac
  done
}

# merge_sandbox_block(settings_file, sandbox_json)
# Arguments: path to existing settings.json (or /dev/null if absent), sandbox JSON string.
# Deep-merges sandbox block into settings.json via array_merge (idempotent).
# Calls mutate_write for all settings.json writes.
# Caller must ensure lib/mutate.sh is already sourced.
merge_sandbox_block() {
  local settings_file="$1"
  local sandbox_json="$2"

  local CURRENT
  CURRENT="$(cat "$settings_file" 2>/dev/null || printf '{}')"

  # Deep-merge: preserve all existing keys; merge sandbox sub-keys.
  # def array_merge: union + unique so re-runs are idempotent and existing
  # user-added entries are preserved (RESEARCH.md Pattern 1).
  # Scalar keys (enabled, failIfUnavailable, allowUnsandboxedCommands): new value wins.
  # Array keys (denyRead, denyWrite, allowWrite, allowRead, allowedDomains,
  # excludedCommands): union + unique.
  local UPDATED
  UPDATED="$(printf '%s' "$CURRENT" | jq \
    --argjson sb "$sandbox_json" \
    '
    def array_merge(a; b): (a // []) + (b // []) | unique;

    .sandbox = (
      (.sandbox // {}) as $old |
      $sb as $new |
      $old * $new |
      .filesystem.denyRead  = array_merge($old.filesystem.denyRead;  $new.filesystem.denyRead) |
      .filesystem.denyWrite = array_merge($old.filesystem.denyWrite; $new.filesystem.denyWrite) |
      .filesystem.allowWrite = array_merge($old.filesystem.allowWrite; $new.filesystem.allowWrite) |
      .filesystem.allowRead  = array_merge($old.filesystem.allowRead;  $new.filesystem.allowRead) |
      .network.allowedDomains = array_merge($old.network.allowedDomains; $new.network.allowedDomains) |
      .excludedCommands = array_merge($old.excludedCommands; $new.excludedCommands)
    )
    ')"

  printf '%s' "$UPDATED" | jq empty 2>/dev/null || {
    echo "✗ jq produced invalid JSON for settings.json (sandbox merge)" >&2
    return 1
  }

  mutate_write "$settings_file" "$UPDATED"
}

# merge_deny_read_permissions(settings_file, deny_read_json)
# Merges Read() entries derived from deny_read_json into .permissions.deny in settings_file.
# Uses the same array_merge pattern as merge_sandbox_block for idempotency.
# Caller must ensure lib/mutate.sh is already sourced.
merge_deny_read_permissions() {
  local settings_file="$1"
  local deny_read_json="$2"

  # Build Read() entries from deny_read_json
  local read_entries
  read_entries="$(build_deny_read_entries "$deny_read_json")"

  # Convert newline-separated Read() entries to a JSON array
  local read_entries_json
  read_entries_json="$(printf '%s\n' "$read_entries" | jq -R . | jq -sc '.')"

  local CURRENT
  CURRENT="$(cat "$settings_file" 2>/dev/null || printf '{}')"

  local UPDATED
  UPDATED="$(printf '%s' "$CURRENT" | jq \
    --argjson new_entries "$read_entries_json" \
    '
    def array_merge(a; b): (a // []) + (b // []) | unique;
    .permissions = (.permissions // {}) |
    .permissions.deny = array_merge(.permissions.deny; $new_entries)
    ')"

  printf '%s' "$UPDATED" | jq empty 2>/dev/null || {
    echo "✗ jq produced invalid JSON for settings.json (permissions.deny merge)" >&2
    return 1
  }

  mutate_write "$settings_file" "$UPDATED"
}
