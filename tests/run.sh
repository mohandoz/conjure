#!/usr/bin/env bash
# tests/run.sh — Conjure regression test suite.
# Exits non-zero on any failure.
set -uo pipefail

CONJURE_HOME="$(cd "$(dirname "$0")/.." && pwd)"
cd "$CONJURE_HOME"

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

# Summary
echo
echo "═══════════════════════════════════════════════════════════════════"
echo "PASS: $PASS    FAIL: $FAIL"
echo "═══════════════════════════════════════════════════════════════════"

[ "$FAIL" -eq 0 ]
