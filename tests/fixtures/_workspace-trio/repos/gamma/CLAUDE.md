# Gamma Repo

## Project

Gamma is the infrastructure repository for the workspace-trio test fixture.
Used by Phase 30 workspace orchestration tests.

### Constraints

- POSIX bash + Node.js .mjs hooks.
- Hooks must exit 2, never exit 1.

## Technology Stack

Minimal test harness with post-tool hook.

## Conventions

- All hooks use .mjs ESM format.
- Hooks are read-only; mutations route through conjure CLI.

## Architecture

Standard conjure harness layout with post-tool hook.
