#!/usr/bin/env bash
# refresh-graph.sh — rebuild or update the graphify knowledge graph.
# Usage: bash refresh-graph.sh [target-dir] [--full|--update] [--backend <name>] [--ast-only] [--setup]
#   --update (default): incremental AST-only update (graphify update .).
#   --full: full rebuild. Uses detected/forced backend if available, else AST-only.
#   --backend <name>: force semantic backend (gemini|claude|openai|deepseek|kimi).
#   --ast-only: skip LLM extraction even if keys are set.
#   --setup: idempotent integration steps (git-exclude, global merge, claude+hook install).

set -euo pipefail

TARGET=""
MODE="update"
BACKEND_FORCE=""
FORCE_AST=0
DO_SETUP=0

# POSIX arg parsing — no getopt
_next_is_backend=0
for _arg in "$@"; do
  if [ "$_next_is_backend" = "1" ]; then
    BACKEND_FORCE="$_arg"
    _next_is_backend=0
    continue
  fi
  case "$_arg" in
    --full)      MODE="full" ;;
    --update)    MODE="update" ;;
    --ast-only)  FORCE_AST=1 ;;
    --backend)   _next_is_backend=1 ;;
    --setup)     DO_SETUP=1 ;;
    -*)          ;; # ignore unknown flags
    *)           [ -z "$TARGET" ] && TARGET="$_arg" ;;
  esac
done
unset _arg _next_is_backend

TARGET="${TARGET:-$(pwd)}"
cd "$TARGET"

if ! command -v graphify >/dev/null 2>&1; then
  echo "✗ graphify not installed. Install instructions:"
  echo "  uv tool install graphify   # OR  pipx install graphify"
  exit 2
fi

# detect_backend: sets DETECTED_BACKEND in caller scope.
# Pass skip_claude=1 as first arg to bypass the claude entry.
detect_backend() {
  local _skip_claude="${1:-0}"
  DETECTED_BACKEND=""

  if [ "$FORCE_AST" = "1" ]; then
    return
  fi

  if [ -n "${GEMINI_API_KEY:-}" ]; then
    DETECTED_BACKEND="gemini"; return
  fi
  if [ "$_skip_claude" != "1" ] && [ -n "${ANTHROPIC_API_KEY:-}" ]; then
    DETECTED_BACKEND="claude"; return
  fi
  if [ -n "${OPENAI_API_KEY:-}" ]; then
    DETECTED_BACKEND="openai"; return
  fi
  if [ -n "${DEEPSEEK_API_KEY:-}" ]; then
    DETECTED_BACKEND="deepseek"; return
  fi
  if [ -n "${MOONSHOT_API_KEY:-}" ]; then
    DETECTED_BACKEND="kimi"; return
  fi
}

# Apply --backend flag override or run auto-detection
if [ -n "$BACKEND_FORCE" ] && [ "$FORCE_AST" != "1" ]; then
  DETECTED_BACKEND="$BACKEND_FORCE"
else
  detect_backend 0
fi

# Claude probe: verify anthropic Python package is available
if [ "${DETECTED_BACKEND:-}" = "claude" ]; then
  if ! python3 -c "import anthropic" 2>/dev/null; then
    echo "⚠ anthropic Python package missing — run: pip install anthropic"
    # Re-detect skipping claude
    detect_backend 1
  fi
fi

# Build dispatch
if [ "$MODE" = "full" ] || [ ! -f graphify-out/graph.json ]; then
  if [ -n "${DETECTED_BACKEND:-}" ]; then
    echo "→ Full graphify build (backend: $DETECTED_BACKEND)..."
    graphify extract . --backend "$DETECTED_BACKEND"
  else
    echo "→ Full graphify build (AST-only — no LLM backend detected)..."
    graphify update .
    echo "  Tip: export GEMINI_API_KEY / ANTHROPIC_API_KEY / OPENAI_API_KEY for semantic extraction."
  fi
else
  echo "→ Incremental update..."
  graphify update .
fi

# --setup integration steps
if [ "$DO_SETUP" = "1" ]; then
  # Step 1 — git exclude
  if [ -d .git/info ]; then
    if grep -qF "graphify-out/" .git/info/exclude 2>/dev/null; then
      echo "  (already in .git/info/exclude)"
    else
      echo "graphify-out/" >> .git/info/exclude
      echo "✓ Added graphify-out/ to .git/info/exclude"
    fi
  else
    echo "⚠ Not a git repo; skipping git exclude step."
  fi

  # Step 2 — global merge
  if [ -f graphify-out/graph.json ]; then
    REPO_TAG="$(basename "$(pwd)")"
    graphify global add graphify-out/graph.json --as "$REPO_TAG" \
      || { echo "⚠ graphify global add failed; skipping global merge."; }
    echo "✓ Merged into global graph as '$REPO_TAG'"
  else
    echo "⚠ graphify-out/graph.json not found; skipping global merge."
  fi

  # Step 3 — claude install
  graphify claude install \
    || { echo "⚠ graphify claude install failed or not supported; skipping."; }

  # Step 4 — hook install
  graphify hook install \
    || { echo "⚠ graphify hook install failed or not supported; skipping."; }
fi

echo
echo "✓ Graph at: graphify-out/graph.json"
echo "✓ Wiki at:  graphify-out/wiki/"
echo "✓ Report:   graphify-out/GRAPH_REPORT.md"
