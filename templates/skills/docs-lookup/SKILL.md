---
name: docs-lookup
description: "Pull live, version-specific framework/library docs via context7 MCP instead of relying on training-data knowledge. Invoke when user asks about a specific library API, framework feature, or wants the 'latest' docs for any package."
---

# docs-lookup — Live framework docs via context7

LLM training data goes stale. context7 fetches current docs at query time.

## When to use

- "How do I do X in <library/framework>?" where the API may have changed.
- "What's the latest way to <task> in <Next.js / FastAPI / Spring Boot / ...>?"
- Before writing code against any library where minor versions matter
  (React, Next.js, Tailwind, Pydantic, SQLAlchemy, etc.).
- When you suspect Claude is using an outdated API surface.

## When NOT to use

- Standard library / language-builtin questions (Python stdlib, Java SE).
  Training data is fine.
- Architectural questions (use the graph or web research instead).
- Project-internal code (use code-graph / Read).

## Usage

context7 is an MCP server. When installed, Claude can call its tools directly.
No CLI needed.

Trigger phrases that should invoke context7 automatically:
- "use the latest <X> docs"
- "context7 <library>"
- "I'm on <library> version <Y>"

If context7 isn't connected, fall back to `skills/web-research/SKILL.md`.

## Install (one-time)

```json
// In ~/.claude/mcp_servers.json or via /mcp install
{
  "context7": {
    "command": "npx",
    "args": ["-y", "@upstash/context7-mcp"]
  }
}
```

See `reference/MCP-SERVERS.md` for the full MCP stack setup.

## Gotchas

- context7 returns Markdown; cite the URL it provides so the user can verify.
- For very obscure libraries, context7 may have no entry — fall back to
  WebFetch on the official docs URL.
- Don't dump context7 output verbatim into the final answer; extract the
  relevant snippet (saves tokens).
