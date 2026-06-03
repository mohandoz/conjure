#!/usr/bin/env bash
# scripts/workspace.sh — conjure workspace subcommand worker.
# Usage: CONJURE_HOME=<path> bash workspace.sh <subcommand> [args]
# Subcommands: init [--yes] [parent_dir]
#              check <manifest_path>  (Wave 2)
#              audit [--fail-fast] <manifest_path>  (Wave 2)
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

SUBCMD="${1:-}"
[ -z "$SUBCMD" ] && { echo "Usage: conjure workspace init|check|audit" >&2; exit 2; }
shift

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
    echo "✗ workspace check: not yet implemented (Wave 2)" >&2
    exit 2
    ;;

  audit)
    echo "✗ workspace audit: not yet implemented (Wave 2)" >&2
    exit 2
    ;;

  *)
    echo "✗ Unknown workspace subcommand: $SUBCMD" >&2
    exit 2
    ;;

esac
