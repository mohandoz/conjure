---
name: build-deploy
description: "Build, test, package, and deploy commands plus CI/CD layout. Invoke when user asks 'how do I run tests', 'how is this deployed', or before any release work."
---

# build-deploy

## Build & test

| Goal | Command | Notes |
| --- | --- | --- |
| Build | `<cmd>` | <expected duration> |
| Build (no tests) | `<cmd>` | |
| Unit tests | `<cmd>` | |
| Integration tests | `<cmd>` | <requires Docker?> |
| Lint | `<cmd>` | |
| Format | `<cmd>` | |
| Type check | `<cmd>` | |
| Coverage | `<cmd>` | |

## Run locally

```bash
<cmd>
```

Dependencies: `<docker-compose up | local DB | mock services>`.

## CI/CD

Pipeline file: `<.github/workflows/... | bitbucket-pipelines.yml | .gitlab-ci.yml>`.

Stages:
1. <stage> — <duration>
2. <stage>
3. <stage>

Triggered on: `<branches / tags>`.
Required checks before merge: `<list>`.

## Deployment targets

| Env | URL | Trigger | Auth |
| --- | --- | --- | --- |

## Containerization

`<Dockerfile>` — base image: `<image>`.
Multi-stage: `<yes/no>`.

## Toolchain

- Language version: `<version>` (pinned in `<file>`).
- Build tool: `<gradle/maven/npm/poetry/cargo/etc>` version `<>`.

## Cross-references

- Release process → `skills/release/SKILL.md`.
- Debugging issues → `skills/debugging/SKILL.md`.
