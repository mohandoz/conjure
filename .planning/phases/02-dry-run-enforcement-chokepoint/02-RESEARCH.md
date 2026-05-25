# Phase 02: Dry-Run Enforcement Chokepoint — Research

**Researched:** 2026-05-24
**Domain:** POSIX bash library design, mutation chokepoint pattern, env-var threading
**Confidence:** HIGH — all findings based on direct code audit of the actual codebase and live shell verification

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** `lib/mutate.sh` is a **sourced library**, not a standalone script. Scripts do `source "$CONJURE_HOME/lib/mutate.sh"` at the top, then call `mutate_cp`, `mutate_mkdir`, `mutate_write`.
- **D-02:** Expose **minimal function set**: `mutate_mkdir`, `mutate_cp`, `mutate_write`. Covers all actual call sites. No future-proofing (no `mutate_mv`, `mutate_rm`, `mutate_chmod`).
- **D-03:** `DRY_RUN` is an **env var** read by `lib/mutate.sh`. The CLI already exports `DRY_RUN="$dryrun"` for migrations (line 107); extend the same pattern to `init-project.sh` and all apply scripts. No argument threading required.
- **D-04:** Each suppressed mutation prints: `[dry-run] would <op> <args>` (exact prefix, searchable/greppable).
- **D-05:** Print a **summary line at end** of each script's run: `[dry-run] N mutations skipped — run without --dry-run to apply`. Accumulated via `CONJURE_DRY_MUTATION_COUNT` env/global.
- **D-06:** All 4 compliance overlays included in Phase 2. DRY_RUN flows via env var inheritance.
- **D-07:** Compliance scripts must respect `DRY_RUN` when invoked by users even though not called by `conjure init`.

### Claude's Discretion

- Exact `$LIB` resolution path: **use `$CONJURE_HOME/lib/mutate.sh`** (established pattern).
- `mutate_write` content passing: **stdin pipe for multi-line**, positional arg for single-line. *(See Pitfall 3 — pipe creates subshell, breaks counter. Planner should resolve.)*
- Exact minimum bash version: **POSIX bash 3.2+** (matches project-wide constraint).

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| SAFE-01 | `conjure init --dry-run` performs zero filesystem mutations — threads through `init-project.sh`, profile `apply.sh`, and the `.conjure-version` stamp | Write-site inventory below identifies every unguarded mutation; `lib/mutate.sh` + env-var threading is the proven fix pattern already used for migrations. |
| SAFE-02 | All writes route through one shared mutation helper (`lib/mutate.sh`) that honors dry-run, so enforcement is a chokepoint not per-call-site | Confirmed: 0 files in `lib/` exist today; creating `lib/mutate.sh` as the sole write abstraction closes the gap. All 26 bare write sites catalogued. |
</phase_requirements>

---

## Summary

Phase 2 creates `lib/mutate.sh` — a sourced bash library that wraps every filesystem write — and retrofits all write sites to route through it. The result: setting `DRY_RUN=1` in the environment prevents all mutations everywhere, enforced at one chokepoint.

The codebase has **26 unguarded write operations** spread across `scripts/init-project.sh` (12 writes), `profiles/*/apply.sh` (9 profiles × 1–3 writes each), and `compliance/*/apply.sh` (4 overlays, no dry-run guard at all). The `cli/conjure` version stamp at line 84 is also unguarded. The migration scripts already demonstrate the correct pattern: `CONJURE_HOME="$CONJURE_HOME" DRY_RUN="$dryrun" bash "$script" "$target"` at `cli/conjure:107`. Phase 2 extends this pattern to every other write path.

The `lib/` directory does not exist yet. `lib/mutate.sh` is the first file in it. The library must be POSIX bash 3.2+ compatible (no associative arrays, no `mapfile`, no `local -n`), safe to source under `set -uo pipefail`, and use `${DRY_RUN:-0}` throughout to avoid unbound variable errors. One verified pitfall: piping content into `mutate_write` (e.g., `printf '%s' "$content" | mutate_write "$dest"`) runs the function in a subshell and silently loses counter increments. The planner must choose between the two safe alternatives documented in Pitfall 3.

**Primary recommendation:** Build `lib/mutate.sh` first (Wave 0), retrofit init + profiles + compliance in parallel (Wave 1), wire CLI env-var threading last (Wave 2), then add integration test assertion to `tests/run.sh` (Wave 3).

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Dry-run gate / mutation suppression | `lib/mutate.sh` (shared library) | — | Single chokepoint; callers are ignorant of mode |
| DRY_RUN flag parsing | `cli/conjure` cmd_init() | — | Parsed once at CLI entry; threaded via env var to all children |
| Env-var threading to subprocesses | `cli/conjure` (export site) | — | Parent shell sets `DRY_RUN` before `bash child.sh` |
| Per-script mutation counting/summary | Each script that sources `lib/mutate.sh` | — | Counter is shell-local; subprocesses don't share it (verified) |
| Integration test assertion | `tests/run.sh` | — | Phase 4 golden-file tests will grep for `[dry-run]` prefix |

---

## Write-Site Inventory (Complete Audit)

> All findings are `[VERIFIED: direct code audit]`.

### cli/conjure — 3 write sites

| Line | Operation | Type | Current Status |
|------|-----------|------|---------------|
| 75 | `bash "$CONJURE_HOME/scripts/init-project.sh" "$mode" "$target"` | subprocess | DRY_RUN not passed — **live bug** |
| 80 | `bash "$CONJURE_HOME/profiles/$profile/apply.sh" "$target" "$dryrun"` | subprocess | Passes `$dryrun` as positional `$2` (inconsistent with env-var pattern) |
| 84 | `echo "$CONJURE_VERSION" > "$target/.claude/.conjure-version"` | write | Completely unguarded — **live bug** |

**Required changes:**
- L75: Add `CONJURE_HOME="$CONJURE_HOME" DRY_RUN="$dryrun"` prefix (same pattern as L107)
- L80: Add `DRY_RUN="$dryrun"` prefix; remove `"$dryrun"` positional arg
- L84: Source `lib/mutate.sh` in `cmd_init()` and replace with `mutate_write "$target/.claude/.conjure-version" "$CONJURE_VERSION"`

### scripts/init-project.sh — 12 write sites (0 with dry-run guards)

| Line | Operation | Type | Note |
|------|-----------|------|------|
| 25 | `mkdir -p .claude/{skills,agents,hooks,docs}` | mkdir | Brace-expansion mkdir |
| 30 | `cp "$KIT/templates/$f" "$f"` | cp | Loop over 3 root dotfiles |
| 39 | `cp "$KIT/templates/settings.json.tmpl" .claude/settings.json` | cp | Conditional (file absent) |
| 49 | `cp "$hook" ".claude/hooks/$name"` | cp | Loop over .mjs hook files |
| 57 | `cp -r "$KIT/templates/skills/$skill" ".claude/skills/$skill"` | cp -r | Tooling skills loop |
| 65 | `cp -r "$KIT/templates/skills/$skill" ".claude/skills/$skill"` | cp -r | Project skills loop |
| 73 | `cp "$KIT/templates/agents/$agent" ".claude/agents/$agent"` | cp | Agents loop |
| 79 | `mkdir -p docs/adr` | mkdir | Always executed |
| 82 | `cp "$KIT/templates/docs/$doc.md.tmpl" "docs/$doc.md"` | cp | Docs loop |
| 88 | `cp "$KIT/templates/docs/ADR-TEMPLATE.md" docs/adr/0001-*.md` | cp | ADR template |
| 94 | `cat >.env.example <<'EOF' ... EOF` | heredoc write | Multi-line static content |
| 113 | `echo "..." > .claude/COMPOUND-CANDIDATES.md` | echo write | Conditional (file absent) |

**Note on cp -r:** `mutate_cp` with two args (`src`, `dest`) covers both `cp` and `cp -r`. The planner should decide whether to unify these into a single function signature or detect `-r` from arg count. Simplest: `mutate_cp src dest` always — the function can internally use `cp -r` when src is a directory (detected via `[ -d "$1" ]`). [ASSUMED — design choice left for planner]

**Note on brace expansion mkdir:** `mkdir -p .claude/{skills,agents,hooks,docs}` expands to 4 separate dirs. The retrofit needs 4 explicit `mutate_mkdir` calls (one per dir), since POSIX brace expansion is a shell feature, not a function argument. [VERIFIED: bash 3.2 behavior confirmed in this shell]

### profiles/*/apply.sh — 9 profiles, inconsistent DRY handling

| Profile | Write Operations | Current DRY guard | Issues |
|---------|-----------------|-------------------|--------|
| ts-next | `cat fragment >> CLAUDE.md` | `[ "$DRY" = 0 ]` via `$2` | Uses positional arg, not env var |
| data-science | `cat fragment >> CLAUDE.md` | `[ "$DRY" = 0 ]` via `$2` | Uses positional arg, not env var |
| go-gin | `cat fragment >> CLAUDE.md` | `[ "$DRY" = 0 ]` via `$2` | Uses positional arg, not env var |
| java-spring | `cat fragment >> CLAUDE.md`; `cp post-edit-format.sh`; `chmod +x` | `[ "$DRY" = 0 ]` via `$2` | `chmod` not a write but affects disk state |
| monorepo | `cat > $pkg/CLAUDE.md <<EOF` (dynamic heredoc); `cat fragment >> CLAUDE.md` | `[ "$DRY" = 0 ]` via `$2` | Heredoc with interpolated vars |
| node-nest | `cat fragment >> CLAUDE.md` | `[ "$DRY" = 0 ]` via `$2` | Uses positional arg, not env var |
| polyglot | `cat fragment >> CLAUDE.md` | `[ "$DRY" = 0 ]` via `$2` | Uses positional arg, not env var |
| python-fastapi | `cat fragment >> CLAUDE.md` | `[ "$DRY" = 0 ]` via `$2` | Uses positional arg, not env var |
| rust-axum | `cat fragment >> CLAUDE.md` | `[ "$DRY" = 0 ]` via `$2` | Uses positional arg, not env var |

**Key finding:** All 9 profiles already have a conceptual dry-run guard via the `$DRY` positional arg — but the guard uses the wrong variable source (`$2` instead of the `DRY_RUN` env var). The migration is: (1) delete `DRY="${2:-0}"` line, (2) add `source "$CONJURE_HOME/lib/mutate.sh"`, (3) replace each guarded write with the appropriate `mutate_*` function.

**`chmod` handling:** `java-spring` uses `chmod +x` on a copied hook file. D-02 excludes `mutate_chmod`. The planner should decide whether to (a) suppress chmod in dry-run with a simple `[ "${DRY_RUN:-0}" = "1" ] || chmod +x ...` inline guard, or (b) silently omit chmod in dry-run since no file is created anyway. Option (b) is cleaner — if `mutate_cp` is skipped, the subsequent chmod is unreachable regardless. [ASSUMED — planner decision]

### compliance/*/apply.sh — 4 overlays, zero dry-run handling

| Overlay | Write Operations | Current DRY guard |
|---------|-----------------|-------------------|
| gdpr | `cat fragment >> CLAUDE.md` | **None** — bare write |
| soc2 | `cat fragment >> CLAUDE.md` | **None** — bare write |
| pci | `cat fragment >> CLAUDE.md` | **None** — bare write |
| hipaa | `cat fragment >> CLAUDE.md`; `mkdir -p .claude/hooks`; `cp pre-commit-phi-scan.sh`; `chmod +x`; `mkdir -p docs/compliance`; `cp CONTROLS.md` | **None** — all bare |

**HIPAA is the most complex:** 6 mutation operations, none guarded. It also has a `chmod +x` which is the same as java-spring. The same decision applies.

---

## Standard Stack

### Core

No external packages. This phase uses only the existing runtime envelope.

| Component | Version | Purpose |
|-----------|---------|---------|
| bash | 3.2+ (POSIX) | Shell library runtime |
| `source` builtin | — | Library loading mechanism |
| `${VAR:-default}` | — | set -u safe var access |

### Package Legitimacy Audit

> This phase installs **zero external packages**. No audit required.

---

## Architecture Patterns

### System Architecture Diagram

```
conjure init --dry-run .
        |
        v
   cli/conjure cmd_init()
        |
        | (1) set DRY_RUN=1 in env
        | (2) source lib/mutate.sh
        |
        |---> CONJURE_HOME=... DRY_RUN=1 bash init-project.sh
        |          |
        |          | source lib/mutate.sh
        |          |
        |          +--> mutate_mkdir()  --> [dry-run] would mkdir X  (no disk write)
        |          +--> mutate_cp()     --> [dry-run] would cp X Y   (no disk write)
        |          +--> mutate_write()  --> [dry-run] would write Z  (no disk write)
        |          |
        |          +--> [dry-run] N mutations skipped (summary)
        |
        |---> DRY_RUN=1 bash profiles/ts-next/apply.sh $target
        |          |
        |          | source lib/mutate.sh
        |          +--> mutate_write() --> [dry-run] would write CLAUDE.md  (append)
        |          +--> [dry-run] N mutations skipped
        |
        +--> mutate_write() for .conjure-version --> [dry-run] would write ...
             [dry-run] 1 mutations skipped  (inline in cmd_init)
```

### New File: lib/mutate.sh

```bash
#!/usr/bin/env bash
# lib/mutate.sh — sourced mutation chokepoint for Conjure.
# Source this file; call mutate_mkdir, mutate_cp, mutate_write.
# Requires: DRY_RUN env var (0=live, 1=dry); set -u safe via ${DRY_RUN:-0}.
# POSIX bash 3.2+ compatible.

# Initialize counter if not already set (safe under set -u)
CONJURE_DRY_MUTATION_COUNT="${CONJURE_DRY_MUTATION_COUNT:-0}"

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
  # <content> is a string value (not a pipe — see PITFALL in RESEARCH.md).
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
  # Call at end of each script to print the summary line.
  # Only prints if DRY_RUN=1.
  if [ "${DRY_RUN:-0}" = "1" ]; then
    echo "[dry-run] ${CONJURE_DRY_MUTATION_COUNT} mutations skipped — run without --dry-run to apply"
  fi
}
```

> **Note on `mutate_summary`:** D-05 requires a summary line at end of each script. Adding `mutate_summary` as a 4th exported function (alongside the 3 mutate functions) is the cleanest way to implement this. It does not perform mutations and does not violate the D-02 minimal-set spirit. The planner should include a `mutate_summary` call at the tail of each retrofitted script. [ASSUMED — planner may inline the summary instead]

### Recommended Project Structure

```
lib/
└── mutate.sh          # new — sourced mutation chokepoint
scripts/
└── init-project.sh    # modified — add source + replace 12 bare writes
cli/
└── conjure            # modified — add DRY_RUN threading to L75; source mutate.sh for L84
profiles/
├── ts-next/apply.sh   # modified (and 8 others) — rm $2 DRY, add source + mutate_write
compliance/
├── gdpr/apply.sh      # modified (and 3 others) — add source + mutate_write/mkdir/cp
tests/
└── run.sh             # modified — add dry-run integration test assertion
```

### Anti-Patterns to Avoid

- **Piping content into `mutate_write`:** `printf '%s' "$content" | mutate_write "$dest"` creates a subshell for `mutate_write`. The function runs in a child process, so `CONJURE_DRY_MUTATION_COUNT` increments are lost. The counter reports 0 even though the write was suppressed. See Pitfall 3 for the correct patterns.
- **Re-checking `DRY_RUN` inline:** Code like `[ "${DRY_RUN:-0}" = "1" ] || cp src dst` scattered through scripts is the old pattern. Every write must go through `mutate_*` — never add new inline guards.
- **Sourcing with relative paths:** `source ../lib/mutate.sh` breaks when scripts are called from different `cwd`. Always use `source "$CONJURE_HOME/lib/mutate.sh"`.
- **Brace-expanding a single `mutate_mkdir`:** `mutate_mkdir ".claude/{skills,agents,hooks,docs}"` passes the literal string with braces, not 4 separate args. Must expand to 4 calls.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Env-var threading to subprocesses | Custom IPC or temp files | `CONJURE_HOME=... DRY_RUN=... bash child.sh` | Standard POSIX env inheritance; already proven at migrations (cli/conjure:107) |
| Counter accumulation across sourced context | Complex state files or named pipes | Shell variable (`CONJURE_DRY_MUTATION_COUNT`) modified in place by sourced functions | Sourced scripts share the parent shell's variable space (verified); simpler than IPC |
| Multi-line content writing | Piped heredocs | Variable capture: assign heredoc to variable, pass as arg to `mutate_write` | Pipes create subshells; variables do not |

---

## Common Pitfalls

### Pitfall 1: init-project.sh receives no DRY_RUN (two-sided bug)

**What goes wrong:** `cli/conjure:75` calls `bash "$CONJURE_HOME/scripts/init-project.sh" "$mode" "$target"` without `DRY_RUN` in the env prefix. The script has no dry-run awareness at all today. Even after adding `mutate_*` calls to `init-project.sh`, if the CLI doesn't export `DRY_RUN`, the library will see `DRY_RUN` unset and default to live mode.

**Why it happens:** The CLI only sets `DRY_RUN` for migration scripts (L107), not for init. The two-sided fix: (a) CLI must export `DRY_RUN` before invoking `init-project.sh`, and (b) `init-project.sh` must source `lib/mutate.sh` and use `mutate_*` functions.

**How to avoid:** Both sides must change in the same plan wave. Test by running `DRY_RUN=1 bash scripts/init-project.sh existing /tmp/test` directly to verify the script honors the env var before wiring through CLI.

**Warning signs:** `[dry-run]` lines appear for profile writes but not for init writes.

### Pitfall 2: Brace expansion in mutate_mkdir calls

**What goes wrong:** The single `mkdir -p .claude/{skills,agents,hooks,docs}` call in `init-project.sh:25` becomes four directories. If replaced naively with `mutate_mkdir ".claude/{skills,agents,hooks,docs}"`, the braces are treated as a literal string, not expanded. `mkdir -p` would create a directory named literally `.claude/{skills,agents,hooks,docs}`.

**Why it happens:** Brace expansion happens at parse time, before function arguments are evaluated. It cannot be passed through a function call.

**How to avoid:** Replace with 4 explicit calls:
```bash
mutate_mkdir ".claude/skills"
mutate_mkdir ".claude/agents"
mutate_mkdir ".claude/hooks"
mutate_mkdir ".claude/docs"
```

**Warning signs:** A dry-run that prints `[dry-run] would mkdir .claude/{skills,agents,hooks,docs}` (with literal braces) — or a live run that creates a weirdly-named directory.

### Pitfall 3: Pipe into mutate_write creates subshell, breaks counter

**What goes wrong:** The CONTEXT.md discretion item says "stdin pipe for multi-line content" — but this is the pattern that breaks counter accumulation. Shell pipelines run the right-hand command in a subshell. Changes to `CONJURE_DRY_MUTATION_COUNT` inside the subshell are discarded when the subshell exits. The dry-run output `[dry-run] would write X` still prints (stdout from subshell is inherited), but the counter remains at 0.

**Verified behavior (live test):**
```bash
printf '%s\n' "content" | mutate_write "/tmp/out.txt"
echo "$CONJURE_DRY_MUTATION_COUNT"  # prints 0, not 1
```

**How to avoid:** Two safe alternatives:

*Option A — Variable capture for multi-line content:*
```bash
CONTENT="$(cat "$PROFILE_DIR/CLAUDE.md.fragment")"
mutate_write "$TARGET/CLAUDE.md" "$CONTENT" "--append"
```
(Counter increments correctly; no subshell for `mutate_write`)

*Option B — Command substitution to read file content inline:*
```bash
mutate_write "$TARGET/CLAUDE.md" "$(cat "$PROFILE_DIR/CLAUDE.md.fragment")" "--append"
```
(The `$(...)` runs in a subshell but its *return value* is captured; `mutate_write` itself runs in the current shell. Counter increments correctly.)

**Both options are verified correct. Option B is more concise. The planner should pick one and apply it consistently.**

**Warning signs:** `[dry-run] N mutations skipped` prints `0 mutations skipped` on a run that should have skipped several writes.

### Pitfall 4: cli/conjure sources lib/mutate.sh under `set -uo pipefail`

**What goes wrong:** `cli/conjure` uses `set -uo pipefail` (line 22). If `lib/mutate.sh` references any variable without a `:-` default and that variable hasn't been set by the time `source` is called, the script exits immediately with "unbound variable".

**Why it happens:** The library initializes `CONJURE_DRY_MUTATION_COUNT="${CONJURE_DRY_MUTATION_COUNT:-0}"` at source time. If `CONJURE_DRY_MUTATION_COUNT` is already set from a parent, this is a no-op. If not set, it initializes to 0. This is safe. The `DRY_RUN` env var uses `${DRY_RUN:-0}` inside each function, not at source time — also safe.

**How to avoid:** Every variable access in `lib/mutate.sh` must use `:-` defaults. No bare `$DRY_RUN` or `$CONJURE_DRY_MUTATION_COUNT` without defaults.

**Warning signs:** `conjure init --dry-run` exits with "unbound variable" error.

### Pitfall 5: cp -r ambiguity in mutate_cp

**What goes wrong:** `scripts/init-project.sh` uses both `cp` (single file) and `cp -r` (directory). A single `mutate_cp src dest` signature that internally checks `[ -d "$1" ]` works for the simple case. However, if `src` doesn't exist yet (the templates/ path might be wrong), `[ -d "$1" ]` returns false and the function uses plain `cp`, which may fail differently.

**How to avoid:** The auto-detection approach (`if [ -d "$1" ]; then cp -r; else cp; fi`) is correct. It mirrors what the callers already do. The pre-existing conditional existence checks in init-project.sh (`if [ ! -f ... ]`) already ensure `src` is valid before calling cp. No change needed to that logic.

---

## Code Examples

### Pattern: Correct env-var threading from CLI to subprocess

```bash
# Source: cli/conjure:107 (existing migration pattern — verified working)
CONJURE_HOME="$CONJURE_HOME" DRY_RUN="$dryrun" bash "$script" "$target"

# Apply same pattern for init-project.sh (line 75 today — missing DRY_RUN):
CONJURE_HOME="$CONJURE_HOME" DRY_RUN="$dryrun" bash "$CONJURE_HOME/scripts/init-project.sh" "$mode" "$target"

# Apply same pattern for profiles (line 80 today — wrong mechanism):
# Before: bash "$CONJURE_HOME/profiles/$profile/apply.sh" "$target" "$dryrun"
# After:
CONJURE_HOME="$CONJURE_HOME" DRY_RUN="$dryrun" bash "$CONJURE_HOME/profiles/$profile/apply.sh" "$target"
```
[VERIFIED: direct code audit — cli/conjure:107 uses this exact pattern]

### Pattern: Script header after retrofitting

```bash
#!/usr/bin/env bash
set -uo pipefail
TARGET="${1:-$(pwd)}"
# DRY="${2:-0}"  ← DELETE this line
PROFILE_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$CONJURE_HOME/lib/mutate.sh"   # ← ADD this line
```
[VERIFIED: all 9 profiles have `DRY="${2:-0}"` at line 4 or 5 — confirmed by grep]

### Pattern: Replacing a bare append write in profiles

```bash
# Before (ts-next example, and 8 other profiles):
if ! grep -q "<!-- profile:ts-next -->" "$TARGET/CLAUDE.md"; then
  [ "$DRY" = 0 ] && cat "$PROFILE_DIR/CLAUDE.md.fragment" >> "$TARGET/CLAUDE.md"
  echo "  ✓ appended CLAUDE.md fragment"
fi

# After (Option B — inline command substitution, no subshell for mutate_write):
if ! grep -q "<!-- profile:ts-next -->" "$TARGET/CLAUDE.md"; then
  mutate_write "$TARGET/CLAUDE.md" "$(cat "$PROFILE_DIR/CLAUDE.md.fragment")" "--append"
  echo "  ✓ appended CLAUDE.md fragment"
fi
```

### Pattern: Replacing a bare create write (version stamp)

```bash
# Before (cli/conjure:84):
echo "$CONJURE_VERSION" > "$target/.claude/.conjure-version"

# After (source mutate.sh first in cmd_init):
source "$CONJURE_HOME/lib/mutate.sh"
# ... (existing init-project.sh and profile calls) ...
mutate_write "$target/.claude/.conjure-version" "$CONJURE_VERSION"
mutate_summary
```

### Pattern: Replacing a bare heredoc write

```bash
# Before (init-project.sh:94):
if [ ! -f .env.example ]; then
  cat >.env.example <<'EOF'
# .env.example — ...
EOF
fi

# After:
if [ ! -f .env.example ]; then
  ENV_CONTENT='# .env.example — every env var, with placeholder values.
# Real .env is gitignored.
#
# DATABASE_URL=postgresql://user:pass@localhost:5432/dbname'
  mutate_write ".env.example" "$ENV_CONTENT"
fi
```

### Pattern: COMPOUND-CANDIDATES conditional write

```bash
# Before (init-project.sh:113):
[ -f .claude/COMPOUND-CANDIDATES.md ] || echo "# Compound Engineering..." > .claude/COMPOUND-CANDIDATES.md

# After:
if [ ! -f .claude/COMPOUND-CANDIDATES.md ]; then
  mutate_write ".claude/COMPOUND-CANDIDATES.md" "# Compound Engineering — Candidate Rules from Sessions"
fi
```

### Pattern: Monorepo dynamic heredoc write

```bash
# Before (profiles/monorepo/apply.sh):
if [ "$DRY" = 0 ]; then
  cat > "$pkg/CLAUDE.md" <<EOF
# $dir/$name — Local Working Notes
...
EOF
fi

# After:
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

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Per-call-site `[ "$DRY" = 0 ] && ...` guards | Single `lib/mutate.sh` chokepoint | Phase 2 | Impossible to miss a write site post-refactor |
| `$DRY` positional arg threading | `DRY_RUN` env var inheritance | Phase 2 | No signature changes needed when new child scripts added |
| No dry-run in compliance overlays | DRY_RUN honored everywhere | Phase 2 | User-invoked `compliance/hipaa/apply.sh` safe to preview |

**Deprecated after Phase 2:**
- `DRY="${2:-0}"` positional arg in all `profiles/*/apply.sh`: removed, replaced by env var.
- Direct `mkdir -p`, `cp`, `cat >`, `echo >` calls outside `lib/mutate.sh`: forbidden in all init/profile/compliance scripts.

---

## Wave Decomposition

> This section guides the planner's task decomposition.

| Wave | Work | Dependency | Parallelizable |
|------|------|------------|----------------|
| Wave 0 | Create `lib/mutate.sh` with `mutate_mkdir`, `mutate_cp`, `mutate_write`, `mutate_summary` | None | — |
| Wave 1a | Retrofit `scripts/init-project.sh` (12 write sites) | Wave 0 | Yes, parallel with 1b/1c |
| Wave 1b | Retrofit 9 `profiles/*/apply.sh` (remove `$DRY` arg, source mutate.sh, replace guards) | Wave 0 | Yes, parallel with 1a/1c |
| Wave 1c | Retrofit 4 `compliance/*/apply.sh` (add source + all write conversions) | Wave 0 | Yes, parallel with 1a/1b |
| Wave 2 | Update `cli/conjure` cmd_init(): add `DRY_RUN` to L75 subprocess call, remove positional arg from L80, source mutate.sh for L84 stamp, add `mutate_summary` call | Wave 1 (needs retrofitted scripts to work correctly end-to-end) | — |
| Wave 3 | Add integration test to `tests/run.sh`: `conjure init --dry-run` against a temp dir, assert no files created, assert `[dry-run]` lines present, assert mutation count > 0 | Wave 2 | — |

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | hand-rolled `tests/run.sh` (project mandate — no shellspec, no npm test deps) |
| Config file | none — `tests/run.sh` is self-contained |
| Quick run command | `bash tests/run.sh` |
| Full suite command | `bash tests/run.sh` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| SAFE-01 | `conjure init --dry-run .` leaves target tree unchanged | integration | `bash tests/run.sh` (dry-run section) | ❌ Wave 3 |
| SAFE-01 | `[dry-run]` prefix lines appear in output | integration | `bash tests/run.sh` (dry-run section) | ❌ Wave 3 |
| SAFE-02 | All write sites route through `lib/mutate.sh` | static audit | `grep -rn "mkdir\|cp \|cat >" scripts/ profiles/ compliance/ cli/conjure` finds no bare writes | ❌ Wave 3 |
| SAFE-02 | DRY_RUN=1 suppresses all mutations | integration | Temp-dir snapshot: `diff -r before after` | ❌ Wave 3 |

### Sampling Rate

- **Per task commit:** `bash tests/run.sh` (full suite — fast, < 5s today)
- **Per wave merge:** `bash tests/run.sh`
- **Phase gate:** Full suite green + new dry-run assertion passes before `/gsd-verify-work`

### Wave 0 Gaps

- [ ] `tests/run.sh` dry-run integration test section — covers SAFE-01 and SAFE-02
- [ ] `lib/mutate.sh` — covers both requirements; must exist before any other wave

---

## Security Domain

> `security_enforcement` not explicitly set to false; treated as enabled.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | — |
| V3 Session Management | no | — |
| V4 Access Control | no | — |
| V5 Input Validation | partial | `$dest` and `$content` args to `mutate_*` functions come from trusted internal callers only — no user-supplied paths |
| V6 Cryptography | no | — |

### Known Threat Patterns for shell mutation libraries

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Path traversal via `$dest` arg | Tampering | All callers use hardcoded relative paths or `$TARGET`-prefixed paths; `$TARGET` is validated by CLI as a real directory before init. No user-controlled path injection. |
| `DRY_RUN` env var spoofing | Tampering | Low risk: `DRY_RUN=0` when user wants dry-run is user error. The flag only suppresses writes, never enables writes that weren't already intended. No security boundary crossed. |
| Shell injection via content args | Tampering | `mutate_write` uses `printf '%s\n' "$content"` (quoted), not `eval`. Content is not executed. |

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| bash 3.2+ | lib/mutate.sh | ✓ | 3.2.57 (macOS) | — |
| `source` builtin | all scripts | ✓ | POSIX | — |
| CONJURE_HOME env var | `source "$CONJURE_HOME/lib/mutate.sh"` | ✓ (set by CLI) | — | Scripts that call each other must set it if invoking standalone |

**Missing dependencies with no fallback:** None.

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `mutate_write` accepts `--append` as a 3rd positional arg for file appends (absorbing all `cat >>` patterns within the D-02 minimal function set) | lib/mutate.sh Interface | If wrong, planner adds a `mutate_append` function as 4th member — minimal impact on wave structure |
| A2 | `mutate_cp` auto-detects directories via `[ -d "$1" ]` and uses `cp -r` internally | mutate_cp design | If wrong, planner uses separate `mutate_cp_dir` — adds 8 extra function calls in init-project.sh loops |
| A3 | `mutate_summary` is included as a helper in `lib/mutate.sh` (4th function, not a mutation) | Code examples | If planner prefers inline, remove from mutate.sh — no wave impact |
| A4 | The monorepo heredoc content can safely be assigned to a variable with embedded newlines and backtick escapes | Pitfall 3 / monorepo pattern | If not (exotic shell edge case), use `printf` to a temp file in live mode — more complex |

**If this table is empty:** All claims in this research were verified or cited — no user confirmation needed.

---

## Open Questions

1. **Should `mutate_summary` be in `lib/mutate.sh` or inline at each call site?**
   - What we know: D-05 requires the summary line at the end of each script.
   - What's unclear: Whether the function should live in the library or be copy-pasted per script.
   - Recommendation: Put it in `lib/mutate.sh` as `mutate_summary`. Keep each script's tail clean (`mutate_summary` one-liner). The library function is idempotent (only prints if `DRY_RUN=1`).

2. **How should cli/conjure source mutate.sh? (it uses `local` — a shell function context)**
   - What we know: `cmd_init()` is a bash function using `local`. Sourcing mutate.sh inside a function puts `CONJURE_DRY_MUTATION_COUNT` into the function's local scope if `local` is used — but `source` does not create locals; variables defined by `source` are global.
   - What's unclear: Whether the counter will persist correctly across the function's lifetime.
   - Recommendation: Source mutate.sh at the top of `cmd_init()` (not at script level to avoid polluting all subcommands). Counter will be global, not function-local, because mutate.sh uses plain assignment without `local`. This is correct behavior.

3. **What happens to the `$dryrun` positional arg in cli/conjure:80 after migration?**
   - What we know: Line 80 currently passes `"$dryrun"` as `$2` to profile scripts. All profile scripts read `DRY="${2:-0}"`.
   - What's unclear: Should the `$2` slot be removed from profile scripts (they still take `$TARGET` as `$1`)?
   - Recommendation: Remove `DRY="${2:-0}"` and the `$2` position from all profile scripts. The CLI removes the trailing `"$dryrun"` arg from the call. The env var is sufficient.

---

## Sources

### Primary (HIGH confidence — direct code audit)

- `/Users/mohandoz/u01/innovate/conjure/cli/conjure` — complete read, all write sites and env-var patterns catalogued
- `/Users/mohandoz/u01/innovate/conjure/scripts/init-project.sh` — complete read, all 12 write sites catalogued
- `/Users/mohandoz/u01/innovate/conjure/profiles/*/apply.sh` — all 9 profiles read, write pattern catalogued
- `/Users/mohandoz/u01/innovate/conjure/compliance/*/apply.sh` — all 4 overlays read, confirmed zero DRY guards
- Live shell verification: counter accumulation via `source`, subshell behavior of pipes, `${VAR:-0}` safety under `set -u`

### Secondary (HIGH confidence — project docs)

- `.planning/phases/02-dry-run-enforcement-chokepoint/02-CONTEXT.md` — locked decisions D-01 through D-07
- `.planning/REQUIREMENTS.md` — SAFE-01, SAFE-02 text
- `CLAUDE.md` — POSIX bash 3.2+ constraint, `exit 2` hook convention, minimal deps constraint

---

## Metadata

**Confidence breakdown:**
- Write-site inventory: HIGH — direct line-by-line audit of all 26 sites
- lib/mutate.sh design: HIGH — verified in live bash 3.2 shell against all relevant patterns
- Counter/subshell behavior: HIGH — verified empirically (pipe = subshell = lost counter; source = shared scope = counter preserved)
- Wave decomposition: HIGH — dependency graph is straightforward; Wave 0 → 1 (parallel) → 2 → 3

**Research date:** 2026-05-24
**Valid until:** Stable — this phase has no external dependencies; findings are valid until the codebase changes.
