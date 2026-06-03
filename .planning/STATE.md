---
gsd_state_version: 1.0
milestone: v0.7.0
milestone_name: Plugin-native + Policy-grade
status: verifying
last_updated: "2026-06-03T09:58:49.835Z"
last_activity: 2026-06-03
progress:
  total_phases: 6
  completed_phases: 2
  total_plans: 8
  completed_plans: 8
  percent: 33
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-06-03)

**Core value:** A developer can turn any repo into a production-grade, eval-backed Claude Code harness with one trustworthy command — and keep it healthy over time.
**Current focus:** Phase 26 — sandbox-managed-settings-mdm

## Current Position

Phase: 26 (sandbox-managed-settings-mdm) — EXECUTING
Plan: 4 of 4
Status: Phase complete — ready for verification
Last activity: 2026-06-03

## Performance Metrics

**Velocity:**

- Total plans completed: 83 (v0.3.0: 22, v0.4.0: 23, v0.5.0: 10, v0.6.0: 12, v0.6.1 quick: 1 [qk-260603-302])
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

Last session: 2026-06-03T09:58:49.829Z
Stopped at: Phase 25 context gathered
Resume file: None

## Operator Next Steps

- Begin Phase 25: `/gsd-plan-phase 25`
- Before planning Phase 28 (eval): run `--research-phase 3` (promptfoo + Conjure harness integration)
- Before planning Phase 30 (workspace saga): run `--research-phase 5` (aggregate rollback state machine)
