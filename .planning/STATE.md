---
gsd_state_version: 1.0
milestone: v0.7.0
milestone_name: Plugin-native + Policy-grade
status: executing
last_updated: "2026-06-03T23:45:12.879Z"
last_activity: 2026-06-03
progress:
  total_phases: 6
  completed_phases: 5
  total_plans: 24
  completed_plans: 22
  percent: 83
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-06-03)

**Core value:** A developer can turn any repo into a production-grade, eval-backed Claude Code harness with one trustworthy command — and keep it healthy over time.
**Current focus:** Phase 30 — workspace-orchestration-mutating-rollback-saga

## Current Position

Phase: 30 (workspace-orchestration-mutating-rollback-saga) — EXECUTING
Plan: 4 of 5
Status: Ready to execute
Last activity: 2026-06-03

## Performance Metrics

**Velocity:**

- Total plans completed: 98 (v0.3.0: 22, v0.4.0: 23, v0.5.0: 10, v0.6.0: 12, v0.6.1 quick: 1 [qk-260603-302])
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
| 25 | 4 | - | - |
| 26 | 4 | - | - |
| 27 | 4 | - | - |
| 28 | 4 | - | - |
| 29 | 3 | - | - |

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
| Phase 26 P02 | 20 | 2 tasks | 2 files |
| Phase 26 P03 | 10 | 1 tasks | 1 files |
| Phase 27 P01 | 20 | 2 tasks | 1 files |
| Phase 27 P02 | 20 | 2 tasks | 2 files |
| Phase 28 P00 | 23 | 2 tasks | 12 files |
| Phase 28 P01 | 30 | 2 tasks | 3 files |
| Phase 29 P01 | 15 | 2 tasks | 3 files |
| Phase 30 P00 | 25 | 2 tasks | 11 files |
| Phase 30 P01 | 15min | 1 tasks | 1 files |
| Phase 30 P02 | 20 | 1 tasks | 2 files |

## Accumulated Context

### Decisions

Full decision log in PROJECT.md Key Decisions table. Key v0.6.0 design decisions carried forward:

- Split responsibility: CLI owns all filesystem mutations; restructure skill owns all LLM judgment
- Skill restricted to `[Read, Bash]` — cannot call `Write`/`Edit` on project files directly
- `snapshot_create` uses raw `cp -R`, NOT `mutate_cp` — snapshot is the safety primitive, not a mutation
- Build order is hard: log.sh → snapshot.sh → inventory.sh → adopt.sh → skill → tests

v0.7.0 design decisions (from research + roadmap):

- **Emit-and-verify-at-emit-time**: every emitted artifact (plugin manifest, sandbox block, managed-settings, MDM) must ship with a testable verification command; an emitted config that silently does nothing is the milestone's primary failure class (v0.6.1 lesson)
- **SCHM ships before EVAL**: `conjure audit --json` (SCHM-05) unblocks workspace audit aggregation; schema validation of `disallowed-tools` + frontmatter enriches the eval coverage check (EVAL-05)
- **Workspace is last**: `scripts/workspace.sh` calls every other conjure subcommand as subprocess; Phases 25–28 must be stable before Phase 29/30 starts
- **Workspace split into two phases**: Phase 29 (read-only: manifest+init+check+audit) before Phase 30 (mutating: update+adopt+rollback saga); saga is HIGH risk and must not start until the manifest infrastructure is proven
- **All-snapshot-before-any-apply**: workspace saga invariant — snapshot ALL repos before applying to ANY; `.conjure-workspace-state.json` written before each op for SIGKILL durability
- **Fail-tolerant default for workspace**: one repo failure → exit 1 (partial), not exit 2; `--fail-fast` is opt-in; `--continue-on-error` explicitly for workspace update
- **bundled cc-schema.json, NOT runtime-fetched**: zero-egress-in-CI constraint wins; staleness handled by >90-day advisory warn; live-fetch is the anti-pattern for this codebase
- **promptfoo as opt-in subcommand**: never invoked from `conjure audit`/`check`; `conjure eval` with promptfoo absent exits 2 human-readable; `conjure audit` with promptfoo absent exits 0
- **Zero new runtime deps**: promptfoo via `npx --yes promptfoo@<pinned>`; plist via `python3 plistlib` or `plutil` (macOS system); everything else jq + bash already in envelope
- [Phase ?]: SCHM-02 subsumed POL-05c: deliberate refactor covering both permissions. and top-level disableBypassPermissionsMode paths; Phase 26 exit-2 behavior preserved
- [Phase ?]: awk two-line lookahead for YAML object detection in SCHM-01 (T-27-01 mitigate)
- [Phase ?]: SCHM-01 reads lib/cc-schema.json at runtime via jq — schema file is single source of truth
- [Phase ?]: workspace_state_validate accepts snapshotting as valid in-progress status; status-level validation is the caller's responsibility
- [Phase ?]: ws_do_update non-TTY gate omitted: conjure update without --apply is read-only; gate reserved for ws_do_adopt

### Pending Todos

None.

### Blockers/Concerns

- Phase 29/30: workspace adopt multi-repo brownfield is HIGH complexity + HIGH risk — SUMMARY.md noted as "defer to v0.7.x or v0.8.0" in FEATURES.md but WS-06/WS-07 are v1 requirements; Phase 30 must be locked until Phase 29 manifest infrastructure is proven
- Phase 28: promptfoo `claude-code-agent` provider behavior against Conjure's harness structure is novel; SUMMARY.md recommends a `--research-phase 3` pass before planning Phase 28
- Phase 30: workspace manifest schema + aggregate rollback state machine design is new territory; SUMMARY.md recommends a `--research-phase 5` pass before planning Phase 30
- Windows `managed-settings.d/` drop-in directory behavior: MEDIUM confidence; verify during Phase 26 planning before generating Windows drop-in configs

### Quick Tasks Completed

| # | Description | Date | Commit | Status | Directory |
|---|-------------|------|--------|--------|-----------|
| 260603-302 | v0.6.1 hardening patch: dead stdin hooks, gitleaks branch, curl-pipe cron, predictable temp, exit 1→2, rm-rf regex | 2026-06-02 | 076aca5 | Verified | [260603-302-v0-6-1-hardening-patch-fix-dead-hooks-st](./quick/260603-302-v0-6-1-hardening-patch-fix-dead-hooks-st/) |

## Deferred Items

| Category | Item | Status | Deferred At |
|----------|------|--------|-------------|
| Docker | `conjure:full` tag with optional Go/Rust tools | Deferred to v0.4.x | v0.4.0 scoping |
| Overlay | `compatible-kit-version` manifest field | Deferred to v0.4.x | v0.4.0 scoping |
| verification_gap | Phase 10 VERIFICATION.md — human_needed (claude CLI required) | human_needed | v0.4.0 close |
| verification_gap | Phase 13 VERIFICATION.md — human_needed (live brew install) | human_needed | v0.4.0 close |
| verification_gap | Phase 14 VERIFICATION.md — human_needed (Docker + Windows CI) | human_needed | v0.4.0 close |
| verification_gap | Phase 15 VERIFICATION.md — human_needed (live tag push) | human_needed | v0.4.0 close |
| hardening | adopt `--rollback` fails-closed if SIGKILL lands in snapshot_path-flush window | known_limitation | Phase 22 → Phase 24 |

## Session Continuity

Last session: 2026-06-03T23:45:12.871Z
Stopped at: Completed Phase 27 Plan 01: SCHM-01 + SCHM-02 implemented in audit-setup.sh
Resume file: None

## Operator Next Steps

- Begin Phase 25: `/gsd-plan-phase 25`
- Before planning Phase 28 (eval): run `--research-phase 3` (promptfoo + Conjure harness integration)
- Before planning Phase 30 (workspace saga): run `--research-phase 5` (aggregate rollback state machine)
