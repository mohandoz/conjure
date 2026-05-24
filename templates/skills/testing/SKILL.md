---
name: testing
description: "Test framework, conventions, fixtures, snapshot/golden file patterns. Invoke when user asks to write tests, mock a dependency, or asks about test failures."
---

# testing

Frameworks: `<unit: jest/vitest/junit/pytest/...> + <integration: testcontainers/...> + <e2e: playwright/cypress/...>`.

## Layout

```
<dir>/   ← <test type>
```

| Test type | Location | Naming pattern |
| --- | --- | --- |
| Unit | `<dir>` | `*.test.<ext>` / `*Test.<ext>` |
| Integration | `<dir>` | `*IT.<ext>` |
| E2E | `<dir>` | `*.e2e.<ext>` |

## Fixtures

- Static data: `<dir>` (small inputs only — large fixtures live in `<dir>` and are gitignored / git-LFS).
- DB seed: `<file>`.
- Mock services: `<framework — wiremock / msw / responses>`.

## Conventions

- Naming: `<descriptive | given_when_then | should_*>`.
- Assertion library: `<>`.
- Mock policy: `<minimize mocks — prefer real deps via testcontainers>`.
- Determinism: seed RNG with `<value>`; freeze time with `<lib>`.
- Snapshot tests: `<location, when to update>`.

## Running a subset

```bash
<cmd to run a single test>
<cmd to run by pattern>
<cmd to run by tag/group>
```

## What NOT to mock (project rule)

- <e.g. "Never mock the database in integration tests — use Testcontainers.">

## Cross-references

- Build commands → `skills/build-deploy/SKILL.md`.
- Debugging test failures → `skills/debugging/SKILL.md`.
