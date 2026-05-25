---
gsd_state_version: 1.0
milestone: v0.4.0
milestone_name: Distribution + Ecosystem
status: executing
last_updated: "2026-05-25T15:00:23.221Z"
last_activity: 2026-05-25 -- Phase 08 execution started
progress:
  total_phases: 8
  completed_phases: 0
  total_plans: 3
  completed_plans: 0
  percent: 0
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-05-25)

**Core value:** A developer can turn any repo into a production-grade, eval-backed Claude Code harness with one trustworthy command — and keep it healthy over time.
**Current focus:** Phase 08 — nyquist-compliance-backfill

## Current Position

Phase: 08 (nyquist-compliance-backfill) — EXECUTING
Plan: 1 of 3
Status: Executing Phase 08
Last activity: 2026-05-25 -- Phase 08 execution started

Progress: [░░░░░░░░░░] 0%

## Performance Metrics

**Velocity:**

- Total plans completed: 22 (from v0.3.0)
- Average duration: — min
- Total execution time: —

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| v0.3.0 phases 01–07 | 22 | - | - |
| v0.4.0 phases 08–15 | TBD | - | - |

**Recent Trend:**

- Last 5 plans: —
- Trend: —

*Updated after each plan completion*

## Accumulated Context

### Decisions

- [v0.3.0 scope]: Quality/trust precede distribution; all writes through `lib/mutate.sh` chokepoint
- [v0.4.0 ordering]: Nyquist backfill first, then 3-way merge (deepest logic), then distribution channels
- [Docker base]: debian:bookworm-slim (not Alpine) to avoid musl libc breaks for optional Go/Rust tools
- [Homebrew]: Separate tap repo `mohandoz/homebrew-conjure`; formula pinned to tagged tarball SHA256 only

### Pending Todos

None yet.

### Blockers/Concerns

- [Phase 12]: Overlay version compatibility contract (`compatible-kit-version`) deferred to v0.4.x — define during OVLY implementation before first overlay ships in production
- [Phase 13]: Run `brew search conjure` before Phase 13 formula work to check for name collision; fallback names are `conjure-kit` or `conjure-claude`
- [Phase 09]: Non-git installs (Homebrew tarball) will not have `.conjure-templates-<version>/` unless snapshot is written at init time — must decide on snapshot strategy before merge implementation

## Deferred Items

| Category | Item | Status | Deferred At |
|----------|------|--------|-------------|
| Docker | `conjure:full` tag with optional Go/Rust tools | Deferred to v0.4.x | v0.4.0 scoping |
| Windows | PowerShell `conjure.ps1` entrypoint (no Git Bash) | Deferred to v0.5.0 | v0.4.0 scoping |
| Overlay | `compatible-kit-version` manifest field | Deferred to v0.4.x | v0.4.0 scoping |
| Publish | `--dry-run` for `conjure publish` / `publish-skill` | Deferred | v0.4.0 scoping |

## Session Continuity

Last session: 2026-05-25T14:35:32.677Z
Stopped at: Phase 08 context gathered
Resume file: .planning/phases/08-nyquist-compliance-backfill/08-CONTEXT.md
