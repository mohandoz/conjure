# Roadmap: Conjure

## Completed Milestones

- **v0.3.0** — "Testing + Telemetry" — 7 phases, 22 plans, 20/20 requirements satisfied, 169 commits (2026-05-24 → 2026-05-25) — [Archive](.planning/milestones/v0.3.0-ROADMAP.md)
- **v0.4.0** — "Distribution + Ecosystem" — 9 phases, 23 plans, 29/29 requirements satisfied, 136 commits (2026-05-25 → 2026-05-26) — [Archive](.planning/milestones/v0.4.0-ROADMAP.md)
- **v0.5.0** — "Auto-Update + Healthcheck" — 5 phases, 10 plans, 11/11 requirements satisfied, 49 commits (2026-05-26 → 2026-05-28) — [Archive](.planning/milestones/v0.5.0-ROADMAP.md)
- **v0.6.0** — "Safe Brownfield Adoption" — 4 phases, 12 plans, 23/23 requirements satisfied, ~104 commits (2026-05-28 → 2026-05-29) — [Archive](.planning/milestones/v0.6.0-ROADMAP.md)

## Active Milestone

None — v0.6.0 shipped 2026-05-29. Run `/gsd-new-milestone` to begin the next cycle.

## Phases

<details>
<summary>✅ v0.6.0 Safe Brownfield Adoption (Phases 21-24) — SHIPPED 2026-05-29</summary>

- [x] **Phase 21: Foundation Libs + Inventory** — `lib/log.sh`, `lib/snapshot.sh`, `lib/inventory.sh`, `lib/caps.sh` + finalized `adopt-manifest.json` schema with 6-bucket classification (completed 2026-05-28)
- [x] **Phase 22: `conjure adopt` CLI Core + Rollback** — `scripts/adopt.sh` + `cmd_adopt`, 5-step pipeline, `--dry-run`/`--force`/`--rollback`/`--apply-step`/`--update-manifest`, `.conjure-adopt-state` schema, signal traps, partial-run recovery (completed 2026-05-28)
- [x] **Phase 23: Restructure Skill + Safety Gates** — human-gated `restructure` skill (`[Read, Bash]`) + 5 gate helpers (verify-invariants, audit-staged, extract-invariants, decision-scan, approve) riding the adopt seam (completed 2026-05-29)
- [x] **Phase 24: Integration Tests + Argus Fixture** — 500-file `_brownfield-argus` generator + E2E `▸ Phase 24` test block (dry-run perf, rollback zero-diff, idempotent re-run, SIGKILL recovery, symlink-skip + @import-block) (completed 2026-05-29)

</details>

Full phase details for shipped milestones live in their archives under `.planning/milestones/`.

## Progress

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 21. Foundation Libs + Inventory | v0.6.0 | 4/4 | Complete | 2026-05-28 |
| 22. `conjure adopt` CLI Core + Rollback | v0.6.0 | 3/3 | Complete | 2026-05-28 |
| 23. Restructure Skill + Safety Gates | v0.6.0 | 3/3 | Complete | 2026-05-29 |
| 24. Integration Tests + Argus Fixture | v0.6.0 | 2/2 | Complete | 2026-05-29 |
