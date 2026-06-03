# Phase 26: Sandbox + Managed-Settings / MDM - Context

**Gathered:** 2026-06-03
**Status:** Ready for planning
**Mode:** Smart discuss (autonomous — all 4 grey areas accepted as recommended)

<domain>
## Phase Boundary

Each compliance overlay (hipaa/soc2/gdpr/pci) emits a deployable, testable security
policy — a regime-specific `sandbox{}` block merged into `.claude/settings.json`, a
`managed-settings.json`, and platform-tagged MDM artifacts (macOS plist + Windows
PowerShell/registry setter) — and `conjure audit` can verify each artifact is present,
correctly typed, and internally consistent.

Implements POL-01..05. Future items POL-F1 (`managed-settings.d/` drop-in fragments),
POL-F2 (`_conjure_source` provenance), POL-F3 (`policyHelper`) are explicitly deferred.

Non-goals (locked, from REQUIREMENTS): no auto-deploy via Jamf/Intune APIs; never claim
overlays make a project "compliant" (keep the "reduces non-compliant output" disclaimer);
no repo-scanning to auto-detect credential paths — ship standard per-regime deny patterns.

</domain>

<decisions>
## Implementation Decisions

### CLI Surface & Invocation
- New dedicated command `conjure emit-policy --regime hipaa|soc2|gdpr|pci [--output DIR]`,
  parallel to `emit-plugin`/`publish-plugin`. Do NOT overload existing `--overlay=<git-url>`
  (that is the org git-URL overlay) — regime selection is via `--regime`.
- The `sandbox{}` block is written into the target `.claude/settings.json` via `jq` +
  `mutate_write` (POL-01 mandates an in-settings merge, not a sidecar file).
- `managed-settings.json` + MDM artifacts are written to a caller-specified `--output DIR`;
  when omitted, default to `./conjure-policy/` inside the target. NEVER auto-place at system
  paths (e.g. `/Library/Application Support/...`, `C:\ProgramData\...`).
- A single `emit-policy` command emits all three artifact types together; subset flags
  `--managed-only` and `--mdm-only` narrow the emission.

### Audit Severity & Detection
- POL-05 check severities: `fail` (exit 2) for hard correctness bugs — `disableBypassPermissionsMode`
  wrong type (boolean instead of string), and overlay active but sandbox missing or
  `enabled:false`. Advisory `note` (exit 0) for "unreviewed policy template".
  (Phase 25 lesson: `warn()` increments WARN and flips audit exit code — reserve `warn()`/`fail`
  for genuine errors, use `note()` for advisory.)
- `denyRead` path with no mirrored `Read(...)` permissions.deny entry → `fail` (exit 2)
  (POL-02 is an enforcement-gap closure, not advisory).
- Policy checks auto-run when an overlay is detected active; `--compliance` flag forces the
  full compliance audit even when no active overlay is detected.
- "Active overlay" detection: presence of the `<!-- compliance:REGIME -->` marker in CLAUDE.md
  (already emitted by `compliance/<regime>/apply.sh`) together with a sandbox block.
- "Unreviewed template" detection: a sentinel left in the emitted template (the
  `REPLACE_WITH_ORG_UUID` placeholder still present, and/or a `_conjure_unreviewed` marker);
  audit warns until the operator customizes/removes it.

### Artifact Content & Safety Defaults
- `forceLoginOrgUUID` ships as the literal placeholder `"REPLACE_WITH_ORG_UUID"` — obviously
  fake so it fails validation if shipped unreviewed.
- `disableBypassPermissionsMode` is the STRING `"disable"` (never boolean) — assert in tests.
- Windows managed-settings: a single `managed-settings.json` for v1. The `managed-settings.d/`
  numbered drop-in directory is POL-F1 and is deferred (STATE flagged Windows drop-in behavior
  as MEDIUM confidence — verify before pulling forward).
- MDM bundle: macOS `com.anthropic.claudecode.plist` + Windows `Set-ClaudeCodePolicy.ps1`
  (registry root `HKLM\SOFTWARE\Policies\ClaudeCode`). The deprecated Windows path
  `C:\ProgramData\ClaudeCode\` is NEVER emitted.
- Each emitted artifact ships with a printed, testable verification assertion (e.g.
  "Verify: `claude config get sandbox.enabled` must return true") to stdout AND persisted to
  a file in the output dir, so no overlay ships without a live-verification step.
- All settings.json mutation routes through `mutate_write` (snapshot-before-mutate) with an
  idempotent `jq` merge — re-running `emit-policy` produces an identical sandbox block.

### Per-Regime Sandbox Content
- Per-regime `denyRead`/`denyWrite`/`network.allowedDomains` deny lists ship as standard
  patterns under `compliance/<regime>/` (no repo scanning — see non-goals).
- Structure: a shared secure baseline (deny secrets/keys/`.env`/credential dirs) plus
  per-regime deltas (HIPAA → PHI paths; PCI → cardholder-data paths; etc.).
- `network.allowedDomains` defaults to EMPTY = deny-all egress (most secure; operator adds
  domains). Not a baseline allowlist.
- Every `sandbox.filesystem.denyRead` path is mirrored 1:1 into `permissions.deny` as
  `Read(<path>)` (POL-02 — closes the Read-tool enforcement gap #32226).

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `lib/mutate.sh` — `mutate_write` (snapshot-before-mutate routing), `mutate_mkdir`, `mutate_cp`,
  `mutate_summary`; `DRY_RUN` env honored. All target mutations MUST route through here.
- `lib/snapshot.sh` — `snapshot_create` blessed backup (used by adopt/emit-plugin); reuse the
  same backup-root convention established in Phase 25.
- `lib/plugin-helpers.sh` (Phase 25) — reference pattern for an emit worker: jq merge-base `.`,
  `validate_*_json` gate before every `mutate_write`, exit 2 on invalid, idempotent jq.
- `scripts/emit-plugin.sh` + `cmd_publish_plugin` dispatch in `cli/conjure` — the structural
  template for a new `scripts/emit-policy.sh` + `cmd_emit_policy` + `emit-policy)` dispatch.
- `compliance/<regime>/apply.sh` + `CLAUDE.md.fragment` — existing overlay apply path; emits the
  `<!-- compliance:REGIME -->` marker the audit detection keys off. HIPAA also ships
  `CONTROLS.md` + `pre-commit-phi-scan.sh`.
- `scripts/audit-setup.sh` — existing advisory sections (plugin reconciliation, ref-without-sha)
  show the `note()` advisory pattern (exit 0) and where to add new policy checks before the
  summary block.
- `.claude-plugin/SCHEMAS/*.json` (Phase 25) — pattern for shipping bundled JSON schemas; a
  `sandbox`/`managed-settings` schema can follow the same bundling + validate-at-emit approach.
- `tests/run.sh` — fixture-based regression harness; Phase 25 added `_emit-plugin*` fixtures.
  Mirror with `_emit-policy*` fixtures + expected artifacts (graceful-red block first per
  test-first convention).

### Established Patterns
- POSIX bash 3.2+ only (no associative arrays / mapfile / `local -n`); inline shellcheck dirs;
  CI gate `shellcheck -S error -e SC2164,SC2044,SC2034,SC2155`.
- Hooks/CLI/scripts `exit 2`, never `exit 1`. Non-TTY → exit 2, never auto-mutate.
- Emit workers validate before write and refuse to write any file when invalid (no silent no-op).

### Integration Points
- New `cmd_emit_policy` in `cli/conjure` + `emit-policy)` case in the dispatch switch + usage line.
- New `scripts/emit-policy.sh` worker; shared logic in a new `lib/policy-helpers.sh`
  (independent of `lib/plugin-helpers.sh`, per the roadmap dependency note).
- New audit sections in `scripts/audit-setup.sh` (POL-05 checks) keyed off the CLAUDE.md
  compliance marker.
- Per-regime deny-pattern data files under `compliance/<regime>/`.

</code_context>

<specifics>
## Specific Ideas

- Managed-settings keys are exact and type-sensitive: `disableBypassPermissionsMode:"disable"`
  (STRING), `allowManagedPermissionRulesOnly`, `forceLoginOrgUUID:"REPLACE_WITH_ORG_UUID"`,
  plus the regime sandbox block.
- macOS plist domain: `com.anthropic.claudecode`. Windows registry root:
  `HKLM\SOFTWARE\Policies\ClaudeCode`. Deprecated path `C:\ProgramData\ClaudeCode\` forbidden.
- Audit must catch a deliberately-broken managed-settings artifact (wrong key name or type) —
  include a negative fixture proving detection.
- Keep the "Compliance ≠ Config / engage your compliance officer" disclaimer in all emit output.

</specifics>

<deferred>
## Deferred Ideas

- POL-F1: `managed-settings.d/` numbered drop-in fragments (composable layered policy).
- POL-F2: `_conjure_source` provenance annotations in emitted managed-settings.
- POL-F3: `policyHelper` script generation for dynamic org policy.
- WS-F2: `conjure workspace emit-managed` (union managed-settings across mixed-compliance repos)
  — belongs to the workspace phases (29/30), not here.

</deferred>
