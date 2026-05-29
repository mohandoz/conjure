#!/usr/bin/env bash
# generate-large.sh — creates 510+ synthetic .md files for INV-03 cap tests.
# Usage: bash generate-large.sh <target-dir>
# Creates: <target-dir>/generated-docs/doc-001.md through doc-510.md
# Each file has 3 lines. Target dir is created if absent.

set -uo pipefail

TARGET="${1:-}"
if [ -z "$TARGET" ]; then
  echo "Usage: bash generate-large.sh <target-dir>" >&2
  exit 1
fi

DEST="${TARGET}/generated-docs"
mkdir -p "${DEST}"

i=1
while [ "$i" -le 510 ]; do
  NUM="$(printf '%03d' "$i")"
  printf '# Doc %s\n\nSynthetic document for INV-03 cap test.\n' "$NUM" \
    > "${DEST}/doc-${NUM}.md"
  i=$((i + 1))
done

echo "Generated 510 .md files in ${DEST}"
