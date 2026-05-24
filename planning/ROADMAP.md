# Conjure Roadmap

Development is GSD-style. Each version = a milestone. Each feature = a phase.

## Status legend

- 🟢 done
- 🟡 in progress
- ⚪ planned
- 🔵 considering (no commitment)

## v0.1.0 — claude-init prototype (2026-05-24) 🟢

- 🟢 4-layer harness scaffold (CLAUDE.md + skills + agents + hooks)
- 🟢 17 skill templates + 6 agent templates + 5 hook scripts
- 🟢 Reference docs (best practices, tools, MCP, anti-patterns)
- 🟢 init-project.sh + audit-setup.sh

## v0.2.0 — Conjure rename + critical gaps (2026-05-24) 🟢

- 🟢 Rename to **Conjure**; git repo; LICENSE / CHANGELOG / CONTRIBUTING / SECURITY / CODEOWNERS
- 🟢 Unified CLI (`conjure init|migrate|audit|update|...`)
- 🟢 Migration paths (from-claude, from-cursor, from-aider, from-continue, from-copilot, from-windsurf)
- 🟢 Stack profiles (java-spring, python-fastapi, ts-next, rust-axum, go-gin, node-nest, monorepo, polyglot, data-science)
- 🟢 Compliance overlays (HIPAA, SOC 2, GDPR, PCI)
- 🟢 Plugin manifest (`.claude-plugin/`)
- 🟢 JSON schemas for skill/agent frontmatter
- 🟢 Version pinning per project (`.claude/.conjure-version`)
- 🟢 FAILURE-MODES.md + MIGRATION-GUIDE.md
- 🟢 templates/.claude/README.md / EVENT-LOG.md / .gitignore.tmpl
- 🟢 Backup-before-mutate semantics
- 🟢 GSD planning structure for self-development

## v0.3.0 — Testing + telemetry ⚪

- ⚪ Test fixtures: example project per stack profile under `tests/fixtures/`
- ⚪ `tests/run.sh` — full kit regression suite (audit assertions per fixture)
- ⚪ `conjure init --dry-run` (currently CLI accepts flag; not enforced everywhere)
- ⚪ Skill firing telemetry: hook records which skills loaded per session → quarterly retire-list
- ⚪ Cost estimator: `conjure audit --cost` predicts session token cost from harness size
- ⚪ Pre-flight dep verification with one-command install fix-its
- ⚪ Failure-mode reproductions in tests

## v0.4.0 — Distribution + ecosystem ⚪

- ⚪ Publish to Claude Code Marketplace (via `.claude-plugin/marketplace.json`)
- ⚪ Homebrew formula `brew install conjure`
- ⚪ Curl-bash installer: `curl -sSL conjure.dev/install | bash`
- ⚪ Docker image with all tools preinstalled (graphify, ast-grep, gitleaks, repomix)
- ⚪ `conjure publish-skill <name>` — contribute project-specific skill back to the kit
- ⚪ Org overlay system: base kit + private overlay repo per organization

## v0.5.0 — Auto-update + drift ⚪

- ⚪ Interactive 3-way merge for `conjure update --apply`
- ⚪ Drift detector: weekly cron compares project's skills vs current templates
- ⚪ Auto-PR bot that opens drift-fix PRs against project repos
- ⚪ MCP server health monitor + alert
- ⚪ Compound-engineering loop: actually proposes CLAUDE.md edits (currently scaffolds only)

## v0.6.0 — Workspace / multi-repo ⚪

- ⚪ Workspace mode: `conjure workspace init` for shared skills across repos
- ⚪ Cross-repo graph: orchestrate `graphify merge-graphs` across project list
- ⚪ Shared `.claude/skills/` via symlink or git submodule
- ⚪ Org-wide search: "where does <org> use pattern X" via aggregated graphs

## v1.0.0 — Stability commitment ⚪

- ⚪ Frozen skill/agent schemas with semver guarantees
- ⚪ Migration path tested from every prior version
- ⚪ Signed releases
- ⚪ Documented public API surface
- ⚪ ≥10 production teams using it
- ⚪ Test coverage ≥80% of CLI paths

## Backlog (no version) 🔵

- 🔵 IDE extensions surfacing Conjure status (VS Code, JetBrains)
- 🔵 Web dashboard: visualize harness health across many repos
- 🔵 LLM-assisted rule extraction: scan session logs to propose new rules
- 🔵 Skill marketplace (browse, install community skills)
- 🔵 A/B testing harness: compare two prompt variants on same fixtures
- 🔵 Internationalization (non-English skill descriptions matching localized user phrases)
- 🔵 Plugin signing + supply-chain verification

## How to propose

1. Open issue with `[proposal]` prefix.
2. Add to backlog (🔵) if exploratory.
3. Promote to a versioned phase via PR to this file once committed.
4. Use `/gsd-plan-phase` for the actual implementation plan.
