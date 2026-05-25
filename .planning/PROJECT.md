# Conjure

## What This Is

Conjure is the missing init kit for Claude Code — it scaffolds the four-layer
harness Anthropic recommends (`CLAUDE.md` + lazy-loaded **Skills** + isolated
**Subagents** + deterministic **Hooks**) in one command, for both new and
existing repos. It ships safe migrations from other AI assistants, 9 stack
profiles, 4 compliance overlays, knowledge-graph integration, and an auditable
CLI. It is an open-source developer tool aimed at teams doing high-stakes work
where prompt-adherence and reproducibility matter.

## Core Value

A developer can turn any repo into a production-grade, eval-backed Claude Code
harness with one trustworthy command — and keep it healthy over time. If
everything else fails, `conjure init` + `conjure audit` must reliably produce
and verify a correct, safe harness.

## Requirements

### Validated

<!-- Shipped in v0.1.0 / v0.2.0 (per planning/ROADMAP.md + working tree). -->

- ✓ Four-layer harness scaffold (CLAUDE.md + 17 skill templates + 6 subagents + 5 hooks) — v0.1.0
- ✓ Unified CLI (`conjure init|migrate|audit|update|refresh-graph|install-mcp`) — v0.2.0
- ✓ 6 migration paths (from-claude/cursor/aider/continue/copilot/windsurf) with backup-before-mutate — v0.2.0
- ✓ 9 stack profiles (java-spring, python-fastapi, ts-next, rust-axum, go-gin, node-nest, monorepo, polyglot, data-science) — v0.2.0
- ✓ 4 compliance overlays (HIPAA, SOC 2, GDPR, PCI) — v0.2.0
- ✓ Plugin manifest (`.claude-plugin/`) — v0.2.0
- ✓ JSON schemas for skill/agent frontmatter (IDE-validated) — v0.2.0
- ✓ Per-project version pinning (`.claude/.conjure-version`) — v0.2.0
- ✓ Audit with size caps, schema validation, anti-pattern detection — v0.2.0
- ✓ 112 self-tests, all green; CI on every PR — v0.2.0
- ✓ Reference docs (best practices, tools, MCP, anti-patterns, sizing, compaction, prompting) — v0.1.0
- ✓ FAILURE-MODES.md + MIGRATION-GUIDE.md + checklists — v0.2.0

### Active

<!-- Current milestone: v0.4.0 — Distribution + Ecosystem. Hypotheses until shipped + validated. -->

- [ ] DIST-01: Publish to Claude Code Marketplace via `.claude-plugin/marketplace.json`
- [ ] DIST-02: Homebrew formula (`brew install conjure`)
- [ ] DIST-03: Docker image with all tools preinstalled
- [ ] DIST-04: `conjure publish-skill <name>` — contribute project skill to public kit
- [ ] DIST-05: Org overlay system (base kit + private overlay repo per org)
- [ ] TECH-01: `cmd_update --apply` 3-way merge implementation (stub at `cli/conjure:171`)
- [ ] TECH-02: Nyquist compliance pass for phases 01, 02, 04, 05, 06, 07
- [ ] TECH-03: Windows CI runtime confirmation for TEST-06

### Out of Scope

<!-- Explicit boundaries with reasoning. -->

- Distribution / ecosystem (Marketplace publish, Homebrew, Docker, `publish-skill`) — deferred to v0.4.0 milestone; quality + trust come before reach
- Auto-update 3-way merge, drift detector, auto-PR bot — v0.5.0; needs stable schemas first
- Workspace / cross-repo graph orchestration — v0.6.0; single-repo correctness first
- IDE extensions, web dashboard, skill marketplace UI — backlog; not core to the one-command value
- Making a project *actually* compliant — overlays reduce non-compliant output only; real compliance needs people + process + audit

## Context

- **Existing mature codebase.** Bash CLI (`cli/conjure`), shell scripts under `scripts/`, profiles, compliance overlays, templates, migrations, and a 112-test suite already exist. Current version: 0.2.1.
- **Self-hosting dev model.** Conjure is developed GSD-style; an informal `planning/ROADMAP.md` (no dot) and `planning/GSD-INTEGRATION.md` already exist. This task formalizes the real GSD `.planning/` structure (with dot) for ongoing work.
- **Eval-backed design philosophy.** Caps and patterns derive from Anthropic eval data, a 2,455-eval community study, and ETH Zurich context-size research. Core principle: less context = better adherence.
- **Cross-platform target.** Node.js `.mjs` hooks on all platforms (Windows, macOS, Linux) — bash hooks retired in Phase 01 (SAFE-03).
- **Community/OSS goal.** MIT-licensed; aims for production teams adopting it and GitHub stars. Adoption depends first on trust (tests, audit, safety), then reach (distribution).

## Constraints

- **Tech stack**: POSIX bash + Node.js `.mjs` for hooks — must stay cross-platform; no hard dependency on heavy runtimes.
- **Safety**: backup-before-mutate on every change; no `curl | sh` foot-guns inside the kit; hooks must `exit 2` (never `exit 1`).
- **Size caps**: CLAUDE.md ≤100 lines, SKILL.md ≤200, agent ≤80 — enforced by audit/CI.
- **Compatibility**: requires Claude Code ≥2.1.117; `@imports` forbidden in CLAUDE.md (eager-load foot-gun).
- **Quality gate**: every PR must pass shellcheck, JSON Schema validation, frontmatter validation, size caps, and migration/profile/compliance coverage checks.

## Current Milestone: v0.4.0 Distribution + Ecosystem

**Goal:** Make Conjure installable and shareable through every standard channel while clearing v0.3.0 tech debt that blocks production use.

**Target features:**
- DIST-01: Claude Code Marketplace publish
- DIST-02: Homebrew formula
- DIST-03: Docker image
- DIST-04: `conjure publish-skill` command
- DIST-05: Org overlay system
- TECH-01: `cmd_update --apply` 3-way merge
- TECH-02: Nyquist compliance pass (phases 01, 02, 04, 05, 06, 07)
- TECH-03: Windows CI runtime confirmation

## Current State

**Shipped:** v0.3.0 — "Testing + Telemetry" (2026-05-25)

- 200 test assertions, all green (`bash tests/run.sh`)
- 9 sandboxed per-profile fixtures committed (`tests/fixtures/`)
- `--dry-run` enforced at `lib/mutate.sh` chokepoint (zero mutations verified)
- `node .mjs` hook wiring on all platforms including native Windows
- `conjure audit --cost` offline cost estimator with per-skill breakdown
- Local-only opt-in skill telemetry with CI-enforced no-egress guarantee
- README animated GIF demo (314KB, Quickstart section)

**Next milestone:** v0.4.0 — Distribution + Ecosystem (not yet started — run `/gsd-new-milestone`)

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Scope first GSD milestone to v0.3.0 (Testing + telemetry) | Quality/trust precede distribution; matches committed next version in planning/ROADMAP.md | Shipped 2026-05-25 |
| Defer distribution (v0.4.0) to a later milestone | "Production ready" depends on test fixtures + audit confidence before chasing stars | Confirmed — v0.4.0 is next |
| Adopt formal GSD `.planning/` alongside existing `planning/` docs | Real plan→execute→verify rigor for continued dev | In use throughout v0.3.0 |
| All writes funnel through `lib/mutate.sh` | Dry-run enforced once, not per call site | Validated Phase 2 |
| `node .mjs` hooks universally in settings template | No OS branching, no shell arg expansion — cross-platform by design | Validated Phase 1 |
| Telemetry: local-only, opt-in, PII-free, no-egress CI-enforced | Trust asset, not a liability; contradicts compliance overlays otherwise | Validated Phase 7 |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd-transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd:complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-05-25 — v0.4.0 milestone started*
