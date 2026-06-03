# Roadmap: Conjure

## Completed Milestones

- **v0.3.0** — "Testing + Telemetry" — 7 phases, 22 plans, 20/20 requirements satisfied, 169 commits (2026-05-24 → 2026-05-25) — [Archive](.planning/milestones/v0.3.0-ROADMAP.md)
- **v0.4.0** — "Distribution + Ecosystem" — 9 phases, 23 plans, 29/29 requirements satisfied, 136 commits (2026-05-25 → 2026-05-26) — [Archive](.planning/milestones/v0.4.0-ROADMAP.md)
- **v0.5.0** — "Auto-Update + Healthcheck" — 5 phases, 10 plans, 11/11 requirements satisfied, 49 commits (2026-05-26 → 2026-05-28) — [Archive](.planning/milestones/v0.5.0-ROADMAP.md)
- **v0.6.0** — "Safe Brownfield Adoption" — 4 phases, 12 plans, 23/23 requirements satisfied, ~104 commits (2026-05-28 → 2026-05-29) — [Archive](.planning/milestones/v0.6.0-ROADMAP.md)

## Active Milestone

**v0.7.0 — Plugin-native + Policy-grade** (started 2026-06-03)

27 requirements across 5 capability areas; 6 phases (25–30).
Build order: Plugin → Policy/MDM → Schema-audit → Eval → Workspace (read-only) → Workspace (mutating + saga).

## Phases

<details>
<summary>✅ v0.6.0 Safe Brownfield Adoption (Phases 21-24) — SHIPPED 2026-05-29</summary>

- [x] **Phase 21: Foundation Libs + Inventory** — `lib/log.sh`, `lib/snapshot.sh`, `lib/inventory.sh`, `lib/caps.sh` + finalized `adopt-manifest.json` schema with 6-bucket classification (completed 2026-05-28)
- [x] **Phase 22: `conjure adopt` CLI Core + Rollback** — `scripts/adopt.sh` + `cmd_adopt`, 5-step pipeline, `--dry-run`/`--force`/`--rollback`/`--apply-step`/`--update-manifest`, `.conjure-adopt-state` schema, signal traps, partial-run recovery (completed 2026-05-28)
- [x] **Phase 23: Restructure Skill + Safety Gates** — human-gated `restructure` skill (`[Read, Bash]`) + 5 gate helpers (verify-invariants, audit-staged, extract-invariants, decision-scan, approve) riding the adopt seam (completed 2026-05-29)
- [x] **Phase 24: Integration Tests + Argus Fixture** — 500-file `_brownfield-argus` generator + E2E `▸ Phase 24` test block (dry-run perf, rollback zero-diff, idempotent re-run, SIGKILL recovery, symlink-skip + @import-block) (completed 2026-05-29)

</details>

**v0.7.0 Plugin-native + Policy-grade**

- [x] **Phase 25: Plugin + Marketplace Emission** — `lib/plugin-helpers.sh` + `scripts/emit-plugin.sh` + `conjure publish-plugin` (plugin.json, marketplace.json, `extraKnownMarketplaces` wiring, `--validate` gate, version-fallback SHA) (completed 2026-06-03)
- [x] **Phase 26: Sandbox + Managed-Settings / MDM** — `lib/policy-helpers.sh` + all 4 compliance overlays gain `--emit-policy`; sandbox block + `permissions.deny` mirror; `managed-settings.json`; MDM plist + Windows PS1; `conjure audit` policy flags (completed 2026-06-03)
- [x] **Phase 27: Schema-Version-Aware Audit** — `lib/cc-schema.json` (bundled); `audit` validates SKILL.md frontmatter + hook event names + `disableBypassPermissionsMode` type; `conjure check --schema` version-gates; `conjure audit --json` machine-readable output (completed 2026-06-03)
- [x] **Phase 28: promptfoo Eval + Context-Budget Linter** — `scripts/eval.sh` + `conjure eval init/run/--emit-workflow`; `templates/evals/`; `conjure audit --budget` static context linter; `conjure audit` eval-coverage gap report (completed 2026-06-03)
- [x] **Phase 29: Workspace Orchestration — Read-Only** — `.conjure-workspace.json` manifest + schema; `conjure workspace init` (TTY discovery); `conjure workspace check` (per-repo porcelain aggregation); `conjure workspace audit` (per-repo --json aggregation + global summary) (completed 2026-06-03)
- [ ] **Phase 30: Workspace Orchestration — Mutating + Rollback Saga** — `lib/workspace.sh` + `scripts/workspace.sh` saga pipeline (preflight-all → snapshot-all → ops-serial → aggregate-report); `conjure workspace update`; `conjure workspace adopt`; `--rollback` saga + SIGKILL durability CI fixture

## Phase Details

### Phase 25: Plugin + Marketplace Emission

**Goal**: Developers can generate, validate, and wire a Claude Code plugin + marketplace manifest from their conjure-scaffolded harness in one command
**Depends on**: Nothing (builds on shipped `lib/mutate.sh` + existing `.claude-plugin/` stub)
**Requirements**: PLUG-01, PLUG-02, PLUG-03, PLUG-04, PLUG-05
**Success Criteria** (what must be TRUE):

  1. `conjure publish-plugin` produces `.claude-plugin/plugin.json` with correct `skills`/`agents`/`hooks`/`mcpServers` paths and `version` from `.conjure-version` (or current git SHA as fallback when version absent)
  2. `conjure publish-plugin --marketplace` produces a valid `.claude-plugin/marketplace.json` with kebab-case name, owner, plugins[] with source; reserved-name guard rejects Anthropic-controlled names with exit 2
  3. `conjure publish-plugin --validate` calls `claude plugin validate .` and a JSON-schema check at emit time — exits 2 and refuses to write any file when the manifest is invalid (no silent no-op)
  4. `conjure publish-plugin` wires `extraKnownMarketplaces` (object form) and `enabledPlugins` into `.claude/settings.json` via idempotent `mutate_write` merge; `conjure audit` flags a `ref`-without-`sha` marketplace entry with a warning
  5. `conjure audit` detects when `.claude-plugin/plugin.json` is out of sync with actual `.claude/` contents (reconciliation check); `conjure publish-plugin` on a fixture with a secret-pattern value in the `env` block exits 2 before writing any file

**Plans**: 4 plans
Plans:
**Wave 1**

- [x] 25-00-PLAN.md — Wave 0: golden fixtures + tests/run.sh Phase 25 graceful-red block (Nyquist)
- [x] 25-01-PLAN.md — Wave 1: lib/plugin-helpers.sh + JSON schemas + scripts/emit-plugin.sh + CLI dispatch (PLUG-01, PLUG-04, PLUG-05)

**Wave 2** *(blocked on Wave 1 completion)*

- [x] 25-02-PLAN.md — Wave 2a: --marketplace + --enable paths in emit-plugin.sh (PLUG-02, PLUG-03)
- [x] 25-03-PLAN.md — Wave 2b: audit-setup.sh reconciliation + ref-without-sha warnings (SC-25 criteria 4+5)

**UI hint**: no

### Phase 26: Sandbox + Managed-Settings / MDM

**Goal**: Each compliance overlay emits a deployable, testable security policy — sandbox block, managed-settings.json, and platform-tagged MDM artifacts — that `conjure audit` can verify is live and correct
**Depends on**: Phase 25 (emit-and-verify pattern established; `lib/policy-helpers.sh` is independent of `lib/plugin-helpers.sh` but ships after the verification discipline is proven)
**Requirements**: POL-01, POL-02, POL-03, POL-04, POL-05
**Success Criteria** (what must be TRUE):

  1. `conjure init --overlay hipaa` (and soc2/gdpr/pci) emits a regime-specific `sandbox{}` block into `.claude/settings.json` via `jq` + `mutate_write`; every `denyRead` path is mirrored in `permissions.deny` as `Read(<path>)` (closes the Read-tool enforcement gap)
  2. Each overlay emits `managed-settings.json` with `disableBypassPermissionsMode: "disable"` (string, not boolean), `allowManagedPermissionRulesOnly`, `forceLoginOrgUUID` placeholder, and the sandbox block written to a caller-specified output dir (never auto-placed at system paths)
  3. MDM artifact generation produces a platform-tagged bundle: macOS `com.anthropic.claudecode.plist` + Windows `Set-ClaudeCodePolicy.ps1` registry setter — both written to the caller-specified dir; deprecated Windows path `C:\ProgramData\ClaudeCode\` is never emitted
  4. `conjure audit` flags (a) overlay active but sandbox missing or `enabled: false`, (b) a `denyRead` path with no mirrored `Read(...)` deny, (c) `disableBypassPermissionsMode` wrong type (boolean instead of string); `conjure audit --compliance` on an uncustomized sandbox template warns "unreviewed policy template — not deployable"
  5. A deliberately-broken managed-settings artifact (wrong key name or type) is detected by `conjure audit`; emitted artifacts ship with a printed testable verification assertion (e.g., "Verify: `claude config get sandbox.enabled` must return true") so no compliance overlay ships without a live-verification step

**Plans**: 4 plans
Plans:
**Wave 0**

- [x] 26-00-PLAN.md — Wave 0: golden fixtures + tests/run.sh Phase 26 graceful-red block (Nyquist)

**Wave 1**

- [x] 26-01-PLAN.md — Wave 1: lib/policy-helpers.sh + compliance/*/policy.sh + emit-policy.sh + CLI dispatch (POL-01, POL-02)

**Wave 2** *(blocked on Wave 1 completion)*

- [x] 26-02-PLAN.md — Wave 2: managed-settings.json + macOS plist + Windows ps1 emit (POL-03, POL-04)

**Wave 3** *(blocked on Wave 2 completion)*

- [x] 26-03-PLAN.md — Wave 3: audit-setup.sh POL-05 checks (POL-05)

**UI hint**: no

### Phase 27: Schema-Version-Aware Audit

**Goal**: `conjure audit` validates harnesses against the current Claude Code schema — catching deprecated keys, wrong types, and invalid hook events — and emits machine-readable JSON output consumed by workspace aggregation
**Depends on**: Phase 26 (audit-setup.sh additions are sequential; SCHM-05 `--json` flag is needed by Phase 29 workspace audit)
**Requirements**: SCHM-01, SCHM-02, SCHM-03, SCHM-04, SCHM-05
**Success Criteria** (what must be TRUE):

  1. `conjure audit` validates all SKILL.md frontmatter keys against the full 14-field Conjure-maintained schema (including `disallowed-tools` as array or space-separated string); no valid field is rejected; an invalid type (e.g., `disallowed-tools: {Bash: true}`) is flagged
  2. `conjure audit` flags `disableBypassPermissionsMode` set to boolean `true` instead of string `"disable"` with the correct value in the warning message
  3. `conjure check` flags unknown or renamed hook event names against the bundled `lib/cc-schema.json` event table (e.g., a settings.json using `SessionStop` instead of `SessionEnd` is flagged); `lib/cc-schema.json` is bundled (not fetched at runtime) and ships with all 34 current hook events
  4. `conjure check --schema` reports which CC version introduced each settings key found in the harness vs the pinned `.conjure-version`; CC version detection falls back gracefully when `claude` is not on PATH (warn, not fail); a staleness advisory fires when `cc-schema.json` is >90 days old (WARN, not ERR)
  5. `conjure audit --json` emits machine-readable JSON output (pass/fail + per-check results); the output is consumed successfully by Phase 29's `conjure workspace audit` aggregation

**Plans**: 4 plans
Plans:

**Wave 0**

- [x] 27-00-PLAN.md — Wave 0: lib/cc-schema.json (30 events, 16 fields, verbatim from RESEARCH) + fixtures + graceful-red SCHM test block (SCHM-01..05 Nyquist)

**Wave 1** *(blocked on Wave 0 completion)*

- [x] 27-01-PLAN.md — Wave 1: SCHM-01 (SKILL.md 16-field type validation) + SCHM-02 (disableBypassPermissionsMode both-path check, replaces POL-05c) in scripts/audit-setup.sh

**Wave 2** *(blocked on Wave 0 completion)*

- [x] 27-02-PLAN.md — Wave 2: SCHM-03 (hook event validation from cc-schema.json) + SCHM-04 (--schema version report) in scripts/check.sh + cli/conjure --schema wiring

**Wave 3** *(blocked on Waves 1+2 completion)*

- [x] 27-03-PLAN.md — Wave 3: SCHM-05 (audit --json: JSON-only stdout, stable check IDs, exit 2 on fail) in scripts/audit-setup.sh + cli/conjure --json wiring

**UI hint**: no

### Phase 28: promptfoo Eval + Context-Budget Linter

**Goal**: Developers can scaffold, run, and CI-gate a promptfoo-based prompt-adherence eval suite, and `conjure audit` statically measures harness context load
**Depends on**: Phase 27 (`conjure audit --json` and enriched audit path needed for EVAL-05 coverage gap; eval.sh never invoked from audit/check path)
**Requirements**: EVAL-01, EVAL-02, EVAL-03, EVAL-04, EVAL-05
**Success Criteria** (what must be TRUE):

  1. `conjure eval init` scaffolds `.conjure/eval/promptfooconfig.yaml` with one `skill-used` assertion per installed skill and one `llm-rubric` assertion per CLAUDE.md rule line; the config uses `repeat: 3, minPassCount: 2` for all `llm-rubric` assertions (flakiness guard)
  2. `conjure eval run` shells out to `npx --yes promptfoo@<pinned>` (with Node ≥20.20.0 preflight); passes through the exit code; `conjure audit` with promptfoo absent exits 0 (eval never invoked from audit/check path); `conjure eval` with promptfoo absent exits 2 with a human-readable message
  3. `conjure eval --emit-workflow` generates a `pull_request` GitHub Actions workflow using `promptfoo/promptfoo-action`, `fail-on-threshold`, path-triggered on `.claude/**` and `CLAUDE.md`; deliberately breaking a hook binary causes the eval suite to fail (enforcement-not-disposition test)
  4. `conjure audit --budget` measures estimated tokens for CLAUDE.md + always-loaded skills (chars/4 heuristic), flags over-threshold sessions, lists top contributors, and supports `--porcelain` JSON output
  5. `conjure audit` reports which installed skills have no `skill-used` assertion in `.conjure/eval/promptfooconfig.yaml`; a skill added after `conjure eval init` appears in the coverage gap report

**Plans**: 4 plans
Plans:

**Wave 0**

- [x] 28-00-PLAN.md — Wave 0: eval fixture harnesses + golden promptfooconfig.yaml + A1/A2/A3 probe README + Phase 28 graceful-red EVAL test block (EVAL-01..05 Nyquist)

**Wave 1** *(blocked on Wave 0 completion)*

- [x] 28-01-PLAN.md — Wave 1: scripts/eval.sh (cmd_eval_init + cmd_eval_run) + cli/conjure cmd_eval dispatch (EVAL-01, EVAL-02)

**Wave 2** *(blocked on Wave 1 completion)*

- [x] 28-02-PLAN.md — Wave 2: scripts/eval.sh cmd_eval_emit_workflow — conjure-eval.yml GitHub Actions workflow (EVAL-03)

**Wave 3** *(blocked on Wave 0 completion; runs parallel to Waves 1+2)*

- [x] 28-03-PLAN.md — Wave 3: scripts/audit-setup.sh --budget linter + EVAL-05 coverage gap + cli/conjure --budget/--porcelain wiring (EVAL-04, EVAL-05)

**UI hint**: no

### Phase 29: Workspace Orchestration — Read-Only

**Goal**: Developers can declare a multi-repo workspace and run read-only harness health checks across all repos in one command, with a per-repo status table
**Depends on**: Phase 27 (`conjure audit --json` must be stable for workspace audit aggregation); Phase 28 complete (workspace can include eval as a future op)
**Requirements**: WS-01, WS-02, WS-03, WS-04
**Success Criteria** (what must be TRUE):

  1. `.conjure-workspace.json` schema is defined and validated; `conjure workspace init` discovers sibling repos containing `.claude/` (TTY prompt for confirmation; non-TTY requires `--yes`; exits 2 without `--yes` in non-TTY); the manifest is written via `mutate_write`
  2. `conjure workspace check` runs `conjure check --porcelain` per repo in the manifest and emits an aggregated per-repo status table (repo name, drift status, exit code); one repo with a permissions error causes exit 1 (partial success), not exit 2, and remaining repos are processed (fail-tolerant default)
  3. `conjure workspace audit` runs `conjure audit --json` per repo and emits a per-repo pass/fail table plus a global summary; `--fail-fast` flag switches to abort-on-first-failure mode
  4. A workspace manifest with 3 repos where 1 has an invalid path exits 2 on `conjure workspace init` before writing anything; `conjure workspace check` on the manifest skips the bad-path repo with a warning and processes the remaining 2

**Plans**: 3 plans
Plans:
**Wave 0**

- [x] 29-00-PLAN.md — Wave 0: workspace fixtures (_workspace/ 3-repo tree + gamma-bad audit-fail variant + _workspace-badpath/ bad-path manifest) + graceful-red WS test block in tests/run.sh (WS-01..04 Nyquist)

**Wave 1** *(blocked on Wave 0 completion)*

- [x] 29-01-PLAN.md — Wave 1: lib/workspace.sh (manifest validate/load/discover helpers) + scripts/workspace.sh init + cli/conjure cmd_workspace dispatch (WS-01, WS-02)

**Wave 2** *(blocked on Wave 1 completion)*

- [x] 29-02-PLAN.md — Wave 2: workspace check (per-repo --porcelain aggregation, fail-tolerant) + workspace audit (per-repo --json aggregation, --fail-fast, exit semantics) in scripts/workspace.sh (WS-03, WS-04)

**UI hint**: no

### Phase 30: Workspace Orchestration — Mutating + Rollback Saga

**Goal**: Developers can run mutating harness operations (update, adopt) across many repos in one command, with a saga-pattern rollback that survives SIGKILL and restores every repo to its pre-run state
**Depends on**: Phase 29 (manifest + read-only ops must be stable; `lib/workspace.sh` + `scripts/workspace.sh` saga pipeline is the highest-risk component and must be last)
**Requirements**: WS-05, WS-06, WS-07
**Success Criteria** (what must be TRUE):

  1. `conjure workspace update` runs `conjure update` per repo serially, reports per-repo merge/conflict status, defaults to stop-on-first-error (fail-fast), and supports `--continue-on-error`; conflict sidecars from individual repos are surfaced in the aggregate report
  2. `conjure workspace adopt` (with optional tag filter) snapshots ALL repos before applying to ANY (saga invariant); `.conjure-workspace-state.json` is written before each repo operation and updated after; a disk-space estimate is checked before the snapshot phase and warns at >2 GB requiring `--allow-large-snapshots`
  3. `conjure workspace adopt --rollback` rolls back each repo independently from its pre-run snapshot recorded in `.conjure-workspace-state.json`; the state file persists across SIGKILL
  4. Saga proof (CI fixture): SIGKILL a `conjure workspace adopt` mid-batch against a `_workspace-trio` fixture (3 small repos) → `conjure workspace adopt --rollback` → per-repo `sha256` zero-diff confirms all applied repos are restored to their pre-run state (mirroring the Phase 24 pattern at workspace scale)
  5. `conjure workspace adopt --dry-run` performs all preflight and snapshot-size checks but writes zero files; exit 2 is never emitted from a dry run unless a preflight check itself fails

**Plans**: 5 plans
Plans:
**Wave 0**

- [x] 30-00-PLAN.md — Wave 0: _workspace-trio fixture (3 adoptable repos alpha/beta/gamma + manifest with tags) + Phase 30 graceful-red block in tests/run.sh (WS-05/06/07 + SIGKILL saga test, Nyquist)

**Wave 1** *(blocked on Wave 0 completion)*

- [x] 30-01-PLAN.md — Wave 1: lib/workspace.sh state helpers — workspace_state_write (atomic jq>tmp+mv), workspace_state_read, workspace_state_validate; schema {run_id, started, phase, repos[{name, snapshot_ref, sha256_pre_ref, status}]} (WS-06, WS-07)

**Wave 2** *(blocked on Wave 1 completion)*

- [x] 30-02-PLAN.md — Wave 2: ws_do_update in scripts/workspace.sh (serial per-repo conjure update, stop-on-first-error, --continue-on-error, conflict sidecar surfacing, CR-02 traversal re-check) + cmd_workspace update|adopt token extension in cli/conjure (WS-05)

**Wave 3** *(blocked on Wave 2 completion)*

- [ ] 30-03-PLAN.md — Wave 3: ws_do_adopt saga orchestrator in scripts/workspace.sh — preflight du gate (2097152 KiB), --tag filter, PHASE A snapshot-all loop (workspace_state_write before+after each op, sha256_pre_ref hash file), PHASE B apply-serial loop, --dry-run zero-write, stop-on-fail; ws_sha_of in lib/workspace.sh (WS-06)

**Wave 4** *(blocked on Wave 3 completion)*

- [ ] 30-04-PLAN.md — Wave 4: ws_do_rollback in scripts/workspace.sh — per-repo independent restore from snapshot_ref, sha256 zero-diff verify loop, idempotent skip (rolled_back), rollback-time CR-02 re-check, state archived timestamped; adopt --rollback dispatch wired; SIGKILL saga test turns green (WS-07)

**UI hint**: no

## Progress

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 21. Foundation Libs + Inventory | v0.6.0 | 4/4 | Complete | 2026-05-28 |
| 22. `conjure adopt` CLI Core + Rollback | v0.6.0 | 3/3 | Complete | 2026-05-28 |
| 23. Restructure Skill + Safety Gates | v0.6.0 | 3/3 | Complete | 2026-05-29 |
| 24. Integration Tests + Argus Fixture | v0.6.0 | 2/2 | Complete | 2026-05-29 |
| 25. Plugin + Marketplace Emission | v0.7.0 | 4/4 | Complete    | 2026-06-03 |
| 26. Sandbox + Managed-Settings / MDM | v0.7.0 | 4/4 | Complete    | 2026-06-03 |
| 27. Schema-Version-Aware Audit | v0.7.0 | 4/4 | Complete    | 2026-06-03 |
| 28. promptfoo Eval + Context-Budget Linter | v0.7.0 | 4/4 | Complete    | 2026-06-03 |
| 29. Workspace Orchestration — Read-Only | v0.7.0 | 3/3 | Complete    | 2026-06-03 |
| 30. Workspace Orchestration — Mutating + Rollback Saga | v0.7.0 | 3/5 | In Progress|  |
