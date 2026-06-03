# shellcheck shell=bash
# compliance/soc2/policy.sh — regime deny-path data for conjure emit-policy.
# Source this file; do not execute directly.
# Sets: REGIME_DENY_READ (newline-separated), REGIME_DENY_WRITE, REGIME_ALLOWED_DOMAINS.
# POSIX bash 3.2+. No associative arrays, no mapfile, no local -n.

# Per-regime delta paths only. Baseline (secrets/keys/.env/credential dirs) is added by emit-policy.sh.

# SOC 2 delta paths — narrower; SOC 2 is process-oriented
REGIME_DENY_READ="
**/audit-logs/**
**/access-logs/**
"

REGIME_DENY_WRITE="
**/audit-logs/**
"

REGIME_ALLOWED_DOMAINS=""
