# Phase 26: Sandbox + Managed-Settings / MDM - Pattern Map

**Mapped:** 2026-06-03
**Files analyzed:** 9 new/modified files
**Analogs found:** 9 / 9

---

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `lib/policy-helpers.sh` | utility/library | transform (JSON build + validate) | `lib/plugin-helpers.sh` | exact |
| `scripts/emit-policy.sh` | worker | request-response (CLI → filesystem write) | `scripts/emit-plugin.sh` | exact |
| `cli/conjure` (MODIFY) | CLI dispatcher | request-response | `cmd_publish_plugin` block in `cli/conjure` (lines 480–507) | exact |
| `scripts/audit-setup.sh` (MODIFY) | audit worker | request-response (read + check + report) | existing plugin reconciliation + ref-without-sha blocks (lines 177–217) | exact |
| `compliance/hipaa/policy.sh` (NEW) | config/data | transform (sourced data) | `compliance/hipaa/apply.sh` (file structure) | role-match |
| `compliance/soc2/policy.sh` (NEW) | config/data | transform (sourced data) | `compliance/soc2/apply.sh` | role-match |
| `compliance/gdpr/policy.sh` (NEW) | config/data | transform (sourced data) | `compliance/gdpr/apply.sh` | role-match |
| `compliance/pci/policy.sh` (NEW) | config/data | transform (sourced data) | `compliance/pci/apply.sh` | role-match |
| `tests/fixtures/_emit-policy*/` (NEW) + `tests/run.sh` (MODIFY) | test | CRUD (fixture-based regression) | `tests/fixtures/_emit-plugin/` + Phase 25 PLUG-01..PLUG-05 blocks (lines 3984–4358) | exact |

---

## Pattern Assignments

### `lib/policy-helpers.sh` (utility, transform)

**Analog:** `lib/plugin-helpers.sh`

**File header and source conventions** (`lib/plugin-helpers.sh` lines 1–6):
```bash
# shellcheck shell=bash
# lib/policy-helpers.sh — shared jq builders, validators, and merge logic for policy emission.
# Source this file; do not execute directly.
# Requires: lib/mutate.sh already sourced (for mutate_write, dry-run awareness).
# POSIX bash 3.2+. No associative arrays, no mapfile, no local -n.
```

**Core jq-validate gate pattern** (`lib/plugin-helpers.sh` lines 59–103):
```bash
validate_plugin_json() {
  local content="$1"
  local errors=0

  if ! printf '%s' "$content" | jq -e '(.name | type) == "string" and (.name | length > 0)' >/dev/null 2>&1; then
    echo "✗ plugin.json: 'name' is required and must be a non-empty string" >&2
    errors=$((errors + 1))
  fi

  if ! printf '%s' "$content" | jq -e 'if .agents then (.agents | type) == "array" else true end' >/dev/null 2>&1; then
    echo "✗ plugin.json: 'agents' must be an array" >&2
    errors=$((errors + 1))
  fi

  [ "$errors" -gt 0 ] && return 1
  return 0
}
```
Copy this per-field error accumulator pattern into `validate_sandbox_json` and `validate_managed_settings_json`. CRITICAL difference: `validate_managed_settings_json` must check `(.permissions.disableBypassPermissionsMode | type) == "string"` — using `jq -r '... | type'` and then a shell `[ "$type" = "boolean" ]` check (see RESEARCH.md Pattern 1 / Code Examples).

**Merge-base `.` idempotent jq pattern** (`lib/plugin-helpers.sh` lines 280–318):
```bash
local updated
updated=$(printf '%s' "$existing" | jq \
  --arg version "$version" \
  --argjson agents "$agents_json" \
  '. as $orig |
   ...
   .version = $version |
   (if ($agents | length) > 0 then .agents = $agents else . end)')

# jq-empty-check before returning
printf '%s' "$updated" | jq empty 2>/dev/null || {
  echo "✗ jq produced invalid JSON for plugin.json" >&2
  return 1
}

printf '%s' "$updated"
```
The merge base is ALWAYS `. as $orig` (existing object), never `{}`. For the sandbox merge, the caller reads existing settings.json into `$CURRENT` then calls this function. For array fields (`denyRead`, `denyWrite`, `allowedDomains`), use explicit union as shown in RESEARCH.md Pattern 1 — do NOT use `.*` which replaces arrays.

**CRITICAL: Array merge for idempotency.** The `.*` jq operator replaces arrays, not concatenates them. For `sandbox.filesystem.denyRead` and similar array fields, use (from RESEARCH.md Pattern 1):
```bash
def array_merge(a; b): (a // []) + (b // []) | unique;
.sandbox.filesystem.denyRead = array_merge($old.filesystem.denyRead; $new.filesystem.denyRead)
```

**secret_scan pattern** (`lib/plugin-helpers.sh` lines 36–54):
```bash
secret_scan() {
  local content="$1"
  local label="${2:-emitted manifest}"
  local patterns
  patterns='sk-ant-[A-Za-z0-9_-]{10,}|sk-[A-Za-z0-9_-]{32,}|...'
  if printf '%s' "$content" | grep -qiE "$patterns" 2>/dev/null; then
    echo "BLOCK: $label appears to contain a credential pattern — remove from env/values before emitting." >&2
    return 1
  fi
  return 0
}
```
Extend to cover managed-settings content before write (see RESEARCH.md Security Domain: "Secret in emitted managed-settings.json").

---

### `scripts/emit-policy.sh` (worker, request-response)

**Analog:** `scripts/emit-plugin.sh`

**File header + shebang + set + source block** (`scripts/emit-plugin.sh` lines 1–19):
```bash
#!/usr/bin/env bash
# emit-policy.sh — Worker script for conjure emit-policy.
# Emits sandbox block into .claude/settings.json, managed-settings.json,
# com.anthropic.claudecode.plist, Set-ClaudeCodePolicy.ps1, and VERIFY.txt.
# Called by cli/conjure cmd_emit_policy.
#
# Usage: bash scripts/emit-policy.sh [options]
# Options: --regime hipaa|soc2|gdpr|pci  --output DIR  --managed-only  --mdm-only  --dry-run
# Exit codes: 0 = success; 2 = hard failure
#
# shellcheck shell=bash

set -euo pipefail

CONJURE_HOME="$(cd "$(dirname "$0")/.." && pwd)"
source "$CONJURE_HOME/lib/mutate.sh"
source "$CONJURE_HOME/lib/log.sh"
source "$CONJURE_HOME/lib/snapshot.sh"
source "$CONJURE_HOME/lib/policy-helpers.sh"
```

**Env defaults + arg parsing** (`scripts/emit-plugin.sh` lines 21–55):
```bash
DRY_RUN="${DRY_RUN:-0}"
TARGET="${CONJURE_POLICY_TARGET:-$(pwd)}"
REGIME="${CONJURE_POLICY_REGIME:-}"
OUTPUT_DIR="${CONJURE_POLICY_OUTPUT:-}"
MANAGED_ONLY=0
MDM_ONLY=0

while [ $# -gt 0 ]; do
  case "$1" in
    --regime)      shift; REGIME="${1:-}" ;;
    --regime=*)    REGIME="${1#--regime=}" ;;
    --output)      shift; OUTPUT_DIR="${1:-}" ;;
    --output=*)    OUTPUT_DIR="${1#--output=}" ;;
    --managed-only) MANAGED_ONLY=1 ;;
    --mdm-only)    MDM_ONLY=1 ;;
    --dry-run)     DRY_RUN=1 ;;
    -h|--help)
      echo "Usage: conjure emit-policy --regime hipaa|soc2|gdpr|pci [--output DIR] [--managed-only|--mdm-only] [--dry-run]"
      exit 0 ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 2 ;;
  esac
  shift
done
```

**jq preflight** (`scripts/emit-plugin.sh` lines 52–55):
```bash
if ! command -v jq >/dev/null 2>&1; then
  echo "✗ jq not installed" >&2
  exit 2
fi
```

**snapshot-before-mutate gate** (`scripts/emit-plugin.sh` lines 96–102):
```bash
if [ "${DRY_RUN:-0}" != "1" ] && { [ -f "$TARGET/.claude-plugin/plugin.json" ] || \
   [ -f "$TARGET/.claude/settings.json" ]; }; then
  snapshot_create "$TARGET" "$TARGET/.conjure-adopt-backups"
  echo "▸ backup created: $CONJURE_SNAPSHOT_PATH"
fi
```
For emit-policy: snapshot when `.claude/settings.json` exists (it will be mutated by the sandbox block merge). Use the same backup root convention: `"$TARGET/.conjure-adopt-backups"`.

**validate-before-write discipline** (`scripts/emit-plugin.sh` lines 87–92):
```bash
# Validate BEFORE any write — exit 2 on invalid, never write then validate
secret_scan "$PLUGIN_JSON" "plugin.json" || exit 2
validate_plugin_json "$PLUGIN_JSON" || exit 2
# ...then mutate_write
mutate_write "$TARGET/.claude-plugin/plugin.json" "$PLUGIN_JSON"
```
Apply identically: `validate_sandbox_json "$SANDBOX_JSON" || exit 2` and `validate_managed_settings_json "$MANAGED_JSON" || exit 2` before any `mutate_write`.

**Success report pattern** (`scripts/emit-plugin.sh` lines 166–181):
```bash
echo "▸ conjure publish-plugin: files written"
echo "  ✓ .claude-plugin/plugin.json"
echo ""
echo "▸ To verify the plugin loads:"
echo "  claude plugin validate ."
mutate_summary
exit 0
```
Mirror for emit-policy: list all written files, print VERIFY.txt path, always call `mutate_summary` before `exit 0`.

---

### `cli/conjure` (MODIFY — add `cmd_emit_policy` + dispatch)

**Analog:** `cmd_publish_plugin` function + dispatch entry (`cli/conjure` lines 480–534)

**Usage line** (line 47 context):
```bash
conjure publish-plugin [--path <dir>] [--marketplace] [--enable] [--validate] [--dry-run]
```
Add directly below (same indentation):
```bash
conjure emit-policy --regime hipaa|soc2|gdpr|pci [--output DIR] [--managed-only|--mdm-only] [--dry-run]
```

**cmd function pattern** (`cli/conjure` lines 480–507):
```bash
cmd_publish_plugin() {
  local target dryrun do_marketplace do_enable do_validate mkt_name
  target="$(pwd)"; dryrun=0; do_marketplace=0; do_enable=0; do_validate=0; mkt_name=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --path)        shift; target="${1:-}" ;;
      --path=*)      target="${1#--path=}" ;;
      --marketplace) do_marketplace=1 ;;
      --dry-run)     dryrun=1 ;;
      --help|-h)
        echo "Usage: conjure publish-plugin [--path <dir>] [--name <kebab-name>] [--marketplace] [--enable] [--validate] [--dry-run]"
        return 0 ;;
      *) echo "Unknown option: $1"; return 2 ;;
    esac
    shift
  done
  CONJURE_HOME="$CONJURE_HOME" DRY_RUN="$dryrun" \
    CONJURE_PLUGIN_PATH="$target" \
    CONJURE_PLUGIN_MARKETPLACE="$do_marketplace" \
    bash "$CONJURE_HOME/scripts/emit-plugin.sh"
}
```
Mirror as `cmd_emit_policy` with vars `CONJURE_POLICY_REGIME`, `CONJURE_POLICY_OUTPUT`, `CONJURE_POLICY_MANAGED_ONLY`, `CONJURE_POLICY_MDM_ONLY`.

**Dispatch block** (`cli/conjure` lines 520–538):
```bash
case "${1:-help}" in
  ...
  publish-plugin)  shift; cmd_publish_plugin "$@"  ;;
  version|-v|--version) cmd_version                ;;
  ...
esac
```
Insert `emit-policy)   shift; cmd_emit_policy "$@"   ;;` before the `version` line.

---

### `scripts/audit-setup.sh` (MODIFY — add POL-05 checks)

**Analog:** plugin reconciliation advisory block + exit-code-based `err()` pattern (`scripts/audit-setup.sh` lines 1–22, 177–217, 338–340)

**Function definitions** (lines 18–21):
```bash
note() { echo "  $1"; }
ok()   { note "✓ $1"; PASS=$((PASS+1)); }
warn() { note "⚠ $1"; WARN=$((WARN+1)); }
err()  { note "✗ $1"; FAIL=$((FAIL+1)); }
```
- `err()` — increments FAIL; `[ "$FAIL" -gt 0 ] && exit 2` fires at line 338.
- `warn()` — increments WARN; `[ "$WARN" -gt 0 ] && exit 1` fires at line 339.
- `note()` — zero-cost advisory, no counter increment, exit remains 0.

**Phase 25 lesson (from CONTEXT.md):** Use `err()` for POL-05a, POL-05b, POL-05c (hard correctness — increments FAIL, triggers exit 2). Use `note "⚠ ..."` (NOT `warn()`) for the "unreviewed template" advisory so audit exits 0 for advisory-only findings.

**Advisory block pattern** (lines 177–217) — the exact structural template for new policy blocks:
```bash
# Plugin reconciliation (D-12 / PLUG-04): plugin.json out-of-sync with .claude/ harness → advisory note (exit 0)
# Advisory only — does not break CI gate.
if [ -f ".claude-plugin/plugin.json" ] && command -v jq >/dev/null 2>&1; then
  PLUG_SKILLS_PATH="$(jq -r '.skills // empty' .claude-plugin/plugin.json 2>/dev/null)"
  if [ -n "$PLUG_SKILLS_PATH" ]; then
    if [ -d "$PLUG_SKILLS_PATH" ]; then
      ...
      note "⚠ [plugin] plugin.json lists skills path '$PLUG_SKILLS_PATH' but no SKILL.md found — re-run: conjure publish-plugin"
    else
      note "⚠ [plugin] plugin.json lists skills path '$PLUG_SKILLS_PATH' but directory not found — re-run: conjure publish-plugin"
    fi
  fi
fi
```

**Marker detection pattern** for POL-05 (from RESEARCH.md Pattern 6):
```bash
_pol_regime="$(grep -oE '<!-- compliance:(hipaa|soc2|gdpr|pci) -->' CLAUDE.md 2>/dev/null \
  | sed 's/<!-- compliance://;s/ -->//' | head -1)"
```
Gate all three `err()` checks and the advisory `note` behind `[ -f ".claude/settings.json" ] && command -v jq >/dev/null 2>&1`.

**Insertion point:** After line 217 (end of existing `extraKnownMarketplaces` ref-without-sha block) and before line 219 (the `# Summary` echo). This matches how Phase 25 attached plugin checks — after the overlay drift block, before the summary.

**Hard-fail exit** (line 338): `[ "$FAIL" -gt 0 ] && exit 2` — already present; do not duplicate. Adding `err()` calls automatically feeds into this gate.

---

### `compliance/<regime>/policy.sh` (NEW × 4)

**Analog:** `compliance/hipaa/apply.sh` (file structure + sourcing convention)

**apply.sh sourcing convention** (`compliance/hipaa/apply.sh` lines 1–5):
```bash
#!/usr/bin/env bash
set -uo pipefail
TARGET="${1:-$(pwd)}"
PROFILE_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$CONJURE_HOME/lib/mutate.sh"
```
`policy.sh` files are DATA files sourced by `emit-policy.sh` (not executed directly). They do NOT need a shebang or `set -euo pipefail`. They follow this pattern:

```bash
# shellcheck shell=bash
# compliance/hipaa/policy.sh — regime deny-path data for conjure emit-policy.
# Source this file; do not execute directly.
# Sets: REGIME_DENY_READ (space-separated), REGIME_DENY_WRITE, REGIME_ALLOWED_DOMAINS.
# POSIX bash 3.2+. No associative arrays.

# Per-regime deny paths (PHI paths for HIPAA).
# Baseline paths (secrets/keys/.env) are added by emit-policy.sh from the shared baseline.
REGIME_DENY_READ="
**/phi
**/phi/**
**/patient*
**/medical*
**/health-records/**
**/ehr/**
**/mrn*
**/ssn*
**/dob*
"

REGIME_DENY_WRITE="
**/phi/**
**/patient*
"

REGIME_ALLOWED_DOMAINS=""
```
Note: Use newline-separated strings (not arrays) for POSIX 3.2+ compatibility. `emit-policy.sh` will convert them to JSON arrays with `printf '%s' "$REGIME_DENY_READ" | jq -R . | jq -sc .`.

**CLAUDE.md.fragment marker** (`compliance/hipaa/CLAUDE.md.fragment` lines 1–2):
```
<!-- compliance:hipaa -->
```
This marker is already emitted by the existing `apply.sh`. The audit detection (`grep -oE '<!-- compliance:(hipaa|soc2|gdpr|pci) -->'`) reads CLAUDE.md for this marker — `policy.sh` does not need to emit it.

---

### `tests/run.sh` (MODIFY) + `tests/fixtures/_emit-policy*/` (NEW)

**Analog:** Phase 25 PLUG-01..PLUG-05 test blocks (`tests/run.sh` lines 3984–4358) + `tests/fixtures/_emit-plugin/` fixture structure

**Phase block header pattern** (lines 3984–3997):
```bash
# Phase 26 — Sandbox + Managed-Settings / MDM (POL-01..POL-05)
# Mirrors Phase 25 block style: `▸ Phase 26 — ...` headers, pass/fail
# helpers, mktemp sandboxes with EXIT-trap discipline. Every emit invocation
# guarded behind P26_EMIT_OK so the suite reports graceful RED when
# scripts/emit-policy.sh is absent (Wave 0 not yet complete).
# ─────────────────────────────────────────────────────────────────────────────

P26_EMIT_SH="$CONJURE_HOME/scripts/emit-policy.sh"
P26_AUDIT_SH="$CONJURE_HOME/scripts/audit-setup.sh"
P26_EMIT_OK=0
[ -f "$P26_EMIT_SH" ] && P26_EMIT_OK=1

echo
echo "▸ Phase 26 — Sandbox + Managed-Settings / MDM (POL-01..POL-05)"
```

**Per-test mktemp sandbox pattern** (lines 4000–4019):
```bash
P25_PLUG01_DIR="$(mktemp -d)"
trap 'rm -rf "$P25_PLUG01_DIR"' EXIT
git -C "$P25_PLUG01_DIR" init -q
git -C "$P25_PLUG01_DIR" config user.email "test@conjure"
git -C "$P25_PLUG01_DIR" config user.name "conjure-test"
cp -r "$CONJURE_HOME/tests/fixtures/_emit-plugin/harness/." "$P25_PLUG01_DIR/"
git -C "$P25_PLUG01_DIR" add -A
git -C "$P25_PLUG01_DIR" commit -q -m "test fixture"
if [ "$P25_EMIT_OK" -eq 1 ]; then
  CONJURE_HOME="$CONJURE_HOME" bash "$P25_EMIT_SH" --path "$P25_PLUG01_DIR" >/dev/null 2>&1
  if jq -e '.name and .skills' "$P25_PLUG01_DIR/.claude-plugin/plugin.json" >/dev/null 2>&1; then
    pass "emit-plugin produces plugin.json with correct fields (PLUG-01)"
  else
    fail "emit-plugin plugin.json missing required fields (PLUG-01)"
  fi
else
  fail "emit-plugin.sh not found — Wave 1 must create scripts/emit-plugin.sh (PLUG-01)"
fi
rm -rf "$P25_PLUG01_DIR"
trap - EXIT
```
Mirror this exactly: every test uses `mktemp -d`, sets `trap 'rm -rf "$P26_xxx_DIR"' EXIT`, calls `trap - EXIT` after cleanup, and guards invocations behind `[ "$P26_EMIT_OK" -eq 1 ]`.

**Advisory audit test pattern** (lines 4319–4337) for the advisory `note()` check (POL-05-advisory):
```bash
P25_REC_OUT=0
PLUG_REC_OUT="$(CONJURE_HOME="$CONJURE_HOME" bash "$P25_AUDIT_SH" "$P25_REC_DIR" 2>&1)" || P25_REC_OUT=$?
if [ "$P25_REC_OUT" -eq 0 ] && printf '%s\n' "$PLUG_REC_OUT" | grep -q "publish-plugin"; then
  pass "audit-setup warns about plugin.json skills path with no SKILL.md (PLUG-REC)"
else
  fail "audit-setup did not warn about skills path drift — rc=$P25_REC_OUT (PLUG-REC)"
fi
```
For advisory (POL-05-advisory / unreviewed template): assert `rc=0` AND output contains `REPLACE_WITH_ORG_UUID`.
For hard-fail checks (POL-05a/b/c): assert `rc=2` AND output contains the specific error string (e.g., `"sandbox.enabled"`).

**Fixture file structure** (mirror of `tests/fixtures/_emit-plugin/`):

`tests/fixtures/_emit-policy/harness/CLAUDE.md`:
```markdown
## Project

Test harness for conjure emit-policy fixture.

<!-- compliance:hipaa -->
```

`tests/fixtures/_emit-policy/harness/.claude/settings.json`:
```json
{
  "hooks": {}
}
```
(Minimal valid settings.json with NO existing sandbox block — emit-policy must create it.)

`tests/fixtures/_emit-policy-broken/harness/.claude/settings.json`:
```json
{
  "permissions": {
    "disableBypassPermissionsMode": true
  }
}
```
(Wrong type: boolean instead of string — for POL-05c negative test.)

`tests/fixtures/_emit-policy-unreviewed/conjure-policy/managed-settings.json`:
```json
{
  "permissions": {
    "disableBypassPermissionsMode": "disable"
  },
  "forceLoginOrgUUID": "REPLACE_WITH_ORG_UUID",
  "_conjure_unreviewed": true
}
```
(Contains placeholder — for POL-05-advisory test.)

---

## Shared Patterns

### mutate_write (ALL file-writing scripts)

**Source:** `lib/mutate.sh` lines 49–67
```bash
mutate_write() {
  local dest="$1"
  local content="$2"
  local mode="${3:-}"
  if [ "${DRY_RUN:-0}" = "1" ]; then
    echo "[dry-run] would write $dest"
    CONJURE_DRY_MUTATION_COUNT=$((CONJURE_DRY_MUTATION_COUNT + 1))
    return 0
  fi
  if [ "$mode" = "--append" ]; then
    printf '%s' "$content" >> "$dest"
  else
    printf '%s' "$content" > "$dest"
  fi
}
```
**Apply to:** `scripts/emit-policy.sh` for every file write. Pass content as a string argument — never pipe (piping loses the dry-run counter).

### snapshot_create (backup-before-mutate)

**Source:** `lib/snapshot.sh` lines 17–83
```bash
snapshot_create "$TARGET" "$TARGET/.conjure-adopt-backups"
echo "▸ backup created: $CONJURE_SNAPSHOT_PATH"
```
**Apply to:** `scripts/emit-policy.sh` before the first `mutate_write` call that modifies `.claude/settings.json`. Condition: `[ "${DRY_RUN:-0}" != "1" ] && [ -f "$TARGET/.claude/settings.json" ]`.

### exit 2 never exit 1 (ALL scripts)

**Source:** CLAUDE.md conventions; enforced by `[ "$FAIL" -gt 0 ] && exit 2` at `scripts/audit-setup.sh` line 338.

All scripts and CLI functions use `exit 2` for hard failures, `return 2` from functions. Never `exit 1` in worker scripts.

### jq validate-before-write (ALL JSON emission)

**Source:** `lib/plugin-helpers.sh` lines 311–316 + `scripts/emit-plugin.sh` lines 87–91
```bash
printf '%s' "$updated" | jq empty 2>/dev/null || {
  echo "✗ jq produced invalid JSON for settings.json" >&2
  return 1
}
```
**Apply to:** Every JSON string before passing to `mutate_write`. This catches jq pipeline bugs (malformed input, bad `--argjson` values) before they corrupt the target file.

### POSIX 3.2+ shell safety (ALL bash scripts)

**Source:** CLAUDE.md; verified throughout `lib/plugin-helpers.sh` and `scripts/emit-plugin.sh`.

- No associative arrays (`declare -A`)
- No `mapfile`/`readarray`
- No `local -n`
- Use `printf '%s' "$var"` not `echo "$var"` for content output
- Use POSIX ERE with `grep -E`; avoid `\s` (use `[[:space:]]` instead — `\s` matches literal `s` under BSD/macOS `grep -E`, as documented in `lib/plugin-helpers.sh` line 48 comment)
- Inline `# shellcheck` directives where needed

### note() vs err() severity (audit-setup.sh)

**Source:** `scripts/audit-setup.sh` lines 18–21, 338–339

```bash
note() { echo "  $1"; }            # advisory — no counter, exit 0
ok()   { note "✓ $1"; PASS=$((PASS+1)); }
warn() { note "⚠ $1"; WARN=$((WARN+1)); }  # increments WARN, causes exit 1
err()  { note "✗ $1"; FAIL=$((FAIL+1)); }  # increments FAIL, causes exit 2
```
**Apply to POL-05:**
- POL-05a (overlay active, sandbox missing/disabled): `err()`
- POL-05b (denyRead path not mirrored in permissions.deny): `err()`
- POL-05c (disableBypassPermissionsMode is boolean): `err()`
- POL-05-advisory (unreviewed template — REPLACE_WITH_ORG_UUID still present): `note "⚠ [policy] ..."` (NOT `warn()` — exits 0)

---

## No Analog Found

All files have close analogs. No entries in this section.

---

## Key Architectural Constraints (from RESEARCH.md)

These are not patterns to copy but constraints the planner must build around:

1. **jq `.*` replaces arrays — never use for sandbox merge.** Use explicit `def array_merge(a;b): (a // []) + (b // []) | unique;` (RESEARCH.md Pattern 1). Single-line analog from `plugin_wire_settings`: `.enabledPlugins = (.enabledPlugins // {}) | .enabledPlugins[$key] = true` — object assignment, not array merge.

2. **`disableBypassPermissionsMode` type is STRING `"disable"`, not boolean.** Validate with `jq -r '.permissions.disableBypassPermissionsMode | type'` → must equal `"string"`. The audit POL-05c check uses this exact jq idiom (RESEARCH.md Pattern 6).

3. **Absolute paths in `permissions.deny` need double-slash prefix.** `/etc/passwd` → `Read(//etc/passwd)`. Only `~/` and `./` prefix paths pass through as-is. (RESEARCH.md Pattern 2, Pitfall 2.)

4. **`managed-settings.d/` is deferred (POL-F1).** Emit only a single `conjure-policy/managed-settings.json`. Do not create a `managed-settings.d/` directory.

5. **NEVER auto-place artifacts at system paths** (`/Library/Application Support/`, `C:\ProgramData\ClaudeCode\`). Always write to `--output DIR` (default `./conjure-policy/`).

6. **`plutil -lint` is macOS-only.** Gate with `command -v plutil >/dev/null 2>&1`; skip on Linux, note in VERIFY.txt.

---

## Metadata

**Analog search scope:** `lib/`, `scripts/`, `cli/`, `compliance/`, `tests/fixtures/_emit-plugin*`, `tests/run.sh`
**Files scanned:** 11 source files fully read
**Pattern extraction date:** 2026-06-03
