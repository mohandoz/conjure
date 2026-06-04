#!/usr/bin/env bash
# scripts/workspace.sh — conjure workspace subcommand worker.
# Usage: CONJURE_HOME=<path> bash workspace.sh <subcommand> [args]
# Subcommands: init [--yes] [parent_dir]
#              check <manifest_path>
#              audit [--fail-fast] <manifest_path>
#              update [--continue-on-error] [--yes] <manifest_path>
#              adopt [--tag <tag>] [--allow-large-snapshots] [--dry-run] [--yes] [--rollback] <manifest_path>
# Exit codes: 0 = success, 1 = partial-success (check/audit/update aggregate), 2 = hard error.
# NOTE: exit 1 is the SC-MANDATED aggregate partial-success for workspace check/audit/update —
# documented exception to the project's exit-2-never-exit-1 rule (mirrors audit WARN→exit-1).
set -uo pipefail

CONJURE_HOME="${CONJURE_HOME:-$(cd "$(dirname "$0")/.." && pwd)}"

# Source helpers — lib/log.sh and lib/mutate.sh MUST be sourced before lib/snapshot.sh
# (snapshot_create calls log_step and mutate_write; sourcing order is load-order dependency).
# shellcheck source=/dev/null
source "$CONJURE_HOME/lib/workspace.sh" || { echo "✗ cannot source lib/workspace.sh" >&2; exit 2; }
# shellcheck source=/dev/null
source "$CONJURE_HOME/lib/log.sh"       || { echo "✗ cannot source lib/log.sh" >&2; exit 2; }
# shellcheck source=/dev/null
source "$CONJURE_HOME/lib/mutate.sh"    || { echo "✗ cannot source lib/mutate.sh" >&2; exit 2; }
# shellcheck source=/dev/null
source "$CONJURE_HOME/lib/snapshot.sh"  || { echo "✗ cannot source lib/snapshot.sh" >&2; exit 2; }

# DRY_RUN propagated from cmd_workspace (default 0)
DRY_RUN="${DRY_RUN:-0}"

# Script-level tempfiles (Phase 27/30 single-EXIT-trap lesson: one combined cleanup function per
# script, registered once at startup; individual functions do NOT add their own traps).
TMPJSON=""
TMPERR=""
# WR-02: WS_STATE_TMP was dead wiring — workspace_state_write uses a LOCAL tmp var and
# never assigned WS_STATE_TMP, so this trap slot always cleaned nothing. State-tmp orphans
# are now swept inside workspace_state_write itself (glob sweep on entry), which also
# handles the SIGKILL-before-mv window across concurrent runs. Slot removed.

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

# ---------------------------------------------------------------------------
# ws_do_adopt <manifest_path> <manifest_dir> <tag_filter> <allow_large> <dry_run> <yes>
# Two-phase saga orchestrator for workspace adopt (WS-06).
#
# SAGA INVARIANT: ALL repos are snapshotted (PHASE A) before ANY repo is applied
# (PHASE B). The state file records every per-repo status transition atomically
# (workspace_state_write) so that a SIGKILL between transitions leaves a durable
# breadcrumb (status="snapshotting" + empty snapshot_ref = never mutated, ws_do_rollback
# treats it as safe to skip).
#
# State machine: pending → snapshotting → snapshotted → applied|failed
#
# Exit codes: 0 = all repos applied; 2 = any failure (exit-2-never-exit-1 rule).
#   --dry-run: prints plan + disk estimate; exits 0; writes ZERO files.
# ---------------------------------------------------------------------------
ws_do_adopt() {
  local manifest_path="$1"
  local manifest_dir="$2"
  local tag_filter="$3"
  local allow_large="$4"
  local dry_run="$5"
  local yes="$6"

  # Non-TTY consent gate (mutating op): if no --yes and not a TTY and not --dry-run → exit 2.
  if [ "$yes" -eq 0 ] && [ "$dry_run" -eq 0 ]; then
    if ! [ -t 0 ]; then
      echo "✗ Not a TTY. Use --yes for non-interactive environments." >&2
      return 2
    fi
  fi

  # Resolve manifest root once (pwd -P) for CR-02 boundary re-checks.
  local manifest_root
  manifest_root="$(cd "$manifest_dir" 2>/dev/null && pwd -P)" || {
    echo "✗ ws_do_adopt: cannot resolve workspace root: $manifest_dir" >&2
    return 2
  }

  local state_path="$manifest_dir/.conjure-workspace-state.json"

  # ── Build filtered repo list ─────────────────────────────────────────────────
  # POSIX 3.2+: no associative arrays; build a newline-delimited list of jq objects.
  local repos_json
  if [ -n "$tag_filter" ]; then
    # Select only repos whose tags[] contains the given tag.
    # shellcheck disable=SC2016
    repos_json="$(jq -c --arg tag "$tag_filter" \
      '.repos[] | select(.tags != null and (.tags | index($tag) != null))' \
      "$manifest_path" 2>/dev/null)" || repos_json=""
  else
    repos_json="$(jq -c '.repos[]' "$manifest_path" 2>/dev/null)" || repos_json=""
  fi

  if [ -z "$repos_json" ]; then
    echo "ws_do_adopt: no repos to process (tag_filter='$tag_filter')" >&2
    return 2
  fi

  # ── Disk estimate (du gate) ──────────────────────────────────────────────────
  # Sum du -sk across all filtered repos; >2097152 KiB (2 GiB) → warn + exit 2
  # unless --allow-large-snapshots is set. Gate runs BEFORE any snapshot is taken.
  local total_kib=0
  local du_name du_relpath du_abs du_kib
  while IFS= read -r repo_json; do
    du_name="$(printf '%s' "$repo_json" | jq -r '.name')"
    du_relpath="$(printf '%s' "$repo_json" | jq -r '.path')"
    du_abs="$manifest_dir/$du_relpath"
    if [ -d "$du_abs" ]; then
      # Real `du -sk` emits one line: "KiB\tpath". awk sums $1 across all lines so that
      # test stubs that emit multiple lines (one per argv) still produce a correct total.
      du_kib="$(du -sk "$du_abs" 2>/dev/null | awk '{sum+=$1} END{print sum+0}')"
      du_kib="${du_kib:-0}"
      total_kib=$((total_kib + du_kib))
    fi
  done <<EOF
$repos_json
EOF

  if [ "$total_kib" -gt 2097152 ]; then
    printf '⚠ snapshot estimate: %d KiB (%d MiB) across all repos\n' \
      "$total_kib" "$((total_kib / 1024))" >&2
    if [ "$allow_large" -eq 0 ]; then
      printf '✗ snapshot too large (>2 GiB); use --allow-large-snapshots to proceed\n' >&2
      return 2
    else
      printf '⚠ --allow-large-snapshots set; proceeding despite large snapshot estimate\n' >&2
    fi
  fi

  # ── DRY_RUN path: print plan, zero writes, exit 0 ───────────────────────────
  if [ "$dry_run" -eq 1 ]; then
    echo "[dry-run] workspace adopt plan:"
    while IFS= read -r repo_json; do
      local dr_name dr_relpath
      dr_name="$(printf '%s' "$repo_json" | jq -r '.name')"
      dr_relpath="$(printf '%s' "$repo_json" | jq -r '.path')"
      printf '  [dry-run] would snapshot+adopt: %s (%s)\n' "$dr_name" "$dr_relpath"
    done <<EOF
$repos_json
EOF
    printf '[dry-run] estimated snapshot size: %d KiB\n' "$total_kib"
    local dr_count=0
    while IFS= read -r _line; do
      [ -n "$_line" ] && dr_count=$((dr_count + 1))
    done <<EOF
$repos_json
EOF
    printf '[dry-run] would snapshot %d repo(s) then adopt each\n' "$dr_count"
    return 0
  fi

  # ── Build initial repos array for state init ─────────────────────────────────
  local repos_init_json
  repos_init_json="$(printf '%s' "$repos_json" | jq -cs \
    '[.[] | {name: .name, snapshot_ref: "", sha256_pre_ref: "", status: "pending"}]' \
    2>/dev/null)" || {
    echo "✗ ws_do_adopt: failed to build repos init JSON" >&2
    return 2
  }

  # ── STATE INIT ──────────────────────────────────────────────────────────────
  local run_id
  run_id="$(printf '%s-%s' "$(date -u '+%Y%m%dT%H%M%SZ')" "$$")"
  local started_at
  started_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

  workspace_state_write "$state_path" \
    '{run_id: $rid, started: $ts, phase: "snapshot", repos: $repos}' \
    --arg rid "$run_id" --arg ts "$started_at" --argjson repos "$repos_init_json" || return 2

  # ── PHASE A: snapshot ALL repos before applying ANY ─────────────────────────
  local phase_a_failed=0
  local repo_json repo_name repo_relpath repo_abs repo_real
  local snap_ref hash_file snap_rc

  while IFS= read -r repo_json; do
    repo_name="$(printf '%s' "$repo_json" | jq -r '.name')"
    repo_relpath="$(printf '%s' "$repo_json" | jq -r '.path')"
    repo_abs="$manifest_dir/$repo_relpath"

    # Bad-path guard
    if [ ! -d "$repo_abs" ]; then
      printf '✗ PHASE A: repo not found, cannot snapshot: %s (%s)\n' "$repo_name" "$repo_abs" >&2
      workspace_state_write "$state_path" \
        '.repos = [.repos[] | if .name == $n then .status = "failed" else . end]' \
        --arg n "$repo_name" || true
      phase_a_failed=1
      break
    fi

    # CR-02 traversal re-check before snapshot
    repo_real="$(cd "$repo_abs" 2>/dev/null && pwd -P)" || {
      printf '✗ PHASE A: cannot resolve path for repo: %s\n' "$repo_name" >&2
      workspace_state_write "$state_path" \
        '.repos = [.repos[] | if .name == $n then .status = "failed" else . end]' \
        --arg n "$repo_name" || true
      phase_a_failed=1
      break
    }
    case "$repo_real" in
      "$manifest_root"|"$manifest_root/"*) ;;
      *)
        printf '✗ PHASE A SECURITY: repo escapes workspace root, aborting: %s (%s)\n' \
          "$repo_name" "$repo_real" >&2
        workspace_state_write "$state_path" \
          '.repos = [.repos[] | if .name == $n then .status = "failed" else . end]' \
          --arg n "$repo_name" || true
        phase_a_failed=1
        break
        ;;
    esac

    # PRE-WRITE: set status="snapshotting" BEFORE calling snapshot_create.
    # SIGKILL durability: if killed here, state shows "snapshotting" + empty snapshot_ref.
    # ws_do_rollback treats "snapshotting" + empty snapshot_ref as never-mutated → skip.
    workspace_state_write "$state_path" \
      '.repos = [.repos[] | if .name == $n then .status = "snapshotting" else . end]' \
      --arg n "$repo_name" || return 2

    printf '  PHASE A: snapshotting %s ...\n' "$repo_name"

    # Call snapshot_create with two positional args: target + backup_root.
    # snapshot_create sets CONJURE_SNAPSHOT_PATH in the current shell; do NOT capture stdout.
    local backup_root="$repo_abs/.conjure-adopt-backups"
    snap_rc=0
    snapshot_create "$repo_abs" "$backup_root" || snap_rc=$?
    snap_ref="$CONJURE_SNAPSHOT_PATH"

    if [ "$snap_rc" -ne 0 ] || [ -z "$snap_ref" ]; then
      printf '✗ PHASE A: snapshot failed for repo: %s\n' "$repo_name" >&2
      workspace_state_write "$state_path" \
        '.repos = [.repos[] | if .name == $n then .status = "failed" else . end]' \
        --arg n "$repo_name" || true
      phase_a_failed=1
      break
    fi

    # Compute per-file sha256 hash file (mktemp OUTSIDE the repo tree, per PATTERNS.md).
    # Store the path as sha256_pre_ref in state. ws_do_rollback needs it for zero-diff verify.
    hash_file="$(mktemp)"
    # Subshell: cd to repo_abs and enumerate the user's tree; write "hash  path" pairs.
    # CR-04: snapshot_create ran ABOVE and placed its copy of the repo INSIDE the tree at
    # .conjure-adopt-backups/conjure-adopt-<ts>/. Excluding only ./.git would hash that
    # in-tree snapshot copy too — doubling the verify set and coupling rollback
    # verification to snapshot internals. The rollback DELETION passes already exclude
    # .conjure-adopt-backups / .conjure-archive-* / .conjure-adopt-state (lines ~889/906),
    # so the hash set MUST exclude the exact same conjure-owned dirs for the two passes to
    # agree on scope. Mirror that exclusion list here.
    ( cd "$repo_abs" && find . -type f \
        -not -path './.git/*' \
        -not -path './.conjure-adopt-backups/*' \
        -not -path './.conjure-archive-*/*' \
        -not -path './.conjure-adopt-state/*' \
        | sort | while IFS= read -r f; do
        printf '%s  %s\n' "$(ws_sha_of "$f")" "$f"
      done ) > "$hash_file" 2>/dev/null || true

    # POST-WRITE: upgrade status from "snapshotting" to "snapshotted" ONLY after
    # snapshot_create returns 0. Record snapshot_ref and sha256_pre_ref.
    workspace_state_write "$state_path" \
      '.repos = [.repos[] | if .name == $n then (.status = "snapshotted" | .snapshot_ref = $sr | .sha256_pre_ref = $hf) else . end]' \
      --arg n "$repo_name" --arg sr "$snap_ref" --arg hf "$hash_file" || return 2

    printf '  PHASE A: snapshotted %s → %s\n' "$repo_name" "$snap_ref"

  done <<EOF
$repos_json
EOF

  if [ "$phase_a_failed" -eq 1 ]; then
    echo "✗ snapshot phase failed — not applying any repo" >&2
    return 2
  fi

  # ── PHASE B: apply (conjure adopt) per repo ──────────────────────────────────
  # Update top-level phase to "apply" before starting PHASE B.
  workspace_state_write "$state_path" '.phase = "apply"' || return 2

  local apply_rc
  # PHASE B iterates over the original filtered manifest repos (which have the .path field).
  # For each, check state to confirm status == "snapshotted" before applying.
  # (snapshotted_repos from state file lacks .path — use manifest as the source of truth.)

  while IFS= read -r repo_json; do
    repo_name="$(printf '%s' "$repo_json" | jq -r '.name')"
    repo_relpath="$(printf '%s' "$repo_json" | jq -r '.path')"
    repo_abs="$manifest_dir/$repo_relpath"

    # Only apply repos that successfully completed PHASE A (status == snapshotted in state).
    local repo_state_status
    repo_state_status="$(jq -r --arg n "$repo_name" \
      '.repos[] | select(.name == $n) | .status // "unknown"' "$state_path" 2>/dev/null || echo "unknown")"
    if [ "$repo_state_status" != "snapshotted" ]; then
      printf '  PHASE B: skipping %s (state=%s, expected snapshotted)\n' "$repo_name" "$repo_state_status"
      continue
    fi

    # CR-02 traversal re-check before apply
    repo_real="$(cd "$repo_abs" 2>/dev/null && pwd -P)" || {
      printf '✗ PHASE B: cannot resolve path for repo: %s\n' "$repo_name" >&2
      workspace_state_write "$state_path" \
        '.repos = [.repos[] | if .name == $n then .status = "failed" else . end]' \
        --arg n "$repo_name" || true
      echo "✗ stop-on-fail: halting adopt (repo=$repo_name)" >&2
      return 2
    }
    case "$repo_real" in
      "$manifest_root"|"$manifest_root/"*) ;;
      *)
        printf '✗ PHASE B SECURITY: repo escapes workspace root: %s (%s)\n' \
          "$repo_name" "$repo_real" >&2
        workspace_state_write "$state_path" \
          '.repos = [.repos[] | if .name == $n then .status = "failed" else . end]' \
          --arg n "$repo_name" || true
        echo "✗ stop-on-fail: halting adopt (repo=$repo_name)" >&2
        return 2
        ;;
    esac

    printf '  PHASE B: applying %s ...\n' "$repo_name"

    # Pass CONJURE_ADOPT_REUSE_SNAPSHOT=1 in the subprocess env so adopt.sh skips its
    # internal snapshot_guarded (workspace already snapshotted this repo in PHASE A —
    # prevents double-snapshot disk overhead).
    apply_rc=0
    CONJURE_ADOPT_REUSE_SNAPSHOT=1 bash "$CONJURE_HOME/cli/conjure" adopt "$repo_abs" \
      >/dev/null 2>&1 || apply_rc=$?

    if [ "$apply_rc" -eq 0 ]; then
      workspace_state_write "$state_path" \
        '.repos = [.repos[] | if .name == $n then .status = "applied" else . end]' \
        --arg n "$repo_name" || return 2
      printf '  PHASE B: applied %s ✓\n' "$repo_name"
    else
      workspace_state_write "$state_path" \
        '.repos = [.repos[] | if .name == $n then .status = "failed" else . end]' \
        --arg n "$repo_name" || true
      printf '✗ PHASE B: apply failed for repo: %s (rc=%d)\n' "$repo_name" "$apply_rc" >&2
      echo "✗ stop-on-fail: halting adopt (repo=$repo_name)" >&2
      return 2
    fi

  done <<EOF
$repos_json
EOF

  # PHASE DONE
  workspace_state_write "$state_path" '.phase = "done"' || return 2

  local applied_count snapshotted_count
  applied_count="$(jq '[.repos[] | select(.status == "applied")] | length' "$state_path" 2>/dev/null || echo 0)"
  snapshotted_count="$(jq '[.repos[] | select(.status == "snapshotted")] | length' "$state_path" 2>/dev/null || echo 0)"

  printf '\n── Workspace Adopt Summary ──\n'
  printf '  Applied:     %s\n' "$applied_count"
  printf '  Snapshotted: %s\n' "$snapshotted_count"
  echo "✓ Workspace adopt complete."
  return 0
}

# ---------------------------------------------------------------------------
# ws_do_rollback <manifest_path> <manifest_dir> <yes>
# Reads .conjure-workspace-state.json, restores each snapshotted/applied repo
# from its snapshot_ref. Skips "snapshotting" + empty snapshot_ref (never-mutated).
# Skips already "rolled_back" repos (idempotent). Updates state atomically.
# After snapshot_rollback: deletes files created by adopt (not in snapshot), prunes
# empty dirs absent from snapshot, then verifies sha256 zero-diff (per-file hash
# from sha256_pre_ref). Aggregate exit 2 if any repo fails (never exit mid-loop).
# On completion: archives the state file with a timestamp (keeps audit trail).
# Exit codes: 0 = all successful or all already rolled_back; 2 = any failure.
# ---------------------------------------------------------------------------
ws_do_rollback() {
  local manifest_path="$1"
  local manifest_dir="$2"
  local yes="$3"

  # WR-01: rollback is DESTRUCTIVE (deletes adopt-created files, prunes dirs, overwrites
  # the working tree via snapshot_rollback). Mirror the ws_do_adopt mutating-op consent
  # gate: in a non-interactive (non-TTY) environment, require --yes; otherwise refuse and
  # exit 2 (never auto-mutate many repos with zero confirmation — CLAUDE.md convention).
  if [ "$yes" -eq 0 ] && ! [ -t 0 ]; then
    echo "✗ Not a TTY. Use --yes for non-interactive rollback." >&2
    return 2
  fi

  local state_path="$manifest_dir/.conjure-workspace-state.json"

  if [ ! -f "$state_path" ]; then
    echo "✗ ws_do_rollback: no .conjure-workspace-state.json found — nothing to roll back" >&2
    return 2
  fi

  # Read state; capture repos list BEFORE any rollback modifies the file.
  # (capture-before-restore pattern: state mutations during the loop must not
  # affect the iteration list; we iterate from this captured snapshot.)
  local repos_captured
  repos_captured="$(jq -c '.repos[]' "$state_path" 2>/dev/null)" || repos_captured=""
  if [ -z "$repos_captured" ]; then
    echo "✗ ws_do_rollback: state file has no repos" >&2
    return 2
  fi

  # Idempotent all-done check: if ALL repos are already rolled_back → exit 0 no-op.
  local all_rolled_back
  all_rolled_back="$(jq 'if (.repos | map(select(.status != "rolled_back")) | length) == 0 then "yes" else "no" end' "$state_path" 2>/dev/null || echo "no")"
  if [ "$all_rolled_back" = '"yes"' ]; then
    echo "ws_do_rollback: all repos already rolled_back — no-op" >&2
    return 0
  fi

  # Resolve workspace root once (pwd -P) for CR-02 traversal re-check at restore time.
  local manifest_root
  manifest_root="$(cd "$manifest_dir" 2>/dev/null && pwd -P)" || {
    echo "✗ ws_do_rollback: cannot resolve workspace root: $manifest_dir" >&2
    return 2
  }

  local any_rb_failed=0
  local rb_json rb_name rb_snap_ref rb_sha256_pre_ref rb_status rb_abs rb_rc

  while IFS= read -r rb_json; do
    rb_name="$(printf '%s' "$rb_json" | jq -r '.name')"
    rb_snap_ref="$(printf '%s' "$rb_json" | jq -r '.snapshot_ref // ""')"
    rb_sha256_pre_ref="$(printf '%s' "$rb_json" | jq -r '.sha256_pre_ref // ""')"
    rb_status="$(printf '%s' "$rb_json" | jq -r '.status')"

    # Get abs path from manifest (manifest has .path; state file does not).
    rb_abs="$manifest_dir/$(jq -r --arg n "$rb_name" '.repos[] | select(.name == $n) | .path' "$manifest_path" 2>/dev/null)"

    # Already rolled back: skip idempotently.
    if [ "$rb_status" = "rolled_back" ]; then
      printf '  rollback: %s already rolled_back — skip\n' "$rb_name"
      continue
    fi

    # "snapshotting" + empty snapshot_ref = never mutated (SIGKILL during PHASE A
    # pre-write sentinel). adopt never ran while any repo was snapshotting — safe to
    # mark rolled_back with a note; nothing to restore.
    if [ "$rb_status" = "snapshotting" ] && [ -z "$rb_snap_ref" ]; then
      printf '  rollback: %s status=snapshotting + no snapshot_ref — never mutated, skip\n' "$rb_name"
      workspace_state_write "$state_path" \
        '.repos = [.repos[] | if .name == $n then .status = "rolled_back" else . end]' \
        --arg n "$rb_name" || true
      continue
    fi

    # "pending" = was never reached; nothing to restore.
    if [ "$rb_status" = "pending" ]; then
      printf '  rollback: %s status=pending — never snapshotted, skip\n' "$rb_name"
      workspace_state_write "$state_path" \
        '.repos = [.repos[] | if .name == $n then .status = "rolled_back" else . end]' \
        --arg n "$rb_name" || true
      continue
    fi

    # CR-03: "failed" + empty snapshot_ref = failed DURING PHASE A (bad path,
    # out-of-bounds, or snapshot_create returned non-zero) BEFORE any mutation. This repo
    # was never adopted — there is nothing to restore. Treat it identically to the
    # snapshotting/pending never-mutated branches: mark rolled_back and continue. WITHOUT
    # this, a PHASE-A failure (the most common partial-failure case) falls through to the
    # snapshot_ref guard below, sets any_rb_failed=1, and rollback returns a SPURIOUS
    # exit 2 that never clears on re-run — breaking the idempotency contract.
    # NOTE: a "failed" repo WITH a snapshot_ref (failed during PHASE B apply, after it was
    # snapshotted) is NOT skipped here — it falls through and gets restored below.
    if [ "$rb_status" = "failed" ] && [ -z "$rb_snap_ref" ]; then
      printf '  rollback: %s status=failed + no snapshot_ref — never mutated, skip\n' "$rb_name"
      workspace_state_write "$state_path" \
        '.repos = [.repos[] | if .name == $n then .status = "rolled_back" else . end]' \
        --arg n "$rb_name" || true
      continue
    fi

    # CR-02 rollback-time traversal re-check: confirm repo still within workspace root.
    local rb_real
    rb_real="$(cd "$rb_abs" 2>/dev/null && pwd -P)" || {
      printf '✗ rollback: %s — cannot resolve path (CR-02): %s\n' "$rb_name" "$rb_abs" >&2
      any_rb_failed=1
      continue
    }
    case "$rb_real" in
      "$manifest_root"|"$manifest_root/"*) ;;
      *)
        printf '✗ rollback: SECURITY: %s escapes workspace root (CR-02): %s\n' \
          "$rb_name" "$rb_real" >&2
        any_rb_failed=1
        continue
        ;;
    esac

    # Validate snapshot_ref exists before attempting restore.
    if [ -z "$rb_snap_ref" ] || [ ! -d "$rb_snap_ref" ]; then
      printf '✗ rollback: %s — snapshot_ref missing or not a dir: %s\n' "$rb_name" "$rb_snap_ref" >&2
      any_rb_failed=1
      continue
    fi

    if [ ! -d "$rb_abs" ]; then
      printf '✗ rollback: %s — target dir not found: %s\n' "$rb_name" "$rb_abs" >&2
      any_rb_failed=1
      continue
    fi

    # ── Pre-restore: evict orphaned adopt subprocesses ──────────────────────────
    # When workspace.sh is killed with SIGKILL, bash child processes (the per-repo
    # `conjure adopt` subprocess launched in PHASE B) are NOT killed — they become
    # orphans and continue writing files to the repo. ws_do_rollback must evict them
    # before (and after) the snapshot restore to avoid a TOCTOU race where the orphan
    # creates new files after the snapshot-based orphan-file deletion pass.
    # pkill -9 -f is a best-effort kill (race-free alternatives require setsid/cgroup;
    # the double-delete-pass below closes the residual window).
    #
    # CR-01: $rb_abs is interpolated into a `pkill -f` REGEX. Interpolating it raw makes
    # the path metacharacters (`.`, `+`, `(`, …) match arbitrary chars AND leaves the
    # match UNANCHORED, so `/…/repo-a` over-matches `/…/repo-abc` (a sibling NOT being
    # rolled back) and can kill unrelated processes (the test harness, a concurrent adopt).
    # Fix: regex-escape every metachar in the path, then anchor the pattern to END-OF-LINE
    # (`$`) so only a command line whose argument is EXACTLY this repo path is matched —
    # `repo-a$` cannot match `repo-abc`.
    local rb_abs_re
    rb_abs_re="$(printf '%s' "$rb_abs" | sed 's/[].[*^$()+?{}|\\]/\\&/g')"
    pkill -9 -f "conjure adopt.*${rb_abs_re}\$" 2>/dev/null || true
    pkill -9 -f "adopt\\.sh.*${rb_abs_re}\$" 2>/dev/null || true
    # Brief wait: let the OS process the SIGKILLs before we inspect the tree.
    sleep 0.05

    printf '  rollback: restoring %s from %s ...\n' "$rb_name" "$rb_snap_ref"
    rb_rc=0
    snapshot_rollback "$rb_snap_ref" "$rb_abs" || rb_rc=$?

    if [ "$rb_rc" -ne 0 ]; then
      printf '✗ rollback: restore failed for repo: %s (rc=%d)\n' "$rb_name" "$rb_rc" >&2
      any_rb_failed=1
      # Independence: do NOT exit — continue processing remaining repos.
      continue
    fi

    # D-03: snapshot_rollback tars snapshot/. into target; the snapshot dir carries
    # .snapshot-meta.json at its root and tar leaks it into the target root. Remove
    # it explicitly so the post-rollback tree is clean (mirrors adopt.sh D-03).
    rm -f "$rb_abs/.snapshot-meta.json" 2>/dev/null || true

    # ── Step 2: delete files created by adopt (absent from snapshot) ──────────
    # snapshot_rollback (tar -xpf) restores modified files but does NOT delete
    # files that adopt created fresh (they have no counterpart in the snapshot).
    # Walk the live repo tree; any file without a counterpart in rb_snap_ref was
    # created by adopt and must be removed so the post-rollback tree is byte-identical.
    # Exception: .snapshot-meta.json was already removed above (D-03).
    # Run TWO passes: the first pass deletes files visible at snapshot_rollback time;
    # the second pass catches files written by any orphaned adopt subprocess between
    # the first pass completing and now (closes the TOCTOU window from the pre-restore
    # pkill above — the orphan may have written a last burst of files before dying).
    local _f _rel _pass
    for _pass in 1 2; do
      while IFS= read -r _f; do
        [ -n "$_f" ] || continue
        _rel="${_f#"$rb_abs"/}"
        # Skip conjure's own internal dirs — they persist across rollback by convention
        # (mirrors adopt.sh rollback_path diff -r exclusion list).
        case "$_rel" in
          .conjure-adopt-backups/*|.conjure-archive-*/*|.conjure-adopt-state/*) continue ;;
        esac
        # If this file has no counterpart in the snapshot, adopt created it.
        if [ ! -e "$rb_snap_ref/$_rel" ]; then
          rm -f "$_f" 2>/dev/null || true
        fi
      done < <(find "$rb_abs" -type f \
                  -not -path "$rb_abs/.conjure-adopt-backups/*" \
                  -not -path "$rb_abs/.conjure-archive-*" \
                  -not -path "$rb_abs/.conjure-adopt-state/*" \
                  2>/dev/null)
    done

    # Bottom-up empty-dir prune: remove dirs absent from snapshot (adopt-created dirs
    # that are now empty after file deletion). rmdir is a no-op on non-empty dirs.
    local _d _drel
    while IFS= read -r _d; do
      [ -n "$_d" ] || continue
      [ "$_d" = "$rb_abs" ] && continue
      _drel="${_d#"$rb_abs"/}"
      # If the dir existed in the snapshot, leave it alone even if now empty.
      [ -d "$rb_snap_ref/$_drel" ] && continue
      rmdir "$_d" 2>/dev/null || true
    done < <(find "$rb_abs" -type d \
                -not -path "$rb_abs/.conjure-adopt-backups*" \
                -not -path "$rb_abs/.conjure-archive-*" \
                -not -path "$rb_abs/.conjure-adopt-state*" \
                2>/dev/null | awk '{ print length, $0 }' | sort -rn | cut -d' ' -f2-)

    # ── Step 3: sha256 zero-diff verify (per-file, from sha256_pre_ref) ───────
    # Mirror the Phase 22 per-file before-hash pattern. sha256_pre_ref is the path
    # to the mktemp hash file recorded by ws_do_adopt (stored outside repo tree so
    # rollback cannot clobber it). Each line: "<hash>  <relative-path>".
    local rb_mismatch=0
    if [ -n "$rb_sha256_pre_ref" ] && [ -f "$rb_sha256_pre_ref" ]; then
      local _h _frel _now
      while IFS= read -r line; do
        [ -n "$line" ] || continue
        # CR-02: each line is "<hash>  <relpath>" (two-space sep). The hash is exactly
        # 64 lowercase-hex chars, so split deterministically: hash = first 64 chars,
        # relpath = everything after the 64-char hash + its two-space separator.
        # Using `${line##*  }` (longest trailing match) TRUNCATED any relpath that itself
        # contained two consecutive spaces to its last segment, fabricating a mismatch on
        # a byte-perfect tree. `${line#*  }` strips only the FIRST two-space run, keeping
        # embedded double spaces verbatim.
        _h="${line%%  *}"
        _frel="${line#*  }"
        # WR-03: make the missing-file sentinel explicit and independent of ws_sha_of's
        # exit status — ws_sha_of returns "" (exit 0) for an absent file, so the
        # `|| echo MISSING` fallback never fired and an empty pre-hash could false-match
        # an empty current hash. Probe existence directly.
        if [ ! -e "$rb_abs/$_frel" ]; then
          _now="MISSING"
        else
          _now="$(ws_sha_of "$rb_abs/$_frel")"
        fi
        [ "$_h" = "$_now" ] || rb_mismatch=$((rb_mismatch+1))
      done < "$rb_sha256_pre_ref"
      if [ "$rb_mismatch" -gt 0 ]; then
        printf '✗ rollback: %s — sha256 mismatch: %d file(s) differ from pre-adopt hash\n' \
          "$rb_name" "$rb_mismatch" >&2
        workspace_state_write "$state_path" \
          '.repos = [.repos[] | if .name == $n then .status = "failed" else . end]' \
          --arg n "$rb_name" || true
        any_rb_failed=1
        # Independence: continue processing remaining repos.
        continue
      fi
    fi

    # All steps passed for this repo.
    workspace_state_write "$state_path" \
      '.repos = [.repos[] | if .name == $n then .status = "rolled_back" else . end]' \
      --arg n "$rb_name" || true
    printf '  rollback: %s restored ✓\n' "$rb_name"

  done <<EOF
$repos_captured
EOF

  # Archive the state file (preserve audit trail — do NOT rm -f).
  # The ORIGINAL state file remains in place with all repos status="rolled_back".
  # A timestamped COPY is created as the audit trail artifact.
  # A second --rollback invocation reads the original (still present), sees all
  # repos are rolled_back, and exits 0 (idempotent no-op).
  local archive_ts
  archive_ts="$(date -u '+%Y%m%dT%H%M%SZ')"
  local archive_name="$manifest_dir/.conjure-workspace-state-${archive_ts}.json"
  cp "$state_path" "$archive_name" 2>/dev/null || true

  if [ "$any_rb_failed" -eq 1 ]; then
    echo "✗ Rollback encountered failures — state archived to $archive_name" >&2
    return 2
  fi

  echo "✓ Workspace rollback complete — state archived to $archive_name"
  return 0
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

  adopt)
    MANIFEST_PATH="" TAG_FILTER="" ALLOW_LARGE=0 ADOPT_DRY_RUN=0 YES=0 ROLLBACK=0
    while [ $# -gt 0 ]; do
      case "$1" in
        --tag)
          TAG_FILTER="${2:-}"
          shift 2
          ;;
        --allow-large-snapshots) ALLOW_LARGE=1; shift ;;
        --dry-run)               ADOPT_DRY_RUN=1; shift ;;
        --yes|-y)                YES=1; shift ;;
        --rollback)              ROLLBACK=1; shift ;;
        --help|-h)
          echo "Usage: conjure workspace adopt [--tag <tag>] [--allow-large-snapshots] [--dry-run] [--yes] [--rollback] <manifest_path>"
          exit 0
          ;;
        *) MANIFEST_PATH="$1"; shift ;;
      esac
    done
    [ -z "$MANIFEST_PATH" ] && MANIFEST_PATH="$(pwd)"
    MANIFEST_PATH="$(workspace_manifest_load "$MANIFEST_PATH")" || exit 2
    MANIFEST_DIR="$(dirname "$MANIFEST_PATH")"
    if [ "$ROLLBACK" -eq 1 ]; then
      ws_do_rollback "$MANIFEST_PATH" "$MANIFEST_DIR" "$YES"
    else
      ws_do_adopt "$MANIFEST_PATH" "$MANIFEST_DIR" "$TAG_FILTER" "$ALLOW_LARGE" "$ADOPT_DRY_RUN" "$YES"
    fi
    ;;

  *)
    echo "✗ Unknown workspace subcommand: $SUBCMD" >&2
    exit 2
    ;;

esac
