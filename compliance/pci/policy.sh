# shellcheck shell=bash
# compliance/pci/policy.sh — regime deny-path data for conjure emit-policy.
# Source this file; do not execute directly.
# Sets: REGIME_DENY_READ (newline-separated), REGIME_DENY_WRITE, REGIME_ALLOWED_DOMAINS.
# POSIX bash 3.2+. No associative arrays, no mapfile, no local -n.

# Per-regime delta paths only. Baseline (secrets/keys/.env/credential dirs) is added by emit-policy.sh.

# PCI DSS delta paths (cardholder data / PAN)
REGIME_DENY_READ="
**/cardholder*
**/pan*
**/card-data/**
**/cde/**
**/cvv*
**/card-numbers*
**/payment-data/**
"

REGIME_DENY_WRITE="
**/pan*
**/cardholder*
"

REGIME_ALLOWED_DOMAINS=""
