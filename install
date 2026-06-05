#!/usr/bin/env bash
# Conjure installer. Designed for `curl -sSL https://raw.githubusercontent.com/mohandoz/conjure/main/install.sh | bash`.
#
# Installs Conjure into ~/.conjure and adds `conjure` to your PATH.
# Set CONJURE_HOME or CONJURE_VERSION to override defaults.
#
# Idempotent. Re-run to update.

set -euo pipefail

CONJURE_HOME="${CONJURE_HOME:-$HOME/.conjure}"
CONJURE_VERSION="${CONJURE_VERSION:-main}"
CONJURE_REPO="${CONJURE_REPO:-https://github.com/mohandoz/conjure.git}"

bold() { printf "\033[1m%s\033[0m\n" "$1"; }
ok()   { printf "  \033[32m✓\033[0m %s\n" "$1"; }
warn() { printf "  \033[33m⚠\033[0m %s\n" "$1"; }
err()  { printf "  \033[31m✗\033[0m %s\n" "$1" >&2; }

bold "Installing Conjure → $CONJURE_HOME (ref: $CONJURE_VERSION)"

# Pre-flight
for tool in git bash; do
  command -v "$tool" >/dev/null 2>&1 || { err "$tool required but not found"; exit 1; }
done

# Recommended-but-optional
for tool in jq node graphify ast-grep gitleaks; do
  command -v "$tool" >/dev/null 2>&1 && ok "found: $tool" || warn "optional: $tool (see reference/TOOLS-CATALOG.md)"
done

# Clone or update
if [ -d "$CONJURE_HOME/.git" ]; then
  ok "existing install — updating"
  git -C "$CONJURE_HOME" fetch --tags --quiet
  git -C "$CONJURE_HOME" checkout --quiet "$CONJURE_VERSION"
  git -C "$CONJURE_HOME" pull --quiet --ff-only || true
else
  ok "cloning $CONJURE_REPO"
  git clone --quiet --depth 1 --branch "$CONJURE_VERSION" "$CONJURE_REPO" "$CONJURE_HOME" \
    || git clone --quiet "$CONJURE_REPO" "$CONJURE_HOME"
  (cd "$CONJURE_HOME" && git checkout --quiet "$CONJURE_VERSION" 2>/dev/null) || true
fi

chmod +x "$CONJURE_HOME/cli/conjure"
ok "CLI installed at: $CONJURE_HOME/cli/conjure"

# Add to PATH (idempotent)
SHELL_RC=""
case "${SHELL:-}" in
  */zsh)  SHELL_RC="$HOME/.zshrc" ;;
  */bash) SHELL_RC="$HOME/.bashrc" ;;
  */fish) SHELL_RC="$HOME/.config/fish/config.fish" ;;
esac

if [ -n "$SHELL_RC" ] && [ -f "$SHELL_RC" ]; then
  if ! grep -q "conjure/cli" "$SHELL_RC" 2>/dev/null; then
    printf '\n# Conjure CLI\nexport PATH="%s/cli:$PATH"\n' "$CONJURE_HOME" >> "$SHELL_RC"
    ok "added PATH entry to $SHELL_RC"
  else
    ok "PATH already configured"
  fi
fi

# Verify
if "$CONJURE_HOME/cli/conjure" version >/dev/null 2>&1; then
  bold "✓ Conjure $("$CONJURE_HOME/cli/conjure" version) installed."
  echo
  echo "Next:"
  echo "  source $SHELL_RC   # or restart your shell"
  echo "  conjure help"
  echo
  echo "Try it on a project:"
  echo "  cd /path/to/repo"
  echo "  conjure init existing"
else
  err "Install verification failed"
  exit 1
fi
