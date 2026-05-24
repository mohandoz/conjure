# Checklist — New Project (Greenfield)

Use when starting from an empty directory.

## Pre-Claude (you do this once, manually)

- [ ] `git init && git commit --allow-empty -m "chore: init"`
- [ ] Pin runtime version: `.tool-versions` (mise/asdf) or `.nvmrc` / `pyproject.toml` `requires-python`.
- [ ] `.gitignore` (use https://gitignore.io for stack).
- [ ] `.editorconfig` (copy from `/u01/claude-init/templates/.editorconfig`).
- [ ] `.gitattributes` (line endings, binary handling).
- [ ] `README.md` with one-paragraph intent (Claude reads this).
- [ ] `LICENSE`.
- [ ] Choose a task runner: `Makefile` / `Justfile` / `Taskfile.yml`. Add `make help` style discovery.
- [ ] Decide MCP stack — see `reference/MCP-SERVERS.md`. At minimum: filesystem (built-in), context7.

## With Claude (paste PROMPT.md with `[NEW]` invocation)

- [ ] Answer Claude's 5-7 discovery questions honestly (stack, DB, test framework, deploy target, team size, conventions to honor, primary language for ad-hoc scripts).
- [ ] Confirm Claude scaffolds the four layers (CLAUDE.md, skills, agents, hooks).
- [ ] Run audit: `bash /u01/claude-init/scripts/audit-setup.sh .`

## First-day-of-coding additions

- [ ] `docs/adr/0001-record-architecture-decisions.md` (Michael Nygard template — see `templates/docs/ADR-TEMPLATE.md`).
- [ ] `docs/ARCHITECTURE.md` — system diagram (Mermaid). Update as you build.
- [ ] `.env.example` — every env var with placeholder. Real `.env` gitignored.
- [ ] `CONTRIBUTING.md` — clone → build → test recipe (must work on fresh machine).
- [ ] `SECURITY.md` — vulnerability disclosure address.
- [ ] `CODEOWNERS` — even with one author, future-you will thank you.
- [ ] Conventional Commits + commitlint OR equivalent enforcement.
- [ ] Set up CI from day 1 (GitHub Actions / Bitbucket Pipelines / GitLab CI). Don't defer.
- [ ] Pre-commit framework: `pre-commit` / `lefthook` / `husky+lint-staged`. Wire to Claude hooks.
- [ ] Secret scanning hook: `gitleaks` or `trufflehog`.
- [ ] Devcontainer or compose stack for reproducible local env.

## When the project hits ~50 files

- [ ] Run graphify: `graphify . --mode deep --wiki --mcp`.
- [ ] Update `skills/code-graph/SKILL.md` to reference real graph paths.
- [ ] Add `--watch` mode to keep graph fresh, OR add a cron via `octo:schedule`.

## Compound-engineering loop (ongoing)

- [ ] Every time you correct Claude, ask: should this become a CLAUDE.md rule, a skill, or a hook?
  - Repeated >2 times → CLAUDE.md rule.
  - Specific workflow → skill.
  - Non-negotiable → hook.
- [ ] Stop hook can automate this — see `templates/hooks/stop-compound-engineering.sh`.

## Anti-patterns to avoid (new project edition)

- ❌ Writing CLAUDE.md before you know your stack — wait until at least the build runs.
- ❌ Adding @imports to "organize" CLAUDE.md — they load eagerly.
- ❌ Installing every MCP server "in case". Start with 2-3; expand on demand.
- ❌ Over-specified slash commands — let Claude orchestrate via Task() instead.
- ❌ Skipping CI on day 1. The cost of adding it later is 10×.
- ❌ Generated code committed without a generator script. Future-Claude won't know how it was made.
