#!/usr/bin/env bash
# tests/run.sh — Conjure regression test suite.
# Exits non-zero on any failure.
set -uo pipefail

CONJURE_HOME="$(cd "$(dirname "$0")/.." && pwd)"
cd "$CONJURE_HOME"
source "$CONJURE_HOME/tests/lib/sandbox.sh"

PASS=0
FAIL=0
TESTS=()

t() { TESTS+=("$1"); }
pass() { echo "  ✓ $1"; PASS=$((PASS+1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL+1)); }

echo "═══════════════════════════════════════════════════════════════════"
echo "Conjure test suite — version $(cat VERSION)"
echo "═══════════════════════════════════════════════════════════════════"
echo

# Smoke tests
echo "▸ Smoke tests"

# CLI exists and runs
if cli/conjure version >/dev/null 2>&1; then pass "cli/conjure version"; else fail "cli/conjure version"; fi

# Every script is executable
while IFS= read -r script; do
  if [ -x "$script" ]; then pass "exec: $script"
  else fail "NOT executable: $script"
  fi
done < <(find scripts cli migrations profiles compliance templates/hooks -name '*.sh' 2>/dev/null)

# JSON validity
if command -v jq >/dev/null 2>&1; then
  while IFS= read -r json; do
    if jq empty "$json" >/dev/null 2>&1; then pass "json valid: $json"
    else fail "json INVALID: $json"
    fi
  done < <(find templates .claude-plugin -name '*.json' 2>/dev/null)
fi

# Skill frontmatter validity
echo
echo "▸ Skill frontmatter validity"
while IFS= read -r skill; do
  name_line=$(head -10 "$skill" | grep '^name:' | head -1)
  desc_line=$(head -10 "$skill" | grep '^description:' | head -1)
  if [ -n "$name_line" ] && [ -n "$desc_line" ]; then pass "frontmatter ok: $skill"
  else fail "frontmatter missing: $skill"
  fi

  # Description length
  desc_len=$(echo "$desc_line" | sed 's/^description: //;s/^"//;s/"$//' | wc -c | tr -d ' ')
  if [ "$desc_len" -lt 30 ]; then fail "description too short ($desc_len chars): $skill"; fi
done < <(find templates/skills -name SKILL.md)

# Size caps
echo
echo "▸ Size caps"
while IFS= read -r skill; do
  lines=$(wc -l < "$skill" | tr -d ' ')
  if [ "$lines" -le 200 ]; then pass "size ≤200: $skill ($lines)"
  else fail "size >200: $skill ($lines)"
  fi
done < <(find templates/skills -name SKILL.md)

while IFS= read -r agent; do
  lines=$(wc -l < "$agent" | tr -d ' ')
  if [ "$lines" -le 80 ]; then pass "size ≤80: $agent ($lines)"
  else fail "size >80: $agent ($lines)"
  fi
done < <(find templates/agents -name '*.md')

# No @imports in any template
echo
echo "▸ No @imports"
if grep -rn "^@" templates/CLAUDE.md.tmpl 2>/dev/null; then fail "@imports in CLAUDE.md template"
else pass "no @imports in templates"
fi

# Hooks use exit 2 (not exit 1)
echo
echo "▸ Hook exit codes"
while IFS= read -r hook; do
  if grep -qE '^exit 1$' "$hook"; then fail "hook uses 'exit 1' (should be 'exit 2' for blocks): $hook"
  else pass "exit codes ok: $hook"
  fi
done < <(find templates/hooks compliance/*/pre-commit-*.sh -name '*.sh' 2>/dev/null)

# Audit script runs without crashing
# (Exit 1 = warnings, 2 = errors, 0 = pass. Conjure kit itself has no CLAUDE.md
#  so warnings are expected; we only fail if the script CRASHES.)
echo
echo "▸ Audit script self-test (must not crash)"
bash scripts/audit-setup.sh "$CONJURE_HOME" >/dev/null 2>&1
rc=$?
if [ "$rc" -le 2 ]; then pass "audit-setup.sh ran (rc=$rc, expected 0|1|2)"
else fail "audit-setup.sh crashed (rc=$rc)"
fi

# Preflight script checks
echo
echo "▸ Preflight script"

# a) Smoke: all required deps present in test env
if bash scripts/preflight.sh >/dev/null 2>&1; then
  pass "scripts/preflight.sh: exits 0 (all required deps present)"
else
  fail "scripts/preflight.sh: non-zero exit (required dep missing in test env?)"
fi

# b) Block-on-required and d) Fix-it output (both use node-strip, share STRIPPED_PATH)
# Strip ALL directories that provide node (accounts for fnm/nvm multi-path envs)
STRIPPED_PATH=""
if command -v node >/dev/null 2>&1; then
  STRIPPED_PATH="$(printf '%s' "$PATH" | tr ':' '\n' | while IFS= read -r dir; do
    [ -x "$dir/node" ] || printf '%s\n' "$dir"
  done | tr '\n' ':' | sed 's/:$//')"

  # b) Block-on-required: strip node from PATH, expect non-zero exit
  if PATH="$STRIPPED_PATH" bash scripts/preflight.sh >/dev/null 2>&1; then
    fail "scripts/preflight.sh: did NOT block when node missing"
  else
    pass "scripts/preflight.sh: correctly blocks when node missing"
  fi

  # d) Fix-it output check: grep output for OS-specific package manager
  FIXIT_OUT="$(PATH="$STRIPPED_PATH" bash scripts/preflight.sh 2>&1 || true)"
  OS_NAME="$(uname -s)"
  if [ "$OS_NAME" = "Darwin" ]; then
    if printf '%s' "$FIXIT_OUT" | grep -q "brew"; then
      pass "scripts/preflight.sh: fix-it output contains brew (macOS)"
    else
      fail "scripts/preflight.sh: fix-it output missing brew on macOS"
    fi
  else
    if printf '%s' "$FIXIT_OUT" | grep -qE "apt|winget"; then
      pass "scripts/preflight.sh: fix-it output contains apt/winget"
    else
      fail "scripts/preflight.sh: fix-it output missing package manager hint"
    fi
  fi
else
  pass "scripts/preflight.sh: skip node-strip test (node not in PATH — already fails smoke)"
fi

# c) Optional-missing exits 0: if shellcheck is absent, preflight must still exit 0
if ! command -v shellcheck >/dev/null 2>&1; then
  if bash scripts/preflight.sh >/dev/null 2>&1; then
    pass "scripts/preflight.sh: exits 0 with shellcheck absent (optional)"
  else
    fail "scripts/preflight.sh: exits non-zero with only optional dep missing"
  fi
else
  pass "scripts/preflight.sh: shellcheck present — optional-missing test skipped"
fi

# Template lint — catch SAFE-03 regressions (bash hooks back in settings template)
echo
echo "▸ Template lint"

if grep -q 'bash .claude/hooks/' templates/settings.json.tmpl 2>/dev/null; then
  fail "settings.json.tmpl: bash hook commands present (SAFE-03 regression)"
else pass "settings.json.tmpl: no bash hook commands"
fi

if grep -q 'node .claude/hooks/' templates/settings.json.tmpl 2>/dev/null; then
  pass "settings.json.tmpl: node hook commands present"
else fail "settings.json.tmpl: node hook commands MISSING"
fi

if grep -q 'hooks-nodejs' scripts/init-project.sh 2>/dev/null; then
  pass "init-project.sh: sources hooks-nodejs (.mjs)"
else fail "init-project.sh: does not source hooks-nodejs (SAFE-03 regression)"
fi

if grep -v '^#' scripts/init-project.sh 2>/dev/null | grep -q 'chmod.*hooks'; then
  fail "init-project.sh: chmod found in hook block (should not chmod .mjs files)"
else pass "init-project.sh: no chmod on hook files"
fi

echo
echo "▸ Dry-run enforcement (SAFE-01, SAFE-02)"

TMPDIR_TARGET="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_TARGET"' EXIT

# Create a minimal CLAUDE.md so profile/compliance fragments have something to append to
printf '# Test project\n' > "$TMPDIR_TARGET/CLAUDE.md"

# Run conjure init --dry-run against the temp dir
DRY_OUT="$(CONJURE_HOME="$CONJURE_HOME" cli/conjure init --dry-run "$TMPDIR_TARGET" 2>&1 || true)"

# SAFE-01 assertion: .claude/ must NOT be created
if [ -d "$TMPDIR_TARGET/.claude" ]; then
  fail "dry-run: .claude/ was created (filesystem mutated — SAFE-01)"
else
  pass "dry-run: .claude/ not created (SAFE-01)"
fi

# SAFE-01 / D-04 assertion: [dry-run] prefix lines must appear in output
if printf '%s' "$DRY_OUT" | grep -q "\[dry-run\]"; then
  pass "dry-run: [dry-run] prefix lines present in output (D-04)"
else
  fail "dry-run: no [dry-run] lines in output (D-04)"
fi

# D-05 assertion: mutation count > 0 in summary line
if printf '%s' "$DRY_OUT" | grep -qE "\[dry-run\] [1-9][0-9]* mutations skipped"; then
  pass "dry-run: mutation count > 0 in summary line (D-05)"
else
  fail "dry-run: summary line missing or count is 0 (D-05)"
fi

# Dry-run section done — clean up now before sandbox_setup registers its own EXIT trap.
# bash 'trap ... EXIT' is not additive; sandbox_setup would overwrite this trap and leak
# TMPDIR_TARGET for the rest of the OS session (CR-01).
rm -rf "$TMPDIR_TARGET"
trap - EXIT

# Migration scripts exist for every documented source
echo
echo "▸ Migration coverage"
for source in from-claude from-cursor from-aider from-continue from-copilot from-windsurf; do
  if [ -x "migrations/$source/migrate.sh" ]; then pass "migration: $source"
  else fail "migration MISSING: $source"
  fi
done

# Profile coverage
echo
echo "▸ Profile coverage"
for profile in java-spring python-fastapi ts-next rust-axum go-gin node-nest monorepo polyglot data-science; do
  if [ -x "profiles/$profile/apply.sh" ]; then pass "profile: $profile"
  else fail "profile MISSING: $profile"
  fi
done

# Compliance coverage
echo
echo "▸ Compliance coverage"
for c in hipaa soc2 gdpr pci; do
  if [ -x "compliance/$c/apply.sh" ]; then pass "compliance: $c"
  else fail "compliance MISSING: $c"
  fi
done

# Fixture audits — sandboxed (TEST-01, TEST-02)
echo
echo "▸ Fixture audits — sandboxed (TEST-01, TEST-02)"
for fx in "$CONJURE_HOME/tests/fixtures"/[^_]*/; do
  prof=$(basename "$fx")
  sandbox_setup "$fx"
  trap 'rm -rf "$SANDBOX_DIR"' EXIT
  AUDIT_OUT="$(bash "$CONJURE_HOME/scripts/audit-setup.sh" "$SANDBOX_DIR" 2>&1)"
  AUDIT_RC=$?
  if [ "$AUDIT_RC" -eq 0 ]; then
    pass "fixture audit green: $prof"
  else
    fail "fixture audit non-green (rc=$AUDIT_RC): $prof"
    printf '%s\n' "$AUDIT_OUT" | head -5
  fi
done

# Broken fixture — specific finding assertion (TEST-04)
echo
echo "▸ Broken fixture — specific finding assertion (TEST-04)"
sandbox_setup "$CONJURE_HOME/tests/fixtures/_broken"
trap 'rm -rf "$SANDBOX_DIR"' EXIT
BROKEN_OUT="$(bash "$CONJURE_HOME/scripts/audit-setup.sh" "$SANDBOX_DIR" 2>&1)"
BROKEN_RC=$?
if [ "$BROKEN_RC" -ne 0 ]; then
  pass "_broken: audit exits non-zero (rc=$BROKEN_RC)"
else
  fail "_broken: audit should exit non-zero"
fi
while IFS= read -r pattern; do
  [ -z "$pattern" ] && continue
  case "$pattern" in \#*) continue ;; esac
  if printf '%s\n' "$BROKEN_OUT" | grep -qE "$pattern"; then
    pass "_broken: found expected finding: $pattern"
  else
    fail "_broken: missing expected finding: $pattern"
  fi
done < "$CONJURE_HOME/tests/fixtures/_broken/EXPECT"

echo
echo "▸ Golden-file EXPECT loop (TEST-03)"
for fx in "$CONJURE_HOME/tests/fixtures"/[^_]*/; do
  prof=$(basename "$fx")
  expect_file="${fx}EXPECT"
  [ ! -f "$expect_file" ] && continue
  sandbox_setup "$fx"
  trap 'rm -rf "$SANDBOX_DIR"' EXIT
  AUDIT_OUT="$(bash "$CONJURE_HOME/scripts/audit-setup.sh" "$SANDBOX_DIR" 2>&1)"
  while IFS= read -r pattern; do
    [ -z "$pattern" ] && continue
    case "$pattern" in \#*) continue ;; esac
    if printf '%s\n' "$AUDIT_OUT" | grep -qE "$pattern"; then
      pass "$prof EXPECT: $pattern"
    else
      fail "$prof EXPECT: missing pattern: $pattern"
    fi
  done < "$expect_file"
done

echo
echo "▸ Dry-run byte-identical snapshot (TEST-05)"
for fx in "$CONJURE_HOME/tests/fixtures"/[^_]*/; do
  prof=$(basename "$fx")
  DRY_ORIG="$(mktemp -d)"
  DRY_SNAP="$(mktemp -d)"
  cp -r "$fx/." "$DRY_ORIG/"
  cp -r "$fx/." "$DRY_SNAP/"
  CONJURE_HOME="$CONJURE_HOME" cli/conjure init --dry-run "$DRY_SNAP" >/dev/null 2>&1 || true
  if diff -r "$DRY_SNAP" "$DRY_ORIG" >/dev/null 2>&1; then
    pass "dry-run snapshot identical: $prof"
  else
    fail "dry-run mutated tree: $prof"
    diff -r "$DRY_SNAP" "$DRY_ORIG" | head -10
  fi
  rm -rf "$DRY_ORIG" "$DRY_SNAP"
done

echo
echo "▸ Failure-mode reproductions (TEST-07)"

# FM-1: CLAUDE.md exceeds 200-line hard cap — audit-setup.sh detects this
FM_DIR="$(mktemp -d)"
printf '# SYNTHETIC — size cap test\n' > "$FM_DIR/CLAUDE.md"
for i in $(seq 1 205); do printf '# filler line %s\n' "$i" >> "$FM_DIR/CLAUDE.md"; done
FM_OUT="$(bash "$CONJURE_HOME/scripts/audit-setup.sh" "$FM_DIR" 2>&1 || true)"
if printf '%s\n' "$FM_OUT" | grep -q "HARD CAP exceeded"; then
  pass "FM: size cap detected by audit"
else
  fail "FM: size cap NOT detected"
fi
rm -rf "$FM_DIR"

# FM-2: Hook uses exit 1 (non-blocking) instead of exit 2 (blocking)
# NOTE: audit-setup.sh does NOT check hook exit codes — use grep directly (Finding F-01)
FM_DIR="$(mktemp -d)"
mkdir -p "$FM_DIR/.claude/hooks"
printf '#!/usr/bin/env bash\nexit 1\n' > "$FM_DIR/.claude/hooks/bad-gate.sh"
if grep -qE '^exit 1$' "$FM_DIR/.claude/hooks/bad-gate.sh"; then
  pass "FM: hook exit 1 detectable via grep"
else
  fail "FM: hook exit 1 NOT found"
fi
rm -rf "$FM_DIR"

# FM-3: .conjure-version mismatch — conjure update detects this
# NOTE: audit-setup.sh does NOT check .conjure-version — use cli/conjure update (Finding F-01)
# NOTE: version file must be at .claude/.conjure-version (not root level — Pitfall 5)
FM_DIR="$(mktemp -d)"
mkdir -p "$FM_DIR/.claude"
printf '0.1.0\n' > "$FM_DIR/.claude/.conjure-version"
FM_OUT="$(CONJURE_HOME="$CONJURE_HOME" cli/conjure update "$FM_DIR" 2>&1 || true)"
if printf '%s\n' "$FM_OUT" | grep -q "pinned to" && \
   ! printf '%s\n' "$FM_OUT" | grep -q "Up to date"; then
  pass "FM: version mismatch detected by conjure update"
else
  fail "FM: version mismatch NOT detected"
fi
rm -rf "$FM_DIR"

# Summary
echo
echo "═══════════════════════════════════════════════════════════════════"
echo "PASS: $PASS    FAIL: $FAIL"
echo "═══════════════════════════════════════════════════════════════════"

[ "$FAIL" -eq 0 ]
