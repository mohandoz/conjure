# Contributing to Conjure

## Development workflow

Conjure develops via GSD (Get Shit Done) — see `planning/` for active roadmap.

```bash
# Pick a phase from planning/
/gsd-plan-phase <phase-id>
/gsd-execute-phase <phase-id>
/gsd-verify-work
```

For non-GSD contributors: standard PR flow. Branch from `main`, PR back to `main`.

## What changes how

| Change | Where |
| --- | --- |
| New skill template | `templates/skills/<name>/SKILL.md` + bump version + CHANGELOG entry |
| New agent template | `templates/agents/<name>.md` + entry in `cli/conjure init` skill list |
| New hook script | `templates/hooks/<name>.sh` (must `chmod +x`) + entry in settings.json.tmpl |
| New stack profile | `profiles/<stack>/` directory with overlay files |
| New migration source | `migrations/from-<tool>/` (`detect.sh`, `migrate.sh`, `MIGRATION.md`) |
| Reference doc update | `reference/<name>.md` — ALWAYS cite sources |
| Best-practice change | Update `reference/BEST-PRACTICES.md` first; ripple to skills |

## Required for every PR

- [ ] CHANGELOG.md entry under `[Unreleased]`.
- [ ] If new template: at least one test fixture in `tests/fixtures/`.
- [ ] If behavior change: at least one assertion in `tests/test-*.sh`.
- [ ] Run `cli/conjure audit tests/fixtures/<fixture>` — green.
- [ ] Run `bash tests/run.sh` — green.
- [ ] No new external dependencies without consensus.

## Versioning

- **MAJOR** — breaking change to `.claude/` layout, script CLI, or skill schema.
- **MINOR** — new feature, new skill, new profile, new migration source. Backward-compatible.
- **PATCH** — bug fix, doc fix, refactor.

`VERSION` file holds current version. Bump in same PR as the change.

## Release process

```bash
# 1. Update VERSION
echo "0.3.0" > VERSION

# 2. Update CHANGELOG.md — move [Unreleased] → [0.3.0] with date

# 3. Commit + tag
git commit -am "chore(release): v0.3.0"
git tag -a v0.3.0 -m "Release v0.3.0"
git push && git push --tags

# 4. CI runs release workflow; GitHub Release published
```

## Style rules for kit content

- Every claim in a skill/agent body MUST cite `file:line` so future Claude can verify.
- Trigger descriptions: one sentence, name concrete user phrases.
- Hook scripts: `set -euo pipefail`; exit 2 to block; finish in <2s.
- Reference docs: cite sources at the bottom.
- No emoji unless inside a hook output or user-facing CLI message.
- Tables over prose for catalogs.

## Anti-patterns we reject

- Adding a skill "in case it's useful". Every skill must have a justification for inclusion (eval-data, user-request, observed gap).
- Bloating CLAUDE.md.tmpl beyond 100 lines.
- Adding @imports anywhere.
- Adding rules that linters/formatters already enforce.
- Adding fields to settings.json without schema update.

## Testing

```bash
bash tests/run.sh                       # full kit test suite
cli/conjure audit tests/fixtures/<x>    # audit a specific fixture
cli/conjure init --dry-run <target>     # preview what init would do
```

## Code review checklist (for maintainers)

- [ ] Cites sources for any best-practice claims.
- [ ] Doesn't break existing fixtures.
- [ ] Updates schemas if config shape changed.
- [ ] CHANGELOG entry present.
- [ ] No regression in `cli/conjure audit` on any fixture.
- [ ] If touching migration logic: backup-before-mutate verified.

## Security

See `SECURITY.md` for disclosure process. Do not file security issues publicly.
