---
name: repo-pack
description: "Pack the entire codebase into a single AI-friendly file via repomix. Invoke when user wants a full repo dump for review, audit, or external LLM, or when graphify isn't available and broad understanding is needed."
---

# repo-pack — Full-codebase context dump via repomix

Repomix packs a repo (or sub-tree) into one structured file. Includes
tree-sitter compression option (~70% token reduction) preserving structure.

## When to use

- "Give me a full repo overview" when no graph exists yet.
- Preparing context for an external LLM/audit.
- Code review of a small subtree (`packages/<name>`).
- Investigation of a bug that crosses many files.

## When NOT to use

- Targeted relationship queries → `code-graph`.
- Specific file → `Read`.
- Pattern search → `ast-search` or `Grep`.
- Live framework docs → `docs-lookup`.

## Usage

```bash
# Pack current directory into repomix-output.xml
repomix

# Pack a subtree
repomix --include "src/**/*.ts"

# Compressed (tree-sitter, ~70% smaller)
repomix --compress

# Specific output format
repomix --style xml         # default; AI-friendly
repomix --style markdown
repomix --style plain
```

## MCP integration

`repomix-mcp` exposes three tools to Claude:
- `pack_codebase` — pack a directory.
- `read_repomix_output` — read packed output with line range.
- `grep_repomix_output` — grep within packed output (preferred over full
  read for large dumps).

```bash
# Install
npm i -g repomix
# MCP setup in reference/MCP-SERVERS.md
```

## Token budgeting

A typical 100-file TS repo packs to ~50k-150k tokens uncompressed; ~15k-45k
with `--compress`. For repos larger than that, use `--include` to scope or
prefer code-graph queries.

## Security note

Repomix integrates `Secretlint` — it WILL refuse to pack files containing
secrets. Don't disable this. If it flags something, fix the leak first.

## Cross-references

- `skills/code-graph/SKILL.md` — for relationship-style queries (cheaper).
- `skills/ast-search/SKILL.md` — for structural queries (cheaper).
