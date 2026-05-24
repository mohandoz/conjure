---
name: domain-model
description: "Catalog of every domain entity / type / schema with file paths and one-line purpose. Invoke when user asks 'what does X represent', 'where is Y entity defined', or 'list all entities'."
---

# domain-model

All entities under `<base package>`. Common base class: `<BaseEntity>` (provides
<id, version, timestamps, audit fields>).

## Catalog

### <Sub-domain 1>

| Entity | File | Table/Type | Purpose |
| --- | --- | --- | --- |
| `<Name>` | `<file:line>` | `<table>` | <one-line> |

### <Sub-domain 2>

| Entity | File | Table/Type | Purpose |
| --- | --- | --- | --- |

## Key relationships (high-level)

```
<A> ──1:N── <B>
<B> ──M:N── <C>  (via join table <D>)
```

For deep detail on a hot data cluster, see `skills/<cluster>-model/SKILL.md`.

## Enum reference

- `<EnumName>`: `<value1>`, `<value2>`, ... (defined in `<file:line>`)

## Conventions

- Entity field naming: <convention>
- Audit fields: <where they come from>
- ID strategy: <auto-increment | UUID | composite>
- Soft delete: <yes/no, how>
