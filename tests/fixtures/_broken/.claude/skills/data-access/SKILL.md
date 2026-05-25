---
name: data-access
description: "Repository / DAO / query-layer catalog. Invoke when user asks 'how do I query X', 'where is the repo for Y', or before writing a new repo."
---

# data-access

<One-paragraph description: ORM/data layer used, repository pattern, transaction strategy.>

## Repository catalog

| Repository | Entity | File | Notes |
| --- | --- | --- | --- |

## Query strategy

| Use case | Tool |
| --- | --- |
| Simple CRUD | <ORM / Active Record / etc> |
| Complex joins | <QueryDSL / Criteria API / raw SQL> |
| Bulk inserts | <JDBC batch / COPY / etc> |
| Read-heavy aggregations | <materialized view / read replica> |

## Transaction conventions

- Service layer manages transactions; repos do not start them.
- Read-only operations use `<annotation/decorator>`.
- Isolation level: `<default>`.
- Avoid `<anti-pattern — e.g. lazy loading outside session>`.

## Performance gotchas (codebase-specific)

- <thing that bit us, with file:line>

## Cross-references

- DB schema → `skills/database-schema/SKILL.md`.
- Read-only introspection → `skills/sql-explorer/SKILL.md`.
