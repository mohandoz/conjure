---
gsd_state_version: 1.0
milestone: v0.4.0
milestone_name: Distribution + Ecosystem
status: executing
last_updated: "2026-05-25T21:54:03.688Z"
last_activity: 2026-05-25 -- Phase 12 planning complete
progress:
  total_phases: 8
  completed_phases: 4
  total_plans: 15
  completed_plans: 12
  percent: 50
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-05-25)

**Core value:** A developer can turn any repo into a production-grade, eval-backed Claude Code harness with one trustworthy command — and keep it healthy over time.
**Current focus:** Phase 11 — skill publishing

## Current Position

Phase: 11
Plan: Not started
Status: Ready to execute
Last activity: 2026-05-25 -- Phase 12 planning complete

Progress: [██████████] 100%

## Performance Metrics

**Velocity:**

- Total plans completed: 32 (from v0.3.0)
- Average duration: — min
- Total execution time: —

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| v0.3.0 phases 01–07 | 22 | - | - |
| v0.4.0 phases 08–15 | TBD | - | - |
| 08 | 3 | - | - |
| 09 | 3 | - | - |
| 10 | 4 | - | - |

**Recent Trend:**

- Last 5 plans: —
- Trend: —

*Updated after each plan completion*
| Phase 10-marketplace-publish P03 | 49 | 2 tasks | 1 files |
| Phase 10 P04 | 2m | 1 tasks | 1 files |

## Accumulated Context

### Decisions

- [v0.3.0 scope]: Quality/trust precede distribution; all writes through `lib/mutate.sh` chokepoint
- [v0.4.0 ordering]: Nyquist backfill first, then 3-way merge (deepest logic), then distribution channels
- [Docker base]: debian:bookworm-slim (not Alpine) to avoid musl libc breaks for optional Go/Rust tools
- [Homebrew]: Separate tap repo `mohandoz/homebrew-conjure`; formula pinned to tagged tarball SHA256 only
- [Phase ?]: Three new CI steps (version-consistency, claude CLI install, plugin validate) added to test job — MKTPL-02 and MKTPL-03 delivered
- [Phase ?]: Script-copy sandbox isolation for publish-plugin.sh regression tests — script self-resolves CONJURE_HOME, env override ignored

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

Last session: 2026-05-25T21:24:12.827Z
Stopped at: Phase 12 context gathered
Resume file: .planning/phases/12-org-overlay/12-CONTEXT.md
