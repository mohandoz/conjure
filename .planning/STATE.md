---
gsd_state_version: 1.0
milestone: v0.6.0
milestone_name: Safe Brownfield Adoption
status: milestone_complete
last_updated: 2026-05-29T04:00:05.309Z
last_activity: 2026-05-29
progress:
  total_phases: 4
  completed_phases: 4
  total_plans: 12
  completed_plans: 12
  percent: 100
stopped_at: Milestone complete (Phase 24 was final phase)
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-05-28)

**Core value:** A developer can turn any repo into a production-grade, eval-backed Claude Code harness with one trustworthy command — and keep it healthy over time.
**Current focus:** Milestone complete

## Current Position

Phase: 24
Plan: Not started
Status: Milestone complete
Last activity: 2026-05-29

Progress: [██████████] 100%

## Performance Metrics

**Velocity:**

- Total plans completed: 67 (v0.3.0: 22, v0.4.0: 23, v0.5.0: 10)
- Average duration: — min
- Total execution time: —

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| v0.3.0 phases 01–07 | 22 | - | - |
| v0.4.0 phases 08–15.1 | 23 | - | - |
| v0.5.0 phases 16–20 | 10 | - | - |
| 21 | 4 | - | - |
| 22 | 3 | - | - |
| 23 | 3 | - | - |
| 24 | 2 | - | - |

**Recent Trend:**

- Last 5 plans: —
- Trend: —

| Phase 22 P22-01 | 18 | 3 tasks | 2 files |
| Phase 22 P22-02 | 35 | 2 tasks | 4 files |
| Phase 22 P22-03 | 40 | 2 tasks | 2 files |
| Phase 23 P23-01 | 14 | 2 tasks | 9 files |
| Phase 23 P23-02 | 35 | 2 tasks | 5 files |
| Phase 23 P23-03 | 9 | 2 tasks | 4 files |
| Phase 24 P24-01 | 4 | 2 tasks | 2 files |
| Phase 24 P24-02 | 8 | 2 tasks | 1 files |

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
- [Phase ?]: Phase 23 Wave 0: graceful-red Phase 23 test block in tests/run.sh gates every Wave 1/2 deliverable (4 gate helpers, SKILL.md scaffold, approval driver) before any of them exist
- [Phase ?]: Phase 23 fixtures live under tests/fixtures/_restructure-gates/ (leading underscore) to dodge the generic tests/fixtures/[^_]*/ audit + golden-EXPECT loops at run.sh:326/368/390
- [Phase ?]: Phase 23 INVARIANTS.txt holds 5 canonical tokens (exit 2, @import, ≤100, mutate.sh, do not delete), proven against case/whitespace-mangled reflowed-invariant.md for the D-07 normalized-substring contract
- [Phase ?]: Phase 23 Wave 1: 4 deterministic gate helpers shipped (verify-invariants/audit-staged/extract-invariants/decision-scan); all exit 2 never exit 1, shellcheck-clean; audit-staged BLOCK keys on named conditions not audit rc; fixed check.sh to skip SKILL.md-less skill dirs
- [Phase 23]: Wave 2: thin restructure SKILL.md ([Read, Bash] chokepoint, <=200 lines, orchestration prose only) + per-class /dev/tty approve/skip/edit driver (non-TTY exit-2, one RESTRUCTURE summary line per bucket, no external editor on edit/O-3); scaffolded via init-project.sh whole-dir copy
- [Phase 23]: check.sh drift manifest now registers every kit file under an installable skill dir (SKILL.md + attached gates/*.sh), not just SKILL.md - whole-dir-copied helpers are no longer spurious added-drift and ARE integrity-checked
- [Phase ?]: [Phase 24] Plan 01: _brownfield-argus is a generator-script fixture (509 .md + real ln -s symlink + 127-line oversized CLAUDE.md + @import seed materialized at test time), exit 2 not exit 1, shellcheck-clean; only the generator is committed
- [Phase ?]: [Phase 24] Plan 01: O-1 report() deviation is a single ADDITIVE conditional echo — emits literal 'nothing to scaffold' when created_count==0 while preserving the 'Scaffolded: 0 layer files' count line; full suite stays PASS 429/0
- [Phase 24]: Plan 02: the ▸ Phase 24 E2E block proves all 5 v0.6.0 ROADMAP criteria against the 500-file _brownfield-argus fixture — reuses P22_ADOPT_SH + p22_sha, guards on P24_ARGUS_OK; suite 429 -> 447 PASS, FAIL 0, shellcheck-clean
- [Phase 24]: Plan 02: C4 SIGKILL section polls state.json .current_step (break on snapshot|inventory) inside a 3-attempt anti-flake relaunch loop keyed on the last-observed step; out-of-window kills clear state+backups and relaunch from a cp -aR pristine copy; interactive [r]/[c]/[s] prompt left manual-only (PTY, UAT'd 22/23)

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

Last session: 2026-05-29T03:37:58.462Z
Stopped at: Completed 24-01-PLAN.md (Phase 24 Wave 1)
Resume file: None
