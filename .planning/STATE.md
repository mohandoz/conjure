---
gsd_state_version: 1.0
milestone: v0.6.0
milestone_name: Safe Brownfield Adoption
status: planning
last_updated: "2026-05-28T15:48:22.144Z"
last_activity: 2026-05-28 — Roadmap created for v0.6.0; 23 requirements mapped to Phases 21–24
progress:
  total_phases: 4
  completed_phases: 0
  total_plans: 0
  completed_plans: 0
  percent: 0
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-05-28)

**Core value:** A developer can turn any repo into a production-grade, eval-backed Claude Code harness with one trustworthy command — and keep it healthy over time.
**Current focus:** Phase 21 ready to plan — Foundation Libs + Inventory

## Current Position

Phase: 21 of 24 (Foundation Libs + Inventory)
Plan: — of —
Status: Ready to plan
Last activity: 2026-05-28 — Roadmap created for v0.6.0; 23 requirements mapped to Phases 21–24

Progress: [░░░░░░░░░░] 0%

## Performance Metrics

**Velocity:**

- Total plans completed: 55 (v0.3.0: 22, v0.4.0: 23, v0.5.0: 10)
- Average duration: — min
- Total execution time: —

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| v0.3.0 phases 01–07 | 22 | - | - |
| v0.4.0 phases 08–15.1 | 23 | - | - |
| v0.5.0 phases 16–20 | 10 | - | - |

**Recent Trend:**

- Last 5 plans: —
- Trend: —

## Accumulated Context

### Decisions

Full decision log in PROJECT.md Key Decisions table. Key v0.6.0 design decisions:

- Split responsibility: CLI owns all filesystem mutations; restructure skill owns all LLM judgment
- Skill restricted to `[Read, Bash]` — cannot call `Write`/`Edit` on project files directly
- `snapshot_create` uses raw `cp -R`, NOT `mutate_cp` — snapshot is the safety primitive, not a mutation
- Build order is hard: log.sh → snapshot.sh → inventory.sh → adopt.sh → skill → tests

### Pending Todos

None.

### Blockers/Concerns

- Phase 22 open question: step-id format (slug vs UUID) — decide during planning before coding `adopt.sh`
- Phase 22 open question: `--apply-step` / `--update-manifest` callback contract JSON schema validation depth
- Phase 23 open question: skill body must fit in ≤200 lines while covering manifest load, invariant check, plan proposal, approval loop, patch write, final audit — may need a planning spike

## Deferred Items

| Category | Item | Status | Deferred At |
|----------|------|--------|-------------|
| Docker | `conjure:full` tag with optional Go/Rust tools | Deferred to v0.4.x | v0.4.0 scoping |
| Overlay | `compatible-kit-version` manifest field | Deferred to v0.4.x | v0.4.0 scoping |
| verification_gap | Phase 10 VERIFICATION.md — human_needed (claude CLI required) | human_needed | v0.4.0 close |
| verification_gap | Phase 13 VERIFICATION.md — human_needed (live brew install) | human_needed | v0.4.0 close |
| verification_gap | Phase 14 VERIFICATION.md — human_needed (Docker + Windows CI) | human_needed | v0.4.0 close |
| verification_gap | Phase 15 VERIFICATION.md — human_needed (live tag push) | human_needed | v0.4.0 close |

## Session Continuity

Last session: 2026-05-28T15:48:22.139Z
Stopped at: Phase 21 context gathered
Resume file: .planning/phases/21-foundation-libs-inventory/21-CONTEXT.md
