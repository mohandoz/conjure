# shellcheck shell=bash
# lib/plugin-helpers.sh — shared jq transforms, validation, and guards for plugin emission.
# Source this file; do not execute directly.
# Requires: lib/mutate.sh already sourced (for mutate_write, dry-run awareness).
# POSIX bash 3.2+. No associative arrays, no mapfile, no local -n.

# Initialize bundled constants if not already set.
# Safe under set -u; idempotent on re-source.
CONJURE_RESERVED_MARKETPLACE_NAMES="${CONJURE_RESERVED_MARKETPLACE_NAMES:-\
claude-code-marketplace claude-code-plugins claude-plugins-official \
anthropic-marketplace anthropic-plugins agent-skills anthropic-agent-skills \
knowledge-work-plugins life-sciences claude-for-legal \
claude-for-financial-services financial-services-plugins}"

# reserved_name_check(name)
# Returns 0 if name is allowed, 1 if reserved or impersonation.
# Caller must: reserved_name_check "$MKT_NAME" || exit 2
reserved_name_check() {
  local name="$1"
  # Exact match against reserved list
  for reserved in $CONJURE_RESERVED_MARKETPLACE_NAMES; do
    if [ "$name" = "$reserved" ]; then
      echo "✗ Marketplace name '$name' is reserved for official Anthropic use." >&2
      return 1
    fi
  done
  # Impersonation patterns
  case "$name" in
    anthropic-*|claude-*|official-*)
      echo "✗ Marketplace name '$name' appears to impersonate an official Anthropic marketplace." >&2
      return 1 ;;
  esac
  return 0
}

# secret_scan(content, label)
# Returns 0 if no credential patterns found, 1 if a pattern matches.
# Caller must: secret_scan "$MANIFEST_CONTENT" "plugin.json" || exit 2
secret_scan() {
  local content="$1"
  local label="${2:-emitted manifest}"
  # Patterns cover common API key prefixes + password= patterns + quoted credential field assignments
  # shellcheck disable=SC2016
  local patterns
  patterns='sk-ant-[A-Za-z0-9_-]{10,}|sk-[A-Za-z0-9_-]{32,}|ghp_[A-Za-z0-9]{20,}|ghs_[A-Za-z0-9]{20,}|xoxb-[0-9A-Za-z_-]{10,}|-----BEGIN [A-Z ]+-----|password\s*[=:]\s*['"'"'"][^'"'"'"\s]{6,}['"'"'"]|"(api_key|api_secret|auth_token|access_token|secret_key|private_key)"\s*:\s*"[^"]{6,}"'
  if printf '%s' "$content" | grep -qiE "$patterns" 2>/dev/null; then
    echo "BLOCK: $label appears to contain a credential pattern — remove from env/values before emitting." >&2
    return 1
  fi
  return 0
}

# validate_plugin_json(content)
# Returns 0 if content is valid plugin.json, 1 if invalid.
# Caller must: validate_plugin_json "$PLUGIN_JSON" || exit 2
validate_plugin_json() {
  local content="$1"
  local errors=0

  # Required: name (string)
  if ! printf '%s' "$content" | jq -e '(.name | type) == "string"' >/dev/null 2>&1; then
    echo "✗ plugin.json: 'name' is required and must be a string" >&2
    errors=$((errors + 1))
  fi

  # Optional typed: version must be string if present
  if ! printf '%s' "$content" | jq -e 'if .version then (.version | type) == "string" else true end' >/dev/null 2>&1; then
    echo "✗ plugin.json: 'version' must be a string" >&2
    errors=$((errors + 1))
  fi

  # Optional typed: agents must be array if present
  if ! printf '%s' "$content" | jq -e 'if .agents then (.agents | type) == "array" else true end' >/dev/null 2>&1; then
    echo "✗ plugin.json: 'agents' must be an array" >&2
    errors=$((errors + 1))
  fi

  # Optional typed: keywords must be array if present
  if ! printf '%s' "$content" | jq -e 'if .keywords then (.keywords | type) == "array" else true end' >/dev/null 2>&1; then
    echo "✗ plugin.json: 'keywords' must be an array" >&2
    errors=$((errors + 1))
  fi

  # Optional typed: hooks must be object if present
  if ! printf '%s' "$content" | jq -e 'if .hooks then (.hooks | type) == "object" else true end' >/dev/null 2>&1; then
    echo "✗ plugin.json: 'hooks' must be an object" >&2
    errors=$((errors + 1))
  fi

  # Optional typed: mcpServers must be object if present
  if ! printf '%s' "$content" | jq -e 'if .mcpServers then (.mcpServers | type) == "object" else true end' >/dev/null 2>&1; then
    echo "✗ plugin.json: 'mcpServers' must be an object" >&2
    errors=$((errors + 1))
  fi

  [ "$errors" -gt 0 ] && return 1
  return 0
}

# validate_marketplace_json(content)
# Returns 0 if content is valid marketplace.json, 1 if invalid.
# Caller must: validate_marketplace_json "$MKT_JSON" || exit 2
validate_marketplace_json() {
  local content="$1"
  local errors=0

  # Required: name (string)
  if ! printf '%s' "$content" | jq -e '(.name | type) == "string"' >/dev/null 2>&1; then
    echo "✗ marketplace.json: 'name' is required and must be a string" >&2
    errors=$((errors + 1))
  fi

  # Required: owner (object)
  if ! printf '%s' "$content" | jq -e '(.owner | type) == "object"' >/dev/null 2>&1; then
    echo "✗ marketplace.json: 'owner' is required and must be an object" >&2
    errors=$((errors + 1))
  fi

  # Required: plugins (array)
  if ! printf '%s' "$content" | jq -e '(.plugins | type) == "array"' >/dev/null 2>&1; then
    echo "✗ marketplace.json: 'plugins' is required and must be an array" >&2
    errors=$((errors + 1))
  fi

  # Per-plugin entry: name string and source present
  if printf '%s' "$content" | jq -e '.plugins | length > 0' >/dev/null 2>&1; then
    if ! printf '%s' "$content" | jq -e '[.plugins[] | select((.name | type) != "string" or (.source == null))] | length == 0' >/dev/null 2>&1; then
      echo "✗ marketplace.json: each plugin entry requires 'name' (string) and 'source'" >&2
      errors=$((errors + 1))
    fi
  fi

  [ "$errors" -gt 0 ] && return 1
  return 0
}

# detect_github_source(target)
# Prints owner/repo to stdout on success, returns 1 for non-GitHub remotes or no remote.
detect_github_source() {
  local target="$1"
  local remote_url
  remote_url="$(git -C "$target" remote get-url origin 2>/dev/null)" || return 1

  local owner_repo=""
  case "$remote_url" in
    # SSH: git@github.com:owner/repo.git or git@github.com:owner/repo
    git@github.com:*)
      owner_repo="${remote_url#git@github.com:}"
      owner_repo="${owner_repo%.git}" ;;
    # HTTPS: https://github.com/owner/repo.git or https://github.com/owner/repo
    https://github.com/*)
      owner_repo="${remote_url#https://github.com/}"
      owner_repo="${owner_repo%.git}" ;;
    *) return 1 ;;
  esac

  [ -n "$owner_repo" ] && printf '%s' "$owner_repo"
}

# resolve_version(target)
# Tier 1: .conjure-version file
# Tier 2: git HEAD SHA (warns on dirty tree)
# Tier 3: 0.0.0 + warning
# Always prints version to stdout and returns 0.
resolve_version() {
  local target="$1"

  # Tier 1: .conjure-version file
  if [ -f "$target/.conjure-version" ]; then
    cat "$target/.conjure-version"
    return 0
  fi

  # Tier 2: git HEAD SHA
  if command -v git >/dev/null 2>&1 && git -C "$target" rev-parse HEAD >/dev/null 2>&1; then
    local sha
    sha="$(git -C "$target" rev-parse HEAD)"
    # D-06: dirty tree WARNS, never exits 2 on target-repo emit path
    if ! git -C "$target" diff --quiet 2>/dev/null || ! git -C "$target" diff --cached --quiet 2>/dev/null; then
      echo "WARN: working tree has uncommitted changes — sha may not reflect emitted contents" >&2
    fi
    printf '%s' "$sha"
    return 0
  fi

  # Tier 3: placeholder
  echo "WARN: not a git repo and no .conjure-version — emitting version 0.0.0" >&2
  printf '0.0.0'
  return 0
}

# plugin_build_plugin_json(target, version)
# Builds updated plugin.json by reading harness paths and merging with existing manifest.
# Prints resulting JSON to stdout; caller writes via mutate_write.
plugin_build_plugin_json() {
  local target="$1"
  local version="$2"

  # Harness path discovery
  local skills_dir=""
  if [ -d "$target/.claude/skills" ]; then
    local count
    count=$(find "$target/.claude/skills" -name "SKILL.md" 2>/dev/null | wc -l | tr -d ' ')
    [ "$count" -gt 0 ] && skills_dir=".claude/skills"
  fi

  local agents_json="[]"
  if [ -d "$target/.claude/agents" ]; then
    agents_json=$(find "$target/.claude/agents" -maxdepth 1 -name "*.md" 2>/dev/null \
      | sed "s|$target/||" | jq -R . | jq -sc .)
    [ -z "$agents_json" ] && agents_json="[]"
  fi

  local hooks_obj="null"
  if [ -f "$target/.claude/settings.json" ] && command -v jq >/dev/null 2>&1; then
    hooks_obj=$(jq '.hooks // null' "$target/.claude/settings.json")
  fi

  local mcp_obj="null"
  if [ -f "$target/.mcp.json" ] && command -v jq >/dev/null 2>&1; then
    mcp_obj=$(jq '.mcpServers // null' "$target/.mcp.json")
  fi

  # Read existing plugin.json for merge-preserve (D-03)
  local existing='{}'
  if [ -f "$target/.claude-plugin/plugin.json" ]; then
    existing=$(cat "$target/.claude-plugin/plugin.json" 2>/dev/null || echo '{}')
  fi

  # Build updated JSON via jq with merge-preserve of user metadata fields
  local updated
  updated=$(printf '%s' "$existing" | jq \
    --arg skills "$skills_dir" \
    --argjson agents "$agents_json" \
    --argjson hooks "$hooks_obj" \
    --argjson mcp "$mcp_obj" \
    --arg version "$version" \
    '. as $orig |
     ($orig.description // null) as $desc |
     ($orig.keywords // null) as $kw |
     ($orig.author // null) as $auth |
     ($orig.license // null) as $lic |
     ($orig.homepage // null) as $hp |
     ($orig.repository // null) as $repo |
     . |
     .version = $version |
     (if $skills != "" then .skills = $skills else . end) |
     (if ($agents | length) > 0 then .agents = $agents else . end) |
     (if $hooks != null then .hooks = $hooks else . end) |
     (if $mcp != null then .mcpServers = $mcp else . end) |
     (if $desc != null then .description = $desc else . end) |
     (if $kw != null then .keywords = $kw else . end) |
     (if $auth != null then .author = $auth else . end) |
     (if $lic != null then .license = $lic else . end) |
     (if $hp != null then .homepage = $hp else . end) |
     (if $repo != null then .repository = $repo else . end)')

  # jq-empty-check before returning
  printf '%s' "$updated" | jq empty 2>/dev/null || {
    echo "✗ jq produced invalid JSON for plugin.json" >&2
    return 1
  }

  printf '%s' "$updated"
}

# run_cli_validate(target)
# Runs `claude plugin validate` on target.
# Exits 2 if claude is absent (when --validate was explicitly requested).
# Translates claude's non-zero exit → conjure exit 2.
run_cli_validate() {
  local target="$1"
  # D-10: absent claude CLI → exit 2 with install hint
  if ! command -v claude >/dev/null 2>&1; then
    echo "✗ --validate requires the claude CLI (install from https://code.claude.com)." >&2
    echo "  Check: command -v claude" >&2
    exit 2
  fi
  # Run validate; claude exits 1 on errors, 0 on clean/warnings-only
  # Capture output so user sees error details; translate exit 1 → exit 2
  local validate_out validate_rc
  validate_out="$(claude plugin validate "$target" 2>&1)" || validate_rc=$?
  validate_rc="${validate_rc:-0}"
  if [ -n "$validate_out" ]; then
    printf '%s\n' "$validate_out"
  fi
  if [ "$validate_rc" -ne 0 ]; then
    echo "✗ claude plugin validate failed — manifests not committed. Fix errors and re-run." >&2
    exit 2
  fi
}
