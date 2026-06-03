---
phase: 25-plugin-marketplace-emission
reviewed: 2026-06-03T00:00:00Z
depth: standard
iteration: 2
files_reviewed: 7
files_reviewed_list:
  - lib/plugin-helpers.sh
  - scripts/emit-plugin.sh
  - scripts/publish-plugin.sh
  - scripts/audit-setup.sh
  - cli/conjure
  - .claude-plugin/SCHEMAS/plugin.schema.json
  - .claude-plugin/SCHEMAS/marketplace.schema.json
findings:
  critical: 0
  warning: 3
  info: 3
  total: 6
status: issues_found
---

# Phase 25: Code Review Report (Iteration 2)

**Reviewed:** 2026-06-03T00:00:00Z
**Depth:** standard
**Files Reviewed:** 7
**Status:** issues_found

## Summary

Re-review after the fixer applied 8 findings from iteration 1. All 8 prior fixes
were verified as correctly applied:

- **CR-01** — `publish-plugin.sh` now `exit 2` on all failure paths (no `exit 1`). Confirmed.
- **CR-02** — `snapshot_create` runs before the first overwriting write in both
  `emit-plugin.sh` (lines 90–95, gated on a pre-existing manifest/settings file) and
  `publish-plugin.sh` (lines 108–111). Ordering verified: secret-scan + schema validation
  precede snapshot, which precedes `mutate_write`. Correct.
- **WR-01** — emit-plugin marketplace-name regex `^[a-z][a-z0-9-]{0,63}$` matches the
  schema pattern. Verified it rejects digit-leading and all-hyphen derivations.
- **WR-02** — `validate_marketplace_json` enforces name pattern, `owner.name`, and per-plugin
  `name`/`source` typing. Confirmed.
- **WR-03** — agent-path stripping uses bash parameter expansion (`${f#"$target/"}`), no `sed`.
  Confirmed safe for paths with metacharacters; empty dir yields `[]` cleanly under `set -e`.
- **WR-04** — jq merge base is `.` (preserves all existing fields). Documented and correct.
- **WR-05** — `resolve_version` strips whitespace from `.conjure-version`. **Fix introduced a
  regression** (see WR-01 below).
- **WR-06** — secret-scan ERE uses `[[:space:]]` not `\s`. Verified the key-prefix and
  bare-`password=` patterns fire under macOS/BSD `grep -E`.
- **WR-07** — intentionally left as `note()` in audit-setup.sh; not re-flagged (per instructions,
  switching to `warn()` would flip the audit exit code).

shellcheck passes clean at the project gate (`-S error -e SC2164,SC2044,SC2034,SC2155`) on all
four scripts.

No Critical findings remain. Three new/residual Warnings surfaced — the most important is a
regression introduced by the WR-05 fix.

## Warnings

### WR-01: WR-05 whitespace-strip regression — blank `.conjure-version` emits `"version": ""`

**File:** `lib/plugin-helpers.sh:180-183`
**Issue:** The WR-05 fix replaced the raw read with
`head -1 "$target/.conjure-version" | tr -d '[:space:]'`. When the file exists but is empty or
whitespace-only (blank line, stray newline, file touched but not filled), `tr -d '[:space:]'`
collapses it to the **empty string**, and `resolve_version` returns `""` with exit 0 — it never
falls through to the git-SHA (Tier 2) or `0.0.0` (Tier 3) fallbacks.

That empty string is then passed as `--arg version ""` into `plugin_build_plugin_json` and
`plugin_build_marketplace_json`, producing `"version": ""` in the emitted manifests. Verified:
`printf '\n' > .conjure-version; head -1 ... | tr -d '[:space:]'` yields an empty result, and the
downstream validator accepts it (see WR-02). The user gets a silently version-less plugin instead
of the intended git-SHA or `0.0.0` fallback. Pre-fix behavior (raw read) would at least have
emitted a non-empty token.

**Fix:** Guard for the empty result and fall through to the existing Tier 2/3 logic:
```bash
if [ -f "$target/.conjure-version" ]; then
  _ver="$(head -1 "$target/.conjure-version" | tr -d '[:space:]')"
  if [ -n "$_ver" ]; then
    printf '%s' "$_ver"
    return 0
  fi
  echo "WARN: .conjure-version is empty — falling back to git SHA / 0.0.0" >&2
fi
# ... continue to Tier 2 (git) and Tier 3 (0.0.0)
```

### WR-02: `validate_plugin_json` accepts empty `name` and empty `version` — last gate before write is too permissive

**File:** `lib/plugin-helpers.sh:64-67,70-73`
**Issue:** The required-`name` check only asserts `(.name | type) == "string"`. An empty string
`""` is a string, so a manifest with `"name": ""` passes the validator (verified). Because the
jq merge base is `.` (WR-04), an existing `plugin.json` carrying a blank or whitespace `name`
flows through unchanged and is written out. The schema marks `name` as required but the bundled
validator — the actual gate that runs before `mutate_write` — does not enforce non-blank. The same
applies to `version`: jq treats `""` as truthy, so the `if .version then ...` branch is taken and
`""` passes the string check, compounding WR-01.

**Fix:** Tighten the required-field checks to reject blank values:
```bash
if ! printf '%s' "$content" | jq -e '(.name | type) == "string" and (.name | length > 0)' >/dev/null 2>&1; then
  echo "✗ plugin.json: 'name' is required and must be a non-empty string" >&2
  errors=$((errors + 1))
fi
```
Optionally reject `""` for `version` the same way (`(.version | length > 0)`) so an empty
`.conjure-version` is caught even if WR-01 is not fixed.

### WR-03: Marketplace `--name` override is plumbed end-to-end but unreachable from the CLI

**File:** `cli/conjure:481-504`, `scripts/emit-plugin.sh:26`
**Issue:** `CONJURE_PLUGIN_MKT_NAME` is threaded from `cmd_publish_plugin` (line 503) into
`emit-plugin.sh` (line 26, `MKT_NAME="${CONJURE_PLUGIN_MKT_NAME:-}"`), and the marketplace path
honours a non-empty `MKT_NAME` instead of auto-deriving. But `cmd_publish_plugin` initialises
`mkt_name=""` and its arg loop has **no flag that ever sets it** — there is no `--name`/`--mkt-name`
case. Neither does `emit-plugin.sh`'s own arg loop (lines 29-47). The result: the only way to reach
the override is to set the env var by hand; via the documented CLI the marketplace name is *always*
auto-derived from the repo basename.

This matters because auto-derivation can produce a name the user cannot fix: a repo whose basename
starts with a digit (e.g. `123-tools` → `123-tools`) or normalises to all hyphens (`_._` → `---`)
fails the WR-01 regex and hard-`exit 2`s the command, with no documented escape hatch. Dead
plumbing also misleads maintainers into thinking the override works.

**Fix:** Add the flag to both arg loops, or remove the dead env plumbing. Preferred — wire the flag:
```bash
# in cmd_publish_plugin and emit-plugin.sh arg loops:
--name)    shift; mkt_name="${1:-}" ;;
--name=*)  mkt_name="${1#--name=}" ;;
```
and surface `[--name <kebab-name>]` in the usage strings.

## Info

### IN-01: secret-scan JSON field allowlist omits `password`

**File:** `lib/plugin-helpers.sh:48`
**Issue:** The quoted-JSON-field branch lists `api_key|api_secret|auth_token|access_token|secret_key|private_key`
but not `password`. A manifest field literally `"password": "<value>"` (e.g. an MCP server `env`
entry merged from `.mcp.json`) does not match that branch, and the bare-`password=` branch requires
a non-JSON `=`/`:` form, so it slips through. Raw key prefixes (`sk-ant-`, `ghp_`, …) still catch
most real leaks, so impact is limited.

**Fix:** Add `password` to the JSON-field alternation:
`"(api_key|api_secret|auth_token|access_token|secret_key|private_key|password)"`.

### IN-02: Redundant `command -v git` re-check in emit-plugin.sh

**File:** `scripts/emit-plugin.sh:68`
**Issue:** git availability is already a hard prerequisite (`exit 2`) at lines 55-58, so the
`if command -v git` guard at line 68 is always true and adds noise.
**Fix:** Drop the inner `command -v git` test and run the dirty-tree check unconditionally.

### IN-03: `publish-plugin.sh` reads `plugin.json` for validation without existence check

**File:** `scripts/publish-plugin.sh:81-84,96-98`
**Issue:** The script checks that `marketplace.json` exists (line 59) but `jq empty "$PLUGIN_DIR/plugin.json"`
(line 81) and the later `jq ... "$PLUGIN_DIR/plugin.json"` (line 96) assume `plugin.json` is present.
If only `marketplace.json` exists, `jq` errors on the missing file and the `2>/dev/null || exit 2`
branch fires with the misleading message "is not valid JSON" rather than "not found". Low impact
(still exits 2) but the diagnostic is wrong.
**Fix:** Add an explicit `[ -f "$PLUGIN_DIR/plugin.json" ]` guard mirroring lines 59-62 before the
jq validation.

---

_Reviewed: 2026-06-03T00:00:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard (iteration 2)_
