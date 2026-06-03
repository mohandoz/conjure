---
phase: 27-schema-version-aware-audit
verified: 2026-06-03T14:30:00Z
status: passed
score: 5/5
overrides_applied: 0
re_verification: false
---

# Phase 27: Schema-Version-Aware Audit — Verification Report

**Phase Goal:** `conjure audit` validates harnesses against the current Claude Code schema — catching deprecated keys, wrong types, and invalid hook events — and emits machine-readable JSON output consumed by workspace aggregation.
**Verified:** 2026-06-03T14:30:00Z
**Status:** PASSED
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | `conjure audit` validates SKILL.md frontmatter keys against full schema (incl. disallowed-tools as array OR space-string); no valid field rejected; object-typed disallowed-tools flagged (SCHM-01) | VERIFIED | `bash scripts/audit-setup.sh _schema-audit-badfield` → exit 2, output "Skill 'bad-skill': field 'disallowed-tools' is an object (YAML mapping) — expected array-or-space-string (SCHM-01)"; valid array/space-string forms produce no SCHM-01 error |
| 2 | `conjure audit` flags boolean disableBypassPermissionsMode (both top-level and permissions.*) with correct value in warning (SCHM-02) | VERIFIED | `bash scripts/audit-setup.sh _schema-audit-disablebypass` → exit 2, output "must be string \"disable\" (SCHM-02)" for both `.permissions.disableBypassPermissionsMode` and `.disableBypassPermissionsMode` paths |
| 3 | `conjure check` flags unknown/renamed hook event names against bundled lib/cc-schema.json; SessionStop→SessionEnd detected; cc-schema.json is bundled not fetched, ships all 30 current events (SCHM-03) | VERIFIED | `bash scripts/check.sh _schema-audit-hookevent` → exit 2, stderr "Hook event \"SessionStop\" was renamed — use \"SessionEnd\"" and "Unknown hook event \"UnknownEvent42\""; `jq '(.hook_events|length)' lib/cc-schema.json` = 30; zero-egress confirmed (no fetch/curl/wget in schema file) |
| 4 | `conjure check --schema` reports CC-introduced version per settings key; CC version detection falls back gracefully (WARN not fail) when claude absent; staleness advisory fires when cc-schema.json >90 days old (SCHM-04) | VERIFIED | `CONJURE_SCHEMA=1 bash scripts/check.sh valid/harness` → exit 1, stdout "hooks  introduced: all"; `PATH=/usr/bin:/bin CONJURE_SCHEMA=1 bash scripts/check.sh valid/harness` → "SCHM-04 [warn] claude not found on PATH" + exit ≤1; SCHM-STALE test suite case passes (stale fixture warns, not fails) |
| 5 | `conjure audit --json` emits machine-readable JSON (pass/fail + per-check results), consumable by Phase 29 workspace aggregation (SCHM-05) | VERIFIED | `CONJURE_JSON=1 bash scripts/audit-setup.sh valid/harness 2>/dev/null \| jq '.'` → `{"schema_version":"1","status":"warn","checks":[],"summary":{"pass":8,"warn":6,"fail":0}}`; disablebypass fixture → `{"status":"fail","checks":[...]}`  exit 2; zero non-JSON lines to stdout (grep count = 0); `cli/conjure audit --json` end-to-end confirmed |

**Score:** 5/5 truths verified

### SC Count Reconciliation

The ROADMAP success criteria reference "14-field schema" and "34 hook events". The authoritative live Claude Code v2.1.161 documentation establishes 16 SKILL.md frontmatter fields and 30 hook events. This reconciliation is documented in 27-RESEARCH.md and accepted per the verification context. `lib/cc-schema.json` carries the correct counts (`jq '(.hook_events|length)' lib/cc-schema.json` = 30; `jq '(.skill_frontmatter|keys|length)' lib/cc-schema.json` = 16). Phase goal is VERIFIED against the authoritative counts.

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `lib/cc-schema.json` | Bundled schema, 30 events, 16 skill fields, renamed_events | VERIFIED | schema_version="1", generated="2026-06-03", cc_version="2.1.161"; all jq assertions pass; zero-egress (no fetch/curl/wget) |
| `tests/fixtures/_schema-audit/valid/harness/.claude/skills/ok-skill/SKILL.md` | Valid fixture: known fields, array types | VERIFIED | Uses `allowed-tools: [Read, Bash]` YAML list + `user-invocable: false`; no SCHM-01 errors emitted |
| `tests/fixtures/_schema-audit-badfield/harness/.claude/skills/bad-skill/SKILL.md` | Negative: disallowed-tools as block-style YAML mapping | VERIFIED | `disallowed-tools:\n  Bash: true\n  Write: true` — block-style object; triggers SCHM-01 exit 2 |
| `tests/fixtures/_schema-audit-disablebypass/harness/.claude/settings.json` | Negative: boolean disableBypassPermissionsMode both paths | VERIFIED | `jq '(.disableBypassPermissionsMode\|type)'` = "boolean"; `jq '(.permissions.disableBypassPermissionsMode\|type)'` = "boolean" |
| `tests/fixtures/_schema-audit-hookevent/harness/.claude/settings.json` | Negative: renamed event SessionStop + unknown UnknownEvent42 | VERIFIED | `jq '.hooks\|has("SessionStop")'` = true; `jq '.hooks\|has("UnknownEvent42")'` = true |
| `tests/fixtures/_schema-audit-stale/cc-schema-stale.json` | Staleness fixture: generated = "2025-01-01" | VERIFIED | `jq '.generated'` = "2025-01-01" (>90 days before 2026-06-03) |
| `tests/run.sh` | Phase 27 SCHM block with 12 test cases | VERIFIED | "Phase 27 — Schema-Version-Aware Audit (SCHM-01..05)" header present; all 12 SCHM-* test IDs found; 48 total SCHM grep hits |
| `scripts/audit-setup.sh` | SCHM-01 type validation + SCHM-02 both-path check + SCHM-05 JSON mode | VERIFIED | SCHM-01 section (6 grep hits); json_check() + CONJURE_JSON + human() (17 grep hits); SCHM-02 replaces POL-05c (0 non-comment POL-05c references) |
| `scripts/check.sh` | SCHM-03 hook validation + SCHM-04 --schema report; SCHEMA_FAIL counter | VERIFIED | SCHEMA_FAIL count = 5 (declare + 2 increments + check + exit); hook_events/renamed_events/cc-schema.json references = 5; exit-code comment "2 = schema error" present |
| `cli/conjure` | --json flag → CONJURE_JSON=1; --schema flag → CONJURE_SCHEMA=1 | VERIFIED | `grep -c CONJURE_JSON cli/conjure` = 2; `grep -c CONJURE_SCHEMA cli/conjure` = 1; `grep -c -- '--json' cli/conjure` = 5; `grep -c -- '--schema' cli/conjure` = 3 |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| scripts/audit-setup.sh SCHM-01 section | lib/cc-schema.json | `jq -r '.skill_frontmatter \| keys[]'` | VERIFIED | `grep -c "skill_frontmatter.*keys" scripts/audit-setup.sh` ≥ 1; schema file read at runtime; graceful skip when absent |
| scripts/audit-setup.sh SCHM-02 section | .claude/settings.json | `jq -r "${_dbpm_path} \| type"` over both paths | VERIFIED | Two disableBypassPermissionsMode errors emitted for disablebypass fixture; `disableBypassPermissionsMode.*type` pattern found in audit-setup.sh |
| scripts/check.sh SCHM-03 section | lib/cc-schema.json | `jq -r '.hook_events[]'` and `'.renamed_events // {} \| to_entries[]'` | VERIFIED | `grep -c "hook_events.*cc-schema.json\|hook_events\[\]\|renamed_events" scripts/check.sh` = 5; no hardcoded event names in check.sh SCHM logic |
| cli/conjure cmd_check | scripts/check.sh | CONJURE_SCHEMA env var | VERIFIED | `CONJURE_SCHEMA="$schema" bash scripts/check.sh "$target"` in cmd_check; end-to-end `cli/conjure check --schema` test confirmed |
| cli/conjure cmd_audit | scripts/audit-setup.sh | CONJURE_JSON env var | VERIFIED | `CONJURE_JSON="$do_json" bash scripts/audit-setup.sh "$target"` in cmd_audit; preflight routed to stderr in JSON mode (`>/dev/stderr 2>&1`) |
| scripts/audit-setup.sh CONJURE_JSON mode | Phase 29 conjure workspace audit | stdout JSON {schema_version, status, checks, summary} | VERIFIED | `CONJURE_JSON=1 bash scripts/audit-setup.sh valid/harness 2>/dev/null \| jq -r 'keys\|sort\|join(",") '` = "checks,schema_version,status,summary"; JSON contract established with stable check IDs |
| tests/run.sh Phase 27 block | scripts/audit-setup.sh | P27_AUDIT_OK presence guard | VERIFIED | `grep -c "P27_AUDIT_OK" tests/run.sh` = 11; guard prevents silent pass when implementation absent |
| tests/run.sh Phase 27 block | lib/cc-schema.json | SCHEMA_FILE variable | VERIFIED | `grep -c "SCHEMA_FILE.*lib/cc-schema.json" tests/run.sh` = 1; SCHM-SCHEMA test independently verifies schema structure |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|--------------------|--------|
| scripts/audit-setup.sh SCHM-01 | KNOWN_FIELDS | `jq -r '.skill_frontmatter \| keys[]' lib/cc-schema.json` | Yes — 16 fields from bundled schema | FLOWING |
| scripts/audit-setup.sh SCHM-02 | _dbpm_type | `jq -r "${_dbpm_path} \| type" .claude/settings.json` | Yes — type check on live file | FLOWING |
| scripts/check.sh SCHM-03 | KNOWN_EVENTS, RENAMED_ENTRIES | `jq -r '.hook_events[]'` and `'.renamed_events // {} \| to_entries[]'` from lib/cc-schema.json | Yes — 30 events + 1 renamed entry | FLOWING |
| scripts/audit-setup.sh SCHM-05 | CHECKS_JSONL | json_check() appends to mktemp file; jq --slurpfile reads at emit | Yes — real check results accumulated | FLOWING |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| SCHM-01: object disallowed-tools → exit 2 | `CONJURE_HOME=$(pwd) bash scripts/audit-setup.sh tests/fixtures/_schema-audit-badfield/harness` | exit 2, "field 'disallowed-tools' is an object (YAML mapping) — expected array-or-space-string (SCHM-01)" | PASS |
| SCHM-01: valid SKILL.md → no error | `CONJURE_HOME=$(pwd) bash scripts/audit-setup.sh tests/fixtures/_schema-audit/valid/harness` | exit 1 (warn only, no SCHM-01 error), PASS:8 WARN:6 FAIL:0 | PASS |
| SCHM-01: unknown field → warn not fail | `CONJURE_HOME=$(pwd) bash scripts/audit-setup.sh <tmpdir with unknown field>` | "unknown frontmatter field 'totally_unknown_field' (not in CC schema — SCHM-01)" as WARN (⚠), exit not driven by SCHM-01 | PASS |
| SCHM-02: boolean DBPM both paths → exit 2 | `CONJURE_HOME=$(pwd) bash scripts/audit-setup.sh tests/fixtures/_schema-audit-disablebypass/harness` | exit 2, two "must be string \"disable\" (SCHM-02)" errors | PASS |
| SCHM-03: SessionStop → exit 2 with renamed message | `CONJURE_HOME=$(pwd) bash scripts/check.sh tests/fixtures/_schema-audit-hookevent/harness 2>&1` | exit 2, stderr "Hook event \"SessionStop\" was renamed — use \"SessionEnd\"" | PASS |
| SCHM-03: UnknownEvent42 → exit 2 with unknown message | Same command as above | exit 2, stderr "Unknown hook event \"UnknownEvent42\" — not in CC schema v2.1.161" | PASS |
| SCHM-04: --schema emits introduced: lines | `CONJURE_HOME=$(pwd) CONJURE_SCHEMA=1 bash scripts/check.sh tests/fixtures/_schema-audit/valid/harness 2>&1` | stdout "hooks  introduced: all", exit 1 (drift only), no exit 2 | PASS |
| SCHM-04: claude absent → WARN not fail | `PATH=/usr/bin:/bin CONJURE_SCHEMA=1 bash scripts/check.sh valid/harness 2>&1` | "SCHM-04 [warn] claude not found on PATH — using bundled schema baseline", exit ≤1 | PASS |
| SCHM-05: JSON stdout parseable | `CONJURE_HOME=$(pwd) CONJURE_JSON=1 bash scripts/audit-setup.sh valid/harness 2>/dev/null \| jq -e '.schema_version and .status and (.checks \| type == "array") and .summary'` | exit 0 | PASS |
| SCHM-05: JSON keys complete | `... \| jq -r 'keys \| sort \| join(",")'` | "checks,schema_version,status,summary" | PASS |
| SCHM-05: fail fixture → exit 2, status:"fail" | `CONJURE_JSON=1 bash scripts/audit-setup.sh _schema-audit-disablebypass 2>/dev/null` | exit 2, JSON `{"status":"fail","checks":[...],"summary":{"fail":3,...}}` | PASS |
| SCHM-05: zero non-JSON lines to stdout | `CONJURE_JSON=1 bash scripts/audit-setup.sh valid/harness 2>/dev/null \| grep -v '^{' \| grep -v '^}' \| wc -l` | 0 | PASS |
| CLI end-to-end --json | `CONJURE_HOME=$(pwd) bash cli/conjure audit --json tests/fixtures/_schema-audit-disablebypass/harness 2>/dev/null` | exit 2, pure JSON stdout with status:"fail" | PASS |
| CLI end-to-end --schema | `CONJURE_HOME=$(pwd) bash cli/conjure check --schema tests/fixtures/_schema-audit/valid/harness 2>&1 \| grep "introduced"` | "Settings keys in this harness and CC version introduced:" + "hooks  introduced: all" | PASS |

### Probe Execution

No explicit probe scripts declared for this phase. The `bash tests/run.sh` suite serves as the authoritative probe.

| Probe | Command | Result | Status |
|-------|---------|--------|--------|
| Full test suite | `bash tests/run.sh` | PASS: 523  FAIL: 0 — all SCHM-* and pre-existing tests green | PASS |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| SCHM-01 | 27-00, 27-01 | SKILL.md frontmatter validation against 16-field schema | SATISFIED | SCHM-01-badtype, SCHM-01-valid, SCHM-01-unknown test cases all PASS in suite; live codebase spot-check confirmed |
| SCHM-02 | 27-01 | disableBypassPermissionsMode boolean detection, both paths | SATISFIED | SCHM-02-permissions, SCHM-02-toplevel PASS; POL-05c replaced with no regression |
| SCHM-03 | 27-02 | Hook event validation against bundled cc-schema.json | SATISFIED | SCHM-03-renamed, SCHM-03-unknown PASS; 30 events confirmed in schema; no hardcoded event names in check.sh |
| SCHM-04 | 27-02 | --schema per-key CC version report; graceful claude-absent fallback | SATISFIED | SCHM-04-schema PASS; claude absent → WARN confirmed; staleness advisory fires for stale fixture |
| SCHM-05 | 27-03 | audit --json machine-readable output with stable check IDs | SATISFIED | SCHM-05-json, SCHM-05-exit2, SCHM-STALE all PASS; JSON shape verified; CONJURE_JSON wired in cli/conjure |

All 5 requirement IDs from PLAN frontmatter (SCHM-01 through SCHM-05) are fully accounted for. REQUIREMENTS.md marks all five as `[x] Complete` for Phase 27.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| (none) | — | — | — | — |

Scanned: `lib/cc-schema.json`, `scripts/audit-setup.sh`, `scripts/check.sh`, `cli/conjure`, `tests/run.sh`. No TBD/FIXME/XXX markers found. No placeholder returns or hardcoded empty data. No unreferenced stubs. Shellcheck `-S error -e SC2164,SC2044,SC2034,SC2155` passes clean on all three shell files.

### Human Verification Required

None. All success criteria were verifiable programmatically:

- SCHM-01/02: direct fixture invocation with exit code and output assertions
- SCHM-03: hook event fixture exits 2 with correct renamed/unknown messages
- SCHM-04: `--schema` flag produces per-key output; claude-absent fallback tested with minimal PATH
- SCHM-05: JSON stdout purity and parse confirmed via jq; exit codes confirmed
- Full test suite (523 PASS / 0 FAIL) executed and confirmed in this session

The one item listed in the verification context as potentially human_needed — "SCHM-04 present-path version compare" — was verified automatically: `claude --version` = 2.1.161 matches `cc_version` in schema; SCHM-04 report prints "Detected CC version: 2.1.161"; the version-newer-than-schema warning path was covered by the WR-05 test case in the suite. No human verification needed.

### Gaps Summary

No gaps. All 5 must-have truths are VERIFIED with codebase evidence. Full test suite passes (523/0). Shellcheck clean on all three shell files. Requirements SCHM-01 through SCHM-05 fully satisfied.

---

_Verified: 2026-06-03T14:30:00Z_
_Verifier: Claude (gsd-verifier)_
