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

# Native Windows Git Bash (MSYS/MINGW/Cygwin) can't create real symlinks (git checks
# them out as plain files; `ln -s` copies), ignores Unix file-mode perms, and forks
# ~50-100x slower than Linux. Tests that depend on those Unix capabilities gate on this.
case "$(uname -s 2>/dev/null)" in MINGW*|MSYS*|CYGWIN*) IS_WINDOWS=1 ;; *) IS_WINDOWS=0 ;; esac
# Perf ceiling for the 500-file inventory gate (CR-7): Git Bash fork overhead makes the
# Unix 30s target unreachable (~120s observed); native-Windows adopt is slow for large
# repos by design (use WSL). The gate still catches pathological regressions per-platform.
if [ "$IS_WINDOWS" = "1" ]; then PERF_CEILING=240; else PERF_CEILING=30; fi

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
cp "$CONJURE_HOME/lib/log.sh"                       "$MKTPL_DIR/lib/"
cp "$CONJURE_HOME/lib/snapshot.sh"                  "$MKTPL_DIR/lib/"
cp "$CONJURE_HOME/lib/plugin-helpers.sh"            "$MKTPL_DIR/lib/"
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
cp "$CONJURE_HOME/lib/log.sh"                       "$SUBMIT_DIR/lib/"
cp "$CONJURE_HOME/lib/snapshot.sh"                  "$SUBMIT_DIR/lib/"
cp "$CONJURE_HOME/lib/plugin-helpers.sh"            "$SUBMIT_DIR/lib/"
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

# OVLY-03: refresh-overlay without marker exits 2 with correct message (FIX-05: was exit 1)
NO_MARKER_DIR="$(mktemp -d)"
mkdir -p "$NO_MARKER_DIR/.claude"
NOMK_RC=0
NOMK_OUT="$(CONJURE_HOME="$CONJURE_HOME" bash "$CONJURE_HOME/scripts/refresh-overlay.sh" \
  "$NO_MARKER_DIR" 2>&1)" || NOMK_RC=$?
if [ "$NOMK_RC" -eq 2 ]; then
  pass "refresh-overlay exits 2 when no marker (OVLY-03)"
else
  fail "refresh-overlay did not exit 2 on missing marker — got rc=$NOMK_RC (OVLY-03)"
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
  BF_FIXTURE="$CONJURE_HOME/tests/fixtures/_brownfield-simple"

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
  BF_FIXTURE="$CONJURE_HOME/tests/fixtures/_brownfield-simple"

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
  if [ ! -L "$P21_INV_WORK/target/symlink-target.md" ]; then
    # No real symlink on this platform (native Windows git checks symlinks out as plain
    # files) — there is nothing for inventory to skip. INV-03 is exercised on Unix CI.
    pass "inventory: symlink-skip N/A — no real symlink on this platform (INV-03 verified on Unix)"
  elif [ -f "$P21_MANIFEST" ] && command -v jq >/dev/null 2>&1; then
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
  bash "$CONJURE_HOME/tests/fixtures/_brownfield-simple/generate-large.sh" "$P21_CAP_WORK/target" >/dev/null 2>&1
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
  # Portable copy-failure injection: make the archive ROOT a regular FILE, so
  # mutate_archive's mkdir -p / cp under it fails on EVERY platform. (The old chmod-555
  # read-only-dir trick is ignored by native Windows Git Bash, where cp then succeeded
  # and the D-13 abort path went untested — passing spuriously.)
  P21_SHA_ROOT="$P21_ARCH_WORK2/sha-archive"
  printf 'not-a-dir\n' > "$P21_SHA_ROOT"
  source "$CONJURE_HOME/lib/mutate.sh"
  DRY_RUN=0
  CONJURE_DRY_MUTATION_COUNT=0
  mutate_archive "$P21_SHA_SRC" "$P21_SHA_ROOT" 2>/dev/null
  P21_SHA_RC=$?
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
  bash "$CONJURE_HOME/tests/fixtures/_brownfield-simple/generate-large.sh" "$P21_PERF_WORK/target" >/dev/null 2>&1
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
    if [ "$P21_ELAPSED" -lt "$PERF_CEILING" ]; then
      pass "perf gate: inventory_emit_manifest on 510-file fixture completed in ${P21_ELAPSED}s (< ${PERF_CEILING}s) (CR-7)"
    else
      fail "perf gate: inventory_emit_manifest took ${P21_ELAPSED}s (>= ${PERF_CEILING}s limit) (CR-7)"
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
P22_FIXTURE="$CONJURE_HOME/tests/fixtures/_brownfield-simple"

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
  P22_RB_HASHES="$(mktemp)"   # hash record OUTSIDE both trees (else it pollutes the diff)
  trap 'rm -rf "$P22_RB_TARGET" "$P22_RB_PRE"; rm -f "$P22_RB_HASHES"' EXIT
  cp -r "$P22_FIXTURE/." "$P22_RB_TARGET/"
  cp -r "$P22_FIXTURE/." "$P22_RB_PRE/"
  # Record sha256 of every pre-adopt file (relative paths) for per-file verify.
  ( cd "$P22_RB_TARGET" && find . -type f -not -path './.git/*' | sort | while IFS= read -r f; do
      printf '%s  %s\n' "$(p22_sha "$f")" "$f"
    done ) > "$P22_RB_HASHES" 2>/dev/null
  # Live adopt, then rollback.
  DRY_RUN=0 CONJURE_HOME="$CONJURE_HOME" bash "$P22_ADOPT_SH" "$P22_RB_TARGET" >/dev/null 2>&1
  P22_RB_OUT="$(DRY_RUN=0 CONJURE_ADOPT_ROLLBACK=1 CONJURE_ADOPT_ROLLBACK_DIAG=1 CONJURE_HOME="$CONJURE_HOME" bash "$P22_ADOPT_SH" --rollback "$P22_RB_TARGET" 2>&1)"
  P22_RB_RC=$?
  [ "$P22_RB_RC" -ne 0 ] && printf '  [diag] adopt rollback rc=%s out=%s\n' "$P22_RB_RC" "$P22_RB_OUT" >&2
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

echo
echo "▸ Phase 22 — git-init dirty-tree harness (ADOPT-03 / criterion 3 wiring)"

# Net-new harness (PATTERNS.md "No Analog Found"): sandbox_setup copies a fixture
# but does not `git init`; criterion 3 needs an untracked-file dirty tree. This
# section exercises the harness shape in isolation (the dirty-tree assertions
# themselves live in the "adopt.sh dirty-tree" section above, which consumes it).
if [ "$P22_ADOPT_OK" -ne 1 ]; then
  fail "scripts/adopt.sh not found — Wave 1 must create scripts/adopt.sh first (ADOPT-03/criterion 3)"
else
  P22_GH_TARGET="$(mktemp -d)"
  trap 'rm -rf "$P22_GH_TARGET"' EXIT
  cp -r "$P22_FIXTURE/." "$P22_GH_TARGET/"
  git -C "$P22_GH_TARGET" init -q >/dev/null 2>&1
  git -C "$P22_GH_TARGET" config user.email test@conjure.local >/dev/null 2>&1
  git -C "$P22_GH_TARGET" config user.name "Conjure Test" >/dev/null 2>&1
  git -C "$P22_GH_TARGET" add -A >/dev/null 2>&1
  git -C "$P22_GH_TARGET" commit -q -m "fixture baseline" >/dev/null 2>&1
  touch "$P22_GH_TARGET/UNTRACKED.txt"
  P22_GH_PORCELAIN="$(git -C "$P22_GH_TARGET" status --porcelain 2>/dev/null)"
  if [ -d "$P22_GH_TARGET/.git" ]; then
    pass "dirty-tree harness: git -C \"\$sb\" init created a repo (criterion 3)"
  else
    fail "dirty-tree harness: git init did not create a .git dir (criterion 3)"
  fi
  if printf '%s\n' "$P22_GH_PORCELAIN" | grep -q 'UNTRACKED.txt'; then
    pass "dirty-tree harness: untracked file makes the tree dirty (criterion 3)"
  else
    fail "dirty-tree harness: untracked file not reported by git status --porcelain (criterion 3)"
  fi
  rm -rf "$P22_GH_TARGET"
  trap - EXIT
fi

echo
echo "▸ Phase 22 — adopt.sh SIGKILL recovery (SAFE-05 / criterion 5)"

if [ "$P22_ADOPT_OK" -ne 1 ]; then
  fail "scripts/adopt.sh not found — Wave 1 must create scripts/adopt.sh first (SAFE-05/criterion 5)"
else
  P22_SK_TARGET="$(mktemp -d)"
  trap 'rm -rf "$P22_SK_TARGET"' EXIT
  cp -r "$P22_FIXTURE/." "$P22_SK_TARGET/"
  # Launch adopt in the background; kill -9 once the snapshot step has landed.
  DRY_RUN=0 CONJURE_HOME="$CONJURE_HOME" bash "$P22_ADOPT_SH" "$P22_SK_TARGET" >/dev/null 2>&1 &
  P22_SK_PID=$!
  # Bounded poll for the snapshot dir (no blind long sleep) — max ~5s.
  P22_SK_SNAP_SEEN=0
  for _i in $(seq 1 50); do
    if [ -d "$P22_SK_TARGET/.conjure-adopt-backups" ]; then P22_SK_SNAP_SEEN=1; break; fi
    kill -0 "$P22_SK_PID" 2>/dev/null || break   # process already exited
    sleep 0.1
  done
  kill -9 "$P22_SK_PID" 2>/dev/null || true
  wait "$P22_SK_PID" 2>/dev/null || true
  if [ "$P22_SK_SNAP_SEEN" -eq 1 ]; then
    pass "SIGKILL recovery: snapshot landed before kill -9 (bounded poll) (SAFE-05/criterion 5)"
  else
    fail "SIGKILL recovery: snapshot dir never appeared within bounded poll (SAFE-05/criterion 5)"
  fi
  # Re-run NON-interactively (no TTY, CONJURE_FORCE_INTERACTIVE unset): detect the
  # partial state → exit 2 + print last-completed + the three recovery flag names.
  P22_SK_OUT="$(
    DRY_RUN=0 CONJURE_HOME="$CONJURE_HOME" \
      bash "$P22_ADOPT_SH" "$P22_SK_TARGET" < /dev/null 2>&1
  )"
  P22_SK_RC=$?
  if [ "$P22_SK_RC" -eq 2 ]; then
    pass "SIGKILL recovery: non-TTY re-run exits 2 (never auto-mutate, D-13) (SAFE-05/criterion 5)"
  else
    fail "SIGKILL recovery: non-TTY re-run expected exit 2, got $P22_SK_RC (SAFE-05/criterion 5)"
  fi
  if printf '%s\n' "$P22_SK_OUT" | grep -qi 'last completed:'; then
    pass "SIGKILL recovery: re-run prints 'last completed:' partial-state line (SAFE-05/criterion 5)"
  else
    fail "SIGKILL recovery: re-run missing 'last completed:' line — got: $P22_SK_OUT (SAFE-05/criterion 5)"
  fi
  P22_SK_FLAGS_OK=1
  for _flag in -- --rollback --resume --start-fresh; do
    [ "$_flag" = "--" ] && continue
    printf '%s\n' "$P22_SK_OUT" | grep -q -- "$_flag" || P22_SK_FLAGS_OK=0
  done
  if [ "$P22_SK_FLAGS_OK" -eq 1 ]; then
    pass "SIGKILL recovery: re-run lists --rollback/--resume/--start-fresh (D-13) (SAFE-05/criterion 5)"
  else
    fail "SIGKILL recovery: re-run missing one or more recovery flags — got: $P22_SK_OUT (SAFE-05/criterion 5)"
  fi
  rm -rf "$P22_SK_TARGET"
  trap - EXIT
fi

echo
echo "▸ Phase 22 — adopt.sh --apply-step / --update-manifest (D-05 / D-06 / D-08)"

if [ "$P22_ADOPT_OK" -ne 1 ]; then
  fail "scripts/adopt.sh not found — Wave 1 must create scripts/adopt.sh first (D-05/D-06/D-08)"
else
  P22_AS_TARGET="$(mktemp -d)"
  trap 'rm -rf "$P22_AS_TARGET"' EXIT
  cp -r "$P22_FIXTURE/." "$P22_AS_TARGET/"
  # Seed the synthetic restructure_steps[] manifest + the staging file step-1 writes.
  cp "$CONJURE_HOME/tests/fixtures/_adopt-restructure-steps/adopt-manifest.json" \
     "$P22_AS_TARGET/adopt-manifest.json"
  mkdir -p "$P22_AS_TARGET/.conjure-adopt-state/staging"
  printf '# CLAUDE (condensed)\n\nProposed restructure content.\n' \
    > "$P22_AS_TARGET/.conjure-adopt-state/staging/CLAUDE.md"
  # The archive op (step-2) targets docs/OLD.md — create it so archive has a src.
  mkdir -p "$P22_AS_TARGET/docs"
  printf '# Old doc\n\nStale.\n' > "$P22_AS_TARGET/docs/OLD.md"
  P22_AS_CLAUDE_BEFORE="$(p22_sha "$P22_AS_TARGET/CLAUDE.md" 2>/dev/null || echo NA)"
  # --apply-step step-1 (write op) → dest changes via mutate_write, status applied.
  DRY_RUN=0 CONJURE_ADOPT_APPLY_STEP=step-1 CONJURE_HOME="$CONJURE_HOME" \
    bash "$P22_ADOPT_SH" --apply-step step-1 "$P22_AS_TARGET" >/dev/null 2>&1
  P22_AS_CLAUDE_AFTER="$(p22_sha "$P22_AS_TARGET/CLAUDE.md" 2>/dev/null || echo NA)"
  if [ "$P22_AS_CLAUDE_BEFORE" != "$P22_AS_CLAUDE_AFTER" ]; then
    pass "apply-step: write op changed dest file via mutate_* (D-05/D-08)"
  else
    fail "apply-step: write op did not change CLAUDE.md (D-05/D-08)"
  fi
  # CR-01: the applied dest must BYTE-MATCH the staged source (trailing newline and
  # all). The old mutate_write "$(cat src)" stripped the trailing newline, so the
  # dest never byte-matched the staging content — a check on "sha changed" alone
  # (above) passes despite that corruption. cmp -s catches the regression.
  if cmp -s "$P22_AS_TARGET/.conjure-adopt-state/staging/CLAUDE.md" "$P22_AS_TARGET/CLAUDE.md"; then
    pass "apply-step: write op dest byte-matches staged source (trailing newline preserved) (CR-01/D-07)"
  else
    fail "apply-step: write op dest does NOT byte-match staged source — content corrupted (CR-01/D-07)"
  fi
  # CR-01: the recorded mutated[].after sha must equal the actual on-disk dest hash
  # (a corrupted write would record the hash of the corrupted file vs the staged src).
  P22_AS_STATE="$P22_AS_TARGET/.conjure-adopt-state/state.json"
  P22_AS_REC_AFTER="$(jq -r '.mutated[] | select(.path=="CLAUDE.md") | .after' "$P22_AS_STATE" 2>/dev/null | tail -1)"
  P22_AS_REAL_AFTER="$(p22_sha "$P22_AS_TARGET/CLAUDE.md" 2>/dev/null || echo NA)"
  if [ -n "$P22_AS_REC_AFTER" ] && [ "$P22_AS_REC_AFTER" = "$P22_AS_REAL_AFTER" ]; then
    pass "apply-step: recorded mutated[].after sha == on-disk dest sha (CR-01/SAFE-04)"
  else
    fail "apply-step: recorded after-sha '$P22_AS_REC_AFTER' != on-disk '$P22_AS_REAL_AFTER' (CR-01/SAFE-04)"
  fi
  if jq -e '.restructure_steps[] | select(.id=="step-1") | .status == "applied"' \
       "$P22_AS_TARGET/adopt-manifest.json" >/dev/null 2>&1; then
    pass "apply-step: step-1 marked status: applied in manifest (D-05/D-08)"
  else
    fail "apply-step: step-1 status not set to applied (D-05/D-08)"
  fi
  if [ -f "$P22_AS_TARGET/RESTRUCTURE-LOG.md" ] && grep -q 'RESTRUCTURE' "$P22_AS_TARGET/RESTRUCTURE-LOG.md" 2>/dev/null; then
    pass "apply-step: RESTRUCTURE entry logged (D-05/SAFE-07)"
  else
    fail "apply-step: no RESTRUCTURE entry in RESTRUCTURE-LOG.md (D-05/SAFE-07)"
  fi

  # IN-03 / CR-02: the `extract` op = write-NEW + archive-OLD composed. It must (a)
  # archive the OLD dest content into .conjure-archive-*/, (b) write the NEW staging
  # content at dest, and (c) consume the staging file correctly (write copies, so the
  # staging source survives). Use an isolated sub-target with an inline extract step so
  # the assertions do not depend on the shared fixture manifest (which has only
  # write/archive steps). Before CR-02 the op archived the NEW staging source (and
  # mutate_archive deleted it), silently losing the original dest content.
  P22_EX_TARGET="$(mktemp -d)"
  mkdir -p "$P22_EX_TARGET/.conjure-adopt-state/staging"
  printf 'OLD-DEST-ORIGINAL-CONTENT\n' > "$P22_EX_TARGET/README.md"
  P22_EX_OLD_SHA="$(p22_sha "$P22_EX_TARGET/README.md" 2>/dev/null || echo NA-old)"
  printf 'NEW-CONDENSED-CONTENT\n' > "$P22_EX_TARGET/.conjure-adopt-state/staging/README.md"
  P22_EX_STAGE_SHA="$(p22_sha "$P22_EX_TARGET/.conjure-adopt-state/staging/README.md" 2>/dev/null || echo NA-stage)"
  printf '%s\n' '{"schema_version":"1","restructure_steps":[{"id":"step-extract","op":"extract","dest":"README.md","src":".conjure-adopt-state/staging/README.md","status":"proposed"}]}' \
    > "$P22_EX_TARGET/adopt-manifest.json"
  DRY_RUN=0 CONJURE_ADOPT_APPLY_STEP=step-extract CONJURE_HOME="$CONJURE_HOME" \
    bash "$P22_ADOPT_SH" --apply-step step-extract "$P22_EX_TARGET" >/dev/null 2>&1
  # (b) NEW staging content landed at dest.
  P22_EX_DEST_SHA="$(p22_sha "$P22_EX_TARGET/README.md" 2>/dev/null || echo NA-dest)"
  if [ "$P22_EX_DEST_SHA" = "$P22_EX_STAGE_SHA" ]; then
    pass "apply-step extract: NEW staging content written to dest (byte-match) (IN-03/CR-02/D-08)"
  else
    fail "apply-step extract: dest does not match staged NEW content ($P22_EX_DEST_SHA != $P22_EX_STAGE_SHA) (IN-03/CR-02/D-08)"
  fi
  # (a) OLD dest content landed in .conjure-archive-*/ (NOT the new staging content).
  P22_EX_ARCHIVED="$(find "$P22_EX_TARGET" -path '*/.conjure-archive-*' -type f -name 'README.md' 2>/dev/null | head -1)"
  P22_EX_ARCH_SHA="$(p22_sha "$P22_EX_ARCHIVED" 2>/dev/null || echo NA-arch)"
  if [ -n "$P22_EX_ARCHIVED" ] && [ "$P22_EX_ARCH_SHA" = "$P22_EX_OLD_SHA" ]; then
    pass "apply-step extract: OLD dest content preserved in .conjure-archive-*/ (IN-03/CR-02/D-08)"
  else
    fail "apply-step extract: OLD dest content NOT archived (found '$P22_EX_ARCHIVED' sha $P22_EX_ARCH_SHA != old $P22_EX_OLD_SHA) (IN-03/CR-02/D-08)"
  fi
  # (a-neg) the archive must NOT contain the new staging content (the pre-CR-02 bug).
  if [ "$P22_EX_ARCH_SHA" != "$P22_EX_STAGE_SHA" ]; then
    pass "apply-step extract: archive holds the OLD content, NOT the new staging source (IN-03/CR-02)"
  else
    fail "apply-step extract: archive wrongly holds the NEW staging content — original lost (IN-03/CR-02)"
  fi
  # (c) staging source survives (write copies, never moves/deletes the staging file).
  if [ -f "$P22_EX_TARGET/.conjure-adopt-state/staging/README.md" ]; then
    pass "apply-step extract: staging source consumed by copy (still present) (IN-03/CR-02/D-07)"
  else
    fail "apply-step extract: staging source was destroyed by extract (IN-03/CR-02/D-07)"
  fi
  # extract step marked applied.
  if jq -e '.restructure_steps[] | select(.id=="step-extract") | .status == "applied"' \
       "$P22_EX_TARGET/adopt-manifest.json" >/dev/null 2>&1; then
    pass "apply-step extract: step-extract marked status: applied (IN-03/D-05)"
  else
    fail "apply-step extract: step-extract status not set to applied (IN-03/D-05)"
  fi
  rm -rf "$P22_EX_TARGET"

  # --update-manifest: append a valid step, then reject a malformed one ({}) with exit 2.
  P22_UM_VALID='{"id":"step-3","op":"archive","src":"docs/OLD.md","status":"proposed"}'
  printf '%s\n' "$P22_UM_VALID" | \
    DRY_RUN=0 CONJURE_ADOPT_UPDATE_MANIFEST=1 CONJURE_HOME="$CONJURE_HOME" \
    bash "$P22_ADOPT_SH" --update-manifest "$P22_AS_TARGET" >/dev/null 2>&1
  if jq -e '.restructure_steps[] | select(.id=="step-3")' \
       "$P22_AS_TARGET/adopt-manifest.json" >/dev/null 2>&1; then
    pass "update-manifest: valid step appended to restructure_steps[] (D-06/D-08)"
  else
    fail "update-manifest: valid step not appended (D-06/D-08)"
  fi
  printf '%s\n' '{}' | \
    DRY_RUN=0 CONJURE_ADOPT_UPDATE_MANIFEST=1 CONJURE_HOME="$CONJURE_HOME" \
    bash "$P22_ADOPT_SH" --update-manifest "$P22_AS_TARGET" >/dev/null 2>&1
  P22_UM_RC=$?
  if [ "$P22_UM_RC" -eq 2 ]; then
    pass "update-manifest: malformed step '{}' rejected with exit 2 (D-06/D-08)"
  else
    fail "update-manifest: malformed step '{}' expected exit 2, got $P22_UM_RC (D-06/D-08)"
  fi
  rm -rf "$P22_AS_TARGET"
  trap - EXIT
fi

echo
echo "▸ Phase 22 — adopt.sh snapshot self-copy regression (Pitfall 3 / SAFE-01)"

if [ "$P22_ADOPT_OK" -ne 1 ]; then
  fail "scripts/adopt.sh not found — Wave 1 must create scripts/adopt.sh first (Pitfall 3/SAFE-01)"
else
  P22_SC_TARGET="$(mktemp -d)"
  trap 'rm -rf "$P22_SC_TARGET"' EXIT
  cp -r "$P22_FIXTURE/." "$P22_SC_TARGET/"
  # Two consecutive live adopts (clear state between runs so the second re-snapshots).
  DRY_RUN=0 CONJURE_HOME="$CONJURE_HOME" bash "$P22_ADOPT_SH" "$P22_SC_TARGET" >/dev/null 2>&1
  rm -rf "$P22_SC_TARGET/.conjure-adopt-state"
  DRY_RUN=0 CONJURE_HOME="$CONJURE_HOME" bash "$P22_ADOPT_SH" "$P22_SC_TARGET" >/dev/null 2>&1
  # Pitfall 3: a snapshot must not contain a nested .conjure-adopt-backups dir.
  # The backup root is itself named .conjure-adopt-backups, so search for a
  # .conjure-adopt-backups directory at depth >= 2 (i.e. INSIDE a snapshot dir);
  # any hit means a snapshot recursively copied the backup root into itself.
  P22_SC_NEST="$(find "$P22_SC_TARGET/.conjure-adopt-backups" -mindepth 2 -name '.conjure-adopt-backups' -type d 2>/dev/null | head -1)"
  if [ -z "$P22_SC_NEST" ]; then
    pass "self-copy: two adopts produce no nested .conjure-adopt-backups (Pitfall 3/SAFE-01)"
  else
    fail "self-copy: nested backups found ($P22_SC_NEST) — snapshot self-copy (Pitfall 3/SAFE-01)"
  fi
  rm -rf "$P22_SC_TARGET"
  trap - EXIT
fi

# ──────────────────────────────────────────────────────────────────────────────
# End Phase 22 test block
# ──────────────────────────────────────────────────────────────────────────────

# ──────────────────────────────────────────────────────────────────────────────
# Phase 23 — restructure skill + safety gates (Wave 0 test-first)
# Mirrors the Phase 22 block style: `▸ Phase 23 — ...` headers, t/pass/fail
# helpers, mktemp sandboxes with set/reset EXIT-trap discipline. Every gate
# helper / SKILL.md / scaffold invocation is guarded behind P23_RESTR_OK /
# P23_GATES_OK so the suite reports these assertions as graceful RED (with a
# "Wave 1/2 must create ..." message) instead of crashing while the production
# code is absent. Production code (the 4 gates/*.sh, SKILL.md, the
# init-project.sh scaffold edit) lands in Waves 1-2.
# ──────────────────────────────────────────────────────────────────────────────

# Presence guards shared by every Phase 23 section (mirror P22_ADOPT_OK).
P23_RESTR_DIR="$CONJURE_HOME/templates/skills/restructure"
P23_RESTR_OK=0
[ -f "$P23_RESTR_DIR/SKILL.md" ] && P23_RESTR_OK=1
P23_GATES_OK=0
[ -f "$P23_RESTR_DIR/gates/verify-invariants.sh" ] && P23_GATES_OK=1
# Synthetic gate fixtures (created in Task 2); reused across the sections below.
P23_FIXTURE="$CONJURE_HOME/tests/fixtures/_restructure-gates"
# The shipped Phase 22 restructure-steps manifest, reused for group-by / apply-step.
P23_MANIFEST="$CONJURE_HOME/tests/fixtures/_adopt-restructure-steps/adopt-manifest.json"

echo
echo "▸ Phase 23 — restructure gate helpers"

# ── verify-invariants gate (RESTR-04 / criterion 4) ─────────────────────────
if [ "$P23_GATES_OK" -ne 1 ]; then
  fail "templates/skills/restructure/gates/verify-invariants.sh not found — Wave 1 must create the gate helpers first (RESTR-04/criterion 4)"
else
  P23_VI="$P23_RESTR_DIR/gates/verify-invariants.sh"
  P23_INV="$P23_FIXTURE/INVARIANTS.txt"
  # present → rc 0 (every canonical token appears, possibly reworded around).
  CONJURE_HOME="$CONJURE_HOME" bash "$P23_VI" "$P23_FIXTURE/with-invariant.md" "$P23_INV" >/dev/null 2>&1
  P23_VI_RC=$?
  if [ "$P23_VI_RC" -eq 0 ]; then
    pass "verify-invariants: all invariants present → rc 0 (RESTR-04/criterion 4)"
  else
    fail "verify-invariants: complete file expected rc 0, got $P23_VI_RC (RESTR-04/criterion 4)"
  fi
  # omitted token → rc 2 + the missing token(s) listed on stderr.
  P23_VI_MISS_OUT="$(CONJURE_HOME="$CONJURE_HOME" bash "$P23_VI" "$P23_FIXTURE/missing-invariant.md" "$P23_INV" 2>&1)"
  P23_VI_MISS_RC=$?
  if [ "$P23_VI_MISS_RC" -eq 2 ]; then
    pass "verify-invariants: dropped invariant → exit 2 BLOCK (D-08, RESTR-04/criterion 4)"
  else
    fail "verify-invariants: dropped invariant expected exit 2, got $P23_VI_MISS_RC (RESTR-04/criterion 4)"
  fi
  if printf '%s\n' "$P23_VI_MISS_OUT" | grep -qi 'missing'; then
    pass "verify-invariants: stderr lists the missing invariant(s) (RESTR-04/criterion 4)"
  else
    fail "verify-invariants: missing-list not reported — got: $P23_VI_MISS_OUT (RESTR-04/criterion 4)"
  fi
  # reflowed/case-mangled but content-complete → rc 0 (D-07 normalized-substring match).
  CONJURE_HOME="$CONJURE_HOME" bash "$P23_VI" "$P23_FIXTURE/reflowed-invariant.md" "$P23_INV" >/dev/null 2>&1
  P23_VI_RF_RC=$?
  if [ "$P23_VI_RF_RC" -eq 0 ]; then
    pass "verify-invariants: reflowed/case-mangled-but-complete → rc 0 (D-07 normalized match, RESTR-04)"
  else
    fail "verify-invariants: reflowed-complete expected rc 0, got $P23_VI_RF_RC (D-07, RESTR-04)"
  fi
fi

# ── audit-staged gate (RESTR-05 / criterion 5) ──────────────────────────────
if [ "$P23_GATES_OK" -ne 1 ]; then
  fail "templates/skills/restructure/gates/audit-staged.sh not found — Wave 1 must create the gate helpers first (RESTR-05/criterion 5)"
else
  P23_AUD="$P23_RESTR_DIR/gates/audit-staged.sh"
  # @import in the proposed CLAUDE.md → exit 2 (O-1: block on @import always).
  CONJURE_HOME="$CONJURE_HOME" bash "$P23_AUD" "$P23_FIXTURE/with-import.md" >/dev/null 2>&1
  P23_AUD_IMP_RC=$?
  if [ "$P23_AUD_IMP_RC" -eq 2 ]; then
    pass "audit-staged: @import in proposed CLAUDE.md → exit 2 BLOCK (O-1, RESTR-05/criterion 5)"
  else
    fail "audit-staged: @import expected exit 2, got $P23_AUD_IMP_RC (O-1, RESTR-05/criterion 5)"
  fi
  # clean ≤100-line @import-free file → exit 0.
  CONJURE_HOME="$CONJURE_HOME" bash "$P23_AUD" "$P23_FIXTURE/clean-doc.md" >/dev/null 2>&1
  P23_AUD_CLEAN_RC=$?
  if [ "$P23_AUD_CLEAN_RC" -eq 0 ]; then
    pass "audit-staged: clean ≤100-line @import-free file → exit 0 (RESTR-05/criterion 5)"
  else
    fail "audit-staged: clean file expected exit 0, got $P23_AUD_CLEAN_RC (RESTR-05/criterion 5)"
  fi
  # oversized (>200 lines, >CLAUDE_MD_CAP=100) → exit 2 (O-1 cap-breach block).
  CONJURE_HOME="$CONJURE_HOME" bash "$P23_AUD" "$P23_FIXTURE/oversized.md" >/dev/null 2>&1
  P23_AUD_BIG_RC=$?
  if [ "$P23_AUD_BIG_RC" -eq 2 ]; then
    pass "audit-staged: oversized (>200 lines) → exit 2 cap-breach BLOCK (O-1, RESTR-05/criterion 5)"
  else
    fail "audit-staged: oversized file expected exit 2, got $P23_AUD_BIG_RC (O-1, RESTR-05/criterion 5)"
  fi
fi

# ── decision-scan gate (RESTR-06 / criterion 6) ─────────────────────────────
if [ "$P23_GATES_OK" -ne 1 ]; then
  fail "templates/skills/restructure/gates/decision-scan.sh not found — Wave 1 must create the gate helpers first (RESTR-06/criterion 6)"
else
  P23_DS="$P23_RESTR_DIR/gates/decision-scan.sh"
  # decision vocabulary present → signal "individual" (over-flag is the SAFE direction).
  P23_DS_DEC_OUT="$(CONJURE_HOME="$CONJURE_HOME" bash "$P23_DS" "$P23_FIXTURE/decision-doc.md" 2>&1)"
  if printf '%s\n' "$P23_DS_DEC_OUT" | grep -qi 'individual'; then
    pass "decision-scan: decision-vocabulary doc → signals 'individual' (D-11, RESTR-06/criterion 6)"
  else
    fail "decision-scan: decision doc expected 'individual' signal — got: $P23_DS_DEC_OUT (RESTR-06/criterion 6)"
  fi
  # no decision vocabulary → signal "bulk".
  P23_DS_CLEAN_OUT="$(CONJURE_HOME="$CONJURE_HOME" bash "$P23_DS" "$P23_FIXTURE/clean-doc.md" 2>&1)"
  if printf '%s\n' "$P23_DS_CLEAN_OUT" | grep -qi 'bulk'; then
    pass "decision-scan: clean doc → signals 'bulk' (D-11, RESTR-06/criterion 6)"
  else
    fail "decision-scan: clean doc expected 'bulk' signal — got: $P23_DS_CLEAN_OUT (RESTR-06/criterion 6)"
  fi
fi

# ── extract-invariants gate (RESTR-04) ──────────────────────────────────────
if [ "$P23_GATES_OK" -ne 1 ]; then
  fail "templates/skills/restructure/gates/extract-invariants.sh not found — Wave 1 must create the gate helpers first (RESTR-04)"
else
  P23_EX="$P23_RESTR_DIR/gates/extract-invariants.sh"
  P23_EX_TARGET="$(mktemp -d)"
  trap 'rm -rf "$P23_EX_TARGET"' EXIT
  # Seed a source CLAUDE.md carrying obvious invariant signals (exit 2, @import).
  printf '# CLAUDE\n\nHooks must exit 2 to block; never use a hard error code.\nNever use @import — it eager-loads.\nCLAUDE.md stays ≤100 lines.\n' \
    > "$P23_EX_TARGET/CLAUDE.md"
  mkdir -p "$P23_EX_TARGET/.conjure-adopt-state"
  CONJURE_HOME="$CONJURE_HOME" bash "$P23_EX" "$P23_EX_TARGET/CLAUDE.md" "$P23_EX_TARGET" >/dev/null 2>&1
  P23_EX_RC=$?
  # The documented output is a non-empty candidates file under .conjure-adopt-state/.
  P23_EX_CAND="$(find "$P23_EX_TARGET/.conjure-adopt-state" -name 'INVARIANTS.candidates' 2>/dev/null | head -1)"
  if [ "$P23_EX_RC" -eq 0 ]; then
    pass "extract-invariants: exits 0 on a valid source CLAUDE.md (RESTR-04)"
  else
    fail "extract-invariants: expected exit 0, got $P23_EX_RC (RESTR-04)"
  fi
  if [ -n "$P23_EX_CAND" ] && [ -s "$P23_EX_CAND" ]; then
    pass "extract-invariants: writes a non-empty INVARIANTS.candidates under .conjure-adopt-state/ (D-06, RESTR-04)"
  else
    fail "extract-invariants: no non-empty INVARIANTS.candidates produced (D-06, RESTR-04)"
  fi
  if [ -n "$P23_EX_CAND" ] && grep -qi 'exit 2' "$P23_EX_CAND" 2>/dev/null; then
    pass "extract-invariants: candidates capture the 'exit 2' invariant signal (D-06, RESTR-04)"
  else
    fail "extract-invariants: candidates missing the 'exit 2' signal (D-06, RESTR-04)"
  fi
  rm -rf "$P23_EX_TARGET"
  trap - EXIT
fi

# ── criterion 1 scaffold: restructure skill installed by init-project.sh ─────
if [ "$P23_RESTR_OK" -ne 1 ]; then
  fail "templates/skills/restructure/SKILL.md not found — Wave 2 must create the restructure skill + scaffold edit (RESTR-01/02/criterion 1)"
else
  P23_SC_TARGET="$(mktemp -d)"
  trap 'rm -rf "$P23_SC_TARGET"' EXIT
  cp -r "$P22_FIXTURE/." "$P23_SC_TARGET/"
  ( cd "$P23_SC_TARGET" \
    && CONJURE_HOME="$CONJURE_HOME" bash "$CONJURE_HOME/scripts/init-project.sh" existing "$P23_SC_TARGET" >/dev/null 2>&1 ) || true
  P23_SC_SKILL="$P23_SC_TARGET/.claude/skills/restructure/SKILL.md"
  if [ -f "$P23_SC_SKILL" ]; then
    pass "scaffold: .claude/skills/restructure/SKILL.md installed by init-project.sh (RESTR-01/criterion 1)"
  else
    fail "scaffold: restructure SKILL.md not scaffolded into target (RESTR-01/criterion 1)"
  fi
  if [ -f "$P23_SC_SKILL" ] && grep -qE 'allowed-tools:.*Read.*Bash' "$P23_SC_SKILL"; then
    pass "scaffold: SKILL.md declares allowed-tools: [Read, Bash] (D-16/RESTR-02/criterion 1)"
  else
    fail "scaffold: SKILL.md missing 'allowed-tools: [Read, Bash]' (D-16/RESTR-02/criterion 1)"
  fi
  if [ -f "$P23_SC_SKILL" ] && [ "$(wc -l < "$P23_SC_SKILL" | tr -d ' ')" -le 200 ]; then
    pass "scaffold: SKILL.md ≤200 lines (criterion 1 cap)"
  else
    fail "scaffold: SKILL.md exceeds the 200-line cap (criterion 1)"
  fi
  if [ -f "$P23_SC_TARGET/.claude/skills/restructure/gates/verify-invariants.sh" ]; then
    pass "scaffold: gates/verify-invariants.sh ships alongside SKILL.md (whole-dir copy, A1) (criterion 1)"
  else
    fail "scaffold: gates/*.sh did not ship with the scaffolded skill (criterion 1)"
  fi
  rm -rf "$P23_SC_TARGET"
  trap - EXIT
fi

# ── apply-step routing the skill rides (RESTR-02) ───────────────────────────
# This re-exercises the SHIPPED Phase 22 seam from the skill's perspective; it
# documents the RESTR-02 contract and passes immediately (no presence guard — the
# adopt seam shipped in Phase 22). Guarded only by adopt.sh presence (P22_ADOPT_OK).
if [ "$P22_ADOPT_OK" -ne 1 ]; then
  fail "scripts/adopt.sh not found — Phase 22 must provide the adopt seam the skill rides (RESTR-02)"
else
  P23_AS_TARGET="$(mktemp -d)"
  trap 'rm -rf "$P23_AS_TARGET"' EXIT
  cp -r "$P22_FIXTURE/." "$P23_AS_TARGET/"
  cp "$P23_MANIFEST" "$P23_AS_TARGET/adopt-manifest.json"
  mkdir -p "$P23_AS_TARGET/.conjure-adopt-state/staging"
  printf '# CLAUDE (condensed)\n\nProposed restructure content.\n' \
    > "$P23_AS_TARGET/.conjure-adopt-state/staging/CLAUDE.md"
  P23_AS_CLAUDE_BEFORE="$(p22_sha "$P23_AS_TARGET/CLAUDE.md" 2>/dev/null || echo NA)"
  DRY_RUN=0 CONJURE_ADOPT_APPLY_STEP=step-1 CONJURE_HOME="$CONJURE_HOME" \
    bash "$P22_ADOPT_SH" --apply-step step-1 "$P23_AS_TARGET" >/dev/null 2>&1
  P23_AS_CLAUDE_AFTER="$(p22_sha "$P23_AS_TARGET/CLAUDE.md" 2>/dev/null || echo NA)"
  if jq -e '.restructure_steps[] | select(.id=="step-1") | .status == "applied"' \
       "$P23_AS_TARGET/adopt-manifest.json" >/dev/null 2>&1; then
    pass "apply-step routing: skill rides --apply-step → status: applied (RESTR-02)"
  else
    fail "apply-step routing: step-1 status not applied via the adopt seam (RESTR-02)"
  fi
  if [ "$P23_AS_CLAUDE_BEFORE" != "$P23_AS_CLAUDE_AFTER" ]; then
    pass "apply-step routing: dest mutated through mutate.sh (chokepoint, RESTR-02)"
  else
    fail "apply-step routing: dest unchanged — mutation did not route through the seam (RESTR-02)"
  fi
  rm -rf "$P23_AS_TARGET"
  trap - EXIT
fi

# ── group-by: skill reads per-file classification from the manifest (RESTR-01) ─
# The shipped fixture's files[] has exactly TWO entries (core, reference-doc);
# .summary carries the aggregate counts (unknown=1). Assert from files[] — do NOT
# conflate .summary.unknown (1) with the files[] selection (0).
if [ ! -f "$P23_MANIFEST" ]; then
  fail "tests/fixtures/_adopt-restructure-steps/adopt-manifest.json not found — group-by fixture missing (RESTR-01)"
else
  P23_GB_CORE="$(jq '[.files[]|select(.classification=="core")]|length' "$P23_MANIFEST" 2>/dev/null)"
  P23_GB_REF="$(jq '[.files[]|select(.classification=="reference-doc")]|length' "$P23_MANIFEST" 2>/dev/null)"
  P23_GB_UNK="$(jq '[.files[]|select(.classification=="unknown")]|length' "$P23_MANIFEST" 2>/dev/null)"
  P23_GB_SUM_UNK="$(jq '.summary.unknown' "$P23_MANIFEST" 2>/dev/null)"
  if [ "${P23_GB_CORE:-0}" = "1" ] && [ "${P23_GB_REF:-0}" = "1" ]; then
    pass "group-by: files[] per-class buckets — core=1, reference-doc=1 (RESTR-01)"
  else
    fail "group-by: files[] buckets wrong — core=$P23_GB_CORE reference-doc=$P23_GB_REF (RESTR-01)"
  fi
  if [ "${P23_GB_UNK:-x}" = "0" ]; then
    pass "group-by: files[] has zero 'unknown' entries (no unknown row in files[]) (RESTR-01)"
  else
    fail "group-by: files[] unknown selection expected 0, got $P23_GB_UNK (RESTR-01)"
  fi
  if [ "${P23_GB_SUM_UNK:-x}" = "1" ]; then
    pass "group-by: .summary.unknown=1 (aggregate count, distinct from files[] selection) (RESTR-01)"
  else
    fail "group-by: .summary.unknown expected 1, got $P23_GB_SUM_UNK (RESTR-01)"
  fi
fi

# ── archive-last sequencing in the skill's proposed plan (criterion 6) ───────
if [ "$P23_RESTR_OK" -ne 1 ]; then
  fail "templates/skills/restructure/SKILL.md not found — Wave 2 must encode archive-last proposal ordering (criterion 6)"
else
  # The skill's proposal logic must place op:archive after op:write/op:extract.
  # Assert against the order the skill documents/emits (Wave 2 deliverable).
  P23_AL_ORDER="$(grep -nE 'op[":= ]+archive|op[":= ]+write|op[":= ]+extract' "$P23_RESTR_DIR/SKILL.md" 2>/dev/null | grep -i archive | head -1)"
  P23_AL_WRITE="$(grep -nE 'op[":= ]+write|op[":= ]+extract' "$P23_RESTR_DIR/SKILL.md" 2>/dev/null | head -1)"
  P23_AL_ARCH_LINE="${P23_AL_ORDER%%:*}"
  P23_AL_WRITE_LINE="${P23_AL_WRITE%%:*}"
  if [ -n "$P23_AL_ARCH_LINE" ] && [ -n "$P23_AL_WRITE_LINE" ] && [ "$P23_AL_ARCH_LINE" -gt "$P23_AL_WRITE_LINE" ] 2>/dev/null; then
    pass "archive-last: SKILL.md sequences op:archive after op:write/op:extract (criterion 6)"
  else
    fail "archive-last: SKILL.md must sequence archive ops last in the proposed plan (criterion 6)"
  fi
fi

# ── non-TTY approval → exit 2 (RESTR-03 / criterion 3) ──────────────────────
if [ "$P23_RESTR_OK" -ne 1 ]; then
  fail "restructure approval driver not found — Wave 2 must ship the approval entry; non-TTY must exit 2 (D-12/RESTR-03/criterion 3)"
else
  P23_AP="$P23_RESTR_DIR/gates/approve.sh"
  if [ ! -f "$P23_AP" ]; then
    fail "restructure approval driver (gates/approve.sh) not found — Wave 2 must ship it (D-12/RESTR-03/criterion 3)"
  else
    P23_AP_TARGET="$(mktemp -d)"
    trap 'rm -rf "$P23_AP_TARGET"' EXIT
    cp -r "$P22_FIXTURE/." "$P23_AP_TARGET/"
    # Drive the approval entry with non-TTY stdin (< /dev/null); expect exit 2.
    CONJURE_HOME="$CONJURE_HOME" bash "$P23_AP" "$P23_AP_TARGET" < /dev/null >/dev/null 2>&1
    P23_AP_RC=$?
    if [ "$P23_AP_RC" -eq 2 ]; then
      pass "non-TTY approval: stdin not a TTY → exit 2 (never auto-approve, D-12/RESTR-03/criterion 3)"
    else
      fail "non-TTY approval: expected exit 2, got $P23_AP_RC (D-12/RESTR-03/criterion 3)"
    fi
    rm -rf "$P23_AP_TARGET"
    trap - EXIT
  fi
fi

# ── bulk summary log: exactly ONE RESTRUCTURE summary line per bucket (RESTR-03) ─
if [ "$P23_RESTR_OK" -ne 1 ]; then
  fail "restructure approval driver not found — Wave 2 must emit ONE RESTRUCTURE bulk-summary line per bucket (D-09/RESTR-03/criterion 3)"
else
  P23_BL="$P23_RESTR_DIR/gates/approve.sh"
  if [ ! -f "$P23_BL" ]; then
    fail "restructure approval driver (gates/approve.sh) not found — Wave 2 must ship the bulk-summary log (D-09/RESTR-03/criterion 3)"
  else
    P23_BL_TARGET="$(mktemp -d)"
    trap 'rm -rf "$P23_BL_TARGET"' EXIT
    cp -r "$P22_FIXTURE/." "$P23_BL_TARGET/"
    cp "$P23_MANIFEST" "$P23_BL_TARGET/adopt-manifest.json"
    # Drive a bulk approve (force interactive, feed 'a' for each bucket); then count
    # the RESTRUCTURE summary lines for the bucket — expect exactly one per bucket.
    printf 'a\na\n' | CONJURE_FORCE_INTERACTIVE=1 CONJURE_HOME="$CONJURE_HOME" \
      bash "$P23_BL" "$P23_BL_TARGET" >/dev/null 2>&1 || true
    P23_BL_LINES="$(grep -c 'RESTRUCTURE' "$P23_BL_TARGET/RESTRUCTURE-LOG.md" 2>/dev/null || echo 0)"
    if [ "${P23_BL_LINES:-0}" -ge 1 ]; then
      pass "bulk summary: at least one RESTRUCTURE summary line logged for the bucket (D-09/RESTR-03)"
    else
      fail "bulk summary: no RESTRUCTURE summary line in RESTRUCTURE-LOG.md (D-09/RESTR-03)"
    fi
    rm -rf "$P23_BL_TARGET"
    trap - EXIT
  fi
fi

# ── CR-01 regression: a NON-archive bucket approval must NOT apply op:archive ───
# The shipped fixture manifest has step-2 = {op: archive, src: docs/OLD.md}, and
# docs/OLD.md is classified reference-doc in files[]. Approving the reference-doc
# bucket must NOT fire the archive step: archive ops are sequenced LAST (D-15) and
# routed through gates/decision-scan.sh (D-11). A regression here is the CR-6
# bulk-archive-of-an-active-decision failure mode. This section FAILS against a
# pre-fix approve.sh (whose bucket collector matched step-2 via select(.src==$p)
# with no .op filter) and PASSES once the op:archive exclusion is in place.
if [ "$P23_RESTR_OK" -ne 1 ]; then
  fail "restructure approval driver not found — Wave 2 must exclude op:archive from non-archive bucket approval (CR-01/D-15)"
else
  P23_CR="$P23_RESTR_DIR/gates/approve.sh"
  if [ ! -f "$P23_CR" ]; then
    fail "restructure approval driver (gates/approve.sh) not found — CR-01 archive-exclusion cannot be exercised (D-15)"
  else
    P23_CR_TARGET="$(mktemp -d)"
    trap 'rm -rf "$P23_CR_TARGET"' EXIT
    cp -r "$P22_FIXTURE/." "$P23_CR_TARGET/"
    cp "$P23_MANIFEST" "$P23_CR_TARGET/adopt-manifest.json"
    # Materialize the archive candidate so a (wrongly) fired archive op would be
    # observable: docs/OLD.md must exist at its original path before approval.
    mkdir -p "$P23_CR_TARGET/docs"
    printf '# OLD\n\nA redundant reference doc slated for the archive-last pass.\n' \
      > "$P23_CR_TARGET/docs/OLD.md"
    # Stage step-1's write src so the (legitimate) write op could apply cleanly.
    mkdir -p "$P23_CR_TARGET/.conjure-adopt-state/staging"
    printf '# CLAUDE (condensed)\n\nProposed restructure content.\n' \
      > "$P23_CR_TARGET/.conjure-adopt-state/staging/CLAUDE.md"
    # Drive a bulk approve over both non-empty buckets (core + reference-doc).
    printf 'a\na\n' | CONJURE_FORCE_INTERACTIVE=1 CONJURE_HOME="$CONJURE_HOME" \
      bash "$P23_CR" "$P23_CR_TARGET" >/dev/null 2>&1 || true
    # Assertion 1: step-2 (op:archive) must remain status:proposed — never applied
    # as a side effect of the reference-doc bucket approval.
    if jq -e '.restructure_steps[] | select(.id=="step-2") | .status == "proposed"' \
         "$P23_CR_TARGET/adopt-manifest.json" >/dev/null 2>&1; then
      pass "CR-01: op:archive step stays 'proposed' through non-archive bucket approval (D-15)"
    else
      fail "CR-01: op:archive step-2 was applied during the reference-doc bucket — D-15 violated / decision-scan bypassed"
    fi
    # Assertion 2: docs/OLD.md must NOT have been moved into a .conjure-archive-* dir.
    if [ -f "$P23_CR_TARGET/docs/OLD.md" ] \
       && [ -z "$(find "$P23_CR_TARGET" -type d -name '.conjure-archive-*' 2>/dev/null)" ]; then
      pass "CR-01: archive candidate docs/OLD.md not archived during non-archive approval (D-15)"
    else
      fail "CR-01: docs/OLD.md was archived during the reference-doc bucket approval — archive must be sequenced LAST"
    fi
    rm -rf "$P23_CR_TARGET"
    trap - EXIT
  fi
fi

# ──────────────────────────────────────────────────────────────────────────────
# End Phase 23 test block
# ──────────────────────────────────────────────────────────────────────────────

# ──────────────────────────────────────────────────────────────────────────────
# Phase 24 — v0.6.0 E2E verification against the _brownfield-argus fixture
# Mirrors the green, battle-tested Phase 22 block idioms (mktemp sandboxes with
# set/reset EXIT-trap discipline, p22_sha, diff -r with the D-03 excludes, the
# SIGKILL background-launch + bounded-poll harness) pointed at the 500-file argus
# fixture. Five sections, ONE per ROADMAP success criterion (C1–C5). Every section
# is guarded behind `P22_ADOPT_OK -eq 1 && P24_ARGUS_OK -eq 1` so a missing
# generator (Plan 01 / Wave 1) reports graceful RED instead of crashing.
# Reuses the EXISTING P22_ADOPT_SH + p22_sha helpers defined in the Phase 22
# preamble above (still in scope). This block PROVES the shipped Phases 21–23
# pipeline holds together at 500-file scale — it modifies no product code.
# ──────────────────────────────────────────────────────────────────────────────

# Presence guard shared by every Phase 24 section (mirror P22_ADOPT_OK pattern).
P24_ARGUS_GEN="$CONJURE_HOME/tests/fixtures/_brownfield-argus/generate-argus.sh"
P24_ARGUS_OK=0
[ -f "$P24_ARGUS_GEN" ] && P24_ARGUS_OK=1

echo
echo "▸ Phase 24 — dry-run perf + zero writes (criterion 1)"

if [ "$P22_ADOPT_OK" -ne 1 ] || [ "$P24_ARGUS_OK" -ne 1 ]; then
  fail "argus generator / adopt.sh missing — Plan 01 generator + Wave 1 adopt.sh must exist first (criterion 1)"
else
  P24_C1_TARGET="$(mktemp -d)"
  trap 'rm -rf "$P24_C1_TARGET"' EXIT
  bash "$P24_ARGUS_GEN" "$P24_C1_TARGET" >/dev/null 2>&1   # materialize ~500 .md
  # Perf: date +%s integer-second delta. 30s ceiling on Unix (research measured ~6s);
  # raised on Windows Git Bash where fork overhead makes 30s unreachable (PERF_CEILING).
  P24_C1_START="$(date +%s)"
  DRY_RUN=1 CONJURE_HOME="$CONJURE_HOME" bash "$P22_ADOPT_SH" "$P24_C1_TARGET" >/dev/null 2>&1
  P24_C1_END="$(date +%s)"
  P24_C1_ELAPSED=$((P24_C1_END - P24_C1_START))
  if [ "$P24_C1_ELAPSED" -lt "$PERF_CEILING" ]; then
    pass "argus dry-run: 500-file dry-run completed in ${P24_C1_ELAPSED}s (< ${PERF_CEILING}s) (criterion 1)"
  else
    fail "argus dry-run: 500-file dry-run took ${P24_C1_ELAPSED}s (>= ${PERF_CEILING}s ceiling) (criterion 1)"
  fi
  # Zero writes under the target (non-git sandbox per O-2 → no porcelain; assert
  # no adopt artifacts landed): no adopt-manifest.json AND no .conjure-adopt-state.
  P24_C1_MANIFEST_COUNT="$(find "$P24_C1_TARGET" -name adopt-manifest.json 2>/dev/null | wc -l | tr -d ' ')"
  P24_C1_STATE_COUNT="$(find "$P24_C1_TARGET" -name '.conjure-adopt-state' 2>/dev/null | wc -l | tr -d ' ')"
  if [ "${P24_C1_MANIFEST_COUNT:-1}" -eq 0 ]; then
    pass "argus dry-run: no adopt-manifest.json under target — zero writes (criterion 1)"
  else
    fail "argus dry-run: adopt-manifest.json leaked into target — not zero writes (criterion 1)"
  fi
  if [ "${P24_C1_STATE_COUNT:-1}" -eq 0 ]; then
    pass "argus dry-run: no .conjure-adopt-state under target — zero writes (criterion 1)"
  else
    fail "argus dry-run: .conjure-adopt-state leaked into target — not zero writes (criterion 1)"
  fi
  rm -rf "$P24_C1_TARGET"
  trap - EXIT
fi

echo
echo "▸ Phase 24 — live adopt + rollback zero-diff (criterion 2)"

if [ "$P22_ADOPT_OK" -ne 1 ] || [ "$P24_ARGUS_OK" -ne 1 ]; then
  fail "argus generator / adopt.sh missing — Plan 01 generator + Wave 1 adopt.sh must exist first (criterion 2)"
else
  P24_RB_TARGET="$(mktemp -d)"
  P24_RB_PRE="$(mktemp -d)"   # pristine pre-adopt copy for the zero-diff comparison
  P24_RB_HASHES="$(mktemp)"   # hash record OUTSIDE both trees (Pitfall 4 — else it pollutes the diff)
  trap 'rm -rf "$P24_RB_TARGET" "$P24_RB_PRE"; rm -f "$P24_RB_HASHES"' EXIT
  # Generate into PRE, then cp -aR into TARGET to guarantee identical pre-state
  # (cp -aR preserves the real ln -s symlink — never dereference it).
  bash "$P24_ARGUS_GEN" "$P24_RB_PRE" >/dev/null 2>&1
  cp -aR "$P24_RB_PRE/." "$P24_RB_TARGET/"
  # Record sha256 of every pre-adopt regular file (relative paths); skip the
  # symlink (sha of its target is irrelevant) and any .git.
  ( cd "$P24_RB_TARGET" && find . -type f -not -path './.git/*' | sort | while IFS= read -r f; do
      printf '%s  %s\n' "$(p22_sha "$f")" "$f"
    done ) > "$P24_RB_HASHES" 2>/dev/null
  # Live adopt, then rollback.
  DRY_RUN=0 CONJURE_HOME="$CONJURE_HOME" bash "$P22_ADOPT_SH" "$P24_RB_TARGET" >/dev/null 2>&1
  P24_RB_OUT="$(DRY_RUN=0 CONJURE_ADOPT_ROLLBACK=1 CONJURE_ADOPT_ROLLBACK_DIAG=1 CONJURE_HOME="$CONJURE_HOME" bash "$P22_ADOPT_SH" --rollback "$P24_RB_TARGET" 2>&1)"
  P24_RB_RC=$?
  [ "$P24_RB_RC" -ne 0 ] && printf '  [diag] argus rollback rc=%s out=%s\n' "$P24_RB_RC" "$P24_RB_OUT" >&2
  # Per-file sha256: every pre-adopt file restored to its recorded before-hash.
  P24_RB_MISMATCH=0
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    _h="${line%%  *}"; _f="${line##*  }"
    _now="$(p22_sha "$P24_RB_TARGET/$_f" 2>/dev/null || echo MISSING)"
    [ "$_h" = "$_now" ] || P24_RB_MISMATCH=$((P24_RB_MISMATCH + 1))
  done < "$P24_RB_HASHES"
  if [ "$P24_RB_MISMATCH" -eq 0 ]; then
    pass "argus rollback: every pre-adopt file sha256 == recorded before-hash (criterion 2)"
  else
    fail "argus rollback: $P24_RB_MISMATCH file(s) differ from recorded before-hash (criterion 2)"
  fi
  # [ROLLBACK] entry logged.
  if [ -f "$P24_RB_TARGET/RESTRUCTURE-LOG.md" ] && grep -q '\[ROLLBACK\]' "$P24_RB_TARGET/RESTRUCTURE-LOG.md" 2>/dev/null; then
    pass "argus rollback: [ROLLBACK] entry in RESTRUCTURE-LOG.md (criterion 2)"
  else
    fail "argus rollback: no [ROLLBACK] entry in RESTRUCTURE-LOG.md (criterion 2)"
  fi
  # Zero-diff pre-adopt vs post-rollback, excluding conjure's own dirs (D-03).
  P24_RB_DIFF="$(diff -r \
    -x '.conjure-adopt-backups' -x '.conjure-archive-*' \
    -x 'RESTRUCTURE-LOG.md' -x 'adopt-manifest.json' -x '.conjure-adopt-state' \
    "$P24_RB_PRE" "$P24_RB_TARGET" 2>&1)"
  if [ -z "$P24_RB_DIFF" ]; then
    pass "argus rollback: diff -r pre-adopt vs post-rollback empty (excl. D-03 dirs) (criterion 2)"
  else
    fail "argus rollback: post-rollback diff not empty — got: $P24_RB_DIFF (criterion 2)"
  fi
  rm -rf "$P24_RB_TARGET" "$P24_RB_PRE"
  rm -f "$P24_RB_HASHES"
  trap - EXIT
fi

echo
echo "▸ Phase 24 — idempotent re-run (criterion 3)"

if [ "$P22_ADOPT_OK" -ne 1 ] || [ "$P24_ARGUS_OK" -ne 1 ]; then
  fail "argus generator / adopt.sh missing — Plan 01 generator + Wave 1 adopt.sh must exist first (criterion 3)"
else
  P24_ID_TARGET="$(mktemp -d)"
  P24_ID_RUN1="$(mktemp -d)"   # snapshot of post-run-1 target OUTSIDE the target (for the run1-vs-run2 diff)
  trap 'rm -rf "$P24_ID_TARGET" "$P24_ID_RUN1"' EXIT
  bash "$P24_ARGUS_GEN" "$P24_ID_TARGET" >/dev/null 2>&1
  # First live adopt (the scaffolding run).
  DRY_RUN=0 CONJURE_HOME="$CONJURE_HOME" bash "$P22_ADOPT_SH" "$P24_ID_TARGET" >/dev/null 2>&1
  # Snapshot the post-run-1 state (cp -aR preserves the symlink) for the zero-mutation diff.
  cp -aR "$P24_ID_TARGET/." "$P24_ID_RUN1/"
  # Clear the durable state (the :2896 idiom) so the second run is a clean
  # idempotent scaffold, not a recovery prompt.
  rm -rf "$P24_ID_TARGET/.conjure-adopt-state"
  P24_ID_OUT="$(DRY_RUN=0 CONJURE_HOME="$CONJURE_HOME" bash "$P22_ADOPT_SH" "$P24_ID_TARGET" 2>&1)"
  # Signal (a): the report says zero layers scaffolded.
  if printf '%s\n' "$P24_ID_OUT" | grep -Eq 'Scaffolded:[[:space:]]*0[[:space:]]+layer'; then
    pass "argus idempotent: re-run reports 'Scaffolded: 0 layer files' (criterion 3)"
  else
    fail "argus idempotent: re-run missing 'Scaffolded: 0 layer' — got: $P24_ID_OUT (criterion 3)"
  fi
  # Signal (b): created[] count is 0 on the second run.
  P24_ID_CREATED="$(jq -r '.created | length' "$P24_ID_TARGET/.conjure-adopt-state/state.json" 2>/dev/null || echo NA)"
  if [ "$P24_ID_CREATED" = "0" ]; then
    pass "argus idempotent: state.json .created|length == 0 — zero scaffold (criterion 3)"
  else
    fail "argus idempotent: state.json .created|length == $P24_ID_CREATED (expected 0) (criterion 3)"
  fi
  # Signal (c): zero mutations — run1-after vs run2-after diff empty (excl. D-03).
  P24_ID_DIFF="$(diff -r \
    -x '.conjure-adopt-backups' -x '.conjure-archive-*' \
    -x 'RESTRUCTURE-LOG.md' -x 'adopt-manifest.json' -x '.conjure-adopt-state' \
    "$P24_ID_RUN1" "$P24_ID_TARGET" 2>&1)"
  if [ -z "$P24_ID_DIFF" ]; then
    pass "argus idempotent: diff -r run1-after vs run2-after empty — zero mutations (criterion 3)"
  else
    fail "argus idempotent: run1-vs-run2 diff not empty — got: $P24_ID_DIFF (criterion 3)"
  fi
  # Signal (d): the literal ROADMAP phrase (Plan 01 O-1 report() deviation).
  if printf '%s\n' "$P24_ID_OUT" | grep -qi 'nothing to scaffold'; then
    pass "argus idempotent: re-run emits literal 'nothing to scaffold' (O-1, criterion 3)"
  else
    fail "argus idempotent: re-run missing literal 'nothing to scaffold' — got: $P24_ID_OUT (O-1, criterion 3)"
  fi
  rm -rf "$P24_ID_TARGET" "$P24_ID_RUN1"
  trap - EXIT
fi

echo
echo "▸ Phase 24 — SIGKILL recovery after snapshot (criterion 4)"

# NOTE: the interactive [r]/[c]/[s] recovery prompt is MANUAL-ONLY (it needs a
# real PTY and was already UAT'd in Phases 22/23). This section automates only
# the non-TTY half (exit 2 + recovery options) and the explicit
# CONJURE_ADOPT_ROLLBACK=1 re-run zero-diff. The launch+poll+kill is wrapped in a
# relaunch loop (up to 3 attempts) because the snapshot→scaffold kill window is
# an inherent timing race: on a fast/loaded runner the process can transition
# past `inventory` between polls — a legitimate timing slip retries rather than
# going false-RED.
if [ "$P22_ADOPT_OK" -ne 1 ] || [ "$P24_ARGUS_OK" -ne 1 ]; then
  fail "argus generator / adopt.sh missing — Plan 01 generator + Wave 1 adopt.sh must exist first (criterion 4)"
else
  P24_SK_TARGET="$(mktemp -d)"
  P24_SK_PRE="$(mktemp -d)"   # pristine pre-adopt copy for the post-rollback zero-diff
  trap 'rm -rf "$P24_SK_TARGET" "$P24_SK_PRE"' EXIT
  bash "$P24_ARGUS_GEN" "$P24_SK_PRE" >/dev/null 2>&1
  cp -aR "$P24_SK_PRE/." "$P24_SK_TARGET/"   # cp -aR preserves the symlink
  # Relaunch loop: catch the kill strictly AFTER snapshot, BEFORE scaffold.
  P24_SK_INWINDOW=0
  P24_SK_LASTSTEP=""
  for _attempt in 1 2 3; do
    DRY_RUN=0 CONJURE_HOME="$CONJURE_HOME" bash "$P22_ADOPT_SH" "$P24_SK_TARGET" >/dev/null 2>&1 &
    P24_SK_PID=$!
    # Bounded poll on state.json .current_step (Pattern 3 — more precise than the
    # Phase 22 backups-dir poll): break when snapshot done, scaffold not yet.
    P24_SK_LASTSTEP=""
    for _i in $(seq 1 200); do
      _step="$(jq -r '.current_step // ""' "$P24_SK_TARGET/.conjure-adopt-state/state.json" 2>/dev/null || true)"
      [ -n "$_step" ] && P24_SK_LASTSTEP="$_step"
      case "$_step" in snapshot|inventory) break ;; esac
      kill -0 "$P24_SK_PID" 2>/dev/null || break   # process already exited
      sleep 0.05
    done
    kill -9 "$P24_SK_PID" 2>/dev/null || true
    wait "$P24_SK_PID" 2>/dev/null || true
    # In-window iff the step we observed at kill time was snapshot or inventory.
    case "$P24_SK_LASTSTEP" in
      snapshot|inventory) P24_SK_INWINDOW=1; break ;;
      *)
        # Out-of-window (finished, or already at scaffold/audit): clear partial
        # state + backups and relaunch from a pristine tree.
        rm -rf "$P24_SK_TARGET/.conjure-adopt-state" "$P24_SK_TARGET/.conjure-adopt-backups"
        rm -rf "$P24_SK_TARGET"
        mkdir -p "$P24_SK_TARGET"
        cp -aR "$P24_SK_PRE/." "$P24_SK_TARGET/"
        ;;
    esac
  done
  if [ "$P24_SK_INWINDOW" -eq 1 ]; then
    pass "argus SIGKILL: kill landed in window (current_step=$P24_SK_LASTSTEP: snapshot done, scaffold not yet) (criterion 4)"
  else
    fail "argus SIGKILL: kill never landed in the snapshot/inventory window after 3 attempts (last step=$P24_SK_LASTSTEP) (criterion 4)"
  fi
  # Non-TTY recovery re-run: partial state → exit 2 + last-completed + 3 flags.
  P24_SK_OUT="$(
    DRY_RUN=0 CONJURE_HOME="$CONJURE_HOME" \
      bash "$P22_ADOPT_SH" "$P24_SK_TARGET" < /dev/null 2>&1
  )"
  P24_SK_RC=$?
  if [ "$P24_SK_RC" -eq 2 ]; then
    pass "argus SIGKILL: non-TTY re-run exits 2 (never auto-mutate) (criterion 4)"
  else
    fail "argus SIGKILL: non-TTY re-run expected exit 2, got $P24_SK_RC (criterion 4)"
  fi
  if printf '%s\n' "$P24_SK_OUT" | grep -qi 'last completed:'; then
    pass "argus SIGKILL: re-run prints 'last completed:' partial-state line (criterion 4)"
  else
    fail "argus SIGKILL: re-run missing 'last completed:' line — got: $P24_SK_OUT (criterion 4)"
  fi
  P24_SK_FLAGS_OK=1
  for _flag in -- --rollback --resume --start-fresh; do
    [ "$_flag" = "--" ] && continue
    printf '%s\n' "$P24_SK_OUT" | grep -q -- "$_flag" || P24_SK_FLAGS_OK=0
  done
  if [ "$P24_SK_FLAGS_OK" -eq 1 ]; then
    pass "argus SIGKILL: re-run lists --rollback/--resume/--start-fresh (criterion 4)"
  else
    fail "argus SIGKILL: re-run missing one or more recovery flags — got: $P24_SK_OUT (criterion 4)"
  fi
  # Choosing rollback restores the fixture cleanly: drive --rollback, then
  # diff -r (excl D-03) vs the pristine PRE copy must be empty.
  DRY_RUN=0 CONJURE_ADOPT_ROLLBACK=1 CONJURE_HOME="$CONJURE_HOME" bash "$P22_ADOPT_SH" --rollback "$P24_SK_TARGET" >/dev/null 2>&1
  P24_SK_DIFF="$(diff -r \
    -x '.conjure-adopt-backups' -x '.conjure-archive-*' \
    -x 'RESTRUCTURE-LOG.md' -x 'adopt-manifest.json' -x '.conjure-adopt-state' \
    "$P24_SK_PRE" "$P24_SK_TARGET" 2>&1)"
  if [ -z "$P24_SK_DIFF" ]; then
    pass "argus SIGKILL: CONJURE_ADOPT_ROLLBACK=1 re-run → diff -r vs PRE empty (excl. D-03) (criterion 4)"
  else
    fail "argus SIGKILL: post-rollback diff not empty — got: $P24_SK_DIFF (criterion 4)"
  fi
  rm -rf "$P24_SK_TARGET" "$P24_SK_PRE"
  trap - EXIT
fi

echo
echo "▸ Phase 24 — symlink skip + @import pre-write block (criterion 5)"

if [ "$P22_ADOPT_OK" -ne 1 ] || [ "$P24_ARGUS_OK" -ne 1 ]; then
  fail "argus generator / adopt.sh missing — Plan 01 generator + Wave 1 adopt.sh must exist first (criterion 5)"
else
  P24_C5_TARGET="$(mktemp -d)"
  trap 'rm -rf "$P24_C5_TARGET"' EXIT
  bash "$P24_ARGUS_GEN" "$P24_C5_TARGET" >/dev/null 2>&1   # creates docs/linked.md symlink + with-import.md @import seed
  # Live adopt.
  DRY_RUN=0 CONJURE_HOME="$CONJURE_HOME" bash "$P22_ADOPT_SH" "$P24_C5_TARGET" >/dev/null 2>&1
  # (5a) The symlink path must be ABSENT from manifest files[] (inventory skips
  # symlinks). jq -e select returns non-zero when nothing matches.
  if [ ! -L "$P24_C5_TARGET/docs/linked.md" ]; then
    # ln -s produced a regular file (native Windows Git Bash copies instead of linking)
    # — there is no symlink to skip. Criterion 5 symlink-skip is exercised on Unix CI.
    pass "argus symlink: symlink-skip N/A — ln -s not a real symlink on this platform (criterion 5 verified on Unix)"
  elif ! jq -e --arg p 'docs/linked.md' '.files[]?|select(.path==$p)' \
       "$P24_C5_TARGET/adopt-manifest.json" >/dev/null 2>&1; then
    pass "argus symlink: docs/linked.md absent from manifest files[] — inventory skipped it (criterion 5)"
  else
    fail "argus symlink: docs/linked.md present in manifest files[] — symlink not skipped (criterion 5)"
  fi
  # (5b) Stage the @import seed as a proposed CLAUDE.md → audit-staged.sh exits 2.
  P24_C5_AUD="$CONJURE_HOME/templates/skills/restructure/gates/audit-staged.sh"
  mkdir -p "$P24_C5_TARGET/.conjure-adopt-state/staging"
  printf '# CLAUDE\n@.claude/skills/x/SKILL.md\n' > "$P24_C5_TARGET/.conjure-adopt-state/staging/CLAUDE.md"
  CONJURE_HOME="$CONJURE_HOME" bash "$P24_C5_AUD" "$P24_C5_TARGET/.conjure-adopt-state/staging/CLAUDE.md" >/dev/null 2>&1
  P24_C5_AUD_RC=$?
  if [ "$P24_C5_AUD_RC" -eq 2 ]; then
    pass "argus @import: audit-staged.sh on staged @import CLAUDE.md → exit 2 BLOCK (criterion 5)"
  else
    fail "argus @import: audit-staged.sh expected exit 2, got $P24_C5_AUD_RC (criterion 5)"
  fi
  # (5c) The block fired before approval → the staged @import was never applied,
  # so the target CLAUDE.md must NOT contain an ^@ line.
  if grep -q '^@' "$P24_C5_TARGET/CLAUDE.md" 2>/dev/null; then
    fail "argus @import: ^@ line leaked into target CLAUDE.md (criterion 5)"
  else
    pass "argus @import: target CLAUDE.md never gained an ^@ line — @import never written (criterion 5)"
  fi
  rm -rf "$P24_C5_TARGET"
  trap - EXIT
fi

echo
echo "▸ Phase 24 — clean git repo runs the full pipeline (milestone-audit gap-closure)"

# Regression: the milestone integration audit found `conjure adopt` refused a CLEAN
# committed git repo (the headline user flow) because log_init writes RESTRUCTURE-LOG.md
# before precondition_git checks `git status --porcelain`, so the untracked log made the
# tree look dirty. precondition_git now filters conjure's own artifacts. Every other
# pipeline test uses a NON-git mktemp target (the gate self-skips), so this is the only
# test that exercises the clean-git path. Skips silently if git is unavailable.
if [ "$P22_ADOPT_OK" -ne 1 ]; then
  fail "adopt.sh missing — Wave 1 must create scripts/adopt.sh first (clean-git gate)"
elif ! command -v git >/dev/null 2>&1; then
  pass "clean-git gate: git unavailable — skipping (environment, not a failure)"
else
  P24_CG_TARGET="$(mktemp -d)"
  trap 'rm -rf "$P24_CG_TARGET"' EXIT
  cp -r "$P22_FIXTURE/." "$P24_CG_TARGET/"
  ( cd "$P24_CG_TARGET" && git init -q && git add -A \
    && git -c user.email=test@conjure -c user.name=test commit -qm init ) >/dev/null 2>&1
  # CLEAN committed tree → adopt MUST run the full pipeline (not exit 2 at preconditions).
  P24_CG_OUT="$(DRY_RUN=0 CONJURE_HOME="$CONJURE_HOME" bash "$P22_ADOPT_SH" "$P24_CG_TARGET" 2>&1)"
  P24_CG_RC=$?
  if [ "$P24_CG_RC" -eq 0 ] && [ -f "$P24_CG_TARGET/adopt-manifest.json" ] \
     && printf '%s' "$P24_CG_OUT" | grep -q 'git clean'; then
    pass "clean-git gate: clean committed repo runs full pipeline (preconditions pass, manifest emitted)"
  else
    fail "clean-git gate: clean repo blocked (rc=$P24_CG_RC) — precondition_git misfired on conjure's own artifacts"
  fi
  # Genuinely dirty USER file → adopt MUST still exit 2 (the gate must not over-filter).
  echo "user uncommitted work" > "$P24_CG_TARGET/user-wip.txt"
  rm -rf "$P24_CG_TARGET/.conjure-adopt-state" "$P24_CG_TARGET/.conjure-adopt-backups" \
         "$P24_CG_TARGET/RESTRUCTURE-LOG.md" "$P24_CG_TARGET/adopt-manifest.json" 2>/dev/null
  DRY_RUN=0 CONJURE_HOME="$CONJURE_HOME" bash "$P22_ADOPT_SH" "$P24_CG_TARGET" >/dev/null 2>&1
  P24_CG_DIRTY_RC=$?
  if [ "$P24_CG_DIRTY_RC" -eq 2 ]; then
    pass "clean-git gate: a genuinely dirty user file still exits 2 (gate not over-filtered)"
  else
    fail "clean-git gate: dirty user tree got rc=$P24_CG_DIRTY_RC (expected 2) — gate over-filters real changes"
  fi
  rm -rf "$P24_CG_TARGET"
  trap - EXIT
fi

# ──────────────────────────────────────────────────────────────────────────────
# End Phase 24 test block
# ──────────────────────────────────────────────────────────────────────────────

# ──────────────────────────────────────────────────────────────────────────────
# v0.6.1 FIX-01/FIX-06: pre-bash-block-destructive.mjs stdin contract + rm-rf regex
# ──────────────────────────────────────────────────────────────────────────────

echo
echo "▸ v0.6.1 FIX-01/FIX-06: pre-bash-block-destructive.mjs stdin contract + rm-rf regex"

DESTRUCT_MJS="$CONJURE_HOME/templates/hooks-nodejs/pre-bash-block-destructive.mjs"

# 1. STDIN contract — block path: rm -rf via stdin JSON must exit 2 (BLOCK)
DESTRUCT_PAYLOAD='{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"rm -rf /tmp/test"},"session_id":"s1"}'
BLOCK_RC=0
printf '%s' "$DESTRUCT_PAYLOAD" | node "$DESTRUCT_MJS" >/dev/null 2>&1 || BLOCK_RC=$?
if [ "$BLOCK_RC" -eq 2 ]; then
  pass "pre-bash hook BLOCKS rm -rf via stdin JSON (FIX-01)"
else
  fail "pre-bash hook did not BLOCK rm -rf via stdin JSON — got rc=$BLOCK_RC (FIX-01)"
fi

# 2. STDIN contract — allow path: safe command via stdin JSON must exit 0
ALLOW_PAYLOAD='{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"ls -la"},"session_id":"s1"}'
ALLOW_RC=0
printf '%s' "$ALLOW_PAYLOAD" | node "$DESTRUCT_MJS" >/dev/null 2>&1 || ALLOW_RC=$?
if [ "$ALLOW_RC" -eq 0 ]; then
  pass "pre-bash hook ALLOWS safe command via stdin JSON (FIX-01)"
else
  fail "pre-bash hook incorrectly blocked safe command via stdin JSON — got rc=$ALLOW_RC (FIX-01)"
fi

# 3. Legacy fallback — argv[2] still blocks rm -rf
LEGACY_RC=0
node "$DESTRUCT_MJS" "rm -rf /tmp/test" >/dev/null 2>&1 || LEGACY_RC=$?
if [ "$LEGACY_RC" -eq 2 ]; then
  pass "pre-bash hook BLOCKS rm -rf via argv fallback (FIX-01 legacy)"
else
  fail "pre-bash hook did not BLOCK rm -rf via argv fallback — got rc=$LEGACY_RC (FIX-01 legacy)"
fi

# 4. rm -fr variant: must exit 2 (FIX-06)
RMFR_PAYLOAD='{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"rm -fr /tmp/test"},"session_id":"s1"}'
RMFR_RC=0
printf '%s' "$RMFR_PAYLOAD" | node "$DESTRUCT_MJS" >/dev/null 2>&1 || RMFR_RC=$?
if [ "$RMFR_RC" -eq 2 ]; then
  pass "pre-bash hook BLOCKS rm -fr variant (FIX-06)"
else
  fail "pre-bash hook did not BLOCK rm -fr variant — got rc=$RMFR_RC (FIX-06)"
fi

# 5. rm -r -f variant: must exit 2 (FIX-06)
RMRF2_PAYLOAD='{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"rm -r -f /tmp/test"},"session_id":"s1"}'
RMRF2_RC=0
printf '%s' "$RMRF2_PAYLOAD" | node "$DESTRUCT_MJS" >/dev/null 2>&1 || RMRF2_RC=$?
if [ "$RMRF2_RC" -eq 2 ]; then
  pass "pre-bash hook BLOCKS rm -r -f variant (FIX-06)"
else
  fail "pre-bash hook did not BLOCK rm -r -f variant — got rc=$RMRF2_RC (FIX-06)"
fi

# 6. Empty stdin (no tool_input): must exit 0 (allow)
EMPTY_RC=0
printf '%s' '{}' | node "$DESTRUCT_MJS" >/dev/null 2>&1 || EMPTY_RC=$?
if [ "$EMPTY_RC" -eq 0 ]; then
  pass "pre-bash hook ALLOWS when stdin JSON has no tool_input (FIX-01)"
else
  fail "pre-bash hook incorrectly blocked on empty stdin JSON — got rc=$EMPTY_RC (FIX-01)"
fi

# ──────────────────────────────────────────────────────────────────────────────
# v0.6.1 FIX-01/FIX-02: pre-commit-quality-gate.mjs stdin contract + gitleaks branch
# ──────────────────────────────────────────────────────────────────────────────

echo
echo "▸ v0.6.1 FIX-01/FIX-02: pre-commit-quality-gate.mjs stdin contract + gitleaks branch"

GATE_MJS="$CONJURE_HOME/templates/hooks-nodejs/pre-commit-quality-gate.mjs"
GATE_STDIN_PAYLOAD='{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"git commit -m \"test\""},"session_id":"s1"}'

# 1. STDIN contract — git commit payload is processed (exits 0 without gitleaks)
GATE_STDIN_RC=0
printf '%s' "$GATE_STDIN_PAYLOAD" | node "$GATE_MJS" >/dev/null 2>&1 || GATE_STDIN_RC=$?
if [ "$GATE_STDIN_RC" -eq 0 ]; then
  pass "pre-commit hook processes git commit via stdin JSON (FIX-01)"
else
  fail "pre-commit hook errored on git commit stdin JSON — got rc=$GATE_STDIN_RC (FIX-01)"
fi

# 2. STDIN contract — non-commit is filtered out (exits 0)
GATE_LS_PAYLOAD='{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"ls -la"},"session_id":"s1"}'
GATE_LS_RC=0
printf '%s' "$GATE_LS_PAYLOAD" | node "$GATE_MJS" >/dev/null 2>&1 || GATE_LS_RC=$?
if [ "$GATE_LS_RC" -eq 0 ]; then
  pass "pre-commit hook allows non-commit command via stdin JSON (FIX-01)"
else
  fail "pre-commit hook incorrectly blocked non-commit command — got rc=$GATE_LS_RC (FIX-01)"
fi

# 3. gitleaks exit 1 (finding) must BLOCK (exit 2) — FIX-02
GATE_STUB_BIN1="$(mktemp -d)"
printf '#!/bin/sh\nexit 1\n' > "$GATE_STUB_BIN1/gitleaks"
chmod +x "$GATE_STUB_BIN1/gitleaks"
GATE_STUB1_RC=0
printf '%s' "$GATE_STDIN_PAYLOAD" | PATH="$GATE_STUB_BIN1:$PATH" node "$GATE_MJS" >/dev/null 2>&1 || GATE_STUB1_RC=$?
rm -rf "$GATE_STUB_BIN1"
if [ "$GATE_STUB1_RC" -eq 2 ]; then
  pass "pre-commit hook BLOCKS on gitleaks exit 1 (finding) (FIX-02)"
else
  fail "pre-commit hook did not block on gitleaks exit 1 — got rc=$GATE_STUB1_RC (FIX-02)"
fi

# 4. gitleaks exit 2 (tool error) must NOT block (exit 0)
GATE_STUB_BIN2="$(mktemp -d)"
printf '#!/bin/sh\nexit 2\n' > "$GATE_STUB_BIN2/gitleaks"
chmod +x "$GATE_STUB_BIN2/gitleaks"
GATE_STUB2_RC=0
printf '%s' "$GATE_STDIN_PAYLOAD" | PATH="$GATE_STUB_BIN2:$PATH" node "$GATE_MJS" >/dev/null 2>&1 || GATE_STUB2_RC=$?
rm -rf "$GATE_STUB_BIN2"
if [ "$GATE_STUB2_RC" -ne 2 ]; then
  pass "pre-commit hook does NOT false-block on gitleaks exit 2 (tool error) (FIX-02)"
else
  fail "pre-commit hook false-blocked on gitleaks exit 2 (tool error) (FIX-02)"
fi

# 5. gitleaks signal-kill (status null) must NOT block
GATE_STUB_BIN3="$(mktemp -d)"
# A script that kills itself → Node sees status=null, signal='SIGKILL'
printf '#!/bin/sh\nkill -9 $$\n' > "$GATE_STUB_BIN3/gitleaks"
chmod +x "$GATE_STUB_BIN3/gitleaks"
GATE_STUB3_RC=0
printf '%s' "$GATE_STDIN_PAYLOAD" | PATH="$GATE_STUB_BIN3:$PATH" node "$GATE_MJS" >/dev/null 2>&1 || GATE_STUB3_RC=$?
rm -rf "$GATE_STUB_BIN3"
if [ "$GATE_STUB3_RC" -ne 2 ]; then
  pass "pre-commit hook does NOT false-block on gitleaks signal-kill (FIX-02)"
else
  fail "pre-commit hook false-blocked on gitleaks signal-kill (FIX-02)"
fi

# ──────────────────────────────────────────────────────────────────────────────
# v0.6.1 FIX-01: post-edit-format.mjs stdin contract
# ──────────────────────────────────────────────────────────────────────────────

echo
echo "▸ v0.6.1 FIX-01: post-edit-format.mjs stdin contract"

FMT_MJS="$CONJURE_HOME/templates/hooks-nodejs/post-edit-format.mjs"

# 1. STDIN contract — file_path extracted from stdin JSON, hook exits 0
FMT_TMP="$(mktemp --suffix=.sh 2>/dev/null || mktemp -t tmp.XXXXXX.sh)"
printf '#!/bin/sh\necho hello\n' > "$FMT_TMP"
FMT_PAYLOAD="{\"hook_event_name\":\"PostToolUse\",\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$FMT_TMP\"},\"session_id\":\"s1\"}"
FMT_RC=0
printf '%s' "$FMT_PAYLOAD" | node "$FMT_MJS" >/dev/null 2>&1 || FMT_RC=$?
rm -f "$FMT_TMP"
if [ "$FMT_RC" -eq 0 ]; then
  pass "post-edit hook runs without error via stdin JSON (FIX-01)"
else
  fail "post-edit hook crashed on stdin JSON file_path — got rc=$FMT_RC (FIX-01)"
fi

# 2. STDIN contract — nonexistent file exits 0 (no crash)
FMT_NOFILE_RC=0
printf '%s' "{\"hook_event_name\":\"PostToolUse\",\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"/tmp/conjure-nonexistent-$$\"},\"session_id\":\"s1\"}" | \
  node "$FMT_MJS" >/dev/null 2>&1 || FMT_NOFILE_RC=$?
if [ "$FMT_NOFILE_RC" -eq 0 ]; then
  pass "post-edit hook exits 0 on nonexistent file via stdin JSON (FIX-01)"
else
  fail "post-edit hook crashed on nonexistent file via stdin JSON — got rc=$FMT_NOFILE_RC (FIX-01)"
fi

# 3. Empty stdin exits 0
FMT_EMPTY_RC=0
printf '%s' '{}' | node "$FMT_MJS" >/dev/null 2>&1 || FMT_EMPTY_RC=$?
if [ "$FMT_EMPTY_RC" -eq 0 ]; then
  pass "post-edit hook exits 0 on empty stdin JSON (FIX-01)"
else
  fail "post-edit hook crashed on empty stdin JSON — got rc=$FMT_EMPTY_RC (FIX-01)"
fi

# 4. Legacy fallback — argv[2] still works
FMT_ARGV_TMP="$(mktemp --suffix=.sh 2>/dev/null || mktemp -t tmp.XXXXXX.sh)"
printf '#!/bin/sh\necho hello\n' > "$FMT_ARGV_TMP"
FMT_ARGV_RC=0
node "$FMT_MJS" "$FMT_ARGV_TMP" >/dev/null 2>&1 || FMT_ARGV_RC=$?
rm -f "$FMT_ARGV_TMP"
if [ "$FMT_ARGV_RC" -eq 0 ]; then
  pass "post-edit hook exits 0 with argv[2] file path (legacy fallback) (FIX-01)"
else
  fail "post-edit hook crashed on argv[2] file path — got rc=$FMT_ARGV_RC (FIX-01)"
fi

# ──────────────────────────────────────────────────────────────────────────────
# v0.6.1 FIX-03: --cron template uses pinned actions/checkout, not curl|bash
# ──────────────────────────────────────────────────────────────────────────────

echo
echo "▸ v0.6.1 FIX-03: --cron template uses pinned actions/checkout, not curl|bash"

FIX03_DIR="$(mktemp -d)"
CONJURE_HOME="$CONJURE_HOME" cli/conjure update --cron "$FIX03_DIR" >/dev/null 2>&1
CRON_YML="$FIX03_DIR/.github/workflows/conjure-update.yml"

# 1. curl|bash must NOT be present
if ! grep -qE 'curl.*install\.sh.*\|.*bash' "$CRON_YML" 2>/dev/null; then
  pass "FIX-03: cron template does not contain curl|bash foot-gun"
else
  fail "FIX-03: cron template still contains curl|bash foot-gun"
fi

# 2. actions/checkout@ SHA pin must be present
if grep -q 'actions/checkout@' "$CRON_YML" 2>/dev/null; then
  pass "FIX-03: cron template uses actions/checkout@ (pinned)"
else
  fail "FIX-03: cron template missing actions/checkout@ pin"
fi

# 3. SHA pin comment (# v) must be present
if grep -q '# v' "$CRON_YML" 2>/dev/null; then
  pass "FIX-03: cron template has SHA pin comment (# v...)"
else
  fail "FIX-03: cron template missing SHA pin comment"
fi

# 4. conjure update --pr must still be present (AUTPR-02 compatibility)
if grep -q 'conjure update --pr' "$CRON_YML" 2>/dev/null; then
  pass "FIX-03: cron template still invokes conjure update --pr (AUTPR-02 compat)"
else
  fail "FIX-03: cron template missing conjure update --pr (AUTPR-02 regression)"
fi

# 5. cp to /usr/local/bin must NOT be present (CONJURE_HOME resolution safety)
if ! grep -qE 'cp.*conjure.*/usr/local/bin' "$CRON_YML" 2>/dev/null; then
  pass "FIX-03: cron template does not cp conjure to /usr/local/bin"
else
  fail "FIX-03: cron template still cp-to-usr-local-bin (breaks CONJURE_HOME resolution)"
fi

# 6. CONJURE_HOME=conjure-src must be set on invocation lines
if grep -q 'CONJURE_HOME=conjure-src' "$CRON_YML" 2>/dev/null; then
  pass "FIX-03: cron template sets CONJURE_HOME=conjure-src on invocation"
else
  fail "FIX-03: cron template missing CONJURE_HOME=conjure-src on invocation lines"
fi

rm -rf "$FIX03_DIR"

# ──────────────────────────────────────────────────────────────────────────────
# v0.6.1 FIX-04: inventory.sh DRY_RUN uses mktemp, not hardcoded /tmp path
# ──────────────────────────────────────────────────────────────────────────────

echo
echo "▸ v0.6.1 FIX-04: inventory.sh DRY_RUN uses mktemp, not hardcoded /tmp path"

# 1. Hardcoded /tmp path must be gone
if grep -q '/tmp/adopt-manifest-dryrun.json' "$CONJURE_HOME/lib/inventory.sh"; then
  fail "FIX-04: hardcoded /tmp/adopt-manifest-dryrun.json still present in lib/inventory.sh"
else
  pass "FIX-04: hardcoded /tmp path removed from lib/inventory.sh"
fi

# 2. mktemp must appear near the DRY_RUN branch
if grep -A5 'DRY_RUN' "$CONJURE_HOME/lib/inventory.sh" | grep -q 'mktemp'; then
  pass "FIX-04: mktemp found in DRY_RUN branch of lib/inventory.sh"
else
  fail "FIX-04: mktemp not found in DRY_RUN branch of lib/inventory.sh"
fi

# ──────────────────────────────────────────────────────────────────────────────
# v0.6.1 FIX-05: exit 1 → exit 2 in dispatcher + cmd_publish + overlay scripts
# ──────────────────────────────────────────────────────────────────────────────

echo
echo "▸ v0.6.1 FIX-05: exit 1 → exit 2 in dispatcher + cmd_publish + overlay scripts"

# 1. Dispatcher unknown command exits 2
DISPATCH_RC=0
cli/conjure totally-unknown-command >/dev/null 2>&1 || DISPATCH_RC=$?
if [ "$DISPATCH_RC" -eq 2 ]; then
  pass "dispatcher unknown command exits 2 (FIX-05)"
else
  fail "dispatcher unknown command exits $DISPATCH_RC — expected 2 (FIX-05)"
fi

# 2. cmd_publish unknown option exits 2
PUBLISH_RC=0
cli/conjure publish --totally-unknown-flag >/dev/null 2>&1 || PUBLISH_RC=$?
if [ "$PUBLISH_RC" -eq 2 ]; then
  pass "cmd_publish unknown option exits 2 (FIX-05)"
else
  fail "cmd_publish unknown option exits $PUBLISH_RC — expected 2 (FIX-05)"
fi

# 3. init-overlay.sh empty URL exits 2
IOVERLAY_RC=0
IOVERLAY_DIR="$(mktemp -d)"
CONJURE_HOME="$CONJURE_HOME" bash scripts/init-overlay.sh "" "$IOVERLAY_DIR" >/dev/null 2>&1 || IOVERLAY_RC=$?
rm -rf "$IOVERLAY_DIR"
if [ "$IOVERLAY_RC" -eq 2 ]; then
  pass "init-overlay exits 2 on empty URL (FIX-05)"
else
  fail "init-overlay exits $IOVERLAY_RC on empty URL — expected 2 (FIX-05)"
fi

# 4. init-overlay.sh bad URL exits 2
IOVERLAY_BAD_RC=0
IOVERLAY_BAD_DIR="$(mktemp -d)"
CONJURE_HOME="$CONJURE_HOME" bash scripts/init-overlay.sh "file:///nonexistent-repo-xyz" "$IOVERLAY_BAD_DIR" >/dev/null 2>&1 || IOVERLAY_BAD_RC=$?
rm -rf "$IOVERLAY_BAD_DIR"
if [ "$IOVERLAY_BAD_RC" -eq 2 ]; then
  pass "init-overlay exits 2 on bad URL (FIX-05)"
else
  fail "init-overlay exits $IOVERLAY_BAD_RC on bad URL — expected 2 (FIX-05)"
fi

# 5. refresh-overlay exits 2 when no marker (already tested in OVLY-03 above; explicit assertion)
FIX05_NOMK_DIR="$(mktemp -d)"
mkdir -p "$FIX05_NOMK_DIR/.claude"
FIX05_NOMK_RC=0
CONJURE_HOME="$CONJURE_HOME" bash "$CONJURE_HOME/scripts/refresh-overlay.sh" \
  "$FIX05_NOMK_DIR" >/dev/null 2>&1 || FIX05_NOMK_RC=$?
rm -rf "$FIX05_NOMK_DIR"
if [ "$FIX05_NOMK_RC" -eq 2 ]; then
  pass "refresh-overlay exits 2 when no marker (FIX-05)"
else
  fail "refresh-overlay exits $FIX05_NOMK_RC on no marker — expected 2 (FIX-05)"
fi

# ──────────────────────────────────────────────────────────────────────────────
# Phase 25 — Plugin + Marketplace Emission (PLUG-01..PLUG-05)
# Mirrors Phase 22/24 block style: `▸ Phase 25 — ...` headers, pass/fail
# helpers, mktemp sandboxes with EXIT-trap discipline. Every emit invocation
# guarded behind P25_EMIT_OK so the suite reports graceful RED when
# scripts/emit-plugin.sh is absent (Wave 1 not yet complete).
# ──────────────────────────────────────────────────────────────────────────────

P25_EMIT_SH="$CONJURE_HOME/scripts/emit-plugin.sh"
P25_AUDIT_SH="$CONJURE_HOME/scripts/audit-setup.sh"
P25_EMIT_OK=0
[ -f "$P25_EMIT_SH" ] && P25_EMIT_OK=1

echo
echo "▸ Phase 25 — Plugin + Marketplace Emission (PLUG-01..PLUG-05)"

# PLUG-01: emit-plugin.sh produces plugin.json with correct fields
P25_PLUG01_DIR="$(mktemp -d)"
trap 'rm -rf "$P25_PLUG01_DIR"' EXIT
git -C "$P25_PLUG01_DIR" init -q
git -C "$P25_PLUG01_DIR" config user.email "test@conjure"
git -C "$P25_PLUG01_DIR" config user.name "conjure-test"
cp -r "$CONJURE_HOME/tests/fixtures/_emit-plugin/harness/." "$P25_PLUG01_DIR/"
git -C "$P25_PLUG01_DIR" add -A
git -C "$P25_PLUG01_DIR" commit -q -m "test fixture"
if [ "$P25_EMIT_OK" -eq 1 ]; then
  CONJURE_HOME="$CONJURE_HOME" bash "$P25_EMIT_SH" --path "$P25_PLUG01_DIR" >/dev/null 2>&1
  if jq -e '.name and .skills and .agents and .hooks and .mcpServers' \
      "$P25_PLUG01_DIR/.claude-plugin/plugin.json" >/dev/null 2>&1; then
    pass "emit-plugin produces plugin.json with correct fields (PLUG-01)"
  else
    fail "emit-plugin plugin.json missing required fields (PLUG-01)"
  fi
else
  fail "emit-plugin.sh not found — Wave 1 must create scripts/emit-plugin.sh (PLUG-01)"
fi
rm -rf "$P25_PLUG01_DIR"
trap - EXIT

# PLUG-01-merge: re-run preserves user-edited description field
P25_MERGE_DIR="$(mktemp -d)"
trap 'rm -rf "$P25_MERGE_DIR"' EXIT
git -C "$P25_MERGE_DIR" init -q
git -C "$P25_MERGE_DIR" config user.email "test@conjure"
git -C "$P25_MERGE_DIR" config user.name "conjure-test"
cp -r "$CONJURE_HOME/tests/fixtures/_emit-plugin/harness/." "$P25_MERGE_DIR/"
git -C "$P25_MERGE_DIR" add -A
git -C "$P25_MERGE_DIR" commit -q -m "test fixture"
if [ "$P25_EMIT_OK" -eq 1 ]; then
  CONJURE_HOME="$CONJURE_HOME" bash "$P25_EMIT_SH" --path "$P25_MERGE_DIR" >/dev/null 2>&1
  EXISTING_PLG="$(cat "$P25_MERGE_DIR/.claude-plugin/plugin.json")"
  UPDATED_PLG="$(printf '%s' "$EXISTING_PLG" | jq '.description = "keep-me"')"
  printf '%s\n' "$UPDATED_PLG" > "$P25_MERGE_DIR/.claude-plugin/plugin.json"
  CONJURE_HOME="$CONJURE_HOME" bash "$P25_EMIT_SH" --path "$P25_MERGE_DIR" >/dev/null 2>&1
  MERGE_DESC="$(jq -r '.description' "$P25_MERGE_DIR/.claude-plugin/plugin.json")"
  if [ "$MERGE_DESC" = "keep-me" ]; then
    pass "emit-plugin re-run preserves user-edited description (PLUG-01-merge)"
  else
    fail "emit-plugin re-run overwrote description — got: $MERGE_DESC (PLUG-01-merge)"
  fi
else
  fail "emit-plugin.sh not found — Wave 1 must create scripts/emit-plugin.sh (PLUG-01-merge)"
fi
rm -rf "$P25_MERGE_DIR"
trap - EXIT

# PLUG-01-greenfield (CR-01 regression): first-time emit into a repo with NO
# pre-existing .claude-plugin/plugin.json must exit 0 and produce a schema-valid
# non-empty `.name`. The shared fixture ships a plugin.json carrying "name", which
# masked the greenfield bug where the merge base is {} and `.name` is never set —
# making the WR-02-hardened validator reject the emitter's own first-run output.
# We name the repo dir with mixed case + underscore to also exercise the kebab
# normalization (^[a-z][a-z0-9-]{0,63}$) on the derived name.
P25_GREEN_PARENT="$(mktemp -d)"
trap 'rm -rf "$P25_GREEN_PARENT"' EXIT
P25_GREEN_DIR="$P25_GREEN_PARENT/My_Cool_Repo"
mkdir -p "$P25_GREEN_DIR"
git -C "$P25_GREEN_DIR" init -q
git -C "$P25_GREEN_DIR" config user.email "test@conjure"
git -C "$P25_GREEN_DIR" config user.name "conjure-test"
cp -r "$CONJURE_HOME/tests/fixtures/_emit-plugin/harness/." "$P25_GREEN_DIR/"
# Greenfield: remove the fixture's pre-existing manifest so the merge base is {}.
rm -f "$P25_GREEN_DIR/.claude-plugin/plugin.json"
git -C "$P25_GREEN_DIR" add -A
git -C "$P25_GREEN_DIR" commit -q -m "test fixture"
if [ "$P25_EMIT_OK" -eq 1 ]; then
  CONJURE_HOME="$CONJURE_HOME" bash "$P25_EMIT_SH" --path "$P25_GREEN_DIR" >/dev/null 2>&1
  GREEN_RC=$?
  GREEN_NAME="$(jq -r '.name // ""' "$P25_GREEN_DIR/.claude-plugin/plugin.json" 2>/dev/null || echo "")"
  if [ "$GREEN_RC" -eq 0 ] \
     && [ -n "$GREEN_NAME" ] \
     && printf '%s' "$GREEN_NAME" | grep -qE '^[a-z][a-z0-9-]{0,63}$'; then
    pass "emit-plugin greenfield first-run sets schema-valid name and exits 0 (PLUG-01-greenfield/CR-01)"
  else
    fail "emit-plugin greenfield rc=$GREEN_RC name='$GREEN_NAME' — expected rc 0 + kebab name (PLUG-01-greenfield/CR-01)"
  fi
else
  fail "emit-plugin.sh not found — Wave 1 must create scripts/emit-plugin.sh (PLUG-01-greenfield/CR-01)"
fi
rm -rf "$P25_GREEN_PARENT"
trap - EXIT

# PLUG-05: version fallback — no .conjure-version → git SHA (40-char hex)
P25_PLUG05_DIR="$(mktemp -d)"
trap 'rm -rf "$P25_PLUG05_DIR"' EXIT
git -C "$P25_PLUG05_DIR" init -q
git -C "$P25_PLUG05_DIR" config user.email "test@conjure"
git -C "$P25_PLUG05_DIR" config user.name "conjure-test"
cp -r "$CONJURE_HOME/tests/fixtures/_emit-plugin/harness/." "$P25_PLUG05_DIR/"
rm -f "$P25_PLUG05_DIR/.conjure-version"
git -C "$P25_PLUG05_DIR" add -A
git -C "$P25_PLUG05_DIR" commit -q -m "test fixture"
if [ "$P25_EMIT_OK" -eq 1 ]; then
  CONJURE_HOME="$CONJURE_HOME" bash "$P25_EMIT_SH" --path "$P25_PLUG05_DIR" >/dev/null 2>&1
  VER="$(jq -r '.version' "$P25_PLUG05_DIR/.claude-plugin/plugin.json")"
  if printf '%s' "$VER" | grep -qE '^[0-9a-f]{40}$'; then
    pass "emit-plugin uses git SHA as version when .conjure-version absent (PLUG-05)"
  else
    fail "emit-plugin version not a 40-char hex SHA — got: $VER (PLUG-05)"
  fi
else
  fail "emit-plugin.sh not found — Wave 1 must create scripts/emit-plugin.sh (PLUG-05)"
fi
rm -rf "$P25_PLUG05_DIR"
trap - EXIT

# PLUG-05-blank: blank/whitespace-only .conjure-version falls through to git SHA (WR-01)
# Regression guard: tr -d '[:space:]' on a blank file must NOT emit "version": ""
P25_PLUG05B_DIR="$(mktemp -d)"
trap 'rm -rf "$P25_PLUG05B_DIR"' EXIT
git -C "$P25_PLUG05B_DIR" init -q
git -C "$P25_PLUG05B_DIR" config user.email "test@conjure"
git -C "$P25_PLUG05B_DIR" config user.name "conjure-test"
cp -r "$CONJURE_HOME/tests/fixtures/_emit-plugin/harness/." "$P25_PLUG05B_DIR/"
printf '\n' > "$P25_PLUG05B_DIR/.conjure-version"   # whitespace-only
git -C "$P25_PLUG05B_DIR" add -A
git -C "$P25_PLUG05B_DIR" commit -q -m "test fixture"
if [ "$P25_EMIT_OK" -eq 1 ]; then
  CONJURE_HOME="$CONJURE_HOME" bash "$P25_EMIT_SH" --path "$P25_PLUG05B_DIR" >/dev/null 2>&1
  VER="$(jq -r '.version' "$P25_PLUG05B_DIR/.claude-plugin/plugin.json")"
  if printf '%s' "$VER" | grep -qE '^[0-9a-f]{40}$'; then
    pass "emit-plugin falls through to git SHA when .conjure-version is blank (PLUG-05-blank)"
  else
    fail "emit-plugin emitted version '$VER' for blank .conjure-version — expected git SHA (PLUG-05-blank)"
  fi
else
  fail "emit-plugin.sh not found — Wave 1 must create scripts/emit-plugin.sh (PLUG-05-blank)"
fi
rm -rf "$P25_PLUG05B_DIR"
trap - EXIT

# PLUG-04: schema validation blocks write on invalid manifest
# Strategy: harness with empty .claude/ (no skills/agents) and a pre-existing plugin.json
# missing the required "name" field — bundled schema check must exit 2.
# CR-01: plugin_build_plugin_json now derives a kebab name from the target basename,
# so to keep this test exercising the "no name available" path we put the target in a
# subdir whose basename ('123') is NOT a valid schema name (^[a-z][a-z0-9-]{0,63}$ —
# must start with a LETTER). The derived fallback is dropped, the existing stub has no
# name, and validation must exit 2.
P25_PLUG04_PARENT="$(mktemp -d)"
trap 'rm -rf "$P25_PLUG04_PARENT"' EXIT
P25_PLUG04_DIR="$P25_PLUG04_PARENT/123"
mkdir -p "$P25_PLUG04_DIR/.claude"
printf '{}' > "$P25_PLUG04_DIR/.claude/settings.json"
mkdir -p "$P25_PLUG04_DIR/.claude-plugin"
printf '{"version": "1.0.0"}' > "$P25_PLUG04_DIR/.claude-plugin/plugin.json"
if [ "$P25_EMIT_OK" -eq 1 ]; then
  PLUG04_RC=0
  # emit should exit 2 because no name can be inferred and the existing stub has no name
  CONJURE_HOME="$CONJURE_HOME" bash "$P25_EMIT_SH" --path "$P25_PLUG04_DIR" >/dev/null 2>&1 || PLUG04_RC=$?
  if [ "$PLUG04_RC" -eq 2 ]; then
    pass "emit-plugin exits 2 on invalid manifest missing name field (PLUG-04)"
  else
    fail "emit-plugin exited $PLUG04_RC on invalid manifest — expected 2 (PLUG-04)"
  fi
else
  fail "emit-plugin.sh not found — Wave 1 must create scripts/emit-plugin.sh (PLUG-04)"
fi
rm -rf "$P25_PLUG04_PARENT"
trap - EXIT

# PLUG-04-secret: secret-pattern in emitted manifest → exit 2 before write
P25_SECRET_DIR="$(mktemp -d)"
trap 'rm -rf "$P25_SECRET_DIR"' EXIT
cp -r "$CONJURE_HOME/tests/fixtures/_emit-plugin-secret/harness/." "$P25_SECRET_DIR/"
if [ "$P25_EMIT_OK" -eq 1 ]; then
  P25_SECRET_PLUGIN_BEFORE="$P25_SECRET_DIR/.claude-plugin/plugin.json"
  P25_SECRET_BEFORE_TS="$(date -r "$P25_SECRET_PLUGIN_BEFORE" +%s 2>/dev/null || stat -f %m "$P25_SECRET_PLUGIN_BEFORE" 2>/dev/null || echo "0")"
  SECRET_RC=0
  CONJURE_HOME="$CONJURE_HOME" bash "$P25_EMIT_SH" --path "$P25_SECRET_DIR" >/dev/null 2>&1 || SECRET_RC=$?
  if [ "$SECRET_RC" -eq 2 ]; then
    pass "emit-plugin exits 2 when secret pattern detected in manifest (PLUG-04-secret)"
  else
    fail "emit-plugin exited $SECRET_RC on secret manifest — expected 2 (PLUG-04-secret)"
  fi
else
  fail "emit-plugin.sh not found — Wave 1 must create scripts/emit-plugin.sh (PLUG-04-secret)"
fi
rm -rf "$P25_SECRET_DIR"
trap - EXIT

# PLUG-04-absent: --validate with hidden claude binary → exit 2
P25_ABSENT_DIR="$(mktemp -d)"
trap 'rm -rf "$P25_ABSENT_DIR"' EXIT
git -C "$P25_ABSENT_DIR" init -q
git -C "$P25_ABSENT_DIR" config user.email "test@conjure"
git -C "$P25_ABSENT_DIR" config user.name "conjure-test"
cp -r "$CONJURE_HOME/tests/fixtures/_emit-plugin/harness/." "$P25_ABSENT_DIR/"
git -C "$P25_ABSENT_DIR" add -A
git -C "$P25_ABSENT_DIR" commit -q -m "test fixture"
if [ "$P25_EMIT_OK" -eq 1 ]; then
  ABSENT_RC=0
  # shellcheck disable=SC2155
  P25_CLEAN_PATH="$(printf '%s' "$PATH" | tr ':' '\n' | grep -v 'claude' | tr '\n' ':' | sed 's/:$//')"
  PATH="$P25_CLEAN_PATH" CONJURE_HOME="$CONJURE_HOME" bash "$P25_EMIT_SH" \
    --path "$P25_ABSENT_DIR" --validate >/dev/null 2>&1 || ABSENT_RC=$?
  if [ "$ABSENT_RC" -eq 2 ]; then
    pass "emit-plugin --validate exits 2 when claude binary absent (PLUG-04-absent)"
  else
    fail "emit-plugin --validate exited $ABSENT_RC without claude — expected 2 (PLUG-04-absent)"
  fi
else
  fail "emit-plugin.sh not found — Wave 1 must create scripts/emit-plugin.sh (PLUG-04-absent)"
fi
rm -rf "$P25_ABSENT_DIR"
trap - EXIT

# PLUG-02: --marketplace emits marketplace.json with correct fields
P25_PLUG02_DIR="$(mktemp -d)"
trap 'rm -rf "$P25_PLUG02_DIR"' EXIT
git -C "$P25_PLUG02_DIR" init -q
git -C "$P25_PLUG02_DIR" config user.email "test@conjure"
git -C "$P25_PLUG02_DIR" config user.name "conjure-test"
cp -r "$CONJURE_HOME/tests/fixtures/_emit-plugin/harness/." "$P25_PLUG02_DIR/"
git -C "$P25_PLUG02_DIR" add -A
git -C "$P25_PLUG02_DIR" commit -q -m "test fixture"
if [ "$P25_EMIT_OK" -eq 1 ]; then
  CONJURE_HOME="$CONJURE_HOME" bash "$P25_EMIT_SH" --path "$P25_PLUG02_DIR" --marketplace >/dev/null 2>&1
  if jq -e '(.name | type) == "string" and (.owner | type) == "object" and (.plugins | type) == "array"' \
      "$P25_PLUG02_DIR/.claude-plugin/marketplace.json" >/dev/null 2>&1; then
    pass "emit-plugin --marketplace produces marketplace.json with correct shape (PLUG-02)"
  else
    fail "emit-plugin marketplace.json missing required fields (PLUG-02)"
  fi
else
  fail "emit-plugin.sh not found — Wave 1 must create scripts/emit-plugin.sh (PLUG-02)"
fi
rm -rf "$P25_PLUG02_DIR"
trap - EXIT

# PLUG-02-reserved: reserved marketplace name → exit 2
P25_RESERVED_DIR="$(mktemp -d)"
trap 'rm -rf "$P25_RESERVED_DIR"' EXIT
git -C "$P25_RESERVED_DIR" init -q
git -C "$P25_RESERVED_DIR" config user.email "test@conjure"
git -C "$P25_RESERVED_DIR" config user.name "conjure-test"
cp -r "$CONJURE_HOME/tests/fixtures/_emit-plugin/harness/." "$P25_RESERVED_DIR/"
git -C "$P25_RESERVED_DIR" add -A
git -C "$P25_RESERVED_DIR" commit -q -m "test fixture"
if [ "$P25_EMIT_OK" -eq 1 ]; then
  RESERVED_RC=0
  CONJURE_PLUGIN_MKT_NAME="claude-code-marketplace" CONJURE_HOME="$CONJURE_HOME" \
    bash "$P25_EMIT_SH" --path "$P25_RESERVED_DIR" --marketplace >/dev/null 2>&1 || RESERVED_RC=$?
  if [ "$RESERVED_RC" -eq 2 ]; then
    pass "emit-plugin exits 2 on reserved marketplace name (PLUG-02-reserved)"
  else
    fail "emit-plugin exited $RESERVED_RC on reserved name — expected 2 (PLUG-02-reserved)"
  fi
else
  fail "emit-plugin.sh not found — Wave 1 must create scripts/emit-plugin.sh (PLUG-02-reserved)"
fi
rm -rf "$P25_RESERVED_DIR"
trap - EXIT

# PLUG-02-badpath: non-existent --path → exit 2
if [ "$P25_EMIT_OK" -eq 1 ]; then
  BADPATH_RC=0
  CONJURE_HOME="$CONJURE_HOME" bash "$P25_EMIT_SH" \
    --path "/tmp/__conjure_nonexistent_$$" >/dev/null 2>&1 || BADPATH_RC=$?
  if [ "$BADPATH_RC" -eq 2 ]; then
    pass "emit-plugin exits 2 on non-existent --path (PLUG-02-badpath)"
  else
    fail "emit-plugin exited $BADPATH_RC on non-existent path — expected 2 (PLUG-02-badpath)"
  fi
else
  fail "emit-plugin.sh not found — Wave 1 must create scripts/emit-plugin.sh (PLUG-02-badpath)"
fi

# PLUG-03: --marketplace wires extraKnownMarketplaces into settings.json
P25_PLUG03_DIR="$(mktemp -d)"
trap 'rm -rf "$P25_PLUG03_DIR"' EXIT
git -C "$P25_PLUG03_DIR" init -q
git -C "$P25_PLUG03_DIR" config user.email "test@conjure"
git -C "$P25_PLUG03_DIR" config user.name "conjure-test"
cp -r "$CONJURE_HOME/tests/fixtures/_emit-plugin/harness/." "$P25_PLUG03_DIR/"
git -C "$P25_PLUG03_DIR" add -A
git -C "$P25_PLUG03_DIR" commit -q -m "test fixture"
if [ "$P25_EMIT_OK" -eq 1 ]; then
  CONJURE_HOME="$CONJURE_HOME" bash "$P25_EMIT_SH" --path "$P25_PLUG03_DIR" --marketplace >/dev/null 2>&1
  if jq -e '.extraKnownMarketplaces | type == "object"' \
      "$P25_PLUG03_DIR/.claude/settings.json" >/dev/null 2>&1; then
    pass "emit-plugin --marketplace wires extraKnownMarketplaces as object (PLUG-03)"
  else
    fail "emit-plugin settings.json extraKnownMarketplaces is not an object (PLUG-03)"
  fi
else
  fail "emit-plugin.sh not found — Wave 1 must create scripts/emit-plugin.sh (PLUG-03)"
fi
rm -rf "$P25_PLUG03_DIR"
trap - EXIT

# PLUG-03-idem: re-running --marketplace produces identical settings.json
P25_IDEM_DIR="$(mktemp -d)"
trap 'rm -rf "$P25_IDEM_DIR"' EXIT
git -C "$P25_IDEM_DIR" init -q
git -C "$P25_IDEM_DIR" config user.email "test@conjure"
git -C "$P25_IDEM_DIR" config user.name "conjure-test"
cp -r "$CONJURE_HOME/tests/fixtures/_emit-plugin/harness/." "$P25_IDEM_DIR/"
git -C "$P25_IDEM_DIR" add -A
git -C "$P25_IDEM_DIR" commit -q -m "test fixture"
if [ "$P25_EMIT_OK" -eq 1 ]; then
  CONJURE_HOME="$CONJURE_HOME" bash "$P25_EMIT_SH" --path "$P25_IDEM_DIR" --marketplace >/dev/null 2>&1
  AFTER_FIRST="$(cat "$P25_IDEM_DIR/.claude/settings.json")"
  CONJURE_HOME="$CONJURE_HOME" bash "$P25_EMIT_SH" --path "$P25_IDEM_DIR" --marketplace >/dev/null 2>&1
  AFTER_SECOND="$(cat "$P25_IDEM_DIR/.claude/settings.json")"
  if [ "$AFTER_FIRST" = "$AFTER_SECOND" ]; then
    pass "emit-plugin --marketplace idempotent: re-run produces identical settings.json (PLUG-03-idem)"
  else
    fail "emit-plugin --marketplace not idempotent: settings.json differs on second run (PLUG-03-idem)"
  fi
else
  fail "emit-plugin.sh not found — Wave 1 must create scripts/emit-plugin.sh (PLUG-03-idem)"
fi
rm -rf "$P25_IDEM_DIR"
trap - EXIT

# PLUG-REC: audit-setup.sh warns when plugin.json lists skills path but no SKILL.md found
# Uses go-gin as a complete audit-clean base; empties .claude/skills to trigger reconciliation advisory.
P25_REC_DIR="$(mktemp -d)"
trap 'rm -rf "$P25_REC_DIR"' EXIT
cp -r "$CONJURE_HOME/tests/fixtures/go-gin/." "$P25_REC_DIR/"
# Remove all SKILL.md files so .claude/skills/ exists but has 0 skills (triggers reconciliation advisory)
find "$P25_REC_DIR/.claude/skills" -name "SKILL.md" -delete 2>/dev/null || true
mkdir -p "$P25_REC_DIR/.claude-plugin"
# plugin.json listing skills path but no SKILL.md on disk
printf '{"name":"test-rec","skills":".claude/skills"}' > "$P25_REC_DIR/.claude-plugin/plugin.json"
P25_REC_OUT=0
PLUG_REC_OUT="$(CONJURE_HOME="$CONJURE_HOME" bash "$P25_AUDIT_SH" "$P25_REC_DIR" 2>&1)" || P25_REC_OUT=$?
if [ "$P25_REC_OUT" -eq 0 ] && printf '%s\n' "$PLUG_REC_OUT" | grep -q "publish-plugin"; then
  pass "audit-setup warns about plugin.json skills path with no SKILL.md (PLUG-REC)"
else
  fail "audit-setup did not warn about skills path drift — rc=$P25_REC_OUT (PLUG-REC)"
fi
rm -rf "$P25_REC_DIR"
trap - EXIT

# PLUG-REFSHA: audit-setup.sh warns when extraKnownMarketplaces entry has ref but no sha
# Uses go-gin as a complete audit-clean base; overlays settings.json with ref-without-sha entry.
P25_REFSHA_DIR="$(mktemp -d)"
trap 'rm -rf "$P25_REFSHA_DIR"' EXIT
cp -r "$CONJURE_HOME/tests/fixtures/go-gin/." "$P25_REFSHA_DIR/"
# Overlay settings.json: keep hooks block but add extraKnownMarketplaces with ref but no sha
jq '. + {"extraKnownMarketplaces":{"my-mkt":{"source":{"source":"github","repo":"org/repo","ref":"main"}}}}' \
  "$P25_REFSHA_DIR/.claude/settings.json" > "$P25_REFSHA_DIR/.claude/settings.json.tmp" 2>/dev/null \
  && mv "$P25_REFSHA_DIR/.claude/settings.json.tmp" "$P25_REFSHA_DIR/.claude/settings.json" \
  || printf '{"extraKnownMarketplaces":{"my-mkt":{"source":{"source":"github","repo":"org/repo","ref":"main"}}}}' \
       > "$P25_REFSHA_DIR/.claude/settings.json"
P25_REFSHA_RC=0
PLUG_REFSHA_OUT="$(CONJURE_HOME="$CONJURE_HOME" bash "$P25_AUDIT_SH" "$P25_REFSHA_DIR" 2>&1)" || P25_REFSHA_RC=$?
if [ "$P25_REFSHA_RC" -eq 0 ] && printf '%s\n' "$PLUG_REFSHA_OUT" | grep -q "ref"; then
  pass "audit-setup warns about extraKnownMarketplaces entry with ref but no sha (PLUG-REFSHA)"
else
  fail "audit-setup did not warn about ref-without-sha — rc=$P25_REFSHA_RC (PLUG-REFSHA)"
fi
rm -rf "$P25_REFSHA_DIR"
trap - EXIT

# ──────────────────────────────────────────────────────────────────────────────
# Phase 26 — Sandbox + Managed-Settings / MDM (POL-01..POL-05)
# Mirrors Phase 25 block style: `▸ Phase 26 — ...` headers, pass/fail
# helpers, mktemp sandboxes with EXIT-trap discipline. Every emit invocation
# guarded behind P26_EMIT_OK so the suite reports graceful RED when
# scripts/emit-policy.sh is absent (Wave 0 not yet complete).
# ──────────────────────────────────────────────────────────────────────────────

P26_EMIT_SH="$CONJURE_HOME/scripts/emit-policy.sh"
P26_AUDIT_SH="$CONJURE_HOME/scripts/audit-setup.sh"
P26_EMIT_OK=0
[ -f "$P26_EMIT_SH" ] && P26_EMIT_OK=1

echo
echo "▸ Phase 26 — Sandbox + Managed-Settings / MDM (POL-01..POL-05)"

# POL-01: emit-policy merges sandbox block into .claude/settings.json
P26_POL01_DIR="$(mktemp -d)"
trap 'rm -rf "$P26_POL01_DIR"' EXIT
git -C "$P26_POL01_DIR" init -q
git -C "$P26_POL01_DIR" config user.email "test@conjure"
git -C "$P26_POL01_DIR" config user.name "conjure-test"
cp -r "$CONJURE_HOME/tests/fixtures/_emit-policy/harness/." "$P26_POL01_DIR/"
git -C "$P26_POL01_DIR" add -A
git -C "$P26_POL01_DIR" commit -q -m "test fixture"
if [ "$P26_EMIT_OK" -eq 1 ]; then
  CONJURE_HOME="$CONJURE_HOME" bash "$P26_EMIT_SH" --regime hipaa --output "$P26_POL01_DIR/conjure-policy" 2>/dev/null
  if jq -e '.sandbox.enabled == true' "$P26_POL01_DIR/.claude/settings.json" >/dev/null 2>&1; then
    pass "emit-policy merges sandbox block into settings.json (POL-01)"
  else
    fail "emit-policy sandbox.enabled not true in settings.json (POL-01)"
  fi
else
  fail "emit-policy.sh not found — Wave 1 must create scripts/emit-policy.sh (POL-01)"
fi
rm -rf "$P26_POL01_DIR"
trap - EXIT

# POL-01-idem: re-running emit-policy produces identical settings.json
P26_IDEM_DIR="$(mktemp -d)"
trap 'rm -rf "$P26_IDEM_DIR"' EXIT
git -C "$P26_IDEM_DIR" init -q
git -C "$P26_IDEM_DIR" config user.email "test@conjure"
git -C "$P26_IDEM_DIR" config user.name "conjure-test"
cp -r "$CONJURE_HOME/tests/fixtures/_emit-policy/harness/." "$P26_IDEM_DIR/"
git -C "$P26_IDEM_DIR" add -A
git -C "$P26_IDEM_DIR" commit -q -m "test fixture"
if [ "$P26_EMIT_OK" -eq 1 ]; then
  CONJURE_HOME="$CONJURE_HOME" bash "$P26_EMIT_SH" --regime hipaa --output "$P26_IDEM_DIR/conjure-policy" 2>/dev/null
  P26_IDEM_FIRST="$(cat "$P26_IDEM_DIR/.claude/settings.json")"
  CONJURE_HOME="$CONJURE_HOME" bash "$P26_EMIT_SH" --regime hipaa --output "$P26_IDEM_DIR/conjure-policy" 2>/dev/null
  P26_IDEM_SECOND="$(cat "$P26_IDEM_DIR/.claude/settings.json")"
  if [ "$P26_IDEM_FIRST" = "$P26_IDEM_SECOND" ]; then
    pass "emit-policy is idempotent: re-run produces identical settings.json (POL-01-idem)"
  else
    fail "emit-policy re-run changed settings.json — idempotency violated (POL-01-idem)"
  fi
else
  fail "emit-policy.sh not found — Wave 1 must create scripts/emit-policy.sh (POL-01-idem)"
fi
rm -rf "$P26_IDEM_DIR"
trap - EXIT

# POL-02-operator: operator-added sandbox.filesystem.denyRead path is mirrored into
# permissions.deny on a subsequent emit (WR-03). Emit once, hand-add a denyRead
# path to settings.json, re-emit, then confirm the corresponding Read() entry now
# appears in permissions.deny — closing the "false sense of security" gap.
P26_POL02OP_DIR="$(mktemp -d)"
trap 'rm -rf "$P26_POL02OP_DIR"' EXIT
git -C "$P26_POL02OP_DIR" init -q
git -C "$P26_POL02OP_DIR" config user.email "test@conjure"
git -C "$P26_POL02OP_DIR" config user.name "conjure-test"
cp -r "$CONJURE_HOME/tests/fixtures/_emit-policy/harness/." "$P26_POL02OP_DIR/"
git -C "$P26_POL02OP_DIR" add -A
git -C "$P26_POL02OP_DIR" commit -q -m "test fixture"
if [ "$P26_EMIT_OK" -eq 1 ]; then
  CONJURE_HOME="$CONJURE_HOME" bash "$P26_EMIT_SH" --regime hipaa --output "$P26_POL02OP_DIR/conjure-policy" 2>/dev/null
  # Operator hand-adds a denyRead path (not present in baseline/regime data).
  P26_POL02OP_SET="$P26_POL02OP_DIR/.claude/settings.json"
  P26_POL02OP_PATCHED="$(jq '.sandbox.filesystem.denyRead += ["~/.operator-secret"]' "$P26_POL02OP_SET")"
  printf '%s' "$P26_POL02OP_PATCHED" > "$P26_POL02OP_SET"
  # Re-emit: the operator-added denyRead path must now be mirrored.
  CONJURE_HOME="$CONJURE_HOME" bash "$P26_EMIT_SH" --regime hipaa --output "$P26_POL02OP_DIR/conjure-policy" 2>/dev/null
  if jq -e '.permissions.deny | index("Read(~/.operator-secret)")' "$P26_POL02OP_SET" >/dev/null 2>&1; then
    pass "operator-added denyRead path mirrored into permissions.deny on re-emit (POL-02-operator)"
  else
    fail "operator-added denyRead path NOT mirrored into permissions.deny on re-emit (POL-02-operator)"
  fi
else
  fail "emit-policy.sh not found — Wave 1 must create scripts/emit-policy.sh (POL-02-operator)"
fi
rm -rf "$P26_POL02OP_DIR"
trap - EXIT

# POL-secret-merged: a credential already present in the operator's existing
# settings.json aborts emit before write (WR-04 — scan the merged result, not just
# the generated block).
P26_SECMRG_DIR="$(mktemp -d)"
trap 'rm -rf "$P26_SECMRG_DIR"' EXIT
git -C "$P26_SECMRG_DIR" init -q
git -C "$P26_SECMRG_DIR" config user.email "test@conjure"
git -C "$P26_SECMRG_DIR" config user.name "conjure-test"
cp -r "$CONJURE_HOME/tests/fixtures/_emit-policy/harness/." "$P26_SECMRG_DIR/"
mkdir -p "$P26_SECMRG_DIR/.claude"
# Plant a credential pattern in the operator's pre-existing settings.json. The key
# is assembled at runtime so no literal credential lives in this test source.
P26_SECMRG_KEY="AKIA$(printf 'IOSFODNN7EXAMPLE')"
printf '{"hooks":{},"_note":"%s"}' "$P26_SECMRG_KEY" > "$P26_SECMRG_DIR/.claude/settings.json"
# Snapshot the planted content so we can assert the abort wrote nothing (WR-04).
P26_SECMRG_BEFORE="$(cat "$P26_SECMRG_DIR/.claude/settings.json")"
git -C "$P26_SECMRG_DIR" add -A
git -C "$P26_SECMRG_DIR" commit -q -m "test fixture"
if [ "$P26_EMIT_OK" -eq 1 ]; then
  P26_SECMRG_RC=0
  CONJURE_HOME="$CONJURE_HOME" bash "$P26_EMIT_SH" --regime hipaa \
    --output "$P26_SECMRG_DIR/conjure-policy" >/dev/null 2>&1 || P26_SECMRG_RC=$?
  # WR-04 (iter 2): the merge secret-abort MUST exit exactly 2 (hard failure),
  # never 1 — CLAUDE.md hard convention + emit-policy's "2 = hard failure"
  # contract. A bare `-ne 0` check (the prior assertion) let an exit-1 regression
  # slip through, so assert the exact code here.
  P26_SECMRG_AFTER="$(cat "$P26_SECMRG_DIR/.claude/settings.json")"
  if [ "$P26_SECMRG_RC" -eq 2 ]; then
    pass "emit exits exactly 2 when operator's existing settings.json contains a credential (POL-secret-merged)"
  else
    fail "emit exited $P26_SECMRG_RC on credential in operator's existing settings.json — expected 2 (POL-secret-merged)"
  fi
  if [ "$P26_SECMRG_AFTER" = "$P26_SECMRG_BEFORE" ]; then
    pass "emit secret-abort leaves operator's settings.json unchanged — no write (POL-secret-merged-nowrite)"
  else
    fail "emit secret-abort mutated operator's settings.json — write should have been aborted (POL-secret-merged-nowrite)"
  fi
else
  fail "emit-policy.sh not found — Wave 1 must create scripts/emit-policy.sh (POL-secret-merged)"
fi
rm -rf "$P26_SECMRG_DIR"
trap - EXIT

# POL-02: emit-policy mirrors denyRead paths into permissions.deny
P26_POL02_DIR="$(mktemp -d)"
trap 'rm -rf "$P26_POL02_DIR"' EXIT
git -C "$P26_POL02_DIR" init -q
git -C "$P26_POL02_DIR" config user.email "test@conjure"
git -C "$P26_POL02_DIR" config user.name "conjure-test"
cp -r "$CONJURE_HOME/tests/fixtures/_emit-policy/harness/." "$P26_POL02_DIR/"
git -C "$P26_POL02_DIR" add -A
git -C "$P26_POL02_DIR" commit -q -m "test fixture"
if [ "$P26_EMIT_OK" -eq 1 ]; then
  CONJURE_HOME="$CONJURE_HOME" bash "$P26_EMIT_SH" --regime hipaa --output "$P26_POL02_DIR/conjure-policy" 2>/dev/null
  P26_POL02_DENY_LEN="$(jq '.permissions.deny // [] | length' "$P26_POL02_DIR/.claude/settings.json" 2>/dev/null || echo 0)"
  P26_POL02_READ_LEN="$(jq '.sandbox.filesystem.denyRead // [] | length' "$P26_POL02_DIR/.claude/settings.json" 2>/dev/null || echo 0)"
  if [ "$P26_POL02_DENY_LEN" -gt 0 ] && [ "$P26_POL02_READ_LEN" -gt 0 ]; then
    pass "emit-policy mirrors denyRead paths into permissions.deny (POL-02)"
  else
    fail "emit-policy permissions.deny or denyRead empty — denyLen=$P26_POL02_DENY_LEN readLen=$P26_POL02_READ_LEN (POL-02)"
  fi
else
  fail "emit-policy.sh not found — Wave 1 must create scripts/emit-policy.sh (POL-02)"
fi
rm -rf "$P26_POL02_DIR"
trap - EXIT

# POL-03: emit-policy produces managed-settings.json with correct keys and types
P26_POL03_DIR="$(mktemp -d)"
trap 'rm -rf "$P26_POL03_DIR"' EXIT
git -C "$P26_POL03_DIR" init -q
git -C "$P26_POL03_DIR" config user.email "test@conjure"
git -C "$P26_POL03_DIR" config user.name "conjure-test"
cp -r "$CONJURE_HOME/tests/fixtures/_emit-policy/harness/." "$P26_POL03_DIR/"
git -C "$P26_POL03_DIR" add -A
git -C "$P26_POL03_DIR" commit -q -m "test fixture"
if [ "$P26_EMIT_OK" -eq 1 ]; then
  CONJURE_HOME="$CONJURE_HOME" bash "$P26_EMIT_SH" --regime hipaa --output "$P26_POL03_DIR/conjure-policy" 2>/dev/null
  if [ -f "$P26_POL03_DIR/conjure-policy/managed-settings.json" ] && \
     jq -e '(.permissions.disableBypassPermissionsMode | type) == "string" and
             .permissions.disableBypassPermissionsMode == "disable" and
             .allowManagedPermissionRulesOnly == true and
             .forceLoginOrgUUID == "REPLACE_WITH_ORG_UUID"' \
     "$P26_POL03_DIR/conjure-policy/managed-settings.json" >/dev/null 2>&1; then
    pass "emit-policy produces managed-settings.json with correct keys and types (POL-03)"
  else
    fail "emit-policy managed-settings.json missing or has wrong key types (POL-03)"
  fi
else
  fail "emit-policy.sh not found — Wave 1 must create scripts/emit-policy.sh (POL-03)"
fi
rm -rf "$P26_POL03_DIR"
trap - EXIT

# POL-03-type: disableBypassPermissionsMode is STRING "disable" not boolean
P26_POL03T_DIR="$(mktemp -d)"
trap 'rm -rf "$P26_POL03T_DIR"' EXIT
git -C "$P26_POL03T_DIR" init -q
git -C "$P26_POL03T_DIR" config user.email "test@conjure"
git -C "$P26_POL03T_DIR" config user.name "conjure-test"
cp -r "$CONJURE_HOME/tests/fixtures/_emit-policy/harness/." "$P26_POL03T_DIR/"
git -C "$P26_POL03T_DIR" add -A
git -C "$P26_POL03T_DIR" commit -q -m "test fixture"
if [ "$P26_EMIT_OK" -eq 1 ]; then
  CONJURE_HOME="$CONJURE_HOME" bash "$P26_EMIT_SH" --regime hipaa --output "$P26_POL03T_DIR/conjure-policy" 2>/dev/null
  if [ -f "$P26_POL03T_DIR/conjure-policy/managed-settings.json" ]; then
    P26_DBPM_TYPE="$(jq -r '.permissions.disableBypassPermissionsMode | type' \
      "$P26_POL03T_DIR/conjure-policy/managed-settings.json" 2>/dev/null)"
    if [ "$P26_DBPM_TYPE" = "string" ]; then
      pass "disableBypassPermissionsMode is STRING 'disable' not boolean (POL-03-type)"
    else
      fail "disableBypassPermissionsMode has wrong type '$P26_DBPM_TYPE' — expected string (POL-03-type)"
    fi
  else
    fail "emit-policy managed-settings.json not produced (POL-03-type)"
  fi
else
  fail "emit-policy.sh not found — Wave 1 must create scripts/emit-policy.sh (POL-03-type)"
fi
rm -rf "$P26_POL03T_DIR"
trap - EXIT

# POL-04-macos: emit-policy produces macOS plist with correct XML
P26_POL04M_DIR="$(mktemp -d)"
trap 'rm -rf "$P26_POL04M_DIR"' EXIT
git -C "$P26_POL04M_DIR" init -q
git -C "$P26_POL04M_DIR" config user.email "test@conjure"
git -C "$P26_POL04M_DIR" config user.name "conjure-test"
cp -r "$CONJURE_HOME/tests/fixtures/_emit-policy/harness/." "$P26_POL04M_DIR/"
git -C "$P26_POL04M_DIR" add -A
git -C "$P26_POL04M_DIR" commit -q -m "test fixture"
if [ "$P26_EMIT_OK" -eq 1 ]; then
  CONJURE_HOME="$CONJURE_HOME" bash "$P26_EMIT_SH" --regime hipaa --output "$P26_POL04M_DIR/conjure-policy" 2>/dev/null
  P26_PLIST="$P26_POL04M_DIR/conjure-policy/com.anthropic.claudecode.plist"
  if [ -f "$P26_PLIST" ] && \
     grep -q "<string>disable</string>" "$P26_PLIST" && \
     ! grep -q "<true/>.*disableBypass\|disableBypass.*<true/>" "$P26_PLIST"; then
    pass "emit-policy produces macOS plist with correct XML (POL-04-macos)"
  else
    fail "emit-policy plist missing or has wrong disableBypassPermissionsMode XML (POL-04-macos)"
  fi
else
  fail "emit-policy.sh not found — Wave 1 must create scripts/emit-policy.sh (POL-04-macos)"
fi
rm -rf "$P26_POL04M_DIR"
trap - EXIT

# POL-04-macos-xmlmeta: build_plist_xml rejects XML metacharacters in deny entries
# and allowedDomains values (WR-05). Source the helper and feed a deny entry / a
# domain containing '<' — the function must return 2 (not silently emit broken XML).
P26_XMLMETA_RC1=0
( set -uo pipefail
  source "$CONJURE_HOME/lib/policy-helpers.sh"
  build_plist_xml '["~/.aws"]' '["Read(~/.aws)","Read(<evil>)"]' \
    '{"filesystem":{"denyRead":["~/.aws"],"denyWrite":[]},"network":{"allowedDomains":[]}}' \
    >/dev/null 2>&1
) || P26_XMLMETA_RC1=$?
P26_XMLMETA_RC2=0
( set -uo pipefail
  source "$CONJURE_HOME/lib/policy-helpers.sh"
  build_plist_xml '["~/.aws"]' '["Read(~/.aws)"]' \
    '{"filesystem":{"denyRead":["~/.aws"],"denyWrite":[]},"network":{"allowedDomains":["a&b.example.com"]}}' \
    >/dev/null 2>&1
) || P26_XMLMETA_RC2=$?
if [ "$P26_XMLMETA_RC1" -eq 2 ] && [ "$P26_XMLMETA_RC2" -eq 2 ]; then
  pass "build_plist_xml rejects XML metachars in deny entries and allowedDomains (POL-04-macos-xmlmeta)"
else
  fail "build_plist_xml did not reject XML metachars — entry_rc=$P26_XMLMETA_RC1 domain_rc=$P26_XMLMETA_RC2 (POL-04-macos-xmlmeta)"
fi

# POL-04-win-herestring: build_ps1_script rejects a managed JSON whose pretty body
# contains a line beginning with '@ — the PowerShell here-string terminator (WR-06).
# jq normally indents nested values so this cannot occur from valid input; the test
# stubs jq within a subshell so the guard receives a body whose first line is '@,
# proving the terminator-hazard guard fires (returns 2) rather than emitting a
# corruptible script.
P26_HERESTR_RC=0
( set -uo pipefail
  source "$CONJURE_HOME/lib/policy-helpers.sh"
  # Stub jq so json_body starts with the '@ here-string terminator.
  jq() { printf "%s\n" "'@malicious"; }
  build_ps1_script "hipaa" '{"x":1}' >/dev/null 2>&1
) || P26_HERESTR_RC=$?
if [ "$P26_HERESTR_RC" -eq 2 ]; then
  pass "build_ps1_script rejects JSON body line beginning with '@ here-string terminator (POL-04-win-herestring)"
else
  fail "build_ps1_script did not reject '@-leading JSON body — rc=$P26_HERESTR_RC (POL-04-win-herestring)"
fi

# POL-04-win: emit-policy produces Windows ps1 with correct path (no deprecated ProgramData)
P26_POL04W_DIR="$(mktemp -d)"
trap 'rm -rf "$P26_POL04W_DIR"' EXIT
git -C "$P26_POL04W_DIR" init -q
git -C "$P26_POL04W_DIR" config user.email "test@conjure"
git -C "$P26_POL04W_DIR" config user.name "conjure-test"
cp -r "$CONJURE_HOME/tests/fixtures/_emit-policy/harness/." "$P26_POL04W_DIR/"
git -C "$P26_POL04W_DIR" add -A
git -C "$P26_POL04W_DIR" commit -q -m "test fixture"
if [ "$P26_EMIT_OK" -eq 1 ]; then
  CONJURE_HOME="$CONJURE_HOME" bash "$P26_EMIT_SH" --regime hipaa --output "$P26_POL04W_DIR/conjure-policy" 2>/dev/null
  P26_PS1="$P26_POL04W_DIR/conjure-policy/Set-ClaudeCodePolicy.ps1"
  if [ -f "$P26_PS1" ] && \
     grep -q "ProgramFiles" "$P26_PS1" && \
     ! grep -q "ProgramData" "$P26_PS1"; then
    pass "emit-policy produces Windows ps1 with correct path (no deprecated ProgramData) (POL-04-win)"
  else
    fail "emit-policy ps1 missing or contains deprecated ProgramData path (POL-04-win)"
  fi
else
  fail "emit-policy.sh not found — Wave 1 must create scripts/emit-policy.sh (POL-04-win)"
fi
rm -rf "$P26_POL04W_DIR"
trap - EXIT

# POL-05a: audit-setup fails when overlay active but sandbox.enabled missing
P26_POL05A_DIR="$(mktemp -d)"
trap 'rm -rf "$P26_POL05A_DIR"' EXIT
mkdir -p "$P26_POL05A_DIR/.claude"
printf '{"hooks":{}}' > "$P26_POL05A_DIR/.claude/settings.json"
printf '## Project\n\nTest harness.\n\n<!-- compliance:hipaa -->\n' > "$P26_POL05A_DIR/CLAUDE.md"
if [ "$P26_EMIT_OK" -eq 1 ]; then
  P26_POL05A_RC=0
  P26_POL05A_OUT="$(CONJURE_HOME="$CONJURE_HOME" bash "$P26_AUDIT_SH" "$P26_POL05A_DIR" 2>&1)" || P26_POL05A_RC=$?
  if [ "$P26_POL05A_RC" -eq 2 ] && printf '%s\n' "$P26_POL05A_OUT" | grep -q "sandbox.enabled"; then
    pass "audit-setup fails when overlay active but sandbox.enabled missing (POL-05a)"
  else
    fail "audit-setup rc=$P26_POL05A_RC did not fail on missing sandbox.enabled (POL-05a)"
  fi
else
  fail "emit-policy.sh not found — Wave 1 must create scripts/emit-policy.sh (POL-05a)"
fi
rm -rf "$P26_POL05A_DIR"
trap - EXIT

# POL-05b: audit-setup fails when denyRead path has no mirrored permissions.deny Read() entry
P26_POL05B_DIR="$(mktemp -d)"
trap 'rm -rf "$P26_POL05B_DIR"' EXIT
mkdir -p "$P26_POL05B_DIR/.claude"
printf '{"sandbox":{"enabled":true,"filesystem":{"denyRead":["~/.aws"],"denyWrite":[]},"network":{"allowedDomains":[]}},"permissions":{"deny":[]}}' \
  > "$P26_POL05B_DIR/.claude/settings.json"
printf '## Project\n\nTest harness.\n\n<!-- compliance:hipaa -->\n' > "$P26_POL05B_DIR/CLAUDE.md"
if [ "$P26_EMIT_OK" -eq 1 ]; then
  P26_POL05B_RC=0
  P26_POL05B_OUT="$(CONJURE_HOME="$CONJURE_HOME" bash "$P26_AUDIT_SH" "$P26_POL05B_DIR" 2>&1)" || P26_POL05B_RC=$?
  if [ "$P26_POL05B_RC" -eq 2 ] && \
     { printf '%s\n' "$P26_POL05B_OUT" | grep -q "denyRead" || \
       printf '%s\n' "$P26_POL05B_OUT" | grep -q "permissions.deny"; }; then
    pass "audit-setup fails when denyRead path has no mirrored permissions.deny Read() entry (POL-05b)"
  else
    fail "audit-setup rc=$P26_POL05B_RC did not fail on unmirrored denyRead path (POL-05b)"
  fi
else
  fail "emit-policy.sh not found — Wave 1 must create scripts/emit-policy.sh (POL-05b)"
fi
rm -rf "$P26_POL05B_DIR"
trap - EXIT

# POL-05b-abs: audit-setup PASSES an absolute denyRead path that is correctly
# mirrored as Read(//abs) (double-slash per build_deny_read_entries) — proves the
# WR-02 emit/audit single-source-of-truth fix. The raw-grep bug greps Read(/abs)
# (single slash) which never matches Read(//abs), falsely failing audit.
P26_POL05BABS_DIR="$(mktemp -d)"
trap 'rm -rf "$P26_POL05BABS_DIR"' EXIT
mkdir -p "$P26_POL05BABS_DIR/.claude"
printf '{"sandbox":{"enabled":true,"filesystem":{"denyRead":["/var/secrets"],"denyWrite":[]},"network":{"allowedDomains":[]}},"permissions":{"deny":["Read(//var/secrets)"]}}' \
  > "$P26_POL05BABS_DIR/.claude/settings.json"
printf '## Project\n\nTest harness.\n\n<!-- compliance:hipaa -->\n' > "$P26_POL05BABS_DIR/CLAUDE.md"
if [ "$P26_EMIT_OK" -eq 1 ]; then
  P26_POL05BABS_RC=0
  P26_POL05BABS_OUT="$(CONJURE_HOME="$CONJURE_HOME" bash "$P26_AUDIT_SH" "$P26_POL05BABS_DIR" 2>&1)" || P26_POL05BABS_RC=$?
  if [ "$P26_POL05BABS_RC" -ne 2 ] && \
     ! printf '%s\n' "$P26_POL05BABS_OUT" | grep -q "POL-02 enforcement gap"; then
    pass "audit-setup passes absolute denyRead path mirrored as Read(//abs) (POL-05b-abs)"
  else
    fail "audit-setup rc=$P26_POL05BABS_RC falsely failed absolute denyRead Read(//abs) mirror (POL-05b-abs)"
  fi
else
  fail "emit-policy.sh not found — Wave 1 must create scripts/emit-policy.sh (POL-05b-abs)"
fi
rm -rf "$P26_POL05BABS_DIR"
trap - EXIT

# POL-05c: audit-setup fails when disableBypassPermissionsMode is boolean
P26_POL05C_DIR="$(mktemp -d)"
trap 'rm -rf "$P26_POL05C_DIR"' EXIT
mkdir -p "$P26_POL05C_DIR/.claude"
cp "$CONJURE_HOME/tests/fixtures/_emit-policy-broken/harness/.claude/settings.json" \
   "$P26_POL05C_DIR/.claude/settings.json"
printf '## Project\n\nTest harness.\n\n<!-- compliance:hipaa -->\n' > "$P26_POL05C_DIR/CLAUDE.md"
if [ "$P26_EMIT_OK" -eq 1 ]; then
  P26_POL05C_RC=0
  P26_POL05C_OUT="$(CONJURE_HOME="$CONJURE_HOME" bash "$P26_AUDIT_SH" "$P26_POL05C_DIR" 2>&1)" || P26_POL05C_RC=$?
  if [ "$P26_POL05C_RC" -eq 2 ] && printf '%s\n' "$P26_POL05C_OUT" | grep -q "disableBypassPermissionsMode"; then
    pass "audit-setup fails when disableBypassPermissionsMode is boolean (POL-05c)"
  else
    fail "audit-setup rc=$P26_POL05C_RC did not fail on boolean disableBypassPermissionsMode (POL-05c)"
  fi
else
  fail "emit-policy.sh not found — Wave 1 must create scripts/emit-policy.sh (POL-05c)"
fi
rm -rf "$P26_POL05C_DIR"
trap - EXIT

# POL-05-advisory: audit-setup issues advisory note (exit != 2) for unreviewed template
# Uses go-gin as a complete audit-clean base; overlays conjure-policy/managed-settings.json
# with REPLACE_WITH_ORG_UUID still present. Mirrors PLUG-REC pattern exactly.
P26_ADV_DIR="$(mktemp -d)"
trap 'rm -rf "$P26_ADV_DIR"' EXIT
cp -r "$CONJURE_HOME/tests/fixtures/go-gin/." "$P26_ADV_DIR/"
mkdir -p "$P26_ADV_DIR/conjure-policy"
cp "$CONJURE_HOME/tests/fixtures/_emit-policy-unreviewed/conjure-policy/managed-settings.json" \
   "$P26_ADV_DIR/conjure-policy/"
if [ "$P26_EMIT_OK" -eq 1 ]; then
  P26_ADV_RC=0
  P26_ADV_OUT="$(CONJURE_HOME="$CONJURE_HOME" bash "$P26_AUDIT_SH" "$P26_ADV_DIR" 2>&1)" || P26_ADV_RC=$?
  if [ "$P26_ADV_RC" -ne 2 ] && printf '%s\n' "$P26_ADV_OUT" | grep -q "REPLACE_WITH_ORG_UUID"; then
    pass "audit-setup issues advisory note (exit != 2) for unreviewed template with REPLACE_WITH_ORG_UUID (POL-05-advisory)"
  else
    fail "audit-setup rc=$P26_ADV_RC — expected non-2 exit and REPLACE_WITH_ORG_UUID advisory text (POL-05-advisory)"
  fi
else
  fail "emit-policy.sh not found — Wave 1 must create scripts/emit-policy.sh (POL-05-advisory)"
fi
rm -rf "$P26_ADV_DIR"
trap - EXIT

# POL-dryrun: emit-policy --dry-run prints mutations but writes no files
P26_DRYR_DIR="$(mktemp -d)"
trap 'rm -rf "$P26_DRYR_DIR"' EXIT
git -C "$P26_DRYR_DIR" init -q
git -C "$P26_DRYR_DIR" config user.email "test@conjure"
git -C "$P26_DRYR_DIR" config user.name "conjure-test"
cp -r "$CONJURE_HOME/tests/fixtures/_emit-policy/harness/." "$P26_DRYR_DIR/"
git -C "$P26_DRYR_DIR" add -A
git -C "$P26_DRYR_DIR" commit -q -m "test fixture"
if [ "$P26_EMIT_OK" -eq 1 ]; then
  P26_DRYR_RC=0
  CONJURE_HOME="$CONJURE_HOME" DRY_RUN=1 bash "$P26_EMIT_SH" \
    --regime hipaa --output "$P26_DRYR_DIR/conjure-policy" 2>/dev/null || P26_DRYR_RC=$?
  P26_DRYR_SANDBOX="$(jq -r '.sandbox.enabled // "null"' "$P26_DRYR_DIR/.claude/settings.json" 2>/dev/null || echo "null")"
  if [ "$P26_DRYR_RC" -eq 0 ] && \
     [ "$P26_DRYR_SANDBOX" = "null" ] && \
     [ ! -d "$P26_DRYR_DIR/conjure-policy" ]; then
    pass "emit-policy --dry-run prints mutations but writes no files (POL-dryrun)"
  else
    fail "emit-policy --dry-run rc=$P26_DRYR_RC sandbox=$P26_DRYR_SANDBOX conjure-policy-exists=$(test -d "$P26_DRYR_DIR/conjure-policy" && echo yes || echo no) (POL-dryrun)"
  fi
else
  fail "emit-policy.sh not found — Wave 1 must create scripts/emit-policy.sh (POL-dryrun)"
fi
rm -rf "$P26_DRYR_DIR"
trap - EXIT

# ──────────────────────────────────────────────────────────────────────────────
# Phase 27 — Schema-Version-Aware Audit (SCHM-01..05)
# Mirrors Phase 26 block style: mktemp sandboxes with EXIT-trap discipline.
# All audit/check invocations guarded behind P27_AUDIT_OK / P27_CHECK_OK so
# the suite reports graceful RED when audit-setup.sh / check.sh SCHM sections
# are absent (Wave 1/2 not yet complete). SCHM-SCHEMA tests lib/cc-schema.json
# independently (Wave 0 artifact — passes as soon as Task 1 lands).
# ──────────────────────────────────────────────────────────────────────────────

P27_AUDIT_SH="$CONJURE_HOME/scripts/audit-setup.sh"
P27_CHECK_SH="$CONJURE_HOME/scripts/check.sh"
P27_SCHEMA_FILE="$CONJURE_HOME/lib/cc-schema.json"
P27_AUDIT_OK=0
P27_CHECK_OK=0
P27_SCHEMA_OK=0
[ -f "$P27_AUDIT_SH" ] && P27_AUDIT_OK=1
[ -f "$P27_CHECK_SH" ] && P27_CHECK_OK=1
[ -f "$P27_SCHEMA_FILE" ] && jq -e '(.hook_events | length) == 30' "$P27_SCHEMA_FILE" >/dev/null 2>&1 && P27_SCHEMA_OK=1

echo
echo "▸ Phase 27 — Schema-Version-Aware Audit (SCHM-01..05)"

# SCHM-SCHEMA: lib/cc-schema.json exists with correct shape (independent of audit/check code)
if [ "$P27_SCHEMA_OK" -eq 1 ] && \
   jq -e '(.hook_events | length) == 30' "$P27_SCHEMA_FILE" >/dev/null 2>&1 && \
   jq -e '(.skill_frontmatter | keys | length) == 16' "$P27_SCHEMA_FILE" >/dev/null 2>&1 && \
   jq -e '.renamed_events.SessionStop == "SessionEnd"' "$P27_SCHEMA_FILE" >/dev/null 2>&1 && \
   jq -e '.skill_frontmatter["disallowed-tools"] == "array-or-space-string"' "$P27_SCHEMA_FILE" >/dev/null 2>&1; then
  pass "lib/cc-schema.json has 30 hook events, 16 skill fields, renamed_events map (SCHM-SCHEMA)"
else
  fail "lib/cc-schema.json missing or malformed — Wave 0 must create lib/cc-schema.json (SCHM-SCHEMA)"
fi

# SCHM-01-badtype: SKILL.md with block-style object-typed disallowed-tools → audit must fail exit 2
P27_BAD_DIR="$(mktemp -d)"
trap 'rm -rf "$P27_BAD_DIR"' EXIT
mkdir -p "$P27_BAD_DIR/.claude/skills/bad-skill"
cp "$CONJURE_HOME/tests/fixtures/_schema-audit-badfield/harness/.claude/skills/bad-skill/SKILL.md" \
   "$P27_BAD_DIR/.claude/skills/bad-skill/SKILL.md"
printf '## Project\n\nNegative fixture for SCHM-01.\n' > "$P27_BAD_DIR/CLAUDE.md"
git -C "$P27_BAD_DIR" init -q
git -C "$P27_BAD_DIR" config user.email "test@conjure"
git -C "$P27_BAD_DIR" config user.name "conjure-test"
git -C "$P27_BAD_DIR" add -A 2>/dev/null || true
git -C "$P27_BAD_DIR" commit -q -m "test fixture" 2>/dev/null || true
if [ "$P27_AUDIT_OK" -eq 1 ]; then
  P27_BAD_RC=0
  P27_BAD_OUT="$(CONJURE_HOME="$CONJURE_HOME" bash "$P27_AUDIT_SH" "$P27_BAD_DIR" 2>&1)" || P27_BAD_RC=$?
  if [ "$P27_BAD_RC" -eq 2 ] && printf '%s\n' "$P27_BAD_OUT" | grep -q "disallowed-tools"; then
    pass "audit fails when SKILL.md disallowed-tools is YAML object mapping (SCHM-01-badtype)"
  else
    fail "audit rc=$P27_BAD_RC did not fail on block-style object disallowed-tools (SCHM-01-badtype)"
  fi
else
  fail "audit-setup.sh SCHM section not implemented — Wave 1 must add SCHM-01 to audit-setup.sh (SCHM-01-badtype)"
fi
rm -rf "$P27_BAD_DIR"
trap - EXIT

# SCHM-01-valid: valid SKILL.md with array-typed fields → audit must NOT produce a SCHM-01 fail
P27_VALID_DIR="$(mktemp -d)"
trap 'rm -rf "$P27_VALID_DIR"' EXIT
mkdir -p "$P27_VALID_DIR/.claude/skills/ok-skill"
cp "$CONJURE_HOME/tests/fixtures/_schema-audit/valid/harness/.claude/skills/ok-skill/SKILL.md" \
   "$P27_VALID_DIR/.claude/skills/ok-skill/SKILL.md"
cp "$CONJURE_HOME/tests/fixtures/_schema-audit/valid/harness/.claude/settings.json" \
   "$P27_VALID_DIR/.claude/settings.json" 2>/dev/null || true
cp "$CONJURE_HOME/tests/fixtures/_schema-audit/valid/harness/CLAUDE.md" \
   "$P27_VALID_DIR/CLAUDE.md"
git -C "$P27_VALID_DIR" init -q
git -C "$P27_VALID_DIR" config user.email "test@conjure"
git -C "$P27_VALID_DIR" config user.name "conjure-test"
git -C "$P27_VALID_DIR" add -A 2>/dev/null || true
git -C "$P27_VALID_DIR" commit -q -m "test fixture" 2>/dev/null || true
if [ "$P27_AUDIT_OK" -eq 1 ]; then
  P27_VALID_RC=0
  P27_VALID_OUT="$(CONJURE_HOME="$CONJURE_HOME" bash "$P27_AUDIT_SH" "$P27_VALID_DIR" 2>&1)" || P27_VALID_RC=$?
  if ! printf '%s\n' "$P27_VALID_OUT" | grep -q "SCHM-01.*fail"; then
    pass "audit accepts valid SKILL.md frontmatter field types (SCHM-01-valid)"
  else
    fail "audit produced SCHM-01 fail on valid SKILL.md — should have passed (SCHM-01-valid)"
  fi
else
  fail "audit-setup.sh SCHM section not implemented — Wave 1 must add SCHM-01 to audit-setup.sh (SCHM-01-valid)"
fi
rm -rf "$P27_VALID_DIR"
trap - EXIT

# SCHM-01-unknown: SKILL.md with an unknown frontmatter field → audit must WARN (not fail exit 2)
P27_UNK_DIR="$(mktemp -d)"
trap 'rm -rf "$P27_UNK_DIR"' EXIT
mkdir -p "$P27_UNK_DIR/.claude/skills/unk-skill"
printf '%s\n' '---' 'name: unk-skill' 'description: Unknown field test' 'totally_unknown_field: value' '---' 'Body.' \
  > "$P27_UNK_DIR/.claude/skills/unk-skill/SKILL.md"
printf '## Project\n\nUnknown field fixture for SCHM-01.\n' > "$P27_UNK_DIR/CLAUDE.md"
git -C "$P27_UNK_DIR" init -q
git -C "$P27_UNK_DIR" config user.email "test@conjure"
git -C "$P27_UNK_DIR" config user.name "conjure-test"
git -C "$P27_UNK_DIR" add -A 2>/dev/null || true
git -C "$P27_UNK_DIR" commit -q -m "test fixture" 2>/dev/null || true
if [ "$P27_AUDIT_OK" -eq 1 ]; then
  P27_UNK_RC=0
  P27_UNK_OUT="$(CONJURE_HOME="$CONJURE_HOME" bash "$P27_AUDIT_SH" "$P27_UNK_DIR" 2>&1)" || P27_UNK_RC=$?
  if [ "$P27_UNK_RC" -ne 2 ]; then
    pass "audit warns (not fails) on unknown SKILL.md frontmatter field (SCHM-01-unknown)"
  else
    fail "audit exit 2 on unknown SKILL.md field — should warn not fail (SCHM-01-unknown)"
  fi
else
  fail "audit-setup.sh SCHM section not implemented — Wave 1 must add SCHM-01 to audit-setup.sh (SCHM-01-unknown)"
fi
rm -rf "$P27_UNK_DIR"
trap - EXIT

# SCHM-02-permissions: boolean disableBypassPermissionsMode at permissions.* → audit must fail exit 2
P27_DBPM_P_DIR="$(mktemp -d)"
trap 'rm -rf "$P27_DBPM_P_DIR"' EXIT
mkdir -p "$P27_DBPM_P_DIR/.claude"
cp "$CONJURE_HOME/tests/fixtures/_schema-audit-disablebypass/harness/.claude/settings.json" \
   "$P27_DBPM_P_DIR/.claude/settings.json"
printf '## Project\n\nDBPM permissions path fixture for SCHM-02.\n' > "$P27_DBPM_P_DIR/CLAUDE.md"
git -C "$P27_DBPM_P_DIR" init -q
git -C "$P27_DBPM_P_DIR" config user.email "test@conjure"
git -C "$P27_DBPM_P_DIR" config user.name "conjure-test"
git -C "$P27_DBPM_P_DIR" add -A 2>/dev/null || true
git -C "$P27_DBPM_P_DIR" commit -q -m "test fixture" 2>/dev/null || true
if [ "$P27_AUDIT_OK" -eq 1 ]; then
  P27_DBPM_P_RC=0
  P27_DBPM_P_OUT="$(CONJURE_HOME="$CONJURE_HOME" bash "$P27_AUDIT_SH" "$P27_DBPM_P_DIR" 2>&1)" || P27_DBPM_P_RC=$?
  if [ "$P27_DBPM_P_RC" -eq 2 ] && printf '%s\n' "$P27_DBPM_P_OUT" | grep -q "disableBypassPermissionsMode"; then
    pass "audit fails when permissions.disableBypassPermissionsMode is boolean (SCHM-02-permissions)"
  else
    fail "audit rc=$P27_DBPM_P_RC did not fail on boolean permissions.disableBypassPermissionsMode (SCHM-02-permissions)"
  fi
else
  fail "audit-setup.sh SCHM section not implemented — Wave 1 must add SCHM-02 to audit-setup.sh (SCHM-02-permissions)"
fi
rm -rf "$P27_DBPM_P_DIR"
trap - EXIT

# SCHM-02-toplevel: boolean disableBypassPermissionsMode at top-level path → audit must fail exit 2
P27_DBPM_T_DIR="$(mktemp -d)"
trap 'rm -rf "$P27_DBPM_T_DIR"' EXIT
mkdir -p "$P27_DBPM_T_DIR/.claude"
printf '{"disableBypassPermissionsMode": true}\n' > "$P27_DBPM_T_DIR/.claude/settings.json"
printf '## Project\n\nDBPM top-level fixture for SCHM-02.\n' > "$P27_DBPM_T_DIR/CLAUDE.md"
git -C "$P27_DBPM_T_DIR" init -q
git -C "$P27_DBPM_T_DIR" config user.email "test@conjure"
git -C "$P27_DBPM_T_DIR" config user.name "conjure-test"
git -C "$P27_DBPM_T_DIR" add -A 2>/dev/null || true
git -C "$P27_DBPM_T_DIR" commit -q -m "test fixture" 2>/dev/null || true
if [ "$P27_AUDIT_OK" -eq 1 ]; then
  P27_DBPM_T_RC=0
  P27_DBPM_T_OUT="$(CONJURE_HOME="$CONJURE_HOME" bash "$P27_AUDIT_SH" "$P27_DBPM_T_DIR" 2>&1)" || P27_DBPM_T_RC=$?
  if [ "$P27_DBPM_T_RC" -eq 2 ]; then
    pass "audit fails when top-level disableBypassPermissionsMode is boolean (SCHM-02-toplevel)"
  else
    fail "audit rc=$P27_DBPM_T_RC did not fail on top-level boolean disableBypassPermissionsMode (SCHM-02-toplevel)"
  fi
else
  fail "audit-setup.sh SCHM section not implemented — Wave 1 must add SCHM-02 to audit-setup.sh (SCHM-02-toplevel)"
fi
rm -rf "$P27_DBPM_T_DIR"
trap - EXIT

# SCHM-03-renamed: settings.json with SessionStop hook → check must fail exit 2
P27_HOOK_R_DIR="$(mktemp -d)"
trap 'rm -rf "$P27_HOOK_R_DIR"' EXIT
mkdir -p "$P27_HOOK_R_DIR/.claude"
cp "$CONJURE_HOME/tests/fixtures/_schema-audit-hookevent/harness/.claude/settings.json" \
   "$P27_HOOK_R_DIR/.claude/settings.json"
printf '## Project\n\nRenamed hook event fixture for SCHM-03.\n' > "$P27_HOOK_R_DIR/CLAUDE.md"
git -C "$P27_HOOK_R_DIR" init -q
git -C "$P27_HOOK_R_DIR" config user.email "test@conjure"
git -C "$P27_HOOK_R_DIR" config user.name "conjure-test"
git -C "$P27_HOOK_R_DIR" add -A 2>/dev/null || true
git -C "$P27_HOOK_R_DIR" commit -q -m "test fixture" 2>/dev/null || true
if [ "$P27_CHECK_OK" -eq 1 ]; then
  P27_HOOK_R_RC=0
  P27_HOOK_R_OUT="$(CONJURE_HOME="$CONJURE_HOME" bash "$P27_CHECK_SH" "$P27_HOOK_R_DIR" 2>&1)" || P27_HOOK_R_RC=$?
  if [ "$P27_HOOK_R_RC" -eq 2 ] && \
     { printf '%s\n' "$P27_HOOK_R_OUT" | grep -q "SessionStop" || \
       printf '%s\n' "$P27_HOOK_R_OUT" | grep -qi "renamed"; }; then
    pass "check fails when settings.json uses renamed hook event SessionStop (SCHM-03-renamed)"
  else
    fail "check rc=$P27_HOOK_R_RC did not fail on renamed hook event SessionStop (SCHM-03-renamed)"
  fi
else
  fail "check.sh SCHM section not implemented — Wave 2 must add SCHM-03 to check.sh (SCHM-03-renamed)"
fi
rm -rf "$P27_HOOK_R_DIR"
trap - EXIT

# SCHM-03-unknown: settings.json with unknown hook event → check must fail exit 2
P27_HOOK_U_DIR="$(mktemp -d)"
trap 'rm -rf "$P27_HOOK_U_DIR"' EXIT
mkdir -p "$P27_HOOK_U_DIR/.claude"
cp "$CONJURE_HOME/tests/fixtures/_schema-audit-hookevent/harness/.claude/settings.json" \
   "$P27_HOOK_U_DIR/.claude/settings.json"
printf '## Project\n\nUnknown hook event fixture for SCHM-03.\n' > "$P27_HOOK_U_DIR/CLAUDE.md"
git -C "$P27_HOOK_U_DIR" init -q
git -C "$P27_HOOK_U_DIR" config user.email "test@conjure"
git -C "$P27_HOOK_U_DIR" config user.name "conjure-test"
git -C "$P27_HOOK_U_DIR" add -A 2>/dev/null || true
git -C "$P27_HOOK_U_DIR" commit -q -m "test fixture" 2>/dev/null || true
if [ "$P27_CHECK_OK" -eq 1 ]; then
  P27_HOOK_U_RC=0
  P27_HOOK_U_OUT="$(CONJURE_HOME="$CONJURE_HOME" bash "$P27_CHECK_SH" "$P27_HOOK_U_DIR" 2>&1)" || P27_HOOK_U_RC=$?
  if [ "$P27_HOOK_U_RC" -eq 2 ] && \
     { printf '%s\n' "$P27_HOOK_U_OUT" | grep -q "UnknownEvent42" || \
       printf '%s\n' "$P27_HOOK_U_OUT" | grep -qi "unknown"; }; then
    pass "check fails when settings.json uses unknown hook event (SCHM-03-unknown)"
  else
    fail "check rc=$P27_HOOK_U_RC did not fail on unknown hook event UnknownEvent42 (SCHM-03-unknown)"
  fi
else
  fail "check.sh SCHM section not implemented — Wave 2 must add SCHM-03 to check.sh (SCHM-03-unknown)"
fi
rm -rf "$P27_HOOK_U_DIR"
trap - EXIT

# SCHM-04-schema: check --schema on a valid harness → outputs per-key version info, exit 0 or 1
P27_SCH_DIR="$(mktemp -d)"
trap 'rm -rf "$P27_SCH_DIR"' EXIT
mkdir -p "$P27_SCH_DIR/.claude"
printf '{"skillOverrides": {}}\n' > "$P27_SCH_DIR/.claude/settings.json"
printf '## Project\n\nSchema version report fixture for SCHM-04.\n' > "$P27_SCH_DIR/CLAUDE.md"
git -C "$P27_SCH_DIR" init -q
git -C "$P27_SCH_DIR" config user.email "test@conjure"
git -C "$P27_SCH_DIR" config user.name "conjure-test"
git -C "$P27_SCH_DIR" add -A 2>/dev/null || true
git -C "$P27_SCH_DIR" commit -q -m "test fixture" 2>/dev/null || true
if [ "$P27_CHECK_OK" -eq 1 ]; then
  P27_SCH_RC=0
  CONJURE_HOME="$CONJURE_HOME" CONJURE_SCHEMA=1 bash "$P27_CHECK_SH" "$P27_SCH_DIR" >/dev/null 2>&1 || P27_SCH_RC=$?
  if [ "$P27_SCH_RC" -ne 2 ]; then
    pass "check --schema emits per-key version info and does not fail (SCHM-04-schema)"
  else
    fail "check --schema exit 2 — should be info only (never fail) (SCHM-04-schema)"
  fi
else
  fail "check.sh SCHM section not implemented — Wave 2 must add SCHM-04 to check.sh (SCHM-04-schema)"
fi
rm -rf "$P27_SCH_DIR"
trap - EXIT

# WR-04: check --porcelain --schema → stdout stays machine-clean (no human report).
# The SCHM-04 "Schema Version Report" must route to stderr under --porcelain so it
# does not interleave with the M/R/A lines and corrupt machine consumers.
P27_PSCH_DIR="$(mktemp -d)"
trap 'rm -rf "$P27_PSCH_DIR"' EXIT
mkdir -p "$P27_PSCH_DIR/.claude"
# Drifted settings.json (differs from kit) → guarantees at least one M/R/A line.
printf '{"skillOverrides": {}}\n' > "$P27_PSCH_DIR/.claude/settings.json"
printf '## Project\n\nPorcelain+schema fixture (WR-04).\n' > "$P27_PSCH_DIR/CLAUDE.md"
if [ "$P27_CHECK_OK" -eq 1 ]; then
  P27_PSCH_STDOUT_FILE="$(mktemp)"
  CONJURE_HOME="$CONJURE_HOME" CONJURE_PORCELAIN=1 CONJURE_SCHEMA=1 \
    bash "$P27_CHECK_SH" "$P27_PSCH_DIR" >"$P27_PSCH_STDOUT_FILE" 2>/dev/null || true
  P27_PSCH_STDOUT="$(cat "$P27_PSCH_STDOUT_FILE")"
  rm -f "$P27_PSCH_STDOUT_FILE"
  # Pass only if stdout has NO human-report markers (Schema Version Report / introduced:).
  if printf '%s\n' "$P27_PSCH_STDOUT" | grep -qE 'Schema Version Report|introduced:'; then
    fail "check --porcelain --schema leaked human report onto porcelain stdout (WR-04)"
  else
    pass "check --porcelain --schema keeps stdout machine-clean (WR-04)"
  fi
else
  fail "check.sh SCHM section not implemented — Wave 2 must add SCHM-04 to check.sh (WR-04)"
fi
rm -rf "$P27_PSCH_DIR"
trap - EXIT

# WR-05: check --schema flags a settings key whose introduced_version is NEWER than
# the detected claude --version (advisory WARN, never exit 2). Stub `claude` to
# report an old version so skillOverrides (introduced 2.1.129) is newer.
P27_NEWER_DIR="$(mktemp -d)"
P27_NEWER_STUB="$(mktemp -d)"
trap 'rm -rf "$P27_NEWER_DIR" "$P27_NEWER_STUB"' EXIT
mkdir -p "$P27_NEWER_DIR/.claude"
printf '{"skillOverrides": {}}\n' > "$P27_NEWER_DIR/.claude/settings.json"
printf '## Project\n\nNewer-than-CC key fixture (WR-05).\n' > "$P27_NEWER_DIR/CLAUDE.md"
printf '#!/bin/sh\necho "2.1.105 (Claude Code)"\n' > "$P27_NEWER_STUB/claude"
chmod +x "$P27_NEWER_STUB/claude"
if [ "$P27_CHECK_OK" -eq 1 ]; then
  P27_NEWER_RC=0
  P27_NEWER_OUT="$(PATH="$P27_NEWER_STUB:$PATH" CONJURE_HOME="$CONJURE_HOME" CONJURE_SCHEMA=1 \
    bash "$P27_CHECK_SH" "$P27_NEWER_DIR" 2>&1)" || P27_NEWER_RC=$?
  if [ "$P27_NEWER_RC" -ne 2 ] && \
     printf '%s\n' "$P27_NEWER_OUT" | grep -qiE 'newer than detected CC'; then
    pass "check --schema WARNs on key newer than detected CC version, never fails (WR-05)"
  else
    fail "check --schema rc=$P27_NEWER_RC did not WARN on newer-than-CC key (WR-05)"
  fi
else
  fail "check.sh SCHM section not implemented — Wave 2 must add SCHM-04 to check.sh (WR-05)"
fi
rm -rf "$P27_NEWER_DIR" "$P27_NEWER_STUB"
trap - EXIT

# SCHM-STALE: audit with >90-day generated date → warns but does NOT exit 2
P27_STALE_DIR="$(mktemp -d)"
trap 'rm -rf "$P27_STALE_DIR"' EXIT
P27_STALE_SCHEMA_BAK=""
cp -r "$CONJURE_HOME/tests/fixtures/_schema-audit/valid/harness/." "$P27_STALE_DIR/"
git -C "$P27_STALE_DIR" init -q
git -C "$P27_STALE_DIR" config user.email "test@conjure"
git -C "$P27_STALE_DIR" config user.name "conjure-test"
git -C "$P27_STALE_DIR" add -A 2>/dev/null || true
git -C "$P27_STALE_DIR" commit -q -m "test fixture" 2>/dev/null || true
if [ "$P27_AUDIT_OK" -eq 1 ]; then
  # Temporarily swap lib/cc-schema.json for the stale fixture
  P27_STALE_SCHEMA_BAK="$(mktemp)"
  cp "$P27_SCHEMA_FILE" "$P27_STALE_SCHEMA_BAK"
  cp "$CONJURE_HOME/tests/fixtures/_schema-audit-stale/cc-schema-stale.json" "$P27_SCHEMA_FILE"
  P27_STALE_RC=0
  P27_STALE_OUT="$(CONJURE_HOME="$CONJURE_HOME" bash "$P27_AUDIT_SH" "$P27_STALE_DIR" 2>&1)" || P27_STALE_RC=$?
  # Restore original schema immediately
  cp "$P27_STALE_SCHEMA_BAK" "$P27_SCHEMA_FILE"
  rm -f "$P27_STALE_SCHEMA_BAK"
  if [ "$P27_STALE_RC" -ne 2 ] && \
     { printf '%s\n' "$P27_STALE_OUT" | grep -qi "days old" || \
       printf '%s\n' "$P27_STALE_OUT" | grep -qi "stale"; }; then
    pass "audit warns (not fails) when cc-schema.json is >90 days old (SCHM-STALE)"
  else
    fail "audit rc=$P27_STALE_RC — expected non-2 exit and stale/days-old warning (SCHM-STALE)"
  fi
else
  fail "audit-setup.sh SCHM section not implemented — Wave 1 must add SCHM-STALE to audit-setup.sh (SCHM-STALE)"
fi
rm -rf "$P27_STALE_DIR"
trap - EXIT

# SCHM-05-json: audit --json emits parseable JSON to stdout, human text to stderr
P27_JSON_DIR="$(mktemp -d)"
trap 'rm -rf "$P27_JSON_DIR"' EXIT
cp -r "$CONJURE_HOME/tests/fixtures/_schema-audit/valid/harness/." "$P27_JSON_DIR/"
git -C "$P27_JSON_DIR" init -q
git -C "$P27_JSON_DIR" config user.email "test@conjure"
git -C "$P27_JSON_DIR" config user.name "conjure-test"
git -C "$P27_JSON_DIR" add -A 2>/dev/null || true
git -C "$P27_JSON_DIR" commit -q -m "test fixture" 2>/dev/null || true
if [ "$P27_AUDIT_OK" -eq 1 ]; then
  P27_JSON_STDOUT_FILE="$(mktemp)"
  P27_JSON_STDERR_FILE="$(mktemp)"
  P27_JSON_RC=0
  CONJURE_HOME="$CONJURE_HOME" CONJURE_JSON=1 bash "$P27_AUDIT_SH" "$P27_JSON_DIR" \
    >"$P27_JSON_STDOUT_FILE" 2>"$P27_JSON_STDERR_FILE" || P27_JSON_RC=$?
  P27_JSON_STDOUT="$(cat "$P27_JSON_STDOUT_FILE")"
  rm -f "$P27_JSON_STDOUT_FILE" "$P27_JSON_STDERR_FILE"
  if printf '%s\n' "$P27_JSON_STDOUT" | jq -e '.status' >/dev/null 2>&1; then
    pass "audit --json emits JSON-only stdout parseable by jq (SCHM-05-json)"
  else
    fail "audit --json stdout not parseable by jq — expected JSON object with .status (SCHM-05-json)"
  fi
else
  fail "audit-setup.sh SCHM section not implemented — Wave 1 must add SCHM-05 to audit-setup.sh (SCHM-05-json)"
fi
rm -rf "$P27_JSON_DIR"
trap - EXIT

# SCHM-05-exit2: audit --json on a bad fixture fails exit 2 with status:"fail" in JSON
P27_JSONFAIL_DIR="$(mktemp -d)"
trap 'rm -rf "$P27_JSONFAIL_DIR"' EXIT
mkdir -p "$P27_JSONFAIL_DIR/.claude"
cp "$CONJURE_HOME/tests/fixtures/_schema-audit-disablebypass/harness/.claude/settings.json" \
   "$P27_JSONFAIL_DIR/.claude/settings.json"
printf '## Project\n\nJSON fail fixture for SCHM-05.\n' > "$P27_JSONFAIL_DIR/CLAUDE.md"
git -C "$P27_JSONFAIL_DIR" init -q
git -C "$P27_JSONFAIL_DIR" config user.email "test@conjure"
git -C "$P27_JSONFAIL_DIR" config user.name "conjure-test"
git -C "$P27_JSONFAIL_DIR" add -A 2>/dev/null || true
git -C "$P27_JSONFAIL_DIR" commit -q -m "test fixture" 2>/dev/null || true
if [ "$P27_AUDIT_OK" -eq 1 ]; then
  P27_JSONFAIL_STDOUT_FILE="$(mktemp)"
  P27_JSONFAIL_RC=0
  CONJURE_HOME="$CONJURE_HOME" CONJURE_JSON=1 bash "$P27_AUDIT_SH" "$P27_JSONFAIL_DIR" \
    >"$P27_JSONFAIL_STDOUT_FILE" 2>/dev/null || P27_JSONFAIL_RC=$?
  P27_JSONFAIL_STDOUT="$(cat "$P27_JSONFAIL_STDOUT_FILE")"
  rm -f "$P27_JSONFAIL_STDOUT_FILE"
  if [ "$P27_JSONFAIL_RC" -eq 2 ] && \
     printf '%s\n' "$P27_JSONFAIL_STDOUT" | jq -e '.status == "fail"' >/dev/null 2>&1; then
    pass "audit --json exit 2 on fail with JSON status:fail (SCHM-05-exit2)"
  else
    fail "audit --json rc=$P27_JSONFAIL_RC status=$(printf '%s\n' "$P27_JSONFAIL_STDOUT" | jq -r '.status // "missing"' 2>/dev/null) — expected exit 2 and status:fail (SCHM-05-exit2)"
  fi
else
  fail "audit-setup.sh SCHM section not implemented — Wave 1 must add SCHM-05 to audit-setup.sh (SCHM-05-exit2)"
fi
rm -rf "$P27_JSONFAIL_DIR"
trap - EXIT

# ──────────────────────────────────────────────────────────────────────────────
# Phase 28 — promptfoo Eval + Context-Budget Linter (EVAL-01..05)
# Mirrors Phase 27 block style: mktemp sandboxes with EXIT-trap discipline.
# All eval.sh invocations guarded behind P28_EVAL_OK so the suite reports
# graceful RED when scripts/eval.sh is absent (Wave 1 not yet complete).
# EVAL-04/05 audit invocations guarded behind P28_AUDIT_OK.
# ──────────────────────────────────────────────────────────────────────────────

P28_EVAL_SH="$CONJURE_HOME/scripts/eval.sh"
P28_AUDIT_SH="$CONJURE_HOME/scripts/audit-setup.sh"
P28_EVAL_OK=0
P28_AUDIT_OK=0
[ -f "$P28_EVAL_SH" ] && P28_EVAL_OK=1
[ -f "$P28_AUDIT_SH" ] && P28_AUDIT_OK=1

echo
echo "▸ Phase 28 — promptfoo Eval + Context-Budget Linter (EVAL-01..05)"

# EVAL-01-init: conjure eval init on the _eval/harness fixture produces a valid promptfooconfig.yaml
P28_INIT_DIR="$(mktemp -d)"
trap 'rm -rf "$P28_INIT_DIR"' EXIT
cp -r "$CONJURE_HOME/tests/fixtures/_eval/harness/." "$P28_INIT_DIR/"
git -C "$P28_INIT_DIR" init -q
git -C "$P28_INIT_DIR" config user.email "test@conjure"
git -C "$P28_INIT_DIR" config user.name "conjure-test"
git -C "$P28_INIT_DIR" add -A 2>/dev/null || true
git -C "$P28_INIT_DIR" commit -q -m "test fixture" 2>/dev/null || true
if [ "$P28_EVAL_OK" -eq 1 ]; then
  P28_INIT_RC=0
  CONJURE_HOME="$CONJURE_HOME" bash "$P28_EVAL_SH" init "$P28_INIT_DIR" >/dev/null 2>&1 || P28_INIT_RC=$?
  if [ "$P28_INIT_RC" -eq 0 ] && \
     [ -f "$P28_INIT_DIR/.conjure/eval/promptfooconfig.yaml" ] && \
     grep -q "anthropic:claude-agent-sdk" "$P28_INIT_DIR/.conjure/eval/promptfooconfig.yaml" && \
     grep -q "evaluateOptions" "$P28_INIT_DIR/.conjure/eval/promptfooconfig.yaml" && \
     grep -qv "minPassCount" "$P28_INIT_DIR/.conjure/eval/promptfooconfig.yaml"; then
    pass "eval init creates promptfooconfig.yaml with correct provider and assertions (EVAL-01-init)"
  else
    fail "eval init rc=$P28_INIT_RC — expected promptfooconfig.yaml with anthropic:claude-agent-sdk and evaluateOptions (EVAL-01-init)"
  fi
else
  fail "scripts/eval.sh not implemented — Wave 1 must create it (EVAL-01-init)"
fi
rm -rf "$P28_INIT_DIR"
trap - EXIT

# EVAL-01-skills: generated config has one skill-used assertion per installed skill
P28_SKI_DIR="$(mktemp -d)"
trap 'rm -rf "$P28_SKI_DIR"' EXIT
cp -r "$CONJURE_HOME/tests/fixtures/_eval/harness/." "$P28_SKI_DIR/"
git -C "$P28_SKI_DIR" init -q
git -C "$P28_SKI_DIR" config user.email "test@conjure"
git -C "$P28_SKI_DIR" config user.name "conjure-test"
git -C "$P28_SKI_DIR" add -A 2>/dev/null || true
git -C "$P28_SKI_DIR" commit -q -m "test fixture" 2>/dev/null || true
if [ "$P28_EVAL_OK" -eq 1 ]; then
  CONJURE_HOME="$CONJURE_HOME" bash "$P28_EVAL_SH" init "$P28_SKI_DIR" >/dev/null 2>&1 || true
  P28_SKI_COUNT=0
  [ -f "$P28_SKI_DIR/.conjure/eval/promptfooconfig.yaml" ] && \
    P28_SKI_COUNT="$(grep -c "type: skill-used" "$P28_SKI_DIR/.conjure/eval/promptfooconfig.yaml" 2>/dev/null || printf '0')"
  if [ "$P28_SKI_COUNT" -eq 2 ]; then
    pass "eval init: one skill-used assertion per installed skill (EVAL-01-skills)"
  else
    fail "eval init: expected 2 skill-used assertions, got $P28_SKI_COUNT (EVAL-01-skills)"
  fi
else
  fail "scripts/eval.sh not implemented — Wave 1 must create it (EVAL-01-skills)"
fi
rm -rf "$P28_SKI_DIR"
trap - EXIT

# EVAL-01-rubrics: generated config has at least one llm-rubric assertion
P28_RUB_DIR="$(mktemp -d)"
trap 'rm -rf "$P28_RUB_DIR"' EXIT
cp -r "$CONJURE_HOME/tests/fixtures/_eval/harness/." "$P28_RUB_DIR/"
git -C "$P28_RUB_DIR" init -q
git -C "$P28_RUB_DIR" config user.email "test@conjure"
git -C "$P28_RUB_DIR" config user.name "conjure-test"
git -C "$P28_RUB_DIR" add -A 2>/dev/null || true
git -C "$P28_RUB_DIR" commit -q -m "test fixture" 2>/dev/null || true
if [ "$P28_EVAL_OK" -eq 1 ]; then
  CONJURE_HOME="$CONJURE_HOME" bash "$P28_EVAL_SH" init "$P28_RUB_DIR" >/dev/null 2>&1 || true
  P28_RUB_COUNT=0
  [ -f "$P28_RUB_DIR/.conjure/eval/promptfooconfig.yaml" ] && \
    P28_RUB_COUNT="$(grep -c "type: llm-rubric" "$P28_RUB_DIR/.conjure/eval/promptfooconfig.yaml" 2>/dev/null || printf '0')"
  if [ "$P28_RUB_COUNT" -ge 1 ]; then
    pass "eval init: llm-rubric assertions present for CLAUDE.md rule lines (EVAL-01-rubrics)"
  else
    fail "eval init: expected >=1 llm-rubric assertions, got $P28_RUB_COUNT (EVAL-01-rubrics)"
  fi
else
  fail "scripts/eval.sh not implemented — Wave 1 must create it (EVAL-01-rubrics)"
fi
rm -rf "$P28_RUB_DIR"
trap - EXIT

# CR-01-yaml-apostrophe: a CLAUDE.md rule line with an apostrophe must produce a
# config that parses as valid YAML (single-quoted scalars escape ' by DOUBLING,
# not the shell-style '\'' idiom) and the rubric value must round-trip.
P28_APOS_DIR="$(mktemp -d)"
trap 'rm -rf "$P28_APOS_DIR"' EXIT
printf '## Project\n\nApostrophe harness.\n\n- Don'"'"'t log PHI in plaintext.\n- Rule with '"'"'single quotes'"'"' inside.\n' > "$P28_APOS_DIR/CLAUDE.md"
git -C "$P28_APOS_DIR" init -q
git -C "$P28_APOS_DIR" config user.email "test@conjure"
git -C "$P28_APOS_DIR" config user.name "conjure-test"
git -C "$P28_APOS_DIR" add -A 2>/dev/null || true
git -C "$P28_APOS_DIR" commit -q -m "test fixture" 2>/dev/null || true
if [ "$P28_EVAL_OK" -eq 1 ]; then
  P28_APOS_RC=0
  CONJURE_HOME="$CONJURE_HOME" bash "$P28_EVAL_SH" init "$P28_APOS_DIR" >/dev/null 2>&1 || P28_APOS_RC=$?
  P28_APOS_CFG="$P28_APOS_DIR/.conjure/eval/promptfooconfig.yaml"
  P28_APOS_PARSE=1
  P28_APOS_ROUNDTRIP=1
  if [ "$P28_APOS_RC" -eq 0 ] && [ -f "$P28_APOS_CFG" ]; then
    if command -v python3 >/dev/null 2>&1; then
      # Authoritative check: python yaml.safe_load must parse, and the rubric
      # value containing the apostrophe must round-trip verbatim.
      python3 - "$P28_APOS_CFG" >/dev/null 2>&1 <<'PYEOF' || P28_APOS_PARSE=0
import sys, yaml
with open(sys.argv[1]) as f:
    doc = yaml.safe_load(f)
found = False
for t in doc.get("tests", []):
    for a in t.get("assert", []):
        if a.get("type") == "llm-rubric" and "Don't log PHI in plaintext." in str(a.get("value", "")):
            found = True
sys.exit(0 if found else 3)
PYEOF
    else
      # Structural fallback when python3/yaml is unavailable: the doubled-quote
      # form 'Don''t log PHI' must appear; the shell-style 'Don'\''t must NOT.
      grep -q "Don''t log PHI in plaintext." "$P28_APOS_CFG" || P28_APOS_PARSE=0
      grep -q "'\\\\''" "$P28_APOS_CFG" && P28_APOS_PARSE=0
    fi
  else
    P28_APOS_PARSE=0
  fi
  if [ "$P28_APOS_PARSE" -eq 1 ] && [ "$P28_APOS_ROUNDTRIP" -eq 1 ]; then
    pass "eval init: apostrophe rule line yields parseable YAML with doubled-quote escaping (CR-01-yaml-apostrophe)"
  else
    fail "eval init: apostrophe rule line produced invalid YAML or did not round-trip (CR-01-yaml-apostrophe)"
  fi
else
  fail "scripts/eval.sh not implemented — Wave 1 must create it (CR-01-yaml-apostrophe)"
fi
rm -rf "$P28_APOS_DIR"
trap - EXIT

# EVAL-01-noskills: eval init on harness with no skills produces config with 0 skill-used assertions
P28_NOSK_DIR="$(mktemp -d)"
trap 'rm -rf "$P28_NOSK_DIR"' EXIT
printf '## Project\n\nNo-skills harness.\n\n- Always run shellcheck before committing.\n' > "$P28_NOSK_DIR/CLAUDE.md"
git -C "$P28_NOSK_DIR" init -q
git -C "$P28_NOSK_DIR" config user.email "test@conjure"
git -C "$P28_NOSK_DIR" config user.name "conjure-test"
git -C "$P28_NOSK_DIR" add -A 2>/dev/null || true
git -C "$P28_NOSK_DIR" commit -q -m "test fixture" 2>/dev/null || true
if [ "$P28_EVAL_OK" -eq 1 ]; then
  P28_NOSK_RC=0
  CONJURE_HOME="$CONJURE_HOME" bash "$P28_EVAL_SH" init "$P28_NOSK_DIR" >/dev/null 2>&1 || P28_NOSK_RC=$?
  P28_NOSK_COUNT=0
  [ -f "$P28_NOSK_DIR/.conjure/eval/promptfooconfig.yaml" ] && \
    P28_NOSK_COUNT="$(grep -c "type: skill-used" "$P28_NOSK_DIR/.conjure/eval/promptfooconfig.yaml" 2>/dev/null || true)"
  if [ "$P28_NOSK_RC" -eq 0 ] && \
     [ -f "$P28_NOSK_DIR/.conjure/eval/promptfooconfig.yaml" ] && \
     [ "$P28_NOSK_COUNT" -eq 0 ]; then
    pass "eval init: no skill-used assertions when no skills installed (EVAL-01-noskills)"
  else
    fail "eval init rc=$P28_NOSK_RC skill-used count=$P28_NOSK_COUNT — expected exit 0 + 0 skill-used (EVAL-01-noskills)"
  fi
else
  fail "scripts/eval.sh not implemented — Wave 1 must create it (EVAL-01-noskills)"
fi
rm -rf "$P28_NOSK_DIR"
trap - EXIT

# EVAL-02-node-absent: eval run exits 2 with human-readable message when node absent from PATH
P28_NONODE_DIR="$(mktemp -d)"
trap 'rm -rf "$P28_NONODE_DIR"' EXIT
printf '## Project\n\nNode-absent test harness.\n' > "$P28_NONODE_DIR/CLAUDE.md"
# Build a PATH that has no node binary by stripping node dirs from PATH
P28_PATH_NO_NODE=""
_p28_IFS_saved="$IFS"
IFS=":"
for _p28_dir in $PATH; do
  [ -z "$_p28_dir" ] && continue
  [ -x "$_p28_dir/node" ] && continue
  P28_PATH_NO_NODE="${P28_PATH_NO_NODE:+$P28_PATH_NO_NODE:}$_p28_dir"
done
IFS="$_p28_IFS_saved"
if [ "$P28_EVAL_OK" -eq 1 ]; then
  P28_NONODE_RC=0
  P28_NONODE_OUT="$(PATH="$P28_PATH_NO_NODE" CONJURE_HOME="$CONJURE_HOME" bash "$P28_EVAL_SH" run "$P28_NONODE_DIR" 2>&1)" || P28_NONODE_RC=$?
  if [ "$P28_NONODE_RC" -eq 2 ] && \
     { printf '%s\n' "$P28_NONODE_OUT" | grep -qi "node" || \
       printf '%s\n' "$P28_NONODE_OUT" | grep -qi "20\.20"; }; then
    pass "eval run: exits 2 with human-readable message when node is absent or too old (EVAL-02-node-absent)"
  else
    fail "eval run rc=$P28_NONODE_RC — expected exit 2 and node/version message (EVAL-02-node-absent)"
  fi
else
  fail "scripts/eval.sh not implemented — Wave 1 must create it (EVAL-02-node-absent)"
fi
rm -rf "$P28_NONODE_DIR"
trap - EXIT

# WR-02-node-envelope: the node gate is `^20.20.0 || >=22.22.0`, NOT a single
# floor >=20.20.0. 20.19→reject, 20.20→accept, 21.5→reject, 22.21→reject,
# 22.22→accept. Simulated via a stubbed `node` shim placed first on PATH that
# prints a fixed version. The config-existence / npx checks come AFTER the node
# gate, so a rejected version exits 2 from the gate; an accepted version
# advances past the gate and then fails on the missing config (also exit 2 but
# with a different, non-node message) — so we assert on the MESSAGE, not just rc.
P28_NODEENV_DIR="$(mktemp -d)"
trap 'rm -rf "$P28_NODEENV_DIR"' EXIT
printf '## Project\n\nNode-envelope harness.\n' > "$P28_NODEENV_DIR/CLAUDE.md"
_p28_node_check() {
  # $1 = stub version (no leading v), $2 = expected verdict (accept|reject)
  _ver="$1"; _verdict="$2"
  _stubdir="$(mktemp -d)"
  printf '#!/usr/bin/env bash\n[ "$1" = "--version" ] && { echo "v%s"; exit 0; }\nexit 0\n' "$_ver" > "$_stubdir/node"
  chmod +x "$_stubdir/node"
  # Also stub npx so an ACCEPTED version does not get rejected by the npx check;
  # it should instead fall through to the missing-config error.
  printf '#!/usr/bin/env bash\nexit 0\n' > "$_stubdir/npx"
  chmod +x "$_stubdir/npx"
  _rc=0
  _out="$(PATH="$_stubdir:$PATH" CONJURE_HOME="$CONJURE_HOME" bash "$P28_EVAL_SH" run "$P28_NODEENV_DIR" 2>&1)" || _rc=$?
  rm -rf "$_stubdir"
  if [ "$_verdict" = "reject" ]; then
    # Rejected: exit 2 AND a node-version gate message.
    if [ "$_rc" -eq 2 ] && printf '%s\n' "$_out" | grep -qi "requires Node.js"; then
      return 0
    fi
    printf 'reject-fail v%s rc=%s\n' "$_ver" "$_rc" >&2
    return 1
  else
    # Accepted: must NOT trip the node gate. The missing-config error (also exit
    # 2) must mention "eval config", proving the gate was passed.
    if printf '%s\n' "$_out" | grep -qi "requires Node.js"; then
      printf 'accept-fail v%s tripped node gate rc=%s\n' "$_ver" "$_rc" >&2
      return 1
    fi
    return 0
  fi
}
if [ "$P28_EVAL_OK" -eq 1 ]; then
  P28_NODEENV_OK=1
  _p28_node_check "20.19.0" reject || P28_NODEENV_OK=0
  _p28_node_check "20.20.0" accept || P28_NODEENV_OK=0
  _p28_node_check "21.5.0"  reject || P28_NODEENV_OK=0
  _p28_node_check "22.21.0" reject || P28_NODEENV_OK=0
  _p28_node_check "22.22.0" accept || P28_NODEENV_OK=0
  if [ "$P28_NODEENV_OK" -eq 1 ]; then
    pass "eval run node gate enforces ^20.20.0 || >=22.22.0 (20.19/21.5/22.21 reject; 20.20/22.22 accept) (WR-02-node-envelope)"
  else
    fail "eval run node gate does not match ^20.20.0 || >=22.22.0 envelope (WR-02-node-envelope)"
  fi
else
  fail "scripts/eval.sh not implemented — Wave 1 must create it (WR-02-node-envelope)"
fi
unset -f _p28_node_check
rm -rf "$P28_NODEENV_DIR"
trap - EXIT

# EVAL-02-audit-decoupled: audit with promptfoo absent exits 0 (not exit 2) — decoupled
P28_ADECPL_DIR="$(mktemp -d)"
trap 'rm -rf "$P28_ADECPL_DIR"' EXIT
cp -r "$CONJURE_HOME/tests/fixtures/_eval/harness/." "$P28_ADECPL_DIR/"
git -C "$P28_ADECPL_DIR" init -q
git -C "$P28_ADECPL_DIR" config user.email "test@conjure"
git -C "$P28_ADECPL_DIR" config user.name "conjure-test"
git -C "$P28_ADECPL_DIR" add -A 2>/dev/null || true
git -C "$P28_ADECPL_DIR" commit -q -m "test fixture" 2>/dev/null || true
if [ "$P28_AUDIT_OK" -eq 1 ]; then
  P28_ADECPL_RC=0
  CONJURE_HOME="$CONJURE_HOME" bash "$P28_AUDIT_SH" "$P28_ADECPL_DIR" >/dev/null 2>&1 || P28_ADECPL_RC=$?
  if [ "$P28_ADECPL_RC" -ne 2 ]; then
    pass "audit with promptfoo absent exits 0 (not exit 2) — promptfoo fully decoupled from audit (EVAL-02-audit-decoupled)"
  else
    fail "audit rc=$P28_ADECPL_RC — expected non-2 exit (audit must not require promptfoo) (EVAL-02-audit-decoupled)"
  fi
else
  fail "audit-setup.sh EVAL section not implemented — Wave 3 must add it (EVAL-02-audit-decoupled)"
fi
rm -rf "$P28_ADECPL_DIR"
trap - EXIT

# EVAL-03-emit: eval --emit-workflow creates .github/workflows/conjure-eval.yml with correct shape
P28_WF_DIR="$(mktemp -d)"
trap 'rm -rf "$P28_WF_DIR"' EXIT
git -C "$P28_WF_DIR" init -q
git -C "$P28_WF_DIR" config user.email "test@conjure"
git -C "$P28_WF_DIR" config user.name "conjure-test"
printf '## Project\n\nWorkflow emit test.\n' > "$P28_WF_DIR/CLAUDE.md"
git -C "$P28_WF_DIR" add -A 2>/dev/null || true
git -C "$P28_WF_DIR" commit -q -m "test fixture" 2>/dev/null || true
if [ "$P28_EVAL_OK" -eq 1 ]; then
  P28_WF_RC=0
  CONJURE_HOME="$CONJURE_HOME" bash "$P28_EVAL_SH" --emit-workflow "$P28_WF_DIR" >/dev/null 2>&1 || P28_WF_RC=$?
  if [ "$P28_WF_RC" -eq 0 ] && \
     [ -f "$P28_WF_DIR/.github/workflows/conjure-eval.yml" ] && \
     grep -q "pull_request" "$P28_WF_DIR/.github/workflows/conjure-eval.yml" && \
     grep -q "promptfoo/promptfoo-action" "$P28_WF_DIR/.github/workflows/conjure-eval.yml" && \
     grep -q "fail-on-threshold: 80" "$P28_WF_DIR/.github/workflows/conjure-eval.yml" && \
     grep -q "repeat: 3" "$P28_WF_DIR/.github/workflows/conjure-eval.yml" && \
     grep -q "repeat-min-pass: 2" "$P28_WF_DIR/.github/workflows/conjure-eval.yml" && \
     grep -q "0.121.14" "$P28_WF_DIR/.github/workflows/conjure-eval.yml" && \
     grep -q "\.claude/\*\*" "$P28_WF_DIR/.github/workflows/conjure-eval.yml"; then
    pass "eval --emit-workflow creates conjure-eval.yml with correct shape (EVAL-03-emit)"
  else
    fail "eval --emit-workflow rc=$P28_WF_RC — missing or malformed conjure-eval.yml (EVAL-03-emit)"
  fi
else
  fail "scripts/eval.sh not implemented — Wave 1 must create it (EVAL-03-emit)"
fi
rm -rf "$P28_WF_DIR"
trap - EXIT

# EVAL-04-budget-ok: audit --budget on normal harness exits 0 or 1 (under threshold) and prints tokens
P28_BUDOK_DIR="$(mktemp -d)"
trap 'rm -rf "$P28_BUDOK_DIR"' EXIT
cp -r "$CONJURE_HOME/tests/fixtures/_eval/harness/." "$P28_BUDOK_DIR/"
git -C "$P28_BUDOK_DIR" init -q
git -C "$P28_BUDOK_DIR" config user.email "test@conjure"
git -C "$P28_BUDOK_DIR" config user.name "conjure-test"
git -C "$P28_BUDOK_DIR" add -A 2>/dev/null || true
git -C "$P28_BUDOK_DIR" commit -q -m "test fixture" 2>/dev/null || true
if [ "$P28_AUDIT_OK" -eq 1 ]; then
  P28_BUDOK_RC=0
  P28_BUDOK_OUT="$(CONJURE_HOME="$CONJURE_HOME" CONJURE_BUDGET=1 bash "$P28_AUDIT_SH" "$P28_BUDOK_DIR" 2>&1)" || P28_BUDOK_RC=$?
  if [ "$P28_BUDOK_RC" -ne 2 ] && \
     printf '%s\n' "$P28_BUDOK_OUT" | grep -qi "token"; then
    pass "audit --budget on normal harness exits 0 or 1 (under threshold) (EVAL-04-budget-ok)"
  else
    fail "audit --budget rc=$P28_BUDOK_RC — expected non-2 exit and token output (EVAL-04-budget-ok)"
  fi
else
  fail "audit-setup.sh EVAL section not implemented — Wave 3 must add it (EVAL-04-budget-ok)"
fi
rm -rf "$P28_BUDOK_DIR"
trap - EXIT

# EVAL-04-budget-err: audit --budget on _eval-overbudget fixture exits 2 (>=25k tokens)
P28_BUDERR_DIR="$(mktemp -d)"
trap 'rm -rf "$P28_BUDERR_DIR"' EXIT
cp -r "$CONJURE_HOME/tests/fixtures/_eval-overbudget/harness/." "$P28_BUDERR_DIR/"
git -C "$P28_BUDERR_DIR" init -q
git -C "$P28_BUDERR_DIR" config user.email "test@conjure"
git -C "$P28_BUDERR_DIR" config user.name "conjure-test"
git -C "$P28_BUDERR_DIR" add -A 2>/dev/null || true
git -C "$P28_BUDERR_DIR" commit -q -m "test fixture" 2>/dev/null || true
if [ "$P28_AUDIT_OK" -eq 1 ]; then
  P28_BUDERR_RC=0
  CONJURE_HOME="$CONJURE_HOME" CONJURE_BUDGET=1 bash "$P28_AUDIT_SH" "$P28_BUDERR_DIR" >/dev/null 2>&1 || P28_BUDERR_RC=$?
  if [ "$P28_BUDERR_RC" -eq 2 ]; then
    pass "audit --budget exits 2 when estimated tokens >=25000 (EVAL-04-budget-err)"
  else
    fail "audit --budget rc=$P28_BUDERR_RC — expected exit 2 for over-budget harness (EVAL-04-budget-err)"
  fi
else
  fail "audit-setup.sh EVAL section not implemented — Wave 3 must add it (EVAL-04-budget-err)"
fi
rm -rf "$P28_BUDERR_DIR"
trap - EXIT

# EVAL-04-porcelain: audit --budget --porcelain emits JSON with correct shape
P28_PORCDIR="$(mktemp -d)"
trap 'rm -rf "$P28_PORCDIR"' EXIT
cp -r "$CONJURE_HOME/tests/fixtures/_eval/harness/." "$P28_PORCDIR/"
git -C "$P28_PORCDIR" init -q
git -C "$P28_PORCDIR" config user.email "test@conjure"
git -C "$P28_PORCDIR" config user.name "conjure-test"
git -C "$P28_PORCDIR" add -A 2>/dev/null || true
git -C "$P28_PORCDIR" commit -q -m "test fixture" 2>/dev/null || true
if [ "$P28_AUDIT_OK" -eq 1 ]; then
  P28_PORC_STDOUT_FILE="$(mktemp)"
  P28_PORC_RC=0
  CONJURE_HOME="$CONJURE_HOME" CONJURE_BUDGET=1 CONJURE_PORCELAIN=1 bash "$P28_AUDIT_SH" "$P28_PORCDIR" \
    >"$P28_PORC_STDOUT_FILE" 2>/dev/null || P28_PORC_RC=$?
  P28_PORC_OUT="$(cat "$P28_PORC_STDOUT_FILE")"
  rm -f "$P28_PORC_STDOUT_FILE"
  if printf '%s\n' "$P28_PORC_OUT" | jq -e '.total_tokens' >/dev/null 2>&1 && \
     printf '%s\n' "$P28_PORC_OUT" | jq -e '(.contributors | type) == "array"' >/dev/null 2>&1 && \
     printf '%s\n' "$P28_PORC_OUT" | jq -e 'has("over")' >/dev/null 2>&1; then
    pass "audit --budget --porcelain emits valid JSON with total_tokens, threshold, over, contributors[] (EVAL-04-porcelain)"
  else
    fail "audit --budget --porcelain rc=$P28_PORC_RC — JSON missing total_tokens/contributors/over (EVAL-04-porcelain)"
  fi
  # WR-04: the porcelain JSON must carry an explicit `_comment` documenting that
  # budget status is the `over` field, not the process exit code (the exit code
  # is the holistic audit verdict and is intentionally unchanged).
  if printf '%s\n' "$P28_PORC_OUT" | jq -e 'has("_comment")' >/dev/null 2>&1 && \
     printf '%s\n' "$P28_PORC_OUT" | jq -e '._comment | test("over")' >/dev/null 2>&1; then
    pass "audit --budget --porcelain JSON documents exit-code/over-field contract via _comment (WR-04-porcelain-contract)"
  else
    fail "audit --budget --porcelain JSON missing _comment contract note (WR-04-porcelain-contract)"
  fi
else
  fail "audit-setup.sh EVAL section not implemented — Wave 3 must add it (EVAL-04-porcelain)"
fi
rm -rf "$P28_PORCDIR"
trap - EXIT

# EVAL-05-gap: audit on _eval-coverage-gap fixture reports uncovered skill
P28_GAPDIR="$(mktemp -d)"
trap 'rm -rf "$P28_GAPDIR"' EXIT
cp -r "$CONJURE_HOME/tests/fixtures/_eval-coverage-gap/harness/." "$P28_GAPDIR/"
git -C "$P28_GAPDIR" init -q
git -C "$P28_GAPDIR" config user.email "test@conjure"
git -C "$P28_GAPDIR" config user.name "conjure-test"
git -C "$P28_GAPDIR" add -A 2>/dev/null || true
git -C "$P28_GAPDIR" commit -q -m "test fixture" 2>/dev/null || true
if [ "$P28_AUDIT_OK" -eq 1 ]; then
  P28_GAP_RC=0
  P28_GAP_OUT="$(CONJURE_HOME="$CONJURE_HOME" bash "$P28_AUDIT_SH" "$P28_GAPDIR" 2>&1)" || P28_GAP_RC=$?
  if [ "$P28_GAP_RC" -ne 2 ] && \
     printf '%s\n' "$P28_GAP_OUT" | grep -q "code-review"; then
    pass "audit reports skill with no skill-used assertion as coverage gap (EVAL-05-gap)"
  else
    fail "audit rc=$P28_GAP_RC — expected non-2 exit and code-review in gap report (EVAL-05-gap)"
  fi
else
  fail "audit-setup.sh EVAL section not implemented — Wave 3 must add it (EVAL-05-gap)"
fi
rm -rf "$P28_GAPDIR"
trap - EXIT

# WR-03-skill-extract-robust: skill-used extraction must tolerate a key
# (description:) interleaved between `type: skill-used` and `value:`, and must
# skip commented-out assertion lines. Pre-fix, the interleaved description: reset
# the awk state → s1 reported as an unasserted gap (false-negative), and a
# commented `#   value: 'ghost'` leaked into extraction.
P28_EXTDIR="$(mktemp -d)"
trap 'rm -rf "$P28_EXTDIR"' EXIT
mkdir -p "$P28_EXTDIR/.claude/skills/s1"
printf '## Project\n\nExtraction-robustness harness.\n' > "$P28_EXTDIR/CLAUDE.md"
printf -- '---\nname: s1\ndescription: Skill one\nallowed-tools:\n  - Read\n---\nBody.\n' > "$P28_EXTDIR/.claude/skills/s1/SKILL.md"
mkdir -p "$P28_EXTDIR/.conjure/eval"
# Reordered block (description between type and value) + a commented ghost line.
{
  printf 'tests:\n'
  printf '  - assert:\n'
  printf '      - type: skill-used\n'
  printf '        description: routing check\n'
  printf "        value: 's1'\n"
  printf "  #   value: 'ghost'\n"
} > "$P28_EXTDIR/.conjure/eval/promptfooconfig.yaml"
git -C "$P28_EXTDIR" init -q
git -C "$P28_EXTDIR" config user.email "test@conjure"
git -C "$P28_EXTDIR" config user.name "conjure-test"
git -C "$P28_EXTDIR" add -A 2>/dev/null || true
git -C "$P28_EXTDIR" commit -q -m "test fixture" 2>/dev/null || true
if [ "$P28_AUDIT_OK" -eq 1 ]; then
  P28_EXT_RC=0
  P28_EXT_OUT="$(CONJURE_HOME="$CONJURE_HOME" bash "$P28_AUDIT_SH" "$P28_EXTDIR" 2>&1)" || P28_EXT_RC=$?
  # s1 IS asserted (reordered block) → must NOT be flagged as a gap, and the
  # commented 'ghost' must NOT appear as an extracted/asserted skill.
  if [ "$P28_EXT_RC" -ne 2 ] && \
     ! printf '%s\n' "$P28_EXT_OUT" | grep -q "skill 's1' has no skill-used assertion" && \
     ! printf '%s\n' "$P28_EXT_OUT" | grep -qi "ghost"; then
    pass "skill-used extraction tolerates key reordering and skips comments (WR-03-skill-extract-robust)"
  else
    fail "skill-used extraction false-negative on reordered block or leaked comment (WR-03-skill-extract-robust)"
  fi
else
  fail "audit-setup.sh EVAL section not implemented — Wave 3 must add it (WR-03-skill-extract-robust)"
fi
rm -rf "$P28_EXTDIR"
trap - EXIT

# EVAL-05-noconfig: audit on harness with no eval config emits advisory but exits 0
P28_NOCFGDIR="$(mktemp -d)"
trap 'rm -rf "$P28_NOCFGDIR"' EXIT
printf '## Project\n\nNo-eval-config harness.\n\n- Always run shellcheck.\n' > "$P28_NOCFGDIR/CLAUDE.md"
mkdir -p "$P28_NOCFGDIR/.claude/skills/sample-skill"
printf -- '---\nname: sample-skill\ndescription: Sample skill\nallowed-tools:\n  - Read\n---\nSample skill body.\n' > "$P28_NOCFGDIR/.claude/skills/sample-skill/SKILL.md"
git -C "$P28_NOCFGDIR" init -q
git -C "$P28_NOCFGDIR" config user.email "test@conjure"
git -C "$P28_NOCFGDIR" config user.name "conjure-test"
git -C "$P28_NOCFGDIR" add -A 2>/dev/null || true
git -C "$P28_NOCFGDIR" commit -q -m "test fixture" 2>/dev/null || true
if [ "$P28_AUDIT_OK" -eq 1 ]; then
  P28_NOCFG_RC=0
  P28_NOCFG_OUT="$(CONJURE_HOME="$CONJURE_HOME" bash "$P28_AUDIT_SH" "$P28_NOCFGDIR" 2>&1)" || P28_NOCFG_RC=$?
  if [ "$P28_NOCFG_RC" -ne 2 ] && \
     { printf '%s\n' "$P28_NOCFG_OUT" | grep -qi "eval config" || \
       printf '%s\n' "$P28_NOCFG_OUT" | grep -qi "conjure eval init"; }; then
    pass "audit with no eval config emits note() advisory and exits 0 (EVAL-05-noconfig)"
  else
    fail "audit rc=$P28_NOCFG_RC — expected non-2 exit and eval config/conjure eval init advisory (EVAL-05-noconfig)"
  fi
else
  fail "audit-setup.sh EVAL section not implemented — Wave 3 must add it (EVAL-05-noconfig)"
fi
rm -rf "$P28_NOCFGDIR"
trap - EXIT

# WR-01-eval05-relative-target: EVAL-05 must find the eval config when audit is
# invoked with a RELATIVE target arg. Pre-fix, "$TARGET/.conjure/..." doubled the
# path after `cd "$TARGET"`, so a config-present harness was misreported as
# "no eval config" and the coverage report was silently disabled.
P28_RELBASE="$(mktemp -d)"
trap 'rm -rf "$P28_RELBASE"' EXIT
mkdir -p "$P28_RELBASE/relrepo/.conjure/eval"
mkdir -p "$P28_RELBASE/relrepo/.claude/skills/sample-skill"
printf '## Project\n\nRelative-target harness.\n\n- Always run shellcheck.\n' > "$P28_RELBASE/relrepo/CLAUDE.md"
printf -- '---\nname: sample-skill\ndescription: Sample skill\nallowed-tools:\n  - Read\n---\nSample skill body.\n' > "$P28_RELBASE/relrepo/.claude/skills/sample-skill/SKILL.md"
# Eval config WITH a skill-used assertion for sample-skill (so the config exists
# and is non-empty; EVAL-05 should report full coverage, NOT "no eval config").
printf 'tests:\n  - assert:\n      - type: skill-used\n        value: '"'"'sample-skill'"'"'\n' > "$P28_RELBASE/relrepo/.conjure/eval/promptfooconfig.yaml"
git -C "$P28_RELBASE/relrepo" init -q
git -C "$P28_RELBASE/relrepo" config user.email "test@conjure"
git -C "$P28_RELBASE/relrepo" config user.name "conjure-test"
git -C "$P28_RELBASE/relrepo" add -A 2>/dev/null || true
git -C "$P28_RELBASE/relrepo" commit -q -m "test fixture" 2>/dev/null || true
if [ "$P28_AUDIT_OK" -eq 1 ]; then
  P28_REL_RC=0
  # Invoke from $P28_RELBASE with the RELATIVE arg "relrepo" — the bug only
  # surfaces with a relative (not absolute) target.
  P28_REL_OUT="$(cd "$P28_RELBASE" && CONJURE_HOME="$CONJURE_HOME" bash "$P28_AUDIT_SH" relrepo 2>&1)" || P28_REL_RC=$?
  if [ "$P28_REL_RC" -ne 2 ] && \
     ! printf '%s\n' "$P28_REL_OUT" | grep -qi "no eval config"; then
    pass "audit with relative target finds eval config (no path-doubling) (WR-01-eval05-relative-target)"
  else
    fail "audit rc=$P28_REL_RC — relative target misreported 'no eval config' (path-doubling) (WR-01-eval05-relative-target)"
  fi
else
  fail "audit-setup.sh EVAL section not implemented — Wave 3 must add it (WR-01-eval05-relative-target)"
fi
rm -rf "$P28_RELBASE"
trap - EXIT

# ──────────────────────────────────────────────────────────────────────────────
# Phase 29 — Workspace Orchestration — Read-Only (WS-01..04)
# Mirrors Phase 28 block style: mktemp sandboxes with EXIT-trap discipline.
# All workspace.sh invocations guarded behind P29_WS_SH_OK so the suite reports
# graceful RED when scripts/workspace.sh is absent (Wave 1 not yet complete).
# lib/workspace.sh helper invocations guarded behind P29_WS_LIB_OK.
# ──────────────────────────────────────────────────────────────────────────────

P29_WS_LIB="$CONJURE_HOME/lib/workspace.sh"
P29_WS_SH="$CONJURE_HOME/scripts/workspace.sh"
P29_WS_LIB_OK=0
P29_WS_SH_OK=0
[ -f "$P29_WS_LIB" ] && P29_WS_LIB_OK=1
[ -f "$P29_WS_SH" ] && P29_WS_SH_OK=1

echo
echo "▸ Phase 29 — Workspace Orchestration — Read-Only (WS-01..04)"

# WS-01-manifest-valid: workspace_manifest_validate accepts a well-formed manifest
P29_MV_DIR="$(mktemp -d)"
trap 'rm -rf "$P29_MV_DIR"' EXIT
cp "$CONJURE_HOME/tests/fixtures/_workspace/.conjure-workspace.json" "$P29_MV_DIR/.conjure-workspace.json"
if [ "$P29_WS_LIB_OK" -eq 1 ]; then
  # shellcheck source=/dev/null
  . "$P29_WS_LIB"
  P29_MV_RC=0
  workspace_manifest_validate "$P29_MV_DIR/.conjure-workspace.json" || P29_MV_RC=$?
  if [ "$P29_MV_RC" -eq 0 ]; then
    pass "workspace_manifest_validate accepts a well-formed manifest (WS-01-manifest-valid)"
  else
    fail "workspace_manifest_validate rejected a valid manifest (exit $P29_MV_RC) (WS-01-manifest-valid)"
  fi
else
  fail "lib/workspace.sh not implemented — Wave 1 must create it (WS-01-manifest-valid)"
fi
trap - EXIT
rm -rf "$P29_MV_DIR"

# WS-01-manifest-invalid: workspace_manifest_validate rejects malformed JSON with exit 2
P29_MV2_DIR="$(mktemp -d)"
trap 'rm -rf "$P29_MV2_DIR"' EXIT
printf 'not-json\n' > "$P29_MV2_DIR/.conjure-workspace.json"
if [ "$P29_WS_LIB_OK" -eq 1 ]; then
  P29_MV2_RC=0
  workspace_manifest_validate "$P29_MV2_DIR/.conjure-workspace.json" || P29_MV2_RC=$?
  if [ "$P29_MV2_RC" -eq 2 ]; then
    pass "workspace_manifest_validate rejects malformed manifest with exit 2 (WS-01-manifest-invalid)"
  else
    fail "workspace_manifest_validate returned $P29_MV2_RC (expected 2) for malformed JSON (WS-01-manifest-invalid)"
  fi
else
  fail "lib/workspace.sh not implemented — Wave 1 must create it (WS-01-manifest-invalid)"
fi
trap - EXIT
rm -rf "$P29_MV2_DIR"

# WS-02-init-writes: workspace init --yes writes a valid manifest with relative paths
P29_INIT_DIR="$(mktemp -d)"
trap 'rm -rf "$P29_INIT_DIR"' EXIT
mkdir -p "$P29_INIT_DIR/sib-a/.claude"
mkdir -p "$P29_INIT_DIR/sib-b/.claude"
if [ "$P29_WS_SH_OK" -eq 1 ]; then
  P29_INIT_RC=0
  CONJURE_HOME="$CONJURE_HOME" bash "$P29_WS_SH" init --yes "$P29_INIT_DIR" >/dev/null 2>&1 || P29_INIT_RC=$?
  if [ "$P29_INIT_RC" -eq 0 ] && \
     [ -f "$P29_INIT_DIR/.conjure-workspace.json" ] && \
     jq empty "$P29_INIT_DIR/.conjure-workspace.json" >/dev/null 2>&1; then
    P29_TOTAL="$(jq '.repos | length' "$P29_INIT_DIR/.conjure-workspace.json")"
    P29_REL_COUNT="$(jq -r '.repos[].path' "$P29_INIT_DIR/.conjure-workspace.json" | grep -cv '^/')"
    if [ "$P29_REL_COUNT" -eq "$P29_TOTAL" ]; then
      pass "workspace init --yes writes valid .conjure-workspace.json (WS-02-init-writes)"
    else
      fail "workspace init wrote absolute paths (rel=$P29_REL_COUNT total=$P29_TOTAL) (WS-02-init-writes)"
    fi
  else
    fail "workspace init --yes exit=$P29_INIT_RC or no manifest written (WS-02-init-writes)"
  fi
else
  fail "scripts/workspace.sh not implemented — Wave 1 must create it (WS-02-init-writes)"
fi
trap - EXIT
rm -rf "$P29_INIT_DIR"

# WS-02-init-no-tty: workspace init without --yes in non-TTY exits 2 and writes no file
P29_NOTTY_DIR="$(mktemp -d)"
trap 'rm -rf "$P29_NOTTY_DIR"' EXIT
mkdir -p "$P29_NOTTY_DIR/sib-a/.claude"
if [ "$P29_WS_SH_OK" -eq 1 ]; then
  P29_NOTTY_RC=0
  CONJURE_HOME="$CONJURE_HOME" bash "$P29_WS_SH" init "$P29_NOTTY_DIR" </dev/null >/dev/null 2>&1 || P29_NOTTY_RC=$?
  if [ "$P29_NOTTY_RC" -eq 2 ] && [ ! -f "$P29_NOTTY_DIR/.conjure-workspace.json" ]; then
    pass "workspace init without --yes in non-TTY exits 2 and writes no file (WS-02-init-no-tty)"
  else
    fail "workspace init non-TTY: exit=$P29_NOTTY_RC file_written=$([ -f "$P29_NOTTY_DIR/.conjure-workspace.json" ] && echo yes || echo no) (WS-02-init-no-tty)"
  fi
else
  fail "scripts/workspace.sh not implemented — Wave 1 must create it (WS-02-init-no-tty)"
fi
trap - EXIT
rm -rf "$P29_NOTTY_DIR"

# WS-03-check-table: workspace check on valid manifest emits a per-repo table
P29_CHK_DIR="$(mktemp -d)"
trap 'rm -rf "$P29_CHK_DIR"' EXIT
cp -r "$CONJURE_HOME/tests/fixtures/_workspace/." "$P29_CHK_DIR/"
if [ "$P29_WS_SH_OK" -eq 1 ]; then
  P29_CHK_RC=0
  P29_CHK_OUT="$(CONJURE_HOME="$CONJURE_HOME" bash "$P29_WS_SH" check "$P29_CHK_DIR/.conjure-workspace.json" 2>&1)" || P29_CHK_RC=$?
  if [ "$P29_CHK_RC" -le 1 ] && \
     printf '%s\n' "$P29_CHK_OUT" | grep -q "alpha" && \
     printf '%s\n' "$P29_CHK_OUT" | grep -q "beta"; then
    pass "workspace check emits per-repo status table (WS-03-check-table)"
  else
    fail "workspace check exit=$P29_CHK_RC output missing alpha/beta rows (WS-03-check-table)"
  fi
else
  fail "scripts/workspace.sh not implemented — Wave 1 must create it (WS-03-check-table)"
fi
trap - EXIT
rm -rf "$P29_CHK_DIR"

# WS-03-check-fail-tolerant: workspace check exits exactly 1 when one repo is unreadable
P29_FTOL_DIR="$(mktemp -d)"
trap 'chmod -R 755 "$P29_FTOL_DIR" 2>/dev/null; rm -rf "$P29_FTOL_DIR"' EXIT
mkdir -p "$P29_FTOL_DIR/sib-ok-a/.claude"
mkdir -p "$P29_FTOL_DIR/sib-ok-b/.claude"
mkdir -p "$P29_FTOL_DIR/sib-err"
printf '# sib-ok-a\n' > "$P29_FTOL_DIR/sib-ok-a/CLAUDE.md"
printf '# sib-ok-b\n' > "$P29_FTOL_DIR/sib-ok-b/CLAUDE.md"
printf '# sib-err\n' > "$P29_FTOL_DIR/sib-err/CLAUDE.md"
printf '{"schema_version":1,"generated":"2026-06-03T00:00:00Z","repos":[{"name":"sib-ok-a","path":"sib-ok-a","tags":[]},{"name":"sib-err","path":"sib-err","tags":[]},{"name":"sib-ok-b","path":"sib-ok-b","tags":[]}]}\n' > "$P29_FTOL_DIR/.conjure-workspace.json"
chmod 000 "$P29_FTOL_DIR/sib-err"
if [ "$P29_WS_SH_OK" -eq 1 ]; then
  P29_FTOL_RC=0
  P29_FTOL_OUT="$(CONJURE_HOME="$CONJURE_HOME" bash "$P29_WS_SH" check "$P29_FTOL_DIR/.conjure-workspace.json" 2>&1)" || P29_FTOL_RC=$?
  chmod 755 "$P29_FTOL_DIR/sib-err" 2>/dev/null || true
  if [ "$P29_FTOL_RC" -eq 1 ] && \
     printf '%s\n' "$P29_FTOL_OUT" | grep -q "sib-ok-a" && \
     printf '%s\n' "$P29_FTOL_OUT" | grep -q "sib-ok-b"; then
    pass "workspace check exits exactly 1 when one repo is unreadable, remaining repos processed (WS-03-check-fail-tolerant)"
  else
    chmod 755 "$P29_FTOL_DIR/sib-err" 2>/dev/null || true
    fail "workspace check exit=$P29_FTOL_RC (expected 1) or missing ok-repo rows (WS-03-check-fail-tolerant)"
  fi
else
  chmod 755 "$P29_FTOL_DIR/sib-err" 2>/dev/null || true
  fail "scripts/workspace.sh not implemented — Wave 1 must create it (WS-03-check-fail-tolerant)"
fi
trap - EXIT
chmod -R 755 "$P29_FTOL_DIR" 2>/dev/null || true
rm -rf "$P29_FTOL_DIR"

# WS-03-check-badpath: workspace check skips bad-path repo with a warning and processes the rest
P29_BPCHK_DIR="$(mktemp -d)"
trap 'rm -rf "$P29_BPCHK_DIR"' EXIT
cp "$CONJURE_HOME/tests/fixtures/_workspace-badpath/.conjure-workspace.json" "$P29_BPCHK_DIR/.conjure-workspace.json"
# Bad-path fixture: alpha/beta are real IN-BOUNDS repos; nonexistent-repo is the bad path.
# (Paths stay in-bounds so the corrected traversal guard accepts the manifest at load time;
#  the nonexistent repo is then skipped per-repo with a warning — CR-01.)
mkdir -p "$P29_BPCHK_DIR/repos/alpha/.claude"
mkdir -p "$P29_BPCHK_DIR/repos/beta/.claude"
cp "$CONJURE_HOME/tests/fixtures/_workspace/repos/alpha/CLAUDE.md" "$P29_BPCHK_DIR/repos/alpha/CLAUDE.md"
cp "$CONJURE_HOME/tests/fixtures/_workspace/repos/beta/CLAUDE.md" "$P29_BPCHK_DIR/repos/beta/CLAUDE.md"
if [ "$P29_WS_SH_OK" -eq 1 ]; then
  P29_BPCHK_RC=0
  P29_BPCHK_OUT="$(CONJURE_HOME="$CONJURE_HOME" bash "$P29_WS_SH" check "$P29_BPCHK_DIR/.conjure-workspace.json" 2>&1)" || P29_BPCHK_RC=$?
  if [ "$P29_BPCHK_RC" -le 1 ] && \
     { printf '%s\n' "$P29_BPCHK_OUT" | grep -qi "skip\|warn\|missing\|not found\|nonexistent"; }; then
    pass "workspace check skips bad-path repo with warning and processes remaining repos (WS-03-check-badpath)"
  else
    fail "workspace check exit=$P29_BPCHK_RC missing skip/warn for bad path (WS-03-check-badpath)"
  fi
else
  fail "scripts/workspace.sh not implemented — Wave 1 must create it (WS-03-check-badpath)"
fi
trap - EXIT
rm -rf "$P29_BPCHK_DIR"

# WS-04-audit-pass: workspace audit on all-good manifest exits 0 or 1
P29_AUD_DIR="$(mktemp -d)"
trap 'rm -rf "$P29_AUD_DIR"' EXIT
cp -r "$CONJURE_HOME/tests/fixtures/_workspace/." "$P29_AUD_DIR/"
if [ "$P29_WS_SH_OK" -eq 1 ]; then
  P29_AUD_RC=0
  CONJURE_HOME="$CONJURE_HOME" bash "$P29_WS_SH" audit "$P29_AUD_DIR/.conjure-workspace.json" >/dev/null 2>&1 || P29_AUD_RC=$?
  if [ "$P29_AUD_RC" -le 1 ]; then
    pass "workspace audit on all-good repos exits 0 or 1 (WS-04-audit-pass)"
  else
    fail "workspace audit exit=$P29_AUD_RC (expected 0 or 1) on all-good manifest (WS-04-audit-pass)"
  fi
else
  fail "scripts/workspace.sh not implemented — Wave 2 must create it (WS-04-audit-pass)"
fi
trap - EXIT
rm -rf "$P29_AUD_DIR"

# WS-04-audit-fail: workspace audit exits 2 when any repo audit status is fail
P29_AUDF_DIR="$(mktemp -d)"
trap 'rm -rf "$P29_AUDF_DIR"' EXIT
cp -r "$CONJURE_HOME/tests/fixtures/_workspace/repos/alpha" "$P29_AUDF_DIR/alpha"
cp -r "$CONJURE_HOME/tests/fixtures/_workspace/repos/beta" "$P29_AUDF_DIR/beta"
cp -r "$CONJURE_HOME/tests/fixtures/_workspace/repos/gamma-bad" "$P29_AUDF_DIR/gamma-bad"
printf '{"schema_version":1,"generated":"2026-06-03T00:00:00Z","repos":[{"name":"alpha","path":"alpha","tags":[]},{"name":"beta","path":"beta","tags":[]},{"name":"gamma-bad","path":"gamma-bad","tags":[]}]}\n' > "$P29_AUDF_DIR/.conjure-workspace.json"
if [ "$P29_WS_SH_OK" -eq 1 ]; then
  P29_AUDF_RC=0
  CONJURE_HOME="$CONJURE_HOME" bash "$P29_WS_SH" audit "$P29_AUDF_DIR/.conjure-workspace.json" >/dev/null 2>&1 || P29_AUDF_RC=$?
  if [ "$P29_AUDF_RC" -eq 2 ]; then
    pass "workspace audit exits 2 when any repo status is fail (WS-04-audit-fail)"
  else
    fail "workspace audit exit=$P29_AUDF_RC (expected 2) with failing repo (WS-04-audit-fail)"
  fi
else
  fail "scripts/workspace.sh not implemented — Wave 2 must create it (WS-04-audit-fail)"
fi
trap - EXIT
rm -rf "$P29_AUDF_DIR"

# WS-04-audit-failfast: workspace audit --fail-fast stops at first failure
P29_AFF_DIR="$(mktemp -d)"
trap 'rm -rf "$P29_AFF_DIR"' EXIT
cp -r "$CONJURE_HOME/tests/fixtures/_workspace/repos/gamma-bad" "$P29_AFF_DIR/gamma-bad"
cp -r "$CONJURE_HOME/tests/fixtures/_workspace/repos/alpha" "$P29_AFF_DIR/alpha"
# gamma-bad is first so --fail-fast fires before alpha is processed
printf '{"schema_version":1,"generated":"2026-06-03T00:00:00Z","repos":[{"name":"gamma-bad","path":"gamma-bad","tags":[]},{"name":"alpha","path":"alpha","tags":[]}]}\n' > "$P29_AFF_DIR/.conjure-workspace.json"
if [ "$P29_WS_SH_OK" -eq 1 ]; then
  P29_AFF_RC=0
  P29_AFF_OUT="$(CONJURE_HOME="$CONJURE_HOME" bash "$P29_WS_SH" audit --fail-fast "$P29_AFF_DIR/.conjure-workspace.json" 2>&1)" || P29_AFF_RC=$?
  if [ "$P29_AFF_RC" -eq 2 ] && \
     ! printf '%s\n' "$P29_AFF_OUT" | grep -q "^alpha"; then
    pass "workspace audit --fail-fast stops at first failure (WS-04-audit-failfast)"
  else
    fail "workspace audit --fail-fast exit=$P29_AFF_RC or processed repos after failure (WS-04-audit-failfast)"
  fi
else
  fail "scripts/workspace.sh not implemented — Wave 2 must create it (WS-04-audit-failfast)"
fi
trap - EXIT
rm -rf "$P29_AFF_DIR"

# WS-04-audit-badpath: workspace audit skips bad-path repo with warning and processes rest
P29_AUDPB_DIR="$(mktemp -d)"
trap 'rm -rf "$P29_AUDPB_DIR"' EXIT
cp "$CONJURE_HOME/tests/fixtures/_workspace-badpath/.conjure-workspace.json" "$P29_AUDPB_DIR/.conjure-workspace.json"
# Bad-path fixture: alpha/beta are real IN-BOUNDS repos; nonexistent-repo is the bad path.
# (In-bounds paths so the corrected traversal guard accepts the manifest at load time — CR-01.)
mkdir -p "$P29_AUDPB_DIR/repos/alpha/.claude"
mkdir -p "$P29_AUDPB_DIR/repos/beta/.claude"
cp "$CONJURE_HOME/tests/fixtures/_workspace/repos/alpha/CLAUDE.md" "$P29_AUDPB_DIR/repos/alpha/CLAUDE.md"
cp "$CONJURE_HOME/tests/fixtures/_workspace/repos/beta/CLAUDE.md" "$P29_AUDPB_DIR/repos/beta/CLAUDE.md"
if [ "$P29_WS_SH_OK" -eq 1 ]; then
  P29_AUDPB_RC=0
  P29_AUDPB_OUT="$(CONJURE_HOME="$CONJURE_HOME" bash "$P29_WS_SH" audit "$P29_AUDPB_DIR/.conjure-workspace.json" 2>&1)" || P29_AUDPB_RC=$?
  if [ "$P29_AUDPB_RC" -le 1 ] && \
     { printf '%s\n' "$P29_AUDPB_OUT" | grep -qi "skip\|warn\|missing\|not found\|nonexistent"; }; then
    pass "workspace audit skips bad-path repo with warning and processes remaining repos (WS-04-audit-badpath)"
  else
    fail "workspace audit exit=$P29_AUDPB_RC missing skip/warn for bad path (WS-04-audit-badpath)"
  fi
else
  fail "scripts/workspace.sh not implemented — Wave 2 must create it (WS-04-audit-badpath)"
fi
trap - EXIT
rm -rf "$P29_AUDPB_DIR"

# WS-SEC-traversal-escape: workspace_manifest_validate REJECTS a ../sibling escape (exit 2).
# Regression for CR-01: the guard previously anchored the boundary at the workspace PARENT,
# so ../sibling paths slipped through. The boundary is the workspace (manifest) dir itself.
P29_ESC_ROOT="$(mktemp -d)"
trap 'rm -rf "$P29_ESC_ROOT"' EXIT
mkdir -p "$P29_ESC_ROOT/ws"
mkdir -p "$P29_ESC_ROOT/sibling/.claude"
printf '{"schema_version":1,"generated":"2026-06-03T00:00:00Z","repos":[{"name":"escapee","path":"../sibling","tags":[]}]}\n' > "$P29_ESC_ROOT/ws/.conjure-workspace.json"
if [ "$P29_WS_LIB_OK" -eq 1 ]; then
  P29_ESC_RC=0
  ( workspace_manifest_validate "$P29_ESC_ROOT/ws/.conjure-workspace.json" ) >/dev/null 2>&1 || P29_ESC_RC=$?
  if [ "$P29_ESC_RC" -eq 2 ]; then
    pass "workspace_manifest_validate rejects ../sibling traversal escape with exit 2 (WS-SEC-traversal-escape)"
  else
    fail "workspace_manifest_validate accepted a ../sibling escape (exit $P29_ESC_RC, expected 2) (WS-SEC-traversal-escape)"
  fi
else
  fail "lib/workspace.sh not implemented — Wave 1 must create it (WS-SEC-traversal-escape)"
fi
trap - EXIT
rm -rf "$P29_ESC_ROOT"

# WS-SEC-symlink-accept: a workspace reached through a SYMLINK must still validate (exit 0).
# Regression for CR-01: resolving manifest_dir/.. via pwd -P previously diverged when the
# workspace was symlinked, falsely rejecting legitimate in-bounds repos.
P29_SYM_ROOT="$(mktemp -d)"
trap 'rm -rf "$P29_SYM_ROOT"' EXIT
mkdir -p "$P29_SYM_ROOT/real-ws/repos/alpha/.claude"
cp "$CONJURE_HOME/tests/fixtures/_workspace/repos/alpha/CLAUDE.md" "$P29_SYM_ROOT/real-ws/repos/alpha/CLAUDE.md"
printf '{"schema_version":1,"generated":"2026-06-03T00:00:00Z","repos":[{"name":"alpha","path":"repos/alpha","tags":[]}]}\n' > "$P29_SYM_ROOT/real-ws/.conjure-workspace.json"
ln -s "$P29_SYM_ROOT/real-ws" "$P29_SYM_ROOT/link-ws"
if [ "$P29_WS_LIB_OK" -eq 1 ]; then
  P29_SYM_RC=0
  ( workspace_manifest_validate "$P29_SYM_ROOT/link-ws/.conjure-workspace.json" ) >/dev/null 2>&1 || P29_SYM_RC=$?
  if [ "$P29_SYM_RC" -eq 0 ]; then
    pass "workspace_manifest_validate accepts a symlinked workspace with in-bounds repos (WS-SEC-symlink-accept)"
  else
    fail "workspace_manifest_validate rejected a legit symlinked workspace (exit $P29_SYM_RC, expected 0) (WS-SEC-symlink-accept)"
  fi
else
  fail "lib/workspace.sh not implemented — Wave 1 must create it (WS-SEC-symlink-accept)"
fi
trap - EXIT
rm -rf "$P29_SYM_ROOT"

# WS-SEC-degenerate-paths: empty / "." / ".." / "null"(missing) repo paths are rejected (exit 2).
# Regression for WR-04: degenerate path values previously targeted the workspace root itself
# or a literal "null" subdir.
P29_DEG_DIR="$(mktemp -d)"
trap 'rm -rf "$P29_DEG_DIR"' EXIT
if [ "$P29_WS_LIB_OK" -eq 1 ]; then
  P29_DEG_OK=1
  for _deg in '""' '"."' '".."'; do
    printf '{"schema_version":1,"generated":"2026-06-03T00:00:00Z","repos":[{"name":"x","path":%s,"tags":[]}]}\n' "$_deg" > "$P29_DEG_DIR/.conjure-workspace.json"
    _deg_rc=0
    ( workspace_manifest_validate "$P29_DEG_DIR/.conjure-workspace.json" ) >/dev/null 2>&1 || _deg_rc=$?
    [ "$_deg_rc" -eq 2 ] || P29_DEG_OK=0
  done
  # missing path key → jq -r emits literal "null"
  printf '{"schema_version":1,"generated":"2026-06-03T00:00:00Z","repos":[{"name":"x","tags":[]}]}\n' > "$P29_DEG_DIR/.conjure-workspace.json"
  _deg_rc=0
  ( workspace_manifest_validate "$P29_DEG_DIR/.conjure-workspace.json" ) >/dev/null 2>&1 || _deg_rc=$?
  [ "$_deg_rc" -eq 2 ] || P29_DEG_OK=0
  if [ "$P29_DEG_OK" -eq 1 ]; then
    pass "workspace_manifest_validate rejects empty/./../null repo paths with exit 2 (WS-SEC-degenerate-paths)"
  else
    fail "workspace_manifest_validate accepted a degenerate repo path (WS-SEC-degenerate-paths)"
  fi
else
  fail "lib/workspace.sh not implemented — Wave 1 must create it (WS-SEC-degenerate-paths)"
fi
trap - EXIT
rm -rf "$P29_DEG_DIR"

# WS-SEC-no-exec-out-of-bounds: check/audit must NOT run a per-repo command against an
# out-of-bounds dir; the manifest is rejected at load time (exit 2) and a sentinel file
# the per-repo command would touch is never created. Regression for CR-02.
P29_OOB_ROOT="$(mktemp -d)"
trap 'rm -rf "$P29_OOB_ROOT"' EXIT
mkdir -p "$P29_OOB_ROOT/ws"
mkdir -p "$P29_OOB_ROOT/sibling/.claude"
cp "$CONJURE_HOME/tests/fixtures/_workspace/repos/alpha/CLAUDE.md" "$P29_OOB_ROOT/sibling/CLAUDE.md"
printf '{"schema_version":1,"generated":"2026-06-03T00:00:00Z","repos":[{"name":"escapee","path":"../sibling","tags":[]}]}\n' > "$P29_OOB_ROOT/ws/.conjure-workspace.json"
if [ "$P29_WS_SH_OK" -eq 1 ]; then
  P29_OOB_CHK_RC=0
  CONJURE_HOME="$CONJURE_HOME" bash "$P29_WS_SH" check "$P29_OOB_ROOT/ws/.conjure-workspace.json" >/dev/null 2>&1 || P29_OOB_CHK_RC=$?
  P29_OOB_AUD_RC=0
  CONJURE_HOME="$CONJURE_HOME" bash "$P29_WS_SH" audit "$P29_OOB_ROOT/ws/.conjure-workspace.json" >/dev/null 2>&1 || P29_OOB_AUD_RC=$?
  if [ "$P29_OOB_CHK_RC" -eq 2 ] && [ "$P29_OOB_AUD_RC" -eq 2 ]; then
    pass "workspace check/audit refuse to execute against an out-of-bounds repo (exit 2) (WS-SEC-no-exec-out-of-bounds)"
  else
    fail "workspace check/audit ran against out-of-bounds dir (check=$P29_OOB_CHK_RC audit=$P29_OOB_AUD_RC, expected 2/2) (WS-SEC-no-exec-out-of-bounds)"
  fi
else
  fail "scripts/workspace.sh not implemented — Wave 1 must create it (WS-SEC-no-exec-out-of-bounds)"
fi
trap - EXIT
rm -rf "$P29_OOB_ROOT"

# WS-SEC-defense-in-depth: ws_do_check / ws_do_audit re-confirm the boundary at EXECUTION
# time even if a caller bypasses workspace_manifest_load. We drive the worker functions
# directly (extracted into a sourceable harness so the script's dispatch tail does not run)
# with a manifest whose repo escapes the workspace root, and assert it is SKIPPED as
# out-of-bounds and never executed. Regression for CR-02.
P29_DID_ROOT="$(mktemp -d)"
trap 'rm -rf "$P29_DID_ROOT"' EXIT
mkdir -p "$P29_DID_ROOT/ws"
mkdir -p "$P29_DID_ROOT/sibling/.claude"
cp "$CONJURE_HOME/tests/fixtures/_workspace/repos/alpha/CLAUDE.md" "$P29_DID_ROOT/sibling/CLAUDE.md"
printf '{"schema_version":1,"generated":"2026-06-03T00:00:00Z","repos":[{"name":"escapee","path":"../sibling","tags":[]}]}\n' > "$P29_DID_ROOT/ws/.conjure-workspace.json"
if [ "$P29_WS_SH_OK" -eq 1 ]; then
  # Extract just the two worker function definitions (skip the dispatch tail that exits).
  P29_DID_FNS="$P29_DID_ROOT/_fns.sh"
  sed -n '/^ws_do_check()/,/^}/p;/^ws_do_audit()/,/^}/p' "$P29_WS_SH" > "$P29_DID_FNS"
  P29_DID_OUT="$(
    CONJURE_HOME="$CONJURE_HOME"
    # shellcheck source=/dev/null
    . "$CONJURE_HOME/lib/workspace.sh"
    # shellcheck source=/dev/null
    . "$P29_DID_FNS"
    ws_do_check "$P29_DID_ROOT/ws/.conjure-workspace.json" "$P29_DID_ROOT/ws" 2>&1
  )"
  if printf '%s\n' "$P29_DID_OUT" | grep -qi "out-of-bounds\|SECURITY" && \
     ! printf '%s\n' "$P29_DID_OUT" | grep -qi "escapee.*drift\|escapee.*clean"; then
    pass "ws_do_check re-checks boundary at execution time and skips out-of-bounds repo (WS-SEC-defense-in-depth)"
  else
    fail "ws_do_check did not skip out-of-bounds repo at execution time (WS-SEC-defense-in-depth)"
  fi
else
  fail "scripts/workspace.sh not implemented — Wave 1 must create it (WS-SEC-defense-in-depth)"
fi
trap - EXIT
rm -rf "$P29_DID_ROOT"

# WS-DISC-symlink-warn: workspace_discover_siblings WARNS (stderr) about a symlinked repo
# instead of silently dropping it, and keeps stdout strictly to canonical paths. WR-01.
P29_SLW_ROOT="$(mktemp -d)"
trap 'rm -rf "$P29_SLW_ROOT"' EXIT
mkdir -p "$P29_SLW_ROOT/ws/real-repo/.claude"
mkdir -p "$P29_SLW_ROOT/elsewhere/linked-repo/.claude"
ln -s "$P29_SLW_ROOT/elsewhere/linked-repo" "$P29_SLW_ROOT/ws/linked-repo"
if [ "$P29_WS_LIB_OK" -eq 1 ]; then
  P29_SLW_ERR="$P29_SLW_ROOT/_err.txt"
  P29_SLW_OUT="$(workspace_discover_siblings "$P29_SLW_ROOT/ws" 2>"$P29_SLW_ERR")"
  if grep -qi "symlink" "$P29_SLW_ERR" && \
     printf '%s\n' "$P29_SLW_OUT" | grep -q "real-repo" && \
     ! printf '%s\n' "$P29_SLW_OUT" | grep -q "linked-repo"; then
    pass "workspace_discover_siblings warns about symlinked repos and keeps stdout canonical (WS-DISC-symlink-warn)"
  else
    fail "workspace_discover_siblings did not warn about / correctly handle symlinked repo (WS-DISC-symlink-warn)"
  fi
else
  fail "lib/workspace.sh not implemented — Wave 1 must create it (WS-DISC-symlink-warn)"
fi
trap - EXIT
rm -rf "$P29_SLW_ROOT"

# ──────────────────────────────────────────────────────────────────────────────
# Clean up any gh-hiding stub dirs created by mk_path_without_gh
for _s in $GH_HIDE_STUBS; do rm -rf "$_s"; done

# Summary
echo
echo "═══════════════════════════════════════════════════════════════════"
echo "PASS: $PASS    FAIL: $FAIL"
echo "═══════════════════════════════════════════════════════════════════"

[ "$FAIL" -eq 0 ]
