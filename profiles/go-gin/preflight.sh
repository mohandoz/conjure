#!/usr/bin/env bash
set -uo pipefail
WARN=0
check() { if command -v "$1" >/dev/null 2>&1; then echo "  ✓ $1"; else echo "  ⚠ $1 missing"; WARN=1; fi }
echo "Pre-flight (go-gin):"
check go
check git
exit "$WARN"
