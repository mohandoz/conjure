#!/usr/bin/env bash
# refresh-graph.sh — rebuild or update the graphify knowledge graph.
# Usage: bash refresh-graph.sh [target-dir] [--full|--update]
#   --update (default): incremental, only changed files.
#   --full: full rebuild (slower, use after large refactors).

set -euo pipefail

TARGET="${1:-$(pwd)}"
MODE="${2:---update}"

cd "$TARGET"

if ! command -v graphify >/dev/null 2>&1; then
  echo "✗ graphify not installed. Install instructions:"
  echo "  uv tool install graphify   # OR  pipx install graphify"
  exit 1
fi

if [ ! -f graphify-out/graph.json ] || [ "$MODE" = "--full" ]; then
  echo "→ Full graphify build (this takes 5-20 min on a 100-500 file repo)..."
  graphify . --mode deep --wiki --mcp
else
  echo "→ Incremental update..."
  graphify . --update
fi

echo
echo "✓ Graph at: graphify-out/graph.json"
echo "✓ Wiki at:  graphify-out/wiki/"
echo "✓ Report:   graphify-out/GRAPH_REPORT.md"
