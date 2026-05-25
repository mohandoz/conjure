# shellcheck shell=bash
# tests/lib/sandbox.sh — sourced sandbox isolation helper for Conjure test suite.
# Source this file (do NOT execute directly — no shebang).
# POSIX bash 3.2+ compatible. No associative arrays, no mapfile, no local -n.
#
# Usage:
#   source "$CONJURE_HOME/tests/lib/sandbox.sh"
#   sandbox_setup <fixture_dir>
#
# Public function:
#   sandbox_setup <fixture_dir>
#     Copies fixture_dir contents into a fresh temp dir and exports environment
#     variables so audit runs are isolated from the developer's real $HOME.
#
# Output variable:
#   SANDBOX_DIR — global, set by sandbox_setup(); path to the temp directory
#
# Env vars exported by sandbox_setup():
#   HOME             → $SANDBOX_DIR
#   XDG_CONFIG_HOME  → $SANDBOX_DIR
#   CLAUDE_CONFIG_DIR → $SANDBOX_DIR
#   PATH             → $CONJURE_HOME/cli:[resolved-node-dir]:/usr/local/bin:/usr/bin:/bin
#                      resolved-node-dir is empty when node is not in PATH (safe no-op).
#
# Cleanup:
#   trap 'rm -rf "$SANDBOX_DIR"' EXIT is registered inside sandbox_setup() (per D-06).
#   Fires on error, signal, and normal exit — no caller cleanup required.
#
# CONJURE_HOME is intentionally NOT overridden (per D-05, Pitfall 5).
# The kit location must stay real so CLI invocations resolve kit scripts correctly.

# sandbox_setup <fixture_dir>
# Sets SANDBOX_DIR (global), copies fixture contents into it, exports isolation vars.
sandbox_setup() {
  local fixture_dir="$1"
  SANDBOX_DIR="$(mktemp -d)"
  trap 'rm -rf "$SANDBOX_DIR"' EXIT
  cp -r "$fixture_dir/." "$SANDBOX_DIR/"
  export HOME="$SANDBOX_DIR"
  export XDG_CONFIG_HOME="$SANDBOX_DIR"
  export CLAUDE_CONFIG_DIR="$SANDBOX_DIR"
  # Resolve node's parent directory so nvm/fnm/volta/Homebrew installations remain
  # reachable inside the sandbox. Falls back gracefully when node is absent (WR-01).
  local _node_dir
  _node_dir="$(dirname "$(command -v node 2>/dev/null || true)" 2>/dev/null || true)"
  export PATH="$CONJURE_HOME/cli:${_node_dir:+$_node_dir:}/usr/local/bin:/usr/bin:/bin"
}
