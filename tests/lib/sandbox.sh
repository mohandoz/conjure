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

# Captured once at source time: the PID of the test-runner process. mk_tmpd uses
# this to fail CLOSED from inside a command substitution (see below). $$ is the
# parent shell's PID even when expanded inside $(...), so it is the script we want
# to abort. Recorded at source time so it is stable regardless of where mk_tmpd
# is later invoked.
MK_TMPD_MAIN_PID="$$"

# mk_tmpd — create a temp directory, validate the result, and return its path.
# Fails CLOSED on mktemp failure or a non-existent result (DEBT-03/T-31-01).
# Prints the path via printf (no trailing newline), suitable for $(...) capture.
#
# Fail-closed mechanism: every caller invokes this as VAR="$(mk_tmpd)", so a bare
# `exit 2` would only terminate the $(...) subshell and let the parent continue
# with VAR="" (the original DEBT-03 footgun — WR-01). To actually abort the run we
# signal the recorded main PID with SIGTERM, then `exit 2` to tear down the
# subshell immediately. The SIGTERM propagates to the parent script (which runs
# under `set -uo pipefail`, no trap on TERM), terminating the whole suite with a
# non-zero status. This keeps the single-helper design without touching ~180 call
# sites, while honoring the documented fail-closed contract.
mk_tmpd() {
  local _d
  # Explicit template: macOS /usr/bin/mktemp without a template IGNORES $TMPDIR
  # and uses the Darwin per-user temp dir (/var/folders/...), which sandboxed or
  # managed environments may deny. A template rooted at ${TMPDIR:-/tmp} honors
  # the caller's temp dir on both BSD and GNU mktemp.
  _d="$(mktemp -d "${TMPDIR:-/tmp}/conjure-test.XXXXXXXX")"
  if [ -z "$_d" ] || [ ! -d "$_d" ]; then
    printf 'FATAL: mk_tmpd: mktemp -d failed or returned non-existent path\n' >&2
    kill -TERM "$MK_TMPD_MAIN_PID" 2>/dev/null
    exit 2
  fi
  printf '%s' "$_d"
}

# sandbox_setup <fixture_dir>
# Sets SANDBOX_DIR (global), copies fixture contents into it, exports isolation vars.
sandbox_setup() {
  local fixture_dir="$1"
  SANDBOX_DIR="$(mk_tmpd)"
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
