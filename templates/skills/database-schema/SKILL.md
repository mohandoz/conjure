---
name: database-schema
description: "Schema migration tool (Liquibase/Alembic/Flyway/etc), changelog files, key tables, audit patterns. Invoke when user asks to write a migration, add a column, or understand a table."
---

# database-schema

Migration tool: `<Liquibase | Alembic | Flyway | Diesel | Prisma | ...>`.
Master changelog: `<path>`.

## Connection (local dev)

```
url:      <jdbc:postgresql://...>
username: <...>
password: <... — note if stored in plain config>
```

⚠️ Note any mismatch between Spring/app DB and tooling DB.

## Changelog layout

```
<dir>/
  <master.xml | env.py | ...>
  <v0.5.xml>   ← <initial schema>
  <v0.6.xml>   ← <feature group>
```

## Key tables

| Table | Purpose | Notable constraints |
| --- | --- | --- |

## Audit pattern

<Describe: triggers? sibling history tables? event sourcing? audit columns?>

## Custom DB types

| Type | Used by | Notes |
| --- | --- | --- |

## Writing a new migration

1. Create a new changeset under `<dir>` named `<naming convention>`.
2. Include rollback / downgrade — ALWAYS testable.
3. Run `<command>` locally to apply.
4. Run `<command>` to test rollback.
5. Verify with `skills/sql-explorer/SKILL.md` queries.

## Common upsert templates

```sql
-- Standard upsert
INSERT INTO <table> (...) VALUES %s
ON CONFLICT (<unique-key>) DO UPDATE
SET <col> = EXCLUDED.<col>, updated_at = NOW();
```

## Cross-references

- Live introspection → `skills/sql-explorer/SKILL.md`.
- Repository layer → `skills/data-access/SKILL.md`.
