# Roadmap: Conjure

## Completed Milestones

- **v0.3.0** — "Testing + Telemetry" — 7 phases, 22 plans, 20/20 requirements satisfied, 169 commits (2026-05-24 → 2026-05-25) — [Archive](.planning/milestones/v0.3.0-ROADMAP.md)
- **v0.4.0** — "Distribution + Ecosystem" — 9 phases, 23 plans, 29/29 requirements satisfied, 136 commits (2026-05-25 → 2026-05-26) — [Archive](.planning/milestones/v0.4.0-ROADMAP.md)
- **v0.5.0** — "Auto-Update + Healthcheck" — 5 phases, 10 plans, 11/11 requirements satisfied, 49 commits (2026-05-26 → 2026-05-28) — [Archive](.planning/milestones/v0.5.0-ROADMAP.md)

## Active Milestone

**v0.6.0 — "Safe Brownfield Adoption"** — 4 phases (21–24), 23 requirements, started 2026-05-28

**Milestone Goal:** Let `conjure` safely fold an existing, grown-messy project into a best-practice four-layer harness — losing nothing, backing up everything, reporting each change.

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

### v0.6.0 Safe Brownfield Adoption (Phases 21-24)

- [x] **Phase 21: Foundation Libs + Inventory** - `lib/log.sh`, `lib/snapshot.sh`, `lib/inventory.sh`, `lib/caps.sh`, and finalized `adopt-manifest.json` schema with 6-bucket classification (completed 2026-05-28)
- [ ] **Phase 22: `conjure adopt` CLI Core + Rollback** - `scripts/adopt.sh` + `cmd_adopt`, full 5-step pipeline, `--dry-run`, `--force`, `--rollback`, `--apply-step`, step-completion manifest, signal traps, snapshot-meta with git state
- [ ] **Phase 23: Restructure Skill + Safety Gates** - `templates/skills/restructure/SKILL.md`, constraint-extraction pre-pass, pre-write audit gate, hierarchical approvals, archive-last sequencing + decision-vocabulary scan
- [ ] **Phase 24: Integration Tests + Argus Fixture** - `tests/fixtures/brownfield-argus/`, bats-core tests covering dry-run output, rollback zero-diff, idempotent re-run, SIGKILL recovery, 500-file perf gate, symlink skip, @import pre-write block

## Phase Details

### Phase 21: Foundation Libs + Inventory

**Goal**: The shared library layer and inventory contract that every subsequent component depends on are in place and independently testable
**Depends on**: Phase 20 (v0.5.0 complete; `lib/mutate.sh` shipped)
**Requirements**: INV-01, INV-02, INV-03, INV-04, SAFE-03, ADOPT-03
**Success Criteria** (what must be TRUE):

  1. `lib/log.sh` writes a `RESTRUCTURE-LOG.md` header and structured `[TIMESTAMP] [PHASE] message` entries via `mutate_write --append`; a dry-run invocation prints entries without touching the filesystem
  2. `lib/snapshot.sh` creates a full timestamped backup under `.conjure-adopt-backups/` using raw `cp -R` (not `mutate_cp`); the snapshot directory is non-empty and contains `CLAUDE.md` and `.claude/`
  3. `lib/inventory.sh` scans a fixture repo, classifies every markdown file into one of the 6 harness buckets, skips symlinks/binary/vendored files, caps at 500 files by default, and emits a valid `adopt-manifest.json` with a `summary` block and per-file `cap_exceeded` flags
  4. `adopt-manifest.json` schema is finalized: `schema_version`, `summary.*`, `files[]`, `size_cap_violations[]`, `harness_missing_layers`, `restructure_steps[]`; a sample manifest validates against the schema
  5. `lib/caps.sh` exports `CLAUDE_MD_CAP=100`, `SKILL_MD_CAP=200`, `AGENT_MD_CAP=80`; stale files are archived (moved to `.conjure-archive-<ts>/`) via a `mutate_archive` primitive, never deleted

**Plans**: 4 plans
Plans:
**Wave 1**

- [x] 21-01-PLAN.md — Wave 0: brownfield-simple fixture + adopt-manifest.schema.json + Phase 21 test block scaffold
- [x] 21-02-PLAN.md — Wave 1: lib/caps.sh + lib/log.sh + mutate_archive in lib/mutate.sh

**Wave 2** *(blocked on Wave 1 completion)*

- [x] 21-03-PLAN.md — Wave 2: lib/snapshot.sh + lib/inventory.sh (6-bucket classifier + manifest emitter)

**Wave 3** *(blocked on Wave 2 completion)*

- [x] 21-04-PLAN.md — Wave 3: audit-setup.sh cap literal extraction + integration gate checkpoint

### Phase 22: `conjure adopt` CLI Core + Rollback

**Goal**: Users can run `conjure adopt` on an existing repo to get a complete, audited, rollback-capable adoption pipeline with zero filesystem surprises
**Depends on**: Phase 21 (all three libs + manifest schema finalized)
**Requirements**: ADOPT-01, ADOPT-02, ADOPT-04, ADOPT-05, ADOPT-06, SAFE-01, SAFE-02, SAFE-04, SAFE-05, SAFE-06, SAFE-07
**Success Criteria** (what must be TRUE):

  1. Running `conjure adopt --dry-run` on a brownfield fixture prints the full 5-step plan (preconditions, snapshot, inventory, scaffold, audit) and writes zero files; `adopt-manifest.json` is written to a temp path so the plan is inspectable
  2. Running `conjure adopt` on a clean-tree fixture creates a snapshot, emits `adopt-manifest.json`, scaffolds only missing harness layers (existing files untouched), runs `audit-setup.sh`, and prints an adoption report showing before/after CLAUDE.md line-count
  3. Running `conjure adopt` on a dirty-tree fixture exits 2 with a clear message; running the same command with `--force` proceeds and logs a warning in `RESTRUCTURE-LOG.md` that uncommitted changes are included in the snapshot
  4. Running `conjure adopt --rollback` after a live run restores every mutated file; the sha256 of each restored file matches its sha256 recorded before the run; `RESTRUCTURE-LOG.md` contains a `[ROLLBACK]` entry
  5. Sending SIGKILL mid-run (via `kill -9`) and then re-running `conjure adopt` detects the partial `.conjure-adopt-state` manifest and offers `[r]ollback / [c]ontinue / [s]tart-fresh`

**Plans**: TBD

### Phase 23: Restructure Skill + Safety Gates

**Goal**: The human-gated restructure skill is installed and operational, with pre-write safety gates that block invalid LLM proposals before the user is ever asked to approve them
**Depends on**: Phase 22 (`conjure adopt --apply-step` and `--update-manifest` working and tested)
**Requirements**: RESTR-01, RESTR-02, RESTR-03, RESTR-04, RESTR-05, RESTR-06
**Success Criteria** (what must be TRUE):

  1. After running `conjure adopt`, a `restructure` skill is present at `.claude/skills/restructure/SKILL.md` in the target; the skill's frontmatter specifies `allowed-tools: [Read, Bash]` and the file is ≤200 lines
  2. The skill reads `adopt-manifest.json`, proposes a numbered restructure plan for an oversized CLAUDE.md, and requires explicit `approve / skip / edit` per step; it never proceeds without a response and never calls `Write` or `Edit` tools on project files directly
  3. For a corpus with 50+ files, the skill presents per-class grouped approvals (not one prompt per file), and the RESTRUCTURE-LOG.md records only a summary line for bulk operations
  4. A constraint-extraction pre-pass on CLAUDE.md produces `INVARIANTS.txt`; proposing a condensed CLAUDE.md that omits an invariant (e.g., "hooks must exit 2") causes the approval gate to block with a list of missing invariants before the user sees the proposal
  5. A proposed CLAUDE.md containing `@import` lines is run through `conjure audit` before approval; the gate blocks with the audit output and the user is not presented an approval prompt for invalid content
  6. Archive steps are sequenced last in the plan; files with decision-vocabulary keywords ("decided", "we chose", "rationale", "do not", "never") are flagged for individual confirmation and not included in bulk archive approvals

**Plans**: TBD

### Phase 24: Integration Tests + Argus Fixture

**Goal**: The complete `conjure adopt` + restructure skill pipeline is verified end-to-end against a representative brownfield fixture, with CI assertions on all safety invariants and performance bounds
**Depends on**: Phase 23 (full pipeline implemented)
**Requirements**: None (verification phase — all 23 requirements map to Phases 21–23)
**Success Criteria** (what must be TRUE):

  1. `conjure adopt --dry-run` against the 500-file `brownfield-argus` fixture completes in under 30 seconds and writes zero files to the fixture directory
  2. A live `conjure adopt` run followed immediately by `conjure adopt --rollback` produces zero diff between the fixture before and after (sha256 of every file matches)
  3. A second `conjure adopt` run on an already-adopted fixture (idempotent re-run) makes zero mutations and reports "nothing to scaffold" in the adoption summary
  4. Simulating a SIGKILL after the snapshot step and before the scaffold step, then re-running `conjure adopt`, triggers the partial-state recovery prompt; choosing rollback restores the fixture cleanly
  5. A fixture file that is a symlink is skipped by inventory; a proposed CLAUDE.md containing an `@import` line is blocked by the pre-write audit gate and never written to disk

**Plans**: TBD

## Progress

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 16. Prerequisites | v0.5.0 | 2/2 | Complete | 2026-05-26 |
| 17. Drift Detection | v0.5.0 | 2/2 | Complete | 2026-05-26 |
| 18. Conflict Resolution | v0.5.0 | 2/2 | Complete | 2026-05-26 |
| 19. Auto-PR | v0.5.0 | 2/2 | Complete | 2026-05-26 |
| 20. Windows + CI Gate | v0.5.0 | 2/2 | Complete | 2026-05-28 |
| 21. Foundation Libs + Inventory | v0.6.0 | 4/4 | Complete   | 2026-05-28 |
| 22. `conjure adopt` CLI Core + Rollback | v0.6.0 | 0/TBD | Not started | - |
| 23. Restructure Skill + Safety Gates | v0.6.0 | 0/TBD | Not started | - |
| 24. Integration Tests + Argus Fixture | v0.6.0 | 0/TBD | Not started | - |
