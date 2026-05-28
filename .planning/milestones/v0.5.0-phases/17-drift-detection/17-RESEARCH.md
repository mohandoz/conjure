# Phase 17: Drift Detection — Research

**Researched:** 2026-05-26
**Domain:** POSIX bash CLI command; sha256 filesystem diff; kit manifest enumeration
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **Drift categories**: `added` (in harness, not in kit), `modified` (in both, content differs), `removed` (in kit, not in harness)
- **Algorithm**: sha256 of each file; no git involvement — pure filesystem diff
- **Upstream snapshot source**: kit files bundled in `$CONJURE_HOME` (not a separate snapshot store)
- **Comparison target**: harness root directory (CWD or passed as arg)
- **Exit codes**: 0 = current, 1 = drift detected
- **Porcelain format**: `<A|M|R> <path>`, one line per file, no color, no headers
- **Human output**: grouped by category with counts; note about user customizations
- **Implementation**: `cmd_check` in `cli/conjure` + `scripts/check.sh` worker; read-only (no mutations)
- **Kit snapshot discovery**: files `cmd_init` writes — determined from `scripts/init-project.sh`
- **Cross-platform sha256**: `sha256sum` (Linux/macOS) or `shasum -a 256` (macOS fallback)
- **No git operations**: pure filesystem comparison
- **v0.5.0 limitation**: modified files may include user customizations (no 3-way false-positive suppression)

### Claude's Discretion

- Exact internal variable names and script organization within `scripts/check.sh`
- Test case construction within `tests/run.sh`
- Whether "added" detection scans `.claude/skills/`, `.claude/agents/`, `.claude/hooks/` only, or broader `.claude/`

### Deferred Ideas (OUT OF SCOPE)

- 3-way merge / base snapshot storage (v0.5.x)
- `conjure check --json` structured output (v0.5.x)
- Interactive resolution (Phase 18)
- Auto-PR (Phase 19)
- False-positive suppression for user-only edits (v0.5.x)
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| DRIFT-01 | User can run `conjure check` to compare installed harness against upstream kit snapshot and see a file-level delta report (added / modified / removed files) | Manifest enumeration algorithm verified; sha256 comparison prototyped and tested against python-fastapi fixture |
| DRIFT-02 | `conjure check` exits 0 when harness is current, exits 1 when drift detected; supports `--porcelain` flag for machine-readable output in CI pipelines | Exit code logic verified; porcelain format defined; test cases designed |
</phase_requirements>

---

## Summary

Phase 17 implements `conjure check`, a read-only CLI command that compares an installed harness against the upstream kit bundled in `$CONJURE_HOME`. The algorithm is a pure filesystem sha256 diff — no git, no network, no mutations. Three classifications are produced: `modified` (file in both but sha differs), `removed` (in kit manifest, absent in harness), and `added` (in harness but not in kit manifest).

The full kit manifest is derived by enumerating what `scripts/init-project.sh` installs: 3 root dotfiles, `settings.json`, 6 hooks (`.mjs`), 19 skill `SKILL.md` files, and 6 agent `.md` files — 35 entries total. [VERIFIED: codebase inspection of `scripts/init-project.sh` and `templates/`] The manifest excludes synthesized content (`COMPOUND-CANDIDATES.md`, `.conjure-version`, `docs/*.md`) because those have no static kit template counterpart to compare against.

The algorithm was prototyped against the `tests/fixtures/python-fastapi` fixture and correctly identified 2 genuine drifts: `settings.json` (telemetry hooks added to template after fixture creation) and `.claude/hooks/skill-telemetry.mjs` (new hook absent from fixture). [VERIFIED: prototype run in this session] This confirms the algorithm is sound for the existing codebase and that existing fixtures can serve as drift-detection test inputs.

**Primary recommendation:** Implement `scripts/check.sh` using temp-file manifest (bash 3.2 compatible — no associative arrays), the cross-platform `sha256_file()` helper from CONTEXT.md, and the `cmd_check` dispatch pattern from `cli/conjure`. Tests in `tests/run.sh` after BREW section, following the sandbox_setup + CLI invocation pattern.

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Kit manifest enumeration | CLI command / worker script | — | Static filesystem enumeration; no external service |
| sha256 comparison | Worker script (`scripts/check.sh`) | — | Pure bash computation; uses system sha256 tool |
| Exit code signaling | CLI command (`cli/conjure cmd_check`) | — | Caller convention (0=current, 1=drift); exits at CLI layer |
| Human-readable output | Worker script | CLI command | Worker prints; CLI orchestrates |
| Porcelain output | Worker script | — | Flag controls format; one path through the worker |
| Test regression coverage | `tests/run.sh` | — | Follows existing test runner pattern |

---

## Standard Stack

No external packages. This phase uses only:

| Tool | Source | Purpose | Notes |
|------|--------|---------|-------|
| `sha256sum` | System (Linux, macOS `/sbin/`) | File content hashing | `[VERIFIED: confirmed present via \`command -v sha256sum\`]` |
| `shasum -a 256` | System (macOS `/usr/bin/shasum`) | File content hashing fallback | `[VERIFIED: confirmed present, version 6.02]` |
| `awk` | POSIX stdlib | Extract hash from sha256 output | Standard; no install needed |
| `find` | POSIX stdlib | Enumerate harness files for "added" detection | Standard |
| `grep -qF` | POSIX stdlib | O(n) manifest membership check (bash 3.2 safe) | Replaces associative array lookup |
| `mktemp` | POSIX stdlib | Temp file for manifest | Standard |

**Package Legitimacy Audit:** Not applicable — zero new package installs. [VERIFIED: codebase `dependencies: {}` stays empty per CLAUDE.md]

---

## Architecture Patterns

### System Architecture Diagram

```
conjure check [--porcelain] [target]
       |
       v
cli/conjure  cmd_check()
       |
       +-- sets CONJURE_HOME, target, porcelain flag
       |
       v
scripts/check.sh  (sourced or bash-invoked with env vars)
       |
       +-- build_manifest()  -> writes to $MANIFEST_TMPFILE
       |     templates/.editorconfig     -> .editorconfig
       |     templates/.gitattributes    -> .gitattributes
       |     templates/.claudeignore     -> .claudeignore
       |     templates/settings.json.tmpl -> .claude/settings.json
       |     templates/hooks-nodejs/*.mjs -> .claude/hooks/*.mjs
       |     templates/skills/*/SKILL.md  -> .claude/skills/*/SKILL.md
       |     templates/agents/*.md        -> .claude/agents/*.md
       |
       +-- classify_kit_files()  (iterate manifest)
       |     sha256_file($kit_file) == sha256_file($harness_file) ?
       |       missing harness file -> R (removed)
       |       sha differs          -> M (modified)
       |       sha matches          -> (current, silent)
       |
       +-- find_added_files()  (scan harness, cross-ref manifest)
       |     find $harness/.claude -type f
       |     skip .conjure-* internal state files
       |     skip COMPOUND-CANDIDATES.md
       |     skip .claude/docs/
       |     grep -qF $rel $MANIFEST_TMPFILE -> not found = A (added)
       |
       +-- print_report()
             if PORCELAIN: "A .claude/foo.md", "M .claude/bar.md", "R .claude/baz.md"
             if human: grouped sections with counts + limitation note
             if no drift: "Harness is current." (exit 0)
             if drift: exit 1
```

### Recommended Project Structure

```
cli/
  conjure              # add cmd_check() + dispatch entry
scripts/
  check.sh             # new worker script
tests/
  run.sh               # add DRIFT-01/DRIFT-02 section near end (before summary)
```

### Pattern 1: cmd_check dispatch in cli/conjure

**What:** Add `cmd_check` function following the exact same structure as `cmd_update` and `cmd_audit`.
**When to use:** Always — this is the required pattern. [VERIFIED: codebase pattern in `cli/conjure`]

```bash
# Source: cli/conjure (cmd_update pattern)
cmd_check() {
  local porcelain=0 target="$(pwd)"
  while [ $# -gt 0 ]; do
    case "$1" in
      --porcelain)  porcelain=1 ;;
      --help|-h)    echo "Usage: conjure check [--porcelain] [target]"; return 0 ;;
      *)            target="$1" ;;
    esac
    shift
  done
  CONJURE_HOME="$CONJURE_HOME" CONJURE_PORCELAIN="$porcelain" \
    bash "$CONJURE_HOME/scripts/check.sh" "$target"
}
```

Dispatch entry:
```bash
# Source: cli/conjure case block
check) shift; cmd_check "$@" ;;
```

Usage line:
```
conjure check [--porcelain] [target]
```

### Pattern 2: Cross-platform sha256 (from CONTEXT.md)

**What:** Abstraction over `sha256sum` (Linux) and `shasum -a 256` (macOS).
**When to use:** Every file hash comparison in `scripts/check.sh`.
**Verified:** Both tools confirmed available on macOS (`sha256sum` at `/sbin/sha256sum`, `shasum` at `/usr/bin/shasum`). Both produce identical output. [VERIFIED: prototype run in this session]

```bash
# Source: 17-CONTEXT.md (cross-platform sha256)
sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}
```

### Pattern 3: Manifest as temp file (bash 3.2 compatible)

**What:** Build kit manifest into a temp file; use `grep -qF` for membership tests. Avoids associative arrays (`declare -A`) which require bash 4+.
**When to use:** Manifest build step and "added" detection in `scripts/check.sh`. [VERIFIED: lib/merge.sh comment: "POSIX bash 3.2+. No associative arrays, no mapfile, no local -n."]

```bash
# Build manifest (relative harness paths)
MANIFEST_TMPFILE="$(mktemp)"
# Root dotfiles
printf '%s\n' ".editorconfig" ".gitattributes" ".claudeignore" >> "$MANIFEST_TMPFILE"
# settings.json
printf '%s\n' ".claude/settings.json" >> "$MANIFEST_TMPFILE"
# Hooks (.mjs only, skip README.md)
for hook in "$CONJURE_HOME"/templates/hooks-nodejs/*.mjs; do
  printf '%s\n' ".claude/hooks/$(basename "$hook")" >> "$MANIFEST_TMPFILE"
done
# Skills
for skill_dir in "$CONJURE_HOME"/templates/skills/*/; do
  printf '%s\n' ".claude/skills/$(basename "$skill_dir")/SKILL.md" >> "$MANIFEST_TMPFILE"
done
# Agents
for agent in "$CONJURE_HOME"/templates/agents/*.md; do
  printf '%s\n' ".claude/agents/$(basename "$agent")" >> "$MANIFEST_TMPFILE"
done
```

### Pattern 4: Kit-to-harness path mapping

The kit-to-harness path mapping is non-uniform — `settings.json.tmpl` maps to `.claude/settings.json` (strips `.tmpl`), while hooks map directly by filename. [VERIFIED: analysis of `scripts/init-project.sh`]

| Kit source (relative to CONJURE_HOME) | Harness target (relative to harness root) |
|---------------------------------------|-------------------------------------------|
| `templates/.editorconfig` | `.editorconfig` |
| `templates/.gitattributes` | `.gitattributes` |
| `templates/.claudeignore` | `.claudeignore` |
| `templates/settings.json.tmpl` | `.claude/settings.json` |
| `templates/hooks-nodejs/<name>.mjs` | `.claude/hooks/<name>.mjs` |
| `templates/skills/<name>/SKILL.md` | `.claude/skills/<name>/SKILL.md` |
| `templates/agents/<name>.md` | `.claude/agents/<name>.md` |

**Excluded from check scope** (no static template counterpart):
- `CLAUDE.md` (user-written; no template content to compare)
- `.claude/.conjure-version` (version pin, internal state)
- `.claude/COMPOUND-CANDIDATES.md` (synthesized empty content)
- `.claude/docs/` (templates use `.tmpl` suffix; installed files are user-written)
- `docs/` directory (user-written from templates; not stable kit content)
- `.env.example` (content written inline in `init-project.sh`, no file template)

### Pattern 5: Test structure in tests/run.sh

**What:** New DRIFT section appended between BREW section and summary. Follows the `mktemp -d` + CLI invocation + `pass/fail` pattern.
**When to use:** All DRIFT-01 and DRIFT-02 regression tests. [VERIFIED: codebase pattern in `tests/run.sh`]

```bash
echo
echo "▸ Drift detection tests (DRIFT-01, DRIFT-02)"

# DRIFT-01a: fresh init -> no drift, exit 0
DRIFT_DIR="$(mktemp -d)"
trap 'rm -rf "$DRIFT_DIR"' EXIT
printf '# Test project\n' > "$DRIFT_DIR/CLAUDE.md"
CONJURE_HOME="$CONJURE_HOME" cli/conjure init "$DRIFT_DIR" >/dev/null 2>&1
DRIFT_RC=0
CONJURE_HOME="$CONJURE_HOME" cli/conjure check "$DRIFT_DIR" >/dev/null 2>&1 || DRIFT_RC=$?
if [ "$DRIFT_RC" -eq 0 ]; then
  pass "check exits 0 on fully-current harness (DRIFT-01)"
else
  fail "check exits $DRIFT_RC on fresh init — expected 0 (DRIFT-01)"
fi
rm -rf "$DRIFT_DIR"
trap - EXIT

# DRIFT-01b: modified file -> exit 1, "Modified" in output
# ...
```

### Anti-Patterns to Avoid

- **Associative arrays:** `declare -A` requires bash 4+. Use temp file + `grep -qF` instead. [VERIFIED: lib/merge.sh enforces this constraint]
- **`exit 1` in worker scripts called from CLI:** The worker script returns its exit code to `cmd_check`, which propagates it. Use `return` not `exit` inside functions. For the worker script (not a function), `exit 1` is correct.
- **`git diff` or `diff` for comparison:** The CONTEXT.md decision is sha256, not text diff. Using `diff` would require handling binary files and is slower.
- **Scanning all of harness root for "added":** Only scan `.claude/` subtree. Root-level user files (README, src/, etc.) are not kit files and must never appear as "added".
- **Reporting `.conjure-*` internal files as "added":** These are conjure state files, not user additions. Skip with `case ".claude/.conjure-*") continue ;;`.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| File content hashing | Custom hash function | `sha256sum` / `shasum -a 256` system tools | Already present on every supported platform; battle-tested |
| Manifest membership check | Custom string search | `grep -qF` (exact string, no regex) | Correct, portable, bash 3.2 compatible |
| Temp file cleanup | Manual cleanup logic | `trap 'rm -rf "$TMPFILE"' EXIT` | Handles errors, signals, normal exit |
| Output colorization | ANSI codes | `[ -t 1 ]` tty check, then ANSI only on tty | Prevents color codes in piped output; matches existing codebase style |

**Key insight:** The algorithm is already fully specified in CONTEXT.md. The implementation risk is in bash compatibility (no associative arrays, no `mapfile`) and the path mapping non-uniformity (`settings.json.tmpl` → `settings.json`). Get those two right and the rest is straightforward iteration.

---

## Common Pitfalls

### Pitfall 1: Associative arrays break on bash 3.2
**What goes wrong:** `declare -A manifest` compiles fine on macOS bash 5 (Homebrew) but silently fails or errors on bash 3.2 (macOS system `/bin/bash`) and older Ubuntu.
**Why it happens:** The CLAUDE.md constraint "POSIX bash 3.2+" exists specifically because macOS ships bash 3.2 as default.
**How to avoid:** Use a newline-delimited temp file and `grep -qF` for membership tests. [VERIFIED: lib/merge.sh enforces "No associative arrays, no mapfile, no local -n."]
**Warning signs:** `declare -A` in any new `.sh` file.

### Pitfall 2: settings.json.tmpl suffix not stripped in manifest
**What goes wrong:** Manifest contains `.claude/settings.json.tmpl` but harness has `.claude/settings.json`. The manifest check falsely reports `settings.json.tmpl` as "removed" and `settings.json` as "added".
**Why it happens:** The kit source file is `templates/settings.json.tmpl` but `init-project.sh` installs it as `.claude/settings.json`.
**How to avoid:** Hard-code the `settings.json` mapping separately rather than using the basename directly. The mapping is: kit=`templates/settings.json.tmpl`, harness=`.claude/settings.json`. [VERIFIED: `scripts/init-project.sh` line 43]
**Warning signs:** Output shows `R .claude/settings.json.tmpl` or `A .claude/settings.json`.

### Pitfall 3: hooks README.md included in manifest
**What goes wrong:** `templates/hooks-nodejs/README.md` is included in the hooks glob `*.mjs` replacement — except the glob is `*.mjs`, so this only occurs if someone changes the glob to `*`.
**Why it happens:** `templates/hooks-nodejs/` contains a `README.md` that is NOT installed to `.claude/hooks/`. [VERIFIED: `scripts/init-project.sh` uses `for hook in "$KIT"/templates/hooks-nodejs/*.mjs`]
**How to avoid:** Always glob `*.mjs` specifically, never `*` for the hooks directory.
**Warning signs:** Output shows `R .claude/hooks/README.md`.

### Pitfall 4: SC2155 shellcheck error in sha256_file
**What goes wrong:** `local merged=$(sha256_file "$f")` triggers SC2155 (declare and assign separately). CI runs `shellcheck -S error`.
**Why it happens:** Combining `local` with command substitution masks the exit code. CI excludes SC2155 (`-e SC2155`) so this actually won't be an error — but be aware.
**How to avoid:** Either use two lines (`local h; h="$(sha256_file "$f")"`) or rely on the CI exclusion. The CI explicitly excludes SC2155.
**Warning signs:** shellcheck outputs SC2155 warnings for sha256 calls.

### Pitfall 5: Comparing template content to harness settings.json
**What goes wrong:** `settings.json.tmpl` contains comments and template markers that the installed `settings.json` also contains verbatim (no template processing — `mutate_cp` does a straight copy). So the comparison IS valid.
**Why it happens:** Unlike some template systems, conjure's `mutate_cp` does no substitution. The `.tmpl` extension is just a naming hint. [VERIFIED: `lib/mutate.sh` `mutate_cp` implementation — plain `cp`]
**How to avoid:** No special handling needed. `sha256_file(kit_template) vs sha256_file(harness_file)` works correctly.
**Warning signs:** None — this is expected behavior.

### Pitfall 6: Printing "R" for internal conjure state files
**What goes wrong:** Files like `.claude/.conjure-templates-0.2.1/` snapshots are scanned during "added" detection and false-report as "added" user files.
**Why it happens:** `find .claude -type f` returns all files including conjure-internal state.
**How to avoid:** Skip files matching `.claude/.conjure-*` and `.claude/COMPOUND-CANDIDATES.md` with a `case` pattern before emitting "A" status.
**Warning signs:** Output shows `A .claude/.conjure-templates-0.2.1/hooks/post-edit-format.mjs`.

---

## Code Examples

### Full check.sh script skeleton

```bash
#!/usr/bin/env bash
# scripts/check.sh — compare installed harness against upstream kit snapshot.
# Usage: CONJURE_HOME=<path> CONJURE_PORCELAIN=<0|1> bash check.sh [target]
# Exit: 0 = current, 1 = drift detected.
# Read-only: no mutations, no lib/mutate.sh required.

set -uo pipefail

TARGET="${1:-$(pwd)}"
CONJURE_HOME="${CONJURE_HOME:-$(cd "$(dirname "$0")/.." && pwd)}"
PORCELAIN="${CONJURE_PORCELAIN:-0}"

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

# Build manifest into temp file (relative harness paths)
MANIFEST="$(mktemp)"
trap 'rm -f "$MANIFEST"' EXIT

printf '%s\n' ".editorconfig" ".gitattributes" ".claudeignore" >> "$MANIFEST"
printf '%s\n' ".claude/settings.json" >> "$MANIFEST"
for hook in "$CONJURE_HOME"/templates/hooks-nodejs/*.mjs; do
  printf '%s\n' ".claude/hooks/$(basename "$hook")" >> "$MANIFEST"
done
for skill_dir in "$CONJURE_HOME"/templates/skills/*/; do
  printf '%s\n' ".claude/skills/$(basename "$skill_dir")/SKILL.md" >> "$MANIFEST"
done
for agent in "$CONJURE_HOME"/templates/agents/*.md; do
  printf '%s\n' ".claude/agents/$(basename "$agent")" >> "$MANIFEST"
done

modified="" removed="" added=""

# Classify kit files: modified or removed
while IFS= read -r rel; do
  # Resolve kit source file (handle .tmpl suffix for settings.json)
  case "$rel" in
    .claude/settings.json)
      kit_file="$CONJURE_HOME/templates/settings.json.tmpl" ;;
    .claude/hooks/*)
      kit_file="$CONJURE_HOME/templates/hooks-nodejs/$(basename "$rel")" ;;
    .claude/skills/*/SKILL.md)
      skill_name="${rel#.claude/skills/}"
      skill_name="${skill_name%/SKILL.md}"
      kit_file="$CONJURE_HOME/templates/skills/$skill_name/SKILL.md" ;;
    .claude/agents/*)
      kit_file="$CONJURE_HOME/templates/agents/$(basename "$rel")" ;;
    .editorconfig|.gitattributes|.claudeignore)
      kit_file="$CONJURE_HOME/templates/$rel" ;;
    *) continue ;;
  esac
  harness_file="$TARGET/$rel"
  if [ ! -f "$harness_file" ]; then
    removed="$removed$rel\n"
  else
    kit_hash="$(sha256_file "$kit_file")"
    harness_hash="$(sha256_file "$harness_file")"
    if [ "$kit_hash" != "$harness_hash" ]; then
      modified="$modified$rel\n"
    fi
  fi
done < "$MANIFEST"

# Detect added files: in harness .claude/ but not in kit manifest
while IFS= read -r harness_file; do
  rel="${harness_file#$TARGET/}"
  case "$rel" in
    .claude/.conjure-*) continue ;;
    .claude/COMPOUND-CANDIDATES.md) continue ;;
    .claude/docs/*) continue ;;
  esac
  if ! grep -qF "$rel" "$MANIFEST" 2>/dev/null; then
    added="$added$rel\n"
  fi
done < <(find "$TARGET/.claude" -type f 2>/dev/null | sort)

# Print report
drift=0
if [ -n "$modified" ] || [ -n "$removed" ] || [ -n "$added" ]; then
  drift=1
fi

if [ "$PORCELAIN" = "1" ]; then
  printf '%b' "$modified" | while IFS= read -r f; do [ -n "$f" ] && printf 'M %s\n' "$f"; done
  printf '%b' "$removed"  | while IFS= read -r f; do [ -n "$f" ] && printf 'R %s\n' "$f"; done
  printf '%b' "$added"    | while IFS= read -r f; do [ -n "$f" ] && printf 'A %s\n' "$f"; done
else
  if [ "$drift" -eq 0 ]; then
    echo "Harness is current."
  else
    mod_count=$(printf '%b' "$modified" | grep -c . || true)
    rem_count=$(printf '%b' "$removed"  | grep -c . || true)
    add_count=$(printf '%b' "$added"    | grep -c . || true)
    total=$((mod_count + rem_count + add_count))
    echo "Drift detected: $total file(s) differ from upstream kit"
    echo "Note: modified files may include user customizations"
    echo
    if [ -n "$modified" ]; then
      echo "Modified ($mod_count):"
      printf '%b' "$modified" | while IFS= read -r f; do [ -n "$f" ] && echo "  $f"; done
    fi
    if [ -n "$removed" ]; then
      echo "Removed ($rem_count):"
      printf '%b' "$removed" | while IFS= read -r f; do [ -n "$f" ] && echo "  $f"; done
    fi
    if [ -n "$added" ]; then
      echo "Added ($add_count):"
      printf '%b' "$added" | while IFS= read -r f; do [ -n "$f" ] && echo "  $f"; done
    fi
  fi
fi

exit "$drift"
```

### Test cases for tests/run.sh

```bash
echo
echo "▸ Drift detection tests (DRIFT-01, DRIFT-02)"

# DRIFT-01a: fresh init -> no drift, exit 0
DRIFT_DIR="$(mktemp -d)"
trap 'rm -rf "$DRIFT_DIR"' EXIT
printf '# Test project\n' > "$DRIFT_DIR/CLAUDE.md"
CONJURE_HOME="$CONJURE_HOME" cli/conjure init "$DRIFT_DIR" >/dev/null 2>&1
DRIFT_RC=0
CONJURE_HOME="$CONJURE_HOME" cli/conjure check "$DRIFT_DIR" >/dev/null 2>&1 || DRIFT_RC=$?
if [ "$DRIFT_RC" -eq 0 ]; then
  pass "check exits 0 on fully-current harness (DRIFT-01)"
else
  fail "check exits $DRIFT_RC on fresh init — expected 0 (DRIFT-01)"
fi
rm -rf "$DRIFT_DIR"
trap - EXIT

# DRIFT-01b: modified file -> exit 1, M status in output
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
  fail "check exits $DRIFT_RC on modified file — expected 1 (DRIFT-01)"
fi
if printf '%s\n' "$DRIFT_OUT" | grep -q '^M .claude/settings.json'; then
  pass "--porcelain emits 'M .claude/settings.json' (DRIFT-02)"
else
  fail "--porcelain missing 'M .claude/settings.json' line (DRIFT-02)"
fi
rm -rf "$DRIFT_DIR"
trap - EXIT

# DRIFT-01c: removed file -> exit 1, R status in output
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
  fail "check exits $DRIFT_RC on removed file — expected 1 (DRIFT-01)"
fi
if printf '%s\n' "$DRIFT_OUT" | grep -q '^R .claude/hooks/post-edit-format.mjs'; then
  pass "--porcelain emits 'R .claude/hooks/post-edit-format.mjs' (DRIFT-02)"
else
  fail "--porcelain missing 'R' line for removed hook (DRIFT-02)"
fi
rm -rf "$DRIFT_DIR"
trap - EXIT

# DRIFT-02: --porcelain exit 0 when current
DRIFT_DIR="$(mktemp -d)"
trap 'rm -rf "$DRIFT_DIR"' EXIT
printf '# Test project\n' > "$DRIFT_DIR/CLAUDE.md"
CONJURE_HOME="$CONJURE_HOME" cli/conjure init "$DRIFT_DIR" >/dev/null 2>&1
PORE_RC=0
CONJURE_HOME="$CONJURE_HOME" cli/conjure check --porcelain "$DRIFT_DIR" >/dev/null 2>&1 || PORE_RC=$?
if [ "$PORE_RC" -eq 0 ]; then
  pass "--porcelain exits 0 when harness is current (DRIFT-02)"
else
  fail "--porcelain exits $PORE_RC on current harness — expected 0 (DRIFT-02)"
fi
rm -rf "$DRIFT_DIR"
trap - EXIT
```

---

## Kit Manifest: Complete Enumeration

The following 35 files are the complete kit manifest for Phase 17. [VERIFIED: codebase inspection of `scripts/init-project.sh` + `templates/` directory enumeration]

**Root dotfiles (3):**
- `.editorconfig`
- `.gitattributes`
- `.claudeignore`

**Core config (1):**
- `.claude/settings.json` (kit source: `templates/settings.json.tmpl`)

**Hooks (6 — all `.mjs` files, NOT `README.md`):**
- `.claude/hooks/post-edit-format.mjs`
- `.claude/hooks/pre-bash-block-destructive.mjs`
- `.claude/hooks/pre-commit-quality-gate.mjs`
- `.claude/hooks/session-start-context.mjs`
- `.claude/hooks/skill-telemetry.mjs`
- `.claude/hooks/stop-compound-engineering.mjs`

**Skills (19 — all skill dirs in `templates/skills/`):**
- `.claude/skills/_anatomy/SKILL.md`
- `.claude/skills/api-routes/SKILL.md`
- `.claude/skills/architecture/SKILL.md`
- `.claude/skills/ast-search/SKILL.md`
- `.claude/skills/build-deploy/SKILL.md`
- `.claude/skills/code-graph/SKILL.md`
- `.claude/skills/data-access/SKILL.md`
- `.claude/skills/database-schema/SKILL.md`
- `.claude/skills/debugging/SKILL.md`
- `.claude/skills/docs-lookup/SKILL.md`
- `.claude/skills/domain-model/SKILL.md`
- `.claude/skills/messaging/SKILL.md`
- `.claude/skills/pr-review/SKILL.md`
- `.claude/skills/release/SKILL.md`
- `.claude/skills/repo-pack/SKILL.md`
- `.claude/skills/security-review/SKILL.md`
- `.claude/skills/sql-explorer/SKILL.md`
- `.claude/skills/testing/SKILL.md`
- `.claude/skills/web-research/SKILL.md`

**Agents (6):**
- `.claude/agents/code-explorer.md`
- `.claude/agents/diff-reviewer.md`
- `.claude/agents/doc-writer.md`
- `.claude/agents/migration-writer.md`
- `.claude/agents/security-auditor.md`
- `.claude/agents/test-writer.md`

---

## State of the Art

| Old Approach | Current Approach | Impact |
|--------------|------------------|--------|
| `cmd_update --check` (only compares SKILL.md files, not all kit files) | `cmd_check` (compares full kit manifest: dotfiles, hooks, agents, settings) | More complete drift detection |
| No exit code for drift | Exit 1 on drift, exit 0 when current | CI/automation can consume result |
| Text output only | `--porcelain` flag for machine-readable output | AUTPR-01 (Phase 19) can consume `--porcelain` |

**Deprecated/outdated:**
- The `cmd_update --check` flag only inspected SKILL.md files (not agents, hooks, dotfiles). `conjure check` supersedes this for health reporting while `--check` remains for the update workflow.

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `.env.example` content is synthesized inline (not a file template), so comparing it is not meaningful | Kit Manifest / Excluded files | Low — even if we included it, it would appear as "modified" since users always customize it |
| A2 | `docs/` directory files (ARCHITECTURE.md, etc.) are excluded from check scope | Kit Manifest / Excluded files | Low — docs are user-written; comparing against the `.tmpl` source would produce false positives on every project |
| A3 | `CLAUDE.md` is excluded from check scope | Kit Manifest / Excluded files | Medium — CLAUDE.md has a template (`CLAUDE.md.tmpl`) but it is user-written content, so comparison would always show "modified" |

---

## Open Questions (RESOLVED)

1. **Should `CLAUDE.md` be in scope?**
   - What we know: `templates/CLAUDE.md.tmpl` exists but its content is meant to be fully replaced by user content
   - What's unclear: Would comparing it produce useful signal or constant noise?
   - RESOLVED: Exclude from Phase 17 (follows CONTEXT.md which doesn't mention it in kit manifest); revisit if users request it

2. **Should `docs/*.md` files be in scope?**
   - What we know: Installed from `.md.tmpl` sources via straight copy; users are expected to modify these
   - What's unclear: Whether upstream doc updates are meaningful enough to track
   - RESOLVED: Exclude from Phase 17; keep scope to `.claude/` + root dotfiles

3. **Should `--porcelain` suppress the "R" for intentionally-removed files?**
   - What we know: CONTEXT.md says "removed" means in kit, not in harness; Phase 17 has no mechanism to distinguish intentional removal from accidental deletion
   - What's unclear: Whether CI users will find "R" lines noisy for intentionally-removed files
   - RESOLVED: Implement as specified (always report R); the v0.5.x base-snapshot feature will handle this

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| `sha256sum` | File hashing | Yes | Darwin 1.0 | `shasum -a 256` |
| `shasum -a 256` | File hashing (macOS fallback) | Yes | 6.02 | — |
| `bash` | Script execution | Yes | 3.2+ | — |
| `awk` | Hash extraction | Yes | POSIX | — |
| `find` | Added-file detection | Yes | POSIX | — |
| `grep` | Manifest membership | Yes | POSIX | — |
| `mktemp` | Temp manifest file | Yes | POSIX | — |
| `shellcheck` 0.11.0 | CI linting | Yes | 0.11.0 | Optional — CI fails without it |

**Missing dependencies with no fallback:** None.
**Missing dependencies with fallback:** None — both sha256 tools confirmed present.

---

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Hand-rolled `tests/run.sh` (project standard) |
| Config file | none |
| Quick run command | `bash tests/run.sh` |
| Full suite command | `bash tests/run.sh` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| DRIFT-01 | `conjure check` reports file-level delta (M/R/A categories) | integration | `bash tests/run.sh` (DRIFT section) | No — Wave 0 |
| DRIFT-01 | Exit 0 when no drift | integration | `bash tests/run.sh` | No — Wave 0 |
| DRIFT-01 | Exit 1 when drift detected | integration | `bash tests/run.sh` | No — Wave 0 |
| DRIFT-02 | `--porcelain` emits `M <path>` format | integration | `bash tests/run.sh` | No — Wave 0 |
| DRIFT-02 | `--porcelain` exits 0 when current | integration | `bash tests/run.sh` | No — Wave 0 |

### Sampling Rate
- **Per task commit:** `bash tests/run.sh` (full suite — it runs fast, under 30s)
- **Per wave merge:** `bash tests/run.sh`
- **Phase gate:** Full suite green before `/gsd-verify-work`

### Wave 0 Gaps
- [ ] DRIFT test section in `tests/run.sh` — covers DRIFT-01 and DRIFT-02 (add before summary block)
- [ ] `scripts/check.sh` — the worker script itself
- [ ] `cmd_check` function in `cli/conjure` + dispatch entry + usage line

*(No new test infrastructure needed — existing `tests/run.sh` + `tests/lib/sandbox.sh` covers the pattern)*

---

## Project Constraints (from CLAUDE.md)

| Constraint | Impact on Phase 17 |
|-----------|-------------------|
| POSIX bash + Node.js `.mjs` hooks | `scripts/check.sh` must be bash; no node in check path |
| No heavy runtime deps | Pure bash + system sha256 tools; no npm packages |
| `dependencies: {}` empty | No new packages; algorithm is pure bash stdlib |
| Claude Code ≥2.1.117 | Not applicable (CLI command, not hook) |
| `@imports` forbidden in CLAUDE.md | Not applicable |
| `exit 2` for hook blocks | Not applicable — `conjure check` exits 0/1 (not a hook) |
| hooks `exit 2` never `exit 1` | Worker script is a CLI command, not a hook; exits 0 or 1 are correct |
| shellcheck must pass | `scripts/check.sh` in `scripts/` — CI lints it; avoid SC2044, SC2064, SC2155 patterns |
| backup-before-mutate | Not applicable (read-only command) |
| Size caps (CLAUDE.md ≤100, SKILL.md ≤200) | Not applicable |

---

## Security Domain

`conjure check` is a read-only command operating on local filesystem paths. No authentication, no network calls, no secrets handling. ASVS categories do not apply.

| ASVS Category | Applies | Note |
|---------------|---------|------|
| V2 Authentication | No | Local CLI, no auth |
| V3 Session Management | No | Stateless CLI |
| V4 Access Control | No | Reads user's own files |
| V5 Input Validation | Partial | `$TARGET` path should be validated as an existing directory before `cd` |
| V6 Cryptography | No | sha256 is for content comparison, not security |

**One security note:** The `TARGET` argument should be validated: `[ -d "$TARGET" ] || { echo "✗ target not a directory: $TARGET"; exit 2; }`. This prevents path traversal via symlink tricks and matches the pattern in `audit-setup.sh`.

---

## Sources

### Primary (HIGH confidence)
- `cli/conjure` — cmd_update, cmd_audit patterns; dispatch structure; usage format [VERIFIED: codebase read]
- `scripts/init-project.sh` — authoritative source for kit manifest (what files conjure installs and their harness paths) [VERIFIED: codebase read]
- `lib/mutate.sh` — confirms bash 3.2+ constraint; POSIX-only patterns [VERIFIED: codebase read]
- `lib/merge.sh` — confirms "No associative arrays, no mapfile, no local -n" constraint [VERIFIED: codebase read]
- `tests/run.sh` — test structure, sandbox pattern, pass/fail helpers [VERIFIED: codebase read]
- `.planning/phases/17-drift-detection/17-CONTEXT.md` — locked decisions, algorithm spec, output formats [VERIFIED: codebase read]
- `.github/workflows/ci.yml` — shellcheck flags and excluded codes [VERIFIED: codebase read]
- Prototype run: algorithm tested against `tests/fixtures/python-fastapi` [VERIFIED: prototype run in this session]

### Secondary (MEDIUM confidence)
- `tests/fixtures/python-fastapi/` — fixture structure used to validate manifest completeness [VERIFIED: codebase read]

### Tertiary (LOW confidence)
- None

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — zero new packages; pure POSIX bash tools confirmed present
- Architecture: HIGH — patterns verified from existing codebase; algorithm prototyped and tested
- Pitfalls: HIGH — discovered via prototype execution (associative arrays, settings.json.tmpl mapping)

**Research date:** 2026-05-26
**Valid until:** 2026-07-26 (stable — no external dependencies; only invalidated if init-project.sh changes the file list)
