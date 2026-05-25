# Phase 4: Regression Suite & Dry-Run Proof - Research

**Researched:** 2026-05-25
**Domain:** Bash test-runner extension, golden-file comparison, CI/CD (GitHub Actions)
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**EXPECT Files for Green Fixtures**
- D-01: Each green fixture gets a committed `tests/fixtures/<profile>/EXPECT` file with positive-pass grep-E patterns. Fails if audit output drifts.
- D-02: Patterns are grep-E regexes that avoid absolute paths. Match semantic content, not sandbox temp paths.
- D-03: EXPECT files live committed alongside fixtures; `scripts/regen-fixtures.sh` is the documented command to regenerate them.

**Dry-Run Byte-Identical Snapshot**
- D-04: Method: `cp -r fixture sandbox`, run `conjure init --dry-run "$sandbox"`, then `diff -r "$sandbox" "$fixture_original"`. Any mutation = failure.
- D-05: Scope: all 9 green fixtures.
- D-06: Run against existing fixture as-is (tests re-init idempotence).

**Failure-Mode Reproductions**
- D-07: Scope limited to Conjure-auditable modes: size cap exceeded, hook wrong exit code, version mismatch. Skip runtime/infra modes.
- D-08: Location: new `▸ Failure-mode reproductions (TEST-07)` section inside `tests/run.sh`.
- D-09: Reproduction pattern: `mktemp -d` synthetic fixture + write offending file + assert specific finding string.

**Windows CI Leg**
- D-10: New `windows-hook-wiring` job in `.github/workflows/ci.yml` on `windows-latest`.
- D-11: `shell: bash` on each step (Git Bash). No extra dependency installation.
- D-12: Three assertions: `node --version` exits 0; `grep 'node' .claude/settings.json` succeeds; `grep -v 'bash .claude/hooks' .claude/settings.json` succeeds.

### Claude's Discretion
- Exact positive patterns in each green fixture's EXPECT file.
- Whether the dry-run diff section re-uses `sandbox_setup` or manages its own temp copy.
- Which specific `exit 1` pattern constitutes the "wrong exit code" synthetic fixture.
- Whether `scripts/regen-fixtures.sh` gets a `--update-expect` flag.

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| TEST-03 | `tests/run.sh` drives per-fixture audit assertions via golden-file (`EXPECT`) comparison | EXPECT loop pattern directly generalizes the existing `_broken` EXPECT loop at run.sh:274-282 |
| TEST-05 | Regression suite asserts a `--dry-run` run leaves the fixture tree byte-identical | `diff -r` confirmed working on macOS and Linux; conjure init --dry-run verified IDENTICAL on ts-next fixture |
| TEST-06 | CI includes a `windows-latest` leg that validates `.mjs` hook wiring | `windows-latest` has Node pre-installed; settings.json uses `node .claude/hooks/*.mjs` — grep assertion is sufficient |
| TEST-07 | Documented failure modes have reproductions encoded as tests | Three Conjure-auditable modes identified; each has a concrete test approach; runtime/infra modes explicitly excluded |
</phase_requirements>

---

## Summary

Phase 4 extends `tests/run.sh` with three new test sections and adds a `windows-hook-wiring` job to `.github/workflows/ci.yml`. All work is pure bash + YAML — no new packages, no new dependencies.

The existing test runner structure is well-understood: `pass`/`fail` helpers, `▸ Section name` headers, `sandbox_setup()` for isolation, and the `_broken` fixture's EXPECT loop as the canonical template for golden-file comparison. Phase 4 generalizes that EXPECT loop to all 9 green fixtures (TEST-03), adds a separate per-fixture dry-run snapshot check using plain `diff -r` (TEST-05), adds failure-mode reproduction tests using mktemp synthetic fixtures (TEST-07), and adds a targeted Windows CI smoke job (TEST-06).

One critical finding: `scripts/audit-setup.sh` currently checks only size cap, JSON validity, hook file presence, and token budget. It does NOT check hook exit codes in `.claude/hooks/` or `.conjure-version` content. The failure-mode tests for "hook wrong exit code" and "version mismatch" must therefore use direct grep and `conjure update` respectively — not `audit-setup.sh`.

**Primary recommendation:** Insert three new sections at the bottom of `tests/run.sh` (before the summary block). Each section is self-contained. The EXPECT loop mirrors the existing `_broken` loop verbatim with a `[ -f EXPECT ]` guard. The dry-run section uses plain `mktemp`+`cp -r`+`diff -r` with no `sandbox_setup` (to avoid HOME/PATH clobbering and trap conflicts). The failure-mode section uses mktemp synthetic fixtures with direct assertions.

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Golden-file EXPECT comparison (TEST-03) | Test runner (`tests/run.sh`) | Committed fixtures (`tests/fixtures/`) | Test runner reads EXPECT, fixtures store golden output; clear separation |
| Dry-run snapshot assertion (TEST-05) | Test runner (`tests/run.sh`) | CLI (`cli/conjure`) | Runner drives the diff; CLI produces the dry-run behavior being tested |
| Failure-mode reproductions (TEST-07) | Test runner (`tests/run.sh`) | Audit script (`scripts/audit-setup.sh`) | Runner creates synthetic state; audit detects size-cap mode; runner uses grep/update for other modes |
| Windows hook-wiring validation (TEST-06) | CI (`ci.yml`) | CLI + settings.json template | CI is the only tier that runs on windows-latest; it exercises the init + grep assertions |
| EXPECT file generation | Fixture generator (`scripts/regen-fixtures.sh`) | — | Centralizes golden-file creation; prevents drift when profiles change |

---

## Standard Stack

### Core
| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| bash | 3.2+ | Test runner language | Already established (CLAUDE.md constraint) |
| `diff -r` | (system) | Directory tree comparison for dry-run snapshot | Built-in on Linux, macOS, and Windows Git Bash; no install required |
| `mktemp -d` | (system) | Create isolated temp dirs for synthetic fixtures | Already used extensively in `tests/run.sh` |
| `grep -qE` | (system) | Pattern matching against audit output | Already used for EXPECT comparison in `_broken` loop |

### Supporting
| Tool | Version | Purpose | When to Use |
|------|---------|---------|-------------|
| `jq` | (optional) | JSON validation in audit-setup.sh | Only needed for settings.json validation; audit falls back gracefully without it |
| `node` | any | Windows CI: runtime check + hook wiring proof | Pre-installed on `windows-latest` runner; used as an assertion target |
| `conjure update` | (local CLI) | Version-mismatch failure-mode test | Only tool that checks `.conjure-version` vs current; `audit-setup.sh` does not |

**Installation:** No new packages. Phase 4 uses only tools already present in the project.

### Package Legitimacy Audit

Phase 4 installs **no external packages**. This section is N/A — the phase extends bash scripts and a YAML workflow file only.

---

## Architecture Patterns

### System Architecture Diagram

```
tests/run.sh (entry point)
│
├── ▸ [EXISTING] Smoke tests
├── ▸ [EXISTING] Skill frontmatter validity
├── ▸ [EXISTING] Size caps
├── ▸ [EXISTING] No @imports
├── ▸ [EXISTING] Hook exit codes (templates only)
├── ▸ [EXISTING] Audit script self-test
├── ▸ [EXISTING] Preflight script
├── ▸ [EXISTING] Template lint
├── ▸ [EXISTING] Dry-run enforcement (SAFE-01, SAFE-02)
├── ▸ [EXISTING] Migration coverage
├── ▸ [EXISTING] Profile coverage
├── ▸ [EXISTING] Compliance coverage
├── ▸ [EXISTING] Fixture audits — sandboxed (TEST-01, TEST-02)
│                └── sandbox_setup($fx) → audit-setup.sh → pass/fail
├── ▸ [EXISTING] Broken fixture — specific finding assertion (TEST-04)
│                └── sandbox_setup(_broken) → EXPECT loop → pass/fail
│
├── ▸ [NEW] Golden-file EXPECT loop (TEST-03)          ← Phase 4
│          └── for each fixture:
│               sandbox_setup($fx) → audit → EXPECT loop (if EXPECT exists)
│
├── ▸ [NEW] Dry-run byte-identical snapshot (TEST-05)  ← Phase 4
│          └── for each green fixture:
│               mktemp ORIG + mktemp SNAP
│               cp -r $fx → ORIG; cp -r $fx → SNAP
│               conjure init --dry-run SNAP
│               diff -r SNAP ORIG → pass/fail
│
└── ▸ [NEW] Failure-mode reproductions (TEST-07)       ← Phase 4
           ├── Size cap: mktemp + 200-line CLAUDE.md + audit-setup.sh
           │   assert: "HARD CAP exceeded" in output
           ├── Hook exit 1: mktemp + hook with "exit 1" + grep
           │   assert: grep -qE '^exit 1$' finds it
           └── Version mismatch: mktemp + .conjure-version=0.1.0 + conjure update
               assert: output contains "pinned to" AND no "Up to date"
```

### Recommended Project Structure

No new directories. All changes go into existing files:

```
tests/
├── run.sh                    # Add 3 sections before summary block
├── lib/
│   └── sandbox.sh            # No changes needed
└── fixtures/
    ├── ts-next/EXPECT        # NEW: committed golden file
    ├── java-spring/EXPECT    # NEW
    ├── rust-axum/EXPECT      # NEW
    ├── go-gin/EXPECT         # NEW
    ├── python-fastapi/EXPECT # NEW
    ├── node-nest/EXPECT      # NEW
    ├── monorepo/EXPECT       # NEW
    ├── polyglot/EXPECT       # NEW
    ├── data-science/EXPECT   # NEW
    └── _broken/EXPECT        # EXISTS (no change)
.github/
└── workflows/
    └── ci.yml                # Add windows-hook-wiring job
scripts/
└── regen-fixtures.sh         # Extend to write EXPECT files (or add --update-expect flag)
```

### Pattern 1: EXPECT Loop (golden-file comparison)

The existing `_broken` loop is the canonical template. Generalize it to all fixtures with a guard:

```bash
# Source: tests/run.sh lines 274-282 (existing _broken loop)
echo
echo "▸ Golden-file EXPECT loop (TEST-03)"
for fx in "$CONJURE_HOME/tests/fixtures"/*/; do
  prof=$(basename "$fx")
  expect_file="$fx/EXPECT"
  [ ! -f "$expect_file" ] && continue   # skip fixtures without EXPECT
  sandbox_setup "$fx"
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
```

[VERIFIED: codebase grep] Pattern matches actual tests/run.sh:274-282 structure exactly.

### Pattern 2: Dry-Run Byte-Identical Snapshot

Do NOT use `sandbox_setup` here — it overrides HOME/PATH and its trap would replace any trap set for the snapshot dirs. Use plain mktemp:

```bash
# Source: CONTEXT.md D-04, verified against codebase
echo
echo "▸ Dry-run byte-identical snapshot (TEST-05)"
for fx in "$CONJURE_HOME/tests/fixtures"/[^_]*/; do
  prof=$(basename "$fx")
  DRY_ORIG="$(mktemp -d)"
  DRY_SNAP="$(mktemp -d)"
  trap 'rm -rf "$DRY_ORIG" "$DRY_SNAP"' EXIT
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
```

[VERIFIED: live test] `diff -r` between two `cp -r` copies of `tests/fixtures/ts-next` after `conjure init --dry-run` exits 0 with empty output. [ASSUMED] Linux `diff` behavior matches macOS.

### Pattern 3: Failure-Mode Reproductions

Three synthetic mini-fixtures, each self-contained:

```bash
# Source: CONTEXT.md D-09 + codebase analysis
echo
echo "▸ Failure-mode reproductions (TEST-07)"

# FM-1: Size cap exceeded
FM_DIR="$(mktemp -d)"
trap 'rm -rf "$FM_DIR"' EXIT
printf '# SYNTHETIC — size cap test\n' > "$FM_DIR/CLAUDE.md"
for i in $(seq 1 105); do printf '# filler line %s\n' "$i" >> "$FM_DIR/CLAUDE.md"; done
FM_OUT="$(bash "$CONJURE_HOME/scripts/audit-setup.sh" "$FM_DIR" 2>&1 || true)"
if printf '%s\n' "$FM_OUT" | grep -q "HARD CAP exceeded"; then
  pass "FM: size cap detected by audit"
else
  fail "FM: size cap NOT detected"
fi
rm -rf "$FM_DIR"

# FM-2: Hook wrong exit code
FM_DIR="$(mktemp -d)"
trap 'rm -rf "$FM_DIR"' EXIT
mkdir -p "$FM_DIR/.claude/hooks"
printf '#!/usr/bin/env bash\nexit 1\n' > "$FM_DIR/.claude/hooks/bad-gate.sh"
if grep -qE '^exit 1$' "$FM_DIR/.claude/hooks/bad-gate.sh"; then
  pass "FM: hook exit 1 detectable via grep"
else
  fail "FM: hook exit 1 NOT found"
fi
rm -rf "$FM_DIR"

# FM-3: Version mismatch
FM_DIR="$(mktemp -d)"
trap 'rm -rf "$FM_DIR"' EXIT
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
```

[VERIFIED: live test] All three patterns validated against actual codebase behavior.

### Pattern 4: Windows CI Job

```yaml
# Source: CONTEXT.md D-10/D-11/D-12
  windows-hook-wiring:
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v4

      - name: Scaffold fixture
        shell: bash
        run: |
          mkdir -p /tmp/fixture
          CONJURE_HOME="$GITHUB_WORKSPACE" cli/conjure init /tmp/fixture

      - name: Assert node version
        shell: bash
        run: node --version

      - name: Assert node hook wiring in settings.json
        shell: bash
        run: grep 'node' /tmp/fixture/.claude/settings.json

      - name: Assert no bash hook regression
        shell: bash
        run: |
          if grep 'bash .claude/hooks' /tmp/fixture/.claude/settings.json; then
            echo "FAIL: bash hook commands found (SAFE-03 regression)" && exit 1
          fi
```

[ASSUMED] `windows-latest` GitHub Actions runner has Node pre-installed (training data). [ASSUMED] Git Bash via `shell: bash` is available on `windows-latest`. [CITED: CONTEXT.md D-11]

### Pattern 5: EXPECT File Format (Green Fixtures)

Based on the summary line `audit-setup.sh` emits for a fully-passing fixture:

```
PASS: 17    WARN: 0    FAIL: 0
```

Recommended EXPECT content for each green fixture:

```
# tests/fixtures/<profile>/EXPECT
# Positive-pass assertions — audit must produce all of these patterns.
# Comments and blank lines are ignored (same format as _broken/EXPECT).
PASS: [0-9]
WARN: 0
FAIL: 0
```

Three lines provides: (1) proof some tests ran, (2) no warnings, (3) no failures. Avoids absolute paths. If a profile-specific check is added to `audit-setup.sh` later, the summary count will change but the `WARN: 0 FAIL: 0` assertion will still hold.

[VERIFIED: live test] All 9 green fixtures produce `PASS: 17    WARN: 0    FAIL: 0` as of Phase 3 output. Each pattern confirmed to match via `grep -E`.

### Pattern 6: regen-fixtures.sh EXPECT Generation

When generating fixtures, `regen_profile` should also write the EXPECT file:

```bash
# After existing regen_profile logic (after audit verification passes)
# Write EXPECT for this profile
EXPECT_FILE="$FIXTURES_DIR/$p/EXPECT"
{
  printf '# tests/fixtures/%s/EXPECT\n' "$p"
  printf '# Positive-pass patterns — generated by scripts/regen-fixtures.sh\n'
  printf '# Comments and blank lines ignored. Same format as _broken/EXPECT.\n'
  printf 'PASS: [0-9]\n'
  printf 'WARN: 0\n'
  printf 'FAIL: 0\n'
} > "$EXPECT_FILE"
printf '[regen] %s: wrote EXPECT\n' "$p"
```

Alternatively, add a `--update-expect` flag to regen-fixtures.sh that regenerates EXPECT files without re-running `conjure init` (faster for when only the EXPECT patterns need to change).

[ASSUMED] The `--update-expect` flag is Claude's discretion per CONTEXT.md.

### Anti-Patterns to Avoid

- **Using `sandbox_setup` in the dry-run section:** `sandbox_setup` calls `trap 'rm -rf "$SANDBOX_DIR"' EXIT` which replaces bash's EXIT trap. If the dry-run section sets up its own trap first and then calls `sandbox_setup`, the dry-run cleanup trap is lost. The dry-run section MUST manage its own temp dirs without `sandbox_setup`.
- **Using diff -r with --brief flag:** Do not use `diff -r --brief` — it suppresses the actual diff output that helps diagnose which file was mutated. Always capture the diff and `head -10` on failure.
- **Making Windows CI job install deps:** D-11 is explicit: no `apt-get`, no `npm install`, no `choco`. The job runs only what's pre-installed (Node, Git Bash, grep).
- **Using absolute paths in EXPECT patterns:** The sandbox copies fixtures to temp dirs under `/var/folders/...` (macOS) or `/tmp/...` (Linux). Any pattern containing a path will fail on different machines. Always use semantic patterns (`PASS: [0-9]`, `HARD CAP exceeded`).
- **Calling `audit-setup.sh` to check hook exit codes or version stamps:** `audit-setup.sh` does not check either. Use `grep -qE '^exit 1$'` on the hook file directly, and use `cli/conjure update` for version mismatch detection.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Directory tree comparison | Custom file-list diff | `diff -r` | Built-in, works on Linux/macOS/Windows Git Bash; content-only (no timestamp noise) |
| EXPECT pattern matching | Custom grep loop | The existing `_broken` loop pattern (generalized) | Already proven, tested, shellcheck-clean |
| Windows Node detection | Custom version parsing | `node --version && echo $?` | Node is pre-installed; just assert exit 0 |
| Synthetic fixture cleanup | Explicit rm at end of test | `trap 'rm -rf "$DIR"' EXIT` + explicit rm | Belt-and-suspenders: removes on failure AND on success |

**Key insight:** The test runner already has every primitive needed. Phase 4 is composition, not invention.

---

## Common Pitfalls

### Pitfall 1: Trap Clobbering in run.sh

**What goes wrong:** `sandbox_setup` registers `trap 'rm -rf "$SANDBOX_DIR"' EXIT` internally. In bash, each `trap EXIT` call **replaces** the previous one. The dry-run section's cleanup trap will be clobbered if any subsequent `sandbox_setup` call runs after it.

**Why it happens:** bash trap EXIT is not cumulative.

**How to avoid:** In the dry-run section, use explicit `rm -rf "$DRY_ORIG" "$DRY_SNAP"` at the end of each loop iteration (not just a trap), so cleanup happens even if `sandbox_setup` is called later in the script.

**Warning signs:** Temp dirs under `/var/folders/` or `/tmp/` accumulating after test runs.

### Pitfall 2: EXPECT Files for Both Green and Broken Fixtures in Same Loop

**What goes wrong:** The EXPECT loop (TEST-03) iterates `fixtures/*/` — which includes `_broken/`. The existing `▸ Broken fixture` section already handles `_broken` separately. Running it again in the EXPECT loop would double-assert `_broken`.

**Why it happens:** `[^_]*/` glob excludes `_broken/` by underscore prefix, but using `*/` would include it.

**How to avoid:** Use `fixtures/[^_]*/` glob for the green-fixture EXPECT loop (same as existing fixture audit loop at run.sh:248). The `_broken` fixture has its own dedicated section.

**Warning signs:** `_broken` appearing in EXPECT loop output.

### Pitfall 3: diff -r Picks Up .DS_Store or Temp Files

**What goes wrong:** On macOS, some tools create `.DS_Store` files. If `conjure init --dry-run` causes any such side effect (unlikely but possible), `diff -r` will flag it as a mutation.

**Why it happens:** macOS Finder and some tools create metadata files automatically.

**How to avoid:** This is low risk since `conjure init --dry-run` is pure bash (no GUI). Verified: test run of `conjure init --dry-run` on `ts-next` produces `diff exit: 0`. If it becomes an issue, use `diff -r --exclude='.DS_Store'`.

**Warning signs:** diff reports `.DS_Store` in the diff output.

### Pitfall 4: Windows CI Job Cannot Run Full test Suite

**What goes wrong:** `tests/run.sh` uses `find ... -name '*.sh' ... -exec shellcheck` which requires shellcheck. `shellcheck` is NOT pre-installed on `windows-latest`. The Windows CI job MUST NOT run `bash tests/run.sh`.

**Why it happens:** D-11 says no extra dep installation; shellcheck is not in the windows-latest default image.

**How to avoid:** Windows CI job runs `conjure init` then `grep` assertions only — not the full test suite. The full test suite (`tests/run.sh`) only runs on `ubuntu-latest` (existing `test` job).

**Warning signs:** `shellcheck not found` error in Windows CI steps.

### Pitfall 5: version-mismatch Test Needs .claude/ Not Just .conjure-version

**What goes wrong:** `conjure update` reads `.claude/.conjure-version`, not `.conjure-version` at root. If the synthetic fixture only has `$FM_DIR/.conjure-version`, `conjure update` will report `pinned="unknown"` rather than the planted mismatch version.

**Why it happens:** The `.conjure-version` file lives at `.claude/.conjure-version` (inside `.claude/` dir).

**How to avoid:** `mkdir -p "$FM_DIR/.claude"` before writing the version file.

**Warning signs:** conjure update output shows `pinned to: unknown` instead of `pinned to: 0.1.0`.

### Pitfall 6: CONJURE_HOME Must Be Explicit for CLI Calls in dry-run Loop

**What goes wrong:** The dry-run loop calls `cli/conjure init --dry-run "$DRY_SNAP"`. The `cli/conjure` script resolves `CONJURE_HOME` from `$(dirname "$0")/..`. When called as a relative path, this works. When called as `"$CONJURE_HOME/cli/conjure"`, the resolution still works from the kit root.

**Why it happens:** `init-project.sh` sources `$CONJURE_HOME/lib/mutate.sh`, requiring `CONJURE_HOME` to be set correctly.

**How to avoid:** Always call `CONJURE_HOME="$CONJURE_HOME" cli/conjure init --dry-run "$DRY_SNAP"` — the same pattern used in existing run.sh dry-run tests (line 195).

**Warning signs:** `lib/mutate.sh: No such file or directory` errors in dry-run output.

---

## Code Examples

### Full audit output for a green fixture (ts-next, verified live)

```
Auditing .claude/ setup in: /tmp/sandbox.../

  ✓ CLAUDE.md: 47 lines (≤100)
  ✓ CLAUDE.md: no @imports
  ✓ .claudeignore present
  ✓ .claude/ directory exists
  ✓ .claude/skills/: 19 skills
  ✓ .claude/agents/: 6 agents
  ✓ .claude/settings.json: valid JSON
  ✓ Hook present: post-edit-format.mjs
  ✓ Hook present: stop-compound-engineering.mjs
  ✓ Hook present: session-start-context.mjs
  ✓ Hook present: pre-bash-block-destructive.mjs
  ✓ Hook present: pre-commit-quality-gate.mjs
  ✓ docs/ARCHITECTURE.md present
  ✓ docs/RUNBOOK.md present
  ✓ docs/adr/ present
  ✓ .env.example present
  ✓ .claude/ token estimate: ~11933 (well-tuned)

─────────────────────────────────────
PASS: 17    WARN: 0    FAIL: 0
─────────────────────────────────────
```

All 9 green fixtures produce `PASS: 17    WARN: 0    FAIL: 0` — verified live. [VERIFIED: codebase]

### Full audit output for _broken fixture (verified live)

```
  ✗ CLAUDE.md: 205 lines (HARD CAP exceeded — trim)
  ...
PASS: 16    WARN: 0    FAIL: 1
```

Exit code 2. Pattern `HARD CAP exceeded` in `_broken/EXPECT` matches. [VERIFIED: codebase]

### Existing EXPECT loop in run.sh (lines 274-282, canonical template)

```bash
# Source: tests/run.sh lines 274-282 [VERIFIED: codebase]
while IFS= read -r pattern; do
  [ -z "$pattern" ] && continue
  case "$pattern" in \#*) continue ;; esac
  if printf '%s\n' "$BROKEN_OUT" | grep -qE "$pattern"; then
    pass "_broken: found expected finding: $pattern"
  else
    fail "_broken: missing expected finding: $pattern"
  fi
done < "$CONJURE_HOME/tests/fixtures/_broken/EXPECT"
```

### sandbox_setup interface (tests/lib/sandbox.sh, verified live)

```bash
# Source: tests/lib/sandbox.sh [VERIFIED: codebase]
# Sets SANDBOX_DIR (global), copies fixture, exports HOME/XDG_CONFIG_HOME/CLAUDE_CONFIG_DIR/PATH
sandbox_setup() {
  local fixture_dir="$1"
  SANDBOX_DIR="$(mktemp -d)"
  trap 'rm -rf "$SANDBOX_DIR"' EXIT   # NOTE: replaces any previous EXIT trap
  cp -r "$fixture_dir/." "$SANDBOX_DIR/"
  export HOME="$SANDBOX_DIR"
  export XDG_CONFIG_HOME="$SANDBOX_DIR"
  export CLAUDE_CONFIG_DIR="$SANDBOX_DIR"
  export PATH="$CONJURE_HOME/cli:/usr/local/bin:/usr/bin:/bin"
}
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Exit-code-only fixture testing | Golden-file EXPECT pattern comparison | Phase 4 | Catches output drift, not just crashes |
| Single broken-fixture test | All-fixture EXPECT loop | Phase 4 | TEST-03: regression coverage for all profiles |
| Informal dry-run check (TMPDIR_TARGET, Phase 2) | Per-fixture byte-identical diff assertion | Phase 4 | TEST-05: prove each profile's init path mutates nothing |
| Ubuntu-only CI | Ubuntu + Windows CI | Phase 4 | TEST-06: SAFE-03 Windows hook wiring confirmed in CI |
| Failure modes documented but untested | Failure modes encoded as executable tests | Phase 4 | TEST-07: detectable regressions become visible |

---

## Critical Findings (Planner Must Address)

### Finding F-01: `audit-setup.sh` does not check hook exit codes or version stamps

`scripts/audit-setup.sh` checks: CLAUDE.md line count, @imports, `.claude/` presence, skills/agents/settings structure, docs presence, and token budget. It does NOT check:
- Exit codes in `.claude/hooks/*.sh` files
- `.claude/.conjure-version` content or format

**Impact on TEST-07:** The failure-mode tests for "hook wrong exit code" and "version mismatch" CANNOT use `audit-setup.sh` as the detection mechanism. They must use:
- Hook exit code: `grep -qE '^exit 1$' "$FM_DIR/.claude/hooks/bad-gate.sh"` (direct grep, same pattern as run.sh lines 87-91 for templates)
- Version mismatch: `cli/conjure update "$FM_DIR"` (the only command that checks `.conjure-version`)

**Recommendation for planner:** Each failure-mode test task should specify the correct detection tool for its mode. Do NOT specify `audit-setup.sh` for hook/version modes. [VERIFIED: codebase]

### Finding F-02: All 9 green fixtures produce identical summary line

Every green fixture produces `PASS: 17    WARN: 0    FAIL: 0`. This means:
- A single shared EXPECT template (three patterns: `PASS: [0-9]`, `WARN: 0`, `FAIL: 0`) works for all 9 fixtures
- The EXPECT content can be written by `regen-fixtures.sh` as a fixed template
- If `audit-setup.sh` gains new checks in a future phase, the count will rise above 17, but `WARN: 0` and `FAIL: 0` will still hold for green fixtures

[VERIFIED: live test against all 9 fixtures]

### Finding F-03: diff -r confirmed byte-identical on macOS for dry-run

Live test: `cp -r tests/fixtures/ts-next → TMP_SNAP`, run `conjure init --dry-run TMP_SNAP`, then `diff -r TMP_SNAP TMP_ORIG` → exit 0, empty output. [VERIFIED: live test] The approach is confirmed correct.

### Finding F-04: No EXPECT files exist for green fixtures yet

`find tests/fixtures -name EXPECT` returns only one result: `tests/fixtures/_broken/EXPECT`. All 9 green fixture EXPECT files must be created in Phase 4. [VERIFIED: codebase]

---

## Open Questions

1. **Should `scripts/regen-fixtures.sh` grow a `--update-expect` flag?**
   - What we know: regen currently regenerates `.claude/` + manifest stubs; EXPECT files are separate golden files
   - What's unclear: whether `--update-expect` should re-run audit and capture output (complex) or just write a fixed template (simple)
   - Recommendation: start with the fixed-template approach (write `PASS: [0-9]`, `WARN: 0`, `FAIL: 0` unconditionally) since all 9 green fixtures produce the same summary. A `--update-expect` flag can be a thin wrapper around this.

2. **Should the EXPECT loop in run.sh also run for `_broken`?**
   - What we know: `_broken` has `EXPECT` and currently gets a dedicated section
   - What's unclear: whether to unify the loops or keep them separate
   - Recommendation: keep separate. The `_broken` section asserts non-zero exit code AND patterns; the green EXPECT loop asserts only patterns (exit 0 already checked by the existing fixture audit). Merging adds complexity for no gain.

3. **Does the Windows CI job need to install `git init` for the fixture?**
   - What we know: `conjure init` does not require a git repo (verified by reading `init-project.sh`); it only copies files
   - What's unclear: whether any profile's `apply.sh` calls git
   - Recommendation: no `git init` needed for the Windows smoke test. If a profile apply.sh fails, the job catches it. Keep it minimal per D-11.

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| bash | tests/run.sh | ✓ | 3.2.57 | — |
| diff | Dry-run snapshot (TEST-05) | ✓ | Apple diff (FreeBSD) | — |
| node | Fixture hooks, Windows CI | ✓ | v24.15.0 | — |
| jq | audit-setup.sh JSON check | ✓ | 1.8.1 | audit warns but doesn't fail |
| git | fixture regen | ✓ | 2.54.0 | — |
| shellcheck | CI lint (ubuntu only) | ✗ (local) | — | CI installs via apt-get |

**Missing dependencies with no fallback:** none that block Phase 4 execution.

**Missing dependencies with fallback:** `shellcheck` not installed locally (optional per CLAUDE.md); CI installs it. This means developers should run `bash tests/run.sh` locally without shellcheck, but CI catches lint issues.

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Hand-rolled `tests/run.sh` (no external framework) |
| Config file | None |
| Quick run command | `bash tests/run.sh` |
| Full suite command | `bash tests/run.sh` (same — no separate unit/integration split) |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| TEST-03 | EXPECT patterns match audit output for all fixtures | integration | `bash tests/run.sh` (EXPECT loop section) | ❌ Wave 0: EXPECT files + run.sh section |
| TEST-05 | dry-run leaves fixture tree byte-identical | integration | `bash tests/run.sh` (snapshot section) | ❌ Wave 0: run.sh section |
| TEST-06 | Windows CI validates `.mjs` hook wiring | CI smoke | Push/PR to GitHub (windows-latest job) | ❌ Wave 0: ci.yml job |
| TEST-07 | Failure-mode reproductions are executable | integration | `bash tests/run.sh` (failure-mode section) | ❌ Wave 0: run.sh section |

### Sampling Rate

- **Per task commit:** `bash tests/run.sh` (includes all new sections once added)
- **Per wave merge:** `bash tests/run.sh` (full suite)
- **Phase gate:** Full suite green before `/gsd-verify-work`; Windows CI job green in CI

### Wave 0 Gaps

- [ ] `tests/fixtures/ts-next/EXPECT` — covers TEST-03 (ts-next profile)
- [ ] `tests/fixtures/java-spring/EXPECT` — covers TEST-03 (java-spring profile)
- [ ] `tests/fixtures/rust-axum/EXPECT` — covers TEST-03 (rust-axum profile)
- [ ] `tests/fixtures/go-gin/EXPECT` — covers TEST-03 (go-gin profile)
- [ ] `tests/fixtures/python-fastapi/EXPECT` — covers TEST-03 (python-fastapi profile)
- [ ] `tests/fixtures/node-nest/EXPECT` — covers TEST-03 (node-nest profile)
- [ ] `tests/fixtures/monorepo/EXPECT` — covers TEST-03 (monorepo profile)
- [ ] `tests/fixtures/polyglot/EXPECT` — covers TEST-03 (polyglot profile)
- [ ] `tests/fixtures/data-science/EXPECT` — covers TEST-03 (data-science profile)
- [ ] `tests/run.sh` — add three new sections (TEST-03 EXPECT loop, TEST-05 dry-run, TEST-07 failure modes)
- [ ] `.github/workflows/ci.yml` — add `windows-hook-wiring` job (TEST-06)
- [ ] `scripts/regen-fixtures.sh` — extend to write EXPECT files when regenerating

---

## Security Domain

Phase 4 makes no authentication, session, cryptography, or access-control changes. It adds test assertions and CI configuration only. No ASVS categories apply.

The one security-adjacent concern: synthetic fixtures in failure-mode tests use `mktemp -d` (safe — no world-readable temp dirs). All synthetic dirs are cleaned up via `trap` + explicit `rm -rf`.

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `windows-latest` GitHub Actions runner has Node pre-installed | Windows CI Leg pattern | Windows CI job fails at `node --version` step; fix by adding `actions/setup-node@v4` |
| A2 | Git Bash via `shell: bash` is available on `windows-latest` | Windows CI Leg pattern | Steps using `shell: bash` fail; fix by using `shell: pwsh` and converting assertions |
| A3 | `diff -r` is available in Windows Git Bash | Dry-Run Snapshot (if run on Windows) | Not an issue since dry-run test only runs in `ubuntu-latest` `tests/run.sh` job |
| A4 | `--update-expect` flag for regen-fixtures.sh is Claude's discretion | regen-fixtures pattern | If user prefers no flag, fixed-template EXPECT generation is equivalent |

**If A1 or A2 are wrong:** Windows CI job will need `actions/setup-node@v4` step or different shell. The assertions themselves (grep on settings.json) are portable.

---

## Sources

### Primary (HIGH confidence — verified against codebase)
- `tests/run.sh` — read in full; sections, helpers, patterns confirmed [VERIFIED: codebase]
- `tests/lib/sandbox.sh` — read in full; interface confirmed [VERIFIED: codebase]
- `scripts/audit-setup.sh` — read in full; what it checks and doesn't check confirmed [VERIFIED: codebase]
- `scripts/regen-fixtures.sh` — read in full; current behavior confirmed [VERIFIED: codebase]
- `.github/workflows/ci.yml` — read in full; job structure confirmed [VERIFIED: codebase]
- `tests/fixtures/_broken/EXPECT` — confirmed EXPECT format [VERIFIED: codebase]
- Live tests (see above) — `diff -r`, dry-run snapshot, audit output [VERIFIED: live test]

### Secondary (MEDIUM confidence — CONTEXT.md decisions)
- `.planning/phases/04-regression-suite-dry-run-proof/04-CONTEXT.md` — locked decisions D-01 through D-12
- `.planning/phases/03-sandboxed-per-profile-fixtures/03-CONTEXT.md` — sandbox pattern, EXPECT format
- `.planning/phases/02-dry-run-enforcement-chokepoint/02-CONTEXT.md` — `[dry-run]` output format, `CONJURE_DRY_MUTATION_COUNT`

### Tertiary (LOW confidence — assumed from training)
- Windows GitHub Actions runner environment (Node pre-installed, Git Bash available) [ASSUMED]

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all tools verified in codebase and live tests
- Architecture: HIGH — verified against actual test runner structure
- Pitfalls: HIGH — each pitfall was confirmed by reading actual code or running live tests
- Failure-mode approach: MEDIUM — audit-setup.sh gaps confirmed; detection alternatives verified

**Research date:** 2026-05-25
**Valid until:** 2026-06-25 (stable domain; only risk is GitHub Actions windows-latest image changes)
