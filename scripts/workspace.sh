#!/usr/bin/env bash
# scripts/workspace.sh — conjure workspace subcommand worker.
# Usage: CONJURE_HOME=<path> bash workspace.sh <subcommand> [args]
# Subcommands: init [--yes] [parent_dir]
#              check <manifest_path>
#              audit [--fail-fast] <manifest_path>
#              update [--continue-on-error] [--yes] <manifest_path>
# Exit codes: 0 = success, 1 = partial-success (check/audit/update aggregate), 2 = hard error.
# NOTE: exit 1 is the SC-MANDATED aggregate partial-success for workspace check/audit/update —
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

# Script-level tempfiles (Phase 27/30 single-EXIT-trap lesson: one combined cleanup function per
# script, registered once at startup; individual functions do NOT add their own traps).
TMPJSON=""
TMPERR=""

_ws_cleanup() {
  rm -f "${TMPJSON:-}" "${TMPERR:-}"
}
trap _ws_cleanup EXIT

SUBCMD="${1:-}"
[ -z "$SUBCMD" ] && { echo "Usage: conjure workspace init|check|audit|update [args]" >&2; exit 2; }
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
  local manifest_root repo_real

  printf '\n%-30s %-15s %s\n' "REPO" "STATUS" "EXIT"
  printf '%-30s %-15s %s\n' "----" "------" "----"

  # Resolve the workspace root once (pwd -P) so the per-repo boundary re-check below
  # compares resolved paths against a resolved base. (CR-02)
  manifest_root="$(cd "$manifest_dir" 2>/dev/null && pwd -P)" || {
    echo "✗ cannot resolve workspace root: $manifest_dir" >&2
    return 2
  }

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

    # Defense-in-depth traversal re-check (CR-02): even though workspace_manifest_load
    # validated the manifest, re-confirm each repo stays under the resolved workspace root
    # before invoking a command against it. Out-of-bounds → skip with a SECURITY warning,
    # NEVER execute. Counts as partial-success like a bad-path skip.
    repo_real="$(cd "$repo_abs" 2>/dev/null && pwd -P)" || {
      printf '%-30s %-15s %s\n' "$repo_name" "SKIP" "bad-path"
      printf '  ⚠ skipping %s: cannot resolve path (%s)\n' "$repo_name" "$repo_abs" >&2
      overall_rc=1
      continue
    }
    case "$repo_real" in
      "$manifest_root"|"$manifest_root/"*) ;;
      *)
        printf '%-30s %-15s %s\n' "$repo_name" "SKIP" "out-of-bounds"
        printf '  ⚠ SECURITY: skipping %s: escapes workspace root (%s)\n' "$repo_name" "$repo_real" >&2
        overall_rc=1
        continue
        ;;
    esac

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
  local manifest_root repo_real

  printf '\n%-30s %-15s %s\n' "REPO" "STATUS" "EXIT"
  printf '%-30s %-15s %s\n' "----" "------" "----"

  # Resolve the workspace root once (pwd -P) for the per-repo boundary re-check. (CR-02)
  manifest_root="$(cd "$manifest_dir" 2>/dev/null && pwd -P)" || {
    echo "✗ cannot resolve workspace root: $manifest_dir" >&2
    return 2
  }

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

    # Defense-in-depth traversal re-check (CR-02): re-confirm each repo stays under the
    # resolved workspace root before invoking. Out-of-bounds → skip with SECURITY warning,
    # NEVER execute. Counts toward skip_count and partial-success like a bad-path skip.
    repo_real="$(cd "$repo_abs" 2>/dev/null && pwd -P)" || {
      printf '%-30s %-15s %s\n' "$repo_name" "SKIP" "bad-path"
      printf '  ⚠ skipping %s: cannot resolve path (%s)\n' "$repo_name" "$repo_abs" >&2
      skip_count=$((skip_count + 1))
      continue
    }
    case "$repo_real" in
      "$manifest_root"|"$manifest_root/"*) ;;
      *)
        printf '%-30s %-15s %s\n' "$repo_name" "SKIP" "out-of-bounds"
        printf '  ⚠ SECURITY: skipping %s: escapes workspace root (%s)\n' "$repo_name" "$repo_real" >&2
        skip_count=$((skip_count + 1))
        if [ "$overall_rc" -lt 1 ]; then
          overall_rc=1
        fi
        continue
        ;;
    esac

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

# ---------------------------------------------------------------------------
# ws_do_update <manifest_path> <manifest_dir> <continue_on_error> <yes>
# Runs `conjure update` per repo serially. Captures per-repo stdout+stderr
# to TMPERR; scans for conflict sidecar paths; emits aggregate report.
# Exit codes:
#   0 = all repos clean
#   1 = some repos have conflicts but no hard error (documented exception)
#       SC-MANDATED partial-success — mirrors check/audit aggregate exception
#   2 = hard error (stop-on-first-error hit, or other failure) or stop-on-fail
# CONTINUE_ON_ERROR=0 (default): stop after first per-repo non-zero exit.
# CONTINUE_ON_ERROR=1 (--continue-on-error): process all repos, aggregate results.
# Traversal re-check (CR-02) runs per repo before invoking conjure update.
# ---------------------------------------------------------------------------
ws_do_update() {
  local manifest_path="$1"
  local manifest_dir="$2"
  local continue_on_error="$3"
  local yes="$4"
  local overall_rc=0
  local clean_count=0 conflict_count=0 error_count=0 skip_count=0
  local repo_json repo_name repo_relpath repo_abs repo_rc repo_status
  local manifest_root repo_real sidecar_line

  # Allocate script-level tempfile for per-repo output (cleaned by _ws_cleanup on EXIT)
  TMPERR="$(mktemp)"

  # Resolve the workspace root once (pwd -P) for the per-repo boundary re-check. (CR-02)
  manifest_root="$(cd "$manifest_dir" 2>/dev/null && pwd -P)" || {
    echo "✗ cannot resolve workspace root: $manifest_dir" >&2
    return 2
  }

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
      skip_count=$((skip_count + 1))
      overall_rc=1
      # stop-on-first-error: skip counts as non-zero
      [ "$continue_on_error" -eq 0 ] && return 2
      continue
    fi

    # Defense-in-depth traversal re-check (CR-02): re-confirm each repo stays under the
    # resolved workspace root before invoking conjure update. Out-of-bounds → skip with
    # SECURITY warning, NEVER execute.
    repo_real="$(cd "$repo_abs" 2>/dev/null && pwd -P)" || {
      printf '%-30s %-15s %s\n' "$repo_name" "SKIP" "bad-path"
      printf '  ⚠ skipping %s: cannot resolve path (%s)\n' "$repo_name" "$repo_abs" >&2
      skip_count=$((skip_count + 1))
      overall_rc=1
      [ "$continue_on_error" -eq 0 ] && return 2
      continue
    }
    case "$repo_real" in
      "$manifest_root"|"$manifest_root/"*) ;;
      *)
        printf '%-30s %-15s %s\n' "$repo_name" "SKIP" "out-of-bounds"
        printf '  ⚠ SECURITY: skipping %s: escapes workspace root (%s)\n' "$repo_name" "$repo_real" >&2
        skip_count=$((skip_count + 1))
        overall_rc=1
        [ "$continue_on_error" -eq 0 ] && return 2
        continue
        ;;
    esac

    # Per-repo update invocation. Capture stdout+stderr to TMPERR for sidecar scanning.
    # Flags like --continue-on-error affect the outer loop, not the subprocess.
    repo_rc=0
    bash "$CONJURE_HOME/cli/conjure" update "$repo_abs" >"$TMPERR" 2>&1 || repo_rc=$?

    # Map exit code to status label and counters
    case "$repo_rc" in
      0)
        repo_status="clean"
        clean_count=$((clean_count + 1))
        ;;
      1)
        # exit 1 = conflict (documented exception from cmd_update D-06)
        repo_status="conflict"
        conflict_count=$((conflict_count + 1))
        if [ "$overall_rc" -lt 1 ]; then
          overall_rc=1
        fi
        ;;
      *)
        repo_status="error($repo_rc)"
        error_count=$((error_count + 1))
        overall_rc=2
        ;;
    esac

    printf '%-30s %-15s %s\n' "$repo_name" "$repo_status" "$repo_rc"

    # Surface conflict sidecars: scan TMPERR for paths matching .conjure-conflict- pattern
    if [ "$repo_rc" -eq 1 ]; then
      while IFS= read -r sidecar_line; do
        case "$sidecar_line" in
          */.conjure-conflict-*) printf '  conflict sidecar: %s\n' "$sidecar_line" ;;
        esac
      done < "$TMPERR"
    fi

    # stop-on-first-error default (CONTINUE_ON_ERROR=0)
    if [ "$continue_on_error" -eq 0 ] && [ "$repo_rc" -ne 0 ]; then
      printf '\n✗ stopping after first failure (%s); use --continue-on-error to process all repos\n' \
        "$repo_name" >&2
      return 2
    fi

  done < <(jq -c '.repos[]' "$manifest_path")

  # Aggregate summary
  printf '\n── Workspace Update Summary ──\n'
  printf '  Clean:    %d\n' "$clean_count"
  printf '  Conflict: %d\n' "$conflict_count"
  printf '  Error:    %d\n' "$error_count"
  printf '  Skip:     %d\n' "$skip_count"
  if [ "$overall_rc" -eq 0 ]; then
    echo "✓ All repos up to date."
  elif [ "$overall_rc" -eq 1 ]; then
    echo "⚠ One or more repos have conflicts (exit 1 — partial success)."
  else
    echo "✗ One or more repos encountered errors (exit 2)."
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
    REPO_COUNT="$(printf '%s\n' "$DISCOVERED" | wc -l | tr -d ' ')"
    mutate_write "$MANIFEST_PATH" "$MANIFEST_CONTENT"

    if [ "${DRY_RUN:-0}" = "1" ]; then
      # WR-03: under DRY_RUN nothing was written — do not print a false "✓ written" success.
      echo "  (dry-run) would write $REPO_COUNT repo(s) to $MANIFEST_PATH"
    else
      # WR-05: self-check the manifest we just generated against the same traversal guard
      # that check/audit rely on. If our own output fails validation, remove it and fail
      # rather than leaving an unsafe manifest on disk.
      if ! workspace_manifest_validate "$MANIFEST_PATH" >/dev/null 2>&1; then
        echo "✗ generated manifest failed validation — removing $MANIFEST_PATH" >&2
        rm -f "$MANIFEST_PATH"
        exit 2
      fi
      echo "✓ Workspace manifest written: $MANIFEST_PATH"
      echo "  Repos: $REPO_COUNT"
    fi
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

  update)
    MANIFEST_PATH="" CONTINUE_ON_ERROR=0 YES=0
    while [ $# -gt 0 ]; do
      case "$1" in
        --continue-on-error) CONTINUE_ON_ERROR=1 ;;
        --yes|-y)            YES=1 ;;
        --help|-h) echo "Usage: conjure workspace update [--continue-on-error] [--yes] <manifest_path>"; exit 0 ;;
        *) MANIFEST_PATH="$1" ;;
      esac
      shift
    done
    [ -z "$MANIFEST_PATH" ] && MANIFEST_PATH="$(pwd)"
    MANIFEST_PATH="$(workspace_manifest_load "$MANIFEST_PATH")" || exit 2
    MANIFEST_DIR="$(dirname "$MANIFEST_PATH")"
    ws_do_update "$MANIFEST_PATH" "$MANIFEST_DIR" "$CONTINUE_ON_ERROR" "$YES"
    ;;

  *)
    echo "✗ Unknown workspace subcommand: $SUBCMD" >&2
    exit 2
    ;;

esac
