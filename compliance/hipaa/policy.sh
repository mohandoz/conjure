# shellcheck shell=bash
# compliance/hipaa/policy.sh — regime deny-path data for conjure emit-policy.
# Source this file; do not execute directly.
# Sets: REGIME_DENY_READ (newline-separated), REGIME_DENY_WRITE, REGIME_ALLOWED_DOMAINS.
# POSIX bash 3.2+. No associative arrays, no mapfile, no local -n.

# Per-regime delta paths only. Baseline (secrets/keys/.env/credential dirs) is added by emit-policy.sh.

# HIPAA PHI delta paths
REGIME_DENY_READ="
**/phi
**/phi/**
**/patient*
**/medical*
**/health-records/**
**/ehr/**
**/mrn*
**/ssn*
**/dob*
"

REGIME_DENY_WRITE="
**/phi/**
**/patient*
"

REGIME_ALLOWED_DOMAINS=""
