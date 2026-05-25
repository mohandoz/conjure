# Phase 12: Org Overlay - Pattern Map

**Mapped:** 2026-05-26
**Files analyzed:** 6
**Analogs found:** 6 / 6

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---|---|---|---|---|
| `scripts/init-overlay.sh` | worker script | file-I/O + request-response | `scripts/publish-plugin.sh` | role-match |
| `scripts/refresh-overlay.sh` | worker script | file-I/O + request-response | `scripts/publish-skill.sh` | role-match |
| `cli/conjure` | CLI dispatcher | request-response | `cli/conjure` (cmd_refresh_graph + cmd_init) | exact (self-extension) |
| `scripts/audit-setup.sh` | audit reporter | batch + request-response | `scripts/audit-setup.sh` (conflict-marker section) | exact (self-extension) |
| `tests/run.sh` | test suite | batch | `tests/run.sh` (MKTPL/SKILL blocks) | exact (self-extension) |
| `.claude/.conjure-org-overlay` | marker file | — | `.claude/.conjure-version` | role-match |

---

## Pattern Assignments

### `scripts/init-overlay.sh` (worker script, file-I/O)

**Analog:** `scripts/publish-plugin.sh`

**Imports / header pattern** (`scripts/publish-plugin.sh` lines 1-21):
```bash
#!/usr/bin/env bash
# init-overlay.sh — Worker script for conjure init --overlay.
# Clones overlay repo (shallow), copies contents into .claude/, writes marker.
#
# Usage:
#   bash scripts/init-overlay.sh <overlay-url> <target-dir>
#   CONJURE_HOME=... DRY_RUN=1 bash scripts/init-overlay.sh <url> <target>
#
# Exit codes:
#   0 = success
#   1 = validation error (empty URL, clone failure)
#   2 = hard prerequisite failure (git not installed, lib/mutate.sh missing)

set -euo pipefail

CONJURE_HOME="$(cd "$(dirname "$0")/.." && pwd)"
source "$CONJURE_HOME/lib/mutate.sh"

DRY_RUN="${DRY_RUN:-0}"
```

**Arg parsing pattern** (`scripts/publish-plugin.sh` lines 24-42 adapted for positional args):
```bash
# Positional args (not flags — url and target come from cmd_init)
OVERLAY_URL="${1:-}"
TARGET="${2:-$(pwd)}"

[ -z "$OVERLAY_URL" ] && { echo "✗ Usage: init-overlay.sh <overlay-url> <target>" >&2; exit 1; }
```

**Prerequisite check pattern** (`scripts/publish-plugin.sh` lines 44-66):
```bash
if ! command -v git >/dev/null 2>&1; then
  echo "✗ git not installed" >&2
  exit 2
fi

if [ ! -f "$CONJURE_HOME/lib/mutate.sh" ]; then
  echo "✗ lib/mutate.sh not found — check CONJURE_HOME ($CONJURE_HOME)" >&2
  exit 2
fi
```

**Core pattern — clone + copy + marker write** (verified in RESEARCH.md, pattern matches `publish-plugin.sh` SHA-read idiom at lines 71-72):
```bash
CLONE_TMP="$(mktemp -d)"
echo "▸ Cloning overlay: $OVERLAY_URL"
git clone --depth 1 "$OVERLAY_URL" "$CLONE_TMP" 2>/dev/null \
  || { echo "✗ git clone failed for: $OVERLAY_URL"; rm -rf "$CLONE_TMP"; exit 1; }
CLONE_SHA="$(git -C "$CLONE_TMP" rev-parse HEAD)"

# Copy overlay files — process substitution avoids subshell (preserves mutation counter)
while IFS= read -r item; do
  mutate_cp "$item" "$TARGET/.claude/"
done < <(find "$CLONE_TMP" -mindepth 1 -maxdepth 1 ! -name '.git')
rm -rf "$CLONE_TMP"

# Write marker AFTER successful copy (Pitfall 4: never write marker before clone succeeds)
mutate_write "$TARGET/.claude/.conjure-org-overlay" \
  "$(printf 'url=%s\nsha=%s' "$OVERLAY_URL" "$CLONE_SHA")"
```

**mutate_summary call pattern** (`scripts/publish-plugin.sh` lines 149-150):
```bash
mutate_summary
exit 0
```

---

### `scripts/refresh-overlay.sh` (worker script, file-I/O)

**Analog:** `scripts/publish-skill.sh` (for structure) + `cli/conjure` cmd_update (for backup-before-mutate)

**Header + source + env defaults** (`scripts/publish-skill.sh` lines 1-21, same shape):
```bash
#!/usr/bin/env bash
# refresh-overlay.sh — Re-pull org overlay and re-apply to .claude/.
# Reads marker .claude/.conjure-org-overlay, backs up, reclones, re-applies.
#
# Usage:
#   bash scripts/refresh-overlay.sh [target-dir]
#   CONJURE_HOME=... DRY_RUN=1 bash scripts/refresh-overlay.sh [target]
#
# Exit codes:
#   0 = success
#   1 = user-fixable error (no marker configured, clone failure)
#   2 = hard prerequisite failure (git not installed, lib/mutate.sh missing)

set -euo pipefail

CONJURE_HOME="$(cd "$(dirname "$0")/.." && pwd)"
source "$CONJURE_HOME/lib/mutate.sh"

DRY_RUN="${DRY_RUN:-0}"
TARGET="${1:-$(pwd)}"
```

**Marker-not-found guard** (D-04 decision — exit 1, not 2):
```bash
OVERLAY_MARKER="$TARGET/.claude/.conjure-org-overlay"
if [ ! -f "$OVERLAY_MARKER" ]; then
  echo "✗ No org overlay configured. Run conjure init --overlay <git-url> first." >&2
  exit 1
fi

OVERLAY_URL="$(grep '^url=' "$OVERLAY_MARKER" | cut -d= -f2-)"
```

**Backup-before-mutate pattern** (`cli/conjure` lines 210-215, cmd_update --apply):
```bash
if [ -d "$TARGET/.claude" ]; then
  local ts; ts="$(date +%Y%m%d-%H%M%S)"
  local backup="$TARGET/.claude.backup-${ts}"
  echo "▸ Backing up existing .claude/ → $backup"
  cp -R "$TARGET/.claude" "$backup" \
    || { echo "✗ Backup failed — aborting"; exit 1; }
fi
```

Note: `local` is only valid inside functions. In a top-level script use `ts="$(date +%Y%m%d-%H%M%S)"` directly (no `local`).

**Re-clone + re-apply core** (same as init-overlay.sh clone section):
```bash
CLONE_TMP="$(mktemp -d)"
echo "▸ Re-cloning overlay: $OVERLAY_URL"
git clone --depth 1 "$OVERLAY_URL" "$CLONE_TMP" 2>/dev/null \
  || { echo "✗ git clone failed for: $OVERLAY_URL"; rm -rf "$CLONE_TMP"; exit 1; }
NEW_SHA="$(git -C "$CLONE_TMP" rev-parse HEAD)"

while IFS= read -r item; do
  mutate_cp "$item" "$TARGET/.claude/"
done < <(find "$CLONE_TMP" -mindepth 1 -maxdepth 1 ! -name '.git')
rm -rf "$CLONE_TMP"

mutate_write "$TARGET/.claude/.conjure-org-overlay" \
  "$(printf 'url=%s\nsha=%s' "$OVERLAY_URL" "$NEW_SHA")"

mutate_summary
exit 0
```

---

### `cli/conjure` — add `--overlay=*` to `cmd_init` + add `cmd_refresh_overlay` + dispatch entry (CLI dispatcher, request-response)

**Analog:** `cli/conjure` itself — self-extension at three precise locations.

**Location 1 — `cmd_init` arg parser** (`cli/conjure` lines 54-65):
Add `--overlay=*` case alongside the existing `--profile=*` case. Current loop:
```bash
cmd_init() {
  local mode="existing" profile="" dryrun=0 target="$(pwd)"
  while [ $# -gt 0 ]; do
    case "$1" in
      new|existing|migrate) mode="$1" ;;
      --profile=*)          profile="${1#--profile=}" ;;
      --dry-run)            dryrun=1 ;;
      --help|-h)            grep -A3 '^  conjure init' <<<"$(usage)"; return 0 ;;
      *)                    target="$1" ;;
    esac
    shift
  done
```
Add after `--profile=*` line:
```bash
      --overlay=*)          overlay="${1#--overlay=}" ;;
```
Also add `overlay=""` to the `local` declaration on line 55.

**Location 2 — `cmd_init` body: apply overlay after profile** (`cli/conjure` lines 82-109):
Insert after the profile overlay block (after line 86):
```bash
  # Apply org overlay if specified
  if [ -n "$overlay" ]; then
    CONJURE_HOME="$CONJURE_HOME" DRY_RUN="$dryrun" \
      bash "$CONJURE_HOME/scripts/init-overlay.sh" "$overlay" "$target"
  fi
```

**Location 3 — `cmd_refresh_overlay` function** (`cli/conjure` lines 253-255, cmd_refresh_graph pattern):
```bash
cmd_refresh_overlay() {
  bash "$CONJURE_HOME/scripts/refresh-overlay.sh" "$@"
}
```

**Location 4 — dispatch table** (`cli/conjure` lines 310-324):
Add alongside `refresh-graph)` at line 316:
```bash
  refresh-overlay)  shift; cmd_refresh_overlay "$@"  ;;
```

**Location 5 — `usage()` string** (`cli/conjure` lines 27-49):
Add to usage block:
```bash
  conjure refresh-overlay [target]
```
And extend the `init` usage line to show `[--overlay=<git-url>]`.

---

### `scripts/audit-setup.sh` — add overlay section (audit reporter, batch)

**Analog:** `scripts/audit-setup.sh` itself — self-extension after conflict-marker check.

**Existing ok/warn/err helpers** (`scripts/audit-setup.sh` lines 14-17):
```bash
note() { echo "  $1"; }
ok()   { note "✓ $1"; PASS=$((PASS+1)); }
warn() { note "⚠ $1"; WARN=$((WARN+1)); }
err()  { note "✗ $1"; FAIL=$((FAIL+1)); }
```
All new overlay checks use these same four functions. No new helpers.

**Existing structural pattern** (`scripts/audit-setup.sh` lines 132-145, conflict-marker check):
```bash
if [ -d .claude ]; then
  CONFLICT_FILES="$(grep -rl '^<<<<<<<' .claude/ 2>/dev/null \
    | grep -v '\.conjure-conflict-' || true)"
  if [ -n "$CONFLICT_FILES" ]; then
    err "Unresolved merge conflicts found in .claude/ — resolve and delete .conjure-conflict-* sidecars"
    printf '%s\n' "$CONFLICT_FILES" | while IFS= read -r cf; do
      [ -z "$cf" ] && continue
      note "  conflict markers: $cf"
    done
  else
    ok ".claude/: no unresolved conflict markers"
  fi
fi
```

**New overlay section to insert after line 145** (D-05, D-06 decisions):
```bash
# Org overlay presence and drift check (OVLY-04)
OVERLAY_MARKER="$TARGET/.claude/.conjure-org-overlay"
if [ ! -f "$OVERLAY_MARKER" ]; then
  ok "no org overlay configured"
else
  OVERLAY_URL="$(grep '^url=' "$OVERLAY_MARKER" | cut -d= -f2-)"
  PINNED_SHA="$(grep  '^sha=' "$OVERLAY_MARKER" | cut -d= -f2)"
  note "[overlay] url: $OVERLAY_URL"
  note "[overlay] pinned: $PINNED_SHA"
  UPSTREAM_SHA="$(git ls-remote "$OVERLAY_URL" HEAD 2>/dev/null | awk '{print $1}')" || true
  if [ -z "$UPSTREAM_SHA" ]; then
    warn "[overlay] drift check skipped (git ls-remote failed)"
  elif [ "$PINNED_SHA" = "$UPSTREAM_SHA" ]; then
    ok "[overlay] up to date ($PINNED_SHA)"
  else
    warn "[overlay] DRIFT — pinned=$PINNED_SHA upstream=$UPSTREAM_SHA — run: conjure refresh-overlay"
  fi
fi
```

Note: `$TARGET` is already set at the top of `audit-setup.sh` (line 8: `TARGET="${1:-$(pwd)}"`). The overlay section uses it consistently.

---

### `tests/run.sh` — add OVLY-01 through OVLY-05 test blocks (test suite, batch)

**Analog:** `tests/run.sh` MKTPL and SKILL blocks — git sandbox creation at lines 764-775 (MKTPL-SETUP) and 896-910 (SKILL-SETUP).

**Test harness globals** (`tests/run.sh` lines 10-16):
```bash
PASS=0
FAIL=0
pass() { echo "  ✓ $1"; PASS=$((PASS+1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL+1)); }
```

**Section header pattern** (lines 890-891):
```bash
echo
echo "▸ OVLY org-overlay tests (OVLY-01 through OVLY-05)"
```

**OVLY-SETUP: local git repo as mock overlay** (verified pattern from RESEARCH.md; structurally mirrors MKTPL-SETUP at lines 764-775):
```bash
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
```

**OVLY-01 and OVLY-02 test pattern** (mirrors MKTPL-01 at lines 778-791):
```bash
# OVLY-01: conjure init --overlay exits 0 and applies overlay files
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
```

**OVLY-03 test pattern** (no-marker exit-1 check mirrors DIRTY_RC test at lines 795-801):
```bash
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
```

**OVLY-04 drift test pattern** (mirrors MKTPL-02 DRIFT test at lines 834-847):
```bash
# OVLY-04: audit reports up-to-date when SHA matches
# Create a minimal audit-able target (needs CLAUDE.md and .claude/)
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
# Restore correct marker
printf 'url=%s\nsha=%s' "$OVLY_URL" "$OVLY_EXPECTED_SHA" \
  > "$OVLY_TARGET/.claude/.conjure-org-overlay"

# OVLY-04: audit skips drift check on invalid URL (exit 0 invariant)
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
```

**OVLY-05 static grep pattern** (mirrors no-egress static test for publish-skill):
```bash
# OVLY-05: no credential storage in worker scripts (static grep)
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
```

**Cleanup pattern** (mirrors lines 1070-1072):
```bash
# CLEANUP OVLY sandbox
rm -rf "$OVLY_REPO" "$OVLY_TARGET"
```

---

### `.claude/.conjure-org-overlay` (marker file)

**Analog:** `.claude/.conjure-version` (plain-text marker, single line)

The `.conjure-version` marker is a single plain-text string (e.g., `0.2.1`) written with `mutate_write`. The overlay marker extends this to two `key=value` lines — the minimal flat-file extension of the same pattern.

**Format** (flat key=value, no JSON, no `jq` dependency):
```
url=https://github.com/myorg/overlay.git
sha=f9655c8c597d4110129ff8727ab659dd83695bbc
```

**Write pattern** (uses `mutate_write` with printf content — same as how `.conjure-version` is written at `cli/conjure` line 89):
```bash
mutate_write "$TARGET/.claude/.conjure-org-overlay" \
  "$(printf 'url=%s\nsha=%s' "$OVERLAY_URL" "$CLONE_SHA")"
```

**Read pattern** (direct grep/cut, no `jq`):
```bash
OVERLAY_URL="$(grep '^url=' "$OVERLAY_MARKER" | cut -d= -f2-)"
PINNED_SHA="$(grep  '^sha=' "$OVERLAY_MARKER" | cut -d= -f2)"
```
Note: `cut -d= -f2-` (not `-f2`) for URL to preserve `=` characters in URLs.

---

## Shared Patterns

### DRY_RUN / mutate chokepoint
**Source:** `lib/mutate.sh` (entire file, 76 lines)
**Apply to:** `scripts/init-overlay.sh`, `scripts/refresh-overlay.sh`

All filesystem writes MUST go through `mutate_write`, `mutate_cp`, or `mutate_mkdir`. Direct `cp`/`mkdir`/`printf >` are forbidden except for the backup step (which is not a `.claude/` mutation and follows the `[ "$DRY_RUN" = 0 ]` guard from `cli/conjure` line 128):
```bash
[ "${DRY_RUN:-0}" = "0" ] && cp -R "$TARGET/.claude" "$backup"
```

`mutate_cp` checks `[ -d "$1" ]` and uses `cp -r` for directories automatically (lib/mutate.sh lines 39-43). No need to check manually before calling it.

### CONJURE_HOME self-resolution
**Source:** `scripts/publish-plugin.sh` line 17, `scripts/publish-skill.sh` line 17
**Apply to:** `scripts/init-overlay.sh`, `scripts/refresh-overlay.sh`
```bash
CONJURE_HOME="$(cd "$(dirname "$0")/.." && pwd)"
```
This is the canonical pattern. Do not rely on the `CONJURE_HOME` env var alone — the self-resolution makes worker scripts invocable directly (e.g., in tests that copy them to temp dirs).

### Exit code convention
**Source:** `scripts/publish-plugin.sh` lines 2-13 (header comment), `scripts/publish-skill.sh` lines 2-14
**Apply to:** `scripts/init-overlay.sh`, `scripts/refresh-overlay.sh`

| Exit code | Meaning |
|---|---|
| `0` | success |
| `1` | user-fixable error (no marker, bad URL, clone failure) |
| `2` | hard prerequisite failure (git not installed, lib/mutate.sh missing) |

### process substitution for find loop
**Source:** `scripts/audit-setup.sh` lines 65 and 103 (find + while read pattern), `tests/run.sh` lines 243-245
**Apply to:** `scripts/init-overlay.sh`, `scripts/refresh-overlay.sh` (copy loop)

Always use `done < <(find ...)` — never `find ... | while`. The pipe form runs the loop in a subshell and loses `CONJURE_DRY_MUTATION_COUNT` increments.

### ok/warn/err audit convention
**Source:** `scripts/audit-setup.sh` lines 14-17
**Apply to:** overlay section in `scripts/audit-setup.sh`

No new helper functions. Use the four already defined: `note`, `ok`, `warn`, `err`. The `PASS`/`WARN`/`FAIL` counters are set at the top of the script; each call to `ok`/`warn`/`err` increments them automatically.

### Test sandbox setup
**Source:** `tests/run.sh` lines 764-775 (MKTPL-SETUP), `tests/lib/sandbox.sh`
**Apply to:** OVLY test blocks in `tests/run.sh`

OVLY tests do NOT use `sandbox_setup` (which copies fixtures). Instead they use the direct `mktemp -d` + `git init` pattern from MKTPL-SETUP, because overlay tests need a real git repo as the mock overlay source. Cleanup: `rm -rf "$OVLY_REPO" "$OVLY_TARGET"` at end of block.

### mutate_summary at end of every worker
**Source:** `scripts/publish-plugin.sh` line 149, `scripts/publish-skill.sh` line (final)
**Apply to:** `scripts/init-overlay.sh`, `scripts/refresh-overlay.sh`

Always the second-to-last line before `exit 0`.

---

## No Analog Found

All files have analogs in the codebase. No RESEARCH.md-only patterns required.

---

## Anti-Patterns Identified (Do Not Copy)

| Anti-pattern | Location in codebase | Correct alternative |
|---|---|---|
| `cp -r clone/. dest/` copies `.git/` | (not present — just a risk) | `find clone -mindepth 1 -maxdepth 1 ! -name '.git'` loop |
| `find ... \| while IFS= read` loses mutation count | `cli/conjure` line 178 uses a `for $(find ...)` with `SC2044` disable comment | `done < <(find ...)` process substitution |
| `local` keyword at script top-level | present in `cmd_migrate` (a function), never at top-level | Use plain `var=value` at script level |

---

## Metadata

**Analog search scope:** `cli/`, `scripts/`, `lib/`, `tests/`, `tests/lib/`
**Files scanned:** 7 source files read in full
**Pattern extraction date:** 2026-05-26
