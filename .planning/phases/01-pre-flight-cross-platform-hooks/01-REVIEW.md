---
phase: 01-pre-flight-cross-platform-hooks
reviewed: 2026-05-24T00:00:00Z
depth: standard
files_reviewed: 6
files_reviewed_list:
  - cli/conjure
  - scripts/audit-setup.sh
  - scripts/init-project.sh
  - scripts/preflight.sh
  - templates/settings.json.tmpl
  - tests/run.sh
findings:
  critical: 4
  warning: 7
  info: 3
  total: 14
status: issues_found
---

# Phase 01: Code Review Report

**Reviewed:** 2026-05-24
**Depth:** standard
**Files Reviewed:** 6
**Status:** issues_found

## Summary

This phase delivers the cross-platform preflight dep-checker, node hook wiring, and associated CLI plumbing. The preflight script itself is solid and cross-platform-correct. The broader CLI and audit infrastructure have four blockers: a broken `--dry-run` contract, a silent `cd` failure that audits the wrong directory, an unreachable dead-code branch that masks missing hooks, and a shell injection vector in `cmd_help`. Seven warnings cover logic gaps, off-by-one errors, dead code, and platform assumptions. Three info items note cosmetic or minor consistency issues.

---

## Critical Issues

### CR-01: `conjure init --dry-run` performs real filesystem mutations

**File:** `cli/conjure:75`
**Issue:** `cmd_init` accepts `--dry-run` and sets `dryrun=1`, but calls `init-project.sh` unconditionally without passing the flag. `init-project.sh` has no dry-run awareness and immediately creates directories, copies files, and writes `.env.example`. The `dryrun` variable is only threaded to `profiles/$profile/apply.sh` (line 80) and the backup guard in `cmd_migrate` (line 104), making `--dry-run` a half-implemented no-op for the primary init path.

**Fix:**
```bash
# cli/conjure cmd_init, around line 75 — guard the real call:
if [ "$dryrun" -eq 0 ]; then
  bash "$CONJURE_HOME/scripts/init-project.sh" "$mode" "$target"
else
  echo "  [dry-run] would run: init-project.sh $mode $target"
fi
```
Alternatively, pass `$dryrun` as a third argument to `init-project.sh` and have it honour `DRY_RUN` throughout.

---

### CR-02: `cd` failure in `audit-setup.sh` silently audits the wrong directory

**File:** `scripts/audit-setup.sh:6,9`
**Issue:** The script uses `set -uo pipefail` (no `-e`). When `$TARGET` does not exist, `cd "$TARGET"` prints an error to stderr and the script continues executing in the original working directory. Every subsequent file check (`CLAUDE.md`, `.claude/`, etc.) then silently evaluates the caller's directory, producing false-positive passes for that directory while claiming to audit `$TARGET`. The user sees `"Auditing .claude/ setup in: $TARGET"` but results reflect a different path.

**Fix:**
```bash
# scripts/audit-setup.sh — replace line 6 with:
set -euo pipefail
```
Or add an explicit guard:
```bash
cd "$TARGET" || { echo "✗ Target directory not found: $TARGET"; exit 2; }
```

---

### CR-03: Shell injection via unsanitised user input in `cmd_help`

**File:** `cli/conjure:177`
**Issue:** `cmd_help` builds a `sed` address from unvalidated user input:
```bash
sed -n "/^cmd_$1()/,/^}/p" "$0" | head -20
```
If `$1` contains sed metacharacters (`/`, `\`, newline via `$'...'`), the pattern is malformed or the address matches unintended ranges. More concretely, `conjure help $'init\n/^}/d'` could inject an additional sed command. This is a local CLI tool, but injection via argument parsing is still a correctness and security defect.

Additionally, hyphenated subcommands (`refresh-graph`, `install-mcp`) produce **no output** because the function names use underscores (`cmd_refresh_graph`), but `$1` is passed verbatim with the hyphen, so the sed pattern never matches.

**Fix:**
```bash
cmd_help() {
  if [ -n "${1:-}" ]; then
    # Normalise hyphen → underscore and reject non-alphanumeric characters
    local safe
    safe="$(printf '%s' "$1" | tr '-' '_' | tr -cd '[:alnum:]_')"
    sed -n "/^cmd_${safe}()/,/^}/p" "$0" | head -20
  else
    usage
  fi
}
```

---

### CR-04: Hook audit dead-code branch — missing hooks go unreported

**File:** `scripts/audit-setup.sh:97-103`
**Issue:** The hook audit loop feeds from `find .claude/hooks -maxdepth 1 -name '*.mjs'`. Because `find` only yields files that already exist, the loop body's `else` branch (`err "Hook MISSING: ..."`) is **unreachable**: `[ -f "$hook" ]` is always true for every path `find` returns. The real failure mode — an empty `.claude/hooks/` directory (no `.mjs` files at all) — causes the loop to never iterate, so zero checks are performed and no error is emitted. A project with no hooks installed silently passes the audit.

**Fix:** Audit against the expected hook list rather than discovered files:
```bash
EXPECTED_HOOKS="post-edit-format.mjs pre-bash-block-destructive.mjs pre-commit-quality-gate.mjs stop-compound-engineering.mjs session-start-context.mjs"
for hook in $EXPECTED_HOOKS; do
  if [ -f ".claude/hooks/$hook" ]; then ok "Hook present: $hook"
  else err "Hook MISSING: $hook — re-run conjure init"
  fi
done
```

---

## Warnings

### WR-01: Word-splitting on `find` output in `cmd_update`

**File:** `cli/conjure:141`
**Issue:** `for f in $(find "$CONJURE_HOME/templates/skills" -name SKILL.md)` is subject to word-splitting: any path containing spaces, tabs, or glob characters causes `$f` to be split across multiple loop iterations, corrupting `$rel` and `$proj` on lines 142-143.

**Fix:**
```bash
while IFS= read -r f; do
  local rel="${f#$CONJURE_HOME/templates/}"
  local proj="$target/.claude/${rel%/SKILL.md}/SKILL.md"
  ...
done < <(find "$CONJURE_HOME/templates/skills" -name SKILL.md)
```

---

### WR-02: Unguarded glob expansion in `init-project.sh` hook copy loop

**File:** `scripts/init-project.sh:46`
**Issue:** When `templates/hooks-nodejs/` contains no `.mjs` files, the glob `"$KIT"/templates/hooks-nodejs/*.mjs` is not expanded (nullglob is off by default in bash). The loop runs once with the literal string `$KIT/templates/hooks-nodejs/*.mjs` as `$hook`. `basename` produces `*.mjs`, `[ ! -f ".claude/hooks/*.mjs" ]` is true, and `cp` attempts to copy a non-existent literal path — failing with an error that exits the script immediately due to `set -euo pipefail`. This would silently prevent hook installation being reported as a skip.

**Fix:**
```bash
# After the for declaration, check whether any files matched:
for hook in "$KIT"/templates/hooks-nodejs/*.mjs; do
  [ -e "$hook" ] || { echo "  ⚠ No .mjs hooks found in templates/hooks-nodejs/"; break; }
  ...
done
```

---

### WR-03: `conjure init migrate` hardcodes `from-claude` as migration source

**File:** `cli/conjure:71`
**Issue:** When `mode=migrate`, `cmd_init` calls `cmd_migrate from-claude "$target" "$dryrun"` with the source hardcoded. There is no way to use `conjure init migrate` to migrate from any other assistant (cursor, aider, etc.). The `conjure migrate <source>` subcommand works correctly, but `conjure init migrate` silently ignores the intent.

**Fix:** Either document that `conjure init migrate` is always from-claude, or parse a source from the argument list:
```bash
# In cmd_init argument parsing:
new|existing|migrate) mode="$1" ;;
from-claude|from-cursor|from-aider|from-continue|from-copilot) migrate_source="$1" ;;
# Then:
cmd_migrate "${migrate_source:-from-claude}" "$target" "$dryrun"
```

---

### WR-04: `stat` arithmetic can crash audit script on file-deletion race

**File:** `scripts/audit-setup.sh:116`
**Issue:**
```bash
AGE_DAYS=$(( ($(date +%s) - $(stat -f %m graphify-out/graph.json 2>/dev/null || stat -c %Y graphify-out/graph.json)) / 86400 ))
```
If `graphify-out/graph.json` is deleted between the `[ -f ... ]` test on line 115 and the `stat` calls on line 116 (TOCTOU), both `stat` commands fail and return empty output. The arithmetic then evaluates as `$(( (ts - ) / 86400 ))`, which is a syntax error and crashes the script under `set -uo pipefail`.

**Fix:**
```bash
if [ -f graphify-out/graph.json ]; then
  mtime="$(stat -f %m graphify-out/graph.json 2>/dev/null || stat -c %Y graphify-out/graph.json 2>/dev/null || echo '')"
  if [ -n "$mtime" ]; then
    AGE_DAYS=$(( ($(date +%s) - mtime) / 86400 ))
    if [ "$AGE_DAYS" -gt 7 ]; then warn "graphify graph is $AGE_DAYS days old"
    else ok "graphify graph: $AGE_DAYS days old"
    fi
  fi
fi
```

---

### WR-05: `from-windsurf` migration tested but absent from CLI help and dispatch

**File:** `tests/run.sh:187` / `cli/conjure:7,34`
**Issue:** `tests/run.sh` tests for `migrations/from-windsurf/migrate.sh`, but the CLI's `--help` output and comment header only list five sources (`from-claude`, `from-cursor`, `from-aider`, `from-continue`, `from-copilot`). If `from-windsurf` is a valid supported migration, the CLI help is wrong; if it is not yet supported, the test should be conditional or removed.

**Fix:** Add `from-windsurf` to the CLI help string at lines 7 and 34, or remove it from the test coverage list until it is officially supported.

---

### WR-06: Description length check off-by-one in `tests/run.sh`

**File:** `tests/run.sh:55`
**Issue:**
```bash
desc_len=$(echo "$desc_line" | sed '...' | wc -c | tr -d ' ')
if [ "$desc_len" -lt 30 ]; then fail ...
```
`wc -c` counts bytes including the newline appended by `echo`. A description of exactly 29 characters reports `desc_len=30` and passes the `< 30` check. Descriptions that are exactly 29 bytes are incorrectly allowed through.

**Fix:** Use `printf` instead of `echo` to avoid the trailing newline, or subtract 1:
```bash
desc_len=$(printf '%s' "$desc_line" | sed '...' | wc -c | tr -d ' ')
```

---

### WR-07: `audit-setup.sh` description regex only matches double-quoted values

**File:** `scripts/audit-setup.sh:62`
**Issue:**
```bash
elif head -10 "$skill" | grep -q '^description: ".\{0,30\}"$'; then
```
This regex matches only descriptions surrounded by double-quotes and ending at end-of-line. Unquoted descriptions (`description: My skill does X`) or descriptions followed by trailing whitespace are silently skipped, even if they are shorter than 30 characters. The `warn` for short descriptions will never fire for unquoted frontmatter values.

**Fix:**
```bash
# Extract raw value and check length regardless of quoting:
desc_val=$(head -10 "$skill" | grep '^description:' | sed 's/^description: *//;s/^"//;s/"$//')
if [ "${#desc_val}" -lt 30 ]; then
  warn "Skill '$name': description very short (${#desc_val} chars)"
fi
```

---

## Info

### IN-01: `TESTS` array and `t()` helper are dead code in `tests/run.sh`

**File:** `tests/run.sh:11,13`
**Issue:** `TESTS=()` and `t() { TESTS+=("$1"); }` are declared and never used. The `t` function is never called anywhere in the file. This is leftover scaffolding.

**Fix:** Remove both lines.

---

### IN-02: `init-project.sh` uses bash-specific `[[ ]]` construct

**File:** `scripts/init-project.sh:14`
**Issue:**
```bash
if [[ "$MODE" != "new" && "$MODE" != "existing" ]]; then
```
The project constraint states "POSIX bash 3.2+", but `[[ ... && ... ]]` is a bashism. All other scripts in the set use POSIX `[ ]` with `-a` or separate tests. This is inconsistent and technically breaks strict POSIX portability.

**Fix:**
```bash
if [ "$MODE" != "new" ] && [ "$MODE" != "existing" ]; then
```

---

### IN-03: `cli/conjure` missing `set -e`; init-project.sh failure not propagated

**File:** `cli/conjure:22,75`
**Issue:** `cli/conjure` uses `set -uo pipefail` without `-e`. The call to `init-project.sh` on line 75 is not checked for failure:
```bash
bash "$CONJURE_HOME/scripts/init-project.sh" "$mode" "$target"
# profile stamp and version write continue even if init-project.sh fails
```
If `init-project.sh` fails partway through (e.g., a `cp` fails), the CLI continues to stamp the version file, leaving the project in a partially initialised state with a valid-looking version pin.

**Fix:**
```bash
bash "$CONJURE_HOME/scripts/init-project.sh" "$mode" "$target" || return 1
```

---

_Reviewed: 2026-05-24_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
