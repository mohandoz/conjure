---
gsd_state_version: 1.0
milestone: v0.8.0
milestone_name: Operability + DX
status: verifying
last_updated: "2026-06-06T02:06:16.772Z"
last_activity: 2026-06-06 - Merged phase 31 into main; CI fixes (GNU grep, fixture-escape cleanup)
progress:
  total_phases: 6
  completed_phases: 1
  total_plans: 4
  completed_plans: 4
  percent: 17
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-06-04)

**Core value:** A developer can turn any repo into a production-grade, eval-backed Claude Code harness with one trustworthy command — and keep it healthy over time.
**Current focus:** Phase 31 — deferred-debt-test-harness-hardening

## Current Position

Phase: 31 (deferred-debt-test-harness-hardening) — executed, awaiting human UAT
Plan: 4 of 4 complete
Status: Phase 31 verification human_needed (see 31-HUMAN-UAT.md)
Last activity: 2026-06-06 - Merged phase 31 into main; CI fixes (GNU grep, fixture-escape cleanup)

## Performance Metrics

**Velocity:**

- Total plans completed: 103 across v0.3.0–v0.7.0
- Average duration: — min
- Total execution time: —

**By Phase (v0.8.0):**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 31 | TBD | - | - |
| 32 | TBD | - | - |
| 33 | TBD | - | - |
| 34 | TBD | - | - |
| 35 | TBD | - | - |
| 36 | TBD | - | - |

## Accumulated Context

### Decisions

Key decisions from v0.7.0 carried forward:

- Advisory checks use `note()` (exit 0), never `warn()` — `warn()` flips audit exit to 1 in CI
- Every filesystem write routes through `lib/mutate.sh`; `snapshot_create` is the sole exception
- `scripts/doctor.sh` + `scripts/stats.sh` are read-only workers; must NOT source `lib/mutate.sh`
- JSONL reads must use `jq -R -r 'try (fromjson | ...) // empty'` (per-line try-parse, not whole-file)

### Pending Todos

None.

### Blockers/Concerns

- Phase 31: `preflight.sh:109` exit 1 fix requires caller audit confirming no `$? -eq 1` equality checks
- Phase 34 (Eval): fork-PR guard in emitted GitHub Actions workflow needs per-phase research before planning (flagged in SUMMARY.md)
- Phase 34: profile marker convention (`<!-- profile:<name> -->`) verified for ts-next; other 8 profiles need confirmation during planning
- Phase 29/30: workspace adopt multi-repo brownfield is HIGH complexity + HIGH risk — SUMMARY.md noted as "defer to v0.7.x or v0.8.0" in FEATURES.md but WS-06/WS-07 are v1 requirements; Phase 30 must be locked until Phase 29 manifest infrastructure is proven
- Phase 28: promptfoo `claude-code-agent` provider behavior against Conjure's harness structure is novel; SUMMARY.md recommends a `--research-phase 3` pass before planning Phase 28
- Phase 30: workspace manifest schema + aggregate rollback state machine design is new territory; SUMMARY.md recommends a `--research-phase 5` pass before planning Phase 30
- Windows `managed-settings.d/` drop-in directory behavior: MEDIUM confidence; verify during Phase 26 planning before generating Windows drop-in configs

### Quick Tasks Completed

| # | Description | Date | Commit | Status | Directory |
|---|-------------|------|--------|--------|-----------|
| 260603-302 | v0.6.1 hardening patch: dead stdin hooks, gitleaks branch, curl-pipe cron, predictable temp, exit 1→2, rm-rf regex | 2026-06-02 | 076aca5 | Verified | [260603-302-v0-6-1-hardening-patch-fix-dead-hooks-st](./quick/260603-302-v0-6-1-hardening-patch-fix-dead-hooks-st/) |
| 260605-sdw | Add Makefile with install/uninstall targets for local dev | 2026-06-05 | 5112349 | | [260605-sdw-add-makefile-with-install-uninstall-targ](./quick/260605-sdw-add-makefile-with-install-uninstall-targ/) |
| 260605-smk | Fix cli/conjure CONJURE_HOME symlink resolution | 2026-06-05 | 6bafa6d | | [260605-smk-fix-cli-conjure-conjure-home-symlink-res](./quick/260605-smk-fix-cli-conjure-conjure-home-symlink-res/) |
| 260605-sv6 | Fix settings.json template: schema URL + fork-bomb deny rule | 2026-06-05 | 432409a | | [260605-sv6-fix-invalid-settings-json-template-schem](./quick/260605-sv6-fix-invalid-settings-json-template-schem/) |
| 260605-tlg | Graphify integration: backend auto-detect, --setup, SessionStart check | 2026-06-05 | 960101a | | [260605-tlg-upgrade-graphify-integration-backend-aut](./quick/260605-tlg-upgrade-graphify-integration-backend-aut/) |
| 260605-txz | Fix hook template: CLAUDE_PROJECT_DIR paths + UserPromptSubmit event | 2026-06-05 | 58caa39 | | [260605-txz-fix-hook-template-bugs-relative-paths-an](./quick/260605-txz-fix-hook-template-bugs-relative-paths-an/) |
| 260605-udi | Workspace-scoped graph merge: --merge flag, drop machine-global add | 2026-06-05 | 621ef72 | | [260605-udi-make-global-graph-merge-opt-in-via-merge](./quick/260605-udi-make-global-graph-merge-opt-in-via-merge/) |

## Deferred Items

Items carried from v0.7.0 close (2026-06-04):

| Category | Item | Status |
|----------|------|--------|
| uat_gap | Phase 25 HUMAN-UAT (live claude --validate) | Addressed in Phase 31 (MANUAL-UAT.md) |
| uat_gap | Phase 26 HUMAN-UAT (managed-settings deploy, MDM hardware) | Addressed in Phase 31 (MANUAL-UAT.md) |
| uat_gap | Phase 28 HUMAN-UAT (live promptfoo enforcement) | Addressed in Phase 31 (UAT-02 gated smoke) |
| test_debt | git -C "$VAR" empty-var guard after mktemp | Addressed in Phase 31 (DEBT-03) |
| test_debt | SCHM-STALE kill-safe atomic swap | Addressed in Phase 31 (DEBT-06) |

## Session Continuity

Last session: 2026-06-06T02:06:16.767Z
Stopped at: Phase 31 context gathered
Resume file: None
