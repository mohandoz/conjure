---
phase: "25"
plan: "02"
subsystem: plugin-emission
tags: [wave-2, marketplace-emit, settings-wiring, plugin-helpers, keyed-object-merge, reserved-name-guard]
dependency_graph:
  requires:
    - 25-01 (lib/plugin-helpers.sh + scripts/emit-plugin.sh + --marketplace stub)
  provides:
    - lib/plugin-helpers.sh (plugin_build_marketplace_json + plugin_wire_settings)
    - scripts/emit-plugin.sh (full --marketplace + --enable paths)
  affects:
    - .claude-plugin/marketplace.json (new emit target)
    - .claude/settings.json (extraKnownMarketplaces + optional enabledPlugins)
tech_stack:
  added: []
  patterns:
    - jq keyed-object idempotent merge for extraKnownMarketplaces (D-15)
    - GitHub source auto-detection via detect_github_source (SSH + HTTPS forms)
    - Reserved-name guard with exact-match + impersonation patterns (D-07)
    - Secret-scan + schema-validate before any mutate_write (D-08, D-09)
    - kebab-case normalization: lowercase, tr _ . -> -, strip non-alphanum (macOS mktemp compat)
key_files:
  created: []
  modified:
    - lib/plugin-helpers.sh
    - scripts/emit-plugin.sh
decisions:
  - "Kebab-case derivation strips dots and non-[a-z0-9-] chars (not just underscores): macOS mktemp produces names like tmp.kFshdPqjVT which contain dots and uppercase — stripping with tr -cd 'a-z0-9-' after lowercasing is necessary to produce a valid kebab-case name"
  - "OWNER_REPO variable needs fresh detection in owner_name fallback block: initial detect_github_source result must be cached and reused when deriving owner_name"
  - "plugin_wire_settings uses single jq call for both extraKnownMarketplaces and enabledPlugins merges (atomicity)"
  - "Source object for extraKnownMarketplaces is extracted from marketplace.json plugins[0].source via jq -c (compact) before passing to plugin_wire_settings as argjson"
metrics:
  duration: 25
  completed: "2026-06-03T05:00:00Z"
  tasks: 2
  files: 2
---

# Phase 25 Plan 02: Marketplace Manifest Emit + Settings Wiring Summary

Marketplace emit path: `plugin_build_marketplace_json` + `plugin_wire_settings` wired into emit-plugin.sh — PLUG-02, PLUG-02-reserved, PLUG-03, PLUG-03-idem all green.

## What Was Built

**Task 1: plugin_build_marketplace_json and plugin_wire_settings in lib/plugin-helpers.sh**

Added two new functions after `plugin_build_plugin_json`:

- `plugin_build_marketplace_json(target, mkt_name, version, owner_name)`:
  - Calls `detect_github_source "$target"` — returns `owner/repo` string or empty on no GitHub remote
  - GitHub path: resolves `sha` via `git rev-parse HEAD` + `ref` via `git rev-parse --abbrev-ref HEAD`; builds source object `{source: "github", repo: ..., ref: ..., sha: ...}` per D-16
  - Local fallback: source object `{source: "local"}` when no GitHub remote or no git
  - Builds marketplace JSON via `jq -n` with `--argjson source_obj`: `{name, owner: {name}, plugins: [{name, source, version}]}`
  - Validates with `printf '%s' "$MKT_JSON" | jq empty` before printing to stdout

- `plugin_wire_settings(settings_file, mkt_name, mkt_source_obj, plugin_key, do_enable)`:
  - Reads current settings: `cat "$settings_file" 2>/dev/null || echo '{}'`
  - Single jq call merges `extraKnownMarketplaces[$mkt_name] = {source: $src}` (D-15 keyed-object idempotent)
  - If `do_enable=1`: same jq call also merges `enabledPlugins[$plugin_key] = true` (D-14)
  - Validates updated JSON before `mutate_write`

**Task 2: Full --marketplace and --enable paths in scripts/emit-plugin.sh**

Replaced the stub comment block with full implementation:

1. Marketplace name derivation: `$CONJURE_PLUGIN_MKT_NAME` env var → git remote repo basename → TARGET directory basename; normalization: lowercase + `tr '_.' '-'` + `tr -cd 'a-z0-9-'` (strips dots and uppercase for macOS mktemp compat)
2. Kebab-case validation guard before any downstream processing
3. `reserved_name_check "$MKT_NAME" || exit 2` — runs BEFORE any file writes per D-07
4. Owner name from `git config user.name` → dirname of owner_repo → "unknown" fallback
5. `plugin_build_marketplace_json` called → result in `MKT_JSON`
6. `secret_scan "$MKT_JSON" "marketplace.json" || exit 2` + `validate_marketplace_json "$MKT_JSON" || exit 2`
7. `mutate_write "$TARGET/.claude-plugin/marketplace.json" "$MKT_JSON"`
8. Source object extracted from `MKT_JSON` via `jq -c '.plugins[0].source'`; `plugin_wire_settings` called with `DO_ENABLE` flag
9. Success report updated: adds `✓ .claude-plugin/marketplace.json` + `✓ .claude/settings.json` with appropriate annotation (D-04)
10. Bare `publish-plugin` (no `--marketplace`) skips the entire block (D-13)

## Test Results

**Before Plan 02:** 479 PASS / 4 FAIL
**After Plan 02:** 481 PASS / 2 FAIL

Plan 02 targets (all PASS):
- PLUG-02: `--marketplace` emits marketplace.json with correct fields (name/owner/plugins shape)
- PLUG-02-reserved: reserved marketplace name (`claude-code-marketplace`) exits 2 before any write
- PLUG-03: `extraKnownMarketplaces` is an object in settings.json after `--marketplace`
- PLUG-03-idem: second run produces identical settings.json (keyed-object idempotency)

Previously passing (still PASS — no regression):
- PLUG-01, PLUG-01-merge, PLUG-05, PLUG-04, PLUG-04-secret, PLUG-04-absent, PLUG-02-badpath

Remaining FAIL (Plan 03 scope):
- PLUG-REC: audit-setup.sh plugin reconciliation warning (Plan 25-03)
- PLUG-REFSHA: audit-setup.sh ref-without-sha warning (Plan 25-03)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] kebab-case normalization missing dot/non-alphanum stripping**
- **Found during:** Task 2 manual debugging (PLUG-02 failing)
- **Issue:** Plan specified `tr '_' '-'` for kebab-case conversion. macOS `mktemp -d` creates directories named `tmp.kFshdPqjVT` (dots + mixed case). After `tr '[:upper:]' '[:lower:]' | tr '_' '-'` → `tmp.kfshdpqjvt` which fails the `^[a-z0-9][a-z0-9-]*$` validation due to the dot. The PLUG-02 test uses `mktemp -d` as the TARGET directory, so the fallback name derivation hit this path.
- **Fix:** Changed to `tr '[:upper:]' '[:lower:]' | tr '_.' '-' | tr -cd 'a-z0-9-'` — converts dots to hyphens and strips all non-`[a-z0-9-]` characters
- **Files modified:** `scripts/emit-plugin.sh` (fallback name derivation line)
- **Commit:** fc3d98b

## Known Stubs

None — Plan 02 stub fully replaced. The --marketplace path is complete.

## Threat Surface

No new threat surface beyond what was documented in Plan 02's threat model. All T-25-07 through T-25-10 mitigations are implemented:

| Flag | File | Description |
|------|------|-------------|
| threat_flag: input_validation | `scripts/emit-plugin.sh` | Marketplace name derived from user-controlled env var or git remote basename; mitigated by kebab-case validation + reserved_name_check before any write (T-25-07) |
| threat_flag: info_disclosure | `scripts/emit-plugin.sh` | marketplace.json content built from harness; mitigated by secret_scan before mutate_write (T-25-08) |

## Self-Check: PASSED

- [x] `lib/plugin-helpers.sh` has `plugin_build_marketplace_json` — `grep -q "plugin_build_marketplace_json" lib/plugin-helpers.sh` exits 0
- [x] `lib/plugin-helpers.sh` has `plugin_wire_settings` — `grep -q "plugin_wire_settings" lib/plugin-helpers.sh` exits 0
- [x] `lib/plugin-helpers.sh` has `extraKnownMarketplaces` — exits 0
- [x] `lib/plugin-helpers.sh` has `enabledPlugins` — exits 0
- [x] `lib/plugin-helpers.sh` has `detect_github_source` call — exits 0
- [x] `shellcheck -S error -e SC2164,SC2044,SC2034,SC2155 lib/plugin-helpers.sh` exits 0
- [x] `shellcheck -S error -e SC2164,SC2044,SC2034,SC2155 scripts/emit-plugin.sh` exits 0
- [x] `bash tests/run.sh 2>&1 | grep "PLUG-02\b"` shows PASS
- [x] `bash tests/run.sh 2>&1 | grep "PLUG-02-reserved"` shows PASS
- [x] `bash tests/run.sh 2>&1 | grep "PLUG-03\b"` shows PASS
- [x] `bash tests/run.sh 2>&1 | grep "PLUG-03-idem"` shows PASS
- [x] Full suite: 481 PASS / 2 FAIL (remaining 2 are Plan 03 scope: PLUG-REC, PLUG-REFSHA)
- [x] Commit 3959e0a exists (Task 1)
- [x] Commit fc3d98b exists (Task 2)
