#!/usr/bin/env bash
# preflight.sh — standalone dep checker with OS detection, required/optional split,
# per-OS fix-it lines, and non-zero exit on required-dep failure.
#
# Usage: bash scripts/preflight.sh
# Exit codes: 0 = all required deps present (optional may be missing)
#             1 = one or more required deps missing
#
# Self-contained: no sourced variables, no $CONJURE_HOME dependency.
# Compatible: POSIX bash 3.2+ (no associative arrays, no mapfile/readarray).

set -uo pipefail

_detect_os() {
  local uname_s uname_r
  uname_s="$(uname -s 2>/dev/null || echo unknown)"
  uname_r="$(uname -r 2>/dev/null || echo unknown)"

  case "$uname_s" in
    Darwin)
      printf "macos"
      return
      ;;
    Linux)
      if printf '%s' "$uname_r" | grep -qi "microsoft"; then
        printf "wsl"
      else
        printf "linux"
      fi
      return
      ;;
    MINGW*|MSYS*|CYGWIN*)
      printf "windows-gitbash"
      return
      ;;
  esac

  # Fallback: check $OSTYPE
  case "${OSTYPE:-}" in
    msys*|cygwin*)
      printf "windows-gitbash"
      ;;
    *)
      printf "unknown"
      ;;
  esac
}

_fixup() {
  local dep="$1"
  local os="$2"

  case "$os" in
    macos)
      case "$dep" in
        node)       printf "    brew install node\n" ;;
        git)        printf "    brew install git\n" ;;
        jq)         printf "    brew install jq\n" ;;
        rg)         printf "    brew install ripgrep\n" ;;
        shellcheck) printf "    brew install shellcheck\n" ;;
        *)          printf "    see: https://github.com/nicholasgasior/conjure#requirements\n" ;;
      esac
      ;;
    linux|wsl)
      case "$dep" in
        node)       printf "    apt install nodejs\n" ;;
        git)        printf "    apt install git\n" ;;
        jq)         printf "    apt install jq\n" ;;
        rg)         printf "    apt install ripgrep\n" ;;
        shellcheck) printf "    apt install shellcheck\n" ;;
        *)          printf "    see: https://github.com/nicholasgasior/conjure#requirements\n" ;;
      esac
      ;;
    windows-gitbash)
      case "$dep" in
        node)       printf "    winget install OpenJS.NodeJS\n" ;;
        git)        printf "    winget install Git.Git\n" ;;
        jq)         printf "    winget install jqlang.jq\n" ;;
        rg)         printf "    winget install BurntSushi.ripgrep.MSVC\n" ;;
        shellcheck) printf "    winget install koalaman.shellcheck\n" ;;
        *)          printf "    see: https://github.com/nicholasgasior/conjure#requirements\n" ;;
      esac
      ;;
    *)
      printf "    see: https://github.com/nicholasgasior/conjure#requirements\n"
      ;;
  esac
}

# Main body
printf "\nConjure pre-flight checks\n"

OS="$(_detect_os)"

# Required deps check (node, git)
printf "Required deps:\n"
REQUIRED_FAILED=0

for dep in node git; do
  if command -v "$dep" >/dev/null 2>&1; then
    printf "  ✓ %s\n" "$dep"
  else
    printf "  ✗ %s missing (required)\n" "$dep"
    _fixup "$dep" "$OS"
    REQUIRED_FAILED=1
  fi
done

[ "$REQUIRED_FAILED" -eq 1 ] && exit 1

# Optional deps check (jq, rg, shellcheck)
printf "\nOptional deps:\n"

for dep in jq rg shellcheck; do
  if command -v "$dep" >/dev/null 2>&1; then
    printf "  ✓ %s\n" "$dep"
  else
    printf "  ⚠ %s not found (optional — some features degraded)\n" "$dep"
    _fixup "$dep" "$OS"
  fi
done

# Optional power tools
for dep in graphify ast-grep; do
  if ! command -v "$dep" >/dev/null 2>&1; then
    printf "  (optional power tool) %s not installed — see reference/TOOLS-CATALOG.md\n" "$dep"
  fi
done

exit 0
