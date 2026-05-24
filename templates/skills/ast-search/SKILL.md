---
name: ast-search
description: "Structural code search via ast-grep — finds patterns by syntax tree, not text. Invoke when user asks to find all functions matching a shape, refactor across files, or run a query like 'all async functions without try/catch'."
---

# ast-search — Structural search/replace via ast-grep

`grep` searches text. `ast-grep` searches code structure (the AST).
Examples grep can't do but ast-grep can:

- "Find every async function without a try/catch."
- "Find every React component returning null."
- "Find every `assert` in production code (non-test)."
- "Rewrite all `.then(x => ...)` to `await`."

## When to use

- Pattern-based search where text-matching gives false positives/negatives.
- Cross-file structural refactor.
- Linting beyond what your linter does.
- Generating codemods.

## When NOT to use

- Simple known string → use `Grep` (faster).
- Relationship questions → use `code-graph`.
- Whole-file understanding → use `Read`.

## Common patterns

```bash
# Find all calls to deprecated API
ast-grep --lang ts --pattern 'oldApi($$$)'

# Refactor sync to async
ast-grep --lang py --pattern 'def $FN($$$): $$$' --rewrite 'async def $FN($$$): $$$'

# Find React class components (migrate to hooks)
ast-grep --lang tsx --pattern 'class $NAME extends React.Component { $$$ }'

# All `console.log` outside test files
ast-grep --lang ts --pattern 'console.log($$$)' --globs '!**/*.test.ts'
```

## Languages supported (out of box)

JavaScript, TypeScript, TSX, Python, Java, Go, Rust, C, C++, C#, Ruby,
PHP, Bash, Lua, CSS, HTML, Kotlin, Scala, Swift. Register custom languages
via tree-sitter parsers.

## MCP integration

ast-grep has an MCP server — install once and Claude can call structural
queries without invoking the CLI manually:

```bash
# Install ast-grep
brew install ast-grep   # or cargo install ast-grep

# Then add MCP server (see reference/MCP-SERVERS.md)
```

## Gotchas

- Patterns are language-specific — declare `--lang` explicitly.
- `$VAR` matches a single node; `$$$` matches a sequence.
- For replace, the rewrite must produce valid syntax — preview with
  `--dry-run` first.

## Cross-references

- `skills/code-graph/SKILL.md` — for relationship queries (graphify).
- `skills/repo-pack/SKILL.md` — when you need full-file context.
