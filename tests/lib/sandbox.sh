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
#   PATH             → $CONJURE_HOME/cli:[node]:[git]:[jq]:[python3]:/usr/local/bin:/usr/bin:/bin
#                      Each resolved-tool dir is empty when the tool is absent (safe
#                      no-op). git/jq/python3 are resolved dynamically because they
#                      live outside /usr/bin on Git Bash (e.g. /mingw64/bin), and a
#                      hardcoded PATH would drop them on Windows runners (WR-01).
#
# Cleanup:
#   trap 'rm -rf "$SANDBOX_DIR"' EXIT is registered inside sandbox_setup() (per D-06).
#   Fires on error, signal, and normal exit — no caller cleanup required.
#
# CONJURE_HOME is intentionally NOT overridden (per D-05, Pitfall 5).
# The kit location must stay real so CLI invocations resolve kit scripts correctly.

# _sandbox_tool_dir <name> — echo the parent dir of <name>, or nothing if absent.
# Used to keep critical tools reachable after the sandbox resets PATH, regardless
# of where they are installed (nvm/fnm/Homebrew, or /mingw64/bin on Git Bash).
_sandbox_tool_dir() {
  local _p
  _p="$(command -v "$1" 2>/dev/null || true)"
  [ -n "$_p" ] && dirname "$_p"
}

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
  # Resolve parent dirs of critical tools so installations outside /usr/bin stay
  # reachable in-sandbox. On Git Bash git/jq/python3 live in /mingw64/bin or /cmd,
  # so a hardcoded /usr/bin:/bin would drop them and break ~all Windows tests (WR-01).
  local _node_dir _git_dir _jq_dir _py_dir
  _node_dir="$(_sandbox_tool_dir node)"
  _git_dir="$(_sandbox_tool_dir git)"
  _jq_dir="$(_sandbox_tool_dir jq)"
  _py_dir="$(_sandbox_tool_dir python3)"
  export PATH="$CONJURE_HOME/cli:${_node_dir:+$_node_dir:}${_git_dir:+$_git_dir:}${_jq_dir:+$_jq_dir:}${_py_dir:+$_py_dir:}/usr/local/bin:/usr/bin:/bin"
}
