#!/usr/bin/env bash
set -uo pipefail
WARN=0
check() { if command -v "$1" >/dev/null 2>&1; then echo "  ✓ $1"; else echo "  ⚠ $1 missing"; WARN=1; fi }

echo "Pre-flight (ts-next):"
check node
check pnpm
check git

if command -v node >/dev/null 2>&1; then
  echo "  ℹ node $(node --version)"
fi

exit "$WARN"
