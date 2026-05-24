---
name: api-routes
description: "REST/GraphQL/RPC endpoint catalog with route prefix and responsibility. Invoke when user asks 'where is endpoint X', 'how to add a new route', or 'what controllers exist'."
---

# api-routes

All HTTP endpoints under `<package>`. Default content-type `application/json`.
Versioning: `<scheme — e.g. /api/v1, header-based>`.

## Catalog

| Controller | Route prefix | File | Responsibility |
| --- | --- | --- | --- |
| `<Name>` | `<prefix>` | `<file:line>` | <one-line> |

## Conventions

- Validation: `<framework — bean validation / pydantic / zod>`. Rules in `<dir>`.
- Errors: throw `<ExceptionType>` subclasses; central handler converts to HTTP.
- DTOs: never return entities; use `<DTO/projection convention>`.
- Pagination: `<style — cursor / offset>`, default size `<N>`.
- Auth: `<scheme>`, configured in `<file>`.

## Adding a new endpoint

1. Define DTO(s) in `<dir>`.
2. Add controller method in `<dir>`.
3. Add validation rules in `<dir>`.
4. Add service-layer method behind interface (`<dir>`).
5. Add integration test in `<dir>` matching naming `<pattern>`.
6. Update OpenAPI spec at `<path>` if applicable.

## Cross-references

- Underlying data layer → `skills/data-access/SKILL.md`.
- Entities returned → `skills/domain-model/SKILL.md`.
