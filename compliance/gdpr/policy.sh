# shellcheck shell=bash
# compliance/gdpr/policy.sh — regime deny-path data for conjure emit-policy.
# Source this file; do not execute directly.
# Sets: REGIME_DENY_READ (newline-separated), REGIME_DENY_WRITE, REGIME_ALLOWED_DOMAINS.
# POSIX bash 3.2+. No associative arrays, no mapfile, no local -n.

# Per-regime delta paths only. Baseline (secrets/keys/.env/credential dirs) is added by emit-policy.sh.

# GDPR delta paths (personal data / PII)
REGIME_DENY_READ="
**/personal-data/**
**/pii/**
**/gdpr/**
**/user-data/**
**/data-subjects/**
"

REGIME_DENY_WRITE="
**/personal-data/**
**/pii/**
"

REGIME_ALLOWED_DOMAINS=""
