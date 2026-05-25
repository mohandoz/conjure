# Phase 4: Regression Suite & Dry-Run Proof - Pattern Map

**Mapped:** 2026-05-25
**Files analyzed:** 13 (2 modified, 9 new EXPECT files, 1 modified, 1 modified)
**Analogs found:** 13 / 13

---

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `tests/run.sh` (3 new sections) | test-runner | batch | `tests/run.sh` lines 262-282 (`▸ Broken fixture` section) | exact |
| `tests/fixtures/ts-next/EXPECT` | golden-file | transform | `tests/fixtures/_broken/EXPECT` | exact |
| `tests/fixtures/java-spring/EXPECT` | golden-file | transform | `tests/fixtures/_broken/EXPECT` | exact |
| `tests/fixtures/rust-axum/EXPECT` | golden-file | transform | `tests/fixtures/_broken/EXPECT` | exact |
| `tests/fixtures/go-gin/EXPECT` | golden-file | transform | `tests/fixtures/_broken/EXPECT` | exact |
| `tests/fixtures/python-fastapi/EXPECT` | golden-file | transform | `tests/fixtures/_broken/EXPECT` | exact |
| `tests/fixtures/node-nest/EXPECT` | golden-file | transform | `tests/fixtures/_broken/EXPECT` | exact |
| `tests/fixtures/monorepo/EXPECT` | golden-file | transform | `tests/fixtures/_broken/EXPECT` | exact |
| `tests/fixtures/polyglot/EXPECT` | golden-file | transform | `tests/fixtures/_broken/EXPECT` | exact |
| `tests/fixtures/data-science/EXPECT` | golden-file | transform | `tests/fixtures/_broken/EXPECT` | exact |
| `.github/workflows/ci.yml` (new job) | CI config | event-driven | `.github/workflows/ci.yml` existing `audit-on-fixture` job | exact |
| `scripts/regen-fixtures.sh` (extend) | utility | batch | `scripts/regen-fixtures.sh` existing `regen_profile` function | exact |

---

## Pattern Assignments

### `tests/run.sh` — Section 1: Golden-file EXPECT loop (TEST-03)

**Analog:** `tests/run.sh` lines 262-282 (`▸ Broken fixture — specific finding assertion`)

**Section header pattern** (lines 24, 47, 62, 86, etc. — consistent throughout file):
```bash
echo
echo "▸ Golden-file EXPECT loop (TEST-03)"
```

**Fixture iteration pattern** (lines 248-260 — existing `▸ Fixture audits` section):
```bash
for fx in "$CONJURE_HOME/tests/fixtures"/[^_]*/; do
  prof=$(basename "$fx")
  sandbox_setup "$fx"
  trap 'rm -rf "$SANDBOX_DIR"' EXIT
  AUDIT_OUT="$(bash "$CONJURE_HOME/scripts/audit-setup.sh" "$SANDBOX_DIR" 2>&1)"
```

**EXPECT loop core pattern** (lines 274-282 — `_broken` EXPECT loop; generalize this verbatim):
```bash
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

**Combined new section (TEST-03)** — merges fixture loop + EXPECT loop with `[ -f EXPECT ]` guard:
```bash
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
```

**Key constraints:**
- Use `[^_]*/` glob (lines 248) — excludes `_broken/`, which has its own dedicated section
- `sandbox_setup` + `trap` pair must appear exactly as in lines 250-251
- Variable for audit output is `AUDIT_OUT` (not `BROKEN_OUT`)
- Insert after line 282 (end of `▸ Broken fixture` section), before line 284 (`# Summary`)

---

### `tests/run.sh` — Section 2: Dry-run byte-identical snapshot (TEST-05)

**Analog:** `tests/run.sh` lines 186-216 (`▸ Dry-run enforcement` section) — uses same `mktemp -d` + `trap` pattern but `sandbox_setup` must NOT be used here

**mktemp + trap pattern** (lines 188-189):
```bash
TMPDIR_TARGET="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_TARGET"' EXIT
```

**CONJURE_HOME-prefixed CLI call pattern** (line 195):
```bash
DRY_OUT="$(CONJURE_HOME="$CONJURE_HOME" cli/conjure init --dry-run "$TMPDIR_TARGET" 2>&1 || true)"
```

**pass/fail with diff diagnostic output pattern** (lines 254-259):
```bash
if [ "$AUDIT_RC" -eq 0 ]; then
  pass "fixture audit green: $prof"
else
  fail "fixture audit non-green (rc=$AUDIT_RC): $prof"
  printf '%s\n' "$AUDIT_OUT" | head -5
fi
```

**Combined new section (TEST-05)** — plain mktemp, no sandbox_setup, explicit cleanup per iteration:
```bash
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
```

**Key constraints:**
- Do NOT call `sandbox_setup` here — it clobbers HOME/PATH and its `trap EXIT` would replace the cleanup trap for DRY_ORIG/DRY_SNAP (sandbox.sh line 35: `trap 'rm -rf "$SANDBOX_DIR"' EXIT`)
- Must `rm -rf` both dirs at end of each iteration (belt-and-suspenders alongside any EXIT trap)
- `diff -r` without `--brief` so failure output is diagnostic
- Insert after the TEST-03 section, before the Summary block

---

### `tests/run.sh` — Section 3: Failure-mode reproductions (TEST-07)

**Analog:** `tests/run.sh` lines 86-91 (`▸ Hook exit codes` section) — pattern for detecting `exit 1` via grep on a file

**Hook exit-code grep pattern** (lines 87-91):
```bash
while IFS= read -r hook; do
  if grep -qE '^exit 1$' "$hook"; then fail "hook uses 'exit 1' (should be 'exit 2' for blocks): $hook"
  else pass "exit codes ok: $hook"
  fi
done < <(find templates/hooks compliance/*/pre-commit-*.sh -name '*.sh' 2>/dev/null)
```

**Audit-setup call pattern for size-cap detection** (lines 98-102):
```bash
bash scripts/audit-setup.sh "$CONJURE_HOME" >/dev/null 2>&1
rc=$?
if [ "$rc" -le 2 ]; then pass "audit-setup.sh ran (rc=$rc, expected 0|1|2)"
else fail "audit-setup.sh crashed (rc=$rc)"
fi
```

**Combined new section (TEST-07)** — three self-contained synthetic mini-fixtures:
```bash
echo
echo "▸ Failure-mode reproductions (TEST-07)"

# FM-1: Size cap exceeded (audit-setup.sh detects CLAUDE.md > 100 lines)
FM_DIR="$(mktemp -d)"
printf '# SYNTHETIC — size cap test\n' > "$FM_DIR/CLAUDE.md"
for i in $(seq 1 105); do printf '# filler line %s\n' "$i" >> "$FM_DIR/CLAUDE.md"; done
FM_OUT="$(bash "$CONJURE_HOME/scripts/audit-setup.sh" "$FM_DIR" 2>&1 || true)"
if printf '%s\n' "$FM_OUT" | grep -q "HARD CAP exceeded"; then
  pass "FM: size cap detected by audit"
else
  fail "FM: size cap NOT detected"
fi
rm -rf "$FM_DIR"

# FM-2: Hook wrong exit code (grep-detectable — audit-setup.sh does NOT check this)
FM_DIR="$(mktemp -d)"
mkdir -p "$FM_DIR/.claude/hooks"
printf '#!/usr/bin/env bash\nexit 1\n' > "$FM_DIR/.claude/hooks/bad-gate.sh"
if grep -qE '^exit 1$' "$FM_DIR/.claude/hooks/bad-gate.sh"; then
  pass "FM: hook exit 1 detectable via grep"
else
  fail "FM: hook exit 1 NOT found"
fi
rm -rf "$FM_DIR"

# FM-3: Version mismatch (conjure update detects — audit-setup.sh does NOT check .conjure-version)
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
```

**Key constraints:**
- FM-2 uses `grep -qE '^exit 1$'` directly on the hook file — NOT `audit-setup.sh` (which does not check hook exit codes per RESEARCH.md Finding F-01)
- FM-3 uses `cli/conjure update` — NOT `audit-setup.sh` (which does not check `.conjure-version`)
- FM-3 version file must be at `$FM_DIR/.claude/.conjure-version` (not `$FM_DIR/.conjure-version`) per RESEARCH.md Pitfall 5
- Each FM block uses its own `FM_DIR` with explicit `rm -rf` after assertions
- No `trap` needed for FM dirs since `rm -rf` is explicit at end of each block

---

### `tests/fixtures/<profile>/EXPECT` (all 9 green fixtures)

**Analog:** `tests/fixtures/_broken/EXPECT` (lines 1-3 — the only existing EXPECT file)

```
# tests/fixtures/_broken/EXPECT
# One extended-grep pattern per line. Comments (# prefix) and blank lines are ignored.
HARD CAP exceeded
```

**Green fixture EXPECT pattern** — identical format, different patterns:
```
# tests/fixtures/<profile>/EXPECT
# Positive-pass patterns — generated by scripts/regen-fixtures.sh
# Comments and blank lines ignored. Same format as _broken/EXPECT.
PASS: [0-9]
WARN: 0
FAIL: 0
```

**Key constraints:**
- `PASS: [0-9]` matches any `PASS: N` where N >= 1 (avoids brittleness when audit gains new checks)
- `WARN: 0` and `FAIL: 0` are exact semantic assertions — green fixtures must produce zero warns and zero fails
- Patterns must be grep-E compatible (these three are plain string + character-class patterns, both valid)
- All 9 green fixtures get identical EXPECT content (RESEARCH.md Finding F-02: all produce `PASS: 17    WARN: 0    FAIL: 0`)
- Do NOT include absolute paths — would fail on different machines (RESEARCH.md Anti-Patterns)

**Profiles requiring EXPECT files:**
`ts-next`, `java-spring`, `rust-axum`, `go-gin`, `python-fastapi`, `node-nest`, `monorepo`, `polyglot`, `data-science`

---

### `.github/workflows/ci.yml` — new `windows-hook-wiring` job (TEST-06)

**Analog:** `.github/workflows/ci.yml` lines 36-52 (`audit-on-fixture` job) — same job-level structure: `runs-on`, `steps`, `uses: actions/checkout@v4`, named steps with `run:` blocks

**Job-level pattern** (lines 36-41):
```yaml
  audit-on-fixture:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Scaffold fixture
        run: |
```

**Assertion step pattern** (lines 51-52 — `grep -q` assertion):
```yaml
          grep -q "PASS:" /tmp/audit.log
```

**New `windows-hook-wiring` job** — same indentation, `windows-latest` runner, `shell: bash` on every step:
```yaml
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

**Key constraints:**
- `shell: bash` on every step — invokes Git Bash (pre-installed on `windows-latest`); do NOT use default PowerShell
- No `apt-get`, `choco`, or `npm install` — D-11 forbids extra dependency installation
- Do NOT run `bash tests/run.sh` — shellcheck is not pre-installed on `windows-latest` (RESEARCH.md Pitfall 4)
- Use `CONJURE_HOME="$GITHUB_WORKSPACE"` — same pattern as line 44 in existing job (`$GITHUB_WORKSPACE` not `$PWD`)
- Insert after `audit-on-fixture` job (after line 52), at same YAML indentation level (2-space job indent)

---

### `scripts/regen-fixtures.sh` — extend to write EXPECT files

**Analog:** `scripts/regen-fixtures.sh` lines 57-87 (`_write_seed_claude` function) — uses `printf` to write file content line by line; same pattern for EXPECT generation

**Existing write-file pattern** (`_write_seed_claude`, lines 62-87):
```bash
_write_seed_claude() {
  local seed="$1"
  printf '# GENERATED — do not edit directly; run scripts/regen-fixtures.sh\n' > "$seed/CLAUDE.md"
  printf '\n' >> "$seed/CLAUDE.md"
  printf '## Project\n' >> "$seed/CLAUDE.md"
  ...
}
```

**Existing audit-verification block** (lines 102-106 inside `regen_profile`):
```bash
  if ! bash "$CONJURE_HOME/scripts/audit-setup.sh" "$FIXTURES_DIR/$p" >/dev/null 2>&1; then
    printf '[regen] WARN: %s fixture fails audit — check profile output\n' "$p" >&2
    exit 1
  fi
  printf '[regen] %s done\n' "$p"
```

**Existing argument parsing pattern** (lines 16-27 — `--profile` flag):
```bash
while [ $# -gt 0 ]; do
  case "$1" in
    --profile)
      PROFILE_FILTER="${2:?'--profile requires an argument'}"
      shift 2
      ;;
    *)
      printf 'Unknown argument: %s\n' "$1" >&2
      exit 1
      ;;
  esac
done
```

**Extension: add `--update-expect` flag** — new case in the argument-parsing `while` loop; new `_write_expect` function; call from `regen_profile` after the audit-verification block:

New flag case (insert into existing while loop at lines 16-27):
```bash
    --update-expect)
      UPDATE_EXPECT=1
      shift
      ;;
```

New function (insert before `regen_profile`):
```bash
# _write_expect <profile>
# Writes a fixed-template EXPECT file for a green fixture.
# All 9 green fixtures produce PASS: 17  WARN: 0  FAIL: 0 as of Phase 3.
_write_expect() {
  local p="$1"
  local expect_file="$FIXTURES_DIR/$p/EXPECT"
  {
    printf '# tests/fixtures/%s/EXPECT\n' "$p"
    printf '# Positive-pass patterns — generated by scripts/regen-fixtures.sh\n'
    printf '# Comments and blank lines ignored. Same format as _broken/EXPECT.\n'
    printf 'PASS: [0-9]\n'
    printf 'WARN: 0\n'
    printf 'FAIL: 0\n'
  } > "$expect_file"
  printf '[regen] %s: wrote EXPECT\n' "$p"
}
```

Call site (insert after audit-verification block in `regen_profile`, replacing line 107's `printf done`):
```bash
  _write_expect "$p"
  printf '[regen] %s done\n' "$p"
```

**Key constraints:**
- `UPDATE_EXPECT` variable initialized to `""` at top of file (same pattern as `PROFILE_FILTER=""` at line 13)
- `_write_expect` uses `printf` (not `echo`) — consistent with entire file's style
- EXPECT content is a fixed template (not captured from live audit output) — simpler and sufficient since all green fixtures produce the same summary
- Guard `_write_expect` call with `[ -n "${UPDATE_EXPECT:-}" ]` only if flag is optional; always write if regen is running without the flag, per CONTEXT.md D-03 (EXPECT files regenerated whenever fixtures are regenerated)

---

## Shared Patterns

### pass/fail Helpers
**Source:** `tests/run.sh` lines 15-16
**Apply to:** All new sections in `tests/run.sh`
```bash
pass() { echo "  ✓ $1"; PASS=$((PASS+1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL+1)); }
```

### Section Header Format
**Source:** `tests/run.sh` lines 24, 47, 62, 79, 86, 93, 105, 163, 186, 219, 228, 237, 246, 263
**Apply to:** All three new sections in `tests/run.sh`
```bash
echo
echo "▸ <Section name> (<REQ-ID>)"
```
Pattern: blank `echo` line before each header, `▸` character prefix, requirement ID in parens.

### Glob Excluding `_broken`
**Source:** `tests/run.sh` line 248
**Apply to:** EXPECT loop (TEST-03), dry-run snapshot (TEST-05)
```bash
for fx in "$CONJURE_HOME/tests/fixtures"/[^_]*/; do
```
Pattern: `[^_]*/` excludes `_broken/` fixture from green-only loops.

### sandbox_setup + trap Pair
**Source:** `tests/run.sh` lines 250-251; `tests/lib/sandbox.sh` lines 32-41
**Apply to:** EXPECT loop section (TEST-03); NOT the dry-run snapshot section (TEST-05)
```bash
sandbox_setup "$fx"
trap 'rm -rf "$SANDBOX_DIR"' EXIT
```
Note: In the dry-run section (TEST-05), use plain `mktemp -d` + explicit `rm -rf` instead — `sandbox_setup` clobbers HOME/PATH which would contaminate the directory comparison.

### CONJURE_HOME-Prefixed CLI Invocation
**Source:** `tests/run.sh` line 195
**Apply to:** dry-run snapshot section (TEST-05), FM-3 version-mismatch test (TEST-07)
```bash
CONJURE_HOME="$CONJURE_HOME" cli/conjure init --dry-run "$TMPDIR_TARGET" 2>&1 || true
```

### printf for Pattern Output (not echo)
**Source:** `tests/run.sh` lines 205, 212 (grep assertions on captured output)
**Apply to:** All `grep -q` assertions in new sections
```bash
if printf '%s\n' "$AUDIT_OUT" | grep -qE "$pattern"; then
```
Pattern: use `printf '%s\n'` to pipe captured output into grep — avoids `echo` interpretation of special characters.

### GitHub Actions Job YAML Structure
**Source:** `.github/workflows/ci.yml` lines 36-52
**Apply to:** new `windows-hook-wiring` job
```yaml
  <job-name>:
    runs-on: <runner>
    steps:
      - uses: actions/checkout@v4
      - name: <step name>
        run: |
          <commands>
```
2-space indentation for job names; 6-space for steps; `run: |` for multi-line, `run: <cmd>` for single-line.

---

## No Analog Found

All files have close analogs in the codebase. No files in Phase 4 require falling back to RESEARCH.md patterns as the primary source.

---

## Metadata

**Analog search scope:** `tests/`, `.github/workflows/`, `scripts/`
**Files scanned:** 5 source files read in full (`tests/run.sh`, `tests/lib/sandbox.sh`, `scripts/regen-fixtures.sh`, `.github/workflows/ci.yml`, `tests/fixtures/_broken/EXPECT`)
**Pattern extraction date:** 2026-05-25
