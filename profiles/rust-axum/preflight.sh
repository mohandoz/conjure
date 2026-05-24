#!/usr/bin/env bash
set -uo pipefail
WARN=0
check() { if command -v "$1" >/dev/null 2>&1; then echo "  ✓ $1"; else echo "  ⚠ $1 missing"; WARN=1; fi }
echo "Pre-flight (rust-axum):"
check cargo
check rustc
check git
exit "$WARN"
