# Changelog

All notable changes to Conjure. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versioning: [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.2.0] — 2026-05-24

### Added
- Renamed kit from `claude-init` to **Conjure**.
- Git repository, CHANGELOG, LICENSE, CONTRIBUTING, SECURITY, CODEOWNERS.
- `cli/conjure` — single CLI entry point with subcommands.
- `migrations/` — safe migration paths for existing `.claude/` and from other AI tools (cursor, aider, continue, copilot).
- `profiles/` — stack-specific overlays (java-spring, python-fastapi, ts-next, rust-axum, go-gin, node-nest, monorepo, polyglot).
- `.claude-plugin/marketplace.json` — Claude Code Plugin manifest for marketplace distribution.
- `examples/` — fully-worked sample projects per stack.
- `tests/` — fixture-driven regression tests for kit changes.
- `planning/` — Conjure's own GSD-style roadmap.
- `.github/workflows/ci.yml` — lint + test on push/PR.
- `MIGRATION-GUIDE.md` — migration playbook for existing configs.
- `FAILURE-MODES.md` — what to do when graphify/MCP/hooks misbehave.
- `COMPLIANCE/` — HIPAA, SOC2, GDPR, PCI overlays.
- `templates/.claude/README.md.tmpl` — per-project harness explainer.
- `templates/.claude/EVENT-LOG.md.tmpl` — per-project harness change log.
- `templates/.gitignore.tmpl` — patterns for `.claude/COMPOUND-CANDIDATES.md`, `graphify-out/`, etc.
- Backup-before-mutate everywhere (every script that writes creates `.claude.backup-<ts>/` first).
- Version pinning: every project's `.claude/.conjure-version` records which kit version installed it.
- Pre-flight dep check in `cli/conjure init`.
- Schema files for `settings.json`, skill frontmatter, agent frontmatter (IDE validation).

### Changed
- Kit folder name `/u01/claude-init/` → `/u01/conjure/`.
- All scripts moved under `cli/conjure` subcommands; old `scripts/*.sh` are shims.

### Migration notes
- Existing users with `/u01/claude-init/` config files: `ln -s /u01/conjure /u01/claude-init` for back-compat.
- Run `conjure migrate self` once to update any pinned references.

## [0.1.0] — 2026-05-24

### Added
- Initial release as `claude-init`: 4-layer harness (CLAUDE.md + skills + agents + hooks).
- 17 skill templates, 6 agent templates, 5 hook scripts.
- Reference docs: BEST-PRACTICES, TOOLS-CATALOG, MCP-SERVERS, ANTI-PATTERNS, SIZING, COMPACTION, PROMPTING-PATTERNS.
- Scripts: init-project.sh, audit-setup.sh, refresh-graph.sh, install-mcp-stack.sh.
- Checklists: NEW-PROJECT, EXISTING-PROJECT, AUDIT, ONBOARDING.

[Unreleased]: https://github.com/<org>/conjure/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/<org>/conjure/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/<org>/conjure/releases/tag/v0.1.0
