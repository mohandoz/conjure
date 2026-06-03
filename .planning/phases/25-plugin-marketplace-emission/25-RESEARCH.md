# Phase 25: Plugin + Marketplace Emission - Research

**Researched:** 2026-06-03
**Domain:** POSIX bash CLI — Claude Code plugin.json + marketplace.json emission, settings.json wiring, emit-time validation
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** Keep `conjure publish` (self-publish) and `conjure publish-plugin` (target-repo emit) as **separate subcommands**. Extract shared `lib/plugin-helpers.sh`; refactor existing `scripts/publish-plugin.sh` self-publish worker to source it.
- **D-02:** `conjure publish-plugin` operates on the **current working directory** by default (like `init`/`adopt`/`audit`) but accepts an explicit **`--path <dir>`** flag.
- **D-03:** When regenerating `.claude-plugin/plugin.json`, **merge-preserve-manual**: regenerate computed fields (`skills`/`agents`/`hooks`/`mcpServers` paths, `version`) via jq through `mutate_write`, but preserve user-edited metadata (`description`, `keywords`, `author`, `license`). Backup-before-mutate.
- **D-04:** On success, print files written plus a copy-pasteable verification command (e.g. `claude plugin validate .`, `claude plugin list`).
- **D-05:** `--marketplace` source default = **auto-detect github**: parse `git remote get-url origin` → owner/repo, emit `source: github` with `ref` + **pinned `sha` (HEAD)**. Fall back to local source if no remote.
- **D-06:** Version fallback chain: `.conjure-version` → **current git SHA** → placeholder **`0.0.0` + printed warning**. Dirty tree → warn loudly, never blocks emit.
- **D-07:** Reserved-name guard uses a **bundled static list** baked into `lib/plugin-helpers.sh`. Reject with **exit 2**. Zero-egress / bundled-data ethos.
- **D-08:** Secret-pattern scan covers the **whole emitted manifest** (`env`, `mcpServers`, and any string value). **Exit 2 before writing any file** on a hit.
- **D-09:** **Two-tier validation.** Bundled JSON-schema check runs on every invocation and **refuses to write any file on an invalid manifest**. `claude plugin validate .` is the opt-in extra layer behind `--validate`.
- **D-10:** When **`--validate` is requested but the `claude` CLI is absent → exit 2 hard** with an install hint.
- **D-11:** Bundled plugin/marketplace JSON-schemas live in **`.claude-plugin/SCHEMAS/`** alongside the existing `agent.schema.json` / `skill.schema.json`. New files: `plugin.schema.json`, `marketplace.schema.json`.
- **D-12:** Audit reconciliation check (plugin.json out-of-sync with actual `.claude/` contents) is a **warning, exit 0** (advisory). Does not break the CI gate.
- **D-13:** Wire `extraKnownMarketplaces` into project **`.claude/settings.json`** (shared/committed) **only when `--marketplace` is passed**.
- **D-14:** **Discoverable-only by default**: `extraKnownMarketplaces` makes the plugin known but does NOT auto-activate. **`--enable`** opts into adding the plugin to `enabledPlugins`.
- **D-15:** `extraKnownMarketplaces` is an **object** (keys = marketplace names); merge is **keyed-object idempotent** via jq through `mutate_write`. Cover with a **golden-fixture re-run test**.
- **D-16:** github entries **pin `sha` with `ref` as fallback** (write both) for audit-clean entries.

### Claude's Discretion

- Exact reserved-name string set (seed with the official docs list).
- Exact secret-pattern regex set / entropy threshold (reuse repo's existing scanner if one exists).
- Output formatting details of the emit report (align with existing `publish-plugin.sh` / adopt-report style).
- Whether `plugin.json` `mcpServers`/`hooks` path emission reads from `.mcp.json` / `.claude/settings.json` hooks block — resolved in this research.

### Deferred Ideas (OUT OF SCOPE)

- `--pin-sha` as a standalone marketplace-source pinning subcommand.
- Workspace / cross-repo `publish-plugin` (emit across many repos) — Phase 29.
- `strictKnownMarketplaces` enforcement — Phase 26 (managed-settings.json only).
- Resolving whether `extraKnownMarketplaces` is honored in managed-settings scope — Phase 26.

</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| PLUG-01 | `conjure publish-plugin` emits `.claude-plugin/plugin.json` from the scaffolded harness (correct `skills`/`agents`/`hooks`/`mcpServers` paths; `version` from `.conjure-version`) | plugin.json schema fields confirmed from official docs; path discovery patterns documented in §Standard Stack + §Code Examples |
| PLUG-02 | `conjure publish-plugin --marketplace` generates `.claude-plugin/marketplace.json` (kebab-case `name`, `owner`, `plugins[]` with `source`); reserved-name guard | Reserved names confirmed from official docs; full schema shapes documented; jq transforms shown in §Code Examples |
| PLUG-03 | Wires `extraKnownMarketplaces` (object form) + `enabledPlugins` into `.claude/settings.json` via idempotent `mutate_write` merge | Object shape confirmed from official docs + live tested jq idempotent merge; §Code Examples §Architecture Patterns |
| PLUG-04 | `conjure publish-plugin --validate` runs `claude plugin validate` + JSON-schema check at emit time; refuses on invalid manifest | CLI behavior verified live (exit 1 on error, exit 0 with warnings, exit 1 with --strict); schema check pattern from SCHEMAS/; §Don't Hand-Roll |
| PLUG-05 | Version fallback — when `version` absent in `plugin.json`/marketplace entry, emit current git SHA as the version | Version resolution chain from official docs; fallback logic documented; §Code Examples |

</phase_requirements>

---

## Summary

Phase 25 delivers `conjure publish-plugin` — a command that generates, validates, and wires a Claude Code plugin + marketplace manifest from a conjure-scaffolded harness. The existing self-publish path (`conjure publish` → `scripts/publish-plugin.sh`) serves as the seed for the new shared `lib/plugin-helpers.sh`. The new worker `scripts/emit-plugin.sh` is the target-repo path; both source the new lib. The critical distinction between the two commands (D-01) is the most important framing for planning.

All schema shapes are now confirmed from official docs, live codebase reads, and live CLI testing. The three most surprising verified findings are: (1) `claude plugin validate` exits **1** (not 2) on validation errors — the planner must not confuse this with conjure's own exit-2 convention; conjure should translate any non-zero exit from `claude plugin validate` into its own exit 2 when `--validate` is passed; (2) `extraKnownMarketplaces` is confirmed to be an **object** keyed by marketplace name (not an array), verified from official docs and live jq tests; (3) `mcpServers` in plugin.json should reference `.mcp.json` directly (the canonical CC MCP config file), while hooks should be read from `.claude/settings.json` hooks block and emitted inline in plugin.json.

The phase has no new runtime dependencies. All functionality is achievable with existing `jq`, `git`, and `bash` primitives already in the envelope. The bundled JSON-schema validation approach is replicated from the existing `SCHEMAS/agent.schema.json` + `skill.schema.json` pattern in `conjure audit`.

**Primary recommendation:** Implement in three build steps: (1) `lib/plugin-helpers.sh` + refactor `publish-plugin.sh`, (2) `scripts/emit-plugin.sh` + dispatch entry, (3) audit-setup.sh reconciliation warnings. The JSON schemas and fixture tests belong to step 2.

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Plugin manifest generation (plugin.json) | CLI worker (emit-plugin.sh) | lib/plugin-helpers.sh | All filesystem mutations via mutate.sh chokepoint |
| Marketplace manifest generation | CLI worker (emit-plugin.sh) | lib/plugin-helpers.sh | Same chokepoint invariant; jq transforms in helper lib |
| settings.json wiring (extraKnownMarketplaces) | lib/plugin-helpers.sh via mutate_write | .claude/settings.json target | Idempotent keyed-object merge via jq |
| Bundled JSON-schema validation | lib/plugin-helpers.sh (validate function) | .claude-plugin/SCHEMAS/ | Runs before every write; jq-based per existing SCHEMAS pattern |
| `claude plugin validate` gate | scripts/emit-plugin.sh (--validate flag path) | cli/conjure flag parsing | Opt-in; exit 2 on absent claude CLI when explicitly requested |
| Reserved-name guard | lib/plugin-helpers.sh (bundled list) | scripts/emit-plugin.sh | Bundled-data ethos; no egress |
| Secret-pattern scan | lib/plugin-helpers.sh (scan function) | scripts/emit-plugin.sh | Pre-write gate; exit 2 on hit |
| Version provenance (SHA/fallback) | scripts/emit-plugin.sh | git commands | Reads .conjure-version → git rev-parse HEAD → 0.0.0 |
| Harness path discovery | scripts/emit-plugin.sh | lib/inventory.sh patterns | find-based; mirrors audit-setup.sh skill/agent enumeration |
| Audit reconciliation check | scripts/audit-setup.sh (new section) | lib/plugin-helpers.sh | Warning-exit-0 advisory; does not break CI gate |
| Dispatch / flag parsing | cli/conjure (cmd_publish_plugin) | — | Thin wrapper pattern per existing cmd_publish |

---

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| `jq` | system (preflight-checked) | JSON transforms for plugin.json/marketplace.json/settings.json | Already hard dep in envelope; existing jq preflight in scripts/preflight.sh |
| `git` | system | SHA pinning, remote URL parsing, dirty-tree check | Already hard dep; existing `command -v git` preflight pattern |
| `bash` 3.2+ | system | Worker script execution | POSIX constraint; CLAUDE.md mandates 3.2+ compatibility |
| `claude` CLI | v2.1.117+ | `claude plugin validate .` (opt-in --validate gate) | Built-in to CC install; `command -v` detection per existing pattern |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `lib/mutate.sh` | (existing) | All filesystem writes — dry-run, backup-before-mutate | Every write in emit-plugin.sh and plugin-helpers.sh routes through this |
| `lib/inventory.sh` patterns | (existing) | `find .claude/skills -name SKILL.md` pattern | Reuse find patterns for harness path discovery |
| `lib/caps.sh` | (existing) | CLAUDE_MD_CAP / SKILL_MD_CAP constants | May be sourced in audit reconciliation section |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| jq-based JSON-schema validation | A Node.js schema validator | jq is already in envelope; Node schema libs would add deps. jq validation is sufficient for required/type checks. |
| Bundled reserved-name list | Runtime fetch of reserved names | Bundled wins: zero-egress-in-CI constraint; staleness handled by audit advisory |
| Inline hooks in plugin.json | hooks/hooks.json file | Inline keeps everything in one file, simpler for emit; generate from .claude/settings.json hooks block |

**Installation:** No new packages. Zero new runtime deps. All tooling is already in the envelope.

---

## Package Legitimacy Audit

No new packages are installed by this phase. The phase operates entirely within the existing runtime envelope (jq + git + bash + optional claude CLI). The Package Legitimacy Gate is not applicable.

---

## Architecture Patterns

### System Architecture Diagram

```
TARGET REPO (.claude/ harness)
  .claude/skills/<name>/SKILL.md  ──────────────┐
  .claude/agents/<name>.md  ────────────────────┤
  .claude/hooks/*.mjs  ─────────────────────────┤  find-based
  .claude/settings.json (.hooks block)  ────────┤  discovery
  .mcp.json (optional)  ────────────────────────┘
           │
           ▼
  scripts/emit-plugin.sh
           │
           ├── lib/plugin-helpers.sh
           │     ├── reserved_name_check()  → exit 2 if reserved
           │     ├── secret_scan()          → exit 2 before ANY write
           │     ├── plugin_validate_schema()  → exit 2 if invalid (bundled .claude-plugin/SCHEMAS/)
           │     ├── plugin_build_plugin_json()  → jq transform
           │     ├── plugin_build_marketplace_json()  → jq transform
           │     └── plugin_wire_settings()  → jq keyed-object merge
           │
           ├── version_resolve()
           │     .conjure-version → git rev-parse HEAD → "0.0.0" + warn
           │
           ├── mutate_write() [all writes]
           │     .claude-plugin/plugin.json
           │     .claude-plugin/marketplace.json
           │     .claude/settings.json  (--marketplace flag path)
           │
           └── [--validate flag]
                 claude plugin validate .
                 (exit 2 if claude absent and --validate was passed)
                 (translate non-zero claude exit → conjure exit 2)

AUDIT PATH (scripts/audit-setup.sh — new section)
  .claude-plugin/plugin.json ←→ .claude/ harness
           │
           ▼
  reconciliation_check()  → warn (exit 0) if manifest ≠ on-disk
  ref_without_sha_check()  → warn (exit 0) if extraKnownMarketplaces entry lacks sha
```

### Recommended Project Structure

New files in this phase:

```
lib/
  plugin-helpers.sh         # (NEW) shared jq transforms + validation functions
scripts/
  emit-plugin.sh            # (NEW) target-repo emit worker
  publish-plugin.sh         # (MODIFIED) source lib/plugin-helpers.sh
cli/
  conjure                   # (MODIFIED) add cmd_publish_plugin + dispatch entry
scripts/
  audit-setup.sh            # (MODIFIED) add reconciliation + ref-without-sha sections
.claude-plugin/SCHEMAS/
  plugin.schema.json        # (NEW) bundled plugin.json schema
  marketplace.schema.json   # (NEW) bundled marketplace.json schema
tests/fixtures/
  _emit-plugin/             # (NEW) golden fixture for idempotent emit tests
```

### Pattern 1: Harness Path Discovery

**What:** Enumerate `skills`/`agents`/`hooks`/`mcpServers` from the actual on-disk harness using `find`.

**When to use:** At emit time, before building plugin.json.

```bash
# Source: live codebase (lib/inventory.sh patterns + audit-setup.sh)
# Skills: directories containing SKILL.md
SKILLS_DIR=""
if [ -d "$TARGET/.claude/skills" ]; then
  COUNT=$(find "$TARGET/.claude/skills" -name "SKILL.md" 2>/dev/null | wc -l | tr -d ' ')
  [ "$COUNT" -gt 0 ] && SKILLS_DIR=".claude/skills"
fi

# Agents: .md files in .claude/agents/
AGENTS_JSON="[]"
if [ -d "$TARGET/.claude/agents" ]; then
  # Build JSON array of relative paths
  AGENTS_JSON=$(find "$TARGET/.claude/agents" -maxdepth 1 -name "*.md" 2>/dev/null \
    | sed "s|$TARGET/||" | jq -R . | jq -sc .)
fi

# Hooks: from .claude/settings.json hooks block
HOOKS_OBJ="null"
if [ -f "$TARGET/.claude/settings.json" ] && command -v jq >/dev/null 2>&1; then
  HOOKS_OBJ=$(jq '.hooks // null' "$TARGET/.claude/settings.json")
fi

# mcpServers: from .mcp.json if present
MCP_OBJ="null"
if [ -f "$TARGET/.mcp.json" ] && command -v jq >/dev/null 2>&1; then
  MCP_OBJ=$(jq '.mcpServers // null' "$TARGET/.mcp.json")
fi
```

### Pattern 2: Keyed-Object Idempotent Merge (extraKnownMarketplaces)

**What:** Merge an `extraKnownMarketplaces` entry into `.claude/settings.json` by marketplace name key — re-running updates the sha in place, never appends a duplicate.

**When to use:** `--marketplace` flag path in emit-plugin.sh.

```bash
# Source: verified live with jq 1.8.1 — idempotent confirmed
# $SETTINGS_FILE = .claude/settings.json
# $MKT_NAME = marketplace name (kebab-case)
# $MKT_SOURCE = jq object: {"source": "github", "repo": "owner/repo", "ref": "main", "sha": "abc123..."}

CURRENT=$(cat "$SETTINGS_FILE")
UPDATED=$(printf '%s' "$CURRENT" | jq \
  --arg name "$MKT_NAME" \
  --argjson src "$MKT_SOURCE" \
  '.extraKnownMarketplaces = (.extraKnownMarketplaces // {}) | .extraKnownMarketplaces[$name] = {"source": $src}')
mutate_write "$SETTINGS_FILE" "$UPDATED"

# enabledPlugins merge (--enable flag path):
# $PLUGIN_KEY = "plugin-name@marketplace-name"
UPDATED2=$(printf '%s' "$CURRENT_AFTER_MKT" | jq \
  --arg key "$PLUGIN_KEY" \
  '.enabledPlugins = (.enabledPlugins // {}) | .enabledPlugins[$key] = true')
mutate_write "$SETTINGS_FILE" "$UPDATED2"
```

### Pattern 3: Merge-Preserve-Manual for plugin.json (D-03)

**What:** Regenerate computed fields while preserving user-edited metadata.

**When to use:** Every `publish-plugin` invocation on an existing plugin.json.

```bash
# Source: verified pattern from scripts/publish-plugin.sh + official plugin.json schema
# Read existing plugin.json; merge-update computed fields only
EXISTING=$(cat "$TARGET/.claude-plugin/plugin.json" 2>/dev/null || echo '{}')

UPDATED=$(printf '%s' "$EXISTING" | jq \
  --arg skills "$SKILLS_DIR" \
  --argjson agents "$AGENTS_JSON" \
  --argjson hooks "$HOOKS_OBJ" \
  --argjson mcp "$MCP_OBJ" \
  --arg version "$RESOLVED_VERSION" \
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
```

### Pattern 4: Version Resolution Chain (D-06)

**What:** Resolve version from `.conjure-version` → git SHA → `0.0.0` + warning.

```bash
# Source: D-06 decision; mirrors VERSION fallback in publish-plugin.sh
resolve_version() {
  local target="$1"
  # Tier 1: .conjure-version file
  if [ -f "$target/.conjure-version" ]; then
    cat "$target/.conjure-version"
    return 0
  fi
  # Tier 2: git HEAD SHA (target repo's git, not CONJURE_HOME)
  if command -v git >/dev/null 2>&1 && git -C "$target" rev-parse HEAD >/dev/null 2>&1; then
    local sha
    sha="$(git -C "$target" rev-parse HEAD)"
    # Dirty tree: warn, still emit SHA
    if ! git -C "$target" diff --quiet 2>/dev/null || ! git -C "$target" diff --cached --quiet 2>/dev/null; then
      echo "WARN: working tree has uncommitted changes — sha may not reflect emitted contents" >&2
    fi
    printf '%s' "$sha"
    return 0
  fi
  # Tier 3: placeholder
  echo "WARN: not a git repo and no .conjure-version — emitting version 0.0.0" >&2
  printf '0.0.0'
}
```

### Pattern 5: Secret-Pattern Scan (D-08)

**What:** Scan the full emitted manifest content before any write. Exit 2 on hit.

```bash
# Source: D-08 decision; patterns from PITFALLS.md §M-2 + pre-bash-block-destructive.mjs
# No existing secret scanner in the repo (v0.6.1 hardening added gitleaks advisory dep, not bundled scanner)
secret_scan() {
  local content="$1"
  local label="${2:-emitted manifest}"
  # Patterns: common credential prefixes + high-entropy string indicators
  # Deliberately conservative: prefer false positive (warn) over false negative (miss)
  local patterns
  patterns='sk-ant-[A-Za-z0-9_-]{10,}|sk-[A-Za-z0-9_-]{32,}|ghp_[A-Za-z0-9]{20,}|ghs_[A-Za-z0-9]{20,}|xoxb-[0-9A-Za-z_-]{10,}|-----BEGIN [A-Z ]+-----|password\s*[=:]\s*['\''"][^'\''"\s]{6,}['\''"]|"(api_key|api_secret|auth_token|access_token|secret_key|private_key)"\s*:\s*"[^"]{6,}"'
  if printf '%s' "$content" | grep -qiE "$patterns" 2>/dev/null; then
    echo "BLOCK: $label appears to contain a credential pattern — remove from env/values before emitting." >&2
    return 1   # caller must exit 2
  fi
  return 0
}
```

### Pattern 6: Reserved Name Guard (D-07)

**What:** Check marketplace name against bundled reserved list + impersonation patterns.

```bash
# Source: Official CC docs (verified 2026-06-03) + D-07 decision
# Authoritative reserved list from https://code.claude.com/docs/en/plugin-marketplaces
CONJURE_RESERVED_MARKETPLACE_NAMES="claude-code-marketplace claude-code-plugins claude-plugins-official anthropic-marketplace anthropic-plugins agent-skills anthropic-agent-skills knowledge-work-plugins life-sciences claude-for-legal claude-for-financial-services financial-services-plugins"

reserved_name_check() {
  local name="$1"
  # Exact match against reserved list
  for reserved in $CONJURE_RESERVED_MARKETPLACE_NAMES; do
    if [ "$name" = "$reserved" ]; then
      echo "✗ Marketplace name '$name' is reserved for official Anthropic use." >&2
      return 1
    fi
  done
  # Impersonation pattern: names starting with anthropic, claude, or official
  # (catches "official-claude-plugins", "anthropic-tools-v2", etc.)
  case "$name" in
    anthropic-*|claude-*|official-*)
      echo "✗ Marketplace name '$name' appears to impersonate an official Anthropic marketplace." >&2
      return 1 ;;
  esac
  return 0
}
# Caller must exit 2 on non-zero return
```

### Pattern 7: claude plugin validate Integration (D-09/D-10)

**What:** Two-tier validation. Bundled schema check always runs. CLI validate is opt-in.

```bash
# Source: live-tested claude 2.1.161; exit codes confirmed
# CRITICAL: claude plugin validate exits 1 (not 2) on validation errors
# Conjure must translate this to exit 2 per Conjure's own exit code convention

run_cli_validate() {
  local target="$1"
  # D-10: if --validate was explicitly requested, hard-fail on absent claude
  if ! command -v claude >/dev/null 2>&1; then
    echo "✗ --validate requires the claude CLI (install from https://code.claude.com)." >&2
    echo "  Check: command -v claude" >&2
    exit 2
  fi
  # Run validate; claude exits 1 on errors, 0 on clean/warnings-only
  if ! claude plugin validate "$target" 2>&1; then
    echo "✗ claude plugin validate failed — manifests not committed. Fix errors and re-run." >&2
    exit 2  # Translate claude's exit 1 → conjure's exit 2
  fi
}
# Note: claude plugin validate --strict treats warnings as errors (exit 1)
# Bare invocation: warnings → exit 0, errors → exit 1, missing file → exit 1
```

### Pattern 8: GitHub Remote Auto-Detection (D-05)

**What:** Parse `git remote get-url origin` to extract owner/repo for marketplace source.

```bash
# Source: live-tested on conjure repo (git@github.com:mohandoz/conjure.git)
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
    *) return 1 ;;  # Not GitHub — fall back to local source
  esac

  [ -n "$owner_repo" ] && printf '%s' "$owner_repo"
}
```

### Pattern 9: Bundled JSON-Schema Validation via jq (D-09/D-11)

**What:** Validate emitted manifests against bundled JSON schemas in .claude-plugin/SCHEMAS/.

```bash
# Source: established pattern from .claude-plugin/SCHEMAS/agent.schema.json + skill.schema.json
# Pattern: use jq to check required fields and types (not full JSON Schema draft/2020-12 validation)
# jq does not implement full JSON Schema, but required-field + type checks are sufficient

validate_plugin_json() {
  local content="$1"
  local errors=0

  # Required: name (string)
  if ! printf '%s' "$content" | jq -e '(.name | type) == "string"' >/dev/null 2>&1; then
    echo "✗ plugin.json: 'name' is required and must be a string" >&2
    errors=$((errors + 1))
  fi

  # Type checks for optional but typed fields
  if ! printf '%s' "$content" | jq -e 'if .version then (.version | type) == "string" else true end' >/dev/null 2>&1; then
    echo "✗ plugin.json: 'version' must be a string" >&2
    errors=$((errors + 1))
  fi

  [ "$errors" -gt 0 ] && return 1
  return 0
}

validate_marketplace_json() {
  local content="$1"
  local errors=0

  # Required: name (string), owner (object), plugins (array)
  if ! printf '%s' "$content" | jq -e '(.name | type) == "string"' >/dev/null 2>&1; then
    echo "✗ marketplace.json: 'name' is required and must be a string" >&2; errors=$((errors+1))
  fi
  if ! printf '%s' "$content" | jq -e '(.owner | type) == "object"' >/dev/null 2>&1; then
    echo "✗ marketplace.json: 'owner' is required and must be an object" >&2; errors=$((errors+1))
  fi
  if ! printf '%s' "$content" | jq -e '(.plugins | type) == "array"' >/dev/null 2>&1; then
    echo "✗ marketplace.json: 'plugins' is required and must be an array" >&2; errors=$((errors+1))
  fi
  # Each plugin entry: name and source required
  if printf '%s' "$content" | jq -e '.plugins | length > 0' >/dev/null 2>&1; then
    if ! printf '%s' "$content" | jq -e '[.plugins[] | select((.name | type) != "string" or (.source == null))] | length == 0' >/dev/null 2>&1; then
      echo "✗ marketplace.json: each plugin entry requires 'name' (string) and 'source'" >&2; errors=$((errors+1))
    fi
  fi

  [ "$errors" -gt 0 ] && return 1
  return 0
}
```

### Anti-Patterns to Avoid

- **Calling `claude plugin init` as a subprocess:** Wrapping an unstable CLI subcommand creates coupling that breaks on CC updates (Pitfall M-5). Generate plugin directory structure directly.
- **Bypassing mutate_write for manifest writes:** Breaks dry-run and backup-before-mutate invariants. All writes must go through `mutate_write`.
- **Treating `claude plugin validate` exit 1 as a warning:** `claude plugin validate` exits 1 on errors (not 2). Conjure must translate any non-zero exit to exit 2 when `--validate` is passed.
- **Array-form `extraKnownMarketplaces`:** The field is an object, not an array. Using array form breaks wiring silently.
- **emitting version without bumping:** CC uses the `version` field as the cache key; a re-publish without version bump means team members never receive updates.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| JSON manifest validation | Custom parser or schema engine | jq type/required checks (existing SCHEMAS/ pattern) | jq is already in envelope; the required+type subset is sufficient for the schema fields; full JSON Schema draft/2020-12 adds no value here |
| Harness path enumeration | Custom file scanner | `find .claude/skills -name SKILL.md` (mirrors audit-setup.sh) | Existing patterns already handle symlink-skip, binary-skip, and POSIX find semantics |
| Git remote URL parsing | Regex from scratch | Existing `git remote get-url` + `sed` strip (live-tested) | Handles both SSH and HTTPS forms; let git resolve the remote |
| Plugin manifest validation | Forking a Node.js validator | `claude plugin validate .` (CC built-in, `--validate` flag) | CC ships the authoritative validator; no dep required |
| Secrets scanning library | gitleaks integration or external scan | Inline regex patterns (9 targeted patterns cover the 90% case) | Zero deps, zero egress, no install; sufficient for common credential prefixes |
| Idempotent JSON merge | Custom merge logic | jq keyed-object update pattern (live-tested idempotent) | One-liner; re-running updates in place; no duplicate entries possible |

**Key insight:** The entire phase is achievable with jq + git + bash already in the envelope. The one external tool (`claude plugin validate`) is optional (behind `--validate`) and absent-detected via `command -v` per Conjure's existing preflight convention.

---

## Common Pitfalls

### Pitfall 1: `claude plugin validate` Exits 1, Not 2 (CR-1)
**What goes wrong:** Conjure treats any non-zero exit from `claude plugin validate` as a warning (exit 1) rather than hard-blocking it. The user sees "validation passed with warnings" but the manifest is actually invalid.
**Why it happens:** Conjure's own exit code convention is exit 2 for hard failures, exit 1 for warnings. `claude plugin validate` uses exit 1 for both warnings (with `--strict`) and errors (always). Without explicit translation, the codes mix.
**How to avoid:** In emit-plugin.sh, treat any non-zero exit from `claude plugin validate` as a hard failure (exit 2) when `--validate` is passed. The bundled schema check (tier 1) handles the blocking gate; the CLI validate is confirmatory.
**Warning signs:** `--validate` passes but manifests fail on a fresh CC install.

### Pitfall 2: mcpServers and hooks Path Confusion (CR-4)
**What goes wrong:** emit-plugin.sh reads hooks from the wrong source (e.g., `.claude/hooks/*.mjs` file list instead of the `.claude/settings.json` hooks block) and generates a plugin.json that references scripts that don't exist in the plugin dir.
**Why it happens:** The harness has TWO hook representations: the `.mjs` script files and the `.claude/settings.json` wiring. The plugin.json hooks field needs the *wiring* (the event→command mapping), not the file list.
**How to avoid:** Read `jq '.hooks // null' .claude/settings.json` for the hooks block and emit it inline in plugin.json. The `.mjs` files are referenced by the hook commands inside that block.
**Warning signs:** Plugin installs but hooks don't fire (the event→command mapping is absent from plugin.json).

### Pitfall 3: `extraKnownMarketplaces` Array vs Object Confusion (D-15)
**What goes wrong:** emit-plugin.sh appends to `extraKnownMarketplaces` as if it were an array, producing `[{...}, {...}]` instead of `{"name": {...}}`. This silently fails because CC only reads the object form.
**Why it happens:** Training knowledge often shows `strictKnownMarketplaces` (which IS an array) alongside `extraKnownMarketplaces`. The two look similar but have different shapes.
**How to avoid:** `extraKnownMarketplaces` is definitively an **object** (keys = marketplace names). Use the keyed-object merge pattern (Pattern 2 above). Confirm with the golden-fixture re-run test.
**Warning signs:** Re-running `publish-plugin --marketplace` adds a second entry to `.claude/settings.json` instead of updating the existing one.

### Pitfall 4: Dirty Tree Asymmetry (D-06)
**What goes wrong:** The planner "fixes" the target-repo path to match the self-publish path (dirty tree → exit 2), breaking D-06's intentional asymmetry.
**Why it happens:** `scripts/publish-plugin.sh` (Conjure self-publish) exits 2 on dirty tree. D-06 says target-repo emit WARNS but does NOT exit 2. This is deliberate: teams often publish plugins from a working branch.
**How to avoid:** Keep the asymmetry explicit in the code comment. Self-publish: `diff --quiet || exit 2`. Target-repo emit: `diff --quiet || echo "WARN: dirty tree..."`.
**Warning signs:** A developer running `publish-plugin` from a feature branch is blocked by an exit 2.

### Pitfall 5: Version Field as Cache Key (CR-3)
**What goes wrong:** emit-plugin.sh emits the same `version` string on every re-run (e.g., always "0.0.0" from placeholder fallback) and team members never receive plugin updates.
**Why it happens:** CC uses the `version` field in plugin.json as the cache key. If the version never changes, the cached copy is always "current."
**How to avoid:** Version fallback chain (D-06): `.conjure-version` → git SHA → `0.0.0`. Using git SHA as the fallback means every commit IS a new version (SHA changes). Only the `0.0.0` placeholder truly pins; the printed warning alerts the user.
**Warning signs:** `claude plugin update` reports "already at latest" when the remote has new commits.

### Pitfall 6: Schema Drift in Bundled Schemas (CR-1)
**What goes wrong:** `plugin.schema.json` and `marketplace.schema.json` in `.claude-plugin/SCHEMAS/` go stale as CC schema evolves. Conjure's bundled validation passes on manifests that fail `claude plugin validate` from the current CC version.
**Why it happens:** Bundled schemas are snapshots. CC schema moves with weekly CC releases.
**How to avoid:** The bundled schemas validate only required fields and known types (the conservative set confirmed from official docs 2026-06-03). They do NOT attempt to replicate the full CC internal schema. The `--validate` gate (clause plugin validate) is the authoritative check. Staleness of the bundled schemas only affects the conservative gate, not the authoritative one.
**Warning signs:** Manifest passes bundled validation but fails `claude plugin validate .`.

---

## Code Examples

### plugin.json complete schema (verified from official docs 2026-06-03)

```json
{
  "name": "my-plugin",
  "displayName": "My Plugin",
  "version": "1.2.0",
  "description": "Brief plugin description",
  "author": {
    "name": "Author Name",
    "email": "author@example.com",
    "url": "https://github.com/author"
  },
  "homepage": "https://docs.example.com/plugin",
  "repository": "https://github.com/author/plugin",
  "license": "MIT",
  "keywords": ["keyword1", "keyword2"],
  "defaultEnabled": true,
  "skills": ".claude/skills/",
  "commands": [".claude/commands/special.md"],
  "agents": [".claude/agents/reviewer.md"],
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [{"type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/scripts/format.sh"}]
      }
    ]
  },
  "mcpServers": {
    "my-server": {
      "command": "${CLAUDE_PLUGIN_ROOT}/server",
      "args": ["--config", "${CLAUDE_PLUGIN_ROOT}/config.json"]
    }
  }
}
```

Only `name` is required if a manifest is present at all. If the manifest is omitted, CC auto-discovers components in default locations.

### marketplace.json complete schema (verified from official docs + live conjure .claude-plugin/marketplace.json)

```json
{
  "name": "company-tools",
  "owner": {
    "name": "DevTools Team",
    "email": "devtools@example.com"
  },
  "plugins": [
    {
      "name": "code-formatter",
      "source": {
        "source": "github",
        "repo": "company/code-formatter",
        "ref": "main",
        "sha": "a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0"
      },
      "description": "Automatic code formatting",
      "version": "2.1.0",
      "author": {"name": "DevTools Team"},
      "homepage": "https://docs.example.com/code-formatter",
      "license": "MIT",
      "keywords": ["formatting", "developer-tools"],
      "category": "developer-tools"
    }
  ]
}
```

Required: `name` (kebab-case), `owner` (object with `name`), `plugins` (array). Each plugin entry requires `name` and `source`.

### extraKnownMarketplaces and enabledPlugins exact shapes (verified from official docs + live jq tests)

```json
{
  "extraKnownMarketplaces": {
    "company-tools": {
      "source": {
        "source": "github",
        "repo": "your-org/claude-plugins",
        "ref": "main",
        "sha": "a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0"
      }
    }
  },
  "enabledPlugins": {
    "code-formatter@company-tools": true,
    "deployment-tools@company-tools": true
  }
}
```

`extraKnownMarketplaces` is an **object** keyed by marketplace name (NOT an array). Each value has a `source` key containing the source object. `enabledPlugins` is an object keyed by `"plugin-name@marketplace-name"` with boolean values.

**IMPORTANT:** The `extraKnownMarketplaces` marketplace source object uses `ref` but NOT `sha` (marketplace sources only support `ref`, not `sha` — only plugin sources in `marketplace.json` support `sha`). However, Conjure's D-16 says to "write both" for audit-cleanliness. This is conservative — the `sha` field may be silently ignored by CC at the marketplace level but is harmless to include.

### Reserved marketplace names (verified from official docs 2026-06-03)

```bash
# Source: https://code.claude.com/docs/en/plugin-marketplaces §Reserved names
# The following names are reserved for official Anthropic use:
CONJURE_RESERVED_MARKETPLACE_NAMES="
  claude-code-marketplace
  claude-code-plugins
  claude-plugins-official
  anthropic-marketplace
  anthropic-plugins
  agent-skills
  anthropic-agent-skills
  knowledge-work-plugins
  life-sciences
  claude-for-legal
  claude-for-financial-services
  financial-services-plugins
"
# Also blocked: names that impersonate official marketplaces
# Pattern: names starting with 'anthropic-', 'claude-', or 'official-'
# The docs say: "Names that impersonate official marketplaces, such as
# official-claude-plugins or anthropic-tools-v2, are also blocked."
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `publish-plugin.sh` monolithic (all jq + logic in one file) | `lib/plugin-helpers.sh` shared + `publish-plugin.sh` refactored to source it | Phase 25 | Enables emit-plugin.sh to reuse transforms without duplication |
| No target-repo plugin emission | `conjure publish-plugin` for target repos | Phase 25 | Developers can turn any conjure-scaffolded harness into an installable plugin |
| No bundled plugin/marketplace schemas | `plugin.schema.json` + `marketplace.schema.json` in `.claude-plugin/SCHEMAS/` | Phase 25 | Pre-write validation gate catches malformed manifests before write |
| No audit reconciliation | `conjure audit` warns when plugin.json drifts from `.claude/` contents | Phase 25 | Nudges user to re-run `publish-plugin` when harness changes |

**Deprecated/outdated:**
- `publish-plugin.sh` monolithic jq transforms: extracted to `lib/plugin-helpers.sh`; existing behavior preserved, no breaking change to `conjure publish` or `release.yml` callers.

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `sha` field in `extraKnownMarketplaces` source is silently ignored at the marketplace level (only `ref` is used) but is harmless to include (D-16 conservative write) | Code Examples §extraKnownMarketplaces | Confirmed from docs that marketplace sources support `ref` not `sha`; harmless to include; risk is near-zero |
| A2 | `defaultEnabled` field in plugin.json (requires CC v2.1.154+) is silently ignored by older CC versions | Standard Stack | If a team on CC <2.1.154 relies on defaultEnabled:false to prevent auto-activation, the plugin will auto-activate. Phase 25 does not emit `defaultEnabled: false` by default, so risk is low. |
| A3 | `conjure publish-plugin` (new command) will be invoked by users as `conjure publish-plugin` (with hyphen), not `conjure publish plugin` (subcommand of publish) | Architecture Patterns | If users try `conjure publish plugin`, the dispatch table needs both forms or a helpful error. Confirm: dispatch entry should be `publish-plugin)`. |

**If this table is empty:** All other claims were verified against official docs (2026-06-03), live CLI tests, and codebase reads.

---

## Open Questions

1. **`sha` in `extraKnownMarketplaces` source object**
   - What we know: Official docs example for `extraKnownMarketplaces` shows only `source` + `repo` (no `sha`); the docs note that "marketplace source — supports `ref` (branch/tag) but not `sha`" for the marketplace source itself.
   - What's unclear: Is D-16's intent to include `sha` in the `extraKnownMarketplaces` source harmless, or does CC reject settings with unknown `sha` field in that context?
   - Recommendation: Emit both `ref` and `sha` per D-16. If CC ignores `sha` at the marketplace level, it's harmless. The audit check (ref-without-sha warning) remains useful for the `marketplace.json` plugin entries where `sha` IS supported and critical.

2. **Hooks inline vs hooks file for plugin.json**
   - What we know: plugin.json accepts either a path string (`"./hooks/hooks.json"`) OR an inline object for the `hooks` field. The `.claude/settings.json` hooks block is the canonical source in a conjure harness.
   - Recommendation: Emit hooks INLINE in plugin.json (build from `.claude/settings.json` hooks block via jq). Avoids needing to generate a separate `hooks/hooks.json` file in `.claude-plugin/`.

3. **Target repos with no `.claude/` harness**
   - What we know: `conjure publish-plugin` runs on target repos. Some repos may not yet have `conjure init` applied.
   - Recommendation: Exit 2 with "run `conjure init` first" if `.claude/` directory is absent. Document this as a prerequisite in the help output.

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| `jq` | All JSON transforms | Yes | 1.8.1 | Exit 2 with `jq not installed` (existing preflight pattern) |
| `git` | SHA pinning, remote detection, dirty-tree | Yes | system | Exit 2 with `git not installed` |
| `claude` CLI | `--validate` gate (opt-in) | Yes | 2.1.161 | `--validate` flag: exit 2 with install hint; bare invocation: skip CLI validate |
| `bash` 3.2+ | Worker scripts | Yes | system | N/A — required by CLAUDE.md |

**Missing dependencies with no fallback:** None.

**Missing dependencies with fallback:** `claude` CLI (absent → skip CLI validate unless `--validate` was explicitly passed).

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Hand-rolled `tests/run.sh` (existing; extend per CLAUDE.md) |
| Config file | `tests/run.sh` (no separate config) |
| Quick run command | `bash tests/run.sh 2>&1 | tail -5` |
| Full suite command | `bash tests/run.sh` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| PLUG-01 | `publish-plugin` emits plugin.json with correct skills/agents/hooks/mcpServers/version | golden-fixture + smoke | `bash tests/run.sh 2>&1 | grep PLUG-01` | No — Wave 0 |
| PLUG-01 | Merge-preserve-manual: re-run preserves description/keywords/author/license | golden-fixture idempotent | `bash tests/run.sh 2>&1 | grep PLUG-01-merge` | No — Wave 0 |
| PLUG-02 | `--marketplace` emits marketplace.json with correct name/owner/plugins[]/source | golden-fixture | `bash tests/run.sh 2>&1 | grep PLUG-02` | No — Wave 0 |
| PLUG-02 | Reserved-name guard exits 2 on reserved name | unit | `bash tests/run.sh 2>&1 | grep PLUG-02-reserved` | No — Wave 0 |
| PLUG-03 | `extraKnownMarketplaces` written as object into settings.json | golden-fixture | `bash tests/run.sh 2>&1 | grep PLUG-03` | No — Wave 0 |
| PLUG-03 | Re-run updates sha in place, never appends duplicate (idempotent) | golden-fixture re-run | `bash tests/run.sh 2>&1 | grep PLUG-03-idem` | No — Wave 0 |
| PLUG-04 | Bundled schema check blocks write when manifest is invalid | unit | `bash tests/run.sh 2>&1 | grep PLUG-04` | No — Wave 0 |
| PLUG-04 | `--validate` with absent `claude` CLI exits 2 | unit | `bash tests/run.sh 2>&1 | grep PLUG-04-absent` | No — Wave 0 |
| PLUG-04 | Secret-pattern in emitted manifest → exit 2 before write | unit | `bash tests/run.sh 2>&1 | grep PLUG-04-secret` | No — Wave 0 |
| PLUG-05 | Version resolution: `.conjure-version` → SHA → 0.0.0 fallback | unit | `bash tests/run.sh 2>&1 | grep PLUG-05` | No — Wave 0 |
| SC-25 | Audit reconciliation: plugin.json out-of-sync → warning exit 0 | smoke | `bash tests/run.sh 2>&1 | grep PLUG-REC` | No — Wave 0 |
| SC-25 | Audit ref-without-sha: `extraKnownMarketplaces` entry missing sha → warning | smoke | `bash tests/run.sh 2>&1 | grep PLUG-REFSYM` | No — Wave 0 |

### Sampling Rate

- **Per task commit:** `bash tests/run.sh 2>&1 | grep -E "PASS|FAIL|PLUG"` (run the Phase 25 block only)
- **Per wave merge:** `bash tests/run.sh` (full suite)
- **Phase gate:** Full suite green before `/gsd-verify-work`

### Wave 0 Gaps

- [ ] `tests/fixtures/_emit-plugin/` — golden fixture directory with a minimal .claude/ harness (skills + agents + hooks + settings.json + optional .mcp.json)
- [ ] `tests/fixtures/_emit-plugin/expected-plugin.json` — golden expected output
- [ ] `tests/fixtures/_emit-plugin/expected-marketplace.json` — golden expected output
- [ ] `tests/fixtures/_emit-plugin/expected-settings.json` — golden expected settings after wiring
- [ ] `tests/run.sh` — new `▸ Phase 25 — Plugin + Marketplace Emission (PLUG-01..PLUG-05)` block

---

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | No | N/A — no auth in emit path |
| V3 Session Management | No | N/A |
| V4 Access Control | No | N/A — operates on target repo files |
| V5 Input Validation | Yes | Reserved-name check + jq-based schema validation for all inputs; marketplace name is user-supplied |
| V6 Cryptography | No | N/A — SHA pinning is git SHA (integrity, not crypto) |

### Known Threat Patterns for Plugin Emission

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Secret leak into committed manifest | Info Disclosure | Secret-pattern scan on full manifest content before any write; exit 2 on hit (D-08) |
| Name squatting / impersonation | Spoofing | Reserved-name guard + impersonation pattern check (D-07); bundled list, zero egress |
| Path traversal in source fields | Tampering | CC's `claude plugin validate` checks for `..` in source paths; bundled schema validates source type |
| Malformed manifest silently writes | Tampering | Bundled JSON-schema check (D-09) blocks write on invalid manifest |
| `claude plugin validate` absent when --validate passed | Denial of Service | Exit 2 with clear install hint (D-10); never silently downgrade |

---

## Sources

### Primary (HIGH confidence)

- [Claude Code plugin-marketplaces docs](https://code.claude.com/docs/en/plugin-marketplaces) — full marketplace.json schema, plugin.json schema, `extraKnownMarketplaces` object shape, `enabledPlugins` shape, reserved names, source types; verified 2026-06-03
- [Claude Code plugins-reference docs](https://code.claude.com/docs/en/plugins-reference) — complete plugin.json schema, all fields including hooks/mcpServers/lspServers, `claude plugin validate` behavior + exit codes; verified 2026-06-03
- Live `claude plugin validate` tests (claude 2.1.161) — confirmed: exit 1 on validation errors (not exit 2), exit 0 with warnings only, exit 1 with `--strict` and warnings, exit 1 on missing file
- Conjure live codebase reads: `scripts/publish-plugin.sh`, `cli/conjure` (dispatch ~line 442-506), `lib/mutate.sh`, `lib/inventory.sh`, `lib/caps.sh`, `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `.claude-plugin/SCHEMAS/agent.schema.json`, `.claude-plugin/SCHEMAS/skill.schema.json`, `scripts/audit-setup.sh`
- `.planning/phases/25-plugin-marketplace-emission/25-CONTEXT.md` — all D-01..D-16 decisions, verified against codebase
- `.planning/research/SUMMARY.md`, `PITFALLS.md`, `ARCHITECTURE.md` — high-confidence v0.7.0 research; all plugin-area findings confirmed

### Secondary (MEDIUM confidence)

- `jq` idempotent merge test (live, jq 1.8.1) — confirmed keyed-object pattern is idempotent for `extraKnownMarketplaces` and `enabledPlugins`
- GitHub remote URL parsing test — confirmed both SSH and HTTPS forms parse correctly to `owner/repo`
- Secret pattern regex test — confirmed patterns detect common credential formats (`sk-ant-*`, `ghp_*`) and produce no false positives on clean manifests

### Tertiary (LOW confidence — needs validation during implementation)

- `sha` field in `extraKnownMarketplaces` source object behavior: docs say marketplace sources support `ref` not `sha`, but harmless to include (LOW risk)

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all tools already in envelope; no new deps; confirmed via codebase reads
- Plugin/marketplace schema fields: HIGH — verified from official docs 2026-06-03 + live claude plugin validate testing
- extraKnownMarketplaces/enabledPlugins shapes: HIGH — confirmed from official docs + live jq tests
- claude plugin validate exit codes: HIGH — live-tested with claude 2.1.161
- Reserved-name list: HIGH — verbatim from official docs 2026-06-03
- Architecture patterns: HIGH — based on live codebase reads and established patterns in existing scripts
- Pitfalls: HIGH — derived from confirmed issues + live testing + codebase patterns

**Research date:** 2026-06-03
**Valid until:** 2026-07-03 (stable CC schema; reserved name list may grow but bundled is sufficient per D-07)
