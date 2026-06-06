# Phase 25: Plugin + Marketplace Emission - Pattern Map

**Mapped:** 2026-06-03
**Files analyzed:** 8 (3 new source files, 2 new schemas, 1 new fixture dir, 2 modified scripts, 1 modified CLI)
**Analogs found:** 8 / 8

---

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---|---|---|---|---|
| `lib/plugin-helpers.sh` | utility (shared lib) | transform + validate | `lib/mutate.sh`, `lib/caps.sh` | role-match |
| `scripts/emit-plugin.sh` | worker (CLI subcommand script) | request-response (CRUD write) | `scripts/publish-plugin.sh`, `scripts/audit-setup.sh` | exact |
| `cli/conjure` (MODIFY) | dispatcher | request-response | `cli/conjure` `cmd_publish` (line 442) + dispatch table (line 502) | exact |
| `scripts/publish-plugin.sh` (MODIFY) | worker (refactor) | request-response | itself — refactor to source `lib/plugin-helpers.sh` | self-analog |
| `scripts/audit-setup.sh` (MODIFY) | auditor | request-response | itself — add two new warning sections | self-analog |
| `.claude-plugin/SCHEMAS/plugin.schema.json` | schema/config | N/A | `.claude-plugin/SCHEMAS/agent.schema.json` | exact |
| `.claude-plugin/SCHEMAS/marketplace.schema.json` | schema/config | N/A | `.claude-plugin/SCHEMAS/skill.schema.json` | exact |
| `tests/fixtures/_emit-plugin/` + `tests/run.sh` block | test + fixture | N/A | MKTPL block (line 849), Phase 22 block (line 2376) | exact |

---

## Pattern Assignments

### `lib/plugin-helpers.sh` (utility, transform + validate)

**Analogs:** `lib/mutate.sh` (lib structure), `lib/caps.sh` (constants block), `scripts/publish-plugin.sh` (jq transforms)

**Lib header pattern** (`lib/mutate.sh` lines 1-6 + `lib/caps.sh` lines 1-7):
```bash
# shellcheck shell=bash
# lib/plugin-helpers.sh — shared jq transforms, validation, guards for plugin emission.
# Source this file; do not execute directly.
# Requires: lib/mutate.sh already sourced (for mutate_write).
# POSIX bash 3.2+. No associative arrays, no mapfile, no local -n.
```

**Constants block pattern** (`lib/caps.sh` lines 8-12):
```bash
# Initialize bundled constants if not already set.
# Safe under set -u; idempotent on re-source.
CONJURE_RESERVED_MARKETPLACE_NAMES="${CONJURE_RESERVED_MARKETPLACE_NAMES:-\
claude-code-marketplace claude-code-plugins claude-plugins-official \
anthropic-marketplace anthropic-plugins agent-skills anthropic-agent-skills \
knowledge-work-plugins life-sciences claude-for-legal \
claude-for-financial-services financial-services-plugins}"
```

**jq-transform-in-variable pattern** (`scripts/publish-plugin.sh` lines 85-101):
```bash
NEW_MKT="$(jq --arg sha "$CURRENT_SHA" --arg ver "$CURRENT_VERSION" \
  '.plugins[0].source.sha = $sha | .plugins[0].version = $ver' \
  "$PLUGIN_DIR/marketplace.json")"

printf '%s' "$NEW_MKT" | jq empty 2>/dev/null || {
  echo "✗ jq produced invalid JSON for marketplace.json" >&2
  exit 1
}
```
For the new helper functions the same pattern applies: build in a variable, validate with `printf '%s' "$VAR" | jq empty`, then pass to `mutate_write`.

**mutate_write call shape** (`scripts/publish-plugin.sh` lines 103-108):
```bash
mutate_write "$PLUGIN_DIR/marketplace.json" "$NEW_MKT"
echo "✓ marketplace.json updated"
mutate_write "$PLUGIN_DIR/plugin.json" "$NEW_PLG"
echo "✓ plugin.json updated"
```

**jq-based field-check validation pattern** (established by `SCHEMAS/` + used in `tests/run.sh` line 2327):
```bash
# Use jq -e for field presence checks; non-zero exit = missing = error.
if ! printf '%s' "$content" | jq -e '(.name | type) == "string"' >/dev/null 2>&1; then
  echo "✗ plugin.json: 'name' is required and must be a string" >&2
  errors=$((errors + 1))
fi
```

**exit 2 for hard failures** (`scripts/publish-plugin.sh` lines 45-48):
```bash
if ! command -v jq >/dev/null 2>&1; then
  echo "✗ jq not installed" >&2
  exit 2
fi
```

**Function return-and-caller-exits-2 pattern** (all scripts):
Functions return 1 on failure; the caller does:
```bash
reserved_name_check "$MKT_NAME" || exit 2
secret_scan "$MANIFEST_CONTENT" "plugin.json" || exit 2
validate_plugin_json "$PLUGIN_JSON" || exit 2
```

---

### `scripts/emit-plugin.sh` (worker, request-response / CRUD write)

**Analog:** `scripts/publish-plugin.sh` (lines 1-150) — exact role + data flow match

**Script header + CONJURE_HOME + source pattern** (`scripts/publish-plugin.sh` lines 1-19):
```bash
#!/usr/bin/env bash
# emit-plugin.sh — Worker script for conjure publish-plugin.
# Emits .claude-plugin/plugin.json + marketplace.json from the target repo's
# .claude/ harness. Source: lib/plugin-helpers.sh + lib/mutate.sh.
#
# Usage: bash scripts/emit-plugin.sh [--path <dir>] [--marketplace] [--enable] [--validate] [--dry-run]
#
# Exit codes:
#   0 = success
#   2 = hard prerequisite failure (missing dep, reserved name, secret in manifest, invalid schema)

set -euo pipefail

CONJURE_HOME="$(cd "$(dirname "$0")/.." && pwd)"
source "$CONJURE_HOME/lib/mutate.sh"
source "$CONJURE_HOME/lib/plugin-helpers.sh"
```

**Env defaults + arg parsing pattern** (`scripts/publish-plugin.sh` lines 21-42):
```bash
DRY_RUN="${DRY_RUN:-0}"

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
```

**command -v preflight table pattern** (`scripts/publish-plugin.sh` lines 45-53):
```bash
if ! command -v jq >/dev/null 2>&1; then
  echo "✗ jq not installed" >&2
  exit 2
fi

if ! command -v git >/dev/null 2>&1; then
  echo "✗ git not installed" >&2
  exit 2
fi
```

**Prerequisite + directory check** (`scripts/publish-plugin.sh` lines 55-59):
```bash
PLUGIN_DIR="$TARGET/.claude-plugin"
if [ ! -d "$TARGET/.claude" ]; then
  echo "✗ .claude/ not found in $TARGET — run: conjure init" >&2
  exit 2
fi
```

**ASYMMETRIC dirty-tree: warn-not-exit (D-06)** — do NOT copy the exit 2 from `publish-plugin.sh` line 63:
```bash
# emit-plugin.sh (target-repo path): dirty tree WARNS but never blocks (D-06).
# CONTRAST: scripts/publish-plugin.sh (self-publish) exits 2 on dirty tree — intentional asymmetry.
if command -v git >/dev/null 2>&1; then
  if ! git -C "$TARGET" diff --quiet 2>/dev/null || ! git -C "$TARGET" diff --cached --quiet 2>/dev/null; then
    echo "WARN: working tree has uncommitted changes — sha may not reflect emitted contents" >&2
  fi
fi
```

**mutate_summary at end** (`scripts/publish-plugin.sh` line 149):
```bash
mutate_summary
exit 0
```

**Success report + copy-pasteable verification command (D-04)** — aligned with `publish-plugin.sh` lines 104-107:
```bash
echo "▸ conjure publish-plugin: files written"
echo "  ✓ .claude-plugin/plugin.json"
echo ""
echo "▸ To verify the plugin loads:"
echo "  claude plugin validate ."
echo "  claude plugin list"
```

**harness path discovery** (mirrors `scripts/audit-setup.sh` lines 51-83 + RESEARCH.md Pattern 1):
```bash
# Skills: directories containing SKILL.md — mirror audit-setup.sh line 52
if [ -d "$TARGET/.claude/skills" ]; then
  COUNT=$(find "$TARGET/.claude/skills" -name "SKILL.md" 2>/dev/null | wc -l | tr -d ' ')
  [ "$COUNT" -gt 0 ] && SKILLS_DIR=".claude/skills"
fi

# Agents: .md files in .claude/agents/ — mirror audit-setup.sh line 76
AGENTS_JSON="[]"
if [ -d "$TARGET/.claude/agents" ]; then
  AGENTS_JSON=$(find "$TARGET/.claude/agents" -maxdepth 1 -name "*.md" 2>/dev/null \
    | sed "s|$TARGET/||" | jq -R . | jq -sc .)
fi
```

---

### `cli/conjure` (MODIFY — add `cmd_publish_plugin` + dispatch entry)

**Analog:** `cmd_publish` (lines 442-456) + `cmd_publish_skill` (lines 458-477) + dispatch table (lines 502-503)

**Thin wrapper function pattern** (`cli/conjure` lines 442-456):
```bash
cmd_publish_plugin() {
  local target dryrun do_marketplace do_enable do_validate
  target="$(pwd)"; dryrun=0; do_marketplace=0; do_enable=0; do_validate=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --path)       shift; target="${1:-}" ;;
      --path=*)     target="${1#--path=}" ;;
      --marketplace) do_marketplace=1 ;;
      --enable)     do_enable=1 ;;
      --validate)   do_validate=1 ;;
      --dry-run)    dryrun=1 ;;
      --help|-h)    echo "Usage: conjure publish-plugin [--path <dir>] [--marketplace] [--enable] [--validate] [--dry-run]"; return 0 ;;
      *)            echo "Unknown option: $1"; return 2 ;;
    esac
    shift
  done
  CONJURE_HOME="$CONJURE_HOME" DRY_RUN="$dryrun" \
    CONJURE_PLUGIN_PATH="$target" \
    CONJURE_PLUGIN_MARKETPLACE="$do_marketplace" \
    CONJURE_PLUGIN_ENABLE="$do_enable" \
    CONJURE_PLUGIN_VALIDATE="$do_validate" \
    bash "$CONJURE_HOME/scripts/emit-plugin.sh"
}
```

**Dispatch table entry** (after `publish-skill)` at line 503):
```bash
  publish-plugin)  shift; cmd_publish_plugin "$@"  ;;
```

**usage() string update** (line 46, after `conjure publish-skill ...`):
```bash
  conjure publish-plugin [--path <dir>] [--marketplace] [--enable] [--validate] [--dry-run]
```

---

### `scripts/publish-plugin.sh` (MODIFY — source `lib/plugin-helpers.sh`)

**Analog:** itself (150 lines) — minimal refactor, no behavior change

The only change is adding one `source` line after the existing `source "$CONJURE_HOME/lib/mutate.sh"` (line 18). The existing jq transforms that are promoted to `lib/plugin-helpers.sh` are replaced with function calls. The dirty-tree exit 2 and `VERSION`-required exit 2 remain unchanged (self-publish contract).

**source insertion pattern** (`scripts/publish-plugin.sh` line 18):
```bash
source "$CONJURE_HOME/lib/mutate.sh"
source "$CONJURE_HOME/lib/plugin-helpers.sh"   # ADD: shared jq transforms + guards
```

---

### `scripts/audit-setup.sh` (MODIFY — add two new warning sections)

**Analog:** itself — the overlay drift + conflict-marker warning sections (lines 154-175, 139-152) are the structural pattern for the two new advisory sections.

**Warning-section structure** (`scripts/audit-setup.sh` lines 154-175 — overlay drift check):
```bash
# Section header comment (matches criterion number)
OVERLAY_MARKER="$TARGET/.claude/.conjure-org-overlay"
if [ ! -f "$OVERLAY_MARKER" ]; then
  ok "no org overlay configured"
else
  # ... jq-based check ...
  warn "[overlay] DRIFT — ..."
fi
```

**New section 1: Plugin reconciliation (D-12)** — warn-exit-0 advisory:
```bash
# Plugin reconciliation (PLUG-04 / D-12): plugin.json out-of-sync with .claude/ harness → warn
if [ -f ".claude-plugin/plugin.json" ] && command -v jq >/dev/null 2>&1; then
  PLUGIN_SKILLS_DIR="$(jq -r '.skills // empty' .claude-plugin/plugin.json 2>/dev/null)"
  if [ -n "$PLUGIN_SKILLS_DIR" ] && [ -d ".claude/skills" ]; then
    ON_DISK_COUNT=$(find .claude/skills -name "SKILL.md" 2>/dev/null | wc -l | tr -d ' ')
    # If skills dir points at .claude/skills but skills count changed, nudge user.
    # (exact drift detection is advisory; emit-plugin.sh computes authoritative value)
    if [ "$ON_DISK_COUNT" -eq 0 ] && [ "$PLUGIN_SKILLS_DIR" != "" ]; then
      warn "plugin.json lists skills path '$PLUGIN_SKILLS_DIR' but no SKILL.md found — re-run: conjure publish-plugin"
    fi
  fi
fi
```

**New section 2: ref-without-sha check (D-12)** — uses same warn() helper:
```bash
# extraKnownMarketplaces ref-without-sha (D-16): warn if entry has ref but no sha
if [ -f ".claude/settings.json" ] && command -v jq >/dev/null 2>&1; then
  REF_WITHOUT_SHA=$(jq -r '
    (.extraKnownMarketplaces // {}) | to_entries[] |
    select((.value.source.ref != null) and (.value.source.sha == null)) |
    .key' .claude/settings.json 2>/dev/null || true)
  if [ -n "$REF_WITHOUT_SHA" ]; then
    while IFS= read -r mkt_name; do
      warn "extraKnownMarketplaces '$mkt_name': has ref but no sha — re-run: conjure publish-plugin --marketplace"
    done <<EOF
$REF_WITHOUT_SHA
EOF
  fi
fi
```

Both new sections must appear **before** the summary block (`echo "─────"...` at line 179). Both use the existing `warn()` helper (line 20) — exit code stays advisory at exit 1 (WARN > 0), never exit 2.

---

### `.claude-plugin/SCHEMAS/plugin.schema.json` (NEW schema/config)

**Analog:** `.claude-plugin/SCHEMAS/agent.schema.json` (lines 1-15) — exact structural match

**Schema file pattern** (`agent.schema.json` lines 1-15):
```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://conjure.dev/schemas/agent.schema.json",
  "title": "Conjure Subagent YAML Frontmatter",
  "type": "object",
  "required": ["name", "description"],
  "additionalProperties": false,
  "properties": {
    "name": { "type": "string", "pattern": "^[a-z][a-z0-9-]{1,40}$" },
    ...
  }
}
```

Apply to `plugin.schema.json`:
```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://conjure.dev/schemas/plugin.schema.json",
  "title": "Claude Code plugin.json",
  "description": "Validates .claude-plugin/plugin.json. Only 'name' is required; all other fields are optional.",
  "type": "object",
  "required": ["name"],
  "properties": {
    "name":        { "type": "string" },
    "displayName": { "type": "string" },
    "version":     { "type": "string" },
    "description": { "type": "string" },
    "author":      { "type": ["object", "string"] },
    "homepage":    { "type": "string" },
    "repository":  { "type": ["object", "string"] },
    "license":     { "type": "string" },
    "keywords":    { "type": "array", "items": { "type": "string" } },
    "defaultEnabled": { "type": "boolean" },
    "skills":      { "type": "string" },
    "commands":    { "type": "array", "items": { "type": "string" } },
    "agents":      { "type": "array", "items": { "type": "string" } },
    "hooks":       { "type": "object" },
    "mcpServers":  { "type": "object" }
  }
}
```
Note: do NOT set `"additionalProperties": false` — the CC plugin.json schema evolves and unknown fields must be tolerated (per RESEARCH.md Pitfall 6).

---

### `.claude-plugin/SCHEMAS/marketplace.schema.json` (NEW schema/config)

**Analog:** `.claude-plugin/SCHEMAS/skill.schema.json` (lines 1-38) — same structure, different required fields

Apply to `marketplace.schema.json`:
```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://conjure.dev/schemas/marketplace.schema.json",
  "title": "Claude Code marketplace.json",
  "description": "Validates .claude-plugin/marketplace.json (Conjure-emitted target-repo marketplace).",
  "type": "object",
  "required": ["name", "owner", "plugins"],
  "properties": {
    "name":        { "type": "string", "pattern": "^[a-z][a-z0-9-]{0,63}$" },
    "description": { "type": "string" },
    "owner": {
      "type": "object",
      "required": ["name"],
      "properties": {
        "name":  { "type": "string" },
        "email": { "type": "string" }
      }
    },
    "plugins": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["name", "source"],
        "properties": {
          "name":        { "type": "string" },
          "description": { "type": "string" },
          "version":     { "type": "string" },
          "source":      { "type": "object" },
          "author":      { "type": ["object", "string"] },
          "homepage":    { "type": "string" },
          "repository":  { "type": ["object", "string"] },
          "license":     { "type": "string" },
          "keywords":    { "type": "array", "items": { "type": "string" } },
          "category":    { "type": "string" }
        }
      }
    }
  }
}
```

---

### `tests/run.sh` (MODIFY — Phase 25 block) + `tests/fixtures/_emit-plugin/`

**Analogs:** MKTPL block (lines 849-983) for sandbox-in-mktemp + git-init + pass/fail shape; Phase 22 block header (lines 2376-2406) for presence-guard + block comment style; Phase 24 header (lines 3299-3315) for the inter-phase-guard pattern.

**Phase block header comment pattern** (`tests/run.sh` lines 2376-2383):
```bash
# ──────────────────────────────────────────────────────────────────────────────
# Phase 25 — Plugin + Marketplace Emission (PLUG-01..PLUG-05)
# Mirrors Phase 22/24 block style: `▸ Phase 25 — ...` headers, pass/fail
# helpers, mktemp sandboxes with EXIT-trap discipline. Every emit invocation
# guarded behind P25_EMIT_OK so the suite reports graceful RED when
# scripts/emit-plugin.sh is absent (Wave 1 not yet complete).
# ──────────────────────────────────────────────────────────────────────────────
```

**Presence guard pattern** (`tests/run.sh` lines 2385-2388):
```bash
P25_EMIT_SH="$CONJURE_HOME/scripts/emit-plugin.sh"
P25_EMIT_OK=0
[ -f "$P25_EMIT_SH" ] && P25_EMIT_OK=1
```

**Git-init sandbox pattern for emit tests** (mirrors MKTPL block lines 855-867):
```bash
P25_TARGET="$(mktemp -d)"
trap 'rm -rf "$P25_TARGET"' EXIT
git -C "$P25_TARGET" init -q
git -C "$P25_TARGET" config user.email "test@conjure"
git -C "$P25_TARGET" config user.name "conjure-test"
# Populate minimal .claude/ harness from fixture
cp -r "$CONJURE_HOME/tests/fixtures/_emit-plugin/harness/." "$P25_TARGET/"
git -C "$P25_TARGET" add -A
git -C "$P25_TARGET" commit -q -m "test fixture"
```

**Pass/fail assertion pattern** (lines 871-883):
```bash
P25_OUT="$(DRY_RUN=1 CONJURE_HOME="$CONJURE_HOME" bash "$P25_EMIT_SH" 2>&1)"
if printf '%s\n' "$P25_OUT" | grep -q 'dry-run'; then
  pass "emit-plugin dry-run prints dry-run mutations (PLUG-01)"
else
  fail "emit-plugin dry-run did not print dry-run output (PLUG-01)"
fi
```

**Golden-fixture idempotency pattern** (mirrors MKTPL lines 877-883):
```bash
# PLUG-03-idem: run emit twice, settings.json must be identical
bash "$P25_EMIT_SH" --path "$P25_IDEM_TARGET" --marketplace >/dev/null 2>&1
AFTER_FIRST="$(cat "$P25_IDEM_TARGET/.claude/settings.json")"
bash "$P25_EMIT_SH" --path "$P25_IDEM_TARGET" --marketplace >/dev/null 2>&1
AFTER_SECOND="$(cat "$P25_IDEM_TARGET/.claude/settings.json")"
if [ "$AFTER_FIRST" = "$AFTER_SECOND" ]; then
  pass "emit-plugin --marketplace idempotent: re-run produces identical settings.json (PLUG-03-idem)"
else
  fail "emit-plugin --marketplace not idempotent: settings.json differs on second run (PLUG-03-idem)"
fi
```

**Fixture structure** (`tests/fixtures/_emit-plugin/`):
```
tests/fixtures/_emit-plugin/
  harness/                     # minimal .claude/ harness to copy into sandboxes
    CLAUDE.md                  # ≤100-line stub
    .claude/
      skills/git/SKILL.md      # one skill (mirrors _brownfield-simple pattern)
      agents/code-explorer.md  # one agent
      settings.json            # hooks block + empty extraKnownMarketplaces
    .mcp.json                  # minimal mcpServers block
    .conjure-version           # pinned version string (e.g. "0.1.0")
  expected-plugin.json         # golden: what emit-plugin should produce
  expected-marketplace.json    # golden: what --marketplace should produce
  expected-settings.json       # golden: what --marketplace wired settings looks like
```

---

## Shared Patterns

### exit 2 (Never exit 1) for Hard Failures
**Source:** `scripts/publish-plugin.sh` lines 45-53, `cli/conjure` line 506, CLAUDE.md §Conventions
**Apply to:** All new scripts — `emit-plugin.sh`, `lib/plugin-helpers.sh` callers
```bash
# Hard prerequisite failure → exit 2. Validation error blocking write → exit 2.
# exit 1 is NOT used; only exit 0 (success) and exit 2 (hard failure).
```

### command -v Preflight for Missing Deps
**Source:** `scripts/publish-plugin.sh` lines 45-53
**Apply to:** `scripts/emit-plugin.sh` (jq, git), `lib/plugin-helpers.sh` (claude CLI)
```bash
if ! command -v jq >/dev/null 2>&1; then
  echo "✗ jq not installed" >&2
  exit 2
fi
```

### mutate_write for ALL Filesystem Writes
**Source:** `lib/mutate.sh` lines 53-67, `scripts/publish-plugin.sh` lines 103-108
**Apply to:** Every write in `scripts/emit-plugin.sh` and `lib/plugin-helpers.sh`
```bash
mutate_write "$DEST_FILE" "$JSON_CONTENT"
```
Never use `>` redirect directly; never bypass for dry-run awareness.

### warn() / ok() / err() Helpers from audit-setup.sh
**Source:** `scripts/audit-setup.sh` lines 18-21
**Apply to:** New audit sections in `scripts/audit-setup.sh`
```bash
ok()   { note "✓ $1"; PASS=$((PASS+1)); }
warn() { note "⚠ $1"; WARN=$((WARN+1)); }
err()  { note "✗ $1"; FAIL=$((FAIL+1)); }
```
New reconciliation sections use `warn()` only (exit 0 advisory, D-12).

### set -euo pipefail + CONJURE_HOME Derivation
**Source:** `scripts/publish-plugin.sh` lines 15-17
**Apply to:** `scripts/emit-plugin.sh`
```bash
set -euo pipefail
CONJURE_HOME="$(cd "$(dirname "$0")/.." && pwd)"
source "$CONJURE_HOME/lib/mutate.sh"
```

### mutate_summary at Script End
**Source:** `scripts/publish-plugin.sh` line 149
**Apply to:** `scripts/emit-plugin.sh`
```bash
mutate_summary
exit 0
```

### jq Empty-Check Before mutate_write
**Source:** `scripts/publish-plugin.sh` lines 89-92
**Apply to:** Every generated JSON blob in `emit-plugin.sh` before writing
```bash
printf '%s' "$NEW_JSON" | jq empty 2>/dev/null || {
  echo "✗ jq produced invalid JSON for <file>" >&2
  exit 2
}
```

### find-based Harness Enumeration
**Source:** `scripts/audit-setup.sh` lines 52, 76
**Apply to:** `scripts/emit-plugin.sh` harness path discovery
```bash
find .claude/skills -name "SKILL.md" 2>/dev/null | wc -l | tr -d ' '
find .claude/agents -maxdepth 1 -name '*.md' 2>/dev/null | wc -l | tr -d ' '
```

---

## Critical Asymmetries to Preserve (Do NOT "Fix")

| File | Asymmetry | Reason |
|---|---|---|
| `scripts/emit-plugin.sh` | Dirty tree → WARN, not exit 2 | D-06: target-repo emit must not block on feature branches |
| `scripts/publish-plugin.sh` | Dirty tree → exit 2 (unchanged) | Self-publish contract; called by `release.yml` |
| `scripts/emit-plugin.sh` | `claude plugin validate` exits 1 on error → translate to conjure exit 2 | CC exit codes differ from conjure convention (RESEARCH.md Pitfall 1) |
| `scripts/audit-setup.sh` new sections | Both new sections use `warn()`, not `err()` | D-12: advisory only, exit 0 not affected |

---

## No Analog Found

All files have close analogs in the codebase. No files in this phase lack a structural match.

---

## Metadata

**Analog search scope:** `lib/`, `scripts/`, `cli/`, `.claude-plugin/SCHEMAS/`, `tests/`
**Files read:** `scripts/publish-plugin.sh`, `lib/mutate.sh`, `lib/caps.sh`, `cli/conjure` (lines 1-60, 193-260, 430-507), `scripts/audit-setup.sh`, `.claude-plugin/SCHEMAS/agent.schema.json`, `.claude-plugin/SCHEMAS/skill.schema.json`, `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `lib/inventory.sh` (lines 1-80), `tests/run.sh` (lines 849-983, 1700-1780, 2376-2420, 3295-3365, tail-100)
**Pattern extraction date:** 2026-06-03
