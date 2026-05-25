# Phase 11: Skill Publishing - Pattern Map

**Mapped:** 2026-05-25
**Files analyzed:** 3 new/modified files
**Analogs found:** 3 / 3

---

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `scripts/publish-skill.sh` | worker script | request-response (validate → emit) | `scripts/publish-plugin.sh` | exact |
| `cli/conjure` (add `cmd_publish_skill` + dispatch case) | CLI dispatcher | request-response | `cli/conjure` `cmd_publish` (lines 264-278) + dispatch (line 297) | exact |
| `tests/run.sh` (add SKILL-01..SKILL-04 block) | test suite | batch (sandbox → assert) | `tests/run.sh` MKTPL block (lines 760-888) | exact |

---

## Pattern Assignments

### `scripts/publish-skill.sh` (worker script, validate→emit)

**Analog:** `scripts/publish-plugin.sh`

**Shebang + set options + CONJURE_HOME derivation** (lines 1-18):
```bash
#!/usr/bin/env bash
# publish-skill.sh — Worker script for conjure publish-skill.
# Validates a project skill (frontmatter, size cap, egress scan, SHA-pinning),
# then prints the gh pr create command (or manual URL) for the user to run.
#
# Usage:
#   bash scripts/publish-skill.sh <skill-name> [--to <org/repo>] [--dry-run]
#   TARGET_REPO=org/repo DRY_RUN=1 bash scripts/publish-skill.sh my-skill
#
# Exit codes:
#   0 = success
#   1 = validation error (user-fixable: frontmatter, size, egress, SHA-pinning)
#   2 = hard prerequisite failure (missing dep, missing SKILL.md)

set -euo pipefail

CONJURE_HOME="$(cd "$(dirname "$0")/.." && pwd)"
source "$CONJURE_HOME/lib/mutate.sh"
```

**Env defaults + arg parsing pattern** (lines 20-42 of publish-plugin.sh, adapted):
```bash
# Env defaults — both env var and flag paths work
DRY_RUN="${DRY_RUN:-0}"
TARGET_REPO="${TARGET_REPO:-mohandoz/conjure}"

SKILL_NAME="${1:-}"
shift || true

while [ $# -gt 0 ]; do
  case "$1" in
    --to)       shift; TARGET_REPO="${1:-}" ;;
    --to=*)     TARGET_REPO="${1#--to=}" ;;
    --dry-run)  DRY_RUN=1 ;;
    -h|--help)
      echo "Usage: conjure publish-skill <name> [--to <org/repo>] [--dry-run]"
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
  shift
done

[ -z "$SKILL_NAME" ] && { echo "Usage: conjure publish-skill <name> [--to <org/repo>] [--dry-run]" >&2; exit 1; }
```

**Prerequisite checks pattern — exit 2 for missing deps** (lines 44-66 of publish-plugin.sh):
```bash
# Hard prerequisite failures: exit 2 (not 1)
if ! command -v git >/dev/null 2>&1; then
  echo "✗ git not installed" >&2
  exit 2
fi

SKILL_FILE="$(pwd)/.claude/skills/$SKILL_NAME/SKILL.md"
if [ ! -f "$SKILL_FILE" ]; then
  echo "✗ Skill not found: $SKILL_FILE" >&2
  exit 2
fi
```

**SHA-pinning guards — two distinct checks, both exit 1** (derived from D-07, D-08 in CONTEXT.md; pattern from publish-plugin.sh lines 62-66):
```bash
# Guard 1: skill must be committed (not dirty)
# Use TARGET (cwd by default) for the skill's git context — NOT CONJURE_HOME
TARGET="$(pwd)"
PORCELAIN="$(git -C "$TARGET" status --porcelain ".claude/skills/$SKILL_NAME/" 2>/dev/null)"
if [ -n "$PORCELAIN" ]; then
  echo "✗ Skill has uncommitted changes. Commit first:" >&2
  echo "    git add .claude/skills/$SKILL_NAME/ && git commit" >&2
  exit 1
fi

# Guard 2: conjure must be on a tagged release (not a branch HEAD)
# Use CONJURE_HOME for the conjure repo git context
CONJURE_VERSION="$(cat "$CONJURE_HOME/VERSION" 2>/dev/null || echo unknown)"
if ! git -C "$CONJURE_HOME" describe --exact-match HEAD 2>/dev/null; then
  echo "✗ Conjure version $CONJURE_VERSION is not a tagged release." >&2
  echo "  Run from a tagged commit." >&2
  exit 1
fi
```

**Frontmatter validation — bash grep/sed, no yq** (from audit-setup.sh lines 57-63 and RESEARCH.md Pattern 1):
```bash
# Extract frontmatter block (lines between opening --- and closing ---)
# Scoped to head -10 as audit-setup.sh does; or use sed -n '1,/^---$/p'
FM_BLOCK="$(sed -n '1,/^---$/p' "$SKILL_FILE" | grep -v '^---$')"

SKILL_NAME_FM="$(printf '%s\n' "$FM_BLOCK" | grep '^name:' | head -1 | sed 's/^name: *//' | tr -d '"')"
SKILL_DESC="$(printf '%s\n' "$FM_BLOCK" | grep '^description:' | head -1 | sed 's/^description: *//' | tr -d '"')"

# Validate name present
[ -z "$SKILL_NAME_FM" ] && { echo "✗ SKILL.md missing 'name:' frontmatter field" >&2; exit 1; }
# Validate name pattern (from skill.schema.json: ^[a-z][a-z0-9-]{1,40}$)
if ! printf '%s' "$SKILL_NAME_FM" | grep -qE '^[a-z][a-z0-9-]{1,40}$'; then
  echo "✗ name '$SKILL_NAME_FM' does not match ^[a-z][a-z0-9-]{1,40}$" >&2; exit 1
fi
# Validate name matches directory
[ "$SKILL_NAME_FM" != "$SKILL_NAME" ] && {
  echo "✗ Frontmatter name '$SKILL_NAME_FM' does not match directory name '$SKILL_NAME'" >&2; exit 1
}
# Validate description present and length (minLength 30, maxLength 400 from skill.schema.json)
[ -z "$SKILL_DESC" ] && { echo "✗ SKILL.md missing 'description:' frontmatter field" >&2; exit 1; }
DESC_LEN="$(printf '%s' "$SKILL_DESC" | wc -c | tr -d ' ')"
[ "$DESC_LEN" -lt 30 ] && { echo "✗ description too short ($DESC_LEN chars, min 30)" >&2; exit 1; }
[ "$DESC_LEN" -gt 400 ] && { echo "✗ description too long ($DESC_LEN chars, max 400)" >&2; exit 1; }
```

**Size cap check** (from tests/run.sh lines 63-68):
```bash
LINES="$(wc -l < "$SKILL_FILE" | tr -d ' ')"
if [ "$LINES" -gt 200 ]; then
  echo "✗ Skill exceeds 200-line cap ($LINES lines). Trim before publishing." >&2
  exit 1
fi
```

**Egress scan — body only, grep -nE, hard block** (from RESEARCH.md Pattern 2 and CONTEXT.md D-01, D-02):
```bash
# Scan body only (after the closing --- delimiter)
# awk: count --- markers; when count >= 2, start printing
BODY="$(awk 'BEGIN{n=0} /^---$/{n++; next} n>=2{print}' "$SKILL_FILE")"

EGRESS_HIT=0
if HITS="$(printf '%s\n' "$BODY" | grep -nE 'curl|wget|\bnc\b|fetch|http://|https://' 2>/dev/null)"; then
  [ -n "$HITS" ] && {
    echo "✗ Egress scan: network patterns found:" >&2
    printf '%s\n' "$HITS" >&2
    EGRESS_HIT=1
  }
fi
if HITS="$(printf '%s\n' "$BODY" | grep -nE '\$(HOME|USER|SECRET|API_KEY|TOKEN|PASSWORD)' 2>/dev/null)"; then
  [ -n "$HITS" ] && {
    echo "✗ Egress scan: sensitive env var refs found:" >&2
    printf '%s\n' "$HITS" >&2
    EGRESS_HIT=1
  }
fi
[ "$EGRESS_HIT" -eq 1 ] && exit 1
```

**PR instruction printing — gh present vs. absent** (from publish-plugin.sh lines 138-146, extended with gh detection; RESEARCH.md Pattern 4):
```bash
if command -v gh >/dev/null 2>&1; then
  echo "▸ conjure publish-skill: validation passed. Run this command to open the PR:"
  echo ""
  echo "  gh pr create \\"
  echo "    --repo $TARGET_REPO \\"
  echo "    --title \"feat(skills): add ${SKILL_NAME} skill\" \\"
  echo "    --body \"Contributes \`${SKILL_NAME}\` skill from \$(git -C \"\$TARGET\" rev-parse --short HEAD)\" \\"
  echo "    --head \$(git branch --show-current)"
else
  echo "▸ conjure publish-skill: validation passed. \`gh\` not found — open PR manually:"
  echo ""
  echo "  1. Push your branch: git push -u origin \$(git branch --show-current)"
  echo "  2. Visit: https://github.com/$TARGET_REPO/compare"
  echo "  3. Select your branch and create a PR titled: feat(skills): add ${SKILL_NAME} skill"
  echo "  4. Skill file: .claude/skills/$SKILL_NAME/SKILL.md"
fi
```

**Script tail — mutate_summary + exit 0** (lines 149-150 of publish-plugin.sh):
```bash
mutate_summary
exit 0
```

---

### `cli/conjure` — add `cmd_publish_skill` + dispatch case (CLI dispatcher)

**Analog:** `cli/conjure` `cmd_publish` (lines 264-278) and dispatch table (lines 288-301)

**`cmd_publish_skill` function** — copy shape of `cmd_publish` exactly; add positional arg:
```bash
# Source: cli/conjure lines 264-278 — cmd_publish shape
cmd_publish_skill() {
  local skill_name="" target_repo="mohandoz/conjure" dryrun=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --to)        shift; target_repo="${1:-}" ;;
      --to=*)      target_repo="${1#--to=}" ;;
      --dry-run)   dryrun=1 ;;
      --help|-h)   echo "Usage: conjure publish-skill <name> [--to <org/repo>] [--dry-run]"; return 0 ;;
      -*)          echo "Unknown option: $1"; return 1 ;;
      *)           skill_name="$1" ;;
    esac
    shift
  done
  [ -z "$skill_name" ] && {
    echo "Usage: conjure publish-skill <name> [--to <org/repo>] [--dry-run]"
    return 1
  }
  CONJURE_HOME="$CONJURE_HOME" DRY_RUN="$dryrun" TARGET_REPO="$target_repo" \
    bash "$CONJURE_HOME/scripts/publish-skill.sh" "$skill_name"
}
```

**Dispatch table insertion** — insert before the wildcard `*)` case; after `publish)` line 297:
```bash
# Source: cli/conjure lines 288-301 — existing dispatch table
# Add this case alongside the existing publish) entry:
  publish-skill)    shift; cmd_publish_skill "$@"    ;;
```

**`usage()` function update** — add the new subcommand line alongside `conjure publish`:
```bash
  conjure publish-skill <name> [--to <org/repo>] [--dry-run]
```

---

### `tests/run.sh` — add SKILL-01..SKILL-04 test block (test suite, batch)

**Analog:** `tests/run.sh` MKTPL block (lines 760-888)

**Sandbox setup pattern** (lines 760-775 of tests/run.sh — copy exactly, change paths):
```bash
# SKILL-SETUP: reusable sandbox — real git repo with committed SKILL.md.
# publish-skill.sh derives CONJURE_HOME from its own script path, so copy
# the script + lib into the sandbox. All writes stay inside the temp dir.
SKILL_DIR="$(mktemp -d)"
git -C "$SKILL_DIR" init -q
git -C "$SKILL_DIR" config user.email "test@conjure"
git -C "$SKILL_DIR" config user.name "conjure-test"
mkdir -p "$SKILL_DIR/.claude/skills/test-skill" "$SKILL_DIR/scripts" "$SKILL_DIR/lib"
# Write a clean SKILL.md (all validation gates pass)
printf -- '---\nname: test-skill\ndescription: A test skill that demonstrates the publish-skill validation pipeline end-to-end.\n---\n\n# test-skill\nSome clean content here with no egress patterns.\n' \
  > "$SKILL_DIR/.claude/skills/test-skill/SKILL.md"
cp "$CONJURE_HOME/scripts/publish-skill.sh" "$SKILL_DIR/scripts/"
cp "$CONJURE_HOME/lib/mutate.sh"            "$SKILL_DIR/lib/"
cp "$CONJURE_HOME/VERSION"                  "$SKILL_DIR/VERSION"
git -C "$SKILL_DIR" add -A
git -C "$SKILL_DIR" commit -q -m "add test-skill"
# Tag the sandbox HEAD so the conjure "tagged release" guard passes
git -C "$SKILL_DIR" tag "v$(cat "$CONJURE_HOME/VERSION")"
```

**Test assertion pattern** (lines 778-783 of tests/run.sh — pass/fail inline, no bats):
```bash
# SKILL-01: dry-run suppresses mutations
SKILL_OUT="$(DRY_RUN=1 bash "$SKILL_DIR/scripts/publish-skill.sh" test-skill 2>&1)"
if printf '%s\n' "$SKILL_OUT" | grep -q 'dry-run'; then
  pass "publish-skill dry-run prints dry-run output (SKILL-01)"
else
  fail "publish-skill dry-run did not print dry-run output (SKILL-01)"
fi
```

**Negative test pattern — inject bad state, assert exit code** (lines 793-800 of tests/run.sh):
```bash
# SKILL-03: dirty skill tree → exit 1 with correct message
echo "dirty" >> "$SKILL_DIR/.claude/skills/test-skill/SKILL.md"
DIRTY_RC=0
bash "$SKILL_DIR/scripts/publish-skill.sh" test-skill >/dev/null 2>&1 || DIRTY_RC=$?
if [ "$DIRTY_RC" -eq 1 ]; then
  pass "publish-skill exits 1 on dirty skill tree (SKILL-03)"
else
  fail "publish-skill did not exit 1 on dirty skill tree — got rc=$DIRTY_RC (SKILL-03)"
fi
# Restore: re-checkout and recommit for subsequent tests
git -C "$SKILL_DIR" checkout -- .claude/skills/test-skill/SKILL.md
```

**Cleanup at end of SKILL block** (line 888 of tests/run.sh):
```bash
rm -rf "$SKILL_DIR"
```

---

## Shared Patterns

### Mutation chokepoint: `lib/mutate.sh`
**Source:** `lib/mutate.sh` (full file, 76 lines)
**Apply to:** `scripts/publish-skill.sh`

```bash
# Source at top of worker script — provides DRY_RUN-aware mutate_write, mutate_mkdir, mutate_cp, mutate_summary
source "$CONJURE_HOME/lib/mutate.sh"

# Call at script tail for clean DRY_RUN accounting even when no files are written:
mutate_summary
```

Key constraint: even if `publish-skill.sh` writes no files, `mutate_summary` must still be called so `DRY_RUN=1` output is emitted cleanly.

### Exit code convention
**Source:** `scripts/publish-plugin.sh` (comments lines 11-13) and `cli/conjure` `cmd_migrate` (line 113)
**Apply to:** `scripts/publish-skill.sh`

```
exit 0 = success
exit 1 = validation error (frontmatter, size, egress, SHA-pinning) — user-fixable
exit 2 = hard prerequisite failure (missing git dep, missing SKILL.md)
```

### DRY_RUN internal env var name
**Source:** `scripts/publish-plugin.sh` line 21 + `cli/conjure` lines 265-277
**Apply to:** `cmd_publish_skill` in `cli/conjure` and `scripts/publish-skill.sh`

The public flag `--dry-run` sets `dryrun=1` in the dispatcher; passed to the worker as `DRY_RUN="$dryrun"`. The worker reads `DRY_RUN="${DRY_RUN:-0}"`. Do not use `CONJURE_DRYRUN` as the internal variable name — `DRY_RUN` is the actual convention.

```bash
# Dispatcher (cli/conjure cmd_publish_skill):
CONJURE_HOME="$CONJURE_HOME" DRY_RUN="$dryrun" TARGET_REPO="$target_repo" \
  bash "$CONJURE_HOME/scripts/publish-skill.sh" "$skill_name"

# Worker (scripts/publish-skill.sh):
DRY_RUN="${DRY_RUN:-0}"
```

### Dirty-tree git check
**Source:** `scripts/publish-plugin.sh` lines 62-66
**Apply to:** `scripts/publish-skill.sh` (SHA-pinning Guard 1)

The established pattern uses `git diff --quiet` for the whole repo tree. For `publish-skill.sh` the check is scoped to the skill directory specifically using `git status --porcelain <path>` with the user's project context (`$TARGET`, not `$CONJURE_HOME`).

### Frontmatter bash parsing (no yq)
**Source:** `scripts/audit-setup.sh` lines 57-63
**Apply to:** `scripts/publish-skill.sh` (Gate 3 validation)

```bash
# From audit-setup.sh — use head -10 for speed; or sed -n '1,/^---$/p' for precision
if ! head -10 "$skill" | grep -q '^name:'; then
  err "Skill '$name': missing 'name:' frontmatter"
fi
if ! head -10 "$skill" | grep -q '^description:'; then
  err "Skill '$name': missing 'description:' frontmatter"
elif head -10 "$skill" | grep -qE '^description: "?.{0,29}"?$'; then
  warn "Skill '$name': description very short (<30 chars)"
fi
```

For `publish-skill.sh`, extract values (not just detect presence) using `sed 's/^name: *//'`. Use `sed -n '1,/^---$/p'` to scope the block precisely.

### Test section header + section separator
**Source:** `tests/run.sh` (lines 46-47, 60-61, pattern throughout)
**Apply to:** SKILL test block in `tests/run.sh`

```bash
echo
echo "▸ SKILL publish-skill tests"
```

---

## Schema Reference

**Source:** `.claude-plugin/SCHEMAS/skill.schema.json` (full file, 39 lines)

Required fields: `name`, `description`. Additional properties forbidden.

| Field | Constraint | Validation method in script |
|-------|-----------|----------------------------|
| `name` | `^[a-z][a-z0-9-]{1,40}$` | `grep -qE '^[a-z][a-z0-9-]{1,40}$'` |
| `description` | minLength 30, maxLength 400 | `wc -c` on extracted value |
| name matches dir | must equal `$SKILL_NAME` | string comparison |

Optional fields (`allowed-tools`, `model`, `memory`) do not need validation in `publish-skill.sh` — their presence is harmless and schema validation is bash-based (grep/sed), not JSON Schema.

---

## No Analog Found

All three deliverable files have close analogs in the codebase. No files require fallback to RESEARCH.md external patterns only.

---

## Critical Pitfall Summary (for planner)

| Pitfall | Risk | Avoidance |
|---------|------|-----------|
| `nc` matches substrings | False positives on "since", "announce" | Use `\bnc\b` (or `(^| )nc[ ;$]` for maximum portability) |
| Egress scan hits frontmatter | False positives on description prose | Use `awk n>=2` body extraction before grep |
| SHA-pinning uses wrong git context | Dirty check never fires | Use `git -C "$TARGET"` for skill check; `git -C "$CONJURE_HOME"` for tag check |
| Sandbox test missing tag | Happy-path test always exits 1 | `git tag v$(cat VERSION)` after initial sandbox commit |
| `gh pr create` executed, not printed | Design violation (D-03) | Only `echo` the command string; never call `gh pr create` directly |
| `cmd_publish_skill` missing positional arg check | Obscure failure when name omitted | `[ -z "$skill_name" ] && { echo "Usage: ..."; return 1; }` |

---

## Metadata

**Analog search scope:** `scripts/`, `cli/`, `tests/`, `lib/`, `scripts/audit-setup.sh`
**Files scanned:** 6 (publish-plugin.sh, cli/conjure, lib/mutate.sh, tests/run.sh, tests/lib/sandbox.sh, scripts/audit-setup.sh) + 1 schema file
**Pattern extraction date:** 2026-05-25
