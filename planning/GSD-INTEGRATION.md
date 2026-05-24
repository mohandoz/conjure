# GSD Integration

Conjure develops via Get Shit Done (GSD) — phase-driven planning with atomic
commits, verification loops, and milestone audits. Bidirectional integration:
Conjure uses GSD for its own development; GSD can use Conjure to scaffold the
projects it manages.

## Concepts

| GSD | Conjure equivalent |
| --- | --- |
| Project | A repo Conjure has initialized |
| Milestone | A Conjure kit version (v0.2.0 → v0.3.0) |
| Phase | A feature inside a milestone |
| Plan | The actionable steps for a phase |
| Verification | Conjure audit + tests/run.sh |
| Backlog | `planning/ROADMAP.md` 🔵 items |

## Workflow: developing Conjure itself

```bash
# 1. Pick a phase from planning/ROADMAP.md
/gsd-plan-phase v0.3.0-test-fixtures

# 2. Execute
/gsd-execute-phase v0.3.0-test-fixtures

# 3. Verify
/gsd-verify-work
bash tests/run.sh

# 4. Ship
/gsd-ship
# bumps VERSION, updates CHANGELOG, creates PR
```

## Workflow: GSD-driven project that uses Conjure

GSD orchestrators can call Conjure for scaffolding:

```bash
# 1. Initialize new project with deep context
/gsd-new-project

# 2. After project structure is established, scaffold Claude harness
conjure init new --profile=python-fastapi .

# 3. Continue with GSD phases
/gsd-plan-phase phase-1
/gsd-execute-phase phase-1
```

Or for an existing project:

```bash
# 1. Conjure init to get a harness
conjure init existing .

# 2. GSD takes over for feature work
/gsd-discuss-phase
/gsd-plan-phase
/gsd-execute-phase
```

## Where Conjure hands off to GSD

Conjure is responsible for **harness** — the persistent configuration that
shapes Claude's behavior session-to-session.

GSD is responsible for **execution** — phase-by-phase work with atomic
commits and verification.

Boundary:
- Conjure writes `.claude/`, `CLAUDE.md`, `docs/ARCHITECTURE.md`, etc.
- GSD writes `.planning/`, phase plans, execution state.
- They share `docs/adr/` (architecture decisions).

## Hook integration

Conjure's Stop hook can trigger `/gsd-session-report` to generate a
session report at end-of-session — useful for milestone reviews.

```bash
# In .claude/hooks/stop-compound-engineering.sh, optionally append:
if command -v gsd >/dev/null 2>&1; then
  gsd session-report --append-to .planning/session-reports/
fi
```

## Combined audit

```bash
conjure audit        # harness health
/gsd-audit-milestone # GSD milestone health
```

Pass both before declaring a milestone complete.

## Conjure as a GSD plugin

Conjure ships with `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json`
making it installable via Claude Code's marketplace UI. GSD can declare Conjure
as a dependency in its own plugin manifest to ensure both load together.
