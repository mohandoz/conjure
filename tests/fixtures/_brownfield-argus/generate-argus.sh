#!/usr/bin/env bash
# generate-argus.sh — materializes the 500-file `brownfield-argus` E2E fixture
# into a passed target dir. Mirrors brownfield-simple/generate-large.sh's shape,
# but honors the project lock "exit 2 never exit 1" on the usage error.
#
# Usage: bash generate-argus.sh <target-dir>
#
# Materializes (all into <target-dir>):
#   (1) an OVERSIZED CLAUDE.md at the target root (>100 lines — over the cap, so
#       the adopt report has a meaningful before-line count and the fixture is
#       genuinely "grown-messy");
#   (2) ~500 bulk .md files under docs/ + generated-docs/ (zero-padded names);
#   (3) a REAL symlink markdown file via `ln -s` (docs/linked.md → real.md), a
#       relative target so it stays portable — criterion 5's symlink-skip source.
#       This MUST be a genuine symlink, never a committed regular file;
#   (4) an `@import` staged seed (with-import.md whose first content line is an
#       `@`-import) — criterion 5's @import-block source. Plan 02 stages it into
#       .conjure-adopt-state/staging/CLAUDE.md and runs the audit-staged gate.
#
# Dependency-free: printf / mkdir / ln / while only. The dir name keeps its
# leading underscore (`_brownfield-argus`) so it is excluded from the generic
# tests/fixtures/[^_]*/ sweep loops. Only this script is committed — every
# generated file (bulk .md, symlink) is materialized at test time.

set -uo pipefail

TARGET="${1:-}"
if [ -z "$TARGET" ]; then
  echo "Usage: bash generate-argus.sh <target-dir>" >&2
  exit 2
fi

mkdir -p "${TARGET}/docs" "${TARGET}/generated-docs"

# (1) Oversized/sprawling CLAUDE.md (>100 lines) at the target root.
{
  printf '# BROWNFIELD-ARGUS fixture (grown-messy)\n\n'
  printf 'A representative brownfield repo whose CLAUDE.md sprawled well past the\n'
  printf '100-line cap over time. Used by the Phase 24 E2E adopt + restructure tests.\n\n'
  printf '## Notes\n\n'
  n=1
  while [ "$n" -le 120 ]; do
    printf -- '- legacy note line %03d: accreted guidance that should be restructured.\n' "$n"
    n=$((n + 1))
  done
} > "${TARGET}/CLAUDE.md"

# (2) ~500 bulk .md files (505 total: 255 under docs/, 250 under generated-docs/).
i=1
while [ "$i" -le 255 ]; do
  NUM="$(printf '%03d' "$i")"
  printf '# Doc %s\n\nSynthetic brownfield document for the argus 500-file fixture.\n' \
    "$NUM" > "${TARGET}/docs/doc-${NUM}.md"
  i=$((i + 1))
done

i=1
while [ "$i" -le 250 ]; do
  NUM="$(printf '%03d' "$i")"
  printf '# Generated %s\n\nSynthetic generated document for the argus fixture.\n' \
    "$NUM" > "${TARGET}/generated-docs/gen-${NUM}.md"
  i=$((i + 1))
done

# (3) A REAL symlink (docs/linked.md -> real.md), relative target for portability.
printf '# Real linked target\n\nThe genuine file the symlink points at.\n' \
  > "${TARGET}/docs/real.md"
ln -s real.md "${TARGET}/docs/linked.md"

# (4) An @import staged seed — first content line is an @-import.
printf '# Proposed CLAUDE\n@.claude/skills/x/SKILL.md\n' > "${TARGET}/with-import.md"

MD_COUNT="$(find "${TARGET}" -name '*.md' | wc -l | tr -d ' ')"
echo "Generated brownfield-argus fixture in ${TARGET} (${MD_COUNT} .md files, real ln -s symlink, oversized CLAUDE.md, @import seed)"
