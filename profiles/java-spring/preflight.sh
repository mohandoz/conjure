#!/usr/bin/env bash
set -uo pipefail
WARN=0
check() { if command -v "$1" >/dev/null 2>&1; then echo "  ✓ $1"; else echo "  ⚠ $1 missing"; WARN=1; fi }

echo "Pre-flight (java-spring):"
check java
check gradle
check git

# Java version check
if command -v java >/dev/null 2>&1; then
  JV=$(java -version 2>&1 | head -1)
  echo "  ℹ $JV"
fi

exit "$WARN"
