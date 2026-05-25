#!/usr/bin/env bash
# scripts/record-demo.sh — record animated demo of conjure init + audit.
# Usage: bash scripts/record-demo.sh
# Requires: asciinema, agg, expect (contributor machine only — not in CI)
# Output: .github/assets/demo.gif

set -euo pipefail

CONJURE_HOME="$(cd "$(dirname "$0")/.." && pwd)"
ASSETS_DIR="$CONJURE_HOME/.github/assets"

# Preflight: require the three tools (contributor machine only — not in CI)
if ! command -v asciinema >/dev/null 2>&1; then
  printf 'record-demo.sh: asciinema is required but not found.\n' >&2
  printf '  macOS:  brew install asciinema\n  Linux:  sudo apt install asciinema\n' >&2
  exit 1
fi
if ! command -v agg >/dev/null 2>&1; then
  printf 'record-demo.sh: agg is required but not found.\n' >&2
  printf '  macOS:  brew install agg\n  Linux:  sudo apt install agg\n' >&2
  exit 1
fi
if ! command -v expect >/dev/null 2>&1; then
  printf 'record-demo.sh: expect is required but not found.\n' >&2
  printf '  macOS:  brew install expect\n  Linux:  sudo apt install expect\n' >&2
  exit 1
fi

# Isolated temp dir — no leakage to developer's real $HOME
DEMO_DIR="$(mktemp -d)"
CAST_FILE="$DEMO_DIR/demo.cast"
GIF_FILE="$DEMO_DIR/demo.gif"
trap 'rm -rf "$DEMO_DIR"' EXIT

# PATH isolation: prepend conjure CLI dir so `conjure` is found inside the
# asciinema-recorded shell (prevents Pitfall 4: "conjure: command not found")
export PATH="$CONJURE_HOME/cli:$PATH"

# Seed files for ts-next profile (same printf pattern as regen-fixtures.sh)
printf '{"name":"demo","version":"0.0.0"}\n' > "$DEMO_DIR/package.json"

printf '# Demo project\n' > "$DEMO_DIR/CLAUDE.md"
printf '\n' >> "$DEMO_DIR/CLAUDE.md"
printf '## Project\n' >> "$DEMO_DIR/CLAUDE.md"
printf '\n' >> "$DEMO_DIR/CLAUDE.md"
printf 'Demo project for conjure init dry-run recording.\n' >> "$DEMO_DIR/CLAUDE.md"
printf '\n' >> "$DEMO_DIR/CLAUDE.md"
printf '## Technology Stack\n' >> "$DEMO_DIR/CLAUDE.md"
printf '\n' >> "$DEMO_DIR/CLAUDE.md"
printf 'TypeScript / Next.js\n' >> "$DEMO_DIR/CLAUDE.md"
printf '\n' >> "$DEMO_DIR/CLAUDE.md"
printf '## Conventions\n' >> "$DEMO_DIR/CLAUDE.md"
printf '\n' >> "$DEMO_DIR/CLAUDE.md"
printf 'None established.\n' >> "$DEMO_DIR/CLAUDE.md"
printf '\n' >> "$DEMO_DIR/CLAUDE.md"
printf '## Architecture\n' >> "$DEMO_DIR/CLAUDE.md"
printf '\n' >> "$DEMO_DIR/CLAUDE.md"
printf 'Standard Next.js app structure.\n' >> "$DEMO_DIR/CLAUDE.md"

# Write the inline expect script to DEMO_DIR.
# The outer process (expect) spawns asciinema rec and drives keystrokes into the shell.
# Uses spawn + window-size 120x35 (asciinema v3 compatible flag).
cat > "$DEMO_DIR/demo.exp" <<'EXPECT_SCRIPT'
#!/usr/bin/env expect -f
set timeout 120
set send_human {0.04 0.08 0.15 0.02 0.5}

proc expect_prompt {} {
    expect -re {[\$#]\s*$}
}

spawn asciinema rec --overwrite --window-size 120x35 $env(CAST_FILE)
expect_prompt

# Normalize prompt for reliable matching — Pitfall 2 prevention
send "PS1='$ '\r"
expect_prompt

# Change into the seeded fixture directory
send "cd $env(DEMO_DIR)\r"
expect_prompt

# D-02: Command 1 — init dry-run
send -h "conjure init --dry-run --profile=ts-next .\r"
expect_prompt
sleep 2

# D-02: Command 2 — audit
send -h "conjure audit\r"
expect_prompt
sleep 2

send "exit\r"
expect eof
EXPECT_SCRIPT

# Export env vars so the expect script can read them
export CAST_FILE DEMO_DIR

printf '[record-demo] Starting asciinema recording via expect...\n'
expect "$DEMO_DIR/demo.exp"

# Convert cast to GIF (D-06: agg with recommended flags per RESEARCH.md Pattern 2)
printf '[record-demo] Converting cast to GIF...\n'
agg --speed 1.5 --idle-time-limit 2 --theme dracula "$CAST_FILE" "$GIF_FILE"

# Copy to assets dir (D-07)
mkdir -p "$ASSETS_DIR"
cp "$GIF_FILE" "$ASSETS_DIR/demo.gif"

printf '[record-demo] demo.gif written to %s\n' "$ASSETS_DIR/demo.gif"
printf '[record-demo] File size: %s bytes\n' "$(wc -c < "$ASSETS_DIR/demo.gif")"
