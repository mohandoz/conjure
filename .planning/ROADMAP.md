# Roadmap: Conjure

## Completed Milestones

- **v0.3.0** — "Testing + Telemetry" — 7 phases, 22 plans, 20/20 requirements satisfied, 169 commits (2026-05-24 → 2026-05-25) — [Archive](.planning/milestones/v0.3.0-ROADMAP.md)
- **v0.4.0** — "Distribution + Ecosystem" — 9 phases, 23 plans, 29/29 requirements satisfied, 136 commits (2026-05-25 → 2026-05-26) — [Archive](.planning/milestones/v0.4.0-ROADMAP.md)
- **v0.5.0** — "Auto-Update + Healthcheck" — 5 phases, 10 plans, 11/11 requirements satisfied, 49 commits (2026-05-26 → 2026-05-28) — [Archive](.planning/milestones/v0.5.0-ROADMAP.md)
- **v0.6.0** — "Safe Brownfield Adoption" — 4 phases, 12 plans, 23/23 requirements satisfied, ~104 commits (2026-05-28 → 2026-05-29) — [Archive](.planning/milestones/v0.6.0-ROADMAP.md)
- **v0.7.0** — "Plugin-native + Policy-grade" — 6 phases, 24 plans, 27/27 requirements satisfied, ~181 commits (2026-06-03 → 2026-06-04) — [Archive](.planning/milestones/v0.7.0-ROADMAP.md)

## Active Milestone

(None — run `/gsd-new-milestone` to start the next cycle.)

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

## Progress

| Phase | Milestone | Plans Complete | Status | Completed |
| ----- | --------- | -------------- | ------ | --------- |
| 25. Plugin + Marketplace Emission | v0.7.0 | 4/4 | Complete | 2026-06-03 |
| 26. Sandbox + Managed-Settings / MDM | v0.7.0 | 4/4 | Complete | 2026-06-03 |
| 27. Schema-Version-Aware Audit | v0.7.0 | 4/4 | Complete | 2026-06-03 |
| 28. promptfoo Eval + Context-Budget Linter | v0.7.0 | 4/4 | Complete | 2026-06-03 |
| 29. Workspace Orchestration — Read-Only | v0.7.0 | 3/3 | Complete | 2026-06-03 |
| 30. Workspace Orchestration — Mutating + Rollback Saga | v0.7.0 | 5/5 | Complete | 2026-06-04 |
