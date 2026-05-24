---
name: architecture
description: "Project package/module layout, layering rules, and where to wire new services. Invoke when user asks 'how is this project organized', 'where does X go', or before adding a new service/module/package."
---

# architecture

<One paragraph describing the project: stack, entry point, layering convention.
e.g. "Spring Boot 3.4 / Java 17 orchestrator. Entry: OrchestratorApplication.java.
Two-tier split: api/ (contracts, entities, DTOs) and implementation/ (Spring beans).">

## Package layout

```
<root>/
  <dir1>/   ← <purpose>
  <dir2>/   ← <purpose>
```

| Sub-package | Holds |
| --- | --- |
| `<path>` | <what lives here> |

## Layering rules (NON-NEGOTIABLE)

1. <Layer A> depends only on <Layer B>. NEVER call <Layer C> directly.
2. Entities never leave their layer — controllers return DTOs/projections.
3. Cross-domain joins go through service composition, not entity relations.

## Where new code goes

| Adding… | Goes in | Example |
| --- | --- | --- |
| REST endpoint | `<path>` | `<example file>` |
| Background job | `<path>` | `<example file>` |
| External client | `<path>` | `<example file>` |
| Domain entity | `<path>` | `<example file>` |

## External integrations

| System | Client | Notes |
| --- | --- | --- |
| <name> | `<file:line>` | <protocol, base URL property> |

## Cross-references

- For entity details → `skills/domain-model/SKILL.md`.
- For HTTP routes → `skills/api-routes/SKILL.md`.
- For messaging → `skills/messaging/SKILL.md`.
- For schema/migrations → `skills/database-schema/SKILL.md`.
