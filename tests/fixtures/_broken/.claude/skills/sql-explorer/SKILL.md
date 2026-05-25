---
name: sql-explorer
description: "Introspect database schema and run safe read-only queries via Postgres MCP / pg CLI. Invoke when user asks about table structure, foreign keys, indexes, row counts, or 'what does the data look like'."
---

# sql-explorer — Database introspection

Read DB schema and sample data without leaving Claude Code.

## When to use

- "What columns are on table <X>?"
- "What references <table>?"
- "How many rows in <table>?"
- "Show me a sample of <table>."
- "Is index <name> being used?"
- Before writing a migration — confirm current shape.

## When NOT to use

- Writes / DDL → ALWAYS use the migration tool (Liquibase / Alembic /
  Flyway / Diesel) so the change is versioned.
- Sensitive data — DO NOT log PII. Mask or aggregate.
- Production DB without explicit user confirmation — read-only role only.

## Safe query patterns

```sql
-- Column inventory
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = '<TABLE>'
ORDER BY ordinal_position;

-- Foreign keys IN
SELECT tc.table_name AS referencing, kcu.column_name, ccu.table_name AS referenced
FROM information_schema.table_constraints tc
JOIN information_schema.key_column_usage kcu USING (constraint_name, table_schema)
JOIN information_schema.constraint_column_usage ccu USING (constraint_name, table_schema)
WHERE tc.constraint_type = 'FOREIGN KEY' AND ccu.table_name = '<TABLE>';

-- Index usage
SELECT indexrelname, idx_scan, idx_tup_read
FROM pg_stat_user_indexes
WHERE relname = '<TABLE>'
ORDER BY idx_scan DESC;

-- Sample (cheap)
SELECT * FROM <TABLE> ORDER BY id DESC LIMIT 5;
```

## Postgres MCP install

```json
{
  "postgres": {
    "command": "npx",
    "args": ["-y", "@modelcontextprotocol/server-postgres", "postgresql://user:pass@host/db"]
  }
}
```

⚠️ **Schema-dump cost.** `get_schema_info` without filtering can dump tens
of thousands of tokens (200+ tables). Always scope by `--table <name>` or
filter to a specific schema.

## Read-only enforcement

Connect via a Postgres role with `CONNECT` + `SELECT` only:
```sql
CREATE ROLE ai_readonly NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT LOGIN;
GRANT CONNECT ON DATABASE <db> TO ai_readonly;
GRANT USAGE ON SCHEMA public TO ai_readonly;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO ai_readonly;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO ai_readonly;
```

Use this role's credentials in the MCP config, not a superuser.

## Cross-references

- `skills/database-schema/SKILL.md` — migration writing (Liquibase / etc).
- `skills/data-access/SKILL.md` — repository code that consumes this schema.
