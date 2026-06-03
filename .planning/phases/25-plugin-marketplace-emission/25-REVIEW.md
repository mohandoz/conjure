---
phase: 25-plugin-marketplace-emission
reviewed: 2026-06-03T00:00:00Z
depth: standard
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
  critical: 2
  warning: 7
  info: 4
  total: 13
status: issues_found
---

# Phase 25: Code Review Report

**Reviewed:** 2026-06-03
**Depth:** standard
**Files Reviewed:** 7
**Status:** issues_found

## Summary

Reviewed the plugin/marketplace emission feature: shared helpers (`lib/plugin-helpers.sh`),
the target-repo emitter (`scripts/emit-plugin.sh`), the self-publish path
(`scripts/publish-plugin.sh`), the audit reconciliation additions
(`scripts/audit-setup.sh`), CLI dispatch (`cli/conjure`), and two JSON schemas.

Two BLOCKERs stand out: (1) `scripts/publish-plugin.sh` violates the project-wide
`exit 2 never exit 1` convention in six code paths, and (2) the emission paths
overwrite `plugin.json` / `marketplace.json` / `settings.json` with **no
backup-before-mutate** snapshot, breaking a core CLAUDE.md safety invariant. Several
validation-consistency gaps (bash validator vs. JSON schema) and a `sed` path-stripping
fragility round out the warnings.

The known `note()`-vs-`warn()` deviation in `audit-setup.sh` is assessed below
(WR-07) and judged **correct** — using `warn()` would have flipped the audit exit code
and broken the advisory-only contract documented in the code.

## Critical Issues

### CR-01: publish-plugin.sh violates `exit 2 never exit 1` convention (data-path divergence)

**File:** `scripts/publish-plugin.sh:40`, `:77`, `:82`, `:93`, `:101`, `:131`
**Issue:** CLAUDE.md is explicit and non-negotiable: "Hooks/CLI/scripts `exit 2`,
never `exit 1`." This worker exits `1` in six places:
- `:40` unknown argument → `exit 1`
- `:77` / `:82` invalid existing JSON → `exit 1`
- `:93` / `:101` jq produced invalid JSON → `exit 1`
- `:131` invalid submit-entry JSON → `exit 1`

The header comment even codifies the deviation ("1 = validation error"), but that
directly contradicts the project constraint. Downstream callers and CI gates that
branch on exit codes treat `1` and `2` differently; a `1` here is interpreted as an
unexpected/uncontrolled failure rather than a controlled hard failure. The sibling
worker `scripts/emit-plugin.sh` correctly uses `exit 2` everywhere (`:41`, `:51`, etc.),
making this an inconsistency within the same feature.

**Fix:** Replace every `exit 1` with `exit 2` and update the header comment block:
```bash
# Exit codes:
#   0 = success
#   2 = hard failure (bad arg, JSON parse failure, missing file, dirty tree, missing dep/VERSION)
```
```bash
# :40
*) echo "Unknown argument: $1" >&2; exit 2 ;;
# :77, :82, :93, :101, :131 — all `exit 1` → `exit 2`
```

### CR-02: Emission overwrites manifests with no backup-before-mutate (safety invariant breach)

**File:** `scripts/emit-plugin.sh:84-86`, `:128`, `:134`; `scripts/publish-plugin.sh:106`, `:108`, `:135`
**Issue:** CLAUDE.md mandates "backup-before-mutate on every change" and the blessed
backup mechanism is `snapshot_create` (see `scripts/adopt.sh:202`/`:214`). Neither
emission worker sources `lib/snapshot.sh` nor calls `snapshot_create` before
overwriting pre-existing files:
- `emit-plugin.sh:86` overwrites `.claude-plugin/plugin.json` (which may contain
  user-authored fields; the jq merge in `plugin_build_plugin_json` re-asserts only an
  allowlist, and any field outside it is at risk under future refactors — see WR-04).
- `emit-plugin.sh:128` overwrites `.claude-plugin/marketplace.json`.
- `plugin_wire_settings` → `mutate_write` (`:366`, called from `emit-plugin.sh:134`)
  overwrites the live `.claude/settings.json`.
- `publish-plugin.sh:106`/`:108` overwrite the repo's own committed manifests.

`mutate_write` does a bare `> "$dest"` (`lib/mutate.sh:65`) with no `.bak`. A bad jq
merge, an unexpected schema, or user error therefore destroys prior content with no
restore path. This is a data-loss risk on every re-run.

**Fix:** Source `lib/snapshot.sh` and snapshot `.claude-plugin/` (and
`.claude/settings.json`) before the first write, mirroring `adopt.sh`:
```bash
source "$CONJURE_HOME/lib/snapshot.sh"
# before the first mutate_write that can overwrite existing files (live mode only):
if [ "${DRY_RUN:-0}" != "1" ] && { [ -f "$TARGET/.claude-plugin/plugin.json" ] || [ -f "$TARGET/.claude/settings.json" ]; }; then
  snapshot_create "$TARGET" "$TARGET/.conjure-backups"
fi
```
Document the backup location in the success report (`:142-156`). If a deliberate
exception was intended, it must be justified the way `snapshot_create` is blessed in
CLAUDE.md — currently it is not.

## Warnings

### WR-01: Bash marketplace-name validator inconsistent with JSON schema (leading digit + length)

**File:** `scripts/emit-plugin.sh:104`; `.claude-plugin/SCHEMAS/marketplace.schema.json:9`
**Issue:** The emitter's gate is `^[a-z0-9][a-z0-9-]*$` — it permits a **leading digit**
and imposes **no length cap**. The authoritative schema requires
`^[a-z][a-z0-9-]{0,63}$` — leading **letter only**, max 64 chars. A repo/dir named
`9tools` yields `MKT_NAME=9tools`, which passes the emitter, gets written and wired into
`settings.json`, then fails `claude plugin validate` / schema validation downstream.
Same for any name >64 chars. The user only discovers the breakage after mutation.

**Fix:** Align the emitter regex with the schema and reject early:
```bash
if ! printf '%s' "$MKT_NAME" | grep -qE '^[a-z][a-z0-9-]{0,63}$'; then
  echo "✗ Marketplace name '$MKT_NAME' must start with a letter and be ≤64 chars (a-z, 0-9, hyphens)" >&2
  exit 2
fi
```

### WR-02: Bash validators skip schema-required constraints (owner.name, name pattern, source type)

**File:** `lib/plugin-helpers.sh:103-135`
**Issue:** `validate_marketplace_json` is the pre-write gate, but it is weaker than the
shipped schema:
- It checks `owner` is an object but never checks the schema-required `owner.name`
  (schema `:14`). An owner object missing `name` passes the bash gate.
- It never enforces the `name` kebab pattern (schema `:9`).
- Per-plugin it checks `source != null` but not that `source` is an **object**
  (schema `:28` requires object); a string `source` would pass.

Because emission only runs `claude plugin validate` when `--validate` is explicitly
passed (`emit-plugin.sh:138`), without that flag the weak bash gate is the only
validation — so malformed manifests can be written and committed.

**Fix:** Tighten `validate_marketplace_json` to mirror schema requirements:
```bash
# owner.name present + string
jq -e '(.owner.name | type) == "string"' ...
# name kebab pattern
jq -e '.name | test("^[a-z][a-z0-9-]{0,63}$")' ...
# each plugin.source is an object
jq -e '[.plugins[] | select((.source | type) != "object")] | length == 0' ...
```

### WR-03: Unescaped `$target` in `sed` substitution breaks on special characters

**File:** `lib/plugin-helpers.sh:209-210`
**Issue:** `find "$target/.claude/agents" ... | sed "s|$target/||"` interpolates
`$target` directly into the `sed` substitution pattern. `TARGET` defaults to `$(pwd)`
(`emit-plugin.sh:20`), an absolute path that can contain `sed` metacharacters or the `|`
delimiter (e.g. a directory whose path contains `|`, or `.`/`*` which are regex-active
in the LHS). When that happens, the path is stripped incorrectly or `sed` errors, and
the resulting `agents` array contains wrong/absolute paths — a silently wrong manifest.

**Fix:** Strip the prefix with bash parameter expansion (no regex) instead of `sed`:
```bash
while IFS= read -r f; do
  printf '%s\n' "${f#"$target/"}"
done < <(find "$target/.claude/agents" -maxdepth 1 -name '*.md' 2>/dev/null) \
  | jq -R . | jq -sc .
```

### WR-04: `plugin_build_plugin_json` allowlist intent diverges from passthrough behavior

**File:** `lib/plugin-helpers.sh:238-256`
**Issue:** The merge preserves only `description`, `keywords`, `author`, `license`,
`homepage`, `repository`. The plugin schema also defines `displayName`, `commands`,
`defaultEnabled` (schema `:10`, `:20`, `:18`). Because the merge base is `.` (the
original object), those three are in fact retained today — but the explicit allowlist of
`($orig.x // null) as $...` lines plus the "merge-preserve of user metadata fields"
comment imply allowlist semantics that do NOT match the passthrough reality. The risk: a
future refactor switching the base from `.` to `{}` (a natural-looking change) would
silently drop every un-allowlisted field with no test catching it.

**Fix:** Either document on `:245` that `.` is the merge base and all existing fields
pass through verbatim (the allowlist lines only re-assert specific fields), or
explicitly preserve all schema-known optional fields so intent and behavior match.

### WR-05: `resolve_version` emits raw `.conjure-version` content with no validation/trim

**File:** `lib/plugin-helpers.sh:169-172`
**Issue:** Tier 1 does `cat "$target/.conjure-version"` and returns it verbatim as the
version string written into `plugin.json` / `marketplace.json`. A file with a trailing
newline, leading/trailing whitespace, multiple lines, or non-semver junk flows straight
into the manifest. While any string satisfies the schema `version` type, multi-line or
whitespace-laden content corrupts the embedded value and `claude plugin validate` /
consumers expect a clean single-line version.

**Fix:** Trim and take the first line:
```bash
if [ -f "$target/.conjure-version" ]; then
  head -1 "$target/.conjure-version" | tr -d '[:space:]'
  return 0
fi
```

### WR-06: Secret-scan regex relies on `\s` under POSIX `grep -E` (security control weakened on macOS)

**File:** `lib/plugin-helpers.sh:45-46`
**Issue:** The secret-scan pattern uses `\s` (e.g. the credential-assignment branch
matching whitespace around `=`/`:`). `\s` is a GNU/PCRE extension and is **not** part of
POSIX ERE. On BSD/macOS `grep -E` (the platform this project explicitly targets), `\s`
matches a literal `s`, not whitespace — so a credential assignment written with spaces
around the operator would NOT be detected, defeating the credential gate on exactly the
platform it ships on. This silently weakens a security control.

**Fix:** Replace `\s` with the POSIX class `[[:space:]]` throughout the pattern so it
matches whitespace on both GNU and BSD `grep -E`.

### WR-07: `note()` substituted for `warn()` in audit advisories — assessed CORRECT (keep)

**File:** `scripts/audit-setup.sh:177-217`
**Issue (assessment requested):** Plan 25-03 specified `warn()` for the two plugin
advisory sections; the executor used `note()` instead. `warn()` increments `WARN`
(`:20`), and the audit exit logic does `[ "$WARN" -gt 0 ] && exit 1` (`:339`). Using
`warn()` would therefore flip the audit from exit 0 to exit 1 purely because a plugin
manifest is stale — and the code comments explicitly state these checks are "advisory
note (exit 0)" / "does not break CI gate" (`:177-178`, `:202-203`). The intended
semantics are informational, not gate-breaking. `note()` (plain echo, no counter) is the
correct choice; using `warn()` would have been a BLOCKER-class regression (CI
false-failure on stale plugin metadata). **No change required.**

Secondary nit: the `note()` calls prefix the message with a warning glyph (`:185`,
`:190`, `:196`, `:212`), which visually reads as a warning while deliberately not
counting as one. Consider a distinct informational prefix so the exit-code contract is
legible to readers.

## Info

### IN-01: `set -uo pipefail` in audit-setup.sh omits `-e` while siblings use `set -euo`

**File:** `scripts/audit-setup.sh:6`
**Issue:** `audit-setup.sh` uses `set -uo pipefail` (no `-e`), whereas the emission
workers use `set -euo pipefail`. For an audit script this is arguably intentional (it
must run all checks even if one fails), but the divergence is undocumented.
**Fix:** Add a one-line comment explaining `-e` is intentionally omitted so audit
continues past individual check failures.

### IN-02: Owner-name derivation falls back to literal `unknown` silently

**File:** `scripts/emit-plugin.sh:114-118`
**Issue:** When `git config user.name` is empty and the repo basename can't supply an
owner, `OWNER_NAME` becomes the literal string `unknown`, written into
`marketplace.json` `owner.name`. This passes validation but produces a low-quality
public manifest with no warning.
**Fix:** Emit a `WARN:` to stderr when falling back to `unknown` so the user sets a real
owner before publishing.

### IN-03: `reserved_name_check` iterates an unquoted space-list

**File:** `lib/plugin-helpers.sh:21`
**Issue:** `for reserved in $CONJURE_RESERVED_MARKETPLACE_NAMES` relies on unquoted
word-splitting. It works because the list contains only single-token values, but it is
fragile to IFS changes or to overrides containing quoted multi-word entries.
**Fix:** Acceptable as-is under the POSIX-3.2 no-arrays constraint; add a comment noting
the list must remain whitespace-delimited single tokens.

### IN-04: `--enable` without `--marketplace` silently no-ops

**File:** `scripts/emit-plugin.sh:88-135`; `cli/conjure:487-488`
**Issue:** `--enable` only takes effect inside the `if [ "$DO_MARKETPLACE" = "1" ]`
block. `conjure publish-plugin --enable` (without `--marketplace`) parses fine, mutates
`plugin.json`, and silently ignores `--enable`. Users will reasonably expect it to do
something.
**Fix:** If `DO_ENABLE=1` and `DO_MARKETPLACE=0`, print a `WARN:` that `--enable`
requires `--marketplace`, or auto-imply `--marketplace`.

---

_Reviewed: 2026-06-03_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
