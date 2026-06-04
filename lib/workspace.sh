#!/usr/bin/env bash
# lib/workspace.sh — workspace manifest helpers for Conjure.
# Sourced by scripts/workspace.sh. Never executed directly.
# Requires: jq in PATH. POSIX bash 3.2+.

# workspace_manifest_validate <manifest_path>
# Validates that a manifest file is well-formed JSON with required fields.
# Rejects absolute repo paths and relative paths that escape the workspace root.
# Exits 0 on valid, exits 2 on any validation failure (prints reason to stderr).
workspace_manifest_validate() {
  local manifest="$1"

  # Check file exists
  if [ ! -f "$manifest" ]; then
    echo "✗ manifest not found: $manifest" >&2
    return 2
  fi

  # Validate JSON
  if ! jq empty "$manifest" >/dev/null 2>&1; then
    echo "✗ manifest is not valid JSON: $manifest" >&2
    return 2
  fi

  # Check schema_version
  if ! jq -e '.schema_version' "$manifest" >/dev/null 2>&1; then
    echo "✗ manifest missing schema_version: $manifest" >&2
    return 2
  fi

  # Check repos array
  if ! jq -e '.repos | type == "array"' "$manifest" >/dev/null 2>&1; then
    echo "✗ manifest missing repos array: $manifest" >&2
    return 2
  fi

  # PATH TRAVERSAL GUARD (D-29 security threat b)
  # The manifest lives at <workspace>/.conjure-workspace.json, so the workspace
  # ROOT *is* the manifest directory — not its parent. Anchor the boundary to the
  # RESOLVED (pwd -P) manifest dir so the comparison base matches the resolved repo
  # paths even when the workspace is reached through a symlink. (CR-01)
  local manifest_dir
  manifest_dir="$(dirname "$manifest")"

  local workspace_root
  workspace_root="$(cd "$manifest_dir" 2>/dev/null && pwd -P)" || {
    echo "✗ cannot resolve workspace root from manifest dir: $manifest_dir" >&2
    return 2
  }

  local rpath resolved
  while IFS= read -r rpath; do
    # Reject degenerate path values that would target the workspace root itself
    # or a literal "null" dir (missing path key → jq emits the string "null"). (WR-04)
    case "$rpath" in
      ""|.|..|null)
        echo "✗ invalid repo path value: '$rpath'" >&2
        return 2
        ;;
    esac

    # Reject absolute paths immediately
    case "$rpath" in
      /*)
        echo "✗ absolute repo path rejected: $rpath" >&2
        return 2
        ;;
    esac

    # For relative paths: resolve against the resolved workspace root via subshell
    # cd + pwd -P. If cd fails (path does not exist), treat as safe — existence
    # check is caller's job.
    resolved="$(cd "$workspace_root/$rpath" 2>/dev/null && pwd -P)" || continue

    # Verify resolved path is the workspace root or stays under it
    case "$resolved" in
      "$workspace_root"|"$workspace_root/"*) ;; # OK — root or under root
      *)
        echo "✗ repo path escapes workspace root: $rpath (resolved: $resolved)" >&2
        return 2
        ;;
    esac
  done < <(jq -r '.repos[].path' "$manifest")

  return 0
}

# workspace_manifest_load <manifest_path_or_cwd>
# Finds and validates the workspace manifest, walking parent directories.
# If arg is a file path: validates it directly and prints its path.
# If arg is a directory: walks up looking for .conjure-workspace.json.
# Returns (prints to stdout) the resolved manifest path; exits 2 if not found or invalid.
workspace_manifest_load() {
  local arg="$1"

  if [ -f "$arg" ]; then
    workspace_manifest_validate "$arg" && echo "$arg"
    return
  fi

  if [ -d "$arg" ]; then
    local dir="$arg"
    while [ "$dir" != "/" ]; do
      if [ -f "$dir/.conjure-workspace.json" ]; then
        workspace_manifest_validate "$dir/.conjure-workspace.json" && echo "$dir/.conjure-workspace.json"
        return 0
      fi
      dir="$(dirname "$dir")"
    done
    echo "✗ no .conjure-workspace.json found in $arg or any parent directory" >&2
    return 2
  fi

  echo "✗ workspace_manifest_load: argument must be a file or directory: $arg" >&2
  return 2
}

# workspace_discover_siblings <parent_dir>
# Lists sibling directories (direct children of parent_dir) that contain a .claude/
# subdirectory. Outputs one absolute path per line to stdout.
# Exits 0 always (empty output if none found); exits 2 if parent_dir is not a directory.
workspace_discover_siblings() {
  local parent="$1"

  if [ ! -d "$parent" ]; then
    echo "✗ discover: not a directory: $parent" >&2
    return 2
  fi

  local canon_parent
  canon_parent="$(cd "$parent" && pwd -P)"

  # WR-01: `find` (without -L) does not descend into symlinked subdirectories, so a
  # workspace member exposed via a symlink (parent/linked -> /elsewhere/repo containing
  # .claude) would be silently dropped from discovery — a false "everything is monitored"
  # signal. We deliberately do NOT switch to `find -L` (it re-introduces symlink-escape
  # risk); instead we emit an explicit WARNING (to stderr) when a symlinked direct child
  # that looks like a repo is skipped, so the operator knows it is not covered. stdout
  # stays strictly canonical paths (IN-02).
  local child
  for child in "$parent"/*; do
    [ -L "$child" ] || continue
    [ -d "$child/.claude" ] || continue
    printf '  ⚠ skipping symlinked repo (not added to manifest): %s\n' "$child" >&2
  done

  # maxdepth 2: parent_dir/sibling/.claude — .claude is one level inside each sibling
  # Filter out the parent dir itself (in case parent_dir/.claude exists)
  find "$parent" -maxdepth 2 -name '.claude' -type d 2>/dev/null | while IFS= read -r claude_dir; do
    local sibling
    sibling="$(dirname "$claude_dir")"
    local canon_sibling
    canon_sibling="$(cd "$sibling" 2>/dev/null && pwd -P)" || continue
    # Exclude parent dir itself
    if [ "$canon_sibling" != "$canon_parent" ]; then
      echo "$canon_sibling"
    fi
  done | sort -u
}

# ── workspace saga state helpers (Phase 30) ───────────────────────────────────

# workspace_state_write <state_path> <jq_filter> [jq_args...]
# Atomically writes or updates the workspace saga state file.
# If state_path does not exist: builds the JSON from scratch with jq -n.
# If state_path exists: applies jq_filter to the existing file.
# Writes via a same-directory tmp file (state_path.tmp.$$) then mv — SIGKILL safe.
# On jq failure: removes tmp and returns 2 with error on stderr.
workspace_state_write() {
  local state_path="$1"; shift
  local filter="$1"; shift
  local tmp="${state_path}.tmp.$$"
  if [ -f "$state_path" ]; then
    if jq "$@" "$filter" "$state_path" > "$tmp" 2>/dev/null; then
      mv "$tmp" "$state_path"
    else
      rm -f "$tmp"
      echo "workspace_state_write: failed to update state at $state_path" >&2
      return 2
    fi
  else
    if jq -n "$@" "$filter" > "$tmp" 2>/dev/null; then
      mv "$tmp" "$state_path"
    else
      rm -f "$tmp"
      echo "workspace_state_write: failed to create state at $state_path" >&2
      return 2
    fi
  fi
}

# workspace_state_read <state_path> <jq_expr>
# Reads a jq expression from the state file, printing the result to stdout.
# Returns empty string if the file is missing or the expression yields null/missing.
# Never exits non-zero — callers use this for safe, optional field extraction.
workspace_state_read() {
  local state_path="$1"
  local jq_expr="$2"
  jq -r "${jq_expr} // empty" "$state_path" 2>/dev/null || true
}

# ws_sha_of <file>
# Cross-platform sha256 of a single file. Returns empty string if the file is missing
# (not an error exit — callers handle absence gracefully).
# tr -d '\r': on Windows Git Bash (MSYS) sha256sum can emit a CR before the line
# terminator; unstripped \r poisons string comparisons (fabricates rollback mismatch).
# No-op on macOS/Linux.
ws_sha_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" 2>/dev/null | cut -d' ' -f1 | tr -d '\r'
  else
    shasum -a 256 "$1" 2>/dev/null | cut -d' ' -f1 | tr -d '\r'
  fi
}

# workspace_state_validate <state_path>
# Validates that a workspace state file is present, is valid JSON, and contains
# the required top-level fields: run_id, phase, repos (array).
# Valid repo status values include "snapshotting" (in-progress sentinel written
# before snapshot_create is called; upgraded to "snapshotted" after it returns 0).
# workspace_state_validate does NOT reject "snapshotting" — status-level validation
# is the caller's responsibility (ws_do_rollback treats "snapshotting" with empty
# snapshot_ref as never-mutated and skips with a note).
# Exits 0 on all checks passed; returns 2 with message to stderr otherwise.
workspace_state_validate() {
  local state_path="$1"

  if [ ! -f "$state_path" ]; then
    echo "workspace_state_validate: no workspace state file: $state_path" >&2
    return 2
  fi

  if ! jq empty "$state_path" >/dev/null 2>&1; then
    echo "workspace_state_validate: invalid JSON: $state_path" >&2
    return 2
  fi

  if ! jq -e '.run_id' "$state_path" >/dev/null 2>&1; then
    echo "workspace_state_validate: missing run_id: $state_path" >&2
    return 2
  fi

  if ! jq -e '.phase' "$state_path" >/dev/null 2>&1; then
    echo "workspace_state_validate: missing phase: $state_path" >&2
    return 2
  fi

  if ! jq -e '.repos | type == "array"' "$state_path" >/dev/null 2>&1; then
    echo "workspace_state_validate: missing repos array: $state_path" >&2
    return 2
  fi

  return 0
}
