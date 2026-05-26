# Conjure

## What This Is

Conjure is the missing init kit for Claude Code — it scaffolds the four-layer
harness Anthropic recommends (`CLAUDE.md` + lazy-loaded **Skills** + isolated
**Subagents** + deterministic **Hooks**) in one command, for both new and
existing repos. It ships safe migrations, 9 stack profiles, 4 compliance
overlays, knowledge-graph integration, an auditable CLI, 3-way merge for
keeping harnesses up-to-date, org overlay support, and is installable via
Homebrew, Docker, and Claude Code Marketplace. An open-source developer tool
aimed at teams doing high-stakes work where prompt-adherence and reproducibility
matter.

## Core Value

A developer can turn any repo into a production-grade, eval-backed Claude Code
harness with one trustworthy command — and keep it healthy over time. If
everything else fails, `conjure init` + `conjure audit` must reliably produce
and verify a correct, safe harness.

## Current Milestone: v0.5.0 Auto-Update + Healthcheck

**Goal:** Enable harnesses to stay current — detect drift from upstream, resolve conflicts interactively, and automate updates via PR.

**Target features:**
- `conjure check` — drift detection command (installed harness vs upstream kit, delta report)
- `conjure update --pr` — open GitHub PR with harness update diff; optional GH Action cron template
- `conjure resolve` — guided prompt walking through diff3 conflict sidecars interactively
- `conjure.ps1` — native PowerShell entrypoint for Windows (no Git Bash required)
- ci-gate empty-check guard (tech debt: fail CI on zero check-runs for tagged commits)
- SKILL-04 positional arg refactor (tech debt: replace `TARGET_REPO` env with positional arg)

## Requirements

### Validated

<!-- Requirements shipped and confirmed across all completed milestones. -->

- ✓ Four-layer harness scaffold (CLAUDE.md + 17 skill templates + 6 subagents + 5 hooks) — v0.1.0
- ✓ Unified CLI (`conjure init|migrate|audit|update|refresh-graph|install-mcp`) — v0.2.0
- ✓ 6 migration paths (from-claude/cursor/aider/continue/copilot/windsurf) with backup-before-mutate — v0.2.0
- ✓ 9 stack profiles — v0.2.0
- ✓ 4 compliance overlays (HIPAA, SOC 2, GDPR, PCI) — v0.2.0
- ✓ Plugin manifest (`.claude-plugin/`) — v0.2.0
- ✓ JSON schemas for skill/agent frontmatter — v0.2.0
- ✓ Per-project version pinning (`.claude/.conjure-version`) — v0.2.0
- ✓ Audit with size caps, schema validation, anti-pattern detection — v0.2.0
- ✓ 112+ self-tests, all green; CI on every PR — v0.2.0
- ✓ Reference docs + FAILURE-MODES.md + MIGRATION-GUIDE.md — v0.1.0/v0.2.0
- ✓ VALIDATION.md with executable verify blocks for phases 01, 02, 04, 05, 06, 07 (TECH-02a–f) — v0.4.0
- ✓ `conjure update --apply` 3-way merge via `git merge-file --diff3`; conflict sidecars; base snapshot at init (MERGE-01–05) — v0.4.0
- ✓ `conjure publish` + Marketplace CI validation + `claude plugin validate` in CI (MKTPL-01–04) — v0.4.0
- ✓ `conjure publish-skill` with 4-gate validation + PR flow (SKILL-01–04) — v0.4.0
- ✓ Org overlay: `conjure init --overlay` + `conjure refresh-overlay` + audit drift (OVLY-01–05) — v0.4.0
- ✓ Homebrew formula + auto-bump-action on release (BREW-01–04) — v0.4.0
- ✓ Multi-arch Docker image (linux/amd64 + linux/arm64, non-root, ≤200 MB) + windows-test CI job (DOCK-01–05, TECH-03) — v0.4.0
- ✓ 4-job release.yml: ci-gate → release → docker + homebrew parallel (REL-01–02) — v0.4.0

### Active

<!-- Requirements for v0.5.0 — hypotheses until shipped and validated. -->

- [ ] **DRIFT-01**: User can run `conjure check` to see which installed harness files diverge from the upstream kit
- [ ] **DRIFT-02**: Drift report shows file-level deltas (added/modified/removed) with actionable next step
- [ ] **AUTPR-01**: User can run `conjure update --pr` to open a GitHub PR with harness update diff
- [ ] **AUTPR-02**: Optional GitHub Action template ships for cron-based auto-PR automation
- [ ] **RESOLVE-01**: User can run `conjure resolve` to walk through diff3 conflict sidecars interactively via guided prompt
- [ ] **RESOLVE-02**: `conjure resolve` marks sidecars resolved and cleans them up after confirmation
- [ ] **WIN-01**: `conjure.ps1` PowerShell entrypoint works on native Windows without Git Bash
- [ ] **WIN-02**: CI matrix includes native PowerShell job (windows-latest, shell: pwsh)
- [ ] **DEBT-01**: ci-gate fails when tagged commit has zero GitHub check-runs (empty-check guard)
- [ ] **DEBT-02**: `conjure publish-skill` accepts positional arg for target repo (replaces `TARGET_REPO` env)

### Out of Scope

<!-- Explicit boundaries with reasoning. -->

- Auto-update 3-way merge conflict resolution UI — conflicts surfaced as sidecar files; interactive resolution is v0.5.0
- Workspace / cross-repo graph orchestration — v0.6.0; single-repo correctness first
- IDE extensions, web dashboard, skill marketplace UI — backlog; not core to the one-command value
- Making a project *actually* compliant — overlays reduce non-compliant output only; real compliance needs people + process + audit
- PowerShell `conjure.ps1` entrypoint for native Windows — v0.5.0; Git Bash works for now
- `conjure:full` Docker tag with optional Go/Rust tools — v0.4.x; baseline image is the priority

## Current State

**Shipped:** v0.4.0 — "Distribution + Ecosystem" (2026-05-26)

- 29/29 requirements satisfied across 9 phases, 23 plans
- `conjure update --apply` uses real 3-way merge (git merge-file --diff3)
- `conjure publish` + `conjure publish-skill` wired and regression-tested
- Org overlay system (init + refresh + audit drift detection)
- Homebrew formula + release pipeline: ci-gate → GH release → Docker + Homebrew
- Multi-arch Docker image (linux/amd64 + linux/arm64, debian:bookworm-slim, non-root)
- Windows CI job (windows-latest, shell: bash)
- 261+ test assertions, all green
- Pre-release checklist items remain (tap repo setup, live tag push, HOMEBREW_TAP_GITHUB_TOKEN secret)

**Previous:** v0.3.0 — "Testing + Telemetry" (2026-05-25) — 7 phases, 22 plans

## Constraints

- **Tech stack**: POSIX bash + Node.js `.mjs` for hooks — must stay cross-platform; no hard dependency on heavy runtimes.
- **Safety**: backup-before-mutate on every change; no `curl | sh` foot-guns inside the kit; hooks must `exit 2` (never `exit 1`).
- **Size caps**: CLAUDE.md ≤100 lines, SKILL.md ≤200, agent ≤80 — enforced by audit/CI.
- **Compatibility**: requires Claude Code ≥2.1.117; `@imports` forbidden in CLAUDE.md (eager-load foot-gun).
- **Quality gate**: every PR must pass shellcheck, JSON Schema validation, frontmatter validation, size caps, and migration/profile/compliance coverage checks.

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Scope first GSD milestone to v0.3.0 (Testing + telemetry) | Quality/trust precede distribution | Shipped 2026-05-25 |
| Defer distribution to v0.4.0 | "Production ready" depends on test fixtures + audit confidence | Shipped 2026-05-26 |
| Adopt formal GSD `.planning/` alongside existing `planning/` docs | Real plan→execute→verify rigor | In use throughout v0.3.0/v0.4.0 |
| All writes funnel through `lib/mutate.sh` | Dry-run enforced once, not per call site | Validated Phase 2 |
| `node .mjs` hooks universally in settings template | No OS branching — cross-platform by design | Validated Phase 1 |
| Telemetry: local-only, opt-in, PII-free, no-egress CI-enforced | Trust asset, not a liability | Validated Phase 7 |
| Docker base: debian:bookworm-slim (not Alpine) | musl libc breaks optional Go/Rust tools | v0.4.0 Phase 14 |
| Homebrew: separate `mohandoz/homebrew-conjure` tap repo | Standard tap pattern; formula pinned to tagged tarball SHA256 only | v0.4.0 Phase 13 |
| release.yml: 4-job structure (ci-gate → release → docker + homebrew parallel) | Docker failure must not block Homebrew and vice versa | v0.4.0 Phase 15.1 |
| `--to <org/repo>` for publish-skill uses TARGET_REPO env (fragile) | Positional arg refactor deferred; functional for v0.4.0 | Tech debt, v0.5.0 |

## Evolution

This document evolves at phase transitions and milestone boundaries.

---
*Last updated: 2026-05-26 — v0.5.0 milestone started — Auto-Update + Healthcheck*
