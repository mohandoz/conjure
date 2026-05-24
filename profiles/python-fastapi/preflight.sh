#!/usr/bin/env bash
set -uo pipefail
WARN=0
check() { if command -v "$1" >/dev/null 2>&1; then echo "  ✓ $1"; else echo "  ⚠ $1 missing"; WARN=1; fi }

echo "Pre-flight (python-fastapi):"
check python3
check uv
check git

if command -v python3 >/dev/null 2>&1; then
  echo "  ℹ $(python3 --version)"
fi

exit "$WARN"
