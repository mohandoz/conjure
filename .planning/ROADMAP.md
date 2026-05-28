# Roadmap: Conjure

## Completed Milestones

- **v0.3.0** — "Testing + Telemetry" — 7 phases, 22 plans, 20/20 requirements satisfied, 169 commits (2026-05-24 → 2026-05-25) — [Archive](.planning/milestones/v0.3.0-ROADMAP.md)
- **v0.4.0** — "Distribution + Ecosystem" — 9 phases, 23 plans, 29/29 requirements satisfied, 136 commits (2026-05-25 → 2026-05-26) — [Archive](.planning/milestones/v0.4.0-ROADMAP.md)
- **v0.5.0** — "Auto-Update + Healthcheck" — 5 phases, 10 plans, 11/11 requirements satisfied, 49 commits (2026-05-26 → 2026-05-28) — [Archive](.planning/milestones/v0.5.0-ROADMAP.md)

## Active Milestone

_None — v0.5.0 shipped 2026-05-28. Start the next milestone with `/gsd-new-milestone`._

## Phases

<details>
<summary>✅ v0.5.0 Auto-Update + Healthcheck (Phases 16-20) — SHIPPED 2026-05-28</summary>

- [x] **Phase 16: Prerequisites** - `mutate_rm` dry-run-safe deletion primitive + `publish-skill` positional arg refactor (completed 2026-05-26)
- [x] **Phase 17: Drift Detection** - `conjure check` 3-way drift classifier with exit codes + `--porcelain` (completed 2026-05-26)
- [x] **Phase 18: Conflict Resolution** - `conjure resolve` interactive diff3 sidecar walker (completed 2026-05-26)
- [x] **Phase 19: Auto-PR** - `conjure update --pr` with idempotency guard + `--cron` workflow template (completed 2026-05-26)
- [x] **Phase 20: Windows + CI Gate** - `conjure.ps1` PowerShell shim + windows-ps1-shim CI job + ci-gate empty-check guard (completed 2026-05-28)

</details>

Full phase details for shipped milestones live in their archives under `.planning/milestones/`.

## Backlog

### Future Milestones

- v0.6.0 — Workspace / cross-repo graph orchestration (single-repo correctness first)
