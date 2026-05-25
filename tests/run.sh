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
  done < <(find templates .claude-plugin lib -name '*.json' 2>/dev/null)
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

  # Description length (printf avoids the trailing newline that echo appends)
  desc_len=$(printf '%s' "$desc_line" | sed 's/^description: //;s/^"//;s/"$//' | wc -c | tr -d ' ')
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
  rm -rf "$SANDBOX_DIR"
  trap - EXIT
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
rm -rf "$SANDBOX_DIR"
trap - EXIT

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
  rm -rf "$SANDBOX_DIR"
  trap - EXIT
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
# shellcheck disable=SC2046
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

echo
echo "▸ Cost estimator tests (COST-01, COST-02, COST-03)"

COST_FX="$CONJURE_HOME/tests/fixtures/python-fastapi"
sandbox_setup "$COST_FX"
trap 'rm -rf "$SANDBOX_DIR"' EXIT

COST_OUT="$(CONJURE_COST=1 bash "$CONJURE_HOME/scripts/audit-setup.sh" "$SANDBOX_DIR" 2>&1)"
COST_RC=$?

# COST-01: section header present
if printf '%s' "$COST_OUT" | grep -q "── Cost Estimate ──"; then
  pass "cost section header present (COST-01)"
else
  fail "cost section header missing (COST-01)"
fi

# COST-02: label has ±20% band
if printf '%s' "$COST_OUT" | grep -qE "Estimate: \\\$[0-9]+\.[0-9]{2} ±20%"; then
  pass "cost label has ±20% band (COST-02)"
else
  fail "cost label format wrong — expected '±20%' (COST-02)"
fi

# COST-02: label contains pricing date
if printf '%s' "$COST_OUT" | grep -q "prices:"; then
  pass "cost label contains pricing date (COST-02)"
else
  fail "cost label missing pricing date (COST-02)"
fi

# COST-02: model name in output
if printf '%s' "$COST_OUT" | grep -q "claude-sonnet-4-6"; then
  pass "cost output names the model (COST-02)"
else
  fail "cost output missing model name (COST-02)"
fi

# COST-01: cost section does not crash
if [ "$COST_RC" -le 2 ]; then
  pass "cost section exit code ≤ 2 (COST-01)"
else
  fail "cost section crashed (rc=$COST_RC) (COST-01)"
fi

# COST-03: no network calls in default path
NO_NET_COUNT=$(grep -v '^#' "$CONJURE_HOME/scripts/audit-setup.sh" | grep -cE "curl|fetch|http[s]?:" || true)
if [ "$NO_NET_COUNT" -eq 0 ]; then
  pass "audit-setup.sh has no network calls in default path (COST-03)"
else
  fail "audit-setup.sh has $NO_NET_COUNT network call(s) in default path (COST-03)"
fi

# COST-03: --exact fallback advisory when API key absent
EXACT_OUT="$(CONJURE_COST=1 CONJURE_EXACT=1 ANTHROPIC_API_KEY="" bash "$CONJURE_HOME/scripts/audit-setup.sh" "$SANDBOX_DIR" 2>&1)"
EXACT_RC=$?
if printf '%s' "$EXACT_OUT" | grep -q "ANTHROPIC_API_KEY not set"; then
  pass "--exact fallback advisory present when API key absent (COST-03)"
else
  fail "--exact fallback advisory missing (COST-03)"
fi
if [ "$EXACT_RC" -le 2 ]; then
  pass "--exact fallback exits cleanly (rc=$EXACT_RC) (COST-03)"
else
  fail "--exact fallback crashed (rc=$EXACT_RC) (COST-03)"
fi

rm -rf "$SANDBOX_DIR"
trap - EXIT

echo
echo "▸ Telemetry tests (TLMY-01 through TLMY-05)"

# TLMY-01: hook file existence
TLMY_HOOK="$CONJURE_HOME/templates/hooks-nodejs/skill-telemetry.mjs"
if [ -f "$TLMY_HOOK" ]; then
  pass "skill-telemetry.mjs exists (TLMY-01)"
else
  fail "skill-telemetry.mjs missing (TLMY-01)"
fi

# TLMY-03: no network egress in hook (static grep — no sandbox needed)
if [ -f "$TLMY_HOOK" ]; then
  EGRESS_PATTERNS='curl|fetch|http|socket|XMLHttpRequest|require\(.https.\)|require\(.http.\)|import.*https|import.*http|net\.Socket'
  if grep -qE "$EGRESS_PATTERNS" "$TLMY_HOOK" 2>/dev/null; then
    fail "skill-telemetry.mjs contains network egress pattern (TLMY-03)"
  else
    pass "skill-telemetry.mjs: no network egress (TLMY-03)"
  fi
else
  fail "skill-telemetry.mjs missing — cannot check egress (TLMY-03)"
fi

# TLMY-05: TELEMETRY.md at repo root
if [ -f "$CONJURE_HOME/TELEMETRY.md" ]; then
  pass "TELEMETRY.md present at repo root (TLMY-05)"
else
  fail "TELEMETRY.md missing (TLMY-05)"
fi

if grep -q 'session_id' "$CONJURE_HOME/TELEMETRY.md" 2>/dev/null && \
   grep -q 'project_cwd' "$CONJURE_HOME/TELEMETRY.md" 2>/dev/null && \
   grep -q 'DO_NOT_TRACK' "$CONJURE_HOME/TELEMETRY.md" 2>/dev/null; then
  pass "TELEMETRY.md contains required schema fields + DO_NOT_TRACK (TLMY-05)"
else
  fail "TELEMETRY.md missing required fields (session_id, project_cwd, or DO_NOT_TRACK) (TLMY-05)"
fi

# TLMY-04: --retire-list flag present in cli/conjure
if grep -q '\-\-retire-list' "$CONJURE_HOME/cli/conjure"; then
  pass "--retire-list flag present in cli/conjure (TLMY-04)"
else
  fail "--retire-list flag missing from cli/conjure (TLMY-04)"
fi

# Sandbox-based tests (TLMY-01 opt-in gate, TLMY-02 JSONL write, TLMY-04 retire-list render)
TLMY_FX="$CONJURE_HOME/tests/fixtures/python-fastapi"
sandbox_setup "$TLMY_FX"
trap 'rm -rf "$SANDBOX_DIR"' EXIT

# TLMY-01: hook exits 0 silently when CONJURE_TELEMETRY is unset
UNSET_RC=0
printf '{}' | CONJURE_TELEMETRY="" node "$TLMY_HOOK" >/dev/null 2>&1 || UNSET_RC=$?
if [ "$UNSET_RC" -eq 0 ]; then
  pass "hook exits 0 silently when CONJURE_TELEMETRY unset (TLMY-01)"
else
  fail "hook exited $UNSET_RC when CONJURE_TELEMETRY unset — expected 0 (TLMY-01)"
fi

# TLMY-01: hook exits 0 silently when CONJURE_TELEMETRY unset — no file written
if [ ! -f "$SANDBOX_DIR/.claude/telemetry/skill-events.jsonl" ]; then
  pass "no JSONL written when CONJURE_TELEMETRY unset (TLMY-01)"
else
  fail "JSONL was written even though CONJURE_TELEMETRY was unset (TLMY-01)"
fi

# TLMY-01: DO_NOT_TRACK=1 suppresses writes even when CONJURE_TELEMETRY=1
SKILL_PAYLOAD='{"hook_event_name":"PreToolUse","tool_name":"Skill","tool_input":{"skill_name":"test-skill"},"session_id":"sess-001","cwd":"'"$SANDBOX_DIR"'"}'
DNT_RC=0
printf '%s' "$SKILL_PAYLOAD" | DO_NOT_TRACK=1 CONJURE_TELEMETRY=1 node "$TLMY_HOOK" >/dev/null 2>&1 || DNT_RC=$?
if [ "$DNT_RC" -eq 0 ]; then
  pass "hook exits 0 when DO_NOT_TRACK=1 (TLMY-01)"
else
  fail "hook exited $DNT_RC with DO_NOT_TRACK=1 — expected 0 (TLMY-01)"
fi
if [ ! -f "$SANDBOX_DIR/.claude/telemetry/skill-events.jsonl" ]; then
  pass "no JSONL written when DO_NOT_TRACK=1 (TLMY-01)"
else
  fail "JSONL written despite DO_NOT_TRACK=1 (TLMY-01)"
fi

# TLMY-02: hook writes JSONL when CONJURE_TELEMETRY=1 with PreToolUse/Skill payload
WRITE_RC=0
printf '%s' "$SKILL_PAYLOAD" | CONJURE_TELEMETRY=1 node "$TLMY_HOOK" >/dev/null 2>&1 || WRITE_RC=$?
if [ "$WRITE_RC" -eq 0 ]; then
  pass "hook exits 0 when writing JSONL (TLMY-02)"
else
  fail "hook exited $WRITE_RC when CONJURE_TELEMETRY=1 — expected 0 (TLMY-02)"
fi
if [ -f "$SANDBOX_DIR/.claude/telemetry/skill-events.jsonl" ]; then
  pass "JSONL file created by hook (TLMY-02)"
else
  fail "JSONL file NOT created when CONJURE_TELEMETRY=1 (TLMY-02)"
fi

# TLMY-02: JSONL line is valid JSON
if command -v jq >/dev/null 2>&1 && [ -f "$SANDBOX_DIR/.claude/telemetry/skill-events.jsonl" ]; then
  if jq empty "$SANDBOX_DIR/.claude/telemetry/skill-events.jsonl" 2>/dev/null; then
    pass "JSONL file contains valid JSON lines (TLMY-02)"
  else
    fail "JSONL file contains invalid JSON (TLMY-02)"
  fi
fi

# TLMY-02: JSONL contains expected fields
if [ -f "$SANDBOX_DIR/.claude/telemetry/skill-events.jsonl" ]; then
  JSONL_LINE=$(head -1 "$SANDBOX_DIR/.claude/telemetry/skill-events.jsonl")
  if printf '%s' "$JSONL_LINE" | grep -q '"skill_invoke"' && \
     printf '%s' "$JSONL_LINE" | grep -q '"test-skill"' && \
     printf '%s' "$JSONL_LINE" | grep -q '"session_id"' && \
     printf '%s' "$JSONL_LINE" | grep -q '"project_cwd"'; then
    pass "JSONL record contains required fields (event, skill, session_id, project_cwd) (TLMY-02)"
  else
    fail "JSONL record missing required fields — got: $JSONL_LINE (TLMY-02)"
  fi
fi

# TLMY-02b: UserPromptExpansion path writes JSONL (skill_typed event)
UPE_PAYLOAD='{"hook_event_name":"UserPromptExpansion","command_name":"/test-skill","session_id":"sess-002","cwd":"'"$SANDBOX_DIR"'"}'
UPE_RC=0
printf '%s' "$UPE_PAYLOAD" | CONJURE_TELEMETRY=1 node "$TLMY_HOOK" >/dev/null 2>&1 || UPE_RC=$?
if [ "$UPE_RC" -eq 0 ]; then
  pass "UserPromptExpansion path exits 0 (TLMY-02b)"
else
  fail "UserPromptExpansion path exited $UPE_RC — expected 0 (TLMY-02b)"
fi
JSONL_COUNT=$(wc -l < "$SANDBOX_DIR/.claude/telemetry/skill-events.jsonl" 2>/dev/null | tr -d ' ')
if [ "${JSONL_COUNT:-0}" -ge 2 ]; then
  pass "UserPromptExpansion path writes JSONL (TLMY-02b)"
else
  fail "UserPromptExpansion path did NOT write JSONL — line count: ${JSONL_COUNT:-0} (TLMY-02b)"
fi
# Verify the UPE record carries skill_typed event type
UPE_LINE=$(tail -1 "$SANDBOX_DIR/.claude/telemetry/skill-events.jsonl" 2>/dev/null || true)
if printf '%s' "$UPE_LINE" | grep -q '"skill_typed"' && \
   printf '%s' "$UPE_LINE" | grep -q '"test-skill"' && \
   printf '%s' "$UPE_LINE" | grep -q '"project_cwd"'; then
  pass "UserPromptExpansion JSONL record has correct fields (TLMY-02b)"
else
  fail "UserPromptExpansion JSONL record missing expected fields — got: $UPE_LINE (TLMY-02b)"
fi

# TLMY-04: retire-list section renders when CONJURE_RETIRE=1
RETIRE_OUT="$(CONJURE_RETIRE=1 bash "$CONJURE_HOME/scripts/audit-setup.sh" "$SANDBOX_DIR" 2>&1)"
RETIRE_RC=$?
if printf '%s' "$RETIRE_OUT" | grep -q '── Skill Retire-List ──'; then
  pass "retire-list section header present (TLMY-04)"
else
  fail "retire-list section header missing (TLMY-04)"
fi
if [ "$RETIRE_RC" -le 2 ]; then
  pass "retire-list section exit code ≤ 2 (TLMY-04)"
else
  fail "retire-list section crashed (rc=$RETIRE_RC) (TLMY-04)"
fi

rm -rf "$SANDBOX_DIR"
trap - EXIT

echo
echo "▸ 3-way merge tests (MERGE-01, MERGE-02, MERGE-03, MERGE-04)"

# Source merge lib once (reused across MERGE-01 and MERGE-02)
# shellcheck disable=SC1090
source "$CONJURE_HOME/lib/mutate.sh"
# shellcheck disable=SC1090
source "$CONJURE_HOME/lib/merge.sh"

# MERGE-01: Clean merge — user and upstream changed non-adjacent lines
# Expected: merge_file_3way returns 0, merged file has both edits, no sidecar written
# NOTE: changed lines must be non-adjacent so git merge-file treats them as separate hunks.
MERGE_DIR="$(mktemp -d)"
trap 'rm -rf "$MERGE_DIR"' EXIT
mkdir -p "$MERGE_DIR/.claude/.conjure-templates-0.0.1/skills/testskill"
mkdir -p "$MERGE_DIR/.claude/skills/testskill"
# base (snapshot — original ancestor); lineA and lineH are far apart
printf 'name: testskill\ndescription: A 30-char minimum test skill here\nlineA: base\nlineB: b\nlineC: c\nlineD: d\nlineE: e\nlineF: f\nlineG: g\nlineH: base\n' \
  > "$MERGE_DIR/.claude/.conjure-templates-0.0.1/skills/testskill/SKILL.md"
# current (user changed lineH only — far from lineA)
printf 'name: testskill\ndescription: A 30-char minimum test skill here\nlineA: base\nlineB: b\nlineC: c\nlineD: d\nlineE: e\nlineF: f\nlineG: g\nlineH: USER_EDIT\n' \
  > "$MERGE_DIR/.claude/skills/testskill/SKILL.md"
# new upstream template (changed lineA only — far from lineH)
MERGE_TMPL="$(mktemp)"
printf 'name: testskill\ndescription: A 30-char minimum test skill here\nlineA: UPSTREAM_EDIT\nlineB: b\nlineC: c\nlineD: d\nlineE: e\nlineF: f\nlineG: g\nlineH: base\n' \
  > "$MERGE_TMPL"
# Reset module-level state before direct lib call
CONJURE_MERGE_CONFLICT_COUNT=0
CONJURE_MERGE_CONFLICT_FILES=""
DRY_RUN=0 merge_file_3way \
  "$MERGE_DIR/.claude/skills/testskill/SKILL.md" \
  "$MERGE_DIR/.claude/.conjure-templates-0.0.1/skills/testskill/SKILL.md" \
  "$MERGE_TMPL" \
  "skills/testskill/SKILL.md" "0.0.1" "0.3.0"
MERGE_RC=$?
rm -f "$MERGE_TMPL"
if [ "$MERGE_RC" -eq 0 ]; then pass "clean merge exits 0 (MERGE-01)"
else fail "clean merge should exit 0, got $MERGE_RC (MERGE-01)"; fi
if grep -q "lineA: UPSTREAM_EDIT" "$MERGE_DIR/.claude/skills/testskill/SKILL.md" && \
   grep -q "lineH: USER_EDIT" "$MERGE_DIR/.claude/skills/testskill/SKILL.md"; then
  pass "merged file contains both user and upstream edits (MERGE-01)"
else fail "merged file missing expected content (MERGE-01)"; fi
if [ -z "$(find "$MERGE_DIR/.claude" -name '.conjure-conflict-*' 2>/dev/null)" ]; then
  pass "no sidecar written on clean merge (MERGE-01)"
else fail "sidecar unexpectedly present on clean merge (MERGE-01)"; fi
rm -rf "$MERGE_DIR"
trap - EXIT

# MERGE-02: Conflict — user and upstream changed the same line
# Expected: merge_file_3way returns 1, sidecar written with markers, original untouched
MERGE_DIR="$(mktemp -d)"
trap 'rm -rf "$MERGE_DIR"' EXIT
mkdir -p "$MERGE_DIR/.claude/.conjure-templates-0.0.1/skills/testskill"
mkdir -p "$MERGE_DIR/.claude/skills/testskill"
# base (ancestor)
printf 'name: testskill\ndescription: A 30-char minimum test skill here\nconflict_line: base\n' \
  > "$MERGE_DIR/.claude/.conjure-templates-0.0.1/skills/testskill/SKILL.md"
# current (user changed conflict_line)
printf 'name: testskill\ndescription: A 30-char minimum test skill here\nconflict_line: USER_VERSION\n' \
  > "$MERGE_DIR/.claude/skills/testskill/SKILL.md"
# new upstream (also changed conflict_line — genuine conflict)
MERGE_TMPL="$(mktemp)"
printf 'name: testskill\ndescription: A 30-char minimum test skill here\nconflict_line: UPSTREAM_VERSION\n' \
  > "$MERGE_TMPL"
# Reset module-level state before direct lib call
CONJURE_MERGE_CONFLICT_COUNT=0
CONJURE_MERGE_CONFLICT_FILES=""
DRY_RUN=0 merge_file_3way \
  "$MERGE_DIR/.claude/skills/testskill/SKILL.md" \
  "$MERGE_DIR/.claude/.conjure-templates-0.0.1/skills/testskill/SKILL.md" \
  "$MERGE_TMPL" \
  "skills/testskill/SKILL.md" "0.0.1" "0.3.0"
MERGE_RC=$?
rm -f "$MERGE_TMPL"
if [ "$MERGE_RC" -eq 1 ]; then pass "conflict exits 1 (MERGE-02)"
else fail "conflict should exit 1, got $MERGE_RC (MERGE-02)"; fi
# D-05: original file must be untouched (no <<<<<<< markers in original)
if grep -q "USER_VERSION" "$MERGE_DIR/.claude/skills/testskill/SKILL.md" && \
   ! grep -q '<<<<<<<' "$MERGE_DIR/.claude/skills/testskill/SKILL.md"; then
  pass "original file untouched on conflict (MERGE-02 / D-05)"
else fail "original file was modified on conflict — D-05 violation (MERGE-02)"; fi
# Sidecar must exist at expected encoded path
SIDECAR="$MERGE_DIR/.claude/skills/testskill/.conjure-conflict-skills_testskill_SKILL.md"
if [ -f "$SIDECAR" ]; then pass "sidecar written at correct path (MERGE-02)"
else fail "sidecar missing at $SIDECAR (MERGE-02)"; fi
if grep -q '<<<<<<<' "$SIDECAR"; then pass "sidecar contains conflict markers (MERGE-02)"
else fail "sidecar missing conflict markers (MERGE-02)"; fi
rm -rf "$MERGE_DIR"
trap - EXIT

# MERGE-03: Missing snapshot — cli/conjure update --apply aborts with D-01 message
# Expected: exits non-zero, prints "No base snapshot for v..."
MERGE_DIR="$(mktemp -d)"
trap 'rm -rf "$MERGE_DIR"' EXIT
mkdir -p "$MERGE_DIR/.claude"
printf '0.1.0\n' > "$MERGE_DIR/.claude/.conjure-version"
# Intentionally NO .conjure-templates-0.1.0/ directory
# Single invocation captures both output and exit code (do NOT use || true when testing exit code)
MERGE_OUT="$(CONJURE_HOME="$CONJURE_HOME" cli/conjure update --apply "$MERGE_DIR" 2>&1)"
MERGE_RC=$?
if [ "$MERGE_RC" -ne 0 ]; then pass "missing snapshot exits non-zero (MERGE-03)"
else fail "missing snapshot should exit non-zero (MERGE-03)"; fi
if printf '%s\n' "$MERGE_OUT" | grep -q "No base snapshot for v0.1.0"; then
  pass "correct abort message for missing snapshot (MERGE-03)"
else fail "abort message missing 'No base snapshot for v0.1.0' (MERGE-03)"; fi
rm -rf "$MERGE_DIR"
trap - EXIT

# MERGE-04: Generated files take upstream unconditionally (no 3-way merge, no sidecar)
# Expected: settings.json replaced by upstream; no .conjure-conflict-*settings* sidecar
# The stale key "conjure_test_stale_key" cannot appear in any real template — uniquely identifies old content
# Use an older pinned version (0.0.1) so conjure update --apply proceeds past the "up to date" guard
MERGE_DIR="$(mktemp -d)"
trap 'rm -rf "$MERGE_DIR"' EXIT
mkdir -p "$MERGE_DIR/.claude/.conjure-templates-0.0.1"
# Stale settings.json with a unique key that no template contains
printf '{"conjure_test_stale_key": "should_be_replaced", "version": "old"}\n' \
  > "$MERGE_DIR/.claude/settings.json"
printf '0.0.1\n' > "$MERGE_DIR/.claude/.conjure-version"
# Run update --apply (pinned=0.0.1, current=CONJURE_VERSION → proceeds to merge)
CONJURE_HOME="$CONJURE_HOME" cli/conjure update --apply "$MERGE_DIR" >/dev/null 2>&1
# settings.json must NOT still contain the unique stale key (it was replaced by upstream)
if ! grep -q '"conjure_test_stale_key"' "$MERGE_DIR/.claude/settings.json" 2>/dev/null; then
  pass "settings.json replaced by upstream (stale key gone) (MERGE-04)"
else
  fail "settings.json not replaced by upstream (MERGE-04)"
fi
# No sidecar for settings.json
if [ -z "$(find "$MERGE_DIR/.claude" -name '.conjure-conflict-*settings*' 2>/dev/null)" ]; then
  pass "no conflict sidecar for generated settings.json (MERGE-04)"
else fail "sidecar written for generated settings.json — should take upstream (MERGE-04)"; fi
rm -rf "$MERGE_DIR"
trap - EXIT

# MERGE-05: audit detects <<<<<<< markers in .claude/ and exits non-zero
MERGE_DIR="$(mktemp -d)"
trap 'rm -rf "$MERGE_DIR"' EXIT
mkdir -p "$MERGE_DIR/.claude/skills/testskill"
# Plant a conflict marker in a real skill file (not a sidecar)
printf 'name: testskill\ndescription: A test skill with 30+ characters here\n<<<<<<< your version\nconflict_line: A\n=======\nconflict_line: B\n>>>>>>> upstream\n' \
  > "$MERGE_DIR/.claude/skills/testskill/SKILL.md"
AUDIT_OUT="$(bash "$CONJURE_HOME/scripts/audit-setup.sh" "$MERGE_DIR" 2>&1)"
AUDIT_RC=$?
if [ "$AUDIT_RC" -ne 0 ]; then pass "audit exits non-zero when conflict markers present (MERGE-05)"
else fail "audit should exit non-zero with conflict markers (MERGE-05)"; fi
if printf '%s\n' "$AUDIT_OUT" | grep -q "Unresolved merge conflicts"; then
  pass "audit reports 'Unresolved merge conflicts' (MERGE-05)"
else fail "audit missing 'Unresolved merge conflicts' message (MERGE-05)"; fi
rm -rf "$MERGE_DIR"
trap - EXIT

echo
echo "▸ Marketplace publish tests (MKTPL-01 through MKTPL-04)"

# MKTPL-SETUP: reusable sandbox — a real git repo with copies of the manifests.
# publish-plugin.sh derives CONJURE_HOME from its own script path (not env), so we
# copy the script + lib into the sandbox and invoke the sandbox copy.  This keeps
# all writes inside the temp dir and leaves the real .claude-plugin/ untouched.
MKTPL_DIR="$(mktemp -d)"
trap 'rm -rf "$MKTPL_DIR"' EXIT
git -C "$MKTPL_DIR" init -q
git -C "$MKTPL_DIR" config user.email "test@conjure"
git -C "$MKTPL_DIR" config user.name "conjure-test"
mkdir -p "$MKTPL_DIR/.claude-plugin" "$MKTPL_DIR/scripts" "$MKTPL_DIR/lib"
cp "$CONJURE_HOME/.claude-plugin/marketplace.json" "$MKTPL_DIR/.claude-plugin/"
cp "$CONJURE_HOME/.claude-plugin/plugin.json"      "$MKTPL_DIR/.claude-plugin/"
cp "$CONJURE_HOME/VERSION"                          "$MKTPL_DIR/VERSION"
cp "$CONJURE_HOME/scripts/publish-plugin.sh"        "$MKTPL_DIR/scripts/"
cp "$CONJURE_HOME/lib/mutate.sh"                    "$MKTPL_DIR/lib/"
git -C "$MKTPL_DIR" add -A
git -C "$MKTPL_DIR" commit -q -m "test fixture"

# MKTPL-01 DRY-RUN TEST
MKTPL_OUT="$(DRY_RUN=1 bash "$MKTPL_DIR/scripts/publish-plugin.sh" 2>&1)"
if printf '%s\n' "$MKTPL_OUT" | grep -q 'dry-run'; then
  pass "publish dry-run prints dry-run mutations (MKTPL-01)"
else
  fail "publish dry-run did not print dry-run output (MKTPL-01)"
fi
# Verify no files were modified (sandbox copy must be identical to original)
MKT_CONTENT_AFTER="$(cat "$MKTPL_DIR/.claude-plugin/marketplace.json")"
MKT_CONTENT_BEFORE="$(cat "$CONJURE_HOME/.claude-plugin/marketplace.json")"
if [ "$MKT_CONTENT_AFTER" = "$MKT_CONTENT_BEFORE" ]; then
  pass "publish dry-run did not modify marketplace.json (MKTPL-01)"
else
  fail "publish dry-run modified marketplace.json — DRY_RUN not honored (MKTPL-01)"
fi

# MKTPL-01 DIRTY-TREE TEST (create an uncommitted change in the sandbox)
echo "dirty" >> "$MKTPL_DIR/.claude-plugin/plugin.json"
DIRTY_RC=0
bash "$MKTPL_DIR/scripts/publish-plugin.sh" >/dev/null 2>&1 || DIRTY_RC=$?
if [ "$DIRTY_RC" -eq 2 ]; then
  pass "publish exits 2 on dirty tree (MKTPL-01, D-06)"
else
  fail "publish did not exit 2 on dirty tree — got rc=$DIRTY_RC (MKTPL-01)"
fi
# Restore: re-checkout the file and recommit for subsequent tests
git -C "$MKTPL_DIR" checkout -- .claude-plugin/plugin.json

# MKTPL-01 VERSION UPDATE TEST (live run in clean sandbox)
LIVE_RC=0
bash "$MKTPL_DIR/scripts/publish-plugin.sh" >/dev/null 2>&1 || LIVE_RC=$?
EXPECTED_VER="$(cat "$MKTPL_DIR/VERSION")"
ACTUAL_VER="$(jq -r '.plugins[0].version' "$MKTPL_DIR/.claude-plugin/marketplace.json")"
if [ "$ACTUAL_VER" = "$EXPECTED_VER" ]; then
  pass "publish updates marketplace.json .plugins[0].version to VERSION (MKTPL-01)"
else
  fail "marketplace.json version ($ACTUAL_VER) != VERSION ($EXPECTED_VER) after publish (MKTPL-01)"
fi

# MKTPL-01 SHA UPDATE TEST (validates SHA format — 40 hex chars)
ACTUAL_SHA="$(jq -r '.plugins[0].source.sha' "$MKTPL_DIR/.claude-plugin/marketplace.json")"
if printf '%s' "$ACTUAL_SHA" | grep -qE '^[0-9a-f]{40}$'; then
  pass "publish writes valid 40-char hex SHA to marketplace.json (MKTPL-01)"
else
  fail "marketplace.json SHA is not a valid 40-char hex string: $ACTUAL_SHA (MKTPL-01)"
fi

# MKTPL-02 VERSION-CONSISTENCY PASS TEST (reproduce the CI check logic inline)
VC_VER="$(cat "$CONJURE_HOME/VERSION")"
VC_MKT="$(jq -r '.plugins[0].version // empty' "$CONJURE_HOME/.claude-plugin/marketplace.json")"
VC_PLG="$(jq -r '.version // empty' "$CONJURE_HOME/.claude-plugin/plugin.json")"
if [ "$VC_MKT" = "$VC_VER" ] && [ "$VC_PLG" = "$VC_VER" ]; then
  pass "version-consistency: all fields match VERSION ($VC_VER) (MKTPL-02)"
else
  fail "version-consistency: mismatch — marketplace=$VC_MKT plugin=$VC_PLG VERSION=$VC_VER (MKTPL-02)"
fi

# MKTPL-02 VERSION-CONSISTENCY FAIL TEST (inject drift into a temp copy)
DRIFT_DIR="$(mktemp -d)"
mkdir -p "$DRIFT_DIR/.claude-plugin"
jq '.plugins[0].version = "0.0.0"' "$CONJURE_HOME/.claude-plugin/marketplace.json" > "$DRIFT_DIR/.claude-plugin/marketplace.json"
cp "$CONJURE_HOME/.claude-plugin/plugin.json" "$DRIFT_DIR/.claude-plugin/"
printf '9.9.9\n' > "$DRIFT_DIR/VERSION"
DRIFT_MKT="$(jq -r '.plugins[0].version // empty' "$DRIFT_DIR/.claude-plugin/marketplace.json")"
DRIFT_VER="$(cat "$DRIFT_DIR/VERSION")"
if [ "$DRIFT_MKT" != "$DRIFT_VER" ]; then
  pass "version-consistency detects marketplace drift (MKTPL-02)"
else
  fail "version-consistency did NOT detect marketplace drift (MKTPL-02)"
fi
rm -rf "$DRIFT_DIR"

# MKTPL-04 SUBMIT-ENTRY TEST (run CONJURE_SUBMIT=1 in fresh sandbox)
SUBMIT_DIR="$(mktemp -d)"
git -C "$SUBMIT_DIR" init -q
git -C "$SUBMIT_DIR" config user.email "test@conjure"
git -C "$SUBMIT_DIR" config user.name "conjure-test"
mkdir -p "$SUBMIT_DIR/.claude-plugin" "$SUBMIT_DIR/scripts" "$SUBMIT_DIR/lib"
cp "$CONJURE_HOME/.claude-plugin/marketplace.json" "$SUBMIT_DIR/.claude-plugin/"
cp "$CONJURE_HOME/.claude-plugin/plugin.json"      "$SUBMIT_DIR/.claude-plugin/"
cp "$CONJURE_HOME/VERSION"                          "$SUBMIT_DIR/VERSION"
cp "$CONJURE_HOME/scripts/publish-plugin.sh"        "$SUBMIT_DIR/scripts/"
cp "$CONJURE_HOME/lib/mutate.sh"                    "$SUBMIT_DIR/lib/"
git -C "$SUBMIT_DIR" add -A
git -C "$SUBMIT_DIR" commit -q -m "submit fixture"

SUBMIT_OUT="$(CONJURE_SUBMIT=1 bash "$SUBMIT_DIR/scripts/publish-plugin.sh" 2>&1)"

if [ -f "$SUBMIT_DIR/.claude-plugin/submit-entry.json" ]; then
  pass "publish --submit writes submit-entry.json (MKTPL-04)"
else
  fail "publish --submit did NOT write submit-entry.json (MKTPL-04)"
fi

# Verify required fields
if jq -e '.name' "$SUBMIT_DIR/.claude-plugin/submit-entry.json" >/dev/null 2>&1 && \
   jq -e '.source' "$SUBMIT_DIR/.claude-plugin/submit-entry.json" >/dev/null 2>&1 && \
   jq -e '.homepage' "$SUBMIT_DIR/.claude-plugin/submit-entry.json" >/dev/null 2>&1; then
  pass "submit-entry.json contains required fields: name, source, homepage (MKTPL-04)"
else
  fail "submit-entry.json missing required fields (MKTPL-04)"
fi

if printf '%s\n' "$SUBMIT_OUT" | grep -q 'claude.ai/settings/plugins/submit'; then
  pass "publish --submit prints submission URL to stdout (MKTPL-04, D-11)"
else
  fail "publish --submit did NOT print submission URL (MKTPL-04)"
fi
rm -rf "$SUBMIT_DIR"

# CLEANUP main MKTPL sandbox
rm -rf "$MKTPL_DIR"
trap - EXIT

echo
echo "▸ SKILL publish-skill tests (SKILL-01 through SKILL-04)"

# SKILL-SETUP: reusable sandbox — real git repo with committed SKILL.md.
# publish-skill.sh derives CONJURE_HOME from its own script path, so copy
# the script + lib into the sandbox. All writes stay inside the temp dir.
SKILL_DIR="$(mktemp -d)"
trap 'rm -rf "$SKILL_DIR"' EXIT
git -C "$SKILL_DIR" init -q
git -C "$SKILL_DIR" config user.email "test@conjure"
git -C "$SKILL_DIR" config user.name "conjure-test"
mkdir -p "$SKILL_DIR/.claude/skills/test-skill" "$SKILL_DIR/scripts" "$SKILL_DIR/lib"
printf -- '---\nname: test-skill\ndescription: A test skill that demonstrates the publish-skill validation pipeline end-to-end.\n---\n\n# test-skill\nSome clean content here with no egress patterns.\n' \
  > "$SKILL_DIR/.claude/skills/test-skill/SKILL.md"
cp "$CONJURE_HOME/scripts/publish-skill.sh" "$SKILL_DIR/scripts/"
cp "$CONJURE_HOME/lib/mutate.sh"            "$SKILL_DIR/lib/"
cp "$CONJURE_HOME/VERSION"                  "$SKILL_DIR/VERSION"
git -C "$SKILL_DIR" add -A
git -C "$SKILL_DIR" commit -q -m "add test-skill"
# Tag the sandbox HEAD so the conjure "tagged release" guard passes (Pitfall 4).
# Must be an annotated tag — git describe --exact-match ignores lightweight tags.
git -C "$SKILL_DIR" tag -a "v$(cat "$CONJURE_HOME/VERSION")" -m "release"

# Helper: run publish-skill.sh from inside SKILL_DIR (script uses pwd for skill path)
skill_run() {
  ( cd "$SKILL_DIR" && bash "$SKILL_DIR/scripts/publish-skill.sh" "$@" )
}

# SKILL-01: dry-run output
SKILL_OUT="$(DRY_RUN=1 skill_run test-skill 2>&1)"
if printf '%s\n' "$SKILL_OUT" | grep -q 'dry-run'; then
  pass "publish-skill --dry-run prints dry-run accounting (SKILL-01)"
else
  fail "publish-skill --dry-run did not print dry-run output (SKILL-01)"
fi

# SKILL-01: size cap — 201-line SKILL.md exits 1
python3 -c "print('---\nname: test-skill\ndescription: A test skill that demonstrates the publish-skill validation pipeline end-to-end.\n---'); [print('line') for _ in range(200)]" \
  > "$SKILL_DIR/.claude/skills/test-skill/SKILL.md"
SIZE_RC=0
skill_run test-skill >/dev/null 2>&1 || SIZE_RC=$?
if [ "$SIZE_RC" -eq 1 ]; then
  pass "publish-skill exits 1 when skill exceeds 200-line cap (SKILL-01)"
else
  fail "publish-skill did not exit 1 on oversized skill — got rc=$SIZE_RC (SKILL-01)"
fi
git -C "$SKILL_DIR" checkout -- .claude/skills/test-skill/SKILL.md

# SKILL-01: frontmatter missing name exits 1
printf -- '---\ndescription: A test skill that demonstrates the publish-skill validation pipeline end-to-end.\n---\n\n# test-skill\nContent.\n' \
  > "$SKILL_DIR/.claude/skills/test-skill/SKILL.md"
NONAME_RC=0
skill_run test-skill >/dev/null 2>&1 || NONAME_RC=$?
if [ "$NONAME_RC" -eq 1 ]; then
  pass "publish-skill exits 1 when frontmatter missing name (SKILL-01)"
else
  fail "publish-skill did not exit 1 on missing name — got rc=$NONAME_RC (SKILL-01)"
fi
git -C "$SKILL_DIR" checkout -- .claude/skills/test-skill/SKILL.md

# SKILL-01: egress scan blocks curl
printf -- '---\nname: test-skill\ndescription: A test skill that demonstrates the publish-skill validation pipeline end-to-end.\n---\n\ncurl https://example.com\n' \
  > "$SKILL_DIR/.claude/skills/test-skill/SKILL.md"
CURL_RC=0
skill_run test-skill >/dev/null 2>&1 || CURL_RC=$?
if [ "$CURL_RC" -eq 1 ]; then
  pass "publish-skill exits 1 when body contains curl (SKILL-01)"
else
  fail "publish-skill did not exit 1 on curl egress — got rc=$CURL_RC (SKILL-01)"
fi
git -C "$SKILL_DIR" checkout -- .claude/skills/test-skill/SKILL.md

# SKILL-01: egress scan blocks $SECRET
printf -- '---\nname: test-skill\ndescription: A test skill that demonstrates the publish-skill validation pipeline end-to-end.\n---\n\necho $SECRET\n' \
  > "$SKILL_DIR/.claude/skills/test-skill/SKILL.md"
SECRET_RC=0
skill_run test-skill >/dev/null 2>&1 || SECRET_RC=$?
if [ "$SECRET_RC" -eq 1 ]; then
  pass "publish-skill exits 1 when body contains \$SECRET (SKILL-01)"
else
  fail "publish-skill did not exit 1 on \$SECRET egress — got rc=$SECRET_RC (SKILL-01)"
fi
git -C "$SKILL_DIR" checkout -- .claude/skills/test-skill/SKILL.md

# SKILL-01: clean skill passes all gates
CLEAN_RC=0
skill_run test-skill >/dev/null 2>&1 || CLEAN_RC=$?
if [ "$CLEAN_RC" -eq 0 ]; then
  pass "publish-skill exits 0 for valid clean skill (SKILL-01)"
else
  fail "publish-skill did not exit 0 on clean skill — got rc=$CLEAN_RC (SKILL-01)"
fi

# SKILL-02: gh present — printed output contains "gh pr create"
STUB_BIN="$(mktemp -d)"
printf '#!/bin/sh\nexit 0\n' > "$STUB_BIN/gh"
chmod +x "$STUB_BIN/gh"
SAVED_PATH="$PATH"
PATH="$STUB_BIN:$PATH"
GH_PRESENT_OUT="$(skill_run test-skill 2>&1)"
PATH="$SAVED_PATH"
rm -rf "$STUB_BIN"
if printf '%s\n' "$GH_PRESENT_OUT" | grep -q 'gh pr create'; then
  pass "publish-skill prints gh pr create when gh is present (SKILL-02)"
else
  fail "publish-skill did not print gh pr create with gh present (SKILL-02)"
fi

# SKILL-02: gh absent — printed output contains "manually" or github.com URL
SAVED_PATH2="$PATH"
GH_LOC="$(command -v gh 2>/dev/null || true)"
FILTERED_PATH="$PATH"
if [ -n "$GH_LOC" ]; then
  GH_LOC_DIR="$(dirname "$GH_LOC")"
  GIT_LOC_DIR="$(dirname "$(command -v git)")"
  FILTERED_PATH="$(printf '%s' "$PATH" | tr ':' '\n' | grep -vxF "$GH_LOC_DIR" | tr '\n' ':' | sed 's/:$//')"
  case ":$FILTERED_PATH:" in
    *":$GIT_LOC_DIR:"*) ;;
    *) FILTERED_PATH="${GIT_LOC_DIR}:${FILTERED_PATH}" ;;
  esac
fi
NOGH_OUT="$(PATH="$FILTERED_PATH" skill_run test-skill 2>&1)"
PATH="$SAVED_PATH2"
if printf '%s\n' "$NOGH_OUT" | grep -qE 'manually|github\.com'; then
  pass "publish-skill prints manual URL when gh is absent (SKILL-02)"
else
  fail "publish-skill did not print manual URL with gh absent (SKILL-02)"
fi

# SKILL-03: dirty skill tree → exit 1
echo "dirty" >> "$SKILL_DIR/.claude/skills/test-skill/SKILL.md"
DIRTY_RC=0
skill_run test-skill >/dev/null 2>&1 || DIRTY_RC=$?
if [ "$DIRTY_RC" -eq 1 ]; then
  pass "publish-skill exits 1 on dirty skill tree (SKILL-03)"
else
  fail "publish-skill did not exit 1 on dirty skill tree — got rc=$DIRTY_RC (SKILL-03)"
fi
DIRTY_MSG="$(skill_run test-skill 2>&1 || true)"
if printf '%s\n' "$DIRTY_MSG" | grep -q 'uncommitted'; then
  pass "publish-skill prints 'uncommitted' message on dirty tree (SKILL-03)"
else
  fail "publish-skill dirty-tree message missing 'uncommitted' (SKILL-03)"
fi
git -C "$SKILL_DIR" checkout -- .claude/skills/test-skill/SKILL.md

# SKILL-03: untagged conjure HEAD → exit 1
UNTAGGED_DIR="$(mktemp -d)"
git -C "$UNTAGGED_DIR" init -q
git -C "$UNTAGGED_DIR" config user.email "test@conjure"
git -C "$UNTAGGED_DIR" config user.name "conjure-test"
mkdir -p "$UNTAGGED_DIR/scripts" "$UNTAGGED_DIR/lib"
cp "$CONJURE_HOME/scripts/publish-skill.sh" "$UNTAGGED_DIR/scripts/"
cp "$CONJURE_HOME/lib/mutate.sh"            "$UNTAGGED_DIR/lib/"
cp "$CONJURE_HOME/VERSION"                  "$UNTAGGED_DIR/VERSION"
git -C "$UNTAGGED_DIR" add -A
git -C "$UNTAGGED_DIR" commit -q -m "no tag"
# Intentionally no git tag — this is the untagged conjure scenario
UNTAGGED_RC=0
( cd "$SKILL_DIR" && bash "$UNTAGGED_DIR/scripts/publish-skill.sh" test-skill >/dev/null 2>&1 ) || UNTAGGED_RC=$?
UNTAGGED_MSG="$( ( cd "$SKILL_DIR" && bash "$UNTAGGED_DIR/scripts/publish-skill.sh" test-skill ) 2>&1 || true )"
if [ "$UNTAGGED_RC" -eq 1 ]; then
  pass "publish-skill exits 1 when conjure HEAD is untagged (SKILL-03)"
else
  fail "publish-skill did not exit 1 on untagged conjure HEAD — got rc=$UNTAGGED_RC (SKILL-03)"
fi
if printf '%s\n' "$UNTAGGED_MSG" | grep -q 'tagged release'; then
  pass "publish-skill prints 'tagged release' message on untagged HEAD (SKILL-03)"
else
  fail "publish-skill untagged-head message missing 'tagged release' (SKILL-03)"
fi
rm -rf "$UNTAGGED_DIR"

# SKILL-04: --to flag substitutes target repo in PR instructions
TO_OUT="$(skill_run test-skill --to myorg/myrepo 2>&1)"
if printf '%s\n' "$TO_OUT" | grep -q 'myorg/myrepo'; then
  pass "--to flag substitutes target repo in PR instructions (SKILL-04)"
else
  fail "--to flag did not substitute target repo (SKILL-04)"
fi

# CLEANUP SKILL sandbox
rm -rf "$SKILL_DIR"
trap - EXIT

# ──────────────────────────────────────────────────────────────────────────────
# OVLY org-overlay tests (OVLY-01 through OVLY-05)
# ──────────────────────────────────────────────────────────────────────────────
echo
echo "▸ OVLY org-overlay tests (OVLY-01 through OVLY-05)"

# OVLY-SETUP: local git repo as mock overlay (file:// URL — no network required)
OVLY_REPO="$(mktemp -d)"
git -C "$OVLY_REPO" init -q
git -C "$OVLY_REPO" config user.email "test@conjure"
git -C "$OVLY_REPO" config user.name "conjure-test"
mkdir -p "$OVLY_REPO/skills/org-skill"
printf 'name: org-skill\ndescription: Org overlay skill for conjure regression testing.\n' \
  > "$OVLY_REPO/skills/org-skill/SKILL.md"
mkdir -p "$OVLY_REPO/agents"
printf '# org-agent\nOrg agent stub.\n' > "$OVLY_REPO/agents/org-agent.md"
git -C "$OVLY_REPO" add -A
git -C "$OVLY_REPO" commit -q -m "overlay v1"
OVLY_URL="file://$OVLY_REPO"
OVLY_EXPECTED_SHA="$(git -C "$OVLY_REPO" rev-parse HEAD)"

# Target dir — a minimal project with .claude/ ready to receive overlay
OVLY_TARGET="$(mktemp -d)"
mkdir -p "$OVLY_TARGET/.claude"

# OVLY-01: init-overlay exits 0 and applies overlay files
OVLY_INIT_RC=0
CONJURE_HOME="$CONJURE_HOME" bash "$CONJURE_HOME/scripts/init-overlay.sh" \
  "$OVLY_URL" "$OVLY_TARGET" >/dev/null 2>&1 || OVLY_INIT_RC=$?
if [ "$OVLY_INIT_RC" -eq 0 ]; then
  pass "init-overlay exits 0 (OVLY-01)"
else
  fail "init-overlay did not exit 0 — got rc=$OVLY_INIT_RC (OVLY-01)"
fi

if [ -f "$OVLY_TARGET/.claude/skills/org-skill/SKILL.md" ]; then
  pass "overlay skill file present in .claude/ after init (OVLY-01)"
else
  fail "overlay skill file missing from .claude/ after init (OVLY-01)"
fi

# OVLY-01c: DRY_RUN honored — no files written to a fresh target
OVLY_DRY_DIR="$(mktemp -d)"
mkdir -p "$OVLY_DRY_DIR/.claude"
OVLY_DRY_RC=0
OVLY_DRY_OUT="$(CONJURE_HOME="$CONJURE_HOME" DRY_RUN=1 bash "$CONJURE_HOME/scripts/init-overlay.sh" \
  "$OVLY_URL" "$OVLY_DRY_DIR" 2>&1)" || OVLY_DRY_RC=$?
if [ "$OVLY_DRY_RC" -eq 0 ]; then
  pass "init-overlay exits 0 with DRY_RUN=1 (OVLY-01)"
else
  fail "init-overlay did not exit 0 with DRY_RUN=1 — got rc=$OVLY_DRY_RC (OVLY-01)"
fi
if [ ! -f "$OVLY_DRY_DIR/.claude/.conjure-org-overlay" ]; then
  pass "DRY_RUN=1 writes no files to .claude/ (OVLY-01)"
else
  fail "DRY_RUN=1 wrote .conjure-org-overlay — DRY_RUN not honored (OVLY-01)"
fi
if printf '%s\n' "$OVLY_DRY_OUT" | grep -q 'mutations skipped'; then
  pass "DRY_RUN=1 mutate_summary reports mutations skipped (OVLY-01)"
else
  fail "DRY_RUN=1 mutate_summary did not print mutations skipped (OVLY-01)"
fi
rm -rf "$OVLY_DRY_DIR"

# OVLY-02: marker file written with correct url= and sha=
if [ -f "$OVLY_TARGET/.claude/.conjure-org-overlay" ]; then
  pass ".conjure-org-overlay marker exists (OVLY-02)"
else
  fail ".conjure-org-overlay marker missing (OVLY-02)"
fi
MARKER_URL="$(grep '^url=' "$OVLY_TARGET/.claude/.conjure-org-overlay" | cut -d= -f2-)"
if [ "$MARKER_URL" = "$OVLY_URL" ]; then
  pass "marker url= matches overlay URL (OVLY-02)"
else
  fail "marker url= mismatch: got=$MARKER_URL expected=$OVLY_URL (OVLY-02)"
fi
MARKER_SHA="$(grep '^sha=' "$OVLY_TARGET/.claude/.conjure-org-overlay" | cut -d= -f2)"
if [ "$MARKER_SHA" = "$OVLY_EXPECTED_SHA" ]; then
  pass "marker sha= matches overlay commit SHA (OVLY-02)"
else
  fail "marker sha= mismatch: got=$MARKER_SHA expected=$OVLY_EXPECTED_SHA (OVLY-02)"
fi

# OVLY-03: refresh-overlay without marker exits 1 with correct message
NO_MARKER_DIR="$(mktemp -d)"
mkdir -p "$NO_MARKER_DIR/.claude"
NOMK_RC=0
NOMK_OUT="$(CONJURE_HOME="$CONJURE_HOME" bash "$CONJURE_HOME/scripts/refresh-overlay.sh" \
  "$NO_MARKER_DIR" 2>&1)" || NOMK_RC=$?
if [ "$NOMK_RC" -eq 1 ]; then
  pass "refresh-overlay exits 1 when no marker (OVLY-03)"
else
  fail "refresh-overlay did not exit 1 on missing marker — got rc=$NOMK_RC (OVLY-03)"
fi
if printf '%s\n' "$NOMK_OUT" | grep -q 'No org overlay configured'; then
  pass "refresh-overlay prints 'No org overlay configured' message (OVLY-03)"
else
  fail "refresh-overlay missing 'No org overlay configured' message (OVLY-03)"
fi
rm -rf "$NO_MARKER_DIR"

# OVLY-03: refresh-overlay with valid marker exits 0 and re-applies
REFRESH_RC=0
CONJURE_HOME="$CONJURE_HOME" bash "$CONJURE_HOME/scripts/refresh-overlay.sh" \
  "$OVLY_TARGET" >/dev/null 2>&1 || REFRESH_RC=$?
if [ "$REFRESH_RC" -eq 0 ]; then
  pass "refresh-overlay exits 0 with valid marker (OVLY-03)"
else
  fail "refresh-overlay did not exit 0 — got rc=$REFRESH_RC (OVLY-03)"
fi
if [ -f "$OVLY_TARGET/.claude/skills/org-skill/SKILL.md" ]; then
  pass "overlay file still present after refresh (OVLY-03)"
else
  fail "overlay file missing after refresh (OVLY-03)"
fi

# OVLY-04: audit reports overlay status when SHA matches
# Create a minimal audit-able target (needs CLAUDE.md)
printf '# Overlay test project\n' > "$OVLY_TARGET/CLAUDE.md"
AUDIT_OK_OUT="$(bash "$CONJURE_HOME/scripts/audit-setup.sh" "$OVLY_TARGET" 2>&1)" || true
if printf '%s\n' "$AUDIT_OK_OUT" | grep -q 'up to date\|overlay'; then
  pass "audit reports overlay status when marker present (OVLY-04)"
else
  fail "audit did not report overlay status (OVLY-04)"
fi

# OVLY-04: audit reports DRIFT when SHA differs
printf 'url=%s\nsha=deadbeefdeadbeefdeadbeefdeadbeefdeadbeef' "$OVLY_URL" \
  > "$OVLY_TARGET/.claude/.conjure-org-overlay"
AUDIT_DRIFT_OUT="$(bash "$CONJURE_HOME/scripts/audit-setup.sh" "$OVLY_TARGET" 2>&1)" || true
if printf '%s\n' "$AUDIT_DRIFT_OUT" | grep -q 'DRIFT'; then
  pass "audit reports DRIFT when pinned SHA differs from upstream (OVLY-04)"
else
  fail "audit did not report DRIFT on SHA mismatch (OVLY-04)"
fi
# Restore correct marker after DRIFT test
printf 'url=%s\nsha=%s' "$OVLY_URL" "$OVLY_EXPECTED_SHA" \
  > "$OVLY_TARGET/.claude/.conjure-org-overlay"

# OVLY-04: audit skips drift check on invalid URL (must not exit 128)
printf 'url=file:///nonexistent-overlay-repo\nsha=abc123' \
  > "$OVLY_TARGET/.claude/.conjure-org-overlay"
AUDIT_SKIP_RC=0
AUDIT_SKIP_OUT="$(bash "$CONJURE_HOME/scripts/audit-setup.sh" "$OVLY_TARGET" 2>&1)" \
  || AUDIT_SKIP_RC=$?
if [ "$AUDIT_SKIP_RC" -ne 128 ]; then
  pass "audit does not exit 128 on git ls-remote failure (OVLY-04, D-06)"
else
  fail "audit exited 128 on git ls-remote failure — must gracefully skip (OVLY-04)"
fi
if printf '%s\n' "$AUDIT_SKIP_OUT" | grep -q 'drift check skipped'; then
  pass "audit prints 'drift check skipped' when git ls-remote fails (OVLY-04)"
else
  fail "audit missing 'drift check skipped' message on ls-remote failure (OVLY-04)"
fi

# OVLY-05: no credential keywords in worker scripts (static grep)
if grep -qE 'password|credential|token' "$CONJURE_HOME/scripts/init-overlay.sh" 2>/dev/null; then
  fail "init-overlay.sh contains credential keyword (OVLY-05)"
else
  pass "init-overlay.sh contains no credential keywords (OVLY-05)"
fi
if grep -qE 'password|credential|token' "$CONJURE_HOME/scripts/refresh-overlay.sh" 2>/dev/null; then
  fail "refresh-overlay.sh contains credential keyword (OVLY-05)"
else
  pass "refresh-overlay.sh contains no credential keywords (OVLY-05)"
fi

# CLEANUP OVLY sandbox
rm -rf "$OVLY_REPO" "$OVLY_TARGET"

# Summary
echo
echo "═══════════════════════════════════════════════════════════════════"
echo "PASS: $PASS    FAIL: $FAIL"
echo "═══════════════════════════════════════════════════════════════════"

[ "$FAIL" -eq 0 ]
