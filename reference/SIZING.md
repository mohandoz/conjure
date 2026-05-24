# Sizing — Token Budgets

Concrete numbers. Use as audit thresholds.

## File-size caps

| Artifact | Hard cap | Practical sweet spot | Audit trigger |
| --- | --- | --- | --- |
| Root `CLAUDE.md` | 200 lines | 50-80 lines | Warn at 80, block at 100 |
| Nested `<dir>/CLAUDE.md` | 50 lines | 20-40 lines | Warn at 40 |
| Each `SKILL.md` body | 200 lines | 80-150 lines | Warn at 150 |
| Each agent definition | 80 lines | 30-50 lines | Warn at 60 |
| `.claudeignore` | 100 lines | <50 lines | Warn at 80 |
| `.claude/settings.json` | 200 lines | <100 lines | Warn at 150 |

## Token estimates (~chars/4)

| Artifact | Avg chars | Tokens |
| --- | --- | --- |
| 80-line CLAUDE.md | ~3200 | ~800 |
| 150-line SKILL.md | ~6000 | ~1500 |
| 50-line agent | ~2000 | ~500 |
| Total `.claude/` (12 skills + 6 agents + root) | ~50k | ~12.5k |

Session baseline (before your prompt): ~20k tokens. With a typical `.claude/`
load: ~32-35k. With 5 MCP servers attached: +5-10k. Workable budget for
actual conversation: 200k context → ~150-160k usable.

## Skill load behavior

- At session start: only `name:` + `description:` of every skill loads
  (~50-200 tokens per skill total).
- When Claude matches a description: BODY loads (~500-2000 tokens).
- After `/compact`: most-recent skill invocations re-attached, first 5k
  tokens each, total cap 25k.

## MCP server load behavior

- ALL tool metadata loads at session start (no progressive disclosure).
- Estimate per server: 500-3000 tokens of tool catalog.
- 5 servers ≈ 5-10k tokens of pure metadata baseline.

## When to split CLAUDE.md

- Single repo, single subsystem: ONE CLAUDE.md.
- Monorepo with `packages/<X>/<Y>/...`: nested `<package>/CLAUDE.md` per
  package that has unique conventions.
- Different test/build commands per service: subsystem CLAUDE.md mandatory.

## Total `.claude/` budget

A well-tuned setup uses about 12-15k tokens across all .claude/ files. If
yours exceeds 25k, you are paying eager-load cost on every session for
content most sessions don't use. Move to skills.

## Sources

- [How Claude remembers your project — Anthropic Docs](https://code.claude.com/docs/en/memory)
- [Designing CLAUDE.md correctly — ObviousWorks](https://www.obviousworks.ch/en/designing-claude-md-right-the-2026-architecture-that-finally-makes-claude-code-work/)
