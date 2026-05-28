# shellcheck shell=bash
# lib/log.sh — RESTRUCTURE-LOG.md writer for Conjure adopt.
# Source this file; requires lib/mutate.sh already sourced and DRY_RUN set.
# POSIX bash 3.2+. No associative arrays, no mapfile, no local -n.

# Module-level state: RESTRUCTURE_LOG_PATH is set by log_init or by caller before log_step.
# Safe under set -u; idempotent on re-source.
RESTRUCTURE_LOG_PATH="${RESTRUCTURE_LOG_PATH:-}"

# log_init <target_dir>
# Creates a fresh RESTRUCTURE-LOG.md at <target_dir>/RESTRUCTURE-LOG.md.
# Writes a YAML-ish header with conjure, target, started, and --- separator.
# Sets RESTRUCTURE_LOG_PATH to <target_dir>/RESTRUCTURE-LOG.md.
# Uses mutate_write (not --append) — replaces any existing log.
# DRY_RUN is honored via mutate_write.
log_init() {
  local target_dir="$1"
  local ts
  ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  RESTRUCTURE_LOG_PATH="${target_dir}/RESTRUCTURE-LOG.md"
  local header="conjure: adopt
target: ${target_dir}
started: ${ts}
---
"
  mutate_write "${RESTRUCTURE_LOG_PATH}" "${header}"
}

# log_step <phase> <message>
# Appends a timestamped entry to RESTRUCTURE_LOG_PATH via mutate_write --append.
# Entry format: [TIMESTAMP] [PHASE] message
# CRITICAL: entry includes a trailing newline so consecutive calls produce separate lines.
# DRY_RUN is honored via mutate_write internally — no separate guard needed here.
log_step() {
  local phase="$1"
  local message="$2"
  local ts
  ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  local entry="[${ts}] [${phase}] ${message}
"
  mutate_write "${RESTRUCTURE_LOG_PATH}" "${entry}" --append
}

# log_fail <message>
# Appends a FAIL entry via log_step, then exits 2.
# Per CLAUDE.md constraint: hooks and lib fatal errors use exit 2, never exit 1.
log_fail() {
  local message="$1"
  log_step "FAIL" "${message}"
  exit 2
}
