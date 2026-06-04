# Phase 27: Schema-Version-Aware Audit - Context

**Gathered:** 2026-06-03
**Status:** Ready for planning
**Mode:** Smart discuss (autonomous — all 4 grey areas accepted as recommended)

<domain>
## Phase Boundary

`conjure audit` and `conjure check` become schema-version-aware: they validate harnesses
against a bundled, Conjure-maintained snapshot of the current Claude Code schema —
catching deprecated/unknown SKILL.md frontmatter keys and wrong types, boolean-vs-string
`disableBypassPermissionsMode`, unknown/renamed hook event names, and per-key
CC-version-introduced reporting — and `conjure audit --json` emits machine-readable output
consumed by Phase 29's `conjure workspace audit` aggregation.

Implements SCHM-01..05. (WS-01/WS-04 listed in REQUIREMENTS under this section belong to
the workspace phases 29/30, not here.) Future SCHM-F1 (`--strict` allowed-tools×matcher
cross-validation) and SCHM-F2 (schema self-update notice) are deferred.

Non-goals (locked, from REQUIREMENTS):
- No auto-fix / settings.json rewrite — emit the correct key/value, the user applies.
- Never hard-fail on a CC version mismatch / newer-than-known schema — WARN, never break CI.
- No runtime fetch of the CC schema — bundle `lib/cc-schema.json`, update via Conjure release (zero-egress-in-CI).

</domain>

<decisions>
## Implementation Decisions

### cc-schema.json Shape & Maintenance
- A SINGLE bundled file `lib/cc-schema.json` with sections:
  `{ schema_version, generated (ISO date), hook_events[], settings_keys{ key: introduced_version }, skill_frontmatter{ field: type } }`.
- Ships with all 34 current hook events and the full 14-field SKILL.md frontmatter schema
  (including `disallowed-tools` accepted as EITHER an array OR a space-separated string).
- Staleness advisory (>90 days) is computed from the top-level `generated` ISO date field
  (NOT file mtime — survives checkout/copy). Fires WARN (never ERR).
- Conjure-maintained: committed to the repo, updated manually per Claude Code release; a
  header/`_comment` field cites the source + CC version it reflects. ZERO runtime fetch.
- CC version detection parses `claude --version`; when `claude` is not on PATH, WARN and
  continue (never fail) — the bundled schema is still usable for structural checks.

### --json Output Contract (audit)
- Shape: `{ schema_version, status: "pass"|"fail", checks: [ { id, severity, message } ], summary: { pass, warn, fail } }`.
  Stable, documented, and consumed by Phase 29 `conjure workspace audit` aggregation.
- `conjure audit --json` emits ONLY JSON to stdout (human-readable text suppressed or routed
  to stderr) so the output is cleanly machine-parseable.
- Exit code semantics: still `exit 2` on fail even with `--json` (so CI gating works); the
  `status` field mirrors the exit code. WARN-only → exit follows the existing audit summary
  contract (`[ "$WARN" -gt 0 ] && exit 1`).
- Each check carries a STABLE `id` (e.g. `SCHM-01-skill-field`, `SCHM-02-disablebypass`,
  `SCHM-03-hook-event`, `SCHM-04-version`, plus existing audit check IDs) usable as an
  aggregation key downstream.

### Severity Mapping
- `fail` (exit 2) for hard correctness bugs:
  - invalid SKILL.md frontmatter field TYPE (e.g. `disallowed-tools: {Bash: true}`) — SCHM-01.
  - unknown/renamed hook event name (e.g. `SessionStop` instead of `SessionEnd`) — a renamed
    event silently no-ops, so it is a real bug — SCHM-03.
  - `disableBypassPermissionsMode` boolean instead of string `"disable"`, with the correct
    value in the warning message — SCHM-02 (consistent with Phase 26 POL-05c).
- `warn` (exit 1 via existing audit summary gate) for forward-compat / advisory:
  - unknown SKILL.md frontmatter field not in the 14-field set (newer CC schema must not hard-
    fail the audit — mirrors the "never hard-fail on newer schema" non-goal).
  - `cc-schema.json` older than 90 days (staleness advisory).
- `info` for SCHM-04 per-key CC-version-introduced reporting (informational, never blocks).
- Reuse the Phase 25/26 convention: `note()` for advisory (exit 0 contribution), `warn()` for
  WARN-counter advisories, `err()`/fail for exit-2 bugs. (audit-setup.sh's pre-existing
  `[ "$WARN" -gt 0 ] && exit 1` summary gate is the established contract — left untouched.)

### check vs audit Responsibility
- Mirrors the ROADMAP success-criteria wording exactly:
  - `conjure audit` owns: SKILL.md frontmatter validation (SCHM-01), `disableBypassPermissionsMode`
    type check (SCHM-02), and `--json` output (SCHM-05).
  - `conjure check` owns: unknown/renamed hook-event detection (SCHM-03) and the new
    `conjure check --schema` per-key CC-version-introduced report (SCHM-04).
- `--schema` is a NEW flag on the existing `conjure check` (scripts/check.sh); `check` keeps
  its existing `--porcelain` flag.
- `--json` is added to `conjure audit` ONLY (SCHM-05 scopes it to audit); `check` keeps
  `--porcelain` for its machine output. Not symmetric — keep the surface minimal.
- The `claude`-absent path WARNs and continues for both commands.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `scripts/audit-setup.sh` — the audit worker; has `note()`/`warn()`/`err()`/`pass()` helpers
  and the `[ "$WARN" -gt 0 ] && exit 1` summary gate + `FAIL → exit 2`. New SCHM-01/02 checks
  + the `--json` emitter attach here. Phase 25/26 added advisory + fail sections as precedent.
- `scripts/check.sh` (`cmd_check`, `--porcelain`) — the drift checker; new SCHM-03 hook-event
  check + `--schema` version report attach here.
- `cli/conjure` — `cmd_audit` / `cmd_check` dispatch + usage lines; add `--json` to audit usage
  and `--schema` to check usage (mirror how Phase 25/26 added flags).
- `lib/caps.sh`, `scripts/publish-skill.sh`, `lib/inventory.sh` — existing SKILL.md frontmatter
  parsing/handling to reuse for the 14-field validation (don't reinvent the YAML reader).
- `.conjure-version` reader (used in Phase 25/26 `resolve_version`) — the pinned CC version
  baseline for the SCHM-04 version comparison.
- `tests/run.sh` + `tests/fixtures/` — fixture harness; add `_schema-audit*` fixtures + a
  graceful-red SCHM block first (test-first convention; mirror Phase 25/26 `_emit-*` pattern).
- jq is the bundled JSON tool — use it to read `lib/cc-schema.json` and build `--json` output.

### Established Patterns
- POSIX bash 3.2+ (no associative arrays / mapfile / local -n); inline shellcheck dirs;
  CI gate `shellcheck -S error -e SC2164,SC2044,SC2034,SC2155`.
- Hooks/CLI/scripts `exit 2`, never `exit 1` (audit summary gate's `exit 1` is the documented
  exception). Non-TTY → exit 2.
- Bundled JSON schema pattern from Phase 25 (`.claude-plugin/SCHEMAS/*.json`) and Phase 26
  (managed-settings validation) — `lib/cc-schema.json` follows the same "bundle + validate at
  runtime, never fetch" approach.

### Integration Points
- `lib/cc-schema.json` (NEW) — the bundled schema snapshot; read by both audit and check.
- New audit section(s) in `scripts/audit-setup.sh` (SCHM-01/02) + a `--json` output path.
- New check logic in `scripts/check.sh` (SCHM-03 hook events, SCHM-04 `--schema`).
- `cli/conjure` flag wiring: `audit --json`, `check --schema`.
- `conjure audit --json` output is the contract Phase 29 `conjure workspace audit` parses —
  keep the shape stable and documented.

</code_context>

<specifics>
## Specific Ideas

- The 14 SKILL.md frontmatter fields are the Conjure-maintained set (NOT the stale VS Code
  schema). `disallowed-tools` MUST accept both an array and a space-separated string; neither
  form is rejected. An invalid type like `disallowed-tools: {Bash: true}` is flagged (fail).
- `disableBypassPermissionsMode` boolean `true` → fail with a message naming the correct value
  (string `"disable"`).
- Hook-event table: all 34 current events; `SessionStop` (renamed) → flagged in favor of
  `SessionEnd`. The event table lives in `lib/cc-schema.json`, not hardcoded in check.sh.
- `conjure check --schema` reports, per settings key found in the harness, which CC version
  introduced it, compared against the pinned `.conjure-version`.
- The `--json` output is the load-bearing integration for Phase 29 — every check needs a
  stable `id` and `severity` so aggregation is deterministic.

</specifics>

<deferred>
## Deferred Ideas

- SCHM-F1: `conjure audit --strict` cross-validates `allowed-tools` vs hook `matcher` patterns.
- SCHM-F2: schema-table self-update notice from `claude --version` in connected environments.
- WS-01 / WS-04: `.conjure-workspace.json` manifest + `conjure workspace audit` aggregation —
  these are Phase 29 (Workspace Read-Only), consuming this phase's `--json` output.

</deferred>
