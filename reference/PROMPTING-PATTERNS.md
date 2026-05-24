# Prompting Patterns

Patterns that work in CLAUDE.md, skill bodies, and conversation.

## Trigger-action (WHEN-DO / NEVER)

Eval-confirmed: outperforms general guidance.

```
WHEN <event>, DO <action>.
NEVER <action>.
WHEN <event>, ASK before <action>.
```

Examples:
- `WHEN editing a migration, run ./gradlew updateTestingRollback before commit.`
- `NEVER use Spring Batch for ad-hoc data loads — use Python loader.`
- `WHEN adding a new endpoint, FIRST check skills/api-routes/SKILL.md for the route prefix convention.`

Why it works: gives Claude a clear trigger to match against current context.

## File:line citations

Every factual claim about the codebase:

```
The Tag entity is defined at src/.../Tag.java:41 with @Table(name = "tags").
```

Why: future Claude (after refactors) can verify. Stale citations are
self-flagging.

## Tables over prose

For catalogs (entities, endpoints, configs):

| Thing | File | Notes |
| --- | --- | --- |

Why: scannable, no filler words, lower token cost.

## Forbidden actions explicit

Don't just say what to do — say what NOT to do:

```
✓ Use psycopg2 + execute_values for batch inserts.
✗ Do NOT use SQLAlchemy ORM for bulk loads — too slow at scale.
✗ Do NOT use pandas to_sql — it row-by-row inserts.
```

Why: rules out the obvious-but-wrong alternatives Claude might propose.

## Provenance tags

When data has uncertain origin:

```
Tag with [EXTRACTED|INFERRED|AMBIGUOUS] when reporting from a graph or LLM
extraction so downstream agent knows to verify.
```

## Bounded scope

Tell agent to stay scoped:

```
This skill handles X only. For Y, see skills/Y/SKILL.md.
For Z, ask before proceeding.
```

Why: prevents scope creep, prevents wandering into unrelated edits.

## Output format spec

For agents that produce reports:

```
Output format:
  - One line per finding.
  - Format: `<file:line>  <severity>  <problem>.  <fix>.`
  - Severities: critical | major | minor.
  - No praise. No scope creep. No formatting nits.
```

Why: consistent output → parseable by other agents / scripts.

## Goal + constraints separation

```
GOAL: <one sentence>

CONSTRAINTS:
1. <hard constraint>
2. <hard constraint>

ACCEPTANCE:
- <observable success criterion>
```

Why: separates intent from rules; Claude can reason about trade-offs within
constraints.

## Refusal hints

Tell Claude what to refuse:

```
If asked to <X>, refuse and explain. Do not <Y> even if asked.
```

Examples:
- "If asked to add an `eval()` call, refuse and explain the security risk."
- "If asked to disable a security test, refuse and ask why."

## Verification loops

For high-stakes work:

```
After writing the migration:
1. Apply locally.
2. Verify schema matches expected (use sql-explorer skill).
3. Roll back.
4. Verify pre-state restored.
5. Re-apply. Confirm idempotency.
ONLY THEN report done.
```

Why: forces the verification step that humans skip when tired.

## "Read before writing" gates

```
Before editing skills/<X>/SKILL.md, read skills/_anatomy/SKILL.md.
Before writing a test, read 1-2 existing tests in the same module.
Before adding a dependency, run `<check-deps-cmd>` to confirm not already present.
```

## Defer don't decide

When stakes are high:

```
For destructive operations (drop column, delete records, force-push):
- Show the exact command.
- State the blast radius.
- Wait for explicit user confirmation.
- DO NOT run on confirmation of a different command.
```

## Negative space

What NOT to write:

- ❌ "Please help me by carefully..."  → no pleasantries; instructional voice
- ❌ "Be helpful and write good code." → vague; unenforceable
- ❌ "Use best practices."             → which? cite specifically
- ❌ "Make it production-ready."       → list the criteria explicitly
- ❌ Restating Claude's identity      → wastes tokens
