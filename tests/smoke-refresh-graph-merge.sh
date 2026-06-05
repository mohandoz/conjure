#!/usr/bin/env bash
# Smoke test for scripts/refresh-graph.sh --merge / --setup
# Usage: bash tests/smoke-refresh-graph-merge.sh
# Exit 0 if all scenarios pass; exit 2 if any fail.

set -uo pipefail

# Locate refresh-graph.sh: check same-dir parent, then env var, then PATH
if [ -n "${CONJURE_HOME:-}" ] && [ -f "$CONJURE_HOME/scripts/refresh-graph.sh" ]; then
  REFRESH_SCRIPT="$CONJURE_HOME/scripts/refresh-graph.sh"
else
  _try="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)/scripts/refresh-graph.sh"
  if [ -f "$_try" ]; then
    REFRESH_SCRIPT="$_try"
  else
    # Last resort: search upward from cwd for scripts/refresh-graph.sh
    _cwd="$(pwd)"
    while [ "$_cwd" != "/" ]; do
      if [ -f "$_cwd/scripts/refresh-graph.sh" ]; then
        REFRESH_SCRIPT="$_cwd/scripts/refresh-graph.sh"
        break
      fi
      _cwd="$(dirname "$_cwd")"
    done
  fi
  unset _try _cwd
fi
if [ -z "${REFRESH_SCRIPT:-}" ] || [ ! -f "$REFRESH_SCRIPT" ]; then
  echo "ERROR: cannot locate scripts/refresh-graph.sh — set CONJURE_HOME or run from repo root" >&2
  exit 2
fi

TMPD="${TMPDIR:-/tmp}/rg-smoke-$$"
mkdir -p "$TMPD"

PASS_COUNT=0
FAIL_COUNT=0

pass() { echo "PASS: $1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { echo "FAIL: $1 — $2"; FAIL_COUNT=$((FAIL_COUNT+1)); }

# Create a stub binary directory; stubs record their calls to a log file.
STUBBIN="$TMPD/bin"
mkdir -p "$STUBBIN"

# Stub: graphify — records all args to $CALL_LOG; writes fake graph.json if asked
cat > "$STUBBIN/graphify" <<'STUB'
#!/usr/bin/env bash
echo "graphify $*" >> "$CALL_LOG"
# If this is an update/extract call in a directory that has graphify-out/, create graph.json
if [ "$1" = "update" ] || [ "$1" = "extract" ]; then
  mkdir -p graphify-out
  echo '{}' > graphify-out/graph.json
fi
exit 0
STUB
chmod +x "$STUBBIN/graphify"

# Stub: jq — minimal implementation for .repos[].path extraction
cat > "$STUBBIN/jq" <<'STUB'
#!/usr/bin/env bash
# Only handles: jq -r '.repos[].path' <file>
if [ "$1" = "-r" ] && [ "$2" = ".repos[].path" ] && [ -f "$3" ]; then
  # Parse the JSON manually with grep/sed for portability
  grep '"path"' "$3" | sed 's/.*"path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/'
  exit 0
fi
exit 2
STUB
chmod +x "$STUBBIN/jq"

# Stub: git — records calls; can simulate git repo or not
cat > "$STUBBIN/git" <<'STUBEOF'
#!/usr/bin/env bash
echo "git $*" >> "$CALL_LOG"
if [ "$1" = "rev-parse" ] && [ "$2" = "--git-dir" ]; then
  if [ "${GIT_IS_REPO:-0}" = "1" ]; then
    echo ".git"
    exit 0
  else
    exit 1
  fi
fi
# Pass through other git commands (not needed in test dirs)
exit 0
STUBEOF
chmod +x "$STUBBIN/git"

export PATH="$STUBBIN:$PATH"

# ---------------------------------------------------------------------------
# Scenario (a): --setup must NOT call global add or merge-graphs
# ---------------------------------------------------------------------------
SCENARIO_A="$TMPD/scenario-a"
mkdir -p "$SCENARIO_A/.git/info"
mkdir -p "$SCENARIO_A/graphify-out"
echo '{}' > "$SCENARIO_A/graphify-out/graph.json"

CALL_LOG="$TMPD/call-log-a.txt"
export CALL_LOG
rm -f "$CALL_LOG"
touch "$CALL_LOG"

GIT_IS_REPO=1 export GIT_IS_REPO
if bash "$REFRESH_SCRIPT" "$SCENARIO_A" --setup >/dev/null 2>&1; then
  if grep -q "global add" "$CALL_LOG" 2>/dev/null; then
    fail "(a) --setup" "graphify global add was called"
  elif grep -q "merge-graphs" "$CALL_LOG" 2>/dev/null; then
    fail "(a) --setup" "graphify merge-graphs was called"
  else
    pass "(a) --setup does not call global add or merge-graphs"
  fi
else
  fail "(a) --setup" "script exited non-zero"
fi

# ---------------------------------------------------------------------------
# Scenario (b): --merge with .conjure-workspace.json + 2 member graphs
# ---------------------------------------------------------------------------
SCENARIO_B="$TMPD/scenario-b"
mkdir -p "$SCENARIO_B/graphify-out"
mkdir -p "$SCENARIO_B/repo1/graphify-out"
echo '{}' > "$SCENARIO_B/repo1/graphify-out/graph.json"
mkdir -p "$SCENARIO_B/repo2/graphify-out"
echo '{}' > "$SCENARIO_B/repo2/graphify-out/graph.json"
# Relative paths in the manifest (relative to workspace root)
cat > "$SCENARIO_B/.conjure-workspace.json" <<JSON
{
  "repos": [
    { "path": "$SCENARIO_B/repo1" },
    { "path": "$SCENARIO_B/repo2" }
  ]
}
JSON

CALL_LOG="$TMPD/call-log-b.txt"
export CALL_LOG
rm -f "$CALL_LOG"
touch "$CALL_LOG"

GIT_IS_REPO=0 export GIT_IS_REPO
if bash "$REFRESH_SCRIPT" "$SCENARIO_B" --merge >/dev/null 2>&1; then
  if grep -q "merge-graphs" "$CALL_LOG" 2>/dev/null; then
    # Verify both graph paths appear
    if grep "merge-graphs" "$CALL_LOG" | grep -q "repo1/graphify-out/graph.json" && \
       grep "merge-graphs" "$CALL_LOG" | grep -q "repo2/graphify-out/graph.json"; then
      pass "(b) --merge with manifest merges both member graphs"
    else
      fail "(b) --merge with manifest" "merge-graphs called but member graph paths missing"
    fi
  else
    fail "(b) --merge with manifest" "merge-graphs was not called"
  fi
else
  fail "(b) --merge with manifest" "script exited non-zero"
fi

# ---------------------------------------------------------------------------
# Scenario (c): --merge inside a git repo (Mode C — single repo)
# ---------------------------------------------------------------------------
SCENARIO_C="$TMPD/scenario-c"
mkdir -p "$SCENARIO_C/.git/info"
mkdir -p "$SCENARIO_C/graphify-out"
echo '{}' > "$SCENARIO_C/graphify-out/graph.json"

CALL_LOG="$TMPD/call-log-c.txt"
export CALL_LOG
rm -f "$CALL_LOG"
touch "$CALL_LOG"

GIT_IS_REPO=1 export GIT_IS_REPO
STDOUT_C="$TMPD/stdout-c.txt"
if bash "$REFRESH_SCRIPT" "$SCENARIO_C" --merge >"$STDOUT_C" 2>&1; then
  if grep -q "single repo" "$STDOUT_C"; then
    if grep -q "merge-graphs" "$CALL_LOG" 2>/dev/null; then
      fail "(c) --merge single repo" "merge-graphs was called unexpectedly"
    else
      pass "(c) --merge in single git repo prints info and skips merge"
    fi
  else
    fail "(c) --merge single repo" "expected 'single repo' message not found in stdout"
  fi
else
  fail "(c) --merge single repo" "script exited non-zero"
fi

# ---------------------------------------------------------------------------
# Scenario (d): --merge with fewer than 2 graphs (Mode A, only 1 graph exists)
# ---------------------------------------------------------------------------
SCENARIO_D="$TMPD/scenario-d"
mkdir -p "$SCENARIO_D/graphify-out"
mkdir -p "$SCENARIO_D/repo1/graphify-out"
echo '{}' > "$SCENARIO_D/repo1/graphify-out/graph.json"
mkdir -p "$SCENARIO_D/repo2"
# repo2 has no graphify-out/graph.json
cat > "$SCENARIO_D/.conjure-workspace.json" <<JSON
{
  "repos": [
    { "path": "$SCENARIO_D/repo1" },
    { "path": "$SCENARIO_D/repo2" }
  ]
}
JSON

CALL_LOG="$TMPD/call-log-d.txt"
export CALL_LOG
rm -f "$CALL_LOG"
touch "$CALL_LOG"

GIT_IS_REPO=0 export GIT_IS_REPO
STDOUT_D="$TMPD/stdout-d.txt"
if bash "$REFRESH_SCRIPT" "$SCENARIO_D" --merge >"$STDOUT_D" 2>&1; then
  if grep -q "fewer than 2" "$STDOUT_D"; then
    if grep -q "merge-graphs" "$CALL_LOG" 2>/dev/null; then
      fail "(d) --merge fewer than 2" "merge-graphs was called unexpectedly"
    else
      pass "(d) --merge with fewer than 2 member graphs warns and skips"
    fi
  else
    fail "(d) --merge fewer than 2" "expected 'fewer than 2' warning not found in stdout"
  fi
else
  fail "(d) --merge fewer than 2" "script exited non-zero"
fi

# ---------------------------------------------------------------------------
# Clean up
# ---------------------------------------------------------------------------
rm -rf "$TMPD"

echo
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
if [ "$FAIL_COUNT" -gt 0 ]; then
  exit 2
fi
exit 0
