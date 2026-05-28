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

## Current Milestone: v0.6.0 Safe Brownfield Adoption

**Goal:** Let `conjure` safely fold an existing, grown-messy project (oversized
CLAUDE.md, scattered docs, prior GSD `.planning/`) into a best-practice
four-layer harness — losing nothing, backing up everything, reporting each change.

**Target features:**
- `conjure adopt` (deterministic CLI): full timestamped snapshot backup, inventory + classify every markdown file, scaffold missing harness layers, size-cap audit, safe mutate via `lib/mutate.sh`, per-step `RESTRUCTURE-LOG.md`, `--dry-run`, `--rollback`.
- `restructure` skill (Claude in-session): reads CLI inventory + oversized CLAUDE.md + doc sprawl → proposes ≤100-line CLAUDE.md core, what extracts to skills/subagents, what stays linked reference, what is stale → archive. Approve each step; applies via CLI safe primitives.
- Safety primitives: snapshot-backup mutate primitive, git-clean precondition (refuse dirty tree without `--force`), never-delete (archive instead), live per-step messaging + persisted log, rollback.

**Approach:** Brownfield-only — cross-repo orchestration deferred to v0.7.0.
Hybrid determinism: file operations deterministic + auditable; content judgment
is LLM, human-gated and backup-guarded.

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
- ✓ `conjure check` drift detection — 3-way sha256 classifier, `--porcelain`, exit 0/1 (DRIFT-01–02) — v0.5.0
- ✓ `conjure resolve` interactive diff3 sidecar walker — TTY-guarded (exit 2), mutate_rm cleanup (RESOLVE-01–02) — v0.5.0
- ✓ `conjure update --pr` + `--cron` — idempotent auto-PR + weekly workflow template (AUTPR-01–02) — v0.5.0
- ✓ `conjure.ps1` native Windows entrypoint + windows-ps1-shim pwsh CI job (WIN-01–02) — v0.5.0
- ✓ `mutate_rm` deletion primitive, publish-skill positional arg, ci-gate empty-check guard (INFRA-01, DEBT-01–02) — v0.5.0

### Active

<!-- Requirements for the next milestone — defined fresh via /gsd-new-milestone. -->

_v0.6.0 "Safe Brownfield Adoption" requirements being defined via `/gsd-new-milestone` — see `.planning/REQUIREMENTS.md`._

### Out of Scope

<!-- Explicit boundaries with reasoning. -->

- Full TUI conflict resolution (side-by-side diff viewer) — `conjure resolve` ships a guided line-by-line prompt; ncurses UI deferred to v0.7.0
- `conjure update --pr` auto-merge on clean apply — never; conflicts always require human review
- Workspace / cross-repo graph orchestration — v0.7.0; safe single-repo brownfield adoption first (v0.6.0)
- IDE extensions, web dashboard, skill marketplace UI — backlog; not core to the one-command value
- Making a project *actually* compliant — overlays reduce non-compliant output only; real compliance needs people + process + audit
- Pure PowerShell port of `conjure.ps1` (no Git Bash/WSL) — v0.7.0; the shim covers native Windows for now
- Fully autonomous (no-approval) restructure of an existing project — v0.6.0 `restructure` requires per-step human approval; unattended adoption is a non-goal (judgment + safety)
- `conjure:full` Docker tag with optional Go/Rust tools — v0.4.x; baseline image is the priority

## Current State

**Shipped:** v0.5.0 — "Auto-Update + Healthcheck" (2026-05-28)

- 11/11 requirements satisfied across 5 phases, 10 plans
- Harness lifecycle loop closed: `conjure check` (drift) → `conjure resolve` (conflicts) → `conjure update --pr/--cron` (automated PRs)
- `conjure.ps1` native Windows entrypoint (Git Bash → WSL → exit 2) with exit-code propagation
- `release.yml` ci-gate hardened: empty-check guard + API-propagation retry loop
- 302 test assertions, all green; CI green on all 5 jobs (ubuntu + 4 Windows/audit jobs)
- v0.5.0 tagged and released; Homebrew formula pinned to v0.5.0 tarball sha256
- Post-close hardening: cross-platform test suite repaired (gh-isolation under usrmerge, Git Bash sandbox PATH, telemetry cwd via cygpath, pwsh exit propagation)

**Previous:** v0.4.0 — "Distribution + Ecosystem" (2026-05-26) — 9 phases, 23 plans

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
| `--to <org/repo>` for publish-skill uses TARGET_REPO env (fragile) | Positional arg refactor deferred; functional for v0.4.0 | ✓ Resolved — positional `$2`, TARGET_REPO deprecated (DEBT-02, v0.5.0) |
| `conjure check`: sha256 3-way classifier, no `git merge-file` at detection time | Read-only drift detection must be cheap and side-effect-free | ✓ Good — DRIFT-01/02, v0.5.0 |
| `conjure resolve`: guided line-by-line prompt, fd-3 stdin isolation, non-TTY → exit 2 | TUI deferred; exit-2 (not 1) matches hook convention for non-interactive | ✓ Good — RESOLVE-01/02, v0.5.0 |
| `conjure update --pr`: deterministic branch (sha256 of kit version), idempotent via `gh pr list` | Re-runs must not open duplicate PRs | ✓ Good — AUTPR-01, v0.5.0 |
| `conjure.ps1` is a shim (Git Bash → WSL → exit 2), not a PowerShell port | No subcommand logic duplicated; one source of truth | ✓ Good — WIN-01, v0.5.0 |
| Test sandbox resets PATH but must resolve git/jq/python3 dirs dynamically | Hardcoded /usr/bin drops tools on Git Bash (usrmerge, /mingw64) | ⚠️ Revisit — fixed post-close; cross-platform test hygiene needs ongoing care |

## Evolution

This document evolves at phase transitions and milestone boundaries.

---
*Last updated: 2026-05-28 — v0.6.0 milestone started — Safe Brownfield Adoption*
