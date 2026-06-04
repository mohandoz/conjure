# Roadmap: Conjure

## Completed Milestones

- **v0.3.0** — "Testing + Telemetry" — 7 phases, 22 plans, 20/20 requirements satisfied, 169 commits (2026-05-24 → 2026-05-25) — [Archive](.planning/milestones/v0.3.0-ROADMAP.md)
- **v0.4.0** — "Distribution + Ecosystem" — 9 phases, 23 plans, 29/29 requirements satisfied, 136 commits (2026-05-25 → 2026-05-26) — [Archive](.planning/milestones/v0.4.0-ROADMAP.md)
- **v0.5.0** — "Auto-Update + Healthcheck" — 5 phases, 10 plans, 11/11 requirements satisfied, 49 commits (2026-05-26 → 2026-05-28) — [Archive](.planning/milestones/v0.5.0-ROADMAP.md)
- **v0.6.0** — "Safe Brownfield Adoption" — 4 phases, 12 plans, 23/23 requirements satisfied, ~104 commits (2026-05-28 → 2026-05-29) — [Archive](.planning/milestones/v0.6.0-ROADMAP.md)
- **v0.7.0** — "Plugin-native + Policy-grade" — 6 phases, 24 plans, 27/27 requirements satisfied, ~181 commits (2026-06-03 → 2026-06-04) — [Archive](.planning/milestones/v0.7.0-ROADMAP.md)

## Active Milestone

**v0.8.0 — "Operability + DX"** — Phases 31–36

## Phases

<details>
<summary>✅ v0.6.0 Safe Brownfield Adoption (Phases 21-24) — SHIPPED 2026-05-29</summary>

- [x] **Phase 21: Foundation Libs + Inventory** — `lib/log.sh`, `lib/snapshot.sh`, `lib/inventory.sh`, `lib/caps.sh` + finalized `adopt-manifest.json` schema with 6-bucket classification (completed 2026-05-28)
- [x] **Phase 22: `conjure adopt` CLI Core + Rollback** — `scripts/adopt.sh` + `cmd_adopt`, 5-step pipeline, `--dry-run`/`--force`/`--rollback`/`--apply-step`/`--update-manifest`, `.conjure-adopt-state` schema, signal traps, partial-run recovery (completed 2026-05-28)
- [x] **Phase 23: Restructure Skill + Safety Gates** — human-gated `restructure` skill (`[Read, Bash]`) + 5 gate helpers (verify-invariants, audit-staged, extract-invariants, decision-scan, approve) riding the adopt seam (completed 2026-05-29)
- [x] **Phase 24: Integration Tests + Argus Fixture** — 500-file `_brownfield-argus` generator + E2E `▸ Phase 24` test block (dry-run perf, rollback zero-diff, idempotent re-run, SIGKILL recovery, symlink-skip + @import-block) (completed 2026-05-29)

</details>

<details>
<summary>✅ v0.7.0 Plugin-native + Policy-grade (Phases 25-30) — SHIPPED 2026-06-04</summary>

- [x] **Phase 25: Plugin + Marketplace Emission** — `lib/plugin-helpers.sh` + `scripts/emit-plugin.sh` + `conjure publish-plugin` (plugin.json, marketplace.json, `extraKnownMarketplaces` wiring, `--validate` gate, version-fallback SHA) (completed 2026-06-03)
- [x] **Phase 26: Sandbox + Managed-Settings / MDM** — `lib/policy-helpers.sh` + `conjure emit-policy` for all 4 compliance overlays; sandbox block + `permissions.deny` mirror; `managed-settings.json`; MDM plist + Windows PS1; `conjure audit` policy flags (completed 2026-06-03)
- [x] **Phase 27: Schema-Version-Aware Audit** — bundled `lib/cc-schema.json` (30 hook events, 16 SKILL.md fields); audit validates frontmatter + `disableBypassPermissionsMode` type; `conjure check --schema` version report; `conjure audit --json` machine-readable output (completed 2026-06-03)
- [x] **Phase 28: promptfoo Eval + Context-Budget Linter** — `scripts/eval.sh` + `conjure eval init/run/--emit-workflow` (claude-agent-sdk provider, pinned promptfoo 0.121.14); `conjure audit --budget` static context linter; eval-coverage gap report (completed 2026-06-03)
- [x] **Phase 29: Workspace Orchestration — Read-Only** — `.conjure-workspace.json` manifest + traversal-guarded validation; `conjure workspace init/check/audit` with fail-tolerant aggregation (completed 2026-06-03)
- [x] **Phase 30: Workspace Orchestration — Mutating + Rollback Saga** — `conjure workspace update/adopt/--rollback`; snapshot-all-before-any-apply saga; SIGKILL-durable state; per-repo sha256 zero-diff rollback proof (completed 2026-06-04)

</details>

### v0.8.0 Operability + DX (In Progress)

**Milestone Goal:** Close v0.7.0 deferred debt, give operators visibility (`doctor`, `stats`), deepen eval coverage, polish init UX, and ship user-facing docs that match what Conjure actually does.

- [ ] **Phase 31: Deferred Debt + Test-Harness Hardening** — `git -C "$VAR"` empty-var guards, `preflight.sh` exit 1 → exit 2, `skip()` counter in `tests/run.sh`, live-smoke gating, `tests/MANUAL-UAT.md`
- [ ] **Phase 32: `conjure doctor`** — new `scripts/doctor.sh` + `cmd_doctor`; binary/version table, `.mjs` ESM probe, harness validation, `--json` output, `--fix` remediation
- [ ] **Phase 33: `conjure stats`** — new `scripts/stats.sh` + `cmd_stats`; skill fire counts, dead-skill detection, cost estimates, `--window`/`--json`/`--export-csv`, JSONL try-parse guard
- [ ] **Phase 34: Eval Suite Expansion** — per-profile assertion templates (4 profiles), `_detect_applied_profiles()`, `eval snapshot`/`eval compare`, fork-PR guard, `repeat: 1` structural cap, tool-trajectory assertions
- [ ] **Phase 35: Init Wizard Polish** — `_detect_profile()` from project fingerprints, TTY-gated confirm picker, `--yes` non-interactive flag, compliance overlay selection during init
- [ ] **Phase 36: README + Docs Refresh** — README rewrite covering v0.3–v0.8, command reference with CI grep gate, MIGRATION-GUIDE + FAILURE-MODES sync

## Phase Details

### Phase 31: Deferred Debt + Test-Harness Hardening

**Goal**: Safety-critical debt from v0.7.0 is resolved and the test harness can accurately report gated/skipped tests
**Depends on**: Phase 30 (v0.7.0 complete)
**Requirements**: DEBT-03, DEBT-04, DEBT-05, DEBT-06, UAT-01, UAT-02, UAT-03
**Success Criteria** (what must be TRUE):

  1. Test suite reports PASS/FAIL/SKIP counts; gated live-system tests skip cleanly when `CONJURE_LIVE_TEST` is unset
  2. User can run `CONJURE_LIVE_TEST=1 tests/run.sh` and the live `claude`-binary smoke test executes (skips when `claude` is absent)
  3. User can run `ANTHROPIC_API_KEY=<key> tests/run.sh` and the live promptfoo eval executes (skips without the key)
  4. `tests/MANUAL-UAT.md` exists with checklists for MDM hardware and managed-settings deploy scenarios
  5. `scripts/preflight.sh` exits 2 in all error paths; no caller breaks from the change

**Plans**: 4 plansPlans:
**Wave 1**

- [x] 31-01-PLAN.md — DEBT-04 (preflight exit 2), DEBT-03 (mk_tmpd helper), DEBT-05 (skip counter + strict mode)
- [x] 31-02-PLAN.md — UAT-03 (tests/MANUAL-UAT.md checklists)

**Wave 2** *(blocked on Wave 1 completion)*

- [x] 31-03-PLAN.md — DEBT-03 sweep (mktemp → mk_tmpd in run.sh), DEBT-06 (SCHM-STALE env override + audit-setup.sh + FAILURE-MODES.md)

**Wave 3** *(blocked on Wave 2 completion)*

- [ ] 31-04-PLAN.md — UAT-01 + UAT-02 (live-system tests section in run.sh)

### Phase 32: `conjure doctor`

**Goal**: Users can diagnose the health of their Conjure installation and harness with a single command
**Depends on**: Phase 31
**Requirements**: DOCT-01, DOCT-02, DOCT-03, DOCT-04, DOCT-05, DOCT-06
**Success Criteria** (what must be TRUE):

  1. `conjure doctor` prints a table of required binaries with version and OS-specific install hint for any missing ones
  2. `conjure doctor` tests Node `.mjs` ESM execution via a temporary probe file and reports pass/fail
  3. `conjure doctor` checks Claude Code version against the ≥2.1.117 minimum and the repo's `.conjure-version` pin
  4. `conjure doctor --json` emits a machine-readable diagnostics object (all checks, pass/fail, versions)
  5. `conjure doctor --fix` auto-remediates safe harness findings (all writes via `lib/mutate.sh`, backup-before-mutate)

**Plans**: TBD
**UI hint**: yes

### Phase 33: `conjure stats`

**Goal**: Users can inspect skill-firing telemetry to understand usage patterns and estimate token costs
**Depends on**: Phase 32
**Requirements**: STAT-01, STAT-02, STAT-03, STAT-04, STAT-05, STAT-06, STAT-07
**Success Criteria** (what must be TRUE):

  1. `conjure stats` shows per-skill fire counts and highlights skills that have never fired (dead skills)
  2. `conjure stats` shows a cost estimate per skill and in aggregate using the chars/4 heuristic and `lib/prices.json`
  3. `conjure stats --window 30` limits the report to the last 30 days; `--json` emits machine-readable output
  4. `conjure stats` shows session-level summary (session count, average skills per session)
  5. `conjure stats --export-csv` writes a CSV file for external analysis
  6. All JSONL reads use per-line `try fromjson` guards; corrupt or partial lines are skipped without aborting

**Plans**: TBD

### Phase 34: Eval Suite Expansion

**Goal**: Users get per-profile eval coverage and can detect regressions by comparing against a saved baseline
**Depends on**: Phase 33
**Requirements**: EVAL-06, EVAL-07, EVAL-08, EVAL-09
**Success Criteria** (what must be TRUE):

  1. `conjure eval init` appends profile-specific assertion blocks when profile markers are detected in CLAUDE.md (all 9 profiles)
  2. `conjure eval snapshot` saves a named baseline; `conjure eval compare <baseline>` reports regressions against it
  3. The emitted eval GitHub Actions workflow guards fork PRs (no secrets exposed) and caps API cost with `repeat: 1` for structural assertions
  4. User can assert tool trajectory from `allowed-tools` frontmatter via `metadata.skillCalls` assertions

**Plans**: TBD

### Phase 35: Init Wizard Polish

**Goal**: `conjure init` auto-detects the correct profile and offers compliance overlays without requiring manual lookup
**Depends on**: Phase 34
**Requirements**: WIZ-01, WIZ-02, WIZ-03, WIZ-04
**Success Criteria** (what must be TRUE):

  1. `conjure init` detects the likely profile from project fingerprints (package.json, go.mod, Cargo.toml, pyproject.toml, pom.xml, monorepo markers) and presents the detected choice first
  2. In a TTY, the user sees a confirm picker; in non-TTY, detection is logged but never auto-applied
  3. `conjure init --yes` accepts all detected defaults non-interactively (profile + no compliance overlay)
  4. During interactive init, the user is offered compliance overlay selection before applying

**Plans**: TBD
**UI hint**: yes

### Phase 36: README + Docs Refresh

**Goal**: README and reference docs accurately describe what Conjure does, covering v0.3 through v0.8
**Depends on**: Phase 35
**Requirements**: DOCS-01, DOCS-02, DOCS-03
**Success Criteria** (what must be TRUE):

  1. README has a quick-start section covering `doctor → init → audit` and a feature tour covering capabilities shipped in v0.3–v0.8
  2. README command reference covers every subcommand in `usage()`; CI grep gate fails if a subcommand is undocumented
  3. MIGRATION-GUIDE.md and FAILURE-MODES.md reflect current behavior (no references to removed or renamed commands)

**Plans**: TBD

## Progress

| Phase | Milestone | Plans Complete | Status | Completed |
| ----- | --------- | -------------- | ------ | --------- |
| 25. Plugin + Marketplace Emission | v0.7.0 | 4/4 | Complete | 2026-06-03 |
| 26. Sandbox + Managed-Settings / MDM | v0.7.0 | 4/4 | Complete | 2026-06-03 |
| 27. Schema-Version-Aware Audit | v0.7.0 | 4/4 | Complete | 2026-06-03 |
| 28. promptfoo Eval + Context-Budget Linter | v0.7.0 | 4/4 | Complete | 2026-06-03 |
| 29. Workspace Orchestration — Read-Only | v0.7.0 | 3/3 | Complete | 2026-06-03 |
| 30. Workspace Orchestration — Mutating + Rollback Saga | v0.7.0 | 5/5 | Complete | 2026-06-04 |
| 31. Deferred Debt + Test-Harness Hardening | v0.8.0 | 3/4 | In Progress|  |
| 32. `conjure doctor` | v0.8.0 | 0/? | Not started | - |
| 33. `conjure stats` | v0.8.0 | 0/? | Not started | - |
| 34. Eval Suite Expansion | v0.8.0 | 0/? | Not started | - |
| 35. Init Wizard Polish | v0.8.0 | 0/? | Not started | - |
| 36. README + Docs Refresh | v0.8.0 | 0/? | Not started | - |
