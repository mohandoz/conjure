# shellcheck shell=bash
# lib/caps.sh — sourced cap constants for Conjure.
# Source this file; do not execute directly.
# Requires: lib/mutate.sh already sourced (for mutate_archive).
# POSIX bash 3.2+. No associative arrays, no mapfile, no local -n.

# Initialize cap constants if not already set.
# Safe under set -u; idempotent on re-source.
CLAUDE_MD_CAP="${CLAUDE_MD_CAP:-100}"
SKILL_MD_CAP="${SKILL_MD_CAP:-200}"
AGENT_MD_CAP="${AGENT_MD_CAP:-80}"
