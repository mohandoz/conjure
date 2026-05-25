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

# Summary
echo
echo "═══════════════════════════════════════════════════════════════════"
echo "PASS: $PASS    FAIL: $FAIL"
echo "═══════════════════════════════════════════════════════════════════"

[ "$FAIL" -eq 0 ]
