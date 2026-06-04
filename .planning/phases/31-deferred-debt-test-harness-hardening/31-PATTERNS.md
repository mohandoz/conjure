# Phase 31: Deferred Debt + Test-Harness Hardening - Pattern Map

**Mapped:** 2026-06-04
**Files analyzed:** 6 files to modify, 1 new file to create
**Analogs found:** 7 / 7

---

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `tests/run.sh` (skip/counter/summary/SCHM-STALE/live-section) | test harness | event-driven (pass/fail/skip) | `tests/run.sh` lines 10-16, 6706-6712 | exact — in-file extension |
| `tests/lib/sandbox.sh` (add `mk_tmpd()`, migrate `sandbox_setup`) | test utility | request-response | `tests/lib/sandbox.sh` lines 44-63 (existing `sandbox_setup`) | exact — in-file extension |
| `scripts/preflight.sh` (exit 1 → exit 2 at line 109) | script / guard | request-response | `scripts/preflight.sh` lines 100-109 | exact — in-file mechanical fix |
| `scripts/audit-setup.sh` (CONJURE_SCHEMA_FILE override at line 117) | script / config lookup | request-response | `scripts/audit-setup.sh` lines 113-127 | exact — in-file extension |
| `tests/run.sh` (SCHM-STALE test rework, lines 5107-5139) | test | CRUD | `tests/run.sh` lines 465-466, 512 (env-override-driven test invocation) | role-match |
| `FAILURE-MODES.md` (atomic-write mandate note) | documentation | — | `FAILURE-MODES.md` lines 168-178 (exit-code pattern note) | exact — same doc style |
| `tests/MANUAL-UAT.md` | documentation / checklist | — | None — new doc category; see style guidance below | no analog |

---

## Pattern Assignments

### `tests/run.sh` — `skip()` function, SKIP counter, strict-mode guard, summary line (DEBT-05)

**Analog:** `tests/run.sh` lines 10-16 and 6706-6712 (existing pass/fail infrastructure)

**Current counter + helper pattern** (lines 10-16):
```bash
PASS=0
FAIL=0
TESTS=()

t() { TESTS+=("$1"); }
pass() { echo "  ✓ $1"; PASS=$((PASS+1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL+1)); }
```

**Insert `skip()` directly after `fail()` at line 16** — follow the same one-line-per-helper shape; add `SKIP=0` beside `PASS=0`/`FAIL=0`:
```bash
PASS=0
FAIL=0
SKIP=0

pass() { echo "  ✓ $1"; PASS=$((PASS+1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL+1)); }
skip() {
  if [ "${CONJURE_STRICT:-0}" = "1" ]; then
    fail "$1 (SKIPPED in strict mode)"
  else
    printf "  ○ %s\n" "$1"; SKIP=$((SKIP+1))
  fi
}
```

**Current summary line** (lines 6706-6712):
```bash
echo "═══════════════════════════════════════════════════════════════════"
echo "PASS: $PASS    FAIL: $FAIL"
echo "═══════════════════════════════════════════════════════════════════"

[ "$FAIL" -eq 0 ]
```

**Modified summary — add SKIP column; exit stays `[ "$FAIL" -eq 0 ]`:**
```bash
echo "═══════════════════════════════════════════════════════════════════"
echo "PASS: $PASS    FAIL: $FAIL    SKIP: $SKIP"
echo "═══════════════════════════════════════════════════════════════════"

[ "$FAIL" -eq 0 ]
```

---

### `tests/run.sh` — Convention regression gate: no raw `$(mktemp -d)` outside sandbox.sh (DEBT-03)

**Analog:** `tests/run.sh` lines 125-130 (existing hook-exit-code convention gate)

**Existing convention gate shape** (lines 125-130):
```bash
echo
echo "▸ Hook exit codes"
while IFS= read -r hook; do
  if grep -qE '^exit 1$' "$hook"; then fail "hook uses 'exit 1' (should be 'exit 2' for blocks): $hook"
  else pass "exit codes ok: $hook"
  fi
done < <(find templates/hooks compliance/*/pre-commit-*.sh -name '*.sh' 2>/dev/null)
```

**New regression gate — same shape, place in the convention/smoke section near top of run.sh:**
```bash
echo
echo "▸ Convention: no raw \$(mktemp -d) in test files (use mk_tmpd)"
RAW_MKTEMP_HITS="$(grep -rn '\$(mktemp -d)' tests/ \
  --include='*.sh' \
  --exclude='sandbox.sh' 2>/dev/null || true)"
if [ -z "$RAW_MKTEMP_HITS" ]; then
  pass "convention: no raw \$(mktemp -d) outside sandbox.sh"
else
  fail "convention: raw \$(mktemp -d) found outside sandbox.sh"
  printf '%s\n' "$RAW_MKTEMP_HITS" | while IFS= read -r line; do
    printf "    %s\n" "$line"
  done
fi
```

---

### `tests/run.sh` — Live-system tests section, UAT-01 and UAT-02 (UAT-01/02)

**Analog:** `tests/run.sh` lines 459-512 (CONJURE_COST/CONJURE_EXACT gated section)

**Existing env-var gated section shape** (lines 459-466):
```bash
echo
echo "▸ Cost estimator tests (COST-01, COST-02, COST-03)"

COST_FX="$CONJURE_HOME/tests/fixtures/python-fastapi"
sandbox_setup "$COST_FX"
trap 'rm -rf "$SANDBOX_DIR"' EXIT

COST_OUT="$(CONJURE_COST=1 bash "$CONJURE_HOME/scripts/audit-setup.sh" "$SANDBOX_DIR" 2>&1)"
```

**Binary presence check pattern** (tests/run.sh line 35, mk_path_without_gh):
```bash
command -v gh >/dev/null 2>&1 || { printf '%s' "$PATH"; return 0; }
```

**New live-system section — place at end of run.sh, before cleanup + summary block:**
```bash
echo
echo "▸ Live-system tests"

# UAT-01: Live claude binary smoke (gated on CONJURE_LIVE_TEST=1 AND claude binary present)
if [ "${CONJURE_LIVE_TEST:-0}" = "1" ] && command -v claude >/dev/null 2>&1; then
  UAT01_DIR="$(mk_tmpd)"
  trap 'rm -rf "$UAT01_DIR"' EXIT
  # scaffold a minimal .claude-plugin/ and run claude plugin validate
  mkdir -p "$UAT01_DIR/.claude-plugin"
  # ... scaffold steps ...
  UAT01_RC=0
  (cd "$UAT01_DIR" && claude plugin validate .) >/dev/null 2>&1 || UAT01_RC=$?
  if [ "$UAT01_RC" -eq 0 ]; then
    pass "live: claude plugin validate accepts scaffolded .claude-plugin/ (UAT-01)"
  else
    fail "live: claude plugin validate failed on scaffolded .claude-plugin/ (UAT-01)"
  fi
  trap - EXIT; rm -rf "$UAT01_DIR"
elif [ "${CONJURE_LIVE_TEST:-0}" = "1" ]; then
  skip "live claude smoke: claude binary not found — install claude CLI (UAT-01)"
else
  skip "live claude smoke: CONJURE_LIVE_TEST not set (UAT-01)"
fi

# UAT-02: Live promptfoo eval probe (gated on ANTHROPIC_API_KEY non-empty)
if [ -n "${ANTHROPIC_API_KEY:-}" ]; then
  UAT02_DIR="$(mk_tmpd)"
  trap 'rm -rf "$UAT02_DIR"' EXIT
  # Build 1-test promptfooconfig.yaml inline
  cat > "$UAT02_DIR/promptfooconfig.yaml" << 'PFEOF'
providers: [...]
tests: [...]
PFEOF
  UAT02_RC=0
  npx --yes "promptfoo@${PROMPTFOO_VERSION:-0.121.14}" eval -c "$UAT02_DIR/promptfooconfig.yaml" >/dev/null 2>&1 || UAT02_RC=$?
  if [ "$UAT02_RC" -eq 0 ]; then
    pass "live: promptfoo 1-test eval probe passes (UAT-02)"
  else
    fail "live: promptfoo 1-test eval probe failed (UAT-02)"
  fi
  trap - EXIT; rm -rf "$UAT02_DIR"
else
  skip "live promptfoo eval: ANTHROPIC_API_KEY not set (UAT-02)"
fi
```

**ANTHROPIC_API_KEY advisory reference** (`scripts/eval.sh` lines 276-278):
```bash
# ANTHROPIC_API_KEY advisory (warn only — do not exit; may be set in env)
if [ -z "${ANTHROPIC_API_KEY:-}" ]; then
  echo "warn: ANTHROPIC_API_KEY not set — set it for LLM-graded assertions" >&2
fi
```

---

### `tests/run.sh` — SCHM-STALE test rework (DEBT-06)

**Analog:** `tests/run.sh` lines 465, 512 (env-var-driven script invocations)

**Existing env-override invocation shape** (line 512):
```bash
EXACT_OUT="$(CONJURE_COST=1 CONJURE_EXACT=1 ANTHROPIC_API_KEY="" bash "$CONJURE_HOME/scripts/audit-setup.sh" "$SANDBOX_DIR" 2>&1)"
```

**Current SCHM-STALE swap to REPLACE** (lines 5118-5126):
```bash
# Temporarily swap lib/cc-schema.json for the stale fixture  ← REPLACE THIS
P27_STALE_SCHEMA_BAK="$(mktemp)"
cp "$P27_SCHEMA_FILE" "$P27_STALE_SCHEMA_BAK"
cp "$CONJURE_HOME/tests/fixtures/_schema-audit-stale/cc-schema-stale.json" "$P27_SCHEMA_FILE"
P27_STALE_RC=0
P27_STALE_OUT="$(CONJURE_HOME="$CONJURE_HOME" bash "$P27_AUDIT_SH" "$P27_STALE_DIR" 2>&1)" || P27_STALE_RC=$?
# Restore original schema immediately
cp "$P27_STALE_SCHEMA_BAK" "$P27_SCHEMA_FILE"
rm -f "$P27_STALE_SCHEMA_BAK"
```

**Replacement — env-override, no production file touched:**
```bash
# DEBT-06: use CONJURE_SCHEMA_FILE override — production lib/cc-schema.json never touched
P27_STALE_RC=0
P27_STALE_OUT="$(CONJURE_HOME="$CONJURE_HOME" \
  CONJURE_SCHEMA_FILE="$CONJURE_HOME/tests/fixtures/_schema-audit-stale/cc-schema-stale.json" \
  bash "$P27_AUDIT_SH" "$P27_STALE_DIR" 2>&1)" || P27_STALE_RC=$?
```

---

### `tests/lib/sandbox.sh` — `mk_tmpd()` helper + `sandbox_setup()` migration (DEBT-03)

**Analog:** `tests/lib/sandbox.sh` lines 35-63 (existing helper + `sandbox_setup` function)

**Existing helper function style** (lines 35-42):
```bash
# _sandbox_tool_dir <name> — echo the parent dir of <name>, or nothing if absent.
_sandbox_tool_dir() {
  local _p
  _p="$(command -v "$1" 2>/dev/null || true)"
  [ -n "$_p" ] && dirname "$_p"
}
```

**Existing raw `mktemp -d` in `sandbox_setup`** (line 48):
```bash
SANDBOX_DIR="$(mktemp -d)"
```

**New `mk_tmpd()` — add above `sandbox_setup`, follow `_sandbox_tool_dir` style:**
```bash
# mk_tmpd — create a temporary directory and abort the suite on mktemp failure.
# Use this everywhere instead of raw $(mktemp -d) so git -C never sees an empty var.
# Exits 2 (not 1) per project convention (CLAUDE.md constraints).
mk_tmpd() {
  local _d
  _d="$(mktemp -d)"
  if [ -z "$_d" ] || [ ! -d "$_d" ]; then
    printf "FATAL: mktemp -d failed — aborting test suite\n" >&2
    exit 2
  fi
  printf '%s' "$_d"
}
```

**`sandbox_setup()` migration — replace raw `mktemp -d` at line 48:**
```bash
# Before:
SANDBOX_DIR="$(mktemp -d)"
# After:
SANDBOX_DIR="$(mk_tmpd)"
```

**Sweep pattern for `tests/run.sh`** — replace every `VAR="$(mktemp -d)"` with `VAR="$(mk_tmpd)"`. Example from line 227:
```bash
# Before:
TMPDIR_TARGET="$(mktemp -d)"
# After:
TMPDIR_TARGET="$(mk_tmpd)"
```

---

### `scripts/preflight.sh` — exit 1 → exit 2 at line 109 (DEBT-04)

**Analog:** `scripts/preflight.sh` lines 100-109 (the block being changed)

**Current code** (lines 100-109):
```bash
  if command -v "$dep" >/dev/null 2>&1; then
    printf "  ✓ %s\n" "$dep"
  else
    printf "  ✗ %s missing (required)\n" "$dep"
    _fixup "$dep" "$OS"
    REQUIRED_FAILED=1
  fi
done

[ "$REQUIRED_FAILED" -eq 1 ] && exit 1
```

**Modified line 109 only:**
```bash
[ "$REQUIRED_FAILED" -eq 1 ] && exit 2
```

**Caller audit evidence** (all 4 callers in `cli/conjure` at lines 84, 172, 174, 234 use generic non-zero check — safe):
```bash
cmd_preflight || return 1          # line 84 — generic non-zero, unaffected
cmd_preflight >/dev/stderr 2>&1 || return 1   # line 172 — generic non-zero, unaffected
cmd_preflight || return 1          # line 174 — generic non-zero, unaffected
cmd_preflight || return 1          # line 234 — generic non-zero, unaffected
```

---

### `scripts/audit-setup.sh` — CONJURE_SCHEMA_FILE env override at line 117 (DEBT-06)

**Analog:** `scripts/audit-setup.sh` lines 113-127 (the schema lookup block being extended)

**Current schema lookup** (line 117):
```bash
SCHEMA_FILE="${CONJURE_HOME}/lib/cc-schema.json"
```

**Modified — add env override + safety comment:**
```bash
# SAFETY: Never write directly to cc-schema.json. Any future write path MUST use:
#   jq ... > "$_tmp" && mv "$_tmp" "$SCHEMA_FILE"   (POSIX mv is atomic same-fs)
# CONJURE_SCHEMA_FILE allows tests to point at a fixture without touching the
# production file — kill-safe by construction (DEBT-06).
SCHEMA_FILE="${CONJURE_SCHEMA_FILE:-${CONJURE_HOME}/lib/cc-schema.json}"
```

---

### `FAILURE-MODES.md` — atomic-write mandate note (DEBT-06)

**Analog:** `FAILURE-MODES.md` lines 168-178 (existing exit-code failure-mode entry — same symptom/cause/fix structure)

**Existing note style** (lines 168-178):
```markdown
## Hook script has wrong exit code

**Symptom**: Destructive action you intended to block proceeded.

**Cause**: Hook used `exit 1` (non-blocking) instead of `exit 2` (block).

**Fix**: Audit all hooks:
```bash
grep -nE '^exit 1$' .claude/hooks/*.sh
# Change to: exit 2
```
```

**New entry to append — same symptom/cause/fix structure:**
```markdown
## Test interrupted mid-swap corrupts production file

**Symptom**: `lib/cc-schema.json` has a `generated` date older than the
project's VERSION release date after running tests.

**Cause**: A test that directly overwrites a production file (via `cp fixture
prod_file`) was interrupted by SIGKILL between the fixture-copy and the
restore-copy. bash `trap` does not fire on SIGKILL, so the fixture is left
as the live file.

**Fix** (after incident):
```bash
# Restore from git
git checkout lib/cc-schema.json
```

**Prevention mandate**: Tests MUST NOT write directly to production kit files.
Use an env override (`CONJURE_SCHEMA_FILE=<fixture-path>`) so the production
file is never touched. If a write path must exist in production code, always
use the atomic pattern:
```bash
jq ... > "$_tmp" && mv "$_tmp" "$target"  # POSIX mv is atomic same-fs
```
A direct `>` or `cp` to a live file is not kill-safe.
```

---

### `tests/MANUAL-UAT.md` — new checklist file (UAT-03)

**Analog:** No existing manual UAT file. Closest style reference: `FAILURE-MODES.md` (same doc family — markdown, code blocks, structured sections). No code pattern to copy.

**Structure mandate from D-10:**
- One section per manual item
- Each section: prerequisites, numbered steps, expected result, `- [ ]` checkboxes, date/version field
- Cover: MDM hardware (macOS plist + Windows PS1), managed-settings deploy
- Cover: `claude plugin validate` live smoke (deferred Phase 25 HUMAN-UAT)

---

## Shared Patterns

### Exit code convention: `exit 2`, never `exit 1`
**Source:** `CLAUDE.md` (constraints), `scripts/preflight.sh` line 109 (being fixed), hook convention gate `tests/run.sh:125-130`
**Apply to:** `mk_tmpd()` fatal exit, DEBT-04 fix in `preflight.sh`
```bash
exit 2   # not exit 1 — project convention
```

### Env-var gating with conditional skip
**Source:** `tests/run.sh` lines 21-25, 465, 512 (IS_WINDOWS, CONJURE_COST, CONJURE_EXACT patterns)
**Apply to:** UAT-01 (`CONJURE_LIVE_TEST`), UAT-02 (`ANTHROPIC_API_KEY`), strict-mode (`CONJURE_STRICT`)
```bash
if [ "${CONJURE_LIVE_TEST:-0}" = "1" ] && command -v claude >/dev/null 2>&1; then
  # run live test
elif ...; then
  skip "reason (UAT-XX)"
else
  skip "reason (UAT-XX)"
fi
```

### POSIX binary presence check
**Source:** `tests/run.sh` line 35 (`command -v gh`), `tests/run.sh` line 76 (`command -v jq`), `tests/run.sh` line 157 (`command -v node`), `tests/run.sh` line 190 (`command -v shellcheck`)
**Apply to:** UAT-01 claude-binary check, `mk_tmpd()` (no check needed — `mktemp` is POSIX guaranteed)
```bash
command -v <binary> >/dev/null 2>&1
```

### Section header format
**Source:** `tests/run.sh` lines 63, 86, 101, 125, 145 (all `▸ <label>` sections)
**Apply to:** New `▸ Live-system tests` section and new convention regression gate section
```bash
echo
echo "▸ Section label"
```

### Trap cleanup pattern for temporary directories
**Source:** `tests/run.sh` lines 227-228, 463, 5109 (trap + rm -rf)
**Apply to:** UAT-01 and UAT-02 temp sandboxes; release trap before manual rm
```bash
UAT01_DIR="$(mk_tmpd)"
trap 'rm -rf "$UAT01_DIR"' EXIT
# ... test work ...
trap - EXIT; rm -rf "$UAT01_DIR"
```

---

## No Analog Found

| File | Role | Data Flow | Reason |
|------|------|-----------|--------|
| `tests/MANUAL-UAT.md` | documentation | — | No existing manual UAT checklist document in the project; planner should model on D-10 spec and `FAILURE-MODES.md` doc style |

---

## Metadata

**Analog search scope:** `tests/run.sh`, `tests/lib/sandbox.sh`, `scripts/preflight.sh`, `scripts/audit-setup.sh`, `scripts/eval.sh`, `scripts/workspace.sh`, `cli/conjure`, `FAILURE-MODES.md`
**Files scanned:** 8
**Pattern extraction date:** 2026-06-04
