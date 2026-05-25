# Roadmap: Conjure

## Completed Milestones

- **v0.3.0** — "Testing + Telemetry" — 7 phases, 22 plans, 20/20 requirements satisfied, 169 commits (2026-05-24 → 2026-05-25) — [Archive](.planning/milestones/v0.3.0-ROADMAP.md)

## Active Milestone

None yet. Run `/gsd-new-milestone` to start v0.4.0.

## Backlog

### Distribution & Ecosystem (v0.4.0 candidates)

- Publish to Claude Code Marketplace via `.claude-plugin/marketplace.json` (DIST-01)
- Homebrew formula (`brew install conjure`) (DIST-02)
- Docker image with all tools preinstalled (DIST-03)
- `conjure publish-skill <name>` — contribute project skill to kit (DIST-04)
- Org overlay system (base kit + private overlay repo per org) (DIST-05)

### Future Milestones

- v0.5.0 — Auto-update 3-way merge, drift detector, auto-PR bot (needs frozen schemas first)
- v0.6.0 — Workspace / cross-repo graph orchestration (single-repo correctness first)

### Tech Debt (from v0.3.0)

- `cmd_update --apply` 3-way merge implementation (cli/conjure:171 — placeholder stub)
- Nyquist compliance pass for phases 01, 02, 04, 05, 06, 07
- Phase 07 VALIDATION.md creation
- SUMMARY.md `requirements-completed` frontmatter for phases 04–07
- Windows CI runtime confirmation for TEST-06 (push to GitHub)
