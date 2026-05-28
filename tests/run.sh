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

# mk_path_without_gh — echo a PATH value in which `gh` is unresolvable.
# Stripping just gh's first dir fails on usrmerged runners (/bin → /usr/bin), where
# gh is reachable as both /usr/bin/gh and /bin/gh, and when gh lives in several PATH
# dirs. So drop EVERY dir that holds an executable gh, mirroring each one's other
# entries (symlinks) into a single stub dir so tools like git/jq stay reachable.
# Echoes $PATH unchanged if gh is not found anywhere.
GH_HIDE_STUBS=""
mk_path_without_gh() {
  command -v gh >/dev/null 2>&1 || { printf '%s' "$PATH"; return 0; }
  local stub new_path dir f base
  stub="$(mktemp -d)"
  GH_HIDE_STUBS="${GH_HIDE_STUBS:+$GH_HIDE_STUBS }$stub"
  new_path=""
  local IFS=:
  for dir in $PATH; do
    [ -z "$dir" ] && continue
    if [ -x "$dir/gh" ]; then
      for f in "$dir"/*; do
        base="${f##*/}"
        [ "$base" = "gh" ] && continue
        [ -e "$stub/$base" ] && continue
        ln -s "$f" "$stub/$base" 2>/dev/null || true
      done
    else
      new_path="${new_path:+$new_path:}$dir"
    fi
  done
  printf '%s' "${stub}:${new_path}"
}

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

echo
echo "▸ mutate_rm unit tests (INFRA-01)"

# Sub-case 1: dry-run path — use a mktemp-style path but do NOT create the file.
# mutate_rm must print "[dry-run] would rm <path>", increment counter, and leave
# the path absent (it was absent before and must remain absent after).
MUTATE_RM_TMPPATH="/tmp/conjure-test-mutate-rm-$$-dry"
MUTATE_RM_OUT="$(
  DRY_RUN=1 bash -c '
    source '"'"'lib/mutate.sh'"'"'
    CONJURE_DRY_MUTATION_COUNT=0
    mutate_rm "'"$MUTATE_RM_TMPPATH"'"
    printf "%s\n" "[count=$CONJURE_DRY_MUTATION_COUNT]"
  '
)"
if printf '%s\n' "$MUTATE_RM_OUT" | grep -q "would rm"; then
  pass "mutate_rm dry-run: output contains 'would rm' (INFRA-01)"
else
  fail "mutate_rm dry-run: output missing 'would rm' (INFRA-01)"
fi
if printf '%s\n' "$MUTATE_RM_OUT" | grep -q "\[count=1\]"; then
  pass "mutate_rm dry-run: CONJURE_DRY_MUTATION_COUNT incremented to 1 (INFRA-01)"
else
  fail "mutate_rm dry-run: counter not incremented — got: $MUTATE_RM_OUT (INFRA-01)"
fi
if [ ! -f "$MUTATE_RM_TMPPATH" ]; then
  pass "mutate_rm dry-run: path absent after call (no filesystem mutation) (INFRA-01)"
else
  fail "mutate_rm dry-run: file was created — DRY_RUN not honored (INFRA-01)"
fi

# Sub-case 2: live path — create a real temp file, call mutate_rm, assert it is gone.
MUTATE_RM_LIVE="$(mktemp)"
# shellcheck disable=SC1090
source lib/mutate.sh
DRY_RUN=0 mutate_rm "$MUTATE_RM_LIVE"
if [ ! -f "$MUTATE_RM_LIVE" ]; then
  pass "mutate_rm live: file removed by rm -f (INFRA-01)"
else
  fail "mutate_rm live: file still present after mutate_rm (INFRA-01)"
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

# The telemetry hook runs under native node; on Git Bash a POSIX cwd (/tmp/...)
# is mis-resolved relative to the current drive, so the JSONL lands somewhere the
# POSIX-path file checks below can't see. cygpath -m yields a forward-slash Windows
# path (JSON-safe, resolves to the same physical dir). No-op off Windows (WR-01).
if command -v cygpath >/dev/null 2>&1; then
  TLMY_CWD="$(cygpath -m "$SANDBOX_DIR")"
else
  TLMY_CWD="$SANDBOX_DIR"
fi

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
SKILL_PAYLOAD='{"hook_event_name":"PreToolUse","tool_name":"Skill","tool_input":{"skill_name":"test-skill"},"session_id":"sess-001","cwd":"'"$TLMY_CWD"'"}'
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
UPE_PAYLOAD='{"hook_event_name":"UserPromptExpansion","command_name":"/test-skill","session_id":"sess-002","cwd":"'"$TLMY_CWD"'"}'
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
SKILL_OUT="$(DRY_RUN=1 skill_run test-skill myorg/myrepo 2>&1)"
if printf '%s\n' "$SKILL_OUT" | grep -q 'dry-run'; then
  pass "publish-skill --dry-run prints dry-run accounting (SKILL-01)"
else
  fail "publish-skill --dry-run did not print dry-run output (SKILL-01)"
fi

# SKILL-01: size cap — 201-line SKILL.md exits 1
python3 -c "print('---\nname: test-skill\ndescription: A test skill that demonstrates the publish-skill validation pipeline end-to-end.\n---'); [print('line') for _ in range(200)]" \
  > "$SKILL_DIR/.claude/skills/test-skill/SKILL.md"
SIZE_RC=0
skill_run test-skill myorg/myrepo >/dev/null 2>&1 || SIZE_RC=$?
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
skill_run test-skill myorg/myrepo >/dev/null 2>&1 || NONAME_RC=$?
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
skill_run test-skill myorg/myrepo >/dev/null 2>&1 || CURL_RC=$?
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
skill_run test-skill myorg/myrepo >/dev/null 2>&1 || SECRET_RC=$?
if [ "$SECRET_RC" -eq 1 ]; then
  pass "publish-skill exits 1 when body contains \$SECRET (SKILL-01)"
else
  fail "publish-skill did not exit 1 on \$SECRET egress — got rc=$SECRET_RC (SKILL-01)"
fi
git -C "$SKILL_DIR" checkout -- .claude/skills/test-skill/SKILL.md

# SKILL-01: clean skill passes all gates
CLEAN_RC=0
skill_run test-skill myorg/myrepo >/dev/null 2>&1 || CLEAN_RC=$?
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
GH_PRESENT_OUT="$(skill_run test-skill myorg/myrepo 2>&1)"
PATH="$SAVED_PATH"
rm -rf "$STUB_BIN"
if printf '%s\n' "$GH_PRESENT_OUT" | grep -q 'gh pr create'; then
  pass "publish-skill prints gh pr create when gh is present (SKILL-02)"
else
  fail "publish-skill did not print gh pr create with gh present (SKILL-02)"
fi

# SKILL-02: gh absent — printed output contains "manually" or github.com URL
FILTERED_PATH="$(mk_path_without_gh)"
NOGH_OUT="$(PATH="$FILTERED_PATH" skill_run test-skill myorg/myrepo 2>&1)"
if printf '%s\n' "$NOGH_OUT" | grep -qE 'manually|github\.com'; then
  pass "publish-skill prints manual URL when gh is absent (SKILL-02)"
else
  fail "publish-skill did not print manual URL with gh absent (SKILL-02)"
fi

# SKILL-03: dirty skill tree → exit 1
echo "dirty" >> "$SKILL_DIR/.claude/skills/test-skill/SKILL.md"
DIRTY_RC=0
skill_run test-skill myorg/myrepo >/dev/null 2>&1 || DIRTY_RC=$?
if [ "$DIRTY_RC" -eq 1 ]; then
  pass "publish-skill exits 1 on dirty skill tree (SKILL-03)"
else
  fail "publish-skill did not exit 1 on dirty skill tree — got rc=$DIRTY_RC (SKILL-03)"
fi
DIRTY_MSG="$(skill_run test-skill myorg/myrepo 2>&1 || true)"
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
( cd "$SKILL_DIR" && bash "$UNTAGGED_DIR/scripts/publish-skill.sh" test-skill myorg/myrepo >/dev/null 2>&1 ) || UNTAGGED_RC=$?
UNTAGGED_MSG="$( ( cd "$SKILL_DIR" && bash "$UNTAGGED_DIR/scripts/publish-skill.sh" test-skill myorg/myrepo ) 2>&1 || true )"
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

echo ""
echo "▸ SKILL-05: positional arg + deprecation (DEBT-02)"

# SKILL-05a: positional $2 sets target repo in PR instructions
P2_OUT="$(skill_run test-skill myorg/myrepo 2>&1)"
if printf '%s\n' "$P2_OUT" | grep -q 'myorg/myrepo'; then
  pass "positional \$2 sets target repo (SKILL-05a)"
else
  fail "positional \$2 did not appear in PR instructions (SKILL-05a)"
fi

# SKILL-05b: TARGET_REPO env emits deprecation WARN to stderr; command still exits 0
DEPR_ERR="$(TARGET_REPO=myorg/myrepo skill_run test-skill 2>&1 1>/dev/null)"
if printf '%s\n' "$DEPR_ERR" | grep -q 'WARN: TARGET_REPO'; then
  pass "TARGET_REPO env emits deprecation WARN (SKILL-05b)"
else
  fail "TARGET_REPO env did not emit deprecation WARN (SKILL-05b)"
fi
DEPR_RC=0
TARGET_REPO=myorg/myrepo skill_run test-skill >/dev/null 2>&1 || DEPR_RC=$?
if [ "$DEPR_RC" -eq 0 ]; then
  pass "TARGET_REPO env path still exits 0 (SKILL-05b)"
else
  fail "TARGET_REPO env path exited $DEPR_RC instead of 0 (SKILL-05b)"
fi

# SKILL-05c: missing $2 and no TARGET_REPO env → exit 2 with usage line
MISS_RC=0
skill_run test-skill >/dev/null 2>&1 || MISS_RC=$?
if [ "$MISS_RC" -eq 2 ]; then
  pass "missing \$2 and no TARGET_REPO env exits 2 (SKILL-05c)"
else
  fail "missing \$2 and no TARGET_REPO env exited $MISS_RC instead of 2 (SKILL-05c)"
fi
MISS_ERR="$(skill_run test-skill 2>&1 || true)"
if printf '%s\n' "$MISS_ERR" | grep -q 'conjure publish-skill'; then
  pass "missing repo shows usage line containing 'conjure publish-skill' (SKILL-05c)"
else
  fail "missing repo did not show expected usage line (SKILL-05c)"
fi

# SKILL-05d: positional $2 takes priority over TARGET_REPO env (no deprecation warning)
PRIO_OUT="$(TARGET_REPO=other/repo skill_run test-skill myorg/myrepo 2>&1)"
if printf '%s\n' "$PRIO_OUT" | grep -q 'myorg/myrepo'; then
  pass "positional \$2 takes priority over TARGET_REPO env (SKILL-05d)"
else
  fail "positional \$2 did not override TARGET_REPO env (SKILL-05d)"
fi
if ! printf '%s\n' "$PRIO_OUT" | grep -q 'WARN:'; then
  pass "no deprecation WARN when positional \$2 is present (SKILL-05d)"
else
  fail "unexpected WARN emitted when positional \$2 is present (SKILL-05d)"
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

# ──────────────────────────────────────────────────────────────────────────────
# BREW homebrew tests (BREW-01 through BREW-04)
# ──────────────────────────────────────────────────────────────────────────────
echo
echo "▸ BREW homebrew tests (BREW-01 through BREW-04)"

if ! command -v ruby >/dev/null 2>&1; then
  pass "Formula/conjure.rb: ruby not installed — syntax check skipped (BREW-01)"
elif ruby -c "$CONJURE_HOME/Formula/conjure.rb" >/dev/null 2>&1; then
  pass "Formula/conjure.rb: valid Ruby syntax (BREW-01)"
else
  fail "Formula/conjure.rb: Ruby syntax error — run: ruby -c Formula/conjure.rb (BREW-01)"
fi

BREW_FAKE="$(mktemp -d)"
trap 'rm -rf "$BREW_FAKE"' EXIT
printf '9.8.7\n' > "$BREW_FAKE/VERSION"
BREW_VER_OUT="$(CONJURE_HOME="$BREW_FAKE" "$CONJURE_HOME/cli/conjure" version 2>&1)"
if printf '%s\n' "$BREW_VER_OUT" | grep -q '9.8.7'; then
  pass "CONJURE_HOME env var overrides default resolution (BREW-02)"
else
  fail "CONJURE_HOME env var did NOT override — got: $BREW_VER_OUT (BREW-02)"
fi
rm -rf "$BREW_FAKE"
trap - EXIT

if grep -qE '\bHEAD\b|\bbranch\b' "$CONJURE_HOME/Formula/conjure.rb" 2>/dev/null; then
  fail "Formula/conjure.rb contains HEAD or branch reference — must use tagged tarball URL (BREW-03)"
else
  pass "Formula/conjure.rb: no HEAD or branch reference (BREW-03)"
fi

if grep -q 'bump-homebrew-formula-action' "$CONJURE_HOME/.github/workflows/release.yml" 2>/dev/null; then
  pass "release.yml references bump-homebrew-formula-action (BREW-04)"
else
  fail "release.yml missing bump-homebrew-formula-action reference (BREW-04)"
fi

# ──────────────────────────────────────────────────────────────────────────────
# DRIFT detection tests (DRIFT-01, DRIFT-02)
# ──────────────────────────────────────────────────────────────────────────────
echo
echo "▸ Drift detection tests (DRIFT-01, DRIFT-02)"

# DRIFT-01a — fresh init → no drift, exit 0
DRIFT_DIR="$(mktemp -d)"
trap 'rm -rf "$DRIFT_DIR"' EXIT
printf '# Test project\n' > "$DRIFT_DIR/CLAUDE.md"
CONJURE_HOME="$CONJURE_HOME" cli/conjure init "$DRIFT_DIR" >/dev/null 2>&1
DRIFT_RC=0
CONJURE_HOME="$CONJURE_HOME" cli/conjure check "$DRIFT_DIR" >/dev/null 2>&1 || DRIFT_RC=$?
if [ "$DRIFT_RC" -eq 0 ]; then
  pass "check exits 0 on fully-current harness (DRIFT-01)"
else
  fail "check exited $DRIFT_RC on fully-current harness — expected 0 (DRIFT-01)"
fi
rm -rf "$DRIFT_DIR"
trap - EXIT

# DRIFT-01b — modified file (settings.json) → exit 1 + porcelain M line
DRIFT_DIR="$(mktemp -d)"
trap 'rm -rf "$DRIFT_DIR"' EXIT
printf '# Test project\n' > "$DRIFT_DIR/CLAUDE.md"
CONJURE_HOME="$CONJURE_HOME" cli/conjure init "$DRIFT_DIR" >/dev/null 2>&1
printf 'user-edit\n' >> "$DRIFT_DIR/.claude/settings.json"
DRIFT_OUT="$(CONJURE_HOME="$CONJURE_HOME" cli/conjure check --porcelain "$DRIFT_DIR" 2>&1 || true)"
DRIFT_RC=0
CONJURE_HOME="$CONJURE_HOME" cli/conjure check "$DRIFT_DIR" >/dev/null 2>&1 || DRIFT_RC=$?
if [ "$DRIFT_RC" -eq 1 ]; then
  pass "check exits 1 when file is modified (DRIFT-01)"
else
  fail "check exited $DRIFT_RC on modified file — expected 1 (DRIFT-01)"
fi
if printf '%s\n' "$DRIFT_OUT" | grep -q '^M .claude/settings.json'; then
  pass "--porcelain emits 'M .claude/settings.json' (DRIFT-02)"
else
  fail "--porcelain did not emit 'M .claude/settings.json' — got: $DRIFT_OUT (DRIFT-02)"
fi
rm -rf "$DRIFT_DIR"
trap - EXIT

# DRIFT-01c — removed file (post-edit-format.mjs) → exit 1 + porcelain R line
DRIFT_DIR="$(mktemp -d)"
trap 'rm -rf "$DRIFT_DIR"' EXIT
printf '# Test project\n' > "$DRIFT_DIR/CLAUDE.md"
CONJURE_HOME="$CONJURE_HOME" cli/conjure init "$DRIFT_DIR" >/dev/null 2>&1
rm -f "$DRIFT_DIR/.claude/hooks/post-edit-format.mjs"
DRIFT_OUT="$(CONJURE_HOME="$CONJURE_HOME" cli/conjure check --porcelain "$DRIFT_DIR" 2>&1 || true)"
DRIFT_RC=0
CONJURE_HOME="$CONJURE_HOME" cli/conjure check "$DRIFT_DIR" >/dev/null 2>&1 || DRIFT_RC=$?
if [ "$DRIFT_RC" -eq 1 ]; then
  pass "check exits 1 when kit file is removed from harness (DRIFT-01)"
else
  fail "check exited $DRIFT_RC on removed file — expected 1 (DRIFT-01)"
fi
if printf '%s\n' "$DRIFT_OUT" | grep -q '^R .claude/hooks/post-edit-format.mjs'; then
  pass "--porcelain emits 'R' for removed hook (DRIFT-02)"
else
  fail "--porcelain did not emit 'R .claude/hooks/post-edit-format.mjs' — got: $DRIFT_OUT (DRIFT-02)"
fi
rm -rf "$DRIFT_DIR"
trap - EXIT

# DRIFT-02 — porcelain exit 0 on current harness
DRIFT_DIR="$(mktemp -d)"
trap 'rm -rf "$DRIFT_DIR"' EXIT
printf '# Test project\n' > "$DRIFT_DIR/CLAUDE.md"
CONJURE_HOME="$CONJURE_HOME" cli/conjure init "$DRIFT_DIR" >/dev/null 2>&1
PORE_RC=0
CONJURE_HOME="$CONJURE_HOME" cli/conjure check --porcelain "$DRIFT_DIR" >/dev/null 2>&1 || PORE_RC=$?
if [ "$PORE_RC" -eq 0 ]; then
  pass "--porcelain exits 0 when harness is current (DRIFT-02)"
else
  fail "--porcelain exited $PORE_RC on current harness — expected 0 (DRIFT-02)"
fi
rm -rf "$DRIFT_DIR"
trap - EXIT

# ──────────────────────────────────────────────────────────────────────────────
# RESOLVE conflict resolution tests (RESOLVE-01, RESOLVE-02)
# ──────────────────────────────────────────────────────────────────────────────
echo
echo "▸ Conflict resolution tests (RESOLVE-01, RESOLVE-02)"

# RESOLVE-01a — non-interactive guard: piped stdin + sidecars present → exit 2
RESOLVE_DIR="$(mktemp -d)"
trap 'rm -rf "$RESOLVE_DIR"' EXIT
printf 'upstream content\n' > "$RESOLVE_DIR/.conjure-conflict-foo.txt"
printf 'my content\n' > "$RESOLVE_DIR/foo.txt"
RESOLVE_RC=0
CONJURE_HOME="$CONJURE_HOME" cli/conjure resolve "$RESOLVE_DIR" </dev/null >/dev/null 2>&1 || RESOLVE_RC=$?
if [ "$RESOLVE_RC" -eq 2 ]; then
  pass "resolve exits 2 when stdin is not a TTY (RESOLVE-01)"
else
  fail "resolve exited $RESOLVE_RC with piped stdin — expected 2 (RESOLVE-01)"
fi
rm -rf "$RESOLVE_DIR"
trap - EXIT

# RESOLVE-02a — all-clear on empty dir: no sidecars → exit 0 + "No conflicts remain"
RESOLVE_DIR="$(mktemp -d)"
trap 'rm -rf "$RESOLVE_DIR"' EXIT
ALLCLEAR_RC=0
ALLCLEAR_OUT="$(CONJURE_HOME="$CONJURE_HOME" cli/conjure resolve "$RESOLVE_DIR" </dev/null 2>&1)" || ALLCLEAR_RC=$?
if [ "$ALLCLEAR_RC" -eq 0 ]; then
  pass "resolve exits 0 on empty dir (RESOLVE-02)"
else
  fail "resolve exited $ALLCLEAR_RC on empty dir — expected 0 (RESOLVE-02)"
fi
if printf '%s\n' "$ALLCLEAR_OUT" | grep -q "No conflicts remain"; then
  pass "resolve prints 'No conflicts remain' on empty dir (RESOLVE-02)"
else
  fail "resolve did not print 'No conflicts remain' — got: $ALLCLEAR_OUT (RESOLVE-02)"
fi
rm -rf "$RESOLVE_DIR"
trap - EXIT

# RESOLVE-02b — keep action: sidecar removed, current file unchanged
RESOLVE_DIR="$(mktemp -d)"
trap 'rm -rf "$RESOLVE_DIR"' EXIT
printf 'upstream content\n' > "$RESOLVE_DIR/.conjure-conflict-foo.txt"
printf 'my content\n' > "$RESOLVE_DIR/foo.txt"
printf 'k\n' | CONJURE_HOME="$CONJURE_HOME" DRY_RUN=0 CONJURE_FORCE_INTERACTIVE=1 bash "$CONJURE_HOME/scripts/resolve.sh" "$RESOLVE_DIR" >/dev/null 2>&1 || true
if [ ! -f "$RESOLVE_DIR/.conjure-conflict-foo.txt" ]; then
  pass "keep removes sidecar (RESOLVE-02)"
else
  fail "keep did not remove sidecar (RESOLVE-02)"
fi
if grep -q 'my content' "$RESOLVE_DIR/foo.txt"; then
  pass "keep leaves current file unchanged (RESOLVE-02)"
else
  fail "keep modified current file — expected 'my content' unchanged (RESOLVE-02)"
fi
rm -rf "$RESOLVE_DIR"
trap - EXIT

# RESOLVE-02c — apply action: current file updated with sidecar content, sidecar removed
RESOLVE_DIR="$(mktemp -d)"
trap 'rm -rf "$RESOLVE_DIR"' EXIT
printf 'upstream content\n' > "$RESOLVE_DIR/.conjure-conflict-foo.txt"
printf 'my content\n' > "$RESOLVE_DIR/foo.txt"
printf 'a\n' | CONJURE_HOME="$CONJURE_HOME" DRY_RUN=0 CONJURE_FORCE_INTERACTIVE=1 bash "$CONJURE_HOME/scripts/resolve.sh" "$RESOLVE_DIR" >/dev/null 2>&1 || true
if [ ! -f "$RESOLVE_DIR/.conjure-conflict-foo.txt" ]; then
  pass "apply removes sidecar (RESOLVE-02)"
else
  fail "apply did not remove sidecar (RESOLVE-02)"
fi
if grep -q 'upstream content' "$RESOLVE_DIR/foo.txt"; then
  pass "apply updates current file (RESOLVE-02)"
else
  fail "apply did not update current file — expected 'upstream content' (RESOLVE-02)"
fi
rm -rf "$RESOLVE_DIR"
trap - EXIT

# ──────────────────────────────────────────────────────────────────────────────
# Auto-PR tests (AUTPR-01, AUTPR-02)
# ──────────────────────────────────────────────────────────────────────────────
echo
echo "▸ Auto-PR tests (AUTPR-01, AUTPR-02)"

# Build a PATH in which gh is unresolvable (mirror-stub; handles gh/git colocation)
AUTPR_FILTERED_PATH="$(mk_path_without_gh)"

# AUTPR-01a — zero-drift guard: fully-current harness → "Harness is current" + exit 0
# Note: --pr checks for gh before the zero-drift guard, so we stub gh to a no-op binary.
AUTPR_STUB_A="$(mktemp -d)"
printf '#!/bin/sh\nexit 0\n' > "$AUTPR_STUB_A/gh"
chmod +x "$AUTPR_STUB_A/gh"
AUTPR_DIR="$(mktemp -d)"
trap 'rm -rf "$AUTPR_DIR" "$AUTPR_STUB_A"' EXIT
printf '# Test project\n' > "$AUTPR_DIR/CLAUDE.md"
CONJURE_HOME="$CONJURE_HOME" cli/conjure init "$AUTPR_DIR" >/dev/null 2>&1
AUTPR_RC=0
AUTPR_OUT="$(PATH="$AUTPR_STUB_A:$PATH" CONJURE_HOME="$CONJURE_HOME" cli/conjure update --pr "$AUTPR_DIR" 2>&1)" || AUTPR_RC=$?
if [ "$AUTPR_RC" -eq 0 ]; then
  pass "update --pr exit code 0 on zero-drift (AUTPR-01)"
else
  fail "update --pr exited $AUTPR_RC on zero-drift — expected 0 (AUTPR-01)"
fi
if printf '%s\n' "$AUTPR_OUT" | grep -q "Harness is current"; then
  pass "update --pr prints 'Harness is current' on zero-drift (AUTPR-01)"
else
  fail "update --pr did not print 'Harness is current' on zero-drift — got: $AUTPR_OUT (AUTPR-01)"
fi
rm -rf "$AUTPR_DIR" "$AUTPR_STUB_A"
trap - EXIT

# AUTPR-01b — missing-gh guard: no gh on PATH → exit 2 + "gh CLI required"
AUTPR_DIR="$(mktemp -d)"
trap 'rm -rf "$AUTPR_DIR"' EXIT
printf '# Test project\n' > "$AUTPR_DIR/CLAUDE.md"
CONJURE_HOME="$CONJURE_HOME" cli/conjure init "$AUTPR_DIR" >/dev/null 2>&1
printf 'drift\n' >> "$AUTPR_DIR/.claude/settings.json"
NOGH_RC=0
NOGH_OUT="$(PATH="$AUTPR_FILTERED_PATH" CONJURE_HOME="$CONJURE_HOME" cli/conjure update --pr "$AUTPR_DIR" 2>&1)" || NOGH_RC=$?
if [ "$NOGH_RC" -eq 2 ]; then
  pass "update --pr exits 2 when gh is absent (AUTPR-01)"
else
  fail "update --pr exited $NOGH_RC with gh absent — expected 2 (AUTPR-01)"
fi
if printf '%s\n' "$NOGH_OUT" | grep -q "gh CLI required"; then
  pass "update --pr prints 'gh CLI required' when gh is absent (AUTPR-01)"
else
  fail "update --pr did not print 'gh CLI required' — got: $NOGH_OUT (AUTPR-01)"
fi
rm -rf "$AUTPR_DIR"
trap - EXIT

# AUTPR-01c — idempotency: stub gh pr list returns URL → print URL + exit 0
AUTPR_STUB_BIN="$(mktemp -d)"
printf '#!/bin/sh\nif [ "$1" = "pr" ] && [ "$2" = "list" ]; then printf "https://github.com/owner/repo/pull/42\\n"; fi\nexit 0\n' > "$AUTPR_STUB_BIN/gh"
chmod +x "$AUTPR_STUB_BIN/gh"
AUTPR_DIR="$(mktemp -d)"
trap 'rm -rf "$AUTPR_DIR" "$AUTPR_STUB_BIN"' EXIT
printf '# Test project\n' > "$AUTPR_DIR/CLAUDE.md"
CONJURE_HOME="$CONJURE_HOME" cli/conjure init "$AUTPR_DIR" >/dev/null 2>&1
printf 'drift\n' >> "$AUTPR_DIR/.claude/settings.json"
IDEM_RC=0
IDEM_OUT="$(PATH="$AUTPR_STUB_BIN:$PATH" CONJURE_HOME="$CONJURE_HOME" cli/conjure update --pr "$AUTPR_DIR" 2>&1)" || IDEM_RC=$?
if [ "$IDEM_RC" -eq 0 ]; then
  pass "update --pr exits 0 when PR already exists (AUTPR-01)"
else
  fail "update --pr exited $IDEM_RC when PR already exists — expected 0 (AUTPR-01)"
fi
if printf '%s\n' "$IDEM_OUT" | grep -q "https://github.com"; then
  pass "update --pr prints existing PR URL (AUTPR-01)"
else
  fail "update --pr did not print existing PR URL — got: $IDEM_OUT (AUTPR-01)"
fi
rm -rf "$AUTPR_DIR" "$AUTPR_STUB_BIN"
trap - EXIT

# AUTPR-02a — cron template write: conjure update --cron creates workflow file
AUTPR_DIR="$(mktemp -d)"
trap 'rm -rf "$AUTPR_DIR"' EXIT
CRON_RC=0
CONJURE_HOME="$CONJURE_HOME" cli/conjure update --cron "$AUTPR_DIR" >/dev/null 2>&1 || CRON_RC=$?
if [ "$CRON_RC" -eq 0 ]; then
  pass "update --cron exits 0 (AUTPR-02)"
else
  fail "update --cron exited $CRON_RC — expected 0 (AUTPR-02)"
fi
if [ -f "$AUTPR_DIR/.github/workflows/conjure-update.yml" ]; then
  pass "conjure-update.yml written (AUTPR-02)"
else
  fail "conjure-update.yml not found at expected path (AUTPR-02)"
fi
if grep -q "0 9 \* \* 1" "$AUTPR_DIR/.github/workflows/conjure-update.yml" 2>/dev/null; then
  pass "cron schedule is Monday 09:00 UTC (AUTPR-02)"
else
  fail "cron schedule '0 9 * * 1' not found in conjure-update.yml (AUTPR-02)"
fi
if grep -q "conjure update --pr" "$AUTPR_DIR/.github/workflows/conjure-update.yml" 2>/dev/null; then
  pass "cron template invokes conjure update --pr (AUTPR-02)"
else
  fail "cron template does not invoke conjure update --pr (AUTPR-02)"
fi
rm -rf "$AUTPR_DIR"
trap - EXIT

# AUTPR-02b — cron template idempotency: running --cron twice both exit 0
AUTPR_DIR="$(mktemp -d)"
trap 'rm -rf "$AUTPR_DIR"' EXIT
CONJURE_HOME="$CONJURE_HOME" cli/conjure update --cron "$AUTPR_DIR" >/dev/null 2>&1
CRON2_RC=0
CONJURE_HOME="$CONJURE_HOME" cli/conjure update --cron "$AUTPR_DIR" >/dev/null 2>&1 || CRON2_RC=$?
if [ "$CRON2_RC" -eq 0 ]; then
  pass "update --cron is idempotent (second run exits 0) (AUTPR-02)"
else
  fail "update --cron second run exited $CRON2_RC — expected 0 (AUTPR-02)"
fi
rm -rf "$AUTPR_DIR"
trap - EXIT

# Clean up any gh-hiding stub dirs created by mk_path_without_gh
for _s in $GH_HIDE_STUBS; do rm -rf "$_s"; done

# ──────────────────────────────────────────────────────────────────────────────
# Phase 21 — Foundation Libs + Inventory (Wave 0 test stubs)
# These stubs fail gracefully when lib files are absent (Plans 02-04 create them).
# All sections use the same pass/fail helpers defined at the top of run.sh.
# ──────────────────────────────────────────────────────────────────────────────

echo
echo "▸ Phase 21 — lib/caps.sh (SC-5)"

P21_CAPS_OK=0
if ! source "$CONJURE_HOME/lib/caps.sh" 2>/dev/null; then
  fail "lib/caps.sh not found — Wave 1 must create it first (SC-5)"
else
  P21_CAPS_OK=1
  if [ "${CLAUDE_MD_CAP:-}" = "100" ]; then
    pass "caps.sh: CLAUDE_MD_CAP=100 (SC-5)"
  else
    fail "caps.sh: CLAUDE_MD_CAP expected 100, got '${CLAUDE_MD_CAP:-unset}' (SC-5)"
  fi
  if [ "${SKILL_MD_CAP:-}" = "200" ]; then
    pass "caps.sh: SKILL_MD_CAP=200 (SC-5)"
  else
    fail "caps.sh: SKILL_MD_CAP expected 200, got '${SKILL_MD_CAP:-unset}' (SC-5)"
  fi
  if [ "${AGENT_MD_CAP:-}" = "80" ]; then
    pass "caps.sh: AGENT_MD_CAP=80 (SC-5)"
  else
    fail "caps.sh: AGENT_MD_CAP expected 80, got '${AGENT_MD_CAP:-unset}' (SC-5)"
  fi
fi

echo
echo "▸ Phase 21 — lib/log.sh (ADOPT-03/SC-1)"

P21_LOG_OK=0
if [ ! -f "$CONJURE_HOME/lib/log.sh" ]; then
  fail "lib/log.sh not found — Wave 1 must create it first (ADOPT-03/SC-1)"
else
  P21_LOG_OK=1
  # DRY_RUN=1 test: output must contain "[dry-run] would write"
  P21_LOG_DRY_OUT="$(
    DRY_RUN=1 RESTRUCTURE_LOG_PATH="/tmp/conjure-p21-log-dryrun-$$" \
    CONJURE_HOME="$CONJURE_HOME" \
    bash -c '
      source "$CONJURE_HOME/lib/mutate.sh"
      source "$CONJURE_HOME/lib/log.sh"
      CONJURE_DRY_MUTATION_COUNT=0
      log_step TEST "hello dry-run"
      printf "%s\n" "[count=$CONJURE_DRY_MUTATION_COUNT]"
    ' 2>&1
  )"
  if printf '%s\n' "$P21_LOG_DRY_OUT" | grep -q "dry-run"; then
    pass "log.sh DRY_RUN=1: output contains dry-run indicator (ADOPT-03/SC-1)"
  else
    fail "log.sh DRY_RUN=1: missing dry-run indicator — got: $P21_LOG_DRY_OUT (ADOPT-03/SC-1)"
  fi
  if ! printf '%s\n' "$P21_LOG_DRY_OUT" | grep -q "RESTRUCTURE-LOG"; then
    pass "log.sh DRY_RUN=1: no actual file written (ADOPT-03/SC-1)"
  else
    fail "log.sh DRY_RUN=1: log file was written (ADOPT-03/SC-1)"
  fi

  # Live mode test: log_init + log_step must write file with entries
  P21_LOG_DIR="$(mktemp -d)"
  trap 'rm -rf "$P21_LOG_DIR"' EXIT
  (
    source "$CONJURE_HOME/lib/mutate.sh"
    source "$CONJURE_HOME/lib/log.sh"
    DRY_RUN=0
    RESTRUCTURE_LOG_PATH="$P21_LOG_DIR/RESTRUCTURE-LOG.md"
    CONJURE_DRY_MUTATION_COUNT=0
    log_init "$P21_LOG_DIR"
    log_step INVENTORY "test message alpha"
    log_step SNAPSHOT "test message beta"
  )
  if [ -f "$P21_LOG_DIR/RESTRUCTURE-LOG.md" ]; then
    pass "log.sh live: RESTRUCTURE-LOG.md created (ADOPT-03/SC-1)"
  else
    fail "log.sh live: RESTRUCTURE-LOG.md not created (ADOPT-03/SC-1)"
  fi
  P21_LOG_ENTRY_COUNT=$(grep -c "^\[" "$P21_LOG_DIR/RESTRUCTURE-LOG.md" 2>/dev/null || echo "0")
  if [ "${P21_LOG_ENTRY_COUNT:-0}" -ge 2 ]; then
    pass "log.sh live: at least 2 bracketed entries found (newline check) (ADOPT-03/SC-1)"
  else
    fail "log.sh live: expected >=2 entries, got $P21_LOG_ENTRY_COUNT — possible newline join bug (ADOPT-03/SC-1)"
  fi
  rm -rf "$P21_LOG_DIR"
  trap - EXIT
fi

echo
echo "▸ Phase 21 — lib/snapshot.sh (SC-2)"

P21_SNAP_OK=0
if [ ! -f "$CONJURE_HOME/lib/snapshot.sh" ]; then
  fail "lib/snapshot.sh not found — Wave 1 must create it first (SC-2)"
else
  P21_SNAP_OK=1
  BF_FIXTURE="$CONJURE_HOME/tests/fixtures/brownfield-simple"

  # DRY_RUN=1: should print dry-run message, no dir created
  P21_SNAP_DRY_BACKUP="$(mktemp -d)"
  trap 'rm -rf "$P21_SNAP_DRY_BACKUP"' EXIT
  P21_SNAP_DRY_OUT="$(
    DRY_RUN=1 _P21_SNAP_TARGET="$BF_FIXTURE" _P21_SNAP_BACKUP="$P21_SNAP_DRY_BACKUP" \
    CONJURE_HOME="$CONJURE_HOME" \
    bash -c '
      source "$CONJURE_HOME/lib/mutate.sh"
      source "$CONJURE_HOME/lib/log.sh"
      source "$CONJURE_HOME/lib/snapshot.sh"
      RESTRUCTURE_LOG_PATH="/tmp/conjure-p21-snap-drylog-$$"
      CONJURE_DRY_MUTATION_COUNT=0
      snapshot_create "$_P21_SNAP_TARGET" "$_P21_SNAP_BACKUP"
    ' 2>&1
  )"
  if printf '%s\n' "$P21_SNAP_DRY_OUT" | grep -q "dry-run"; then
    pass "snapshot.sh DRY_RUN=1: output contains dry-run indicator (SC-2)"
  else
    fail "snapshot.sh DRY_RUN=1: missing dry-run indicator — got: $P21_SNAP_DRY_OUT (SC-2)"
  fi
  P21_SNAP_DRY_COUNT="$(find "$P21_SNAP_DRY_BACKUP" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')"
  if [ "${P21_SNAP_DRY_COUNT:-0}" -eq 0 ]; then
    pass "snapshot.sh DRY_RUN=1: no directory created (SC-2)"
  else
    fail "snapshot.sh DRY_RUN=1: snapshot directory was created — DRY_RUN not honored (SC-2)"
  fi
  rm -rf "$P21_SNAP_DRY_BACKUP"
  trap - EXIT

  # Live mode: snapshot_create must copy the fixture
  P21_SNAP_TARGET="$(mktemp -d)"
  P21_SNAP_BACKUP="$(mktemp -d)"
  trap 'rm -rf "$P21_SNAP_TARGET" "$P21_SNAP_BACKUP"' EXIT
  cp -r "$BF_FIXTURE/." "$P21_SNAP_TARGET/"
  (
    source "$CONJURE_HOME/lib/mutate.sh"
    source "$CONJURE_HOME/lib/log.sh"
    source "$CONJURE_HOME/lib/snapshot.sh"
    DRY_RUN=0
    RESTRUCTURE_LOG_PATH="$P21_SNAP_BACKUP/RESTRUCTURE-LOG.md"
    CONJURE_DRY_MUTATION_COUNT=0
    snapshot_create "$P21_SNAP_TARGET" "$P21_SNAP_BACKUP"
    printf '%s\n' "$CONJURE_SNAPSHOT_PATH" > "$P21_SNAP_BACKUP/.snap-path"
  )
  P21_SNAP_PATH="$(cat "$P21_SNAP_BACKUP/.snap-path" 2>/dev/null || true)"
  if [ -n "$P21_SNAP_PATH" ] && [ -d "$P21_SNAP_PATH" ]; then
    pass "snapshot.sh live: CONJURE_SNAPSHOT_PATH is non-empty and dir exists (SC-2)"
  else
    fail "snapshot.sh live: CONJURE_SNAPSHOT_PATH missing or dir not found (SC-2)"
  fi
  if [ -n "$P21_SNAP_PATH" ] && [ -f "$P21_SNAP_PATH/CLAUDE.md" ]; then
    pass "snapshot.sh live: snapshot contains CLAUDE.md (SC-2)"
  else
    fail "snapshot.sh live: snapshot missing CLAUDE.md (SC-2)"
  fi
  rm -rf "$P21_SNAP_TARGET" "$P21_SNAP_BACKUP"
  trap - EXIT
fi

echo
echo "▸ Phase 21 — lib/inventory.sh (INV-01..INV-04)"

P21_INV_OK=0
if [ ! -f "$CONJURE_HOME/lib/inventory.sh" ]; then
  fail "lib/inventory.sh not found — Wave 1 must create it first (INV-01..INV-04)"
else
  P21_INV_OK=1
  BF_FIXTURE="$CONJURE_HOME/tests/fixtures/brownfield-simple"

  # Source all required libs
  source "$CONJURE_HOME/lib/mutate.sh"
  [ -f "$CONJURE_HOME/lib/caps.sh" ]     && source "$CONJURE_HOME/lib/caps.sh"
  [ -f "$CONJURE_HOME/lib/log.sh" ]      && source "$CONJURE_HOME/lib/log.sh"
  [ -f "$CONJURE_HOME/lib/inventory.sh" ] && source "$CONJURE_HOME/lib/inventory.sh"

  # INV-01: classify — core bucket
  P21_CLS=$(inventory_classify "$BF_FIXTURE/CLAUDE.md" "$BF_FIXTURE" /dev/null 2>/dev/null || true)
  if [ "$P21_CLS" = "core" ]; then
    pass "inventory_classify: CLAUDE.md → core (INV-01)"
  else
    fail "inventory_classify: CLAUDE.md expected 'core', got '$P21_CLS' (INV-01)"
  fi

  # INV-01: skill bucket
  P21_CLS=$(inventory_classify "$BF_FIXTURE/.claude/skills/git/SKILL.md" "$BF_FIXTURE" /dev/null 2>/dev/null || true)
  if [ "$P21_CLS" = "skill" ]; then
    pass "inventory_classify: SKILL.md → skill (INV-01)"
  else
    fail "inventory_classify: SKILL.md expected 'skill', got '$P21_CLS' (INV-01)"
  fi

  # INV-01: agent bucket
  P21_CLS=$(inventory_classify "$BF_FIXTURE/.claude/agents/deploy.md" "$BF_FIXTURE" /dev/null 2>/dev/null || true)
  if [ "$P21_CLS" = "agent" ]; then
    pass "inventory_classify: deploy.md → agent (INV-01)"
  else
    fail "inventory_classify: deploy.md expected 'agent', got '$P21_CLS' (INV-01)"
  fi

  # INV-01: planning-doc bucket
  P21_CLS=$(inventory_classify "$BF_FIXTURE/.planning/21-PLAN.md" "$BF_FIXTURE" /dev/null 2>/dev/null || true)
  if [ "$P21_CLS" = "planning-doc" ]; then
    pass "inventory_classify: 21-PLAN.md → planning-doc (INV-01)"
  else
    fail "inventory_classify: 21-PLAN.md expected 'planning-doc', got '$P21_CLS' (INV-01)"
  fi

  # INV-01: reference-doc bucket
  P21_CLS=$(inventory_classify "$BF_FIXTURE/docs/README.md" "$BF_FIXTURE" /dev/null 2>/dev/null || true)
  if [ "$P21_CLS" = "reference-doc" ]; then
    pass "inventory_classify: docs/README.md → reference-doc (INV-01)"
  else
    fail "inventory_classify: docs/README.md expected 'reference-doc', got '$P21_CLS' (INV-01)"
  fi

  # INV-01: unknown bucket — file outside harness dirs
  P21_UNKNOWN_TMP="$(mktemp --suffix=.md 2>/dev/null || mktemp -t tmp.XXXXXX.md)"
  P21_CLS=$(inventory_classify "$P21_UNKNOWN_TMP" "$BF_FIXTURE" /dev/null 2>/dev/null || true)
  rm -f "$P21_UNKNOWN_TMP"
  if [ "$P21_CLS" = "unknown" ]; then
    pass "inventory_classify: external file → unknown (INV-01)"
  else
    fail "inventory_classify: external file expected 'unknown', got '$P21_CLS' (INV-01)"
  fi

  # INV-02: emit manifest and check required keys
  P21_INV_WORK="$(mktemp -d)"
  trap 'rm -rf "$P21_INV_WORK"' EXIT
  cp -r "$BF_FIXTURE/." "$P21_INV_WORK/target/"
  P21_MANIFEST="$P21_INV_WORK/adopt-manifest.json"
  (
    source "$CONJURE_HOME/lib/mutate.sh"
    [ -f "$CONJURE_HOME/lib/caps.sh" ]     && source "$CONJURE_HOME/lib/caps.sh"
    [ -f "$CONJURE_HOME/lib/log.sh" ]      && source "$CONJURE_HOME/lib/log.sh"
    [ -f "$CONJURE_HOME/lib/inventory.sh" ] && source "$CONJURE_HOME/lib/inventory.sh"
    DRY_RUN=0
    RESTRUCTURE_LOG_PATH="$P21_INV_WORK/RESTRUCTURE-LOG.md"
    CONJURE_DRY_MUTATION_COUNT=0
    inventory_scan "$P21_INV_WORK/target" 2>/dev/null || true
    inventory_emit_manifest "$P21_INV_WORK/target" "$P21_MANIFEST" 2>/dev/null || true
  )
  if [ -f "$P21_MANIFEST" ]; then
    pass "inventory_emit_manifest: adopt-manifest.json created (INV-02)"
  else
    fail "inventory_emit_manifest: adopt-manifest.json not created (INV-02)"
  fi
  if [ -f "$P21_MANIFEST" ] && command -v jq >/dev/null 2>&1; then
    if jq -e '.schema_version' "$P21_MANIFEST" >/dev/null 2>&1; then
      pass "adopt-manifest.json: schema_version field present (INV-02)"
    else
      fail "adopt-manifest.json: schema_version field missing (INV-02)"
    fi
    if jq -e '.summary.scan_capped == false' "$P21_MANIFEST" >/dev/null 2>&1; then
      pass "adopt-manifest.json: summary.scan_capped=false for small fixture (INV-02)"
    else
      fail "adopt-manifest.json: summary.scan_capped unexpected value (INV-02)"
    fi
    if jq -e '.files | length > 0' "$P21_MANIFEST" >/dev/null 2>&1; then
      pass "adopt-manifest.json: files[] is non-empty (INV-02)"
    else
      fail "adopt-manifest.json: files[] is empty (INV-02)"
    fi
    if jq -e '.summary.core == 1' "$P21_MANIFEST" >/dev/null 2>&1; then
      pass "adopt-manifest.json: summary.core == 1 (one CLAUDE.md) (INV-02)"
    else
      P21_CORE_COUNT="$(jq '.summary.core // "N/A"' "$P21_MANIFEST" 2>/dev/null || echo "N/A")"
      fail "adopt-manifest.json: summary.core expected 1, got $P21_CORE_COUNT (INV-02)"
    fi
  fi
  rm -rf "$P21_INV_WORK"
  trap - EXIT

  # INV-03: symlink skip — symlink-target.md must NOT appear in files[]
  # cp -a preserves symlinks (cp -r dereferences them, losing the test invariant)
  P21_INV_WORK="$(mktemp -d)"
  trap 'rm -rf "$P21_INV_WORK"' EXIT
  cp -a "$BF_FIXTURE/." "$P21_INV_WORK/target/" 2>/dev/null || cp -r "$BF_FIXTURE/." "$P21_INV_WORK/target/" 2>/dev/null || true
  P21_MANIFEST="$P21_INV_WORK/adopt-manifest.json"
  (
    source "$CONJURE_HOME/lib/mutate.sh"
    [ -f "$CONJURE_HOME/lib/caps.sh" ]     && source "$CONJURE_HOME/lib/caps.sh"
    [ -f "$CONJURE_HOME/lib/log.sh" ]      && source "$CONJURE_HOME/lib/log.sh"
    [ -f "$CONJURE_HOME/lib/inventory.sh" ] && source "$CONJURE_HOME/lib/inventory.sh"
    DRY_RUN=0
    RESTRUCTURE_LOG_PATH="$P21_INV_WORK/RESTRUCTURE-LOG.md"
    CONJURE_DRY_MUTATION_COUNT=0
    inventory_scan "$P21_INV_WORK/target" 2>/dev/null || true
    inventory_emit_manifest "$P21_INV_WORK/target" "$P21_MANIFEST" 2>/dev/null || true
  )
  if [ -f "$P21_MANIFEST" ] && command -v jq >/dev/null 2>&1; then
    P21_SYMLINK_COUNT="$(jq '[.files[]? | select(.path | test("symlink-target"))] | length' "$P21_MANIFEST" 2>/dev/null || echo "0")"
    if [ "${P21_SYMLINK_COUNT:-0}" -eq 0 ]; then
      pass "inventory: symlink-target.md skipped (not in files[]) (INV-03)"
    else
      fail "inventory: symlink-target.md found in files[] — symlinks must be skipped (INV-03)"
    fi
  else
    fail "inventory: cannot check symlink skip — manifest not created or jq missing (INV-03)"
  fi
  rm -rf "$P21_INV_WORK"
  trap - EXIT

  # CR-01: binary-file skip must work on stock macOS (BSD grep has no -P flag).
  # A .md containing NUL bytes must be excluded from the scan; a plain-text file kept.
  P21_BIN_WORK="$(mktemp -d)"
  trap 'rm -rf "$P21_BIN_WORK"' EXIT
  mkdir -p "$P21_BIN_WORK/target"
  printf '# Title\n\nText.\n' > "$P21_BIN_WORK/target/CLAUDE.md"
  printf 'binary\000content\000here\n' > "$P21_BIN_WORK/target/binary-doc.md"
  P21_BIN_OUT="$(
    source "$CONJURE_HOME/lib/mutate.sh"
    [ -f "$CONJURE_HOME/lib/caps.sh" ]      && source "$CONJURE_HOME/lib/caps.sh"
    [ -f "$CONJURE_HOME/lib/log.sh" ]       && source "$CONJURE_HOME/lib/log.sh"
    [ -f "$CONJURE_HOME/lib/inventory.sh" ] && source "$CONJURE_HOME/lib/inventory.sh"
    DRY_RUN=0
    inventory_scan "$P21_BIN_WORK/target" 2>/dev/null || true
    P21_BIN=$(printf '%s\n' "$CONJURE_INVENTORY_ITEMS" | grep -c 'binary-doc.md' | tr -d ' ')
    P21_CLA=$(printf '%s\n' "$CONJURE_INVENTORY_ITEMS" | grep -c 'CLAUDE.md' | tr -d ' ')
    printf '%s %s\n' "$P21_BIN" "$P21_CLA"
  )"
  P21_BIN_HIT="${P21_BIN_OUT%% *}"
  P21_CLA_HIT="${P21_BIN_OUT##* }"
  if [ "${P21_CLA_HIT:-0}" -ge 1 ] && [ "${P21_BIN_HIT:-1}" = "0" ]; then
    pass "inventory: binary .md (NUL bytes) skipped, text kept (CR-01/INV-03)"
  else
    fail "inventory: binary skip broken (bin=$P21_BIN_HIT claude=$P21_CLA_HIT) (CR-01/INV-03)"
  fi
  rm -rf "$P21_BIN_WORK"
  trap - EXIT

  # INV-03: 500-file cap — use generate-large.sh
  P21_CAP_WORK="$(mktemp -d)"
  trap 'rm -rf "$P21_CAP_WORK"' EXIT
  mkdir -p "$P21_CAP_WORK/target"
  printf '# CLAUDE\n\nCap test fixture.\n' > "$P21_CAP_WORK/target/CLAUDE.md"
  bash "$CONJURE_HOME/tests/fixtures/brownfield-simple/generate-large.sh" "$P21_CAP_WORK/target" >/dev/null 2>&1
  P21_MANIFEST="$P21_CAP_WORK/adopt-manifest.json"
  (
    source "$CONJURE_HOME/lib/mutate.sh"
    [ -f "$CONJURE_HOME/lib/caps.sh" ]     && source "$CONJURE_HOME/lib/caps.sh"
    [ -f "$CONJURE_HOME/lib/log.sh" ]      && source "$CONJURE_HOME/lib/log.sh"
    [ -f "$CONJURE_HOME/lib/inventory.sh" ] && source "$CONJURE_HOME/lib/inventory.sh"
    DRY_RUN=0
    RESTRUCTURE_LOG_PATH="$P21_CAP_WORK/RESTRUCTURE-LOG.md"
    CONJURE_DRY_MUTATION_COUNT=0
    inventory_scan "$P21_CAP_WORK/target" 2>/dev/null || true
    inventory_emit_manifest "$P21_CAP_WORK/target" "$P21_MANIFEST" 2>/dev/null || true
  )
  if [ -f "$P21_MANIFEST" ] && command -v jq >/dev/null 2>&1; then
    if jq -e '.summary.scan_capped == true' "$P21_MANIFEST" >/dev/null 2>&1; then
      pass "inventory: scan_capped=true for 510-file fixture (INV-03)"
    else
      fail "inventory: scan_capped expected true for 510-file fixture (INV-03)"
    fi
    if jq -e '.summary.total_found > 500' "$P21_MANIFEST" >/dev/null 2>&1; then
      pass "inventory: total_found > 500 (INV-03)"
    else
      P21_TF="$(jq '.summary.total_found // "N/A"' "$P21_MANIFEST" 2>/dev/null || echo "N/A")"
      fail "inventory: total_found expected >500, got $P21_TF (INV-03)"
    fi
    if jq -e '(.files | length) <= 500' "$P21_MANIFEST" >/dev/null 2>&1; then
      pass "inventory: files[] capped at <= 500 entries (INV-03)"
    else
      P21_FL="$(jq '.files | length' "$P21_MANIFEST" 2>/dev/null || echo "N/A")"
      fail "inventory: files[] length $P21_FL exceeds cap of 500 (INV-03)"
    fi
    # Harness-first: CLAUDE.md must be in files[]
    if jq -e '.files[] | select(.path == "CLAUDE.md") | .classification == "core"' "$P21_MANIFEST" >/dev/null 2>&1; then
      pass "inventory: CLAUDE.md always included (harness-first budget) (INV-03)"
    else
      fail "inventory: CLAUDE.md missing from files[] in 510-file fixture (INV-03)"
    fi
  else
    fail "inventory: cannot check cap behavior — manifest not created or jq missing (INV-03)"
  fi
  rm -rf "$P21_CAP_WORK"
  trap - EXIT

  # INV-04: size_cap_exceeded for oversized CLAUDE.md
  P21_SZ_WORK="$(mktemp -d)"
  trap 'rm -rf "$P21_SZ_WORK"' EXIT
  mkdir -p "$P21_SZ_WORK/target"
  printf '# CLAUDE\n\nOversized test.\n' > "$P21_SZ_WORK/target/CLAUDE.md"
  # Add 105 lines to exceed CLAUDE_MD_CAP=100
  i=1
  while [ "$i" -le 105 ]; do printf '# filler %s\n' "$i" >> "$P21_SZ_WORK/target/CLAUDE.md"; i=$((i+1)); done
  P21_MANIFEST="$P21_SZ_WORK/adopt-manifest.json"
  (
    source "$CONJURE_HOME/lib/mutate.sh"
    [ -f "$CONJURE_HOME/lib/caps.sh" ]     && source "$CONJURE_HOME/lib/caps.sh"
    [ -f "$CONJURE_HOME/lib/log.sh" ]      && source "$CONJURE_HOME/lib/log.sh"
    [ -f "$CONJURE_HOME/lib/inventory.sh" ] && source "$CONJURE_HOME/lib/inventory.sh"
    DRY_RUN=0
    RESTRUCTURE_LOG_PATH="$P21_SZ_WORK/RESTRUCTURE-LOG.md"
    CONJURE_DRY_MUTATION_COUNT=0
    inventory_scan "$P21_SZ_WORK/target" 2>/dev/null || true
    inventory_emit_manifest "$P21_SZ_WORK/target" "$P21_MANIFEST" 2>/dev/null || true
  )
  if [ -f "$P21_MANIFEST" ] && command -v jq >/dev/null 2>&1; then
    if jq -e '.files[] | select(.path == "CLAUDE.md") | .size_cap_exceeded == true' "$P21_MANIFEST" >/dev/null 2>&1; then
      pass "inventory: size_cap_exceeded=true for 108-line CLAUDE.md (INV-04)"
    else
      fail "inventory: size_cap_exceeded expected true for oversized CLAUDE.md (INV-04)"
    fi
    if jq -e '.size_cap_violations | length > 0' "$P21_MANIFEST" >/dev/null 2>&1; then
      pass "inventory: size_cap_violations[] populated (INV-04)"
    else
      fail "inventory: size_cap_violations[] empty for oversized CLAUDE.md (INV-04)"
    fi
  else
    fail "inventory: cannot check size cap violation — manifest not created or jq missing (INV-04)"
  fi
  rm -rf "$P21_SZ_WORK"
  trap - EXIT
fi

echo
echo "▸ Phase 21 — mutate_archive (SAFE-03)"

P21_ARCHIVE_OK=0
# mutate_archive lives in lib/mutate.sh — check if it has been added
if ! grep -q "mutate_archive" "$CONJURE_HOME/lib/mutate.sh" 2>/dev/null; then
  fail "mutate_archive not found in lib/mutate.sh — Wave 1 must add it (SAFE-03)"
else
  P21_ARCHIVE_OK=1

  # DRY_RUN=1 test
  P21_ARCH_TMPFILE="$(mktemp)"
  P21_ARCH_DRY_ROOT="/tmp/conjure-p21-arch-dryroot-$$"
  P21_ARCH_DRY_OUT="$(
    DRY_RUN=1 _P21_ARCH_SRC="$P21_ARCH_TMPFILE" _P21_ARCH_ROOT="$P21_ARCH_DRY_ROOT" \
    CONJURE_HOME="$CONJURE_HOME" \
    bash -c '
      source "$CONJURE_HOME/lib/mutate.sh"
      CONJURE_DRY_MUTATION_COUNT=0
      mutate_archive "$_P21_ARCH_SRC" "$_P21_ARCH_ROOT"
      printf "%s\n" "[count=$CONJURE_DRY_MUTATION_COUNT]"
    ' 2>&1
  )"
  if printf '%s\n' "$P21_ARCH_DRY_OUT" | grep -q "would archive"; then
    pass "mutate_archive DRY_RUN=1: output contains 'would archive' (SAFE-03)"
  else
    fail "mutate_archive DRY_RUN=1: missing 'would archive' — got: $P21_ARCH_DRY_OUT (SAFE-03)"
  fi
  if printf '%s\n' "$P21_ARCH_DRY_OUT" | grep -q "\[count=1\]"; then
    pass "mutate_archive DRY_RUN=1: CONJURE_DRY_MUTATION_COUNT incremented (SAFE-03)"
  else
    fail "mutate_archive DRY_RUN=1: counter not incremented — got: $P21_ARCH_DRY_OUT (SAFE-03)"
  fi
  if [ -f "$P21_ARCH_TMPFILE" ]; then
    pass "mutate_archive DRY_RUN=1: original file still exists (SAFE-03)"
  else
    fail "mutate_archive DRY_RUN=1: original file was deleted (SAFE-03)"
  fi
  rm -f "$P21_ARCH_TMPFILE"

  # Live mode: file moved to archive, not deleted
  P21_ARCH_WORK="$(mktemp -d)"
  trap 'rm -rf "$P21_ARCH_WORK"' EXIT
  P21_ARCH_SRC="$P21_ARCH_WORK/src/original.md"
  mkdir -p "$P21_ARCH_WORK/src"
  printf 'hello archive\n' > "$P21_ARCH_SRC"
  P21_ARCH_ROOT="$P21_ARCH_WORK/archive-root"
  source "$CONJURE_HOME/lib/mutate.sh"
  DRY_RUN=0
  CONJURE_DRY_MUTATION_COUNT=0
  mutate_archive "$P21_ARCH_SRC" "$P21_ARCH_ROOT" 2>/dev/null
  P21_ARCH_RC=$?
  if [ ! -f "$P21_ARCH_SRC" ]; then
    pass "mutate_archive live: source file no longer at original path (SAFE-03)"
  else
    fail "mutate_archive live: source file still present after archive (SAFE-03)"
  fi
  # Archive destination should preserve path structure
  P21_ARCH_DEST_COUNT="$(find "$P21_ARCH_ROOT" -name 'original.md' 2>/dev/null | wc -l | tr -d ' ')"
  if [ "${P21_ARCH_DEST_COUNT:-0}" -ge 1 ]; then
    pass "mutate_archive live: file exists in archive at path-preserving location (SAFE-03)"
  else
    fail "mutate_archive live: file not found in archive (SAFE-03)"
  fi
  # Ledger file
  if [ -f "$P21_ARCH_ROOT/.archive-ledger" ]; then
    pass "mutate_archive live: .archive-ledger file created (SAFE-03)"
  else
    fail "mutate_archive live: .archive-ledger missing (SAFE-03)"
  fi
  if [ -f "$P21_ARCH_ROOT/.archive-ledger" ] && grep -q "original.md" "$P21_ARCH_ROOT/.archive-ledger"; then
    pass "mutate_archive live: ledger contains source path (SAFE-03)"
  else
    fail "mutate_archive live: ledger missing or does not contain source path (SAFE-03)"
  fi

  # D-13 abort test: simulate failure so mutate_archive returns non-zero without deleting src.
  # We use a read-only archive root so that mkdir -p inside the dest dir path fails,
  # causing cp to fail — verifying that src is never deleted when the copy itself fails.
  P21_ARCH_WORK2="$(mktemp -d)"
  trap 'chmod -R u+w "$P21_ARCH_WORK2" 2>/dev/null; rm -rf "$P21_ARCH_WORK2"' EXIT
  P21_SHA_SRC="$P21_ARCH_WORK2/src-sha.md"
  printf 'original content\n' > "$P21_SHA_SRC"
  P21_SHA_ROOT="$P21_ARCH_WORK2/sha-archive"
  mkdir -p "$P21_SHA_ROOT"
  # Make archive root read-only so mkdir -p / cp inside it will fail → D-13 abort path
  chmod 555 "$P21_SHA_ROOT"
  source "$CONJURE_HOME/lib/mutate.sh"
  DRY_RUN=0
  CONJURE_DRY_MUTATION_COUNT=0
  mutate_archive "$P21_SHA_SRC" "$P21_SHA_ROOT" 2>/dev/null
  P21_SHA_RC=$?
  chmod u+w "$P21_SHA_ROOT" 2>/dev/null || true
  if [ "$P21_SHA_RC" -ne 0 ]; then
    pass "mutate_archive: copy failure aborts (non-zero return) (SAFE-03)"
  else
    fail "mutate_archive: copy failure should abort, got rc=0 (SAFE-03)"
  fi
  if [ -f "$P21_SHA_SRC" ]; then
    pass "mutate_archive: source preserved on copy abort — D-13 guarantee (SAFE-03)"
  else
    fail "mutate_archive: source was deleted despite copy abort — D-13 violation (SAFE-03)"
  fi

  # CR-02 path-traversal guard: a src containing '..' or a relative src must abort
  # before any copy/delete, so attacker-controlled paths cannot escape archive_root.
  P21_ARCH_WORK3="$(mktemp -d)"
  trap 'rm -rf "$P21_ARCH_WORK3"' EXIT
  P21_TRAV_SRC="$P21_ARCH_WORK3/sub/../sub/evil.md"
  mkdir -p "$P21_ARCH_WORK3/sub"
  printf 'evil\n' > "$P21_ARCH_WORK3/sub/evil.md"
  P21_TRAV_ROOT="$P21_ARCH_WORK3/arch"
  source "$CONJURE_HOME/lib/mutate.sh"
  DRY_RUN=0
  mutate_archive "$P21_TRAV_SRC" "$P21_TRAV_ROOT" 2>/dev/null
  if [ "$?" -ne 0 ]; then
    pass "mutate_archive: '..' traversal src aborts (CR-02/SAFE-03)"
  else
    fail "mutate_archive: '..' traversal src should abort, got rc=0 (CR-02/SAFE-03)"
  fi
  if [ -f "$P21_ARCH_WORK3/sub/evil.md" ]; then
    pass "mutate_archive: source preserved on traversal abort (CR-02/SAFE-03)"
  else
    fail "mutate_archive: source deleted despite traversal abort (CR-02/SAFE-03)"
  fi
  mutate_archive "relative/path.md" "$P21_TRAV_ROOT" 2>/dev/null
  if [ "$?" -ne 0 ]; then
    pass "mutate_archive: relative (non-absolute) src aborts (CR-02/SAFE-03)"
  else
    fail "mutate_archive: relative src should abort, got rc=0 (CR-02/SAFE-03)"
  fi

  chmod -R u+w "$P21_ARCH_WORK2" 2>/dev/null || true
  rm -rf "$P21_ARCH_WORK" "$P21_ARCH_WORK2" "$P21_ARCH_WORK3"
  trap - EXIT
fi

echo
echo "▸ Phase 21 — audit-setup.sh caps (SC-5)"

P21_AUDIT_CAP_COUNT=$(grep -v '^#' "$CONJURE_HOME/scripts/audit-setup.sh" 2>/dev/null | grep -c 'CLAUDE_MD_CAP' 2>/dev/null || true)
P21_AUDIT_CAP_COUNT="${P21_AUDIT_CAP_COUNT:-0}"
if [ "$P21_AUDIT_CAP_COUNT" -gt 0 ] 2>/dev/null; then
  pass "audit-setup.sh uses CLAUDE_MD_CAP variable (SC-5)"
else
  fail "audit-setup.sh not yet updated — Plan 04 required to source lib/caps.sh (SC-5)"
fi

echo
echo "▸ Phase 21 — manifest schema (SC-4)"

if jq empty "$CONJURE_HOME/adopt-manifest.schema.json" >/dev/null 2>&1; then
  pass "adopt-manifest.schema.json: valid JSON (SC-4)"
else
  fail "adopt-manifest.schema.json: invalid JSON (SC-4)"
fi
if [ "$(jq '.properties.files.items.properties.classification.enum | length' "$CONJURE_HOME/adopt-manifest.schema.json" 2>/dev/null)" = "6" ]; then
  pass "adopt-manifest.schema.json: classification enum has 6 values (SC-4)"
else
  fail "adopt-manifest.schema.json: classification enum does not have 6 values (SC-4)"
fi
# Validate RESEARCH.md Pattern 7 sample JSON against schema structure
P21_SCHEMA_SAMPLE="$(mktemp --suffix=.json 2>/dev/null || mktemp -t tmp.XXXXXX.json)"
trap 'rm -f "$P21_SCHEMA_SAMPLE"' EXIT
cat > "$P21_SCHEMA_SAMPLE" << 'SCHEMA_SAMPLE_EOF'
{
  "schema_version": "1",
  "generated_at": "2026-05-28T14:23:00Z",
  "conjure_version": "0.6.0",
  "target": "/abs/path/to/repo",
  "snapshot_path": "",
  "summary": {
    "total_files": 2,
    "scan_capped": false,
    "total_found": 2,
    "core": 1,
    "skill": 0,
    "agent": 0,
    "planning-doc": 0,
    "reference-doc": 1,
    "unknown": 0
  },
  "files": [
    {
      "path": "CLAUDE.md",
      "classification": "core",
      "line_count": 87,
      "size_bytes": 4200,
      "size_cap_exceeded": false,
      "size_cap_limit": 100,
      "linked_from": []
    },
    {
      "path": "docs/guide.md",
      "classification": "reference-doc",
      "line_count": 45,
      "size_bytes": 1800,
      "size_cap_exceeded": false,
      "size_cap_limit": null,
      "linked_from": ["CLAUDE.md"]
    }
  ],
  "size_cap_violations": [],
  "harness_missing_layers": [],
  "restructure_steps": []
}
SCHEMA_SAMPLE_EOF
if jq -e '.schema_version and .summary and .files' "$P21_SCHEMA_SAMPLE" >/dev/null 2>&1; then
  pass "Pattern 7 sample JSON: contains required top-level keys (SC-4)"
else
  fail "Pattern 7 sample JSON: missing required keys (SC-4)"
fi
rm -f "$P21_SCHEMA_SAMPLE"
trap - EXIT

echo
echo "▸ Phase 21 — perf gate (CR-7)"

if [ "$P21_INV_OK" -eq 1 ] || true; then
  P21_PERF_WORK="$(mktemp -d)"
  trap 'rm -rf "$P21_PERF_WORK"' EXIT
  mkdir -p "$P21_PERF_WORK/target"
  printf '# CLAUDE\n\nPerf test.\n' > "$P21_PERF_WORK/target/CLAUDE.md"
  bash "$CONJURE_HOME/tests/fixtures/brownfield-simple/generate-large.sh" "$P21_PERF_WORK/target" >/dev/null 2>&1
  if [ ! -f "$CONJURE_HOME/lib/inventory.sh" ]; then
    fail "perf gate skipped — lib/inventory.sh not found (CR-7)"
  else
    P21_START="$(date +%s)"
    (
      source "$CONJURE_HOME/lib/mutate.sh"
      [ -f "$CONJURE_HOME/lib/caps.sh" ]     && source "$CONJURE_HOME/lib/caps.sh"
      [ -f "$CONJURE_HOME/lib/log.sh" ]      && source "$CONJURE_HOME/lib/log.sh"
      [ -f "$CONJURE_HOME/lib/inventory.sh" ] && source "$CONJURE_HOME/lib/inventory.sh"
      DRY_RUN=0
      RESTRUCTURE_LOG_PATH="$P21_PERF_WORK/RESTRUCTURE-LOG.md"
      CONJURE_DRY_MUTATION_COUNT=0
      inventory_scan "$P21_PERF_WORK/target" 2>/dev/null || true
      inventory_emit_manifest "$P21_PERF_WORK/target" "$P21_PERF_WORK/adopt-manifest.json" 2>/dev/null || true
    )
    P21_END="$(date +%s)"
    P21_ELAPSED=$((P21_END - P21_START))
    if [ "$P21_ELAPSED" -lt 30 ]; then
      pass "perf gate: inventory_emit_manifest on 510-file fixture completed in ${P21_ELAPSED}s (< 30s) (CR-7)"
    else
      fail "perf gate: inventory_emit_manifest took ${P21_ELAPSED}s (>= 30s limit) (CR-7)"
    fi
  fi
  rm -rf "$P21_PERF_WORK"
  trap - EXIT
fi

# ──────────────────────────────────────────────────────────────────────────────
# End Phase 21 test block
# ──────────────────────────────────────────────────────────────────────────────

# ──────────────────────────────────────────────────────────────────────────────
# Phase 22 — conjure adopt CLI core + rollback (Wave 0 test-first)
# Mirrors the Phase 21 block style: `▸ Phase 22 — ...` headers, t/pass/fail
# helpers, mktemp sandboxes with set/reset EXIT-trap discipline. Every adopt
# invocation is guarded behind `[ -f scripts/adopt.sh ]` so the suite reports
# these assertions as graceful RED (with a "Wave 1 must create scripts/adopt.sh
# first" message) instead of crashing while the production code is absent.
# Production code (scripts/adopt.sh, cmd_adopt) lands in Waves 1-2.
# ──────────────────────────────────────────────────────────────────────────────

# Presence guard shared by every Phase 22 section (mirror P21_CAPS_OK pattern).
P22_ADOPT_SH="$CONJURE_HOME/scripts/adopt.sh"
P22_ADOPT_OK=0
[ -f "$P22_ADOPT_SH" ] && P22_ADOPT_OK=1
# Brownfield fixture all Phase 22 sandboxes copy from (21-line CLAUDE.md,
# pre-existing .claude/skills/git/SKILL.md for the idempotency byte-check).
P22_FIXTURE="$CONJURE_HOME/tests/fixtures/brownfield-simple"

# p22_adopt — invoke scripts/adopt.sh with the cmd_adopt env-var contract.
# Echoes nothing and returns 127 when adopt.sh is absent (callers gate on
# P22_ADOPT_OK first, so this is only a defensive backstop).
p22_adopt() {
  [ "$P22_ADOPT_OK" -eq 1 ] || return 127
  CONJURE_HOME="$CONJURE_HOME" bash "$P22_ADOPT_SH" "$@"
}

# p22_sha — cross-platform sha256 of a single file (mirror lib/mutate.sh 113-123).
p22_sha() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
  else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

echo
echo "▸ Phase 22 — adopt.sh dry-run (ADOPT-02 / criterion 1)"

if [ "$P22_ADOPT_OK" -ne 1 ]; then
  fail "scripts/adopt.sh not found — Wave 1 must create scripts/adopt.sh first (ADOPT-02/criterion 1)"
else
  P22_DRY_TARGET="$(mktemp -d)"
  trap 'rm -rf "$P22_DRY_TARGET"' EXIT
  cp -r "$P22_FIXTURE/." "$P22_DRY_TARGET/"
  P22_DRY_OUT="$(
    DRY_RUN=1 CONJURE_HOME="$CONJURE_HOME" \
      bash "$P22_ADOPT_SH" "$P22_DRY_TARGET" 2>&1
  )"
  # Zero writes under the target: git status clean (sandbox is not a git repo,
  # so fall back to "no new adopt artifacts") AND no manifest landed in target.
  P22_DRY_PORCELAIN="$(git -C "$P22_DRY_TARGET" status --porcelain 2>/dev/null || true)"
  P22_DRY_MANIFEST_COUNT="$(find "$P22_DRY_TARGET" -name adopt-manifest.json 2>/dev/null | wc -l | tr -d ' ')"
  P22_DRY_STATE_COUNT="$(find "$P22_DRY_TARGET" -name '.conjure-adopt-state' 2>/dev/null | wc -l | tr -d ' ')"
  if [ -z "$P22_DRY_PORCELAIN" ]; then
    pass "adopt.sh dry-run: git status --porcelain clean — zero writes (ADOPT-02/criterion 1)"
  else
    fail "adopt.sh dry-run: working tree dirty after dry-run — got: $P22_DRY_PORCELAIN (ADOPT-02/criterion 1)"
  fi
  if [ "${P22_DRY_MANIFEST_COUNT:-1}" -eq 0 ]; then
    pass "adopt.sh dry-run: no adopt-manifest.json under target (Pitfall 1) (ADOPT-02/criterion 1)"
  else
    fail "adopt.sh dry-run: adopt-manifest.json leaked into target — Pitfall 1 (ADOPT-02/criterion 1)"
  fi
  if [ "${P22_DRY_STATE_COUNT:-1}" -eq 0 ]; then
    pass "adopt.sh dry-run: no .conjure-adopt-state under target (ADOPT-02/criterion 1)"
  else
    fail "adopt.sh dry-run: .conjure-adopt-state leaked into target (ADOPT-02/criterion 1)"
  fi
  # All five step labels appear in the plan output.
  P22_DRY_STEPS_OK=1
  for _step in preconditions snapshot inventory scaffold audit; do
    printf '%s\n' "$P22_DRY_OUT" | grep -qi "$_step" || P22_DRY_STEPS_OK=0
  done
  if [ "$P22_DRY_STEPS_OK" -eq 1 ]; then
    pass "adopt.sh dry-run: plan lists all 5 steps (preconditions/snapshot/inventory/scaffold/audit) (ADOPT-02/criterion 1)"
  else
    fail "adopt.sh dry-run: plan missing one or more step labels — got: $P22_DRY_OUT (ADOPT-02/criterion 1)"
  fi
  if printf '%s\n' "$P22_DRY_OUT" | grep -qi '\[dry-run\] would'; then
    pass "adopt.sh dry-run: output contains a '[dry-run] would' marker (ADOPT-02/criterion 1)"
  else
    fail "adopt.sh dry-run: missing '[dry-run] would' marker — got: $P22_DRY_OUT (ADOPT-02/criterion 1)"
  fi
  # D-11: the printed dry-run manifest temp path must NOT be the hardcoded
  # /tmp/adopt-manifest-dryrun.json the lib defaults to (must be mktemp -d).
  if printf '%s\n' "$P22_DRY_OUT" | grep -q '/tmp/adopt-manifest-dryrun.json'; then
    fail "adopt.sh dry-run: manifest path is the hardcoded /tmp/adopt-manifest-dryrun.json — D-11 requires mktemp (ADOPT-02)"
  else
    pass "adopt.sh dry-run: manifest temp path is not the hardcoded /tmp path (D-11) (ADOPT-02)"
  fi
  rm -rf "$P22_DRY_TARGET"
  trap - EXIT
fi

echo
echo "▸ Phase 22 — adopt.sh live (ADOPT-01/04/05/06 / criterion 2)"

if [ "$P22_ADOPT_OK" -ne 1 ]; then
  fail "scripts/adopt.sh not found — Wave 1 must create scripts/adopt.sh first (ADOPT-01/04/05/06/criterion 2)"
else
  P22_LIVE_TARGET="$(mktemp -d)"
  trap 'rm -rf "$P22_LIVE_TARGET"' EXIT
  cp -r "$P22_FIXTURE/." "$P22_LIVE_TARGET/"
  # sha256 of the pre-existing skill BEFORE adopt (ADOPT-04 never-overwrite).
  P22_SKILL_PATH="$P22_LIVE_TARGET/.claude/skills/git/SKILL.md"
  P22_SKILL_BEFORE="$(p22_sha "$P22_SKILL_PATH" 2>/dev/null || echo NA-before)"
  P22_LIVE_OUT="$(
    DRY_RUN=0 CONJURE_HOME="$CONJURE_HOME" \
      bash "$P22_ADOPT_SH" "$P22_LIVE_TARGET" 2>&1
  )"
  # SAFE-01: a snapshot copy of CLAUDE.md exists under .conjure-adopt-backups/.
  P22_BACKUP_CLAUDE_COUNT="$(find "$P22_LIVE_TARGET/.conjure-adopt-backups" -name CLAUDE.md 2>/dev/null | wc -l | tr -d ' ')"
  if [ "${P22_BACKUP_CLAUDE_COUNT:-0}" -ge 1 ]; then
    pass "adopt.sh live: .conjure-adopt-backups/*/CLAUDE.md snapshot exists (SAFE-01/criterion 2)"
  else
    fail "adopt.sh live: no CLAUDE.md snapshot under .conjure-adopt-backups (SAFE-01/criterion 2)"
  fi
  # ADOPT-01: manifest present under target after a live run.
  if [ -f "$P22_LIVE_TARGET/adopt-manifest.json" ]; then
    pass "adopt.sh live: adopt-manifest.json present under target (ADOPT-01/criterion 2)"
  else
    fail "adopt.sh live: adopt-manifest.json missing under target (ADOPT-01/criterion 2)"
  fi
  # ADOPT-04 (scaffold): new .claude/hooks/* were created (fixture has none).
  P22_HOOK_COUNT="$(find "$P22_LIVE_TARGET/.claude/hooks" -type f 2>/dev/null | wc -l | tr -d ' ')"
  if [ "${P22_HOOK_COUNT:-0}" -ge 1 ]; then
    pass "adopt.sh live: missing hooks layer scaffolded (.claude/hooks/*) (ADOPT-04/criterion 2)"
  else
    fail "adopt.sh live: no hooks scaffolded — missing-layer scaffold failed (ADOPT-04/criterion 2)"
  fi
  # ADOPT-04 (never-overwrite): pre-existing SKILL.md is byte-unchanged.
  P22_SKILL_AFTER="$(p22_sha "$P22_SKILL_PATH" 2>/dev/null || echo NA-after)"
  if [ "$P22_SKILL_BEFORE" = "$P22_SKILL_AFTER" ]; then
    pass "adopt.sh live: pre-existing SKILL.md byte-unchanged (sha256 before==after) (ADOPT-04/criterion 2)"
  else
    fail "adopt.sh live: pre-existing SKILL.md was modified ($P22_SKILL_BEFORE != $P22_SKILL_AFTER) — never-overwrite violated (ADOPT-04/criterion 2)"
  fi
  # ADOPT-06: report shows CLAUDE.md before/after line-count (fixture is 21 lines,
  # Phase 22 does not condense it, so the report must read "21 → 21").
  if printf '%s\n' "$P22_LIVE_OUT" | grep -Eq 'CLAUDE\.md:?[[:space:]]*21[[:space:]]*(->|→)[[:space:]]*21'; then
    pass "adopt.sh live: report shows CLAUDE.md 21 -> 21 before/after (ADOPT-06/criterion 2)"
  else
    fail "adopt.sh live: report missing 'CLAUDE.md 21 -> 21' before/after line — got: $P22_LIVE_OUT (ADOPT-06/criterion 2)"
  fi
  # ADOPT-06: report points the user at the next step (restructure skill).
  if printf '%s\n' "$P22_LIVE_OUT" | grep -Eqi 'Next:|restructure'; then
    pass "adopt.sh live: report includes a Next:/restructure pointer (ADOPT-06/criterion 2)"
  else
    fail "adopt.sh live: report missing Next:/restructure pointer (ADOPT-06/criterion 2)"
  fi
  rm -rf "$P22_LIVE_TARGET"
  trap - EXIT
fi

echo
echo "▸ Phase 22 — adopt.sh dirty-tree (ADOPT-03 / SAFE-06 / criterion 3)"

if [ "$P22_ADOPT_OK" -ne 1 ]; then
  fail "scripts/adopt.sh not found — Wave 1 must create scripts/adopt.sh first (ADOPT-03/SAFE-06/criterion 3)"
else
  # git-init dirty-tree harness: commit the fixture, then leave an untracked file
  # so the tree is dirty for adopt's git status --porcelain check (Pitfall 5).
  P22_DIRTY_TARGET="$(mktemp -d)"
  trap 'rm -rf "$P22_DIRTY_TARGET"' EXIT
  cp -r "$P22_FIXTURE/." "$P22_DIRTY_TARGET/"
  git -C "$P22_DIRTY_TARGET" init -q >/dev/null 2>&1
  git -C "$P22_DIRTY_TARGET" config user.email test@conjure.local >/dev/null 2>&1
  git -C "$P22_DIRTY_TARGET" config user.name "Conjure Test" >/dev/null 2>&1
  git -C "$P22_DIRTY_TARGET" add -A >/dev/null 2>&1
  git -C "$P22_DIRTY_TARGET" commit -q -m "fixture baseline" >/dev/null 2>&1
  touch "$P22_DIRTY_TARGET/UNTRACKED.txt"   # makes the tree dirty (untracked file)
  # No --force on a dirty tree → exit 2 (never exit 1).
  DRY_RUN=0 CONJURE_HOME="$CONJURE_HOME" bash "$P22_ADOPT_SH" "$P22_DIRTY_TARGET" >/dev/null 2>&1
  P22_DIRTY_RC=$?
  if [ "$P22_DIRTY_RC" -eq 2 ]; then
    pass "adopt.sh dirty-tree: refuses without --force, exit 2 (ADOPT-03/criterion 3)"
  else
    fail "adopt.sh dirty-tree: expected exit 2 without --force, got $P22_DIRTY_RC (ADOPT-03/criterion 3)"
  fi
  # With --force → proceeds (rc 0) and logs a WARN about uncommitted changes.
  DRY_RUN=0 CONJURE_ADOPT_FORCE=1 CONJURE_HOME="$CONJURE_HOME" bash "$P22_ADOPT_SH" --force "$P22_DIRTY_TARGET" >/dev/null 2>&1
  P22_FORCE_RC=$?
  if [ "$P22_FORCE_RC" -eq 0 ]; then
    pass "adopt.sh dirty-tree: --force proceeds, exit 0 (SAFE-06/criterion 3)"
  else
    fail "adopt.sh dirty-tree: --force expected exit 0, got $P22_FORCE_RC (SAFE-06/criterion 3)"
  fi
  if [ -f "$P22_DIRTY_TARGET/RESTRUCTURE-LOG.md" ] && grep -q 'WARN.*uncommitted' "$P22_DIRTY_TARGET/RESTRUCTURE-LOG.md" 2>/dev/null; then
    pass "adopt.sh dirty-tree: --force logged 'WARN ... uncommitted' to RESTRUCTURE-LOG.md (SAFE-06/criterion 3)"
  else
    fail "adopt.sh dirty-tree: --force did not log a WARN about uncommitted changes (SAFE-06/criterion 3)"
  fi
  rm -rf "$P22_DIRTY_TARGET"
  trap - EXIT
fi

echo
echo "▸ Phase 22 — adopt.sh rollback (SAFE-02 / criterion 4)"

if [ "$P22_ADOPT_OK" -ne 1 ]; then
  fail "scripts/adopt.sh not found — Wave 1 must create scripts/adopt.sh first (SAFE-02/criterion 4)"
else
  P22_RB_TARGET="$(mktemp -d)"
  P22_RB_PRE="$(mktemp -d)"   # pristine pre-adopt copy for the zero-diff comparison
  trap 'rm -rf "$P22_RB_TARGET" "$P22_RB_PRE"' EXIT
  cp -r "$P22_FIXTURE/." "$P22_RB_TARGET/"
  cp -r "$P22_FIXTURE/." "$P22_RB_PRE/"
  # Record sha256 of every pre-adopt file (relative paths) for per-file verify.
  P22_RB_HASHES="$P22_RB_PRE/.p22-hashes"
  ( cd "$P22_RB_TARGET" && find . -type f -not -path './.git/*' | sort | while IFS= read -r f; do
      printf '%s  %s\n' "$(p22_sha "$f")" "$f"
    done ) > "$P22_RB_HASHES" 2>/dev/null
  # Live adopt, then rollback.
  DRY_RUN=0 CONJURE_HOME="$CONJURE_HOME" bash "$P22_ADOPT_SH" "$P22_RB_TARGET" >/dev/null 2>&1
  DRY_RUN=0 CONJURE_ADOPT_ROLLBACK=1 CONJURE_HOME="$CONJURE_HOME" bash "$P22_ADOPT_SH" --rollback "$P22_RB_TARGET" >/dev/null 2>&1
  # Per-file sha256: every pre-adopt file restored to its recorded before-hash.
  P22_RB_MISMATCH=0
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    _h="${line%%  *}"; _f="${line##*  }"
    _now="$(p22_sha "$P22_RB_TARGET/$_f" 2>/dev/null || echo MISSING)"
    [ "$_h" = "$_now" ] || P22_RB_MISMATCH=$((P22_RB_MISMATCH+1))
  done < "$P22_RB_HASHES"
  if [ "$P22_RB_MISMATCH" -eq 0 ]; then
    pass "adopt.sh rollback: every pre-adopt file sha256 == recorded before-hash (SAFE-02/criterion 4)"
  else
    fail "adopt.sh rollback: $P22_RB_MISMATCH file(s) differ from recorded before-hash (SAFE-02/criterion 4)"
  fi
  # created[] scaffolded files are gone after rollback (fixture had no hooks).
  P22_RB_HOOK_COUNT="$(find "$P22_RB_TARGET/.claude/hooks" -type f 2>/dev/null | wc -l | tr -d ' ')"
  if [ "${P22_RB_HOOK_COUNT:-0}" -eq 0 ]; then
    pass "adopt.sh rollback: scaffolded created[] files removed (SAFE-02/criterion 4)"
  else
    fail "adopt.sh rollback: scaffolded files still present after rollback (SAFE-02/criterion 4)"
  fi
  # [ROLLBACK] entry logged.
  if [ -f "$P22_RB_TARGET/RESTRUCTURE-LOG.md" ] && grep -q '\[ROLLBACK\]' "$P22_RB_TARGET/RESTRUCTURE-LOG.md" 2>/dev/null; then
    pass "adopt.sh rollback: [ROLLBACK] entry in RESTRUCTURE-LOG.md (SAFE-02/criterion 4)"
  else
    fail "adopt.sh rollback: no [ROLLBACK] entry in RESTRUCTURE-LOG.md (SAFE-02/criterion 4)"
  fi
  # Zero-diff pre-adopt vs post-rollback, excluding conjure's own dirs (D-03).
  P22_RB_DIFF="$(diff -r \
    -x '.conjure-adopt-backups' -x '.conjure-archive-*' \
    -x 'RESTRUCTURE-LOG.md' -x 'adopt-manifest.json' -x '.conjure-adopt-state' \
    "$P22_RB_PRE" "$P22_RB_TARGET" 2>&1)"
  if [ -z "$P22_RB_DIFF" ]; then
    pass "adopt.sh rollback: diff -r pre-adopt vs post-rollback empty (excl. conjure dirs, D-03) (SAFE-02/criterion 4)"
  else
    fail "adopt.sh rollback: post-rollback diff not empty — got: $P22_RB_DIFF (SAFE-02/criterion 4)"
  fi
  rm -rf "$P22_RB_TARGET" "$P22_RB_PRE"
  trap - EXIT
fi

echo
echo "▸ Phase 22 — adopt.sh state + log (SAFE-04 / SAFE-07)"

if [ "$P22_ADOPT_OK" -ne 1 ]; then
  fail "scripts/adopt.sh not found — Wave 1 must create scripts/adopt.sh first (SAFE-04/SAFE-07)"
else
  P22_SL_TARGET="$(mktemp -d)"
  trap 'rm -rf "$P22_SL_TARGET"' EXIT
  cp -r "$P22_FIXTURE/." "$P22_SL_TARGET/"
  DRY_RUN=0 CONJURE_HOME="$CONJURE_HOME" bash "$P22_ADOPT_SH" "$P22_SL_TARGET" >/dev/null 2>&1
  # SAFE-04: .conjure-adopt-state parses as JSON. Support both forms (file or
  # directory with state.json) per the planner's Discretion in CONTEXT.md.
  P22_SL_STATE="$P22_SL_TARGET/.conjure-adopt-state"
  P22_SL_STATE_JSON=""
  if [ -f "$P22_SL_STATE" ]; then
    P22_SL_STATE_JSON="$P22_SL_STATE"
  elif [ -f "$P22_SL_STATE/state.json" ]; then
    P22_SL_STATE_JSON="$P22_SL_STATE/state.json"
  fi
  if [ -n "$P22_SL_STATE_JSON" ] && jq . "$P22_SL_STATE_JSON" >/dev/null 2>&1; then
    pass "adopt.sh state: .conjure-adopt-state parses as valid JSON (SAFE-04)"
  else
    fail "adopt.sh state: .conjure-adopt-state missing or not valid JSON (SAFE-04)"
  fi
  if [ -n "$P22_SL_STATE_JSON" ] && jq -e '.mutated[0].before' "$P22_SL_STATE_JSON" >/dev/null 2>&1; then
    pass "adopt.sh state: .mutated[].before sha256 recorded (SAFE-04)"
  else
    fail "adopt.sh state: .mutated[].before not present (SAFE-04)"
  fi
  # SAFE-07: RESTRUCTURE-LOG.md carries SNAPSHOT, INVENTORY, SCAFFOLD, AUDIT in order.
  P22_SL_LOG="$P22_SL_TARGET/RESTRUCTURE-LOG.md"
  if [ -f "$P22_SL_LOG" ]; then
    P22_SL_ORDER="$(grep -nE '\[(SNAPSHOT|INVENTORY|SCAFFOLD|AUDIT)\]' "$P22_SL_LOG" 2>/dev/null | sed -E 's/.*\[(SNAPSHOT|INVENTORY|SCAFFOLD|AUDIT)\].*/\1/' | tr '\n' ' ')"
    if printf '%s' "$P22_SL_ORDER" | grep -q 'SNAPSHOT INVENTORY SCAFFOLD AUDIT'; then
      pass "adopt.sh log: SNAPSHOT, INVENTORY, SCAFFOLD, AUDIT entries in order (SAFE-07)"
    else
      fail "adopt.sh log: step entries missing or out of order — got: '$P22_SL_ORDER' (SAFE-07)"
    fi
  else
    fail "adopt.sh log: RESTRUCTURE-LOG.md not created (SAFE-07)"
  fi
  rm -rf "$P22_SL_TARGET"
  trap - EXIT
fi

# ──────────────────────────────────────────────────────────────────────────────
# End Phase 22 test block
# ──────────────────────────────────────────────────────────────────────────────

# Clean up any gh-hiding stub dirs created by mk_path_without_gh
for _s in $GH_HIDE_STUBS; do rm -rf "$_s"; done

# Summary
echo
echo "═══════════════════════════════════════════════════════════════════"
echo "PASS: $PASS    FAIL: $FAIL"
echo "═══════════════════════════════════════════════════════════════════"

[ "$FAIL" -eq 0 ]
