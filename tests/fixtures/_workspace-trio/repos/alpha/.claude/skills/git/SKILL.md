---
id: git
description: Git workflow skill for managing commits, branches, and collaboration.
tools:
  - Bash
---

# Git Skill

Use this skill when working with git repositories, creating commits, managing
branches, or resolving merge conflicts.

## Commit Guidelines

- Write clear, concise commit messages in imperative mood.
- Keep commits atomic: one logical change per commit.
- Reference issue numbers when applicable.
- Use conventional commit prefixes: feat, fix, docs, chore, refactor.

## Branch Strategy

- Feature branches: `feature/<name>`
- Bug fixes: `fix/<name>`
- Always branch from the latest main/develop.
- Delete branches after merging.

## Conflict Resolution

- Prefer rebasing over merging for local branches.
- Use `git diff --staged` before each commit to review.
