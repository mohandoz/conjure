---
id: docs
description: Documentation skill for writing and maintaining project documentation.
tools:
  - Read
  - Write
---

# Documentation Skill

Use this skill when creating or updating project documentation, READMEs,
architecture docs, or runbooks.

## Documentation Standards

- Use clear, concise language targeted at the intended audience.
- Include code examples where applicable.
- Keep documentation close to the code it describes.

## File Conventions

- READMEs go in the repo root or relevant subdirectory.
- Architecture decision records (ADRs) go in `docs/adr/`.
- Runbooks go in `docs/runbooks/`.

## Maintenance

- Update docs as part of the PR that introduces a change.
- Mark stale docs with a `> **Note:** This document is outdated.` block.
