---
phase: 25-plugin-marketplace-emission
verified: 2026-06-03T08:30:00Z
status: human_needed
score: 5/5
overrides_applied: 0
human_verification:
  - test: "Run conjure publish-plugin --validate on a repo where claude CLI is installed and plugin.json is valid"
    expected: "Exit 0, 'claude plugin validate .' runs and returns clean, no files blocked"
    why_human: "The run_cli_validate path that exercises a present claude binary cannot be tested without the claude CLI installed in CI; PLUG-04-absent covers the absent case (passes), but the success path requires a real claude binary invocation"
---

# Phase 25: Plugin + Marketplace Emission — Verification Report

**Phase Goal:** Developers can generate, validate, and wire a Claude Code plugin + marketplace manifest from their conjure-scaffolded harness in one command
**Verified:** 2026-06-03T08:30:00Z
**Status:** human_needed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | `conjure publish-plugin` produces `.claude-plugin/plugin.json` with correct skills/agents/hooks/mcpServers paths and version from `.conjure-version` (or git SHA fallback) | VERIFIED | `scripts/emit-plugin.sh` calls `resolve_version` (3-tier: .conjure-version → git SHA → 0.0.0); calls `plugin_build_plugin_json` which reads harness paths; writes via `mutate_write`. PLUG-01 and PLUG-05 tests pass. |
| 2 | `conjure publish-plugin --marketplace` produces valid `marketplace.json` with kebab-case name, owner, plugins[] with source; reserved-name guard rejects Anthropic-controlled names with exit 2 | VERIFIED | `plugin_build_marketplace_json` in `lib/plugin-helpers.sh` builds the manifest; `reserved_name_check` blocks reserved and claude-*/anthropic-*/official-* prefixes; `validate_marketplace_json` enforces kebab-case pattern. PLUG-02 and PLUG-02-reserved tests pass. |
| 3 | `conjure publish-plugin --validate` calls `claude plugin validate .` and a JSON-schema check at emit time; exits 2 and refuses to write any file when manifest invalid | VERIFIED | `validate_plugin_json` runs unconditionally at line 91 (before `mutate_write` at line 106); `--validate` additionally calls `run_cli_validate` which exits 2 when claude is absent. PLUG-04, PLUG-04-secret, PLUG-04-absent tests pass. The "claude present and succeeds" path requires human testing (see below). |
| 4 | `conjure publish-plugin` wires `extraKnownMarketplaces` (object form) and `enabledPlugins` into `.claude/settings.json` via idempotent `mutate_write` merge; `conjure audit` flags a ref-without-sha marketplace entry with a warning | VERIFIED | `plugin_wire_settings` in `lib/plugin-helpers.sh` uses keyed-object jq merge (`.extraKnownMarketplaces[$name] = {"source": $src}`); `audit-setup.sh` emits `note "⚠ ... ref but no sha"` for entries where `.value.source.ref != null and .value.source.sha == null`. PLUG-03, PLUG-03-idem, PLUG-REFSHA tests pass. |
| 5 | `conjure audit` detects when `.claude-plugin/plugin.json` is out of sync with actual `.claude/` contents; `conjure publish-plugin` on a fixture with a secret-pattern value in the env block exits 2 before writing any file | VERIFIED | `audit-setup.sh` plugin reconciliation section checks `jq -r '.skills // empty'` and warns when skills path has no SKILL.md on disk. `secret_scan` in `emit-plugin.sh` runs at line 88 before `mutate_write` at line 106. PLUG-REC and PLUG-04-secret tests pass. |

**Score:** 5/5 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `lib/plugin-helpers.sh` | 8 shared functions for plugin emission | VERIFIED | 448 lines; all 8 functions present and shellcheck-clean: `reserved_name_check`, `secret_scan`, `validate_plugin_json`, `validate_marketplace_json`, `detect_github_source`, `resolve_version`, `plugin_build_plugin_json`, `plugin_build_marketplace_json`, `plugin_wire_settings`, `run_cli_validate` (10 functions — plan listed 8, implementation added 2 more) |
| `scripts/emit-plugin.sh` | Target-repo emit worker with all flags | VERIFIED | 183 lines; shellcheck-clean; accepts --path, --name, --marketplace, --enable, --validate, --dry-run; full --marketplace and --enable paths implemented |
| `cli/conjure` | `cmd_publish_plugin` + `publish-plugin` dispatch | VERIFIED | `grep publish-plugin cli/conjure` finds: usage line (line 47), `cmd_publish_plugin` function (line 480), dispatch entry `publish-plugin) shift; cmd_publish_plugin "$@" ;;` (line 534) |
| `.claude-plugin/SCHEMAS/plugin.schema.json` | JSON Schema with required: ["name"] only, no additionalProperties: false | VERIFIED | Valid JSON; `required: ["name"]`; no additionalProperties: false; $schema "https://json-schema.org/draft/2020-12/schema" |
| `.claude-plugin/SCHEMAS/marketplace.schema.json` | JSON Schema with required: ["name", "owner", "plugins"] | VERIFIED | Valid JSON; all 3 required fields present; kebab-case pattern on name; owner has required: ["name"] |
| `tests/fixtures/_emit-plugin/harness/` | Minimal harness with skill, agent, settings.json hooks, .mcp.json | VERIFIED | Harness contains .claude/skills, .claude/agents, .claude/settings.json with PostToolUse hooks, .mcp.json, .conjure-version "0.1.0" |
| `tests/fixtures/_emit-plugin/expected-plugin.json` | Golden expected plugin manifest | VERIFIED | Valid JSON; `name: "test-plugin"`, `version: "0.1.0"`, skills/agents/hooks/mcpServers fields present |
| `tests/fixtures/_emit-plugin/expected-marketplace.json` | Golden expected marketplace manifest | VERIFIED | Valid JSON; name/owner/plugins[] array present |
| `tests/fixtures/_emit-plugin/expected-settings.json` | Golden expected settings after marketplace wiring | VERIFIED | Valid JSON; extraKnownMarketplaces is object; hooks block preserved |
| `tests/fixtures/_emit-plugin-secret/harness/.claude-plugin/plugin.json` | Secret-containing fixture for PLUG-04-secret test | VERIFIED | Contains `"api_key": "testonly-fake-key-do-not-use-ABC123XYZ"` which matches the secret_scan ERE pattern |
| `tests/run.sh` | Phase 25 graceful-red block with 15 PLUG-* tests | VERIFIED | Section header "Phase 25 — Plugin + Marketplace Emission (PLUG-01..PLUG-05)" present; all 15 PLUG-* test tags present; PASS: 485 FAIL: 0 on current codebase |
| `scripts/audit-setup.sh` | Plugin reconciliation + ref-without-sha warning sections | VERIFIED | Plugin reconciliation section at line 177; ref-without-sha section at line 202; both use `note` helper (advisory, exit 0); `conjure publish-plugin` re-run hint present |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `cli/conjure cmd_publish_plugin` | `scripts/emit-plugin.sh` | `bash "$CONJURE_HOME/scripts/emit-plugin.sh"` with env vars | VERIFIED | Line 534: `publish-plugin) shift; cmd_publish_plugin "$@"` dispatches to `cmd_publish_plugin` which sets env vars and calls `emit-plugin.sh` |
| `scripts/emit-plugin.sh` | `lib/plugin-helpers.sh` | `source "$CONJURE_HOME/lib/plugin-helpers.sh"` | VERIFIED | Line 18 in emit-plugin.sh |
| `scripts/emit-plugin.sh` | `lib/mutate.sh` | `mutate_write` for all filesystem writes | VERIFIED | Lines 106, 151 use `mutate_write`; `plugin_wire_settings` also calls `mutate_write` (lib/plugin-helpers.sh line 420) |
| `scripts/publish-plugin.sh` | `lib/plugin-helpers.sh` | `source "$CONJURE_HOME/lib/plugin-helpers.sh"` | VERIFIED | Line 20 in publish-plugin.sh |
| `scripts/emit-plugin.sh --marketplace path` | `.claude-plugin/marketplace.json` | `mutate_write` after `reserved_name_check + secret_scan + validate_marketplace_json` | VERIFIED | Lines 133, 147-148, 151 in emit-plugin.sh |
| `scripts/emit-plugin.sh --marketplace path` | `.claude/settings.json` | `plugin_wire_settings` with keyed-object extraKnownMarketplaces merge | VERIFIED | Line 157 in emit-plugin.sh; `plugin_wire_settings` uses jq keyed-object pattern |
| `scripts/audit-setup.sh reconciliation section` | `.claude-plugin/plugin.json` | `jq -r '.skills // empty'` against on-disk `.claude/skills/` | VERIFIED | Lines 180-197 in audit-setup.sh; checks SKILL.md count via find |
| `scripts/audit-setup.sh ref-without-sha section` | `.claude/settings.json` | jq scanning extraKnownMarketplaces entries | VERIFIED | Lines 206-212 in audit-setup.sh; jq select with `.value.source.ref != null and .value.source.sha == null` |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|-------------------|--------|
| `scripts/emit-plugin.sh` | `RESOLVED_VERSION` | `resolve_version "$TARGET"` reads `.conjure-version` or `git rev-parse HEAD` | Yes | FLOWING |
| `scripts/emit-plugin.sh` | `PLUGIN_JSON` | `plugin_build_plugin_json` reads harness paths via find; reads existing plugin.json for merge | Yes | FLOWING |
| `scripts/emit-plugin.sh` | `MKT_JSON` | `plugin_build_marketplace_json` calls `detect_github_source` and `git rev-parse HEAD` | Yes | FLOWING |
| `lib/plugin-helpers.sh plugin_wire_settings` | `UPDATED` (settings.json) | jq keyed-object merge from `CURRENT` (read from disk) | Yes | FLOWING |
| `scripts/audit-setup.sh` | `PLUG_SKILLS_PATH` | `jq -r '.skills // empty' .claude-plugin/plugin.json` | Yes | FLOWING |
| `scripts/audit-setup.sh` | `REF_WITHOUT_SHA` | `jq -r '(.extraKnownMarketplaces // {}) | to_entries[] | select(...)' .claude/settings.json` | Yes | FLOWING |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| All PLUG-* tests pass | `bash tests/run.sh 2>&1 \| grep "PLUG-"` | 15 checks, all prefixed `✓` | PASS |
| Full test suite | `bash tests/run.sh 2>&1 \| tail -3` | PASS: 485 FAIL: 0 | PASS |
| shellcheck on lib/plugin-helpers.sh | `shellcheck -S error -e SC2164,SC2044,SC2034,SC2155 lib/plugin-helpers.sh` | Exit 0 | PASS |
| shellcheck on scripts/emit-plugin.sh | `shellcheck -S error -e SC2164,SC2044,SC2034,SC2155 scripts/emit-plugin.sh` | Exit 0 | PASS |
| shellcheck on scripts/audit-setup.sh | `shellcheck -S error -e SC2164,SC2044,SC2034,SC2155 scripts/audit-setup.sh` | Exit 0 | PASS |
| shellcheck on scripts/publish-plugin.sh | `shellcheck -S error -e SC2164,SC2044,SC2034,SC2155 scripts/publish-plugin.sh` | Exit 0 | PASS |
| plugin.schema.json is valid JSON | `jq empty .claude-plugin/SCHEMAS/plugin.schema.json` | Exit 0 | PASS |
| marketplace.schema.json is valid JSON | `jq empty .claude-plugin/SCHEMAS/marketplace.schema.json` | Exit 0 | PASS |
| Secret scan blocks before write (line order) | Lines 88-91 (secret_scan + validate) precede line 106 (mutate_write) | Confirmed in source | PASS |
| No exit 1 in new source files (convention: exit 2 only) | `grep "exit 1" lib/plugin-helpers.sh scripts/emit-plugin.sh` | Only in comment text, not executable | PASS |

### Probe Execution

No conventional `scripts/*/tests/probe-*.sh` probes declared for this phase. Tests are exercised via `tests/run.sh`.

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| PLUG-01 | 25-00, 25-01, 25-03 | `conjure publish-plugin` emits `.claude-plugin/plugin.json` from scaffolded harness | SATISFIED | `emit-plugin.sh` + `plugin_build_plugin_json`; PLUG-01, PLUG-01-merge, PLUG-01-greenfield/CR-01 tests all PASS |
| PLUG-02 | 25-00, 25-01, 25-02, 25-03 | `--marketplace` generates `marketplace.json` with kebab-case name, owner, plugins[]; reserved-name guard | SATISFIED | `plugin_build_marketplace_json` + `reserved_name_check`; PLUG-02, PLUG-02-reserved, PLUG-02-badpath tests PASS |
| PLUG-03 | 25-00, 25-02, 25-03 | Wires `extraKnownMarketplaces` (object form) + `enabledPlugins` into `.claude/settings.json` via idempotent merge | SATISFIED | `plugin_wire_settings` with keyed-object jq merge; PLUG-03 and PLUG-03-idem tests PASS |
| PLUG-04 | 25-00, 25-01, 25-03 | `--validate` runs `claude plugin validate` + JSON-schema check at emit time; refuses on invalid manifest | SATISFIED | `validate_plugin_json` runs unconditionally; `run_cli_validate` runs when `--validate` set; PLUG-04, PLUG-04-secret, PLUG-04-absent tests PASS; human verification needed for "claude present + valid" path |
| PLUG-05 | 25-00, 25-01, 25-03 | Version fallback: git SHA when `.conjure-version` absent | SATISFIED | `resolve_version` 3-tier chain in `lib/plugin-helpers.sh`; PLUG-05 and PLUG-05-blank tests PASS |

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `lib/plugin-helpers.sh` | 208 | `# Tier 3: placeholder` comment | Info | Not a stub — this is a descriptive code comment explaining that 0.0.0 is a placeholder version string emitted when no version source exists; the implementation (printf '0.0.0') is complete and intentional |

No blockers found. No `TBD`, `FIXME`, or `XXX` markers. No stub implementations. No orphaned artifacts.

### Human Verification Required

#### 1. `conjure publish-plugin --validate` with claude CLI installed and valid manifest

**Test:** On a machine with `claude` CLI installed (`command -v claude` returns a path), run `conjure publish-plugin --validate` in a repo with a valid `.claude/` harness. Observe that `claude plugin validate .` is actually invoked (can be confirmed via trace or output), exits 0, and `conjure` then exits 0 without blocking.

**Expected:** Exit 0; output contains lines from `claude plugin validate`; `.claude-plugin/plugin.json` is written.

**Why human:** The `run_cli_validate` success path (claude present + validate passes → return 0) cannot be tested without a real `claude` binary. The PLUG-04-absent test confirms the absent-claude path (exit 2) works correctly. The translate-exit-1-to-exit-2 path is also untestable without a failing `claude plugin validate` invocation. These branches are correctly implemented in the source but not covered by the automated suite.

### Gaps Summary

No gaps found. All 5 success criteria are verified with codebase evidence and automated test passage (485 PASS / 0 FAIL). One human verification item exists for the `claude plugin validate` success path, which requires the real `claude` CLI binary not available in CI.

---

_Verified: 2026-06-03T08:30:00Z_
_Verifier: Claude (gsd-verifier)_
