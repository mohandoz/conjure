#!/usr/bin/env bash
# scripts/workspace.sh — conjure workspace subcommand worker.
# Usage: CONJURE_HOME=<path> bash workspace.sh <subcommand> [args]
# Subcommands: init [--yes] [parent_dir]
#              check <manifest_path>
#              audit [--fail-fast] <manifest_path>
# Exit codes: 0 = success, 1 = partial-success (check/audit aggregate), 2 = hard error.
# NOTE: exit 1 is the SC-MANDATED aggregate partial-success for workspace check/audit —
# documented exception to the project's exit-2-never-exit-1 rule (mirrors audit WARN→exit-1).
set -uo pipefail

CONJURE_HOME="${CONJURE_HOME:-$(cd "$(dirname "$0")/.." && pwd)}"

# Source helpers
# shellcheck source=/dev/null
source "$CONJURE_HOME/lib/workspace.sh" || { echo "✗ cannot source lib/workspace.sh" >&2; exit 2; }
# shellcheck source=/dev/null
source "$CONJURE_HOME/lib/mutate.sh"    || { echo "✗ cannot source lib/mutate.sh" >&2; exit 2; }

# DRY_RUN propagated from cmd_workspace (default 0)
DRY_RUN="${DRY_RUN:-0}"

# Script-level tempfile for ws_do_audit (Phase 27 single-EXIT-trap lesson: one combined
# cleanup function per script, registered once at startup; ws_do_audit does NOT add its own trap).
TMPJSON=""

_ws_cleanup() {
  rm -f "${TMPJSON:-}"
}
trap _ws_cleanup EXIT

SUBCMD="${1:-}"
[ -z "$SUBCMD" ] && { echo "Usage: conjure workspace init|check|audit" >&2; exit 2; }
shift

# ---------------------------------------------------------------------------
# ws_do_check <manifest_path> <manifest_dir>
# Reads repos from manifest, runs conjure check --porcelain per repo, emits table.
# Exit codes:
#   0 = all repos clean
#   1 = any repo drifted, errored, or skipped (partial-success, fail-tolerant)
#       SC-MANDATED documented exception — partial aggregate, not a hard failure
#   2 = hard error (invalid manifest, etc.) — only from caller, not from this function
# Per-repo exit 2 (check schema error) maps to OVERALL_RC=1 (fail-tolerant).
# CONJURE_HOME is inherited by subprocesses; --porcelain passed as argv flag (not env var)
# because cmd_check in cli/conjure initializes porcelain=0 from its own argv, overriding any
# inherited CONJURE_PORCELAIN env var.
# ---------------------------------------------------------------------------
ws_do_check() {
  local manifest_path="$1"
  local manifest_dir="$2"
  local overall_rc=0
  local repo_json repo_name repo_relpath repo_abs repo_rc repo_status porcelain_out

  printf '\n%-30s %-15s %s\n' "REPO" "STATUS" "EXIT"
  printf '%-30s %-15s %s\n' "----" "------" "----"

  while IFS= read -r repo_json; do
    repo_name="$(printf '%s' "$repo_json" | jq -r '.name')"
    repo_relpath="$(printf '%s' "$repo_json" | jq -r '.path')"
    repo_abs="$manifest_dir/$repo_relpath"

    # Bad-path guard: skip with warning, set partial-success
    if [ ! -d "$repo_abs" ]; then
      printf '%-30s %-15s %s\n' "$repo_name" "SKIP" "bad-path"
      printf '  ⚠ skipping %s: path not found (%s)\n' "$repo_name" "$repo_abs" >&2
      overall_rc=1
      continue
    fi

    # Per-repo check invocation — MUST pass --porcelain as an argv flag, NOT via env var.
    # cmd_check in cli/conjure initializes porcelain=0 from scratch on every invocation,
    # silently overriding any inherited CONJURE_PORCELAIN env var.
    repo_rc=0
    porcelain_out="$(bash "$CONJURE_HOME/cli/conjure" check --porcelain "$repo_abs" 2>/dev/null)" \
      || repo_rc=$?

    # Map exit code to status label
    # Per-repo exit 2 (schema error) → OVERALL_RC=1 (partial-success, not hard failure)
    case "$repo_rc" in
      0) repo_status="clean" ;;
      1) repo_status="drift"; overall_rc=1 ;;
      2) repo_status="error"; overall_rc=1 ;;
      *) repo_status="error($repo_rc)"; overall_rc=1 ;;
    esac

    printf '%-30s %-15s %s\n' "$repo_name" "$repo_status" "$repo_rc"

  done < <(jq -c '.repos[]' "$manifest_path")

  printf '\n'
  if [ "$overall_rc" -eq 0 ]; then
    echo "✓ All repos clean."
  else
    echo "⚠ One or more repos have drift or errors (exit 1 — partial success)."
  fi

  return "$overall_rc"
}

# ---------------------------------------------------------------------------
# ws_do_audit <manifest_path> <manifest_dir> <fail_fast>
# Reads repos from manifest, runs conjure audit --json per repo, emits pass/fail table
# and global summary.
# Exit codes:
#   0 = all repos passed
#   1 = at least one warn but no fail (SC-MANDATED documented exception for warn-only aggregate)
#   2 = at least one fail (or any hard error)
# Does NOT register its own EXIT trap — uses script-level TMPJSON + _ws_cleanup.
# Per-repo invocation uses --json argv flag (not env var) because cmd_audit initializes
# do_json=0 from its own argv, overriding any inherited CONJURE_JSON env var.
# ---------------------------------------------------------------------------
ws_do_audit() {
  local manifest_path="$1"
  local manifest_dir="$2"
  local fail_fast="$3"
  local overall_rc=0
  local fail_count=0
  local warn_count=0
  local pass_count=0
  local skip_count=0
  local repo_json repo_name repo_relpath repo_abs repo_rc repo_status table_status

  printf '\n%-30s %-15s %s\n' "REPO" "STATUS" "EXIT"
  printf '%-30s %-15s %s\n' "----" "------" "----"

  # Allocate script-level tempfile for this run (cleaned up by _ws_cleanup on EXIT)
  TMPJSON="$(mktemp)"

  while IFS= read -r repo_json; do
    repo_name="$(printf '%s' "$repo_json" | jq -r '.name')"
    repo_relpath="$(printf '%s' "$repo_json" | jq -r '.path')"
    repo_abs="$manifest_dir/$repo_relpath"

    # Bad-path guard: skip with warning, continue processing rest
    if [ ! -d "$repo_abs" ]; then
      printf '%-30s %-15s %s\n' "$repo_name" "SKIP" "bad-path"
      printf '  ⚠ skipping %s: path not found (%s)\n' "$repo_name" "$repo_abs" >&2
      skip_count=$((skip_count + 1))
      continue
    fi

    # Per-repo audit --json invocation — MUST pass --json as an argv flag, NOT via env var.
    # cmd_audit in cli/conjure initializes do_json=0 from scratch on every invocation,
    # silently overriding any inherited CONJURE_JSON env var.
    repo_rc=0
    bash "$CONJURE_HOME/cli/conjure" audit --json "$repo_abs" \
      >"$TMPJSON" 2>/dev/null || repo_rc=$?

    # Parse .status from captured JSON output; validate JSON first
    repo_status="unknown"
    if jq empty "$TMPJSON" >/dev/null 2>&1; then
      repo_status="$(jq -r '.status // "unknown"' "$TMPJSON" 2>/dev/null || echo "unknown")"
    fi

    # Map status to display label and counters
    case "$repo_status" in
      pass)
        pass_count=$((pass_count + 1))
        table_status="pass"
        ;;
      warn)
        warn_count=$((warn_count + 1))
        table_status="warn"
        if [ "$overall_rc" -lt 1 ]; then
          overall_rc=1
        fi
        ;;
      fail)
        fail_count=$((fail_count + 1))
        table_status="FAIL"
        overall_rc=2
        ;;
      *)
        table_status="error($repo_rc)"
        fail_count=$((fail_count + 1))
        overall_rc=2
        ;;
    esac

    printf '%-30s %-15s %s\n' "$repo_name" "$table_status" "$repo_rc"

    # --fail-fast: abort at first failure
    if [ "$fail_fast" -eq 1 ] && [ "$overall_rc" -eq 2 ]; then
      printf '\n✗ --fail-fast: aborting after first failure (%s)\n' "$repo_name" >&2
      return 2
    fi

  done < <(jq -c '.repos[]' "$manifest_path")

  # Global summary
  printf '\n── Workspace Audit Summary ──\n'
  printf '  Pass:  %d\n' "$pass_count"
  printf '  Warn:  %d\n' "$warn_count"
  printf '  Fail:  %d\n' "$fail_count"
  printf '  Skip:  %d\n' "$skip_count"
  if [ "$overall_rc" -eq 0 ]; then
    echo "✓ All repos passed."
  elif [ "$overall_rc" -eq 1 ]; then
    echo "⚠ Warnings only (exit 1 — partial success)."
  else
    echo "✗ One or more repos FAILED audit (exit 2)."
  fi

  return "$overall_rc"
}

case "$SUBCMD" in

  init)
    # Parse flags
    YES=0
    TARGET="$(pwd)"
    while [ $# -gt 0 ]; do
      case "$1" in
        --yes)     YES=1 ;;
        --help|-h) echo "Usage: conjure workspace init [--yes] [parent_dir]"; exit 0 ;;
        *)         TARGET="$1" ;;
      esac
      shift
    done

    # Canonicalize TARGET
    TARGET="$(cd "$TARGET" 2>/dev/null && pwd -P)" || {
      echo "✗ workspace init: not a valid directory: $TARGET" >&2
      exit 2
    }

    # Non-TTY guard: require --yes in non-interactive environments
    if [ "$YES" -eq 0 ]; then
      if ! [ -t 0 ]; then
        echo "✗ Not a TTY. Use --yes for non-interactive environments." >&2
        exit 2
      fi
    fi

    # Discover sibling repos
    DISCOVERED="$(workspace_discover_siblings "$TARGET")" || exit 2
    if [ -z "$DISCOVERED" ]; then
      echo "✗ No sibling directories with .claude/ found under $TARGET." >&2
      exit 2
    fi

    # Validate-before-write: all discovered paths must be valid directories
    while IFS= read -r rpath; do
      if [ ! -d "$rpath" ]; then
        echo "✗ invalid repo path: $rpath" >&2
        exit 2
      fi
    done <<EOF
$DISCOVERED
EOF

    # TTY prompt (only when YES=0 and we confirmed TTY above)
    if [ "$YES" -eq 0 ]; then
      printf '\nDiscovered repos with .claude/:\n'
      while IFS= read -r rpath; do
        printf '  %s\n' "$rpath"
      done <<EOF
$DISCOVERED
EOF
      printf '\nWrite .conjure-workspace.json? [y/N] '
      REPLY=""
      read -r REPLY </dev/tty || REPLY=""
      case "$REPLY" in
        [yY]*) ;;
        *) echo "Aborted." >&2; exit 2 ;;
      esac
    fi

    # Build manifest JSON
    TIMESTAMP="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    REPOS_JSON=""
    FIRST=1
    while IFS= read -r rpath; do
      rname="$(basename "$rpath")"
      # Compute relative path: strip TARGET/ prefix
      rel="${rpath#"$TARGET/"}"
      REPO_ENTRY="$(jq -cn --arg name "$rname" --arg path "$rel" --argjson tags "[]" '{name:$name,path:$path,tags:$tags}')"
      if [ "$FIRST" -eq 1 ]; then
        REPOS_JSON="$REPO_ENTRY"
      else
        REPOS_JSON="$REPOS_JSON,$REPO_ENTRY"
      fi
      FIRST=0
    done <<EOF
$DISCOVERED
EOF

    MANIFEST_CONTENT="$(jq -cn --argjson sv 1 --arg gen "$TIMESTAMP" --argjson repos "[$REPOS_JSON]" '{schema_version:$sv,generated:$gen,repos:$repos}')"

    # Write via mutate_write
    MANIFEST_PATH="$TARGET/.conjure-workspace.json"
    mutate_write "$MANIFEST_PATH" "$MANIFEST_CONTENT"
    echo "✓ Workspace manifest written: $MANIFEST_PATH"
    REPO_COUNT="$(printf '%s\n' "$DISCOVERED" | wc -l | tr -d ' ')"
    echo "  Repos: $REPO_COUNT"
    ;;

  check)
    MANIFEST_PATH=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --help|-h) echo "Usage: conjure workspace check <manifest_path>"; exit 0 ;;
        *)         MANIFEST_PATH="$1" ;;
      esac
      shift
    done
    [ -z "$MANIFEST_PATH" ] && MANIFEST_PATH="$(pwd)"
    MANIFEST_PATH="$(workspace_manifest_load "$MANIFEST_PATH")" || exit 2
    MANIFEST_DIR="$(dirname "$MANIFEST_PATH")"
    ws_do_check "$MANIFEST_PATH" "$MANIFEST_DIR"
    ;;

  audit)
    MANIFEST_PATH=""
    FAIL_FAST=0
    while [ $# -gt 0 ]; do
      case "$1" in
        --fail-fast) FAIL_FAST=1 ;;
        --help|-h)   echo "Usage: conjure workspace audit [--fail-fast] <manifest_path>"; exit 0 ;;
        *)           MANIFEST_PATH="$1" ;;
      esac
      shift
    done
    [ -z "$MANIFEST_PATH" ] && MANIFEST_PATH="$(pwd)"
    MANIFEST_PATH="$(workspace_manifest_load "$MANIFEST_PATH")" || exit 2
    MANIFEST_DIR="$(dirname "$MANIFEST_PATH")"
    ws_do_audit "$MANIFEST_PATH" "$MANIFEST_DIR" "$FAIL_FAST"
    ;;

  *)
    echo "✗ Unknown workspace subcommand: $SUBCMD" >&2
    exit 2
    ;;

esac
