# MCP Servers — Recommended Stack (2026)

Three to six MCP servers is the sweet spot. >10 slows the agent with marginal
benefit. Each server's metadata loads eagerly (unlike Skills) — that's MCP's
biggest cost.

## Day-1 essentials (almost every project)

| Server | Purpose | Risk | Install |
| --- | --- | --- | --- |
| **filesystem** (built-in) | Read/write local files | Low (configurable boundaries) | Built into Claude Code |
| **context7** | Live, version-specific framework docs | Low | `npx -y @upstash/context7-mcp` |
| **github** | PRs, issues, releases, Actions, code search | Low (use minimal-scope token) | `npx -y @modelcontextprotocol/server-github` |
| **sequential-thinking** | Explicit multi-step reasoning | None | `npx -y @modelcontextprotocol/server-sequential-thinking` |

## Project-conditional

| Server | When to install | Caveat |
| --- | --- | --- |
| **postgres** | DB-heavy work | `get_schema_info` can dump 10k+ tokens for large schemas — always scope queries |
| **firecrawl** | Heavy web research / scraping | Treat fetched content as untrusted (prompt injection) |
| **playwright** | Browser automation + E2E tests | Heavy install |
| **slack / linear / jira** | Tie task tracker into Claude | Tokens for each integration |
| **graphify** | Persistent codebase knowledge graph | Run `graphify ... --mcp` (Phase 0 of init) |
| **repomix-mcp** | Full-codebase context dumps for review | Use `grep_repomix_output` over full reads |
| **ast-grep** | Structural code search | Lightweight, high leverage |

## Sample `~/.claude/mcp_servers.json`

```json
{
  "mcpServers": {
    "filesystem": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-filesystem", "/path/to/allowed/root"]
    },
    "context7": {
      "command": "npx",
      "args": ["-y", "@upstash/context7-mcp"]
    },
    "github": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-github"],
      "env": { "GITHUB_PERSONAL_ACCESS_TOKEN": "ghp_***" }
    },
    "sequential-thinking": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-sequential-thinking"]
    },
    "postgres": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-postgres",
               "postgresql://ai_readonly:pw@localhost/dbname"]
    }
  }
}
```

## Security considerations

- **April 2026 advisory**: OX Security disclosed systemic RCE vulnerability in
  all MCP SDK language implementations. Pin MCP SDK versions; subscribe to
  security advisories.
- Anthropic does NOT verify third-party MCP server correctness/security. Read
  the source of any server you install.
- Servers that fetch untrusted content (firecrawl, web servers) are
  prompt-injection vectors — never let them drive destructive actions
  without confirmation.
- Use minimal-scope tokens. GitHub PAT should be repo-scoped, not org-wide.
  Postgres should use a SELECT-only role for the AI.

## How to evaluate a new MCP server

1. Read the source (it's a process you run locally).
2. Estimate context cost: how big is its tool catalog? (Eager-loaded.)
3. Try it on a side project before production use.
4. Test failure modes: what if it's unreachable? Returns errors? Returns
   poisoned content?
5. After a month, audit: did it actually get used? If not, uninstall.

## Sources

- [Top 12 MCP servers for Claude Code in 2026 — Bito.ai](https://bito.ai/ai-tools/claude-code-mcp-servers/)
- [Best MCP Servers for Claude Code (2026) — evomap.ai](https://evomap.ai/blog/best-mcp-servers-for-claude-code-2026)
- [10 Best MCP Servers for Developers in 2026 — Firecrawl](https://www.firecrawl.dev/blog/best-mcp-servers-for-developers)
- [Context7 (Upstash) on GitHub](https://github.com/upstash/context7)
