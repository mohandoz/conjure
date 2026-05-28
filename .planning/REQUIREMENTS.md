# Requirements: Conjure — v0.6.0 Safe Brownfield Adoption

**Defined:** 2026-05-28
**Core Value:** A developer can turn any repo into a production-grade, eval-backed Claude Code harness with one trustworthy command — and keep it healthy over time.

## v1 Requirements

Requirements for milestone v0.6.0. Each maps to exactly one roadmap phase.

### Adopt CLI

The deterministic, one-command entrypoint for folding an existing project into the harness.

- [ ] **ADOPT-01**: User can run `conjure adopt` on an existing repo to fold it into the four-layer harness in one command
- [ ] **ADOPT-02**: User can preview every planned change with `conjure adopt --dry-run` with zero filesystem side-effects before anything is written
- [ ] **ADOPT-03**: `conjure adopt` refuses to run on a dirty git tree (exit 2) unless `--force` is passed
- [ ] **ADOPT-04**: `conjure adopt` scaffolds only *missing* harness layers (skills/agents/hooks/docs) by reusing the idempotent init scaffold — never overwriting existing files
- [ ] **ADOPT-05**: `conjure adopt` runs the size-cap + schema audit and reports harness health before and after adoption
- [ ] **ADOPT-06**: User sees an adoption report summarizing before/after state (files inventoried, layers scaffolded, files archived, CLAUDE.md line-count delta)

### Safety & Rollback

"Lose nothing" made concrete and testable. Per-step transparency.

- [ ] **SAFE-01**: `conjure adopt` takes a full timestamped snapshot of every touched path before the first mutation
- [ ] **SAFE-02**: User can fully restore the pre-adopt state with `conjure adopt --rollback` — every file's sha256 after rollback equals its sha256 recorded before the run
- [ ] **SAFE-03**: No user file is ever deleted — stale files are archived (moved to a timestamped archive dir), never `rm`'d, under any flag
- [ ] **SAFE-04**: Each completed step is recorded in a step-completion manifest (path + sha256 before/after) so an interrupted run can be detected and recovered
- [ ] **SAFE-05**: `conjure adopt` traps interrupts (INT/TERM → exit 2) and, on restart after partial completion, offers rollback / continue / start-fresh
- [ ] **SAFE-06**: The snapshot records git state (HEAD sha + stash list); the tool warns that `--rollback` restores from the filesystem snapshot, not git
- [ ] **SAFE-07**: Every adopt/restructure step appends to a human-readable `RESTRUCTURE-LOG.md` as it happens (survives a mid-run kill) — a clear, persisted record of what changed at each step

### Inventory & Classification

The deterministic plan output and the CLI↔skill contract.

- [ ] **INV-01**: `conjure adopt` inventories every markdown file and classifies each into a harness bucket (core / skill / agent / planning-doc / reference-doc / unknown)
- [ ] **INV-02**: The inventory is emitted as a machine-readable manifest (`adopt-manifest.json`) that is the contract between the CLI and the restructure skill
- [ ] **INV-03**: Inventory skips binary/symlink/generated/vendored files and caps the default scan at 500 files (`--full-inventory` to exceed), with a progress indicator
- [ ] **INV-04**: The manifest flags every size-cap violation (e.g. CLAUDE.md over 100 lines) so the restructure step can target it

### Restructure Skill & Guardrails

The human-gated LLM judgment layer, with safety gates that run on *proposed* content before approval.

- [ ] **RESTR-01**: A `restructure` skill (installed by adopt) reads the manifest + oversized CLAUDE.md + doc sprawl and proposes a plan: ≤100-line CLAUDE.md core, what extracts to skills/subagents, what stays as linked reference, what is archived
- [ ] **RESTR-02**: The skill applies changes ONLY through `conjure adopt` primitives (skill restricted to Read + Bash tools) so every mutation routes through the safe mutate chokepoint and audit trail
- [ ] **RESTR-03**: User approves each restructure step; large corpora use hierarchical grouped approvals (per-class strategy), never one prompt per file
- [ ] **RESTR-04**: A constraint-extraction pre-pass captures invariants from CLAUDE.md; the proposed output is verified to contain every invariant, and approval is blocked if any is missing
- [ ] **RESTR-05**: Proposed content is run through `conjure audit` before the user is asked to approve it — content with `@imports` or cap breaches is blocked pre-write
- [ ] **RESTR-06**: Archive decisions are sequenced last, individually confirmed, and gated by a decision-vocabulary scan ("decided" / "we chose" / "rationale" / "do not" / "never")

## v2 Requirements

Deferred to a later v0.6.x or v0.7.0. Tracked, not in this roadmap.

### Adopt Ergonomics

- **ADOPT-07**: `--json` inventory/report output for CI pipelines
- **ADOPT-08**: `--quick` mode that skips `wc -l` on large files for faster scans on network storage

## Out of Scope

Explicitly excluded for v0.6.0. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| Fully autonomous (no-approval) restructure | Content judgment cannot be made safely without human sign-off; per-step approval is the trust model |
| Permanent deletion of any user file | Never, under any flag — archive only; deletion is a data-loss foot-gun |
| Auto-commit or auto-push after adopt | Trust violation; the user must review the diff and commit |
| Interactive TUI for approvals | Breaks CI, adds deps, excludes Windows Git Bash; the `y/n` model from `conjure resolve` is adequate |
| Cross-repo / workspace orchestration | v0.7.0 — safe single-repo brownfield adoption must be correct first |
| Migrating FROM competitor tools (cursor/aider/…) | Already covered by `conjure migrate`; adopt targets grown-messy Claude Code / GSD projects |

## Traceability

Which phases cover which requirements. Populated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| ADOPT-01 | TBD | Pending |
| ADOPT-02 | TBD | Pending |
| ADOPT-03 | TBD | Pending |
| ADOPT-04 | TBD | Pending |
| ADOPT-05 | TBD | Pending |
| ADOPT-06 | TBD | Pending |
| SAFE-01 | TBD | Pending |
| SAFE-02 | TBD | Pending |
| SAFE-03 | TBD | Pending |
| SAFE-04 | TBD | Pending |
| SAFE-05 | TBD | Pending |
| SAFE-06 | TBD | Pending |
| SAFE-07 | TBD | Pending |
| INV-01 | TBD | Pending |
| INV-02 | TBD | Pending |
| INV-03 | TBD | Pending |
| INV-04 | TBD | Pending |
| RESTR-01 | TBD | Pending |
| RESTR-02 | TBD | Pending |
| RESTR-03 | TBD | Pending |
| RESTR-04 | TBD | Pending |
| RESTR-05 | TBD | Pending |
| RESTR-06 | TBD | Pending |

**Coverage:**
- v1 requirements: 23 total
- Mapped to phases: 0 (roadmap pending)
- Unmapped: 23 ⚠️ (filled by roadmapper)

---
*Requirements defined: 2026-05-28*
*Last updated: 2026-05-28 after initial definition (milestone v0.6.0)*
