#!/usr/bin/env bash
# install-mcp-stack.sh — install recommended MCP servers for Claude Code.
# Usage: bash install-mcp-stack.sh
#
# Idempotent. Verifies each install. Does NOT add to settings — you do that
# via Claude Code's /mcp UI or by editing ~/.claude/mcp_servers.json directly.

set -uo pipefail

echo "MCP stack installer (Tier-1 essentials + optional)"
echo "──────────────────────────────────────────────────"
echo

# Check prerequisites
for tool in npx node; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "✗ $tool not found — install Node.js first (https://nodejs.org)"
    exit 1
  fi
done

install_npm_global() {
  local pkg="$1"
  echo "→ Installing $pkg..."
  if npm install -g "$pkg" 2>&1 | tail -3; then
    echo "  ✓ done"
  else
    echo "  ⚠ install failed for $pkg — install manually"
  fi
}

# Tier 1 — recommended for almost every project
echo "Tier 1 (recommended):"
install_npm_global "@upstash/context7-mcp"
install_npm_global "@modelcontextprotocol/server-sequential-thinking"
install_npm_global "@modelcontextprotocol/server-filesystem"
install_npm_global "@modelcontextprotocol/server-github"

# Tier 2 — install on demand
cat <<'EOF'

Tier 2 (install per project):
  • postgres  : npx -y @modelcontextprotocol/server-postgres <conn-string>
  • firecrawl : npm i -g firecrawl-mcp           (needs FIRECRAWL_API_KEY)
  • playwright: npm i -g @executeautomation/playwright-mcp-server
  • repomix   : npm i -g repomix

Project-local skill wrappers:
  • graphify  : uv tool install graphify   OR   pipx install graphify
  • ast-grep  : brew install ast-grep      OR   cargo install ast-grep

After install, add servers to Claude Code:
  ─ Open Claude Code, run: /mcp
  ─ Or edit: ~/.claude/mcp_servers.json (see reference/MCP-SERVERS.md for examples)

Security:
  • Use minimal-scope tokens (repo-scoped, not org-wide).
  • Use read-only DB roles for Postgres MCP.
  • Pin MCP SDK versions; subscribe to advisories (Apr 2026 RCE issue).
EOF
