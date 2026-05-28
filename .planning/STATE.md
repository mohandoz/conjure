---
gsd_state_version: 1.0
milestone: v0.6.0
milestone_name: Safe Brownfield Adoption
status: verifying
last_updated: "2026-05-28T21:26:39.530Z"
last_activity: 2026-05-28
progress:
  total_phases: 4
  completed_phases: 2
  total_plans: 7
  completed_plans: 7
  percent: 50
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-05-28)

**Core value:** A developer can turn any repo into a production-grade, eval-backed Claude Code harness with one trustworthy command — and keep it healthy over time.
**Current focus:** Phase 22 — conjure-adopt-cli-core-rollback

## Current Position

Phase: 22 (conjure-adopt-cli-core-rollback) — EXECUTING
Plan: 3 of 3
Status: Phase complete — ready for verification
Last activity: 2026-05-28

Progress: [██████████] 100%

## Performance Metrics

**Velocity:**

- Total plans completed: 59 (v0.3.0: 22, v0.4.0: 23, v0.5.0: 10)
- Average duration: — min
- Total execution time: —

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| v0.3.0 phases 01–07 | 22 | - | - |
| v0.4.0 phases 08–15.1 | 23 | - | - |
| v0.5.0 phases 16–20 | 10 | - | - |
| 21 | 4 | - | - |

**Recent Trend:**

- Last 5 plans: —
- Trend: —

| Phase 22 P22-01 | 18 | 3 tasks | 2 files |
| Phase 22 P22-02 | 35 | 2 tasks | 4 files |
| Phase 22 P22-03 | 40 | 2 tasks | 2 files |

## Accumulated Context

### Decisions

Full decision log in PROJECT.md Key Decisions table. Key v0.6.0 design decisions:

- Split responsibility: CLI owns all filesystem mutations; restructure skill owns all LLM judgment
- Skill restricted to `[Read, Bash]` — cannot call `Write`/`Edit` on project files directly
- `snapshot_create` uses raw `cp -R`, NOT `mutate_cp` — snapshot is the safety primitive, not a mutation
- Build order is hard: log.sh → snapshot.sh → inventory.sh → adopt.sh → skill → tests
- [Phase ?]: Phase 22 Wave 0: graceful-red test block in tests/run.sh gates every later verification before scripts/adopt.sh exists
- [Phase ?]: _-prefixed fixture dirs are excluded from the generic tests/fixtures/[^_]*/ audit + golden-EXPECT loops
- [Phase ?]: SIGKILL recovery test asserts the non-TTY exit-2 + last-completed form; interactive prompt deferred to manual verification
- [Phase ?]: Phase 22 Wave 1: cmd_adopt thin dispatcher + scripts/adopt.sh 5-step forward pipeline
- [Phase ?]: Pitfall 3 self-copy fixed by snapshotting into a temp root outside the target then relocating into .conjure-adopt-backups (no lib change)
- [Phase ?]: .conjure-adopt-state directory-form (state.json + staging/); state written atomically (jq>tmp+mv) BEFORE each mutating step for SIGKILL durability (SAFE-04)
- [Phase ?]: Phase 22 Wave 2: rollback_path D-01 3-step — capture created[]/mutated[] before snapshot_rollback (snapshot has stale state.json), restore, strip leaked .snapshot-meta.json, mutate_rm created[], prune snapshot-absent empty dirs, sha256-verify mutated[]; yields Phase 24 zero-diff
- [Phase ?]: apply-step write src is target-relative per D-07; op-allowlist {write,archive,extract} + required-fields {id,op,status} + resolve_under containment guard, exit 2 with no partial mutation (T-22-09/10/11)
- [Phase ?]: Phase 22 --resume reuses the existing snapshot via CONJURE_ADOPT_REUSE_SNAPSHOT so no second backup is created CR-2 and preserves durable log plus state rather than re-initializing per D-12

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
| hardening | adopt `--rollback` fails-closed if SIGKILL lands in the snapshot_path-flush window (no snapshot recorded). Safe (refuse, no corruption); proper fix needs a snapshot-completion marker (touches Phase 21 snapshot contract). Manual UAT 2026-05-29 confirmed all 3 recovery branches otherwise work. | known_limitation | Phase 22 close → Phase 24 |

## Session Continuity

Last session: 2026-05-28T21:26:15.577Z
Stopped at: Completed 22-03-PLAN.md (Phase 22 complete — all plans done)
Resume file: None
