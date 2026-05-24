<div align="center">

# 🪴 Conjure

### The production-grade Claude Code harness kit

*A lattice that supports growth without dictating shape.*

[![License: MIT](https://img.shields.io/github/license/mohandoz/conjure?color=yellow)](LICENSE)
[![Release](https://img.shields.io/github/v/release/mohandoz/conjure?sort=semver&color=blue)](https://github.com/mohandoz/conjure/releases)
[![CI](https://img.shields.io/github/actions/workflow/status/mohandoz/conjure/ci.yml?branch=main&label=CI)](https://github.com/mohandoz/conjure/actions/workflows/ci.yml)
[![Tests](https://img.shields.io/badge/tests-112%20passing-brightgreen.svg)](tests/run.sh)
[![Claude Code](https://img.shields.io/badge/Claude%20Code-%E2%89%A52.1.117-purple.svg)](https://code.claude.com/)
[![Stars](https://img.shields.io/github/stars/mohandoz/conjure?style=social)](https://github.com/mohandoz/conjure/stargazers)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](CONTRIBUTING.md)

[Quickstart](#-quickstart) •
[Why Conjure?](#-why-conjure) •
[Features](#-features) •
[Stack profiles](#-stack-profiles) •
[Compliance](#-compliance-overlays) •
[Migration](#-migration-from-other-tools) •
[Docs](#-documentation) •
[Compare](COMPARISON.md)

</div>

---

## What is Conjure?

Conjure is **the missing init kit for Claude Code**. It sets up the
four-layer harness Anthropic recommends — `CLAUDE.md` + lazy-loaded
**Skills** + isolated **Subagents** + deterministic **Hooks** — and ships
with safe migrations from every other AI assistant, 9 stack profiles, 4
compliance overlays, persistent knowledge-graph integration, and a CLI
that makes it all one command.

Built for high-stakes work where adherence matters. People-lives-depend-on-it
defaults: backup-before-mutate everywhere, size caps enforced, no `curl | sh`
foot-guns, cross-platform Node.js hooks.

> **The problem**: most CLAUDE.md setups fail the same way — a 500-line
> monolith that Claude ignores after the first hundred lines. Conjure
> enforces the ≤100-line cap, splits content into lazy-loaded skills, and
> promotes non-negotiables to deterministic hooks.

## ✨ Why Conjure?

- 🪴 **Four-layer harness** — CLAUDE.md (advisory) + Skills (lazy) + Subagents (isolated) + Hooks (deterministic). Each layer does what it's best at.
- 🧠 **Knowledge-graph aware** — first-class graphify integration. Persistent codebase knowledge that survives sessions.
- 🛡 **Safe migrations** — backup-before-mutate from Cursor, Aider, Continue, GitHub Copilot, Windsurf, and existing `.claude/` configs.
- 🎯 **9 stack profiles** — Java-Spring, Python-FastAPI, TS-Next, Rust-Axum, Go-Gin, Node-Nest, Monorepo, Polyglot, Data Science.
- 🔒 **4 compliance overlays** — HIPAA (with PHI scan hook), SOC 2, GDPR, PCI.
- 🧪 **112 self-tests, all green** — change confidently; CI runs on every PR.
- 🌍 **Cross-platform** — bash hooks for POSIX, Node.js `.mjs` hooks for native Windows.
- 📦 **Plugin-ready** — installable via Claude Code Marketplace.
- 🔁 **Compound engineering** — Stop hook proposes new rules from session corrections.
- 📐 **Eval-backed sizing** — caps from 2,455-evaluation study; less context = better adherence.

## 🚀 Quickstart

```bash
# 1. Install
curl -sSL https://raw.githubusercontent.com/mohandoz/conjure/main/install.sh | bash

# 2. Initialize a project (auto-detects new or existing)
cd /path/to/your/repo
conjure init existing --profile=python-fastapi .

# 3. Open Claude Code, paste PROMPT.md, watch the magic
```

That's it. Run `conjure audit` anytime to verify health.

## 🧰 Features

<table>
<tr>
<td width="50%">

### Core scaffold
- ≤100-line root `CLAUDE.md` (hard cap enforced)
- 17 skill templates with progressive disclosure
- 6 subagent definitions for isolated context
- 5 hook scripts with correct exit codes (bash + `.mjs`)
- `.claudeignore`, `.editorconfig`, `.gitattributes`
- Per-project `.claude/README.md` + `EVENT-LOG.md`
- Standard docs: ARCHITECTURE, RUNBOOK, GLOSSARY, ADR template

</td>
<td width="50%">

### Production guard-rails
- **Backup-before-mutate** on every change
- **Version pinning** per project (`.claude/.conjure-version`)
- **Audit** with size caps, schema validation, anti-pattern detection
- **Pre-flight checks** for tool availability
- **Failure-mode docs** for every common breakage
- **JSON schemas** for skill/agent frontmatter (IDE-validated)
- **Compound-engineering loop** for continuous improvement

</td>
</tr>
<tr>
<td width="50%">

### Tool integrations
- 🕸 **graphify** — persistent knowledge graph
- 📚 **context7** — live framework docs
- 🌐 **firecrawl** — web research
- 🔍 **ast-grep** — structural code search
- 📦 **repomix** — full-codebase context dumps
- 🗄 **Postgres MCP** — schema introspection
- 🐙 **GitHub MCP** — PRs / issues / Actions
- 🧮 **Sequential Thinking MCP**

</td>
<td width="50%">

### Stack & compliance
- 9 stack profiles (Java/Python/TS/Rust/Go/Node/...)
- 4 compliance overlays (HIPAA/SOC2/GDPR/PCI)
- 6 migration paths (Cursor/Aider/Continue/Copilot/Windsurf/Claude)
- Monorepo support (nested CLAUDE.md per package)
- GSD workflow integration

</td>
</tr>
</table>

## 🎯 Stack profiles

```bash
conjure init existing --profile=<stack> .
```

| Profile | Stack | Build | Test |
| --- | --- | --- | --- |
| `java-spring`     | Java 17+ / Spring Boot / Gradle | `./gradlew build` | `./gradlew test` |
| `python-fastapi`  | Python 3.11+ / FastAPI / uv     | `uv sync`         | `uv run pytest`  |
| `ts-next`         | TypeScript / Next.js 15 / pnpm  | `pnpm build`      | `pnpm test`      |
| `rust-axum`       | Rust / Axum / cargo             | `cargo build`     | `cargo nextest`  |
| `go-gin`          | Go / Gin                        | `go build ./...`  | `go test ./...`  |
| `node-nest`       | Node / NestJS / pnpm            | `pnpm build`      | `pnpm test`      |
| `monorepo`        | Turborepo / Nx / pnpm workspaces | per-package      | per-package      |
| `polyglot`        | Mixed stacks                    | Make/Just         | per-language     |
| `data-science`    | Python / Jupyter / dbt          | `uv sync`         | `pytest` + `nbqa` |

## 🔒 Compliance overlays

Layer one or more on top of a profile:

```bash
bash $CONJURE_HOME/compliance/hipaa/apply.sh .
bash $CONJURE_HOME/compliance/soc2/apply.sh  .
bash $CONJURE_HOME/compliance/gdpr/apply.sh  .
bash $CONJURE_HOME/compliance/pci/apply.sh   .
```

Each overlay adds: CLAUDE.md non-negotiables, pre-commit guard hooks (e.g.
PHI pattern scan for HIPAA), and a controls checklist under `docs/compliance/`.

⚠️ Overlays make the AI less likely to produce non-compliant code. They do
NOT make you compliant — that requires people + process + audit.

## 🔄 Migration from other tools

Backup-before-mutate is automatic. Rollback is `mv .claude.backup-<ts> .claude`.

| Source | Command |
| --- | --- |
| Existing hand-rolled `.claude/` | `conjure migrate from-claude .` |
| Cursor (`.cursorrules`, `.cursor/rules/`) | `conjure migrate from-cursor .` |
| Aider (`.aider.conf.yml`, `CONVENTIONS.md`) | `conjure migrate from-aider .` |
| Continue (`.continue/config.json`) | `conjure migrate from-continue .` |
| GitHub Copilot (`.github/copilot-instructions.md`) | `conjure migrate from-copilot .` |
| Windsurf (`.windsurfrules`) | `conjure migrate from-windsurf .` |

See `MIGRATION-GUIDE.md` for details.

## 🧪 Quality

```bash
$ bash tests/run.sh
═══════════════════════════════════════════════════════════════════
PASS: 112    FAIL: 0
═══════════════════════════════════════════════════════════════════
```

Every PR runs:
- shellcheck on all `.sh` files
- JSON Schema validation on all `.json` files
- Frontmatter validation on every `SKILL.md` / agent `.md`
- Size cap enforcement (CLAUDE.md ≤100, SKILL.md ≤200, agent ≤80)
- `@import` detection (forbidden in CLAUDE.md)
- Exit code check on hooks (must be `exit 2`, never `exit 1`)
- Migration coverage (every documented source has a working script)
- Profile + compliance coverage (every documented overlay applies cleanly)

## 📖 Documentation

| Doc | What |
| --- | --- |
| [`PROMPT.md`](PROMPT.md) | The master prompt — paste into Claude Code |
| [`MIGRATION-GUIDE.md`](MIGRATION-GUIDE.md) | Safe migration playbook |
| [`FAILURE-MODES.md`](FAILURE-MODES.md) | Symptom → cause → fix for every common breakage |
| [`COMPARISON.md`](COMPARISON.md) | How Conjure compares to alternatives |
| `checklists/NEW-PROJECT.md` | Greenfield step-by-step |
| `checklists/EXISTING-PROJECT.md` | Brownfield step-by-step |
| `checklists/AUDIT.md` | Periodic health check |
| `checklists/ONBOARDING.md` | Onboard new dev to a Conjure repo |
| `reference/BEST-PRACTICES.md` | 2026 consolidated, eval-backed |
| `reference/TOOLS-CATALOG.md` | Every CLI tool worth knowing |
| `reference/MCP-SERVERS.md` | Which MCPs to install + configs |
| `reference/ANTI-PATTERNS.md` | What NOT to do (with evidence) |
| `reference/SIZING.md` | Line counts + token budgets |
| `reference/COMPACTION.md` | Surviving context compression |
| `reference/PROMPTING-PATTERNS.md` | Trigger-action and other patterns |
| `planning/ROADMAP.md` | What's planned next |
| `planning/GSD-INTEGRATION.md` | GSD workflow integration |
| [`CHANGELOG.md`](CHANGELOG.md) | What changed per version |
| [`CONTRIBUTING.md`](CONTRIBUTING.md) | How to contribute |
| [`SECURITY.md`](SECURITY.md) | Security policy |
| [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md) | Contributor Covenant |
| [`SUPPORT.md`](SUPPORT.md) | Where to get help |

## 🎓 Core principles (10)

1. **Less context = better output.** ETH Zurich + Anthropic eval data.
2. **`@imports` load eagerly.** Use prose refs or skills instead.
3. **Skills are the real lazy loader.** Progressive disclosure.
4. **Hooks > advisory rules.** Promote non-negotiables to hooks.
5. **Subagents isolate context.** Verbose work in fresh windows.
6. **Persistent graph > re-reading files.** Build once, query forever.
7. **Trigger-action format.** "WHEN X, DO Y" beats general guidance.
8. **Order matters.** Top of CLAUDE.md survives compaction; non-negotiables first.
9. **Compound engineering.** Every correction → candidate rule promotion.
10. **Cite file:line.** So future Claude can verify.

## 🤝 Contributing

PRs welcome. See [`CONTRIBUTING.md`](CONTRIBUTING.md).

- Bug? Open an [issue](https://github.com/mohandoz/conjure/issues/new?template=bug_report.yml).
- Feature? Use the [feature request template](https://github.com/mohandoz/conjure/issues/new?template=feature_request.yml).
- Question? Use [Discussions](https://github.com/mohandoz/conjure/discussions).
- Security? See [`SECURITY.md`](SECURITY.md) — do not open public issues.

## 🛣 Roadmap

- **v0.3.0** — test fixtures per profile, skill firing telemetry, cost estimator.
- **v0.4.0** — marketplace publication, Homebrew formula, Docker image, `conjure publish-skill`.
- **v0.5.0** — interactive 3-way merge for updates, drift detector, auto-PR bot.
- **v0.6.0** — workspace mode, cross-repo graphify orchestration.
- **v1.0.0** — frozen schemas, signed releases, ≥10 production teams.

See [`planning/ROADMAP.md`](planning/ROADMAP.md).

## ⚖ License

[MIT](LICENSE) — use freely. Attribution appreciated, not required.

## 🌟 Star history

[View live star history chart →](https://star-history.com/#mohandoz/conjure&Date)

<sub>Inline chart will appear here after the repo crosses ~10 stars (star-history.com rate-limits anonymous renders for fresh repos).</sub>

## 🙏 Built on

- [Claude Code](https://code.claude.com/) by Anthropic
- [graphify](https://graphify.net/) for persistent knowledge graphs
- [context7](https://github.com/upstash/context7) for live docs
- [repomix](https://github.com/yamadashy/repomix), [ast-grep](https://ast-grep.github.io/), [firecrawl](https://www.firecrawl.dev/)
- Eval data from Anthropic's published benchmarks + the 2,455-eval community study
- ETH Zurich research on context size and task success
- GSD workflow (Get Shit Done) for our own development

---

<div align="center">

**Conjure** — *Code grows on Conjure the way a vine grows on a garden frame:
structured but free.*

Made with ⚙ by [Mohannad Ahmad](mailto:mohannad.a@protonmail.com)

</div>
