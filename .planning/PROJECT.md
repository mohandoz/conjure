# Conjure

## What This Is

Conjure is the missing init kit for Claude Code — it scaffolds the four-layer
harness Anthropic recommends (`CLAUDE.md` + lazy-loaded **Skills** + isolated
**Subagents** + deterministic **Hooks**) in one command, for both new and
existing repos. It ships safe migrations, 9 stack profiles, 4 compliance
overlays that emit deployable security policy (sandbox + managed-settings +
MDM), plugin/marketplace emission on Claude Code's native rail, a
schema-version-aware audit with machine-readable output, a promptfoo-based
prompt-adherence eval suite, multi-repo workspace orchestration with a
SIGKILL-durable rollback saga, knowledge-graph integration, 3-way merge
updates, org overlays, and is installable via Homebrew, Docker, and Claude
Code Marketplace. An open-source developer tool aimed at teams doing
high-stakes work where prompt-adherence and reproducibility matter.

## Core Value

A developer can turn any repo into a production-grade, eval-backed Claude Code
harness with one trustworthy command — and keep it healthy over time. If
everything else fails, `conjure init` + `conjure audit` must reliably produce
and verify a correct, safe harness.

## Current Milestone: v0.8.0 Operability + DX

**Goal:** Close v0.7.0's deferred debt, give operators visibility (`doctor`, `stats`), deepen eval coverage, polish init UX, and ship user-facing docs that match what Conjure actually does.

**Target features:**
- Deferred debt — automate live-system UAT where possible (real `claude` binary smoke, live promptfoo run gated on key), document manual steps (MDM hardware); test-harness hardening (`git -C "$VAR"` empty-var guard, kill-safe SCHM-STALE swap)
- `conjure doctor` — preflight diagnostics: `command -v` table + mirrored `.mjs` probe, OS-detected install hints
- Telemetry insights (`conjure stats`) — read skill-firing JSONL, fire/never-fire report, dead-skill detection, chars/4 cost estimates
- Eval suite expansion — per-profile adherence suites, regression baselines beyond scaffold
- Init UX polish — wizard improvements, better profile selection, smarter defaults detection
- README + docs refresh — rewrite README covering v0.3–v0.7 (quick start, command reference, feature tour); sync MIGRATION-GUIDE + FAILURE-MODES

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
- ✓ Foundation libs — `lib/log.sh`/`snapshot.sh`/`inventory.sh`/`caps.sh` + `mutate_archive`, 6-bucket classifier, 500-file cap, finalized `adopt-manifest.json` schema (INV-01–04, SAFE-03, ADOPT-03) — v0.6.0
- ✓ `conjure adopt` CLI — 5-step pipeline, `--dry-run` zero-writes, `--rollback` sha256 zero-diff, partial-run recovery, op-executor seam (ADOPT-01/02/04/05/06, SAFE-01/02/04/05/06/07) — v0.6.0
- ✓ Human-gated `restructure` skill — `[Read, Bash]`-only, pre-write invariant + audit gates (RESTR-01–06) — v0.6.0
- ✓ E2E verification — 500-file `_brownfield-argus` fixture + integration tests; suite 449/0 — v0.6.0
- ✓ `conjure publish-plugin` — plugin.json + marketplace.json emission, merge-preserve, greenfield name derivation, reserved-name guard, `--validate` gate, secret-scan, settings wiring (PLUG-01–05) — v0.7.0
- ✓ `conjure emit-policy` — per-regime sandbox{} merged into settings.json with 1:1 `Read()` deny mirror, managed-settings.json (string `disableBypassPermissionsMode`), macOS plist + Windows PS1 MDM bundle, audit policy flags (POL-01–05) — v0.7.0
- ✓ Schema-version-aware audit — bundled `lib/cc-schema.json` (30 hook events, 16 SKILL.md fields), frontmatter/type/hook-event validation, `check --schema` version report, `audit --json` machine output (SCHM-01–05) — v0.7.0
- ✓ `conjure eval` — promptfoo scaffold (claude-agent-sdk provider, pinned 0.121.14), Node-gated run, PR-gate workflow emission, `audit --budget` context linter, eval-coverage gap report (EVAL-01–05) — v0.7.0
- ✓ Workspace orchestration — `.conjure-workspace.json` manifest with traversal-guarded validation, `workspace init/check/audit` read-only aggregation, `workspace update/adopt/--rollback` snapshot-all-first saga with SIGKILL-durable state + per-repo sha256 zero-diff rollback (WS-01–07) — v0.7.0

### Active

<!-- Requirements for the next milestone — defined fresh via /gsd-new-milestone. -->

_v0.8.0 "Operability + DX" in definition — requirements being scoped via `/gsd-new-milestone`._

### Out of Scope

<!-- Explicit boundaries with reasoning. -->

- Full TUI conflict resolution (side-by-side diff viewer) — `conjure resolve` ships a guided line-by-line prompt; ncurses UI deferred
- `conjure update --pr` auto-merge on clean apply — never; conflicts always require human review
- IDE extensions, web dashboard, skill marketplace UI — backlog; not core to the one-command value
- Making a project *actually* compliant — overlays reduce non-compliant output only; real compliance needs people + process + audit
- Pure PowerShell port of `conjure.ps1` (no Git Bash/WSL) — the shim covers native Windows for now
- Fully autonomous (no-approval) restructure of an existing project — unattended adoption is a non-goal (judgment + safety)
- Auto-deploy MDM artifacts via Jamf/Intune APIs — Conjure generates artifacts + documents deploy; never handles MDM credentials
- Bundling promptfoo as a dependency — `dependencies: {}` stays empty; pinned `npx` shell-out only
- Runtime-fetching the CC schema — zero-egress; `lib/cc-schema.json` bundled, updated per Conjure release
- Parallel per-repo workspace apply — the saga stays serial by design (deterministic, stop-on-fail)
- `conjure:full` Docker tag with optional Go/Rust tools — baseline image is the priority

## Current State

**Shipped:** v0.7.0 — "Plugin-native + Policy-grade" (2026-06-04)

- 27/27 requirements satisfied across 6 phases (25–30), 24 plans; milestone audit: 8/8 cross-phase integration wires verified, status tech_debt (no blockers)
- Conjure now rides Claude Code's native rails end-to-end: harness → versioned plugin + marketplace (`publish-plugin`), compliance overlay → deployable policy (`emit-policy`: sandbox + managed-settings + MDM), audit → schema-version-aware with `--json` machine output, eval-backed via promptfoo (`conjure eval`), and multi-repo via `conjure workspace` (read-only aggregation + mutating saga with SIGKILL-proof rollback)
- Suite 579/0 at close; shellcheck-clean; `dependencies: {}` still empty; CLAUDE.md 84/100 lines
- Every phase ran a code-review→fix→re-review loop to clean — notable catches: exit-1 + missing-backup blockers (25), secret-scan exit-code regression (26), EXIT-trap clobbers (27), YAML-injection (28), path-traversal boundary off-by-one-level (29), pkill over-match + orphaned-subprocess SIGKILL root cause (30)
- Deferred (tracked in v0.7.0-MILESTONE-AUDIT.md + STATE.md): 4 live-system HUMAN-UAT items (real `claude` binary, managed-settings deploy, MDM hardware, live promptfoo enforcement); test-harness hardening (guard `git -C "$VAR"` against empty vars after mktemp failure — proven sandbox-escape vector; kill-safe SCHM-STALE swap)

**Previous:** v0.6.0 — "Safe Brownfield Adoption" (2026-05-29)

- 23/23 requirements across 4 phases; `conjure adopt` + human-gated `restructure` skill; E2E against 500-file fixture; suite 449/0

**Previous:** v0.5.0 — "Auto-Update + Healthcheck" (2026-05-28) — 5 phases, 10 plans
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
| All writes funnel through `lib/mutate.sh` | Dry-run enforced once, not per call site | Validated Phase 2 |
| `node .mjs` hooks universally in settings template | No OS branching — cross-platform by design | Validated Phase 1 |
| Telemetry: local-only, opt-in, PII-free, no-egress CI-enforced | Trust asset, not a liability | Validated Phase 7 |
| Docker base: debian:bookworm-slim (not Alpine) | musl libc breaks optional Go/Rust tools | v0.4.0 Phase 14 |
| `conjure check`: sha256 3-way classifier, no `git merge-file` at detection time | Read-only drift detection must be cheap and side-effect-free | ✓ Good — v0.5.0 |
| `conjure.ps1` is a shim (Git Bash → WSL → exit 2), not a PowerShell port | One source of truth | ✓ Good — v0.5.0 |
| Split responsibility: CLI owns ALL filesystem mutations; skills own LLM judgment (`[Read, Bash]`) | Determinism + auditability | ✓ Good — v0.6.0, reused by v0.7.0 |
| `snapshot_create` raw `cp`/`tar`, excludes `.git`/`node_modules` | The safety primitive must precede dry-run suppression | ✓ Good — v0.6.0; extended with conjure-dir tar excludes v0.7.0 |
| Audit advisory checks use `note()` (exit 0), real bugs use `err()` (exit 2) — never `warn()` for advisories | `warn()` increments WARN and flips audit exit 1, breaking CI on advisory items | ✓ Good — discovered Phase 25, enforced 26–30 |
| `disableBypassPermissionsMode` emitted/validated as STRING `"disable"`, both JSON paths checked | Boolean form is silently ignored by Claude Code — a real security hole | ✓ Good — POL/SCHM, v0.7.0 |
| jq array merges use `(a//[])+(b//[])\|unique`, never `.*` | `.*` replaces arrays — re-runs would delete operator-added deny entries | ✓ Good — Phase 26 |
| One combined EXIT-trap cleanup function per script | bash has one EXIT slot; re-registering silently clobbers prior cleanup (leaked tempfiles) | ✓ Good — Phase 27 lesson, enforced 28–30 |
| promptfoo provider: `anthropic:claude-agent-sdk` (not exec/`claude -p`) | Only the SDK provider supplies `metadata.skillCalls` for the built-in `skill-used` assertion | ✓ Good — Phase 28 research |
| Per-repo subprocess flags passed as argv (`--json`, `--porcelain`), never env-only | Workers re-init flag vars from argv, silently overriding inherited env | ✓ Good — Phase 29 plan-checker catch |
| Workspace path-boundary checked at validate-time AND execution-time (incl. rollback) | Validate-only guards let a crafted manifest execute against out-of-bounds dirs | ✓ Good — Phase 29 CR-02, applied to saga in 30 |
| Workspace saga: snapshot ALL before applying ANY; `snapshotting→snapshotted` sentinel; atomic `jq>tmp+mv` state | SIGKILL at any point leaves a restorable, truthful state file | ✓ Good — Phase 30, SIGKILL zero-diff proof green |
| Rollback kills orphaned adopt subprocesses (anchored pkill) + double deletion pass | SIGKILL of the orchestrator does NOT kill children; orphans kept writing during rollback (flake root cause) | ✓ Good — Phase 30 debug cycle |
| Test sandboxes: `git -C "$VAR"` needs non-empty guard after mktemp | A failed mktemp leaves the var empty; `git -C ""` operates on the REAL repo (proven escape) | ⚠️ Revisit — hardening tracked in v0.7.0 audit tech debt |

## Evolution

This document evolves at phase transitions and milestone boundaries.

---
*Last updated: 2026-06-04 — v0.8.0 "Operability + DX" milestone started*
