# Roadmap: Conjure — v0.3.0 "Testing + Telemetry"

## Overview

v0.3.0 closes the gap between what Conjure *claims* and what it *verifiably does*.
The journey is dependency-ordered: first fix the two live bugs that undermine
trust (`--dry-run` mutates disk; Windows hook wiring is silently dead) and harden
pre-flight, then build sandboxed per-profile fixtures, then the regression net
that guards everything — proving dry-run is byte-safe. Once `init` is trustworthy
and verifiable, record the README demo, ship the offline cost estimator, and land
the headline differentiator (local-only skill-firing telemetry) last, with the
most verification. Each phase makes the next safe to build.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [x] **Phase 1: Pre-flight & Cross-Platform Hooks** - Extract reusable pre-flight with OS-aware fix-its and make generated hook wiring run on native Windows (completed 2026-05-24)
- [x] **Phase 2: Dry-Run Enforcement Chokepoint** - Route every write through `lib/mutate.sh` so `--dry-run` mutates nothing, everywhere (completed 2026-05-24)
- [x] **Phase 3: Sandboxed Per-Profile Fixtures** - Committed, hermetic example project per stack profile plus one intentionally-failing fixture (completed 2026-05-24)
- [x] **Phase 4: Regression Suite & Dry-Run Proof** - Golden-file fixture loop, byte-identical dry-run snapshot assertion, failure-mode reproductions, and a Windows CI leg (completed 2026-05-25)
- [x] **Phase 5: README Demo** - asciinema→GIF demo of `conjure init` + `conjure audit` recorded against safe dry-run (completed 2026-05-25)
- [x] **Phase 6: Cost Estimator** - `conjure audit --cost` offline token/dollar estimate with an explicit ±band, plus opt-in `--exact` (completed 2026-05-25)
- [x] **Phase 7: Skill-Firing Telemetry** - Opt-in, local-only, PII-free skill telemetry feeding a retire-list, with an enforced no-egress test (completed 2026-05-25)

## Phase Details

### Phase 1: Pre-flight & Cross-Platform Hooks
**Goal**: Pre-flight dependency verification is reusable and OS-correct, and the harness that `init` generates fires its hooks on every supported platform including native Windows
**Mode:** mvp
**Depends on**: Nothing (first phase)
**Requirements**: SAFE-03, SAFE-04
**Success Criteria** (what must be TRUE):
  1. Running `conjure init`/`audit` reports each missing dependency with a copy-pasteable, OS-detected install fix-it (brew/apt/winget/npm) and never auto-installs
  2. Pre-flight logic lives in a standalone `scripts/preflight.sh` that both the CLI and `tests/run.sh` invoke (no inline duplication)
  3. A harness scaffolded by `conjure init` wires hooks via a runtime present on the OS (portable `node .mjs` or OS-branched), so hooks fire on native Windows instead of silently no-opping
  4. Required-dependency-missing blocks with a non-zero exit; optional-dependency-missing warns and continues
**Plans**: 2 plans

Plans:
**Wave 1**
- [x] 01-01-PLAN.md — Extract scripts/preflight.sh, wire conjure preflight subcommand, add preflight test section (SAFE-04)

**Wave 2** *(blocked on Wave 1 completion)*
- [x] 01-02-PLAN.md — Update settings.json.tmpl + init-project.sh + audit-setup.sh for node .mjs hook wiring, add template lint assertions (SAFE-03)

Cross-cutting constraints: scripts/preflight.sh must be POSIX bash 3.2+ (no bash 4+ features); backup-before-mutate on all template edits

### Phase 2: Dry-Run Enforcement Chokepoint
**Goal**: `conjure init --dry-run` produces an identical console plan while making zero filesystem mutations, enforced at one chokepoint rather than per call site
**Mode:** mvp
**Depends on**: Phase 1
**Requirements**: SAFE-01, SAFE-02
**Success Criteria** (what must be TRUE):
  1. After `conjure init --dry-run .`, the target tree is unchanged — no scaffolded `.claude/`, no profile output, no `.conjure-version` stamp
  2. All filesystem writes (init, profile/compliance apply, version stamp) route through a single shared `lib/mutate.sh` helper that honors `DRY_RUN`
  3. A dry-run run prints what it *would* write (the plan) for each intended mutation
  4. `DRY_RUN` is parsed once in the CLI and threaded into every child script, not re-checked ad hoc at each write
**Plans**: 6 plans

Plans:
**Wave 1** *(foundation — no dependencies)*
- [x] 02-01-PLAN.md — Create lib/mutate.sh: mutate_mkdir, mutate_cp, mutate_write, mutate_summary (SAFE-02)

**Wave 2** *(parallel — all depend on 02-01 only)*
- [x] 02-02-PLAN.md — Retrofit scripts/init-project.sh: replace 12 bare write sites with mutate_* calls (SAFE-01, SAFE-02)
- [x] 02-03-PLAN.md — Retrofit all 9 profiles/*/apply.sh: remove $DRY positional arg, source mutate.sh, replace write guards (SAFE-01, SAFE-02)
- [x] 02-04-PLAN.md — Retrofit all 4 compliance/*/apply.sh: add source + replace bare writes including hipaa cp+chmod (SAFE-01, SAFE-02)

**Wave 3** *(blocked on all Wave 2 plans)*
- [x] 02-05-PLAN.md — Wire DRY_RUN threading in cli/conjure cmd_init(): L75 init, L80 profile, L84 version stamp (SAFE-01, SAFE-02)

**Wave 4** *(blocked on 02-05)*
- [x] 02-06-PLAN.md — Add dry-run enforcement integration tests to tests/run.sh (SAFE-01, SAFE-02)

### Phase 3: Sandboxed Per-Profile Fixtures
**Goal**: Every stack profile has a committed, audited example project that runs hermetically, plus a deliberately-broken fixture that proves the suite can catch regressions
**Mode:** mvp
**Depends on**: Phase 2
**Requirements**: TEST-01, TEST-02, TEST-04
**Success Criteria** (what must be TRUE):
  1. There is one committed example fixture per stack profile under `tests/fixtures/<profile>/`, each auditing green
  2. Fixtures run with an isolated `HOME`/`XDG_CONFIG_HOME`/`CLAUDE_CONFIG_DIR`/`PATH` copied to a temp dir, with no reads from or writes to the developer's real `$HOME`
  3. At least one fixture intentionally fails audit, and assertions check the specific findings (not merely a non-zero exit)
  4. Fixture audits are offline and deterministic (no `graphify`/git/network), so the audit signature is reproducible
**Plans**: 3 plans

Plans:
**Wave 1** *(foundation — no dependencies)*
- [x] 03-01-PLAN.md — Create tests/lib/sandbox.sh (sourced isolation helper) and scripts/regen-fixtures.sh (fixture generator) (TEST-02)

**Wave 2** *(blocked on 03-01)*
- [x] 03-02-PLAN.md — Run regen-fixtures.sh to generate and commit all 9 green profile fixtures; verify each audits exit 0 (TEST-01)

**Wave 3** *(blocked on 03-01 and 03-02)*
- [x] 03-03-PLAN.md — Create tests/fixtures/_broken/ (201+ line CLAUDE.md + EXPECT) and extend tests/run.sh with sandboxed fixture audit sections (TEST-01, TEST-02, TEST-04)

### Phase 4: Regression Suite & Dry-Run Proof
**Goal**: A one-command, CI-gated regression suite verifies every fixture against golden files, proves dry-run leaves the tree byte-identical, encodes documented failure modes as tests, and validates Windows hook wiring
**Mode:** mvp
**Depends on**: Phase 3
**Requirements**: TEST-03, TEST-05, TEST-06, TEST-07
**Success Criteria** (what must be TRUE):
  1. `tests/run.sh` drives per-fixture audit assertions via golden-file (`EXPECT`) comparison of normalized output, failing on drift
  2. The suite asserts that a `--dry-run` run leaves a fixture tree byte-identical (snapshot invariant)
  3. CI includes a `windows-latest` leg that validates `.mjs` hook wiring fires
  4. Each failure mode documented in FAILURE-MODES.md has a reproduction encoded as a test
  5. Regenerating fixtures (e.g. `--update-expect`) and diffing prevents silent golden-file rot
**Plans**: 3 plans

Plans:
**Wave 1** *(parallel — no dependencies between them)*
- [x] 04-01-PLAN.md — Create 9 green-fixture EXPECT files, add golden-file EXPECT loop to tests/run.sh, extend scripts/regen-fixtures.sh with _write_expect (TEST-03)
- [x] 04-02-PLAN.md — Add windows-hook-wiring job to .github/workflows/ci.yml: scaffold fixture on windows-latest, assert node wiring in settings.json (TEST-06)

**Wave 2** *(blocked on 04-01 — both add sections to tests/run.sh)*
- [x] 04-03-PLAN.md — Add dry-run byte-identical snapshot section and failure-mode reproductions section to tests/run.sh (TEST-05, TEST-07)

### Phase 5: README Demo
**Goal**: A new reader sees Conjure work in seconds via a recorded demo of the now-trustworthy `conjure init` + `conjure audit`
**Mode:** mvp
**Depends on**: Phase 4
**Requirements**: DOCS-01
**Success Criteria** (what must be TRUE):
  1. The README shows an asciinema→GIF demo of `conjure init` followed by `conjure audit`
  2. The demo is recorded against a safe dry-run (no real mutation captured), reproducible from a documented command
  3. The demo reflects current behavior (cross-platform wiring, enforced dry-run) rather than a stale recording
**Plans**: 2 plans

Plans:
**Wave 1**
- [x] 05-01-PLAN.md — Create scripts/record-demo.sh: preflight, mktemp isolation, expect automation of conjure init --dry-run + audit, agg GIF conversion (DOCS-01)

**Wave 2** *(blocked on Wave 1 completion and local GIF generation)*
- [x] 05-02-PLAN.md — Generate demo.gif locally, embed in README.md Quickstart section, add CI assertion to test job (DOCS-01)

### Phase 6: Cost Estimator
**Goal**: `conjure audit --cost` gives an honest, offline-by-default estimate of per-session harness token cost without false precision
**Mode:** mvp
**Depends on**: Phase 4
**Requirements**: COST-01, COST-02, COST-03
**Success Criteria** (what must be TRUE):
  1. `conjure audit --cost` estimates per-session token cost from harness size using the chars/4 heuristic and a dated baked price table
  2. The output is explicitly labeled an estimate, prints a ±band, and names the model plus pricing as-of date (no precise-looking single number)
  3. The default cost path makes zero network calls; an opt-in `--exact` flag may call Anthropic's `count_tokens` endpoint when credentials exist
  4. A per-skill breakdown shows which skills cost the most context
**Plans**: 3 plans

Plans:
**Wave 1** *(foundation — no dependencies)*
- [x] 06-01-PLAN.md — Create lib/prices.json (baked price table), lib/exact-count.mjs (Anthropic SDK wrapper), wire --cost/--exact flags in cli/conjure cmd_audit() (COST-01, COST-02, COST-03)

**Wave 2** *(blocked on 06-01)*
- [x] 06-02-PLAN.md — Implement cost section in scripts/audit-setup.sh: CONJURE_HOME self-derivation, jq price read, per-file breakdown table, --exact integration, label line (COST-01, COST-02, COST-03)

**Wave 3** *(blocked on 06-01 and 06-02)*
- [x] 06-03-PLAN.md — Extend tests/run.sh with cost estimator test section and lib/prices.json in JSON validity loop (COST-01, COST-02, COST-03)

### Phase 7: Skill-Firing Telemetry
**Goal**: Conjure ships local-only, opt-in skill telemetry that produces a retire-list signal while making it provably impossible to phone home — turning "telemetry" into a trust asset
**Mode:** mvp
**Depends on**: Phase 6
**Requirements**: TLMY-01, TLMY-02, TLMY-03, TLMY-04, TLMY-05
**Success Criteria** (what must be TRUE):
  1. Skill-firing telemetry is off by default, opt-in, and PII-free; it honors the `DO_NOT_TRACK` convention
  2. The hook writes an append-only JSONL log the user owns under the *target* project's `.claude/telemetry/` with zero network egress
  3. A build/CI test greps all shipped hooks and fails if any emit network egress (curl/fetch/http/socket)
  4. `conjure audit` produces a skill "retire-list" (skills with 0 loads across recent sessions) folded from the local event log
  5. `TELEMETRY.md` documenting the schema ships in the same change as the hook
**Plans**: 3 plans

Plans:
**Wave 1** *(foundation — no dependencies)*
- [x] 07-01-PLAN.md — Create skill-telemetry.mjs hook (PreToolUse/Skill + UserPromptExpansion), TELEMETRY.md schema doc, settings.json.tmpl wiring, .gitignore.tmpl entry (TLMY-01, TLMY-02, TLMY-05)

**Wave 2** *(blocked on Wave 1)*
- [x] 07-02-PLAN.md — Add --retire-list flag to cli/conjure cmd_audit(), implement retire-list jq aggregation section in audit-setup.sh with date portability (TLMY-04)

**Wave 3** *(blocked on Wave 1 and Wave 2)*
- [x] 07-03-PLAN.md — Extend tests/run.sh with telemetry test section covering TLMY-01 through TLMY-05 (no-egress grep, JSONL write with mock stdin, retire-list render) (TLMY-01, TLMY-02, TLMY-03, TLMY-04, TLMY-05)

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → 4 → 5 → 6 → 7

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Pre-flight & Cross-Platform Hooks | 2/2 | Complete    | 2026-05-24 |
| 2. Dry-Run Enforcement Chokepoint | 6/6 | Complete    | 2026-05-24 |
| 3. Sandboxed Per-Profile Fixtures | 3/3 | Complete    | 2026-05-24 |
| 4. Regression Suite & Dry-Run Proof | 3/3 | Complete    | 2026-05-25 |
| 5. README Demo | 2/2 | Complete    | 2026-05-25 |
| 6. Cost Estimator | 3/3 | Complete    | 2026-05-25 |
| 7. Skill-Firing Telemetry | 3/3 | Complete   | 2026-05-25 |
