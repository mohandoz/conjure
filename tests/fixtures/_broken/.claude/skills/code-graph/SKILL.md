---
name: code-graph
description: "Query the persistent codebase knowledge graph (graphify) instead of grep/read. Invoke when user asks where X is used, what depends on Y, how A connects to B, or 'give me an overview of <module>'. Requires graphify-out/ to exist."
---

# code-graph — Query the project knowledge graph

The graph at `graphify-out/graph.json` was built by graphify and survives
across sessions. Query it instead of reading raw files when the question is
about relationships.

## When to use

- "What calls / depends on / references <X>?"
- "How are <A> and <B> connected?"
- "Explain <module/file/concept>."
- "Give me an architecture overview."
- "Find non-obvious coupling between <area1> and <area2>."

## When NOT to use

- Specific file content → use Read tool.
- Single-symbol lookup with exact name → use Grep or ast-search skill.
- Live runtime behavior → graph is static; read code or run the program.

## Commands

| Goal | Command |
| --- | --- |
| Broad context (BFS) | `graphify query "<question>"` |
| Specific path (DFS) | `graphify query "<question>" --dfs` |
| Bounded answer | `graphify query "<question>" --budget 1500` |
| Shortest path between concepts | `graphify path "<A>" "<B>"` |
| Plain-language node explanation | `graphify explain "<node>"` |
| Read audit report | `cat graphify-out/GRAPH_REPORT.md` |
| Read community article | `cat graphify-out/wiki/<community>.md` |

## Trust rules (provenance)

The graph tags each edge:

| Tag | Meaning | What to do |
| --- | --- | --- |
| `EXTRACTED` | Found in actual code/docs | Trust, but verify the file:line still exists. |
| `INFERRED` | Graph's best guess | Treat as hypothesis; verify before acting. |
| `AMBIGUOUS` | Multiple plausible meanings | Ignore unless user explicitly asks. |

NEVER recommend an action based on an `INFERRED` edge without first reading
the source file to confirm.

## Freshness check

Before relying on the graph, check staleness:

```bash
# If >7 days old OR >20 commits since the graph was built, refresh:
graphify . --update
```

The `--update` mode is incremental — only re-extracts changed files.

## Falling back

If `graphify-out/` does not exist:
- Note this clearly to the user.
- Offer to run `graphify . --mode deep --wiki --mcp` (takes 10-20 min on
  ~200-file projects).
- For one-off queries, fall back to: `repo-pack` skill (full codebase dump),
  `ast-search` skill (structural search), or vanilla Grep/Read.

## Cross-references

- `skills/repo-pack/SKILL.md` — when you need the full codebase in one file.
- `skills/ast-search/SKILL.md` — when you need a structural pattern, not a
  relationship query.

## Gotchas

- Graph nodes use canonical names (often file path or fully-qualified symbol).
  If `explain "Foo"` returns nothing, try `explain "src/foo/Foo.ts"` or look
  up the canonical form in `GRAPH_REPORT.md`.
- Community labels are auto-generated; they may not match human terminology.
  Read the community article body, not just the title.
- Cross-repo graphs (built with `graphify merge-graphs`) carry a `repo`
  attribute on each node — filter by it when querying.
