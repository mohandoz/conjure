# Phase 2: Dry-Run Enforcement Chokepoint - Pattern Map

**Mapped:** 2026-05-24
**Files analyzed:** 17 (1 new + 16 modified)
**Analogs found:** 17 / 17

---

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---|---|---|---|---|
| `lib/mutate.sh` | utility/library | transform | `migrations/from-claude/migrate.sh` (DRY_RUN pattern) | role-match |
| `scripts/init-project.sh` | script | file-I/O | `migrations/from-claude/migrate.sh` (sourced KIT, env vars, idempotent writes) | exact |
| `cli/conjure` (cmd_init) | controller | request-response | self — `cmd_migrate()` at line 107 is the env-var threading template | exact |
| `profiles/ts-next/apply.sh` | script | file-I/O | `profiles/java-spring/apply.sh` (most complex profile — cp + chmod) | exact |
| `profiles/java-spring/apply.sh` | script | file-I/O | `profiles/ts-next/apply.sh` (same $DRY pattern) | exact |
| `profiles/monorepo/apply.sh` | script | file-I/O | `migrations/from-claude/migrate.sh` (dynamic heredoc content) | role-match |
| `profiles/python-fastapi/apply.sh` | script | file-I/O | `profiles/ts-next/apply.sh` | exact |
| `profiles/go-gin/apply.sh` | script | file-I/O | `profiles/ts-next/apply.sh` | exact |
| `profiles/node-nest/apply.sh` | script | file-I/O | `profiles/ts-next/apply.sh` | exact |
| `profiles/polyglot/apply.sh` | script | file-I/O | `profiles/ts-next/apply.sh` | exact |
| `profiles/rust-axum/apply.sh` | script | file-I/O | `profiles/ts-next/apply.sh` | exact |
| `profiles/data-science/apply.sh` | script | file-I/O | `profiles/ts-next/apply.sh` | exact |
| `compliance/hipaa/apply.sh` | script | file-I/O | `profiles/java-spring/apply.sh` (cp + chmod pattern) | exact |
| `compliance/gdpr/apply.sh` | script | file-I/O | `profiles/ts-next/apply.sh` | exact |
| `compliance/soc2/apply.sh` | script | file-I/O | `profiles/ts-next/apply.sh` | exact |
| `compliance/pci/apply.sh` | script | file-I/O | `profiles/ts-next/apply.sh` | exact |
| `tests/run.sh` | test | batch | self — existing preflight section (lines 103–158) is the integration test template | exact |

---

## Pattern Assignments

### `lib/mutate.sh` (NEW — utility/library, transform)

**Analog:** `migrations/from-claude/migrate.sh`

**No-analog for the library form itself** — the migration script is the closest existing file that reads `DRY_RUN` from env and uses `${DRY_RUN:-0}`. The library design comes from RESEARCH.md, but the env-var idioms match the migration script.

**Shebang + set pattern** (`scripts/preflight.sh` lines 1–12 — best POSIX 3.2+ library example in codebase):
```bash
#!/usr/bin/env bash
# lib/mutate.sh — sourced mutation chokepoint for Conjure.
# Source this file; call mutate_mkdir, mutate_cp, mutate_write, mutate_summary.
# Requires: DRY_RUN env var (0=live, 1=dry); set -u safe via ${DRY_RUN:-0}.
# POSIX bash 3.2+ compatible. No associative arrays, no mapfile, no local -n.
```
Note: do NOT add `set -uo pipefail` at top of `lib/mutate.sh` — it is sourced into callers that already have `set -uo pipefail`. Adding it again is harmless but the idiom in this codebase is that libraries do not set shell options.

**DRY_RUN env-var read pattern** (`migrations/from-claude/migrate.sh` line 15):
```bash
DRY="${DRY_RUN:-0}"
```
In `lib/mutate.sh` the functions read `${DRY_RUN:-0}` inline (never assign to a local `DRY`) to stay safe when sourced under `set -u`.

**Counter initialization pattern** — no existing analog; must be created. Use plain assignment with `:-` default so it is safe under `set -u` and idempotent on re-source:
```bash
CONJURE_DRY_MUTATION_COUNT="${CONJURE_DRY_MUTATION_COUNT:-0}"
```

**Function body pattern** — copy the guard+increment+return structure for all three mutate functions:
```bash
mutate_mkdir() {
  # Usage: mutate_mkdir <dir>
  if [ "${DRY_RUN:-0}" = "1" ]; then
    echo "[dry-run] would mkdir $1"
    CONJURE_DRY_MUTATION_COUNT=$((CONJURE_DRY_MUTATION_COUNT + 1))
    return 0
  fi
  mkdir -p "$1"
}

mutate_cp() {
  # Usage: mutate_cp <src> <dest>
  # Detects directories and uses cp -r automatically.
  if [ "${DRY_RUN:-0}" = "1" ]; then
    echo "[dry-run] would cp $1 $2"
    CONJURE_DRY_MUTATION_COUNT=$((CONJURE_DRY_MUTATION_COUNT + 1))
    return 0
  fi
  if [ -d "$1" ]; then
    cp -r "$1" "$2"
  else
    cp "$1" "$2"
  fi
}

mutate_write() {
  # Usage: mutate_write <dest> <content> [--append]
  # Pass content as a string arg — never pipe (pipe = subshell = lost counter).
  local dest="$1"
  local content="$2"
  local mode="${3:-}"
  if [ "${DRY_RUN:-0}" = "1" ]; then
    echo "[dry-run] would write $dest"
    CONJURE_DRY_MUTATION_COUNT=$((CONJURE_DRY_MUTATION_COUNT + 1))
    return 0
  fi
  if [ "$mode" = "--append" ]; then
    printf '%s\n' "$content" >> "$dest"
  else
    printf '%s\n' "$content" > "$dest"
  fi
}

mutate_summary() {
  # Call at end of each script. Only prints if DRY_RUN=1.
  if [ "${DRY_RUN:-0}" = "1" ]; then
    echo "[dry-run] ${CONJURE_DRY_MUTATION_COUNT} mutations skipped — run without --dry-run to apply"
  fi
}
```

---

### `scripts/init-project.sh` (MODIFY — script, file-I/O)

**Analog:** `migrations/from-claude/migrate.sh`

**Header pattern — add source line after variable declarations** (`migrate.sh` lines 14–17):
```bash
TARGET="${1:-$(pwd)}"
DRY="${DRY_RUN:-0}"          # ← migrate.sh reads DRY_RUN from env; init-project.sh must do same
KIT="${CONJURE_HOME:-/u01/conjure}"
# ADD after existing KIT line:
source "$CONJURE_HOME/lib/mutate.sh"
```
In `init-project.sh`, `KIT` is resolved via `$(dirname "$0")` (line 12). The `source` line must come after `KIT`/`CONJURE_HOME` is set, so the path resolves. Use `CONJURE_HOME` not `KIT` for the source path (D-03).

**Current KIT resolution** (`scripts/init-project.sh` lines 10–13):
```bash
MODE="${1:-existing}"
TARGET="${2:-$(pwd)}"
KIT="$(cd "$(dirname "$0")/.." && pwd)"
```
`KIT` and `CONJURE_HOME` both point to the same directory (the repo root). The source line uses `CONJURE_HOME` per D-03.

**Brace-expansion mkdir replacement** (`init-project.sh` line 25 — current):
```bash
mkdir -p .claude/{skills,agents,hooks,docs}
```
Replace with 4 explicit calls (brace expansion cannot pass through a function argument):
```bash
mutate_mkdir ".claude/skills"
mutate_mkdir ".claude/agents"
mutate_mkdir ".claude/hooks"
mutate_mkdir ".claude/docs"
```

**cp replacement pattern** (`init-project.sh` lines 30, 39, 49, 57, 65, 73 — current):
```bash
cp "$KIT/templates/$f" "$f"
cp "$KIT/templates/settings.json.tmpl" .claude/settings.json
cp "$hook" ".claude/hooks/$name"
cp -r "$KIT/templates/skills/$skill" ".claude/skills/$skill"
```
Replace with (mutate_cp auto-detects -r via `[ -d "$1" ]`):
```bash
mutate_cp "$KIT/templates/$f" "$f"
mutate_cp "$KIT/templates/settings.json.tmpl" ".claude/settings.json"
mutate_cp "$hook" ".claude/hooks/$name"
mutate_cp "$KIT/templates/skills/$skill" ".claude/skills/$skill"
```

**Remaining docs mkdir + cp** (`init-project.sh` lines 79, 82, 88):
```bash
mkdir -p docs/adr
cp "$KIT/templates/docs/$doc.md.tmpl" "docs/$doc.md"
cp "$KIT/templates/docs/ADR-TEMPLATE.md" docs/adr/0001-record-architecture-decisions.md
```
Replace with:
```bash
mutate_mkdir "docs/adr"
mutate_cp "$KIT/templates/docs/$doc.md.tmpl" "docs/$doc.md"
mutate_cp "$KIT/templates/docs/ADR-TEMPLATE.md" "docs/adr/0001-record-architecture-decisions.md"
```

**Heredoc write replacement** (`init-project.sh` lines 93–109 — current):
```bash
if [ ! -f .env.example ]; then
  cat >.env.example <<'EOF'
# .env.example — every env var, with placeholder values.
...
EOF
fi
```
Replace using variable-capture pattern (avoids subshell counter loss):
```bash
if [ ! -f .env.example ]; then
  ENV_CONTENT='# .env.example — every env var, with placeholder values.
# Real .env is gitignored.
#
# Add each new env var here when the code references one.

# Database
# DATABASE_URL=postgresql://user:pass@localhost:5432/dbname

# External services
# REASONER_BASE_URL=http://localhost:9009

# Secrets (placeholder values only)
# API_KEY=changeme'
  mutate_write ".env.example" "$ENV_CONTENT"
  echo "  ✓ created .env.example"
fi
```

**Single-line conditional write** (`init-project.sh` line 113 — current):
```bash
[ -f .claude/COMPOUND-CANDIDATES.md ] || echo "# Compound Engineering — Candidate Rules from Sessions" > .claude/COMPOUND-CANDIDATES.md
```
Replace with:
```bash
if [ ! -f .claude/COMPOUND-CANDIDATES.md ]; then
  mutate_write ".claude/COMPOUND-CANDIDATES.md" "# Compound Engineering — Candidate Rules from Sessions"
fi
```

**Summary call — add at end of script** (tail of `init-project.sh`, before the `cat <<EOF` next-steps block):
```bash
mutate_summary
```

---

### `cli/conjure` — cmd_init() (MODIFY — controller, request-response)

**Analog:** Self — `cmd_migrate()` at `cli/conjure` lines 88–108.

**Existing env-var threading template** (`cli/conjure` lines 107 — the proven pattern):
```bash
CONJURE_HOME="$CONJURE_HOME" DRY_RUN="$dryrun" bash "$script" "$target"
```

**Line 75 fix** (current → after):
```bash
# Current (line 75):
bash "$CONJURE_HOME/scripts/init-project.sh" "$mode" "$target"

# After:
CONJURE_HOME="$CONJURE_HOME" DRY_RUN="$dryrun" bash "$CONJURE_HOME/scripts/init-project.sh" "$mode" "$target"
```

**Line 80 fix** (current → after):
```bash
# Current (line 80):
bash "$CONJURE_HOME/profiles/$profile/apply.sh" "$target" "$dryrun"

# After (remove positional $dryrun arg; thread via env var):
CONJURE_HOME="$CONJURE_HOME" DRY_RUN="$dryrun" bash "$CONJURE_HOME/profiles/$profile/apply.sh" "$target"
```

**Line 84 fix** — the version stamp inline write. Source `lib/mutate.sh` at the top of `cmd_init()` (inside the function body, after local var declarations), then replace the bare redirect. Source location follows the `cmd_migrate` pattern of inline env resolution:
```bash
# Add near top of cmd_init() after local declarations:
source "$CONJURE_HOME/lib/mutate.sh"

# Replace line 84 (current):
echo "$CONJURE_VERSION" > "$target/.claude/.conjure-version"

# With:
mutate_write "$target/.claude/.conjure-version" "$CONJURE_VERSION"
mutate_summary
```

**set -uo pipefail context** (`cli/conjure` line 22 — already present):
```bash
set -uo pipefail
```
`lib/mutate.sh` uses `${DRY_RUN:-0}` and `${CONJURE_DRY_MUTATION_COUNT:-0}` throughout — safe under `set -u`. No additional guard needed in `cli/conjure`.

---

### `profiles/ts-next/apply.sh` (MODIFY — representative of all 8 simple profiles)

**Analog:** `profiles/java-spring/apply.sh` (most write operations; ts-next is itself the simplest)

**Current header** (`profiles/ts-next/apply.sh` lines 1–5):
```bash
#!/usr/bin/env bash
set -uo pipefail
TARGET="${1:-$(pwd)}"
DRY="${2:-0}"
PROFILE_DIR="$(cd "$(dirname "$0")" && pwd)"
```

**After header** (delete `DRY` line, add source):
```bash
#!/usr/bin/env bash
set -uo pipefail
TARGET="${1:-$(pwd)}"
PROFILE_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$CONJURE_HOME/lib/mutate.sh"
```

**Current write guard** (`profiles/ts-next/apply.sh` line 11):
```bash
[ "$DRY" = 0 ] && cat "$PROFILE_DIR/CLAUDE.md.fragment" >> "$TARGET/CLAUDE.md"
```

**After write guard** (Option B — inline command substitution, no subshell for mutate_write):
```bash
mutate_write "$TARGET/CLAUDE.md" "$(cat "$PROFILE_DIR/CLAUDE.md.fragment")" "--append"
```

**Tail of each profile script** (add before final echo):
```bash
mutate_summary
echo "✓ Profile ts-next applied"
```

This exact pattern applies to all 8 simple profiles: `data-science`, `go-gin`, `node-nest`, `polyglot`, `python-fastapi`, `rust-axum`. Each differs only in the `<!-- profile:NAME -->` sentinel and the `PROFILE_DIR` path — the source/mutate structure is identical.

---

### `profiles/java-spring/apply.sh` (MODIFY — profile with cp + chmod)

**Analog:** `profiles/ts-next/apply.sh` (same header migration) + `compliance/hipaa/apply.sh` (same cp+chmod decision)

**Current write guards** (`profiles/java-spring/apply.sh` lines 21–23):
```bash
[ "$DRY" = 0 ] && cp "$PROFILE_DIR/hooks/post-edit-format.sh" "$TARGET/.claude/hooks/post-edit-format.sh"
[ "$DRY" = 0 ] && chmod +x "$TARGET/.claude/hooks/post-edit-format.sh"
```

**After** (chmod is naturally skipped in dry-run because mutate_cp returns before creating the file — no need for an explicit chmod guard):
```bash
mutate_cp "$PROFILE_DIR/hooks/post-edit-format.sh" "$TARGET/.claude/hooks/post-edit-format.sh"
[ "${DRY_RUN:-0}" = "1" ] || chmod +x "$TARGET/.claude/hooks/post-edit-format.sh"
```

---

### `profiles/monorepo/apply.sh` (MODIFY — dynamic heredoc write)

**Analog:** `migrations/from-claude/migrate.sh` (dynamic content write at line 128: `echo "$(cat "$KIT/VERSION")" > ...`)

**Current dynamic heredoc** (`profiles/monorepo/apply.sh` lines 28–51):
```bash
if [ "$DRY" = 0 ]; then
  cat > "$pkg/CLAUDE.md" <<EOF
# $dir/$name — Local Working Notes
...
EOF
fi
```

**After** (variable capture to avoid subshell counter loss — same pattern as `.env.example` replacement in `init-project.sh`):
```bash
MONOREPO_CONTENT="# $dir/$name — Local Working Notes

<!-- This nested CLAUDE.md loads automatically when Claude reads files here. -->
<!-- ≤50 lines. Override root rules ONLY where this package differs. -->

## Local rules

- <package-specific rule>

## Build/test (this package only)

| Goal | Command |
| --- | --- |
| Build | \`<cmd>\` |
| Test | \`<cmd>\` |

## Notes

- Owner: <name>
- Type: <library | service | app>"
mutate_write "$pkg/CLAUDE.md" "$MONOREPO_CONTENT"
```

Note: backtick characters inside the variable content must be escaped as `\`` to avoid command substitution. Verify the exact CLAUDE.md template content in `profiles/monorepo/apply.sh` before applying.

---

### `compliance/hipaa/apply.sh` (MODIFY — most complex compliance overlay)

**Analog:** `profiles/java-spring/apply.sh` (cp + chmod pattern) + `profiles/ts-next/apply.sh` (fragment append pattern)

**Current file** (`compliance/hipaa/apply.sh` lines 1–25 — all bare writes):
```bash
#!/usr/bin/env bash
set -uo pipefail
TARGET="${1:-$(pwd)}"
PROFILE_DIR="$(cd "$(dirname "$0")" && pwd)"
```
Note: `compliance/hipaa/apply.sh` has no `DRY` variable at all — cleaner starting point than profiles.

**After header** (just add source line):
```bash
#!/usr/bin/env bash
set -uo pipefail
TARGET="${1:-$(pwd)}"
PROFILE_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$CONJURE_HOME/lib/mutate.sh"
```

**Current fragment append** (`compliance/hipaa/apply.sh` line 10):
```bash
cat "$PROFILE_DIR/CLAUDE.md.fragment" >> "$TARGET/CLAUDE.md"
```
Replace with:
```bash
mutate_write "$TARGET/CLAUDE.md" "$(cat "$PROFILE_DIR/CLAUDE.md.fragment")" "--append"
```

**Current mkdir calls** (`compliance/hipaa/apply.sh` lines 16, 21):
```bash
mkdir -p "$TARGET/.claude/hooks"
mkdir -p "$TARGET/docs/compliance"
```
Replace with:
```bash
mutate_mkdir "$TARGET/.claude/hooks"
mutate_mkdir "$TARGET/docs/compliance"
```

**Current cp calls** (`compliance/hipaa/apply.sh` lines 17, 22):
```bash
cp "$PROFILE_DIR/pre-commit-phi-scan.sh" "$TARGET/.claude/hooks/" 2>/dev/null || true
cp "$PROFILE_DIR/CONTROLS.md" "$TARGET/docs/compliance/HIPAA-CONTROLS.md" 2>/dev/null || true
```
Replace with (mutate_cp handles the -r detection; the `|| true` can be preserved for missing-source tolerance):
```bash
mutate_cp "$PROFILE_DIR/pre-commit-phi-scan.sh" "$TARGET/.claude/hooks/pre-commit-phi-scan.sh"
mutate_cp "$PROFILE_DIR/CONTROLS.md" "$TARGET/docs/compliance/HIPAA-CONTROLS.md"
```

**chmod** (`compliance/hipaa/apply.sh` line 18 — same decision as java-spring):
```bash
chmod +x "$TARGET/.claude/hooks/pre-commit-phi-scan.sh" 2>/dev/null
```
Replace with:
```bash
[ "${DRY_RUN:-0}" = "1" ] || chmod +x "$TARGET/.claude/hooks/pre-commit-phi-scan.sh" 2>/dev/null
```

**Tail**:
```bash
mutate_summary
echo "✓ HIPAA overlay applied"
```

---

### `compliance/gdpr/apply.sh`, `compliance/soc2/apply.sh`, `compliance/pci/apply.sh` (MODIFY — simple overlays)

**Analog:** `profiles/ts-next/apply.sh` (append-only, same migration pattern)

All three are structurally identical — 10 lines each, one bare `cat >> CLAUDE.md` write, no DRY guard at all. Migration is uniform:

1. Add `source "$CONJURE_HOME/lib/mutate.sh"` after `PROFILE_DIR` declaration
2. Replace `cat "$PROFILE_DIR/CLAUDE.md.fragment" >> "$TARGET/CLAUDE.md"` with `mutate_write "$TARGET/CLAUDE.md" "$(cat "$PROFILE_DIR/CLAUDE.md.fragment")" "--append"`
3. Add `mutate_summary` before final echo

**Current gdpr body** (`compliance/gdpr/apply.sh` lines 6–8):
```bash
if [ -f "$TARGET/CLAUDE.md" ] && ! grep -q "<!-- compliance:gdpr -->" "$TARGET/CLAUDE.md"; then
  cat "$PROFILE_DIR/CLAUDE.md.fragment" >> "$TARGET/CLAUDE.md"
fi
```
After:
```bash
if [ -f "$TARGET/CLAUDE.md" ] && ! grep -q "<!-- compliance:gdpr -->" "$TARGET/CLAUDE.md"; then
  mutate_write "$TARGET/CLAUDE.md" "$(cat "$PROFILE_DIR/CLAUDE.md.fragment")" "--append"
fi
```
Same pattern for `soc2` and `pci` (change sentinel string accordingly).

---

### `tests/run.sh` (MODIFY — integration test, batch)

**Analog:** Self — existing preflight integration test section (`tests/run.sh` lines 103–158).

**Test section structure pattern** (`tests/run.sh` lines 103–112 — preflight smoke test):
```bash
echo
echo "▸ Preflight script"

# a) Smoke: all required deps present in test env
if bash scripts/preflight.sh >/dev/null 2>&1; then
  pass "scripts/preflight.sh: exits 0 (all required deps present)"
else
  fail "scripts/preflight.sh: non-zero exit (required dep missing in test env?)"
fi
```

**Temp-dir isolation pattern** (`tests/run.sh` lines 114–127 — STRIPPED_PATH pattern for isolated env):
```bash
STRIPPED_PATH=""
if command -v node >/dev/null 2>&1; then
  STRIPPED_PATH="$(printf '%s' "$PATH" | tr ':' '\n' | ...)"
  if PATH="$STRIPPED_PATH" bash scripts/preflight.sh >/dev/null 2>&1; then
    fail "..."
  else
    pass "..."
  fi
```
Apply the same temp-dir snapshot idiom for the dry-run test section:
```bash
echo
echo "▸ Dry-run enforcement (SAFE-01, SAFE-02)"

TMPDIR_TARGET="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_TARGET"' EXIT

# Create a minimal CLAUDE.md so profile/compliance fragments have something to append to
printf '# Test project\n' > "$TMPDIR_TARGET/CLAUDE.md"

# Run conjure init --dry-run
DRY_OUT="$(CONJURE_HOME="$CONJURE_HOME" cli/conjure init --dry-run "$TMPDIR_TARGET" 2>&1 || true)"

# SAFE-01: target tree must be unchanged (no .claude/ created)
if [ -d "$TMPDIR_TARGET/.claude" ]; then
  fail "dry-run: .claude/ was created (filesystem mutated)"
else
  pass "dry-run: .claude/ not created (SAFE-01)"
fi

# SAFE-01: [dry-run] prefix lines must appear in output
if printf '%s' "$DRY_OUT" | grep -q "\[dry-run\]"; then
  pass "dry-run: [dry-run] prefix lines present in output"
else
  fail "dry-run: no [dry-run] lines in output"
fi

# SAFE-02: mutation count > 0 reported
if printf '%s' "$DRY_OUT" | grep -qE "\[dry-run\] [1-9][0-9]* mutations skipped"; then
  pass "dry-run: mutation count > 0 in summary line"
else
  fail "dry-run: summary line missing or count is 0"
fi
```

**pass/fail helper reuse** (`tests/run.sh` lines 14–15 — already defined at top of file):
```bash
pass() { echo "  ✓ $1"; PASS=$((PASS+1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL+1)); }
```
New test section reuses these — no new helpers needed.

---

## Shared Patterns

### DRY_RUN env-var inheritance from CLI to subprocess

**Source:** `cli/conjure` line 107 (existing, verified working)
**Apply to:** All subprocess invocations in `cmd_init()` (lines 75 and 80)

```bash
# The proven template — copy exactly:
CONJURE_HOME="$CONJURE_HOME" DRY_RUN="$dryrun" bash "$script" "$target"
```

### lib/mutate.sh source line

**Source:** Pattern derived from `migrations/from-claude/migrate.sh` line 16 (`KIT="${CONJURE_HOME:-...}"`)
**Apply to:** All scripts that call `mutate_*` functions — `scripts/init-project.sh`, all `profiles/*/apply.sh`, all `compliance/*/apply.sh`, and inside `cmd_init()` in `cli/conjure`

```bash
# Always use CONJURE_HOME (absolute, set by CLI before child invocation):
source "$CONJURE_HOME/lib/mutate.sh"
```

Never use relative paths (`source ../lib/mutate.sh`) — breaks when scripts are called from a different working directory.

### set -u safe variable access

**Source:** `cli/conjure` line 22 (`set -uo pipefail`); `migrations/from-claude/migrate.sh` line 15 (`DRY="${DRY_RUN:-0}"`)
**Apply to:** Every variable reference in `lib/mutate.sh`

```bash
# Pattern — always use :- default, never bare $VAR:
${DRY_RUN:-0}
${CONJURE_DRY_MUTATION_COUNT:-0}
```

### printf over echo for content writes

**Source:** `scripts/preflight.sh` lines 92, 103, 113 (uses `printf` consistently)
**Apply to:** `mutate_write` implementation in `lib/mutate.sh`

```bash
# Use printf '%s\n', not echo, for portability (echo interprets -n/-e on some platforms):
printf '%s\n' "$content" >> "$dest"
printf '%s\n' "$content" > "$dest"
```

### mutate_summary call placement

**Source:** No existing analog — new convention
**Apply to:** Tail of every retrofitted script before the final status echo

```bash
# Always last mutation-related call, before informational output:
mutate_summary
echo "✓ Profile/Overlay NAME applied"
```

### chmod guard pattern (not a mutate_* call)

**Source:** `migrations/from-claude/migrate.sh` line 88 (`[ "$DRY" = 0 ] && chmod +x "$h"`)
**Apply to:** `profiles/java-spring/apply.sh` and `compliance/hipaa/apply.sh`

```bash
# D-02 excludes mutate_chmod; use inline env-var guard instead:
[ "${DRY_RUN:-0}" = "1" ] || chmod +x "$TARGET/path/to/file"
```

---

## No Analog Found

All files have analogs. No entries in this table.

---

## Metadata

**Analog search scope:** `cli/`, `scripts/`, `profiles/`, `compliance/`, `migrations/`, `tests/`
**Files read directly:** `cli/conjure`, `scripts/init-project.sh`, `scripts/preflight.sh`, `migrations/from-claude/migrate.sh`, `profiles/ts-next/apply.sh`, `profiles/java-spring/apply.sh`, `profiles/monorepo/apply.sh`, `profiles/python-fastapi/apply.sh`, `compliance/hipaa/apply.sh`, `compliance/gdpr/apply.sh`, `compliance/soc2/apply.sh`, `compliance/pci/apply.sh`, `tests/run.sh`
**Pattern extraction date:** 2026-05-24
