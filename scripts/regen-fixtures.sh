#!/usr/bin/env bash
# scripts/regen-fixtures.sh — regenerate all (or one) committed test fixtures.
# Usage: bash scripts/regen-fixtures.sh [--profile <profile>]
#   --profile <p>  Regenerate a single profile instead of all 9.
# Profiles: ts-next java-spring rust-axum go-gin python-fastapi node-nest monorepo polyglot data-science

set -euo pipefail

CONJURE_HOME="$(cd "$(dirname "$0")/.." && pwd)"
FIXTURES_DIR="$CONJURE_HOME/tests/fixtures"

PROFILES="ts-next java-spring rust-axum go-gin python-fastapi node-nest monorepo polyglot data-science"
PROFILE_FILTER=""

# Argument parsing: optional --profile <p> flag
while [ $# -gt 0 ]; do
  case "$1" in
    --profile)
      PROFILE_FILTER="${2:?'--profile requires an argument'}"
      shift 2
      ;;
    *)
      printf 'Unknown argument: %s\n' "$1" >&2
      exit 1
      ;;
  esac
done

# _write_manifest <profile> <seed_dir>
# Writes the appropriate manifest stub for each profile into the seed directory.
_write_manifest() {
  local p="$1"
  local seed="$2"
  case "$p" in
    ts-next|node-nest|monorepo|polyglot)
      printf '{"name":"fixture","version":"0.0.0"}\n' > "$seed/package.json"
      ;;
    java-spring)
      printf '<project><modelVersion>4.0.0</modelVersion><groupId>com.example</groupId><artifactId>fixture</artifactId><version>0.0.1-SNAPSHOT</version></project>\n' > "$seed/pom.xml"
      ;;
    rust-axum)
      printf '[package]\nname = "fixture"\nversion = "0.1.0"\nedition = "2024"\n' > "$seed/Cargo.toml"
      ;;
    go-gin)
      printf 'module fixture\n\ngo 1.22\n' > "$seed/go.mod"
      ;;
    python-fastapi|data-science)
      printf 'fastapi>=0.110\n' > "$seed/requirements.txt"
      ;;
  esac
  # monorepo requires a packages/ subdir or apply.sh exits without appending the fragment
  if [ "$p" = "monorepo" ]; then
    mkdir -p "$seed/packages/api"
  fi
}

# _write_seed_claude <seed_dir>
# Writes a seed CLAUDE.md with GENERATED header before conjure init is called.
# conjure init does NOT create CLAUDE.md; profile apply.sh appends a fragment
# only if CLAUDE.md already exists. Without this seed, the fixture has no CLAUDE.md.
_write_seed_claude() {
  local seed="$1"
  printf '# GENERATED — do not edit directly; run scripts/regen-fixtures.sh\n' > "$seed/CLAUDE.md"
  printf '\n' >> "$seed/CLAUDE.md"
  printf '## Project\n' >> "$seed/CLAUDE.md"
  printf '\n' >> "$seed/CLAUDE.md"
  printf 'Fixture project.\n' >> "$seed/CLAUDE.md"
  printf '\n' >> "$seed/CLAUDE.md"
  printf '### Constraints\n' >> "$seed/CLAUDE.md"
  printf '\n' >> "$seed/CLAUDE.md"
  printf '- POSIX bash + Node.js .mjs hooks.\n' >> "$seed/CLAUDE.md"
  printf '\n' >> "$seed/CLAUDE.md"
  printf '## Technology Stack\n' >> "$seed/CLAUDE.md"
  printf '\n' >> "$seed/CLAUDE.md"
  printf 'See profile fragment below.\n' >> "$seed/CLAUDE.md"
  printf '\n' >> "$seed/CLAUDE.md"
  printf '## Conventions\n' >> "$seed/CLAUDE.md"
  printf '\n' >> "$seed/CLAUDE.md"
  printf 'None.\n' >> "$seed/CLAUDE.md"
  printf '\n' >> "$seed/CLAUDE.md"
  printf '## Architecture\n' >> "$seed/CLAUDE.md"
  printf '\n' >> "$seed/CLAUDE.md"
  printf 'Standard conjure harness layout.\n' >> "$seed/CLAUDE.md"
  printf '\n' >> "$seed/CLAUDE.md"
  printf '## Developer Notes\n' >> "$seed/CLAUDE.md"
  printf '\n' >> "$seed/CLAUDE.md"
}

# regen_profile <profile>
# Creates a seed dir, runs conjure init, copies result to tests/fixtures/<profile>/.
regen_profile() {
  local p="$1"
  printf '[regen] %s\n' "$p"
  local seed
  seed="$(mktemp -d)"
  trap 'rm -rf "$seed"' RETURN
  _write_manifest "$p" "$seed"
  _write_seed_claude "$seed"
  CONJURE_HOME="$CONJURE_HOME" "$CONJURE_HOME/cli/conjure" init --profile="$p" "$seed" >/dev/null
  rm -rf "${FIXTURES_DIR:?}/$p"
  cp -r "$seed/." "$FIXTURES_DIR/$p/"
  if ! bash "$CONJURE_HOME/scripts/audit-setup.sh" "$FIXTURES_DIR/$p" >/dev/null 2>&1; then
    printf '[regen] WARN: %s fixture fails audit — check profile output\n' "$p" >&2
    exit 1
  fi
  printf '[regen] %s done\n' "$p"
}

# Ensure fixtures dir exists
mkdir -p "$FIXTURES_DIR"

# Main loop
for p in $PROFILES; do
  if [ -n "$PROFILE_FILTER" ] && [ "$p" != "$PROFILE_FILTER" ]; then
    continue
  fi
  regen_profile "$p"
done
