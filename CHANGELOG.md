# Changelog

All notable changes to Conjure. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versioning: [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.5.0] — 2026-05-26

### Added — Auto-Update + Healthcheck (v0.5.0)
- `conjure check` — reads 35-file kit manifest, sha256-compares every file,
  exits 0 (current) or 1 (drift detected); `--porcelain` emits `A/M/R <path>`
  machine-readable lines for scripting.
- `conjure resolve` — interactive sidecar walker; prompts `[k]eep / [a]pply /
  [e]dit / [s]kip` per `.conjure-conflict-*` file; exits 2 on non-TTY stdin;
  prints "No conflicts remain" when all sidecars are cleared.
- `conjure update --pr` — idempotent GitHub PR creation; deterministic branch
  `conjure/update-<7-char-sha256>`; PR body is a drift diff table from
  `conjure check --porcelain`; exits 0 if PR already exists (prints URL).
- `conjure update --cron` — writes `.github/workflows/conjure-update.yml`
  cron template (weekly Monday 09:00 UTC) to the target repo; idempotent.
- `conjure.ps1` — 24-line PowerShell shim for native Windows; discovers Git
  Bash at `$env:ProgramFiles\Git`; falls back to WSL with `/mnt/<drive>` path
  conversion; `$ErrorActionPreference = 'Continue'` + `exit $LASTEXITCODE`
  throughout; exits 2 if neither Git Bash nor WSL found.
- `lib/mutate.sh` gains `mutate_rm` — dry-run-safe file deletion consistent
  with existing `mutate_cp` / `mutate_write` primitives.
- `windows-ps1-shim` CI job (`ci.yml`) — `shell: pwsh`; smoke-tests
  `conjure.ps1 --version` exits 0 and `conjure.ps1 init` propagates exit 2.

### Changed — Auto-Update + Healthcheck (v0.5.0)
- `conjure publish-skill` accepts positional `<org/repo>` as `$2`; `TARGET_REPO`
  env kept as deprecated fallback emitting `WARN:` on stderr.
- `release.yml` ci-gate: 5-attempt retry loop (15s sleep) before failure check;
  explicit FAIL message when zero check-runs found after all retries.

### Added — Distribution + Ecosystem (v0.4.0)
- `conjure update --apply` — 3-way merge via `lib/merge.sh`; writes
  `.conjure-conflict-*` sidecars on conflicts; backup-before-mutate throughout.
- Claude Code Marketplace plugin manifest (`.claude-plugin/`); validated by
  `claude plugin validate`.
- `conjure publish-skill` — egress-scans skills, opens PR to target repo;
  GitHub Actions publish pipeline.
- `conjure init --overlay` and `conjure refresh-overlay` — org overlay system
  for team-wide CLAUDE.md / hook enforcement.
- Homebrew tap `mohandoz/homebrew-conjure`; auto-bump action in `release.yml`.
- Multi-arch Docker image (`linux/amd64`, `linux/arm64`) on
  `ghcr.io/mohandoz/conjure`; `release.yml` Docker job.
- `release.yml` — single gate: ci-gate → release → docker + homebrew (parallel).
- VALIDATION.md files for phases 01–07 (Nyquist compliance backfill).

### Added — Testing + Telemetry (v0.3.0)
- Fixture-driven regression test suite (`tests/run.sh`); covers all CLI
  commands, merge/conflict paths, and dry-run invariants.
- Skill-firing telemetry via `PreToolUse(Skill)` + `InstructionsLoaded` hooks;
  append-only JSONL; local-only, no service.
- Cost estimator: chars/4 heuristic × dated price table baked into `conjure`;
  `--exact` opt-in.
- Cross-platform preflight: `command -v` table (bash) + mirrored `.mjs` probe;
  OS-detected install hints.
- `lib/` directory for shared bash logic (`mutate.sh`, `merge.sh`).

### Added — Brand
- Logo at `.github/assets/logo.svg` — binding-circle sigil with four
  inscriptions (CLAUDE.md / Skills / Subagents / Hooks) and a chained `C`.
- Brand voice: *"Bind the daemon. Ship the code."*

## [0.2.1] — 2026-05-24

### Added
- **Cross-platform Node.js hooks** at `templates/hooks-nodejs/` — `.mjs`
  parallel set for native Windows compatibility (per 2026 best-practice
  guidance to invoke `node` rather than platform-specific shells).
- `install.sh` — `curl -sSL | bash` one-line installer; idempotent;
  configures PATH for zsh/bash/fish; verifies install.
- `CODE_OF_CONDUCT.md` (Contributor Covenant 2.1).
- `SUPPORT.md` — where to get help with response expectations.
- `COMPARISON.md` — honest comparison vs awesome-claude-code-toolkit,
  claude-code-plugin-template, TemplateClaw, oh-my-zsh-style framework,
  CCHub, idea-factory, ralph-loop, and manual `.claude/`.
- `.github/ISSUE_TEMPLATE/{bug_report.yml,feature_request.yml,config.yml}`.
- `.github/PULL_REQUEST_TEMPLATE.md`.
- `.github/FUNDING.yml` (placeholder for sponsorship platforms).
- **Viral README**: badges, feature-table layout, comparison section,
  star-history placeholder, social-proof phrasing per 2026 README research.

### Fixed
- Stale `/u01/claude-init/` path references in `PROMPT.md` and
  `checklists/` updated to `/u01/conjure/` + `conjure audit` CLI form.

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

[0.5.0]: https://github.com/mohandoz/conjure/compare/v0.2.1...v0.5.0
[0.2.1]: https://github.com/mohandoz/conjure/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/mohandoz/conjure/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/mohandoz/conjure/releases/tag/v0.1.0
