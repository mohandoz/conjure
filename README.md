# 🪴 Conjure — The Claude Code Harness Kit

**Production-grade scaffolding for Claude Code projects.** Built for high-stakes work
where adherence matters. 2026 best practices baked in: ≤100-line CLAUDE.md,
trigger-action rule format, compaction-aware ordering, deterministic hooks,
lazy-loaded skills, isolated subagents, persistent knowledge graph.

> *A conjure is a lattice that supports growth without dictating shape.
> Your code grows on Conjure the way a vine grows on a garden frame —
> structured but free.*

---

## Why Conjure

Most CLAUDE.md setups fail the same way: a 500-line monolith that Claude ignores
after the first hundred. Conjure enforces the four-layer harness Anthropic
recommends and that the 2,455-evaluation community study validated:

| Layer | Role | Loaded |
| --- | --- | --- |
| `CLAUDE.md` | Always-on advisory rules (≤100 lines) | Every session |
| `.claude/skills/` | Lazy-loaded instructions w/ progressive disclosure | On trigger match |
| `.claude/agents/` | Isolated-context subagents | On delegation |
| `.claude/settings.json` hooks | Deterministic shell-script enforcement | On event |

Plus first-class integration with **graphify** (knowledge graph), **context7**
(live docs), **ast-grep** (structural search), **repomix** (code packing),
**Postgres MCP** (schema introspection), and **firecrawl** (web research).

## Quick start

```bash
# Bootstrap any repo (new or existing)
conjure init [new|existing|migrate] [--profile=<stack>] /path/to/repo

# Migrate from another assistant safely (backup-before-mutate)
conjure migrate from-cursor /path/to/repo
conjure migrate from-aider /path/to/repo
conjure migrate from-continue /path/to/repo
conjure migrate from-copilot /path/to/repo
conjure migrate from-windsurf /path/to/repo
conjure migrate from-claude /path/to/repo    # audit + upgrade existing .claude/

# Health check
conjure audit /path/to/repo

# Update an existing setup to current kit version (interactive merge)
conjure update --check /path/to/repo
conjure update --apply /path/to/repo

# Refresh persistent knowledge graph
conjure refresh-graph /path/to/repo

# Install recommended MCP servers
conjure install-mcp
```

Then paste `PROMPT.md` into a fresh Claude Code session at your repo root.

## What you get

```
.claude/
├── settings.json           ← hooks + permissions + JSON-schema validated
├── skills/                 ← 17 skill scaffolds, fill on demand
│   ├── code-graph/         ← graphify wrapper
│   ├── docs-lookup/        ← context7 wrapper
│   ├── web-research/       ← firecrawl/WebFetch
│   ├── ast-search/         ← ast-grep wrapper
│   ├── repo-pack/          ← repomix wrapper
│   ├── sql-explorer/       ← Postgres MCP wrapper
│   └── (architecture, domain-model, api-routes, data-access, messaging,
│        database-schema, build-deploy, testing, debugging, pr-review,
│        security-review, release)
├── agents/                 ← 6 subagent definitions
│   ├── code-explorer.md    ← read-only locator
│   ├── test-writer.md
│   ├── migration-writer.md ← schema migrations w/ verified rollback
│   ├── security-auditor.md
│   ├── doc-writer.md
│   └── diff-reviewer.md
├── hooks/                  ← 5 enforcement scripts
│   ├── post-edit-format.sh
│   ├── pre-bash-block-destructive.sh
│   ├── pre-commit-quality-gate.sh
│   ├── stop-compound-engineering.sh
│   └── session-start-context.sh
├── README.md               ← per-project harness explainer
├── EVENT-LOG.md            ← per-project harness change log
├── COMPOUND-CANDIDATES.md  ← session-end rule proposals
└── .conjure-version        ← pinned kit version
```

Plus root: `CLAUDE.md`, `.claudeignore`, `.editorconfig`, `.gitattributes`,
and `docs/ARCHITECTURE.md` / `RUNBOOK.md` / `GLOSSARY.md` / `adr/` scaffolds.

## Stack profiles

Layered on top of the base init. Adds stack-specific rules, hooks, and
recommended MCP servers.

| Profile | Apply with |
| --- | --- |
| `java-spring`     | `conjure init existing --profile=java-spring .` |
| `python-fastapi`  | `--profile=python-fastapi` |
| `ts-next`         | `--profile=ts-next` |
| `rust-axum`       | `--profile=rust-axum` |
| `go-gin`          | `--profile=go-gin` |
| `node-nest`       | `--profile=node-nest` |
| `monorepo`        | `--profile=monorepo` |
| `polyglot`        | `--profile=polyglot` |
| `data-science`    | `--profile=data-science` |

## Compliance overlays

Layer one or more on top of a profile when regulated:

```bash
bash /u01/conjure/compliance/hipaa/apply.sh /path/to/repo
bash /u01/conjure/compliance/soc2/apply.sh  /path/to/repo
bash /u01/conjure/compliance/gdpr/apply.sh  /path/to/repo
bash /u01/conjure/compliance/pci/apply.sh   /path/to/repo
```

## Migration from other AI tools

| Source | Detect | Migrate |
| --- | --- | --- |
| Hand-rolled `CLAUDE.md` / `.claude/` | `migrations/from-claude/detect.sh` | `conjure migrate from-claude` |
| Cursor (`.cursorrules`, `.cursor/rules/*.mdc`) | auto | `conjure migrate from-cursor` |
| Aider (`.aider.conf.yml`, `CONVENTIONS.md`) | auto | `conjure migrate from-aider` |
| Continue (`.continue/config.json`) | auto | `conjure migrate from-continue` |
| GitHub Copilot (`.github/copilot-instructions.md`) | auto | `conjure migrate from-copilot` |
| Windsurf (`.windsurfrules`) | auto | `conjure migrate from-windsurf` |

Backup-before-mutate is automatic. Rollback is trivial:
`mv .claude.backup-<timestamp> .claude`.

## GSD integration

Conjure develops via [GSD](https://github.com/<gsd-org>/gsd) — phase-driven
planning with atomic commits. GSD orchestrators can call `conjure init` to
scaffold the harness for projects it manages. See `planning/GSD-INTEGRATION.md`.

## Documentation

| Doc | What |
| --- | --- |
| `PROMPT.md` | The master prompt — paste into Claude Code |
| `MIGRATION-GUIDE.md` | Safe migration playbook |
| `FAILURE-MODES.md` | What to do when things break |
| `checklists/NEW-PROJECT.md` | Greenfield step-by-step |
| `checklists/EXISTING-PROJECT.md` | Brownfield step-by-step |
| `checklists/AUDIT.md` | Periodic health check |
| `checklists/ONBOARDING.md` | Onboard new dev to a Conjure-configured repo |
| `reference/BEST-PRACTICES.md` | 2026 consolidated, eval-backed |
| `reference/TOOLS-CATALOG.md` | Every tool worth knowing |
| `reference/MCP-SERVERS.md` | Which MCPs to install + configs |
| `reference/ANTI-PATTERNS.md` | What NOT to do (with evidence) |
| `reference/SIZING.md` | Line counts and token budgets |
| `reference/COMPACTION.md` | Surviving context compression |
| `reference/PROMPTING-PATTERNS.md` | Trigger-action and other patterns |
| `planning/ROADMAP.md` | What's next |
| `CHANGELOG.md` | What changed |
| `CONTRIBUTING.md` | How to contribute |
| `SECURITY.md` | Security policy |

## Principles

1. **Less context = better output.** ETH Zurich + Anthropic eval data.
2. **`@imports` load eagerly** — not a token saving. Use prose references.
3. **Skills are the real lazy loader.** Progressive disclosure.
4. **Hooks > advisory rules.** Promote non-negotiables to hooks.
5. **Subagents isolate context.** Verbose work in fresh windows.
6. **Persistent graph > re-reading files.** Build once, query forever.
7. **Trigger-action format.** "WHEN X, DO Y" outperforms general guidance.
8. **Order matters.** CLAUDE.md is read top-down; later sections summarized first.
9. **Compound engineering.** Every correction → candidate rule promotion.
10. **Cite file:line.** So future Claude can verify.

## License

MIT — see `LICENSE`.

## Contributing

See `CONTRIBUTING.md`. PRs welcome. Use `tests/run.sh` before submitting.
