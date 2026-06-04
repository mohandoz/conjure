# Phase 31: Deferred Debt + Test-Harness Hardening - Research

**Researched:** 2026-06-04
**Domain:** POSIX bash test harness, exit-code conventions, kill-safe file I/O, env-var gating
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**SKIP semantics (DEBT-05):**
- D-01: `skip()` prints `  ○ <name> (reason)` inline at the point of skip, mirroring existing `pass()`/`fail()` style.
- D-02: Summary line becomes `PASS: N    FAIL: N    SKIP: N`.
- D-03: SKIP never affects exit code by default — exit stays `[ "$FAIL" -eq 0 ]`.
- D-04: Strict mode via env var `CONJURE_STRICT=1`. In strict mode `skip()` routes to `fail()` with the reason — exits non-zero via existing FAIL path. Intended for release machines where live tests MUST run.
- D-05: `skip()` applies to NEW gates only (UAT-01/02 and future gated tests). Existing soft gates (`IS_WINDOWS`, `PERF_CEILING`, gh-absent paths) are NOT migrated — zero regression risk.

**Live-test gating (UAT-01/02/03):**
- D-06: Gates follow roadmap success criteria: claude smoke runs when `CONJURE_LIVE_TEST=1` AND `command -v claude` succeeds (skip with reason otherwise); promptfoo eval runs when `ANTHROPIC_API_KEY` is non-empty (skip otherwise).
- D-07: Live tests live inline in `tests/run.sh` as a new gated `▸ Live-system tests` section at the end.
- D-08: The claude-binary smoke exercises `claude plugin validate` against a scaffolded `.claude-plugin/` — the exact deferred Phase 25 HUMAN-UAT item. Narrow, deterministic, consumes no API tokens.
- D-09: The live promptfoo eval is a minimal probe: 1-test eval in a temp sandbox proving live enforcement wiring. One API call per run.
- D-10: `tests/MANUAL-UAT.md` uses checklist-per-scenario format: one section per manual item (MDM hardware: macOS plist + Windows PS1; managed-settings deploy), each with prerequisites, numbered steps, expected result, `- [ ]` checkboxes, and a field to record date/version verified.

**git -C guard (DEBT-03):**
- D-11: Root-cause fix via a single `mk_tmpd()` helper in `tests/lib/sandbox.sh`: wraps `mktemp -d`, verifies result non-empty AND directory exists, hard-exits the suite (exit 2) on failure. `git -C` call sites need no change.
- D-12: Sweep scope: ALL test files — `tests/run.sh`, `tests/lib/sandbox.sh` (including `sandbox_setup`'s own `mktemp`), and any `tests/*.sh` helpers. Production `scripts/` untouched.
- D-13: Regression gate: a self-test in `run.sh` greps `tests/` for raw `$(mktemp -d)` outside `sandbox.sh` and fails on new offenders.

**SCHM-STALE kill-safety (DEBT-06):**
- D-14: Eliminate the swap entirely: add a `CONJURE_SCHEMA_FILE` env override to the schema lookup in `scripts/audit-setup.sh`; the SCHM-STALE test points it at the stale fixture. Production `lib/cc-schema.json` is never touched.
- D-15: No speculative `_atomic_write()` helper. Add a comment block at the schema lookup in `audit-setup.sh` mandating tmp-&&-mv atomic swap for any future `cc-schema.json` write. Note also in FAILURE-MODES.md.
- D-16: Quick audit of other tests mutating production kit files in place; any other production-file swap gets the same no-swap/env-override (or trap) treatment.

**DEBT-04 rollout (Claude's Discretion):**
- Scout confirmed `scripts/preflight.sh:109` holds the sole `exit 1`; all callers (`cli/conjure:84,172,174,234`) use generic `|| return 1` with no `$? -eq 1` equality checks. Mechanical change + caller-audit note in the plan; planner decides where to record the audit evidence.
- Exact `skip()` glyph/wording, section placement details, MANUAL-UAT.md exact headings — planner/executor judgment within the decisions above.

### Deferred Ideas (OUT OF SCOPE)
- Migrating existing soft gates (`IS_WINDOWS`, `PERF_CEILING`, gh-absent) onto `skip()` for fully accurate SKIP counts — optional future debt, not this phase.
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| DEBT-03 | Test sandboxes guard `git -C "$VAR"` with a non-empty check after every `mktemp` (closes proven sandbox-escape vector) | `mk_tmpd()` helper in `tests/lib/sandbox.sh`; sweeps 216 raw `mktemp` calls in `tests/run.sh`; regression gate via grep self-test |
| DEBT-04 | `preflight.sh` exits 2 (never 1), with caller audit confirming no `$? -eq 1` equality checks break | Single `exit 1` at `scripts/preflight.sh:109`; all 4 callers use generic `\|\| return 1` — safe mechanical change |
| DEBT-05 | `tests/run.sh` supports a `skip()` counter — PASS/FAIL/SKIP reporting for gated tests | `skip()` slots beside existing `pass()`/`fail()` at lines 10-16; `SKIP=0` counter initialized alongside `PASS`/`FAIL` |
| DEBT-06 | SCHM-STALE swap verified kill-safe; atomic `jq > tmp && mv` applied where write path exists, documented otherwise | Replace cp-swap at `tests/run.sh:5107-5139` with `CONJURE_SCHEMA_FILE` env override; document pattern in `audit-setup.sh` comment + `FAILURE-MODES.md` |
| UAT-01 | User can run a gated live `claude`-binary smoke test (`CONJURE_LIVE_TEST=1` + `command -v claude`); skipped cleanly otherwise | New `▸ Live-system tests` section in `tests/run.sh`; gates `claude plugin validate` smoke behind both env var and binary presence |
| UAT-02 | User can run a gated live promptfoo eval (requires `ANTHROPIC_API_KEY`); skipped cleanly otherwise | Minimal 1-test eval probe in temp sandbox; gates on `ANTHROPIC_API_KEY` non-empty; existing `scripts/eval.sh:277` advisory is the reference |
| UAT-03 | `tests/MANUAL-UAT.md` documents manual-only verification steps (MDM hardware, managed-settings deploy) with checklists | New file `tests/MANUAL-UAT.md`; addresses Phase 25 HUMAN-UAT (live claude --validate) + Phase 26 HUMAN-UAT (MDM hardware, managed-settings deploy) deferred items |
</phase_requirements>

---

## Summary

Phase 31 closes seven items of safety-critical debt deferred from v0.7.0. Four are test-harness fixes (DEBT-03 through DEBT-06); three are live-system UAT items (UAT-01 through UAT-03). There are no new user-facing features — `conjure doctor`, `stats`, and eval expansion belong to Phases 32–34.

The work divides into five clean workstreams that share no implementation dependencies and can be planned as sequential waves or independent tasks:

1. **DEBT-04** — one-line change (`exit 1` → `exit 2`) in `scripts/preflight.sh:109` plus a caller audit note. No ripple effect. Fastest item in the phase.
2. **DEBT-05** — add `SKIP=0` counter, `skip()` function, strict-mode guard, and update the summary line in `tests/run.sh`. Self-contained; no callers change.
3. **DEBT-03** — add `mk_tmpd()` helper to `tests/lib/sandbox.sh`, migrate `sandbox_setup()`'s raw `mktemp`, sweep all raw `$(mktemp -d)` call sites in `tests/run.sh` (216 occurrences), add a grep-gate self-test.
4. **DEBT-06** — replace the `cp`-swap in the SCHM-STALE test (lines 5107-5139 of `tests/run.sh`) with a `CONJURE_SCHEMA_FILE` env override; add the env override hook to `scripts/audit-setup.sh:117`; add documentation in `FAILURE-MODES.md` or an `audit-setup.sh` comment.
5. **UAT-01/02/03** — add a `▸ Live-system tests` section at the end of `tests/run.sh` using the new `skip()` helper; create `tests/MANUAL-UAT.md` with checklists for MDM and managed-settings scenarios.

**Primary recommendation:** Plan as five sequential tasks in the order above. DEBT-04 and DEBT-05 unblock the others because the live-test gates (UAT-01/02) depend on `skip()` and `CONJURE_STRICT`. DEBT-03's `mk_tmpd()` is needed before DEBT-06's updated SCHM-STALE test can use it safely.

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| `skip()` helper + SKIP counter | Test harness (`tests/run.sh`) | — | Single file owns all pass/fail/skip state; no external consumers |
| `mk_tmpd()` guard | Test support lib (`tests/lib/sandbox.sh`) | Test harness | Helper is sourced by `run.sh`; centralising in the lib prevents divergence |
| `CONJURE_SCHEMA_FILE` override | Production script (`scripts/audit-setup.sh`) | Test harness | The env hook lives in the script-under-test so tests can drive it without file mutations |
| `preflight.sh` exit code fix | Production script (`scripts/preflight.sh`) | CLI (`cli/conjure`) | Callers gate on non-zero, not on `$? -eq 1`; change is safe at the source |
| Live `claude` smoke gate | Test harness (`tests/run.sh`) | — | Inline in the suite, gated by env var + binary check |
| Live promptfoo eval gate | Test harness (`tests/run.sh`) | — | Inline in the suite, gated by `ANTHROPIC_API_KEY` |
| Manual UAT checklists | Document (`tests/MANUAL-UAT.md`) | — | New file; no code dependency |

---

## Standard Stack

### Core
| Tool | Source | Purpose | Why Standard |
|------|--------|---------|--------------|
| POSIX bash 3.2+ | Runtime (project constraint) | All shell changes | Cross-platform; macOS ships 3.2; no associative arrays, no mapfile |
| `mktemp -d` | POSIX stdlib | Temporary directory creation | Already used throughout; `mk_tmpd()` wraps it |
| `jq` | System dep (preflight gate) | JSON queries in audit-setup.sh | Already required; `CONJURE_SCHEMA_FILE` uses same `jq` path |
| `git -C` | System dep (preflight gate) | Git operations in test sandboxes | Already used 271 times in `tests/run.sh` |
| `command -v` | POSIX shell builtin | Binary presence check for live gates | Already used for `gh`, `shellcheck`, etc. |

### No New Dependencies

[VERIFIED: codebase] `dependencies: {}` stays empty. Every change in this phase uses tools already required by `scripts/preflight.sh`. No npm packages, no new system tools. [CITED: CLAUDE.md tech-stack constraint]

---

## Package Legitimacy Audit

No external packages are installed in this phase. All changes use project-internal bash, `mktemp`, `jq`, and `git` already in the preflight stack.

**Packages removed due to slopcheck:** none (no external packages)
**Packages flagged as suspicious:** none

---

## Architecture Patterns

### System Architecture Diagram

```
tests/run.sh
  │
  ├─ source tests/lib/sandbox.sh
  │    └─ mk_tmpd()        ← NEW: wraps mktemp -d + non-empty guard + exit 2 on failure
  │    └─ sandbox_setup()  ← MODIFIED: use mk_tmpd() instead of raw mktemp -d
  │
  ├─ skip() / SKIP counter  ← NEW: alongside pass() / fail() at top of run.sh
  │    └─ CONJURE_STRICT=1 → skip() routes to fail()
  │
  ├─ ▸ [existing test sections — unchanged]
  │
  ├─ ▸ SCHM-STALE test (lines 5107-5139)  ← MODIFIED: drop cp-swap, use CONJURE_SCHEMA_FILE
  │
  └─ ▸ Live-system tests (NEW section at end)
       ├─ UAT-01: CONJURE_LIVE_TEST=1 + command -v claude → claude plugin validate smoke
       └─ UAT-02: ANTHROPIC_API_KEY non-empty → promptfoo 1-test probe

scripts/audit-setup.sh (line 117)  ← MODIFIED: SCHEMA_FILE=${CONJURE_SCHEMA_FILE:-...}
scripts/preflight.sh (line 109)    ← MODIFIED: exit 1 → exit 2
tests/MANUAL-UAT.md                ← NEW: MDM + managed-settings checklists
FAILURE-MODES.md                   ← MODIFIED: note on tmp-&&-mv atomic write mandate
```

### Recommended Project Structure

No structural changes. All changes modify existing files or create one new file:
```
tests/
  run.sh           (modified — skip(), mk_tmpd migration, live-test section, SCHM-STALE fix)
  lib/
    sandbox.sh     (modified — add mk_tmpd(), update sandbox_setup())
  MANUAL-UAT.md   (NEW)
scripts/
  preflight.sh    (modified — exit 1 → exit 2 at line 109)
  audit-setup.sh  (modified — CONJURE_SCHEMA_FILE env override + documentation comment)
FAILURE-MODES.md  (modified — atomic-write mandate note)
```

### Pattern 1: skip() Helper With Strict-Mode Guard

**What:** A 4-line bash function that increments `SKIP` and optionally escalates to `fail()`.
**When to use:** Any test that requires an external resource (binary, API key, hardware).

```bash
# Source: tests/run.sh (lines 10-16 region) — extend existing pass/fail pattern
PASS=0
FAIL=0
SKIP=0

pass() { printf "  ✓ %s\n" "$1"; PASS=$((PASS+1)); }
fail() { printf "  ✗ %s\n" "$1"; FAIL=$((FAIL+1)); }
skip() {
  if [ "${CONJURE_STRICT:-0}" = "1" ]; then
    fail "$1 (SKIPPED in strict mode)"
  else
    printf "  ○ %s\n" "$1"; SKIP=$((SKIP+1))
  fi
}
```

Summary line update (tail of run.sh):
```bash
# Before:
echo "PASS: $PASS    FAIL: $FAIL"
# After:
echo "PASS: $PASS    FAIL: $FAIL    SKIP: $SKIP"
```

[VERIFIED: codebase] Existing pattern at `tests/run.sh:10-16`.

### Pattern 2: mk_tmpd() Wrapper

**What:** A helper that calls `mktemp -d`, validates the result, and exits 2 if mktemp fails. All callers use `mk_tmpd` instead of `$(mktemp -d)` directly.
**When to use:** Every temporary directory creation in test code.

```bash
# Source: tests/lib/sandbox.sh — new helper
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

Usage in `tests/run.sh` (replace raw `$(mktemp -d)`):
```bash
# Before:
TMPDIR_TARGET="$(mktemp -d)"
# After:
TMPDIR_TARGET="$(mk_tmpd)"
```

`sandbox_setup()` in `tests/lib/sandbox.sh` also migrates:
```bash
# Before (line 48):
SANDBOX_DIR="$(mktemp -d)"
# After:
SANDBOX_DIR="$(mk_tmpd)"
```

[VERIFIED: codebase] `sandbox.sh:48` and `run.sh:227` are representative raw-mktemp sites.

### Pattern 3: CONJURE_SCHEMA_FILE Env Override (DEBT-06)

**What:** `scripts/audit-setup.sh` resolves the schema file through an env override, so tests can point at a stale fixture without touching `lib/cc-schema.json`.
**When to use:** Any test needing a different schema file than the production one.

```bash
# Source: scripts/audit-setup.sh line ~117 — modified lookup
# SAFETY NOTE: Never write directly to cc-schema.json. Any future write path MUST
# use: jq ... > "$tmp" && mv "$tmp" "$SCHEMA_FILE"  (POSIX mv is atomic same-fs)
SCHEMA_FILE="${CONJURE_SCHEMA_FILE:-${CONJURE_HOME}/lib/cc-schema.json}"
```

Test usage (replaces the cp-swap at `tests/run.sh:5107-5139`):
```bash
# Before: cp production schema, swap, test, restore (NOT kill-safe)
P27_STALE_SCHEMA_BAK="$(mktemp)"
cp "$P27_SCHEMA_FILE" "$P27_STALE_SCHEMA_BAK"
cp "$CONJURE_HOME/tests/fixtures/_schema-audit-stale/cc-schema-stale.json" "$P27_SCHEMA_FILE"
# ... run audit ...
cp "$P27_STALE_SCHEMA_BAK" "$P27_SCHEMA_FILE"

# After: env override, no production file touched (kill-safe by construction)
P27_STALE_RC=0
P27_STALE_OUT="$(CONJURE_HOME="$CONJURE_HOME" \
  CONJURE_SCHEMA_FILE="$CONJURE_HOME/tests/fixtures/_schema-audit-stale/cc-schema-stale.json" \
  bash "$P27_AUDIT_SH" "$P27_STALE_DIR" 2>&1)" || P27_STALE_RC=$?
```

[VERIFIED: codebase] The cp-swap is at `tests/run.sh:5118-5126`; `audit-setup.sh:117` is the schema lookup.

### Pattern 4: Live-Test Gating

**What:** Environment variable guards that allow live tests to skip cleanly in standard CI but execute on request.
**When to use:** Tests requiring real external binaries or API keys.

```bash
# Source: established pattern — CONJURE_COST, CONJURE_EXACT, IS_WINDOWS in tests/run.sh
echo
echo "▸ Live-system tests"

# UAT-01: Live claude binary smoke
if [ "${CONJURE_LIVE_TEST:-0}" = "1" ] && command -v claude >/dev/null 2>&1; then
  # scaffold a minimal .claude-plugin/ in a temp dir and run claude plugin validate
  UAT01_DIR="$(mk_tmpd)"
  trap 'rm -rf "$UAT01_DIR"' EXIT
  # ... scaffold and run ...
  if claude plugin validate "$UAT01_DIR" >/dev/null 2>&1; then
    pass "live: claude plugin validate accepts scaffolded .claude-plugin/ (UAT-01)"
  else
    fail "live: claude plugin validate failed on scaffolded .claude-plugin/ (UAT-01)"
  fi
  trap - EXIT; rm -rf "$UAT01_DIR"
elif [ "${CONJURE_LIVE_TEST:-0}" = "1" ]; then
  skip "live claude smoke: claude binary not found (UAT-01)"
else
  skip "live claude smoke: CONJURE_LIVE_TEST not set (UAT-01)"
fi

# UAT-02: Live promptfoo eval probe
if [ -n "${ANTHROPIC_API_KEY:-}" ]; then
  # 1-test eval in temp sandbox
  # ...
  pass "live: promptfoo 1-test eval probe passes (UAT-02)"
else
  skip "live promptfoo eval: ANTHROPIC_API_KEY not set (UAT-02)"
fi
```

[VERIFIED: codebase] Pattern matches existing `CONJURE_COST=1` gates at `run.sh:465,512`.

### Pattern 5: Regression Gate for Raw mktemp

**What:** A self-test that greps test files for raw `$(mktemp -d)` outside `sandbox.sh` and fails on offenders. Catches future drift.
**When to use:** Convention enforcement — same shape as the existing `exit 1` hook grep at `run.sh:126-130`.

```bash
# Convention gate: no raw $(mktemp -d) outside sandbox.sh
echo
echo "▸ Convention: no raw mktemp -d in test files (use mk_tmpd)"
RAW_MKTEMP_HITS="$(grep -rn '\$(mktemp -d)' tests/ \
  --include='*.sh' \
  --exclude='sandbox.sh' 2>/dev/null || true)"
if [ -z "$RAW_MKTEMP_HITS" ]; then
  pass "convention: no raw \$(mktemp -d) outside sandbox.sh"
else
  fail "convention: raw \$(mktemp -d) found outside sandbox.sh:"
  printf '%s\n' "$RAW_MKTEMP_HITS" | while IFS= read -r line; do
    printf "    %s\n" "$line"
  done
fi
```

[VERIFIED: codebase] Modeled on `run.sh:123-130` hook-exit-code gate.

### Anti-Patterns to Avoid

- **In-place swap of production files in tests:** `cp prod_file bak && cp fixture prod_file` is not kill-safe. A SIGKILL between the writes ships the fixture as the real file (exact incident from RETROSPECTIVE.md:159). Use env overrides instead.
- **`$? -eq 1` equality check on callers of preflight:** All callers use `|| return 1` (generic non-zero). Never add an equality check — it would break with `exit 2`.
- **Skipping tests silently without `skip()`:** A bare `if command -v claude; then ...test...; fi` with no `else` makes coverage invisible. Always emit a skip verdict.
- **`sort -V` for version comparison:** GNU extension, not available on macOS bash 3.2. Not relevant here but flagged for context (Phase 32 uses `_ver_gte` instead).
- **Calling `mk_tmpd()` without sourcing `sandbox.sh`:** `mk_tmpd` is defined in `tests/lib/sandbox.sh`; `run.sh` already sources it at line 8. No change needed to the source line.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Kill-safe file update | trap-based restore with `cp` and `rm` | env override (`CONJURE_SCHEMA_FILE`) pointing test at fixture | SIGKILL defeats traps; env override never touches production file |
| Binary presence check | Custom probing logic | `command -v <binary>` | POSIX standard, already used throughout the project for `gh`, `shellcheck`, etc. |
| Semver comparison | `sort -V` | Not needed in this phase; `_ver_gte` in Phase 32 | `sort -V` is GNU extension; breaks macOS bash 3.2 |
| skip() escalation | Separate `skip_strict()` function | `CONJURE_STRICT=1` routes `skip()` to `fail()` | One function, one env var, consistent with existing `CONJURE_COST`/`CONJURE_EXACT` pattern |

---

## Common Pitfalls

### Pitfall 1: mktemp Failure Mode is Silent
**What goes wrong:** `TMPDIR="$(mktemp -d)"` sets `TMPDIR` to an empty string if `mktemp` fails (disk full, `/tmp` permissions). Subsequent `git -C "$TMPDIR"` operates on CWD — the real conjure repo.
**Why it happens:** `set -uo pipefail` catches unset variables but `mktemp -d` returns exit 0 and prints nothing on some failure modes.
**How to avoid:** `mk_tmpd()` validates non-empty AND directory exists, exits 2 if either check fails.
**Warning signs:** Tests that mutate the conjure repo's git history when run under low-disk conditions.

### Pitfall 2: SCHM-STALE Test Interruption Corrupts Production Schema
**What goes wrong:** `tests/run.sh:5118-5126` copies the stale fixture OVER `lib/cc-schema.json`, then restores on completion. A SIGKILL between lines 5121 and 5125 leaves the stale schema as the production file.
**Why it happens:** bash `trap` does not fire on SIGKILL (kernel signal — untrappable).
**How to avoid:** Replace the cp-swap with `CONJURE_SCHEMA_FILE=<stale-fixture-path>` env override. Production file is never touched.
**Warning signs:** `lib/cc-schema.json` has a `generated` date older than the project's VERSION release date after running tests.

### Pitfall 3: Callers Break When preflight.sh exit Code Changes
**What goes wrong:** Changing `preflight.sh:109` from `exit 1` to `exit 2` could break a caller doing `if [ $? -eq 1 ]; then`.
**Why it happens:** Equality-check on specific exit codes is fragile.
**How to avoid:** Scout confirmed all 4 callers use `|| return 1` (generic non-zero check). Document the audit result in the plan for traceability.
**Warning signs:** A caller block like `preflight; RC=$?; if [ "$RC" -eq 1 ]; then`.

### Pitfall 4: Live Tests Run Without `skip()`, Making Coverage Invisible
**What goes wrong:** `if command -v claude >/dev/null; then ...test...; fi` with no `else` branch means the test silently disappears from the summary. PASS count doesn't rise; no indication of what was skipped.
**Why it happens:** The test existed before `skip()` was added.
**How to avoid:** Every conditional test must emit either `pass`, `fail`, or `skip`. The `▸ Live-system tests` section uses `skip()` in all else branches.
**Warning signs:** Summary shows fewer test results when run without `CONJURE_LIVE_TEST=1` than the number of test blocks suggests.

### Pitfall 5: CONJURE_STRICT Interaction with UAT-01/02
**What goes wrong:** `CONJURE_STRICT=1` alone (without `CONJURE_LIVE_TEST=1`) causes the UAT-01 skip to route to `fail()`, making the standard test run fail when the user didn't set up live tests.
**Why it happens:** Strict mode makes every skip a failure, including skips that are expected in non-live environments.
**How to avoid:** Document the intended invocation: `CONJURE_STRICT=1 CONJURE_LIVE_TEST=1 ANTHROPIC_API_KEY=<key> tests/run.sh`. Strict mode without live-test env vars is not a standard workflow.

### Pitfall 6: mk_tmpd() Not Available at All Call Sites
**What goes wrong:** Some `$(mktemp -d)` calls in `run.sh` appear before `tests/lib/sandbox.sh` is sourced, or in sections that don't execute in the same shell context.
**How to avoid:** `tests/lib/sandbox.sh` is sourced at line 8 of `run.sh` — before any `mktemp -d` usage. All 216 raw calls in `run.sh` are in the same shell; `mk_tmpd` is available everywhere after line 8.

---

## Code Examples

### Summary line replacement (tail of tests/run.sh)
```bash
# Source: tests/run.sh (current final lines, verified)
# Before:
echo "PASS: $PASS    FAIL: $FAIL"
# After:
echo "PASS: $PASS    FAIL: $FAIL    SKIP: $SKIP"
```

### Existing env-var gate pattern to follow (from tests/run.sh:465,512)
```bash
# Source: tests/run.sh:465,512 — existing CONJURE_COST/CONJURE_EXACT pattern
COST_OUT="$(CONJURE_COST=1 bash "$CONJURE_HOME/scripts/audit-setup.sh" "$SANDBOX_DIR" 2>&1)"
EXACT_OUT="$(CONJURE_COST=1 CONJURE_EXACT=1 ANTHROPIC_API_KEY="" bash "..." 2>&1)"
```

### audit-setup.sh schema lookup (current, to be modified)
```bash
# Source: scripts/audit-setup.sh:117 (verified)
# Current:
SCHEMA_FILE="${CONJURE_HOME}/lib/cc-schema.json"
# Modified:
SCHEMA_FILE="${CONJURE_SCHEMA_FILE:-${CONJURE_HOME}/lib/cc-schema.json}"
```

### preflight.sh exit code (current, to be modified)
```bash
# Source: scripts/preflight.sh:109 (verified)
# Current:
[ "$REQUIRED_FAILED" -eq 1 ] && exit 1
# Modified:
[ "$REQUIRED_FAILED" -eq 1 ] && exit 2
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| cp-swap of production schema in tests | `CONJURE_SCHEMA_FILE` env override | Phase 31 | Kill-safe by construction; eliminates the RETROSPECTIVE.md:159 incident pattern |
| Raw `$(mktemp -d)` in tests | `mk_tmpd()` wrapper with validation | Phase 31 | Closes proven sandbox-escape vector; catches mktemp failures before `git -C` sees an empty var |
| Pass/Fail summary only | Pass/Fail/Skip summary with `CONJURE_STRICT` escalation | Phase 31 | Makes coverage of gated tests visible; enables release-machine strict mode |
| Live tests either always run or are commented out | Env-var gating with `skip()` verdicts | Phase 31 | Standard CI skips cleanly; developer with `claude` + API key can exercise full suite |

**Deprecated/outdated:**
- `tests/run.sh:5118-5126` cp-swap: replaced by env override (DEBT-06).
- `scripts/preflight.sh:109 exit 1`: project convention requires `exit 2`; lone deviation closes (DEBT-04).

---

## Runtime State Inventory

> This is not a rename/refactor/migration phase. All changes are code edits to bash scripts and a new documentation file. No stored data, live service config, OS-registered state, secrets, or build artifacts carry state that needs migration.

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | None — test suite writes only to `mktemp` dirs, cleaned on exit | None |
| Live service config | None — no n8n, Datadog, or external service config involved | None |
| OS-registered state | None | None |
| Secrets/env vars | `ANTHROPIC_API_KEY` used as gate condition (not secret name change) | None |
| Build artifacts | None | None |

---

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Hand-rolled `tests/run.sh` (project constraint — no shellspec, no npm test deps) |
| Config file | none |
| Quick run command | `bash tests/run.sh` |
| Full suite command | `bash tests/run.sh` |
| Live-test run | `CONJURE_LIVE_TEST=1 ANTHROPIC_API_KEY=<key> bash tests/run.sh` |
| Strict live-test run | `CONJURE_STRICT=1 CONJURE_LIVE_TEST=1 ANTHROPIC_API_KEY=<key> bash tests/run.sh` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| DEBT-03 | `mk_tmpd()` aborts suite on mktemp failure | unit (self-test in run.sh) | `bash tests/run.sh` | `tests/lib/sandbox.sh` exists; `mk_tmpd()` is new |
| DEBT-03 | Regression gate: no raw `$(mktemp -d)` outside sandbox.sh | convention self-test | `bash tests/run.sh` | New test in run.sh |
| DEBT-04 | `preflight.sh` exits 2 when required dep missing | existing test at run.sh:148-197 | `bash tests/run.sh` | Exists — test already covers preflight exit code |
| DEBT-05 | Summary shows PASS/FAIL/SKIP counts | observable output | `bash tests/run.sh \| grep -E 'PASS:.*FAIL:.*SKIP:'` | New counter added to run.sh |
| DEBT-05 | `CONJURE_STRICT=1` makes skip() escalate to fail | unit (self-test) | `CONJURE_STRICT=1 bash tests/run.sh` (expect non-zero if any skip) | New behavior in skip() |
| DEBT-06 | SCHM-STALE test does NOT touch `lib/cc-schema.json` | unit (existing SCHM-STALE test, reworked) | `bash tests/run.sh` | Exists at run.sh:5107-5139 — modified |
| DEBT-06 | `CONJURE_SCHEMA_FILE` override accepted by audit-setup.sh | unit (SCHM-STALE test) | `bash tests/run.sh` | In run.sh:5107-5139 |
| UAT-01 | Live claude smoke skips cleanly when `CONJURE_LIVE_TEST` unset | unit (skip verdict) | `bash tests/run.sh \| grep '○.*UAT-01'` | New section in run.sh |
| UAT-01 | Live claude smoke skips when `claude` binary absent even with `CONJURE_LIVE_TEST=1` | unit (skip verdict) | `CONJURE_LIVE_TEST=1 bash tests/run.sh` on machine without claude | New section in run.sh |
| UAT-02 | Live promptfoo probe skips cleanly when `ANTHROPIC_API_KEY` unset | unit (skip verdict) | `bash tests/run.sh \| grep '○.*UAT-02'` | New section in run.sh |
| UAT-03 | `tests/MANUAL-UAT.md` exists with required sections | smoke (file check) | `bash tests/run.sh` (file-exists assertion) | New file |

### Sampling Rate
- **Per task commit:** `bash tests/run.sh`
- **Per wave merge:** `bash tests/run.sh`
- **Phase gate:** Full suite green + `tests/MANUAL-UAT.md` reviewed by human

### Wave 0 Gaps
None — all test infrastructure exists. Changes land in existing files. No new test framework, no new config files, no new fixtures beyond the `_eval-probe` fixture needed for UAT-02 (a temp sandbox built inline is sufficient per D-09).

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| bash | All scripts | ✓ | 3.2+ (macOS ships 3.2) | — |
| jq | audit-setup.sh, run.sh | ✓ | system dep in preflight | — |
| git | test sandboxes | ✓ | system dep in preflight | — |
| mktemp | mk_tmpd() | ✓ | POSIX stdlib | — |
| claude binary | UAT-01 smoke | optional | unknown — gate checks `command -v claude` | skip() verdict |
| ANTHROPIC_API_KEY | UAT-02 probe | optional — env var | n/a | skip() verdict |
| promptfoo | UAT-02 probe | optional — npx shell-out | 0.121.14 (pinned in eval.sh) | skip() verdict |

**Missing dependencies with no fallback:** None.
**Missing dependencies with fallback:** `claude` binary and `ANTHROPIC_API_KEY` — both have `skip()` fallback.

---

## Security Domain

> Phase 31 makes no auth, session, cryptography, or access-control changes. The only security-adjacent item is the SCHM-STALE fix (DEBT-06), which eliminates a test pattern that could silently corrupt production files.

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | — |
| V3 Session Management | no | — |
| V4 Access Control | no | — |
| V5 Input Validation | no | — |
| V6 Cryptography | no | — |
| File integrity (SIGKILL) | yes (DEBT-06) | env override instead of cp-swap; POSIX `mv` is atomic same-fs |

### Known Threat Patterns for this stack

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| `git -C ""` sandbox escape | Tampering | `mk_tmpd()` validates non-empty before `git -C` ever sees the var |
| SIGKILL-interrupted file swap corrupts production | Tampering | Replace cp-swap with env override; no production file written |

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `claude plugin validate <dir>` accepts a directory path as its argument (not just `.`) | UAT-01 pattern | The smoke test would need to `cd` into the temp dir and run `claude plugin validate .` instead — minor implementation detail, same observable behavior |

> **Note on A1:** STACK.md:1379 documents `claude plugin validate .` (dot = current dir). The smoke test can `cd "$UAT01_DIR" && claude plugin validate .` to avoid any ambiguity about argument form.

---

## Open Questions

1. **UAT-02 promptfoo probe: fixture structure**
   - What we know: The probe is a 1-test eval in a temp sandbox (D-09); `scripts/eval.sh:277` advisory references `ANTHROPIC_API_KEY`.
   - What's unclear: Does the probe reuse the existing `tests/fixtures/_eval-probe/` scaffold (which only contains a `README.md`) or build a minimal `promptfooconfig.yaml` inline in `run.sh`?
   - Recommendation: Build inline in `run.sh` using a heredoc — keeps the probe self-contained and avoids a new fixture that needs its own maintenance.

2. **DEBT-03 sweep: `$(mktemp)` (file, not dir) calls**
   - What we know: The decision (D-12) scopes to `$(mktemp -d)` (directory form). There are also `$(mktemp)` (file) calls that feed into operations other than `git -C`.
   - What's unclear: Should file-form `mktemp` also be wrapped?
   - Recommendation: No — the sandbox-escape vector is specific to `git -C "$VAR"` where `$VAR` was set from `mktemp -d`. File-form mktemp goes to different callers (cp, mv, cat). The convention gate grep targets `$(mktemp -d)` only, matching D-12's scope.

---

## Sources

### Primary (HIGH confidence)
- `tests/run.sh` — inspected directly; line counts, counter pattern, SCHM-STALE swap, and summary line verified [VERIFIED: codebase]
- `tests/lib/sandbox.sh` — full file read; `sandbox_setup()` raw `mktemp -d` at line 48 confirmed [VERIFIED: codebase]
- `scripts/preflight.sh:109` — sole `exit 1` confirmed by grep [VERIFIED: codebase]
- `scripts/audit-setup.sh:117` — `SCHEMA_FILE` assignment confirmed by grep [VERIFIED: codebase]
- `cli/conjure:84,172,174,234` — all callers use `|| return 1` (generic non-zero) confirmed by grep [VERIFIED: codebase]
- `.planning/phases/31-deferred-debt-test-harness-hardening/31-CONTEXT.md` — all implementation decisions D-01 through D-16 [VERIFIED: codebase]
- `.planning/RETROSPECTIVE.md:159` — SCHM-STALE incident origin [VERIFIED: codebase]

### Secondary (MEDIUM confidence)
- `.planning/research/STACK.md:2283-2341` — atomic swap pattern documentation and v0.8.0 stack summary [CITED: project research doc]
- `.planning/research/STACK.md:1373-1391` — `claude plugin validate` CLI surface [CITED: project research doc, verified 2026-05-25 per STACK.md]

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all tools already in preflight; zero new dependencies
- Architecture: HIGH — all changes are in files confirmed by direct codebase inspection
- Pitfalls: HIGH — SCHM-STALE incident and git -C escape vector are documented in RETROSPECTIVE.md and confirmed in code

**Research date:** 2026-06-04
**Valid until:** 2026-07-04 (stable — no external API, no package versions to track)
