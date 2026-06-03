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

  # WR-04: scan the FINAL merged result before write. The operator's pre-existing
  # settings.json content ($CURRENT) is merged back into $UPDATED; scanning only the
  # generated SANDBOX_JSON upstream misses a credential already living in the
  # operator's file. Return 1 on hit so the caller's `set -e` aborts before write,
  # preserving the "secret_scan before any write" invariant for this write path.
  secret_scan "$UPDATED" "settings.json" || return 1

  mutate_write "$settings_file" "$UPDATED"
}

# merge_deny_read_permissions(settings_file, deny_read_json)
# Merges Read() entries derived from deny_read_json into .permissions.deny in settings_file.
# Uses the same array_merge pattern as merge_sandbox_block for idempotency.
# Caller must ensure lib/mutate.sh is already sourced.
merge_deny_read_permissions() {
  local settings_file="$1"
  local deny_read_json="$2"

  local CURRENT
  CURRENT="$(cat "$settings_file" 2>/dev/null || printf '{}')"

  # WR-03: mirror EVERY sandbox denyRead path — conjure-emitted AND operator-added
  # — into permissions.deny. Union the conjure deny_read_json with the existing
  # .sandbox.filesystem.denyRead already present in settings_file. emit calls
  # merge_sandbox_block FIRST (which writes operator paths into denyRead), so by
  # the time this runs CURRENT already contains operator-added paths. Without this
  # union, a hand-added denyRead path is never mirrored and `conjure audit` flags a
  # POL-02 enforcement gap that re-emit can never close ("false sense of security").
  local existing_deny_read
  existing_deny_read="$(printf '%s' "$CURRENT" | jq -c '.sandbox.filesystem.denyRead // []' 2>/dev/null || printf '[]')"

  local combined_deny_read
  combined_deny_read="$(jq -nc \
    --argjson a "$deny_read_json" \
    --argjson b "$existing_deny_read" \
    '(($a // []) + ($b // [])) | unique')"

  # Build Read() entries from the combined (conjure + operator) denyRead set
  local read_entries
  read_entries="$(build_deny_read_entries "$combined_deny_read")"

  # Convert newline-separated Read() entries to a JSON array.
  # Filter empties so an empty deny list yields [] — NOT [""] (WR-01). The naive
  # `printf '%s\n' "" | jq -R . | jq -sc .` produces [""] (one empty string),
  # planting a stray meaningless deny rule.
  local read_entries_json
  read_entries_json="$(printf '%s\n' "$read_entries" \
    | jq -R . | jq -sc '[.[] | select(length > 0)]')"

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

  # WR-04: scan the FINAL merged result before write (see merge_sandbox_block).
  secret_scan "$UPDATED" "settings.json" || return 1

  mutate_write "$settings_file" "$UPDATED"
}

# validate_managed_settings_json(content)
# Returns 0 if content is a valid managed-settings block, 1 if invalid.
# CRITICAL gate: disableBypassPermissionsMode MUST be STRING "disable", NOT boolean.
# Caller must: validate_managed_settings_json "$MANAGED_JSON" || exit 2
validate_managed_settings_json() {
  local content="$1"
  local errors=0

  # CRITICAL: disableBypassPermissionsMode must be STRING "disable", NOT boolean (T-26-07)
  # Use jq -r '... | type' to get the type as a string; separate variable for SC2155 compliance.
  local dbpm_type dbpm_val
  dbpm_type="$(printf '%s' "$content" | jq -r '.permissions.disableBypassPermissionsMode | type' 2>/dev/null)"
  dbpm_val="$(printf '%s' "$content" | jq -r '.permissions.disableBypassPermissionsMode // empty' 2>/dev/null)"
  if [ "$dbpm_type" = "boolean" ]; then
    echo "✗ managed-settings: disableBypassPermissionsMode is boolean (got: $dbpm_val) — must be string \"disable\"" >&2
    errors=$((errors + 1))
  elif [ "$dbpm_type" = "string" ] && [ "$dbpm_val" != "disable" ]; then
    echo "✗ managed-settings: disableBypassPermissionsMode is \"$dbpm_val\" — must be \"disable\"" >&2
    errors=$((errors + 1))
  fi

  # allowManagedPermissionRulesOnly must be boolean if present
  if ! printf '%s' "$content" | jq -e 'if .allowManagedPermissionRulesOnly != null then (.allowManagedPermissionRulesOnly | type) == "boolean" else true end' >/dev/null 2>&1; then
    echo "✗ managed-settings: 'allowManagedPermissionRulesOnly' must be a boolean" >&2
    errors=$((errors + 1))
  fi

  # forceLoginOrgUUID must be a string if present
  if ! printf '%s' "$content" | jq -e 'if .forceLoginOrgUUID != null then (.forceLoginOrgUUID | type) == "string" else true end' >/dev/null 2>&1; then
    echo "✗ managed-settings: 'forceLoginOrgUUID' must be a string" >&2
    errors=$((errors + 1))
  fi

  [ "$errors" -gt 0 ] && return 1
  return 0
}

# build_managed_settings(regime, deny_entries_json, sandbox_json)
# Arguments: regime string (hipaa|soc2|gdpr|pci), JSON array of Read() deny entries, sandbox JSON block.
# Prints managed-settings JSON to stdout. Caller captures.
# Note: does NOT include _conjure_regime or _conjure_unreviewed top-level keys (RESEARCH.md Q1 RESOLVED).
# The sole "unreviewed" sentinel is forceLoginOrgUUID: "REPLACE_WITH_ORG_UUID".
build_managed_settings() {
  # IN-02: keep the documented (regime, deny_entries_json, sandbox_json) contract in
  # sync with the body. regime ($1) is not embedded in the managed-settings JSON
  # (no _conjure_regime key by design — RESEARCH.md Q1), but bind it so the
  # signature and body agree and a future arg-order change cannot silently shift.
  local regime="$1"
  local deny_entries_json="$2"
  local sandbox_json="$3"
  : "$regime"  # consumed: documented arg, intentionally not embedded in output (IN-02)

  local result
  result="$(jq -n \
    --argjson deny_entries "$deny_entries_json" \
    --argjson sandbox "$sandbox_json" \
    '{
      "permissions": {
        "disableBypassPermissionsMode": "disable",
        "deny": $deny_entries
      },
      "allowManagedPermissionRulesOnly": true,
      "forceLoginOrgUUID": "REPLACE_WITH_ORG_UUID",
      "sandbox": $sandbox
    }')"

  printf '%s' "$result" | jq empty 2>/dev/null || {
    echo "✗ build_managed_settings: jq produced invalid JSON" >&2
    return 1
  }

  printf '%s' "$result"
}

# build_plist_xml(deny_read_json, deny_entries_json, sandbox_json)
# Arguments: denyRead JSON array (sandbox paths), deny_entries JSON array (Read() entries),
#            sandbox JSON block.
# Prints macOS plist XML to stdout. Caller captures.
# CRITICAL: disableBypassPermissionsMode is hardcoded as <string>disable</string> — never <true/>.
# Validates paths for XML metacharacters before embedding (T-26-10).
# Runs plutil -lint on macOS if available; skips on Linux.
build_plist_xml() {
  local deny_read_json="$1"
  local deny_entries_json="$2"
  local sandbox_json="$3"

  # Validate all denyRead paths for XML metacharacters before embedding (T-26-10)
  local path_check
  path_check="$(printf '%s' "$deny_read_json" | jq -r '.[]' 2>/dev/null)"
  while IFS= read -r chk_path; do
    case "$chk_path" in
      *'&'*|*'<'*|*'>'*)
        echo "✗ build_plist_xml: denyRead path contains XML metacharacter (&, <, >): $chk_path" >&2
        return 2
        ;;
    esac
  done <<EOF
$path_check
EOF

  # Extract sandbox sub-fields for plist rendering
  local sandbox_deny_read sandbox_deny_write sandbox_allowed_domains
  sandbox_deny_read="$(printf '%s' "$sandbox_json" | jq -r '.filesystem.denyRead // [] | .[]' 2>/dev/null)"
  sandbox_deny_write="$(printf '%s' "$sandbox_json" | jq -r '.filesystem.denyWrite // [] | .[]' 2>/dev/null)"
  sandbox_allowed_domains="$(printf '%s' "$sandbox_json" | jq -r '.network.allowedDomains // [] | .[]' 2>/dev/null)"

  # WR-05: also validate the deny_entries (Read() strings) and allowedDomains
  # values for XML metacharacters. These are embedded into <string>...</string>
  # (below) but were previously unchecked — once allowedDomains is wired up or an
  # independent deny entry is introduced, an unescaped &/</> yields malformed plist
  # XML that plutil catches on macOS but is written silently on Linux (no plutil).
  local entry_check
  entry_check="$(printf '%s' "$deny_entries_json" | jq -r '.[]' 2>/dev/null)"
  while IFS= read -r chk_entry; do
    case "$chk_entry" in
      *'&'*|*'<'*|*'>'*)
        echo "✗ build_plist_xml: deny entry contains XML metacharacter (&, <, >): $chk_entry" >&2
        return 2
        ;;
    esac
  done <<EOF
$entry_check
EOF
  while IFS= read -r chk_domain; do
    case "$chk_domain" in
      *'&'*|*'<'*|*'>'*)
        echo "✗ build_plist_xml: allowedDomains value contains XML metacharacter (&, <, >): $chk_domain" >&2
        return 2
        ;;
    esac
  done <<EOF
$sandbox_allowed_domains
EOF

  # Build deny (Read()) entries array strings for plist
  local deny_entries_plist=""
  while IFS= read -r entry; do
    [ -z "$entry" ] && continue
    deny_entries_plist="${deny_entries_plist}            <string>${entry}</string>
"
  done <<EOF
$(printf '%s' "$deny_entries_json" | jq -r '.[]' 2>/dev/null)
EOF

  # Build sandbox denyRead array strings
  local sb_deny_read_plist=""
  while IFS= read -r p; do
    [ -z "$p" ] && continue
    sb_deny_read_plist="${sb_deny_read_plist}                <string>${p}</string>
"
  done <<EOF
$sandbox_deny_read
EOF

  # Build sandbox denyWrite array strings
  local sb_deny_write_plist=""
  while IFS= read -r p; do
    [ -z "$p" ] && continue
    sb_deny_write_plist="${sb_deny_write_plist}                <string>${p}</string>
"
  done <<EOF
$sandbox_deny_write
EOF

  # Build sandbox allowedDomains array strings
  local sb_allowed_domains_plist=""
  while IFS= read -r p; do
    [ -z "$p" ] && continue
    sb_allowed_domains_plist="${sb_allowed_domains_plist}                <string>${p}</string>
"
  done <<EOF
$sandbox_allowed_domains
EOF

  # Render plist XML — disableBypassPermissionsMode is ALWAYS <string>disable</string>
  local plist_xml
  plist_xml="$(printf '%s\n' \
    '<?xml version="1.0" encoding="UTF-8"?>' \
    '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
    '<plist version="1.0">' \
    '<dict>' \
    '    <key>permissions</key>' \
    '    <dict>' \
    '        <key>disableBypassPermissionsMode</key>' \
    '        <string>disable</string>' \
    '        <key>deny</key>' \
    '        <array>')"

  if [ -n "$deny_entries_plist" ]; then
    plist_xml="${plist_xml}
${deny_entries_plist}        </array>"
  else
    plist_xml="${plist_xml}
        </array>"
  fi

  plist_xml="${plist_xml}
    </dict>
    <key>allowManagedPermissionRulesOnly</key>
    <true/>
    <key>forceLoginOrgUUID</key>
    <string>REPLACE_WITH_ORG_UUID</string>
    <key>sandbox</key>
    <dict>
        <key>enabled</key>
        <true/>
        <key>failIfUnavailable</key>
        <true/>
        <key>allowUnsandboxedCommands</key>
        <false/>
        <key>filesystem</key>
        <dict>
            <key>denyRead</key>
            <array>"

  if [ -n "$sb_deny_read_plist" ]; then
    plist_xml="${plist_xml}
${sb_deny_read_plist}            </array>"
  else
    plist_xml="${plist_xml}
            </array>"
  fi

  plist_xml="${plist_xml}
            <key>denyWrite</key>
            <array>"

  if [ -n "$sb_deny_write_plist" ]; then
    plist_xml="${plist_xml}
${sb_deny_write_plist}            </array>"
  else
    plist_xml="${plist_xml}
            </array>"
  fi

  plist_xml="${plist_xml}
        </dict>
        <key>network</key>
        <dict>
            <key>allowedDomains</key>
            <array>"

  if [ -n "$sb_allowed_domains_plist" ]; then
    plist_xml="${plist_xml}
${sb_allowed_domains_plist}            </array>"
  else
    plist_xml="${plist_xml}
            </array>"
  fi

  plist_xml="${plist_xml}
        </dict>
    </dict>
</dict>
</plist>"

  # Validate with plutil if available (macOS); skip on Linux (RESEARCH.md Q2 RESOLVED)
  if command -v plutil >/dev/null 2>&1; then
    local tmpfile
    tmpfile="$(mktemp /tmp/conjure-plist-XXXXXX.plist)"
    printf '%s\n' "$plist_xml" > "$tmpfile"
    if ! plutil -lint "$tmpfile" >/dev/null 2>&1; then
      echo "✗ build_plist_xml: plutil -lint failed — malformed plist XML" >&2
      rm -f "$tmpfile"
      return 2
    fi
    rm -f "$tmpfile"
  fi

  printf '%s\n' "$plist_xml"
}

# build_ps1_script(regime, managed_settings_json)
# Arguments: regime string, managed-settings JSON content.
# Prints PowerShell script content to stdout. Caller captures and writes via mutate_write.
# CRITICAL: uses $env:ProgramFiles (NOT ProgramData) — verified from official Anthropic MDM example.
# CRITICAL: uses [System.IO.File]::WriteAllText with UTF8Encoding($false) for BOM-free UTF-8.
# The JSON is embedded in a PowerShell @'...'@ heredoc (no single quotes inside).
build_ps1_script() {
  local regime="$1"
  local managed_settings_json="$2"

  # Format the JSON for embedding (compact but readable — use jq for consistent output)
  local json_body
  json_body="$(printf '%s' "$managed_settings_json" | jq '.')"

  # WR-06: a PowerShell @'...'@ here-string terminates at a line whose first
  # characters are '@ (closing delimiter). A crafted deny path beginning with '@,
  # embedded as a JSON array element, could prematurely close the here-string and
  # corrupt the emitted script (injection-into-generated-artifact). Guard: reject
  # if any line of $json_body begins with '@ before embedding.
  while IFS= read -r json_line; do
    case "$json_line" in
      "'@"*)
        echo "✗ build_ps1_script: managed-settings JSON line begins with '@ — refusing to emit (here-string terminator hazard): $json_line" >&2
        return 2
        ;;
    esac
  done <<EOF
$json_body
EOF

  printf '%s\n' \
    '<#' \
    'Deploys Claude Code managed settings as a JSON file.' \
    '' \
    'Intune: Devices > Scripts and remediations > Platform scripts > Add (Windows 10 and later).' \
    '  Run this script using the logged on credentials: No' \
    '  Run script in 64 bit PowerShell Host: Yes' \
    '' \
    "Claude Code reads C:\\Program Files\\ClaudeCode\\managed-settings.json at startup" \
    'and treats it as a managed policy source. Edit the JSON below to change the' \
    'deployed settings; see https://code.claude.com/docs/en/settings for available keys.' \
    '' \
    "NOTE: This script is generated by conjure emit-policy --regime ${regime}." \
    'The forceLoginOrgUUID value MUST be replaced with your organization'"'"'s UUID' \
    'before deploying. See https://code.claude.com/docs/en/settings for details.' \
    'Compliance disclaimer: this configuration reduces non-compliant output risks' \
    'but does not make your project compliant. Engage your compliance officer.' \
    '#>' \
    '' \
    "\$ErrorActionPreference = 'Stop'" \
    '' \
    "\$dir = Join-Path \$env:ProgramFiles 'ClaudeCode'" \
    "New-Item -ItemType Directory -Path \$dir -Force | Out-Null" \
    '' \
    "\$json = @'"

  printf '%s\n' "$json_body"

  printf '%s\n' \
    "'@" \
    '' \
    "\$path = Join-Path \$dir 'managed-settings.json'" \
    "[System.IO.File]::WriteAllText(\$path, \$json, (New-Object System.Text.UTF8Encoding(\$false)))" \
    "Write-Output \"Wrote \$path\"" \
    "Write-Output \"Verify: open Claude Code and run /status -- confirm managed policy source is active\""
}
