---
name: skill-anatomy
description: "Reference for how to write good SKILL.md files. Do NOT auto-invoke; read manually when authoring or auditing skills."
---

# How to write a SKILL.md that actually fires

## Frontmatter (mandatory)

```yaml
---
name: <kebab-case-unique>           # filename should match
description: "<one sentence — Claude matches user requests against this>"
allowed-tools: [Read, Grep, Bash]   # optional; restrict tool grants
model: sonnet | opus | haiku        # optional; override for this skill only
---
```

### Writing a Claude-matchable `description`

Bad descriptions (won't fire reliably):
- `"Database utilities."` — too vague
- `"Helpers for working with the data layer."` — no trigger phrase
- `"This skill contains information about ..."` — passive, no action

Good descriptions (concrete trigger phrases):
- `"Postgres CSV bulk-import via psycopg2 execute_values — invoke when user asks to load CSV into Postgres or write a data loader script."`
- `"Query the codebase knowledge graph — invoke when user asks where X is used, what depends on Y, or how A connects to B."`
- `"OWASP-aligned security review — invoke when user asks for a security review, audit, vulnerability scan, or before any production deploy."`

The litmus test: Could you predict, from the description alone, what user
phrase will trigger this skill? If no, rewrite.

## Body rules

- **≤200 lines.** Longer = lower adherence + higher cost.
- **Self-contained.** A reader of just this file should be able to do the task.
- **Tables over prose** for catalogs (entities, endpoints, fields).
- **Cite file:line** for every factual claim about the codebase.
- **Include forbidden actions**, not just the happy path. ("NEVER use Spring batch for this — use Python loader.")
- **Cross-reference** sibling skills via `see skills/X/SKILL.md` — never duplicate.
- **Code snippets** only when the pattern is non-obvious. Skip "hello world" examples.

## Structure that works

```markdown
---
frontmatter
---

# <Short title>

<One paragraph: what this skill is for, what problems it solves.>

## Files / commands / endpoints / entities (table)

| Thing | Where | Notes |
| --- | --- | --- |

## When to use vs when not to use

- USE when: <concrete trigger>
- DO NOT use for: <delegation hint to other skill>

## Trust / verification rules (if interacting with external data)

- <provenance handling>

## Gotchas

- <thing that bit us, with file:line evidence>
```

## Anti-patterns

- ❌ Skill named "general" or "utilities" → too broad to fire correctly.
- ❌ Skill duplicating CLAUDE.md content → wastes tokens when both load.
- ❌ Skill body that's a screenshot of the codebase → it goes stale immediately.
- ❌ Long prose paragraphs → use tables, lists, and code snippets.
- ❌ `description:` longer than 2 sentences → matching gets fuzzy.
- ❌ Forgetting to update line count after edits → audit script flags it.

## Lifecycle

A skill should be retired if:
- It hasn't fired in 90 days (you can grep your session logs).
- Its claims are >50% stale.
- It's duplicated by a sibling skill.
- A hook now enforces the same rule deterministically.

## Naming

Use kebab-case. Group by domain (`csv-import-pattern`, not `csv` or `import`).
File path is `.claude/skills/<name>/SKILL.md`. Subfolders may hold attached
resources (templates, scripts) that the skill references and Claude reads on
demand from within the skill.
