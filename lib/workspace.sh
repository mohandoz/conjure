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
  local manifest_dir
  manifest_dir="$(dirname "$manifest")"

  local workspace_root
  workspace_root="$(cd "$manifest_dir/.." 2>/dev/null && pwd -P)" || {
    echo "✗ cannot resolve workspace root from manifest dir: $manifest_dir" >&2
    return 2
  }

  local rpath resolved
  while IFS= read -r rpath; do
    # Reject absolute paths immediately
    case "$rpath" in
      /*)
        echo "✗ absolute repo path rejected: $rpath" >&2
        return 2
        ;;
    esac

    # For relative paths: resolve via subshell cd + pwd -P
    # If cd fails (path does not exist), treat as safe — existence check is caller's job
    resolved="$(cd "$manifest_dir/$rpath" 2>/dev/null && pwd -P)" || continue

    # Verify resolved path stays under workspace root
    case "$resolved" in
      "$workspace_root/"*) ;; # OK — stays under workspace root
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
