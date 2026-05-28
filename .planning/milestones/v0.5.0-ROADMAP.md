# Roadmap: Conjure

## Completed Milestones

- **v0.3.0** — "Testing + Telemetry" — 7 phases, 22 plans, 20/20 requirements satisfied, 169 commits (2026-05-24 → 2026-05-25) — [Archive](.planning/milestones/v0.3.0-ROADMAP.md)
- **v0.4.0** — "Distribution + Ecosystem" — 9 phases, 23 plans, 29/29 requirements satisfied, 136 commits (2026-05-25 → 2026-05-26) — [Archive](.planning/milestones/v0.4.0-ROADMAP.md)

## Active Milestone

**v0.5.0 — Auto-Update + Healthcheck**

Enable harnesses to stay current: detect drift from upstream, resolve conflicts interactively, and automate updates via PR. Closes the lifecycle loop opened in v0.4.0.

## Phases

<details>
<summary>✅ v0.4.0 Distribution + Ecosystem (Phases 08-15.1) — SHIPPED 2026-05-26</summary>

- [x] **Phase 08: Nyquist Compliance Backfill** - Write VALIDATION.md for phases 01, 02, 04, 05, 06, 07 (completed 2026-05-25)
- [x] **Phase 09: 3-Way Merge** - Implement `cmd_update --apply` via `lib/merge.sh` + base snapshot (completed 2026-05-25)
- [x] **Phase 10: Marketplace Publish** - Wire and validate the Claude Code Marketplace plugin manifest (completed 2026-05-25)
- [x] **Phase 11: Skill Publishing** - Add `conjure publish-skill` command with egress scan + PR flow (completed 2026-05-25)
- [x] **Phase 12: Org Overlay** - Implement `conjure init --overlay` + `conjure refresh-overlay` system (completed 2026-05-25)
- [x] **Phase 13: Homebrew Tap** - Publish `mohandoz/homebrew-conjure` formula and auto-bump action (completed 2026-05-25)
- [x] **Phase 14: Docker + Windows CI** - Multi-arch Docker image and `windows-latest` CI matrix entry (completed 2026-05-26)
- [x] **Phase 15: Release Pipeline** - Single `release.yml` wires all distribution targets under one gate (completed 2026-05-26)
- [x] **Phase 15.1: Fix release.yml Docker+Homebrew coupling** - Decouple Docker and Homebrew into independent jobs; add HOMEBREW_TAP_GITHUB_TOKEN preflight (completed 2026-05-26)

</details>

### v0.5.0 Auto-Update + Healthcheck (Phases 16-20)

- [x] **Phase 16: Prerequisites** - Add `mutate_rm` to `lib/mutate.sh` and refactor `publish-skill` positional arg (completed 2026-05-26)
- [x] **Phase 17: Drift Detection** - Implement `conjure check` with 3-way drift classification and exit codes (completed 2026-05-26)
- [x] **Phase 18: Conflict Resolution** - Implement `conjure resolve` interactive sidecar walk (completed 2026-05-26)
- [x] **Phase 19: Auto-PR** - Implement `conjure update --pr` with idempotency guard and cron template (completed 2026-05-26)
- [x] **Phase 20: Windows + CI Gate** - Ship `conjure.ps1` PowerShell shim and CI validation jobs (completed 2026-05-26)

## Phase Details

### Phase 16: Prerequisites
**Goal**: Lay the two infrastructure foundations that every downstream phase requires — a dry-run-safe file deletion primitive and a clean positional argument interface for `publish-skill`
**Depends on**: Phase 15.1 (v0.4.0 complete)
**Requirements**: INFRA-01, DEBT-02
**Success Criteria** (what must be TRUE):
  1. `conjure publish-skill <name> <org/repo>` works with a positional second argument and no `TARGET_REPO` env required
  2. Using `TARGET_REPO` env still works but prints a `WARN:` deprecation message
  3. `mutate_rm <path>` exists in `lib/mutate.sh`, respects `DRY_RUN`, and increments `CONJURE_DRY_MUTATION_COUNT`
  4. Existing `mutate_cp` / `mutate_write` regression tests still pass; new `mutate_rm` regression test added
**Plans**: 2 plans
Plans:
- [x] 16-01-PLAN.md — Add mutate_rm to lib/mutate.sh + regression test (INFRA-01)
- [x] 16-02-PLAN.md — publish-skill positional $2 refactor + SKILL-05 test (DEBT-02)

### Phase 17: Drift Detection
**Goal**: Users can discover whether their installed harness has drifted from the upstream kit snapshot via a single read-only command
**Depends on**: Phase 16
**Requirements**: DRIFT-01, DRIFT-02
**Success Criteria** (what must be TRUE):
  1. `conjure check` prints a file-level delta report showing added, modified, and removed files relative to the upstream kit snapshot
  2. `conjure check` exits 0 when the harness is fully current and exits 1 when drift is detected
  3. `conjure check --porcelain` emits machine-readable lines consumable by scripts without text parsing
  4. A harness file with only user edits (not upstream changes) is not falsely reported as drifted
**Plans**: 2 plans
Plans:
- [x] 17-01-PLAN.md — Create scripts/check.sh worker (sha256 classifier, manifest builder, M/R/A output)
- [x] 17-02-PLAN.md — Wire cmd_check in cli/conjure + DRIFT regression tests in tests/run.sh

### Phase 18: Conflict Resolution
**Goal**: Users can interactively resolve all diff3 conflict sidecars left by `conjure update --apply` without manually editing files
**Depends on**: Phase 16
**Requirements**: RESOLVE-01, RESOLVE-02
**Success Criteria** (what must be TRUE):
  1. `conjure resolve` walks through each `.conjure-conflict-*` sidecar file and prompts `[k]eep / [a]pply / [e]dit / [s]kip` per file
  2. Running `conjure resolve` in a non-interactive environment (piped stdin) exits 2 with a clear error message
  3. After a user confirms a resolution, the sidecar file is removed via `mutate_rm` (dry-run safe)
  4. When all sidecars are cleared, `conjure resolve` prints "No conflicts remain" and exits 0
**Plans**: 2 plans
Plans:
- [x] 18-01-PLAN.md — Create scripts/resolve.sh worker (sidecar walker, prompt loop, mutate_rm)
- [x] 18-02-PLAN.md — Wire cmd_resolve in cli/conjure + RESOLVE regression tests in tests/run.sh

### Phase 19: Auto-PR
**Goal**: Users can automate harness-update PRs on demand or via a scheduled GitHub Action without manual git operations
**Depends on**: Phase 17, Phase 18
**Requirements**: AUTPR-01, AUTPR-02
**Success Criteria** (what must be TRUE):
  1. `conjure update --pr` pushes a harness-update branch and opens a GitHub PR with the drift diff as the PR body
  2. Running `conjure update --pr` a second time when a PR already exists for the same branch prints the existing PR URL and exits 0 (idempotent)
  3. An optional `.github/workflows/conjure-update.yml` cron template is written by `conjure update --cron` enabling automated weekly drift checks
**Plans**: 2 plans
Plans:
- [x] 19-01-PLAN.md — Add --pr and --cron branches to cmd_update in cli/conjure (AUTPR-01, AUTPR-02)
- [x] 19-02-PLAN.md — Add AUTPR regression tests to tests/run.sh (AUTPR-01, AUTPR-02)

### Phase 20: Windows + CI Gate
**Goal**: Native Windows users can invoke `conjure` without Git Bash, and CI correctly rejects tagged releases that lack check-run evidence
**Depends on**: Phase 19
**Requirements**: WIN-01, WIN-02, DEBT-01
**Success Criteria** (what must be TRUE):
  1. `conjure.ps1` invokes the full `conjure` CLI on native Windows without requiring Git Bash or a manual PATH setup
  2. `conjure.ps1` propagates exit codes correctly — running `conjure.ps1 --version` in pwsh exits 0; a command that exits 2 propagates 2 to the caller
  3. CI matrix includes a `windows-latest` job with `shell: pwsh` that smoke-tests `conjure.ps1 --version` and asserts exit code propagation
  4. The `ci-gate` job in `release.yml` fails with an explicit error message when a tagged commit has zero GitHub check-runs, and includes a retry loop to handle API propagation lag
**Plans**: 2 plans
Plans:
- [x] 20-01-PLAN.md — conjure.ps1 PowerShell shim (WIN-01)
- [x] 20-02-PLAN.md — windows-ps1-shim CI job + ci-gate retry loop (WIN-02, DEBT-01)

## Progress

**Execution Order:** 16 → 17 → 18 → 19 → 20

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 16. Prerequisites | 2/2 | Complete   | 2026-05-26 |
| 17. Drift Detection | 2/2 | Complete   | 2026-05-26 |
| 18. Conflict Resolution | 2/2 | Complete   | 2026-05-26 |
| 19. Auto-PR | 2/2 | Complete   | 2026-05-26 |
| 20. Windows + CI Gate | 2/2 | Complete   | 2026-05-26 |

## Backlog

### Future Milestones

- v0.6.0 — Workspace / cross-repo graph orchestration (single-repo correctness first)
