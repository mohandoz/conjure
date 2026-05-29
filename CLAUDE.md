<!-- GSD:project-start source:PROJECT.md -->
## Project

**Conjure** — the missing init kit for Claude Code. Scaffolds the four-layer
harness (`CLAUDE.md` + lazy **Skills** + isolated **Subagents** + deterministic
**Hooks**) in one command, for new and existing repos. Ships safe migrations, 9
stack profiles, 4 compliance overlays, graph integration, and an auditable CLI.
Open-source tool for teams where prompt-adherence and reproducibility matter.

**Core Value:** Turn any repo into a production-grade, eval-backed Claude Code
harness with one trustworthy command — and keep it healthy. If all else fails,
`conjure init` + `conjure audit` must reliably produce and verify a safe harness.

### Constraints

- **Tech stack**: POSIX bash + Node.js `.mjs` hooks — stay cross-platform; no heavy runtime deps.
- **Safety**: backup-before-mutate on every change; no `curl | sh` foot-guns; hooks `exit 2` (never `exit 1`).
- **Size caps**: CLAUDE.md ≤100 lines, SKILL.md ≤200, agent ≤80 — enforced by audit/CI.
- **Compatibility**: Claude Code ≥2.1.117; `@imports` forbidden in CLAUDE.md (eager-load foot-gun).
- **Quality gate**: every PR passes shellcheck, JSON Schema, frontmatter, size caps, and coverage checks.
<!-- GSD:project-end -->

<!-- GSD:stack-start source:research/STACK.md -->
## Technology Stack

Shipped through **v0.6.0 — Safe Brownfield Adoption** (`conjure adopt` + the
human-gated `restructure` skill). Foundational stack decisions below still hold;
full detail in `.planning/research/STACK.md` (do not inline — it breaches the cap).

| Decision | Pick |
|----------|------|
| Fixture regression testing | Extend hand-rolled `tests/run.sh`; `bats-core` only at unit level. No shellspec, no npm test deps. |
| Skill-firing telemetry | Append-only JSONL via `PreToolUse`(`Skill`) + `InstructionsLoaded` hooks. Local-only, no service. |
| Cost estimator | chars/4 heuristic × dated price table baked into `conjure`. No bundled tokenizer; `--exact` opt-in only. |
| Cross-platform preflight | `command -v` table (bash) + mirrored `.mjs` probe; OS-detected install hints. |

Runtime envelope: bash + stdlib-`.mjs` + `jq` + `shellcheck`. Keep `dependencies: {}` empty.
<!-- GSD:stack-end -->

<!-- GSD:conventions-start source:CONVENTIONS.md -->
## Conventions

- All target-repo mutations route through `lib/mutate.sh` (dry-run enforced once); `snapshot_create` is the blessed raw-`cp`/`tar` exception (excludes `.git`/`node_modules`).
- Hooks/CLI/scripts `exit 2`, never `exit 1`. Interactive prompts read `/dev/tty`; non-TTY → exit 2, never auto-mutate.
- Split responsibility: the CLI owns all filesystem mutations; skills own LLM judgment and stay `[Read, Bash]` (mutate only via `conjure adopt --update-manifest`/`--apply-step`).
- Test-first: a graceful-red `tests/run.sh` block lands before each feature; `_`-prefixed `tests/fixtures/` dirs are excluded from the generic audit/golden loops.
- POSIX bash 3.2+ (no associative arrays / `mapfile` / `local -n`); inline `# shellcheck` directives; CI gate `shellcheck -S error -e SC2164,SC2044,SC2034,SC2155`. Interactive `/dev/tty` UX verified via `expect`/PTY.
<!-- GSD:conventions-end -->

<!-- GSD:architecture-start source:ARCHITECTURE.md -->
## Architecture

Entrypoint `cli/conjure`; workers in `scripts/` (adopt, init-project, audit-setup,
resolve, …); shared libs in `lib/` (mutate, snapshot, inventory, log, caps).
Profiles in `profiles/`, overlays in `compliance/`, skill templates in
`templates/skills/` (incl. `restructure/` + its `gates/`), fixtures in `tests/fixtures/`.
See `.planning/research/ARCHITECTURE.md` for component boundaries and build order.
<!-- GSD:architecture-end -->

<!-- GSD:skills-start source:skills/ -->
## Project Skills

No project skills found. Add skills under `.claude/skills/` with a `SKILL.md` index.
<!-- GSD:skills-end -->

<!-- GSD:workflow-start source:GSD defaults -->
## GSD Workflow Enforcement

Before using Edit, Write, or other file-changing tools, start work through a GSD command so planning artifacts and execution context stay in sync.

Use these entry points:
- `/gsd-quick` for small fixes, doc updates, and ad-hoc tasks
- `/gsd-debug` for investigation and bug fixing
- `/gsd-execute-phase` for planned phase work

Do not make direct repo edits outside a GSD workflow unless the user explicitly asks to bypass it.
<!-- GSD:workflow-end -->

<!-- GSD:profile-start -->
## Developer Profile

> Profile not yet configured. Run `/gsd-profile-user` to generate your developer profile.
> This section is managed by `generate-claude-profile` -- do not edit manually.
<!-- GSD:profile-end -->
