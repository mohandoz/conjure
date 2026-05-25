# Phase 10: Marketplace Publish - Pattern Map

**Mapped:** 2026-05-25
**Files analyzed:** 3 new/modified files
**Analogs found:** 3 / 3

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---|---|---|---|---|
| `scripts/publish-plugin.sh` | script/worker | file-I/O + request-response | `scripts/init-project.sh` | exact |
| `cli/conjure` (cmd_publish dispatch) | controller/entrypoint | request-response | `cli/conjure:cmd_audit` | exact |
| `.github/workflows/ci.yml` (new steps) | config/CI | batch | `.github/workflows/release.yml` (version check step) | role-match |

---

## Pattern Assignments

### `scripts/publish-plugin.sh` (script/worker, file-I/O)

**Analog:** `scripts/init-project.sh`

**Shebang + set options** (init-project.sh lines 1-8):
```bash
#!/usr/bin/env bash
# publish-plugin.sh — update .claude-plugin/ manifests for marketplace publish.
# Usage: bash publish-plugin.sh [--submit] [--dry-run]
# Exit codes: 0 = success, 1 = validation error, 2 = dirty tree / missing dep.

set -euo pipefail
```

Note: `audit-setup.sh` uses `set -uo pipefail` (no `-e`) so it can accumulate
failures. `publish-plugin.sh` writes files and must abort on first error — use
`set -euo pipefail` like `init-project.sh`.

**CONJURE_HOME resolution + source mutate.sh** (init-project.sh lines 11-13):
```bash
KIT="$(cd "$(dirname "$0")/.." && pwd)"
source "$KIT/lib/mutate.sh"
```
Use the same pattern: `CONJURE_HOME="$(cd "$(dirname "$0")/.." && pwd)"` then
`source "$CONJURE_HOME/lib/mutate.sh"`.

**Argument parsing** (regen-fixtures.sh lines 17-33):
```bash
while [ $# -gt 0 ]; do
  case "$1" in
    --submit)
      DO_SUBMIT=1
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    *)
      printf 'Unknown argument: %s\n' "$1" >&2
      exit 1
      ;;
  esac
done
```
`DRY_RUN` defaults to `0` at top of script: `DRY_RUN="${DRY_RUN:-0}"` (so
the `--dry-run` flag and the env var both work — see cli/conjure:64).

**VERSION reading** (cli/conjure lines 24-25):
```bash
CONJURE_VERSION="$(cat "$CONJURE_HOME/VERSION" 2>/dev/null || echo unknown)"
```
Use the same idiom. Abort if unknown: `[ "$CONJURE_VERSION" = "unknown" ] && { echo "✗ VERSION file missing"; exit 2; }`.

**Dirty-tree abort** (specified in CONTEXT.md D-06; no existing codebase example):
```bash
if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "✗ Working tree has uncommitted changes — commit or stash before publishing."
  exit 2
fi
```
Place this immediately after arg parsing, before any reads or writes. Exit code
2 matches the "errors" convention established in `audit-setup.sh` line 268.

**jq JSON validation** (ci.yml "Validate JSON" step — same guard pattern):
```bash
if ! command -v jq >/dev/null 2>&1; then
  echo "✗ jq not installed — required for manifest validation"
  exit 2
fi
if ! jq empty ".claude-plugin/plugin.json" 2>/dev/null; then
  echo "✗ .claude-plugin/plugin.json: invalid JSON"
  exit 1
fi
if ! jq empty ".claude-plugin/marketplace.json" 2>/dev/null; then
  echo "✗ .claude-plugin/marketplace.json: invalid JSON"
  exit 1
fi
```
Mirror the `jq empty` pattern from `audit-setup.sh` lines 87-91.

**mutate_write calling convention** (lib/mutate.sh lines 50-64 + usage in
init-project.sh line 111 and cli/conjure line 87):
```bash
# Signature: mutate_write <dest> <content> [--append]
# Content passed as string arg — never pipe (pipe = subshell = lost counter).
mutate_write ".claude-plugin/marketplace.json" "$updated_json"
mutate_write ".claude-plugin/plugin.json"      "$updated_plugin_json"
# For submit-entry.json (optional --submit path):
mutate_write ".claude-plugin/submit-entry.json" "$submit_json"
```
`$updated_json` must be assembled in a variable before the call. Use `jq` to
produce the updated JSON string: `updated_json="$(jq --arg v "$CONJURE_VERSION" --arg sha "$HEAD_SHA" ... ".claude-plugin/marketplace.json")"`.

**mutate_summary at end** (init-project.sh line 120, cli/conjure line 106):
```bash
mutate_summary
```
Always the last statement before the final echo/exit.

**Error/status output conventions** (audit-setup.sh lines 14-17):
```bash
# Use these prefixes — consistent with the rest of the CLI:
echo "▸ conjure publish: ..."    # progress / info
echo "✓ marketplace.json updated"  # success
echo "✗ plugin.json: version mismatch"  # fatal error
echo "⚠ ..."  # warning (non-fatal)
```

---

### `cli/conjure` — `cmd_publish` addition (controller, request-response)

**Analog:** `cmd_audit` in `cli/conjure` (lines 132-148) and `cmd_init` (lines 52-108)

**Function signature + arg parsing** (cmd_audit lines 132-148):
```bash
cmd_publish() {
  local do_submit=0
  local dryrun=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --submit)    do_submit=1 ;;
      --dry-run)   dryrun=1 ;;
      --help|-h)   grep -A3 '^  conjure publish' <<<"$(usage)"; return 0 ;;
      *)           echo "Unknown option: $1"; return 1 ;;
    esac
    shift
  done
```

**DRY_RUN export before sourcing mutate.sh** (cmd_init lines 64-66):
```bash
  DRY_RUN="$dryrun"
  source "$CONJURE_HOME/lib/mutate.sh" \
    || { echo "✗ Failed to load lib/mutate.sh — check CONJURE_HOME ($CONJURE_HOME)"; return 1; }
```
`cmd_publish` does NOT source mutate.sh itself (the script does). Just set
`DRY_RUN` and pass it via env to the script call.

**Script invocation via env-prefixed bash** (cmd_audit lines 144-147, cmd_init line 78):
```bash
  CONJURE_HOME="$CONJURE_HOME" DRY_RUN="$dryrun" \
    bash "$CONJURE_HOME/scripts/publish-plugin.sh" \
    ${do_submit:+--submit}
```
`${do_submit:+--submit}` expands to `--submit` only when `do_submit=1` —
avoids an extra `if` branch.

**Dispatch table slot** (cli/conjure lines 272-283):
```bash
# Add before the wildcard `*` case:
  publish)         shift; cmd_publish "$@"         ;;
```
Insert alphabetically or after `preflight)` to keep the table consistent.

**usage() addition** — append a line to the heredoc:
```bash
  conjure publish [--submit] [--dry-run]
```
Place it after the `conjure preflight` line to stay in alphabetical order.

---

### `.github/workflows/ci.yml` — new steps (config, batch)

**Analog:** `.github/workflows/release.yml` "Verify VERSION matches tag" step (lines 18-24)
and the existing ci.yml "Validate JSON" step.

**Version-consistency check step** (release.yml lines 18-24 adapted for PR context):
```yaml
      - name: Check version consistency
        run: |
          ver=$(cat VERSION)
          mkt=$(jq -r '.plugins[0].version' .claude-plugin/marketplace.json)
          plg=$(jq -r '.version' .claude-plugin/plugin.json)
          ok=1
          [ "$mkt" = "$ver" ] || { echo "marketplace.json version ($mkt) != VERSION ($ver)"; ok=0; }
          [ "$plg" = "$ver" ] || { echo "plugin.json version ($plg) != VERSION ($ver)"; ok=0; }
          [ "$ok" = "1" ] || exit 1
```
This step slots into the existing `test` job (same runner) after "Validate JSON".
No new job needed — the step is cheap and fast.

**claude CLI install step** (from CONTEXT.md D-02; no existing analog in repo):
```yaml
      - name: Install claude CLI
        run: |
          curl -fsSL https://claude.ai/install.sh | sh
          echo "$HOME/.claude/bin" >> "$GITHUB_PATH"
```
If the install fails, `set -e` in the shell causes CI to fail — honors D-02
"claude install failure = CI failure". The `GITHUB_PATH` append makes `claude`
available in subsequent steps.

**claude plugin validate step** (from CONTEXT.md D-01):
```yaml
      - name: Validate plugin manifest
        run: claude plugin validate .claude-plugin/plugin.json
```
Exact flag/path determined by RESEARCH.md (the researcher resolves D-03).
If `claude plugin validate .` targets the whole `.claude-plugin/` directory,
replace `plugin.json` with `.` accordingly. Use the result from the researcher.

**Existing JSON validation step** (ci.yml lines 25-28 — extend, don't replace):
```yaml
      - name: Validate JSON
        run: |
          find templates .claude-plugin -name '*.json' \
            -exec jq empty {} \;
```
The current step already includes `.claude-plugin` in its glob. No change
needed here unless the researcher identifies additional JSON files to validate.

**Step ordering in `test` job** — insert after "Validate JSON", before "Run kit
test suite":
1. Validate JSON (existing — no change)
2. Check version consistency (new)
3. Install claude CLI (new)
4. Validate plugin manifest (new)
5. Run kit test suite (existing — no change)

---

## Shared Patterns

### DRY_RUN / mutate.sh sourcing
**Source:** `lib/mutate.sh` lines 1-75, `cli/conjure` lines 64-66
**Apply to:** `scripts/publish-plugin.sh`, `cli/conjure:cmd_publish`

```bash
# In publish-plugin.sh (the script owns the source call):
source "$CONJURE_HOME/lib/mutate.sh"

# In cmd_publish (cli/conjure sets env; script sources mutate.sh):
DRY_RUN="$dryrun"
CONJURE_HOME="$CONJURE_HOME" DRY_RUN="$dryrun" bash "$CONJURE_HOME/scripts/publish-plugin.sh" ...
```
The `DRY_RUN` env var is read by mutate_write/mutate_mkdir/mutate_cp via
`${DRY_RUN:-0}` — no global export required.

### Exit code convention
**Source:** `audit-setup.sh` lines 267-269, `preflight.sh` line 109
**Apply to:** `scripts/publish-plugin.sh`

```bash
# 0 = success
# 1 = validation error / version mismatch (soft fail)
# 2 = hard prerequisite failure (dirty tree, missing dep, missing file)
[ "$FAIL" -gt 0 ] && exit 2
[ "$WARN" -gt 0 ] && exit 1
exit 0
```

### jq availability guard
**Source:** `audit-setup.sh` lines 86-91
**Apply to:** `scripts/publish-plugin.sh`

```bash
if ! command -v jq >/dev/null 2>&1; then
  echo "✗ jq not installed — required"
  exit 2
fi
```

### CONJURE_HOME self-resolution in scripts
**Source:** `scripts/init-project.sh` line 12, `scripts/regen-fixtures.sh` line 10
**Apply to:** `scripts/publish-plugin.sh`

```bash
CONJURE_HOME="$(cd "$(dirname "$0")/.." && pwd)"
```
Scripts resolve their own `CONJURE_HOME` — they do not rely on the caller to
export it. The cli/conjure dispatch passes `CONJURE_HOME="$CONJURE_HOME"` as
an env prefix for explicit safety (see cmd_audit line 145).

---

## No Analog Found

| File / Concern | Role | Data Flow | Reason |
|---|---|---|---|
| Dirty-tree abort logic | guard | request-response | No existing script in the repo aborts on `git diff`. Pattern specified in CONTEXT.md D-06; standard bash idiom. |
| claude CLI install in CI | CI step | batch | No existing step installs the claude CLI. CONTEXT.md D-02 requires it; exact URL from RESEARCH.md. |
| `submit-entry.json` structure | data | file-I/O | No existing catalog entry file. Structure determined by researcher from anthropics/claude-plugins-community. |

---

## Metadata

**Analog search scope:** `cli/`, `scripts/`, `lib/`, `.github/workflows/`, `.claude-plugin/`
**Files scanned:** 8 (conjure CLI, init-project.sh, audit-setup.sh, preflight.sh, regen-fixtures.sh, mutate.sh, ci.yml, release.yml)
**Pattern extraction date:** 2026-05-25
