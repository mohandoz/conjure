#!/usr/bin/env bash
# lib/mutate.sh — sourced mutation chokepoint for Conjure.
# Source this file; call mutate_mkdir, mutate_cp, mutate_write, mutate_summary.
# Requires: DRY_RUN env var (0=live, 1=dry); set -u safe via ${DRY_RUN:-0}.
# POSIX bash 3.2+ compatible. No associative arrays, no mapfile, no local -n.
#
# Usage from any script:
#   source "$CONJURE_HOME/lib/mutate.sh"
#   mutate_mkdir  <dir>
#   mutate_cp     <src> <dest>
#   mutate_write  <dest> <content> [--append]
#   mutate_summary   # call at end of each script

# Initialize dry-run mutation counter if not already set.
# Safe under set -u; idempotent on re-source.
CONJURE_DRY_MUTATION_COUNT="${CONJURE_DRY_MUTATION_COUNT:-0}"

# mutate_mkdir <dir>
# In dry-run: prints [dry-run] would mkdir <dir>, increments counter.
# In live mode: runs mkdir -p.
mutate_mkdir() {
  if [ "${DRY_RUN:-0}" = "1" ]; then
    echo "[dry-run] would mkdir $1"
    CONJURE_DRY_MUTATION_COUNT=$((CONJURE_DRY_MUTATION_COUNT + 1))
    return 0
  fi
  mkdir -p "$1"
}

# mutate_cp <src> <dest>
# In dry-run: prints [dry-run] would cp <src> <dest>, increments counter.
# In live mode: uses cp -r for directories, plain cp for files.
mutate_cp() {
  if [ "${DRY_RUN:-0}" = "1" ]; then
    echo "[dry-run] would cp $1 $2"
    CONJURE_DRY_MUTATION_COUNT=$((CONJURE_DRY_MUTATION_COUNT + 1))
    return 0
  fi
  if [ -d "$1" ]; then
    cp -r "$1" "$2"
  else
    cp "$1" "$2"
  fi
}

# mutate_write <dest> <content> [--append]
# In dry-run: prints [dry-run] would write <dest>, increments counter.
# In live mode: writes or appends content using printf (portable, no echo -e/-n quirks).
# Pass content as a string arg — never pipe (pipe = subshell = lost counter).
mutate_write() {
  local dest="$1"
  local content="$2"
  local mode="${3:-}"
  if [ "${DRY_RUN:-0}" = "1" ]; then
    echo "[dry-run] would write $dest"
    CONJURE_DRY_MUTATION_COUNT=$((CONJURE_DRY_MUTATION_COUNT + 1))
    return 0
  fi
  if [ "$mode" = "--append" ]; then
    printf '%s\n' "$content" >> "$dest"
  else
    printf '%s\n' "$content" > "$dest"
  fi
}

# mutate_summary
# Prints a summary line when DRY_RUN=1 or when any mutations were suppressed.
# Call at the end of each script that sources this library.
# Checking the counter (> 0) handles the case where DRY_RUN was set only as a
# per-command prefix for individual mutate_* calls rather than exported persistently.
mutate_summary() {
  if [ "${DRY_RUN:-0}" = "1" ] || [ "${CONJURE_DRY_MUTATION_COUNT:-0}" -gt 0 ]; then
    echo "[dry-run] ${CONJURE_DRY_MUTATION_COUNT} mutations skipped — run without --dry-run to apply"
  fi
}
