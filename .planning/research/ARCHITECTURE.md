# Architecture Research

**Domain:** Open-source init kit for Claude Code — POSIX bash CLI + Node `.mjs` hooks (Conjure v0.5.0 "Auto-Update + Healthcheck")
**Researched:** 2026-05-26
**Confidence:** HIGH (existing codebase read directly from repo; all files verified at read time)

> **Scope note (subsequent milestone):** This file documents how the six v0.5.0
> capabilities (DRIFT-01/02, AUTPR-01/02, RESOLVE-01/02, WIN-01/02, DEBT-01, DEBT-02)
> slot into the *current* file layout. The v0.4.0 architecture is taken as fixed
> and fully shipped: `cli/conjure` dispatcher → `scripts/*.sh` workers → `lib/mutate.sh`
> (write chokepoint) → `lib/merge.sh` (conflict sidecar producer). 261+ test
> assertions are green. Everything below is additive or a targeted modification.

---

## Existing Architecture (v0.4.0, fixed baseline)

```
cli/conjure               — dispatcher: parse flags, call scripts/*, source lib/*
  ├── cmd_init            — init|migrate; --profile; --overlay; --dry-run
  ├── cmd_migrate         — calls migrations/<source>/migrate.sh
  ├── cmd_audit           — calls scripts/audit-setup.sh; --cost; --retire-list
  ├── cmd_update          — --check (diff); --apply (3-way merge via lib/merge.sh)
  ├── cmd_refresh_graph   — calls scripts/refresh-graph.sh
  ├── cmd_refresh_overlay — calls scripts/refresh-overlay.sh
  ├── cmd_install_mcp     — calls scripts/install-mcp-stack.sh
  ├── cmd_preflight       — calls scripts/preflight.sh
  ├── cmd_publish         — calls scripts/publish-plugin.sh
  └── cmd_publish_skill   — calls scripts/publish-skill.sh (TARGET_REPO env, DEBT-02)

lib/mutate.sh             — write chokepoint (ALL filesystem mutations go here)
lib/merge.sh              — 3-way merge; writes conflict sidecars (.conjure-conflict-*)
lib/cost.sh               — char→token→$ estimation
lib/exact-count.mjs       — opt-in exact token counter (Node.js)
lib/prices.json           — per-model price table

scripts/init-project.sh   — scaffold .claude/
scripts/audit-setup.sh    — health-check; size caps; schema validation
scripts/preflight.sh      — dependency verification
scripts/publish-plugin.sh — marketplace.json update + submission snippet
scripts/publish-skill.sh  — 4-gate skill validation + PR flow
scripts/refresh-graph.sh  — knowledge graph rebuild
scripts/refresh-overlay.sh— org overlay refresh
scripts/install-mcp-stack.sh
scripts/init-overlay.sh

.github/workflows/
  ci.yml      — test + shellcheck + JSON validate + Windows-test jobs
  release.yml — 4-job: ci-gate → release → docker + homebrew (parallel)
  docker.yml  — Docker build smoke for PRs

tests/
  run.sh               — hand-rolled regression suite (261+ assertions)
  lib/sandbox.sh       — test helper
  fixtures/<profile>/  — committed scaffolds per stack profile

Conflict sidecar naming convention (from lib/merge.sh):
  .conjure-conflict-<rel_encoded>   where rel = path with '/' → '_'
  e.g. .conjure-conflict-skills_git-workflow_SKILL.md
```

Key invariant: **every filesystem write in the kit routes through `lib/mutate.sh`**
(mutate_mkdir / mutate_cp / mutate_write). All new commands must honor this.

---

## New Components

### 1. `scripts/check-drift.sh` (DRIFT-01, DRIFT-02)

**What:** Compares installed `.claude/` against the upstream kit snapshot stored at
`.claude/.conjure-templates-<pinned_version>/` (written by `cmd_init`). Produces
a file-level delta report: added, modified, removed.

**Why a new script and not inline in `cmd_update`:** `cmd_update --check` already
exists but only diffs SKILL.md files and does not compare the full harness (agents,
hooks, CLAUDE.md). `conjure check` is a read-only healthcheck with a distinct output
contract — it must not mutate anything, so it never sources `lib/mutate.sh`. Keeping
it separate keeps `cmd_update` concerned only with applying changes.

**Interface:**
```
conjure check [target]
```
Output format (stdout, one line per delta):
```
~ skills/git-workflow/SKILL.md     (modified — upstream changed)
+ skills/new-feature/SKILL.md      (added upstream — not installed)
- agents/old-agent.md              (removed upstream — still installed)
```
Exit codes: 0 = no drift, 1 = drift found (machine-readable for CI use).

**Implementation notes:**
- Reads `.conjure-version` → locates `$target/.claude/.conjure-templates-${pinned}/`
- Iterates upstream template tree + installed tree with POSIX `find` + `diff -q`
- Does NOT call `lib/mutate.sh` (read-only)
- Calls `scripts/preflight.sh` patterns for missing snapshot (error if snapshot absent)
- Should call `cmd_preflight` or equivalent for deps check

**New file:** `scripts/check-drift.sh`

---

### 2. `scripts/update-pr.sh` (AUTPR-01, AUTPR-02)

**What:** Runs `conjure update --apply` (or detects existing conflict sidecars), then
uses `gh` CLI to open a GitHub PR with the diff. Optionally writes
`.github/workflows/conjure-update.yml` as a cron template.

**Why a new script:** `cmd_update --apply` already does the merge; this script adds
PR automation on top. Separating it keeps `cmd_update` simple and `update-pr.sh`
testable in isolation.

**Interface (called by `cmd_update --pr`):**
```
conjure update --pr [target]
```

**Flow:**
1. Check `gh auth status` — exit with friendly error if not authenticated
2. Detect if `.claude/` has unresolved conflict sidecars (`find .claude -name '.conjure-conflict-*'`); if so, skip the apply step and go straight to PR creation with the existing diff
3. If no sidecars: run `lib/merge.sh` flow (same as `--apply`) — identical to existing `cmd_update --apply` logic, reused via `source lib/merge.sh`
4. `git checkout -b conjure-update-<version>` on a new branch
5. `git add .claude/` and commit with a standard message
6. `gh pr create --title "chore: update harness to conjure v<version>" --body <generated>`
7. Print PR URL

**Optional GH Action template (AUTPR-02):**
If `--cron` flag passed (or if `.github/workflows/conjure-update.yml` does not exist):
Write `.github/workflows/conjure-update.yml` via `mutate_write` — a cron workflow
that runs `conjure update --pr` on a schedule. This write goes through `lib/mutate.sh`.

**New file:** `scripts/update-pr.sh`

**Dependency on `gh`:** `gh` is already used in `publish-skill.sh` output. Add `gh`
to `scripts/preflight.sh` as a soft dependency (warn-not-fail, since `conjure check`
and `conjure update --apply` work without it).

---

### 3. `scripts/resolve-conflicts.sh` (RESOLVE-01, RESOLVE-02)

**What:** Interactive guided prompt walking the user through each
`.conjure-conflict-*` sidecar file. Shows the diff3 markers, prompts for a choice
(keep-ours / take-theirs / edit / skip), writes the resolved file via `lib/mutate.sh`,
and removes the sidecar on confirmation.

**Why interactive is OK here (unlike `cmd_update --apply`):** `conjure resolve` is
explicitly a human-in-the-loop command — the user invokes it in a terminal, not in CI.
The existing anti-pattern prohibition was about spawning `$VISUAL` from `cmd_update --apply`,
not about all interactivity everywhere.

**Interface:**
```
conjure resolve [target]
```

**Flow:**
1. `find "$target/.claude" -name '.conjure-conflict-*' | sort` → build list
2. If empty: print "No conflicts found" and exit 0
3. For each sidecar:
   a. Print the sidecar path and the decoded original filename
   b. `cat` the sidecar content (shows diff3 conflict markers)
   c. Prompt: `[k]eep yours / [t]ake theirs / [e]dit / [s]kip`
   d. On `k`: extract `<<<<<<< your version` block → write to original file via `mutate_write`
   e. On `t`: extract `>>>>>>> upstream` block → write to original file via `mutate_write`
   f. On `e`: print "Edit $original_file manually, then re-run conjure resolve" → skip
   g. On `s`: skip (leave sidecar, leave original)
   h. After k/t: `rm sidecar` (via `mutate_write` equivalent — use `mutate_rm` if added, or direct `rm` with dry-run guard)
4. If all sidecars resolved: print instructions to re-run `conjure update --apply` or manually stamp version

**Parser for diff3 markers:** Use `awk` (POSIX, no sed -E). Extract blocks between
`<<<<<<< your version` and `=======` (ours), `=======` and `||||||| v<base>` (base),
and `>>>>>>> v<X> upstream` (theirs). The label format is set by `lib/merge.sh:36-40`.

**New file:** `scripts/resolve-conflicts.sh`

**Note on `mutate_rm`:** The existing `lib/mutate.sh` has `mutate_mkdir`, `mutate_cp`,
`mutate_write` but no `mutate_rm`. Either add `mutate_rm` to `lib/mutate.sh`
(simple: `rm -f` in live mode, `[dry-run] would rm` in dry mode) or guard the `rm`
inline with `[ "${DRY_RUN:-0}" = "0" ] && rm -f "$sidecar"`. Add `mutate_rm` to
`lib/mutate.sh` — it will be needed by `resolve-conflicts.sh` and is a natural
gap in the existing API.

---

### 4. `conjure.ps1` (WIN-01, WIN-02)

**What:** Native PowerShell entrypoint for Windows users who do not have Git Bash.
Translates PowerShell invocation conventions to the equivalent bash script call via
`git bash` or `wsl`, depending on what is available. Does NOT re-implement conjure
logic in PowerShell — it is a thin dispatch shim.

**Why a shim and not a port:** The entire codebase is POSIX bash. Porting to PowerShell
would create two diverging implementations. The constraint "no heavy runtime deps"
applies — PowerShell is available natively on Windows 10+ but the bash logic is
already cross-platform. The right answer is a shim that finds bash and delegates.

**Location:** `cli/conjure.ps1` (alongside `cli/conjure`)

**Implementation:**
```powershell
# conjure.ps1 — PowerShell shim for native Windows
$ErrorActionPreference = "Stop"

# Find bash: Git Bash first, then WSL
$bash = $null
foreach ($candidate in @(
    "C:\Program Files\Git\bin\bash.exe",
    "C:\Program Files\Git\usr\bin\bash.exe",
    "$env:ProgramFiles\Git\bin\bash.exe"
)) {
    if (Test-Path $candidate) { $bash = $candidate; break }
}
if (-not $bash) {
    $wsl = Get-Command wsl -ErrorAction SilentlyContinue
    if ($wsl) { $bash = "wsl"; }
}
if (-not $bash) {
    Write-Error "conjure requires Git Bash or WSL. Install from https://git-scm.com"
    exit 1
}

$conjureScript = Join-Path $PSScriptRoot "conjure"
if ($bash -eq "wsl") {
    # Convert Windows path to WSL path
    $wslScript = wsl wslpath -a $conjureScript.Replace('\', '/')
    & wsl bash $wslScript @args
} else {
    & $bash --login -c "bash '$($conjureScript.Replace('\','/'))'  $($args -join ' ')"
}
exit $LASTEXITCODE
```

**CI job for WIN-02:** Add `windows-pwsh` job to `.github/workflows/ci.yml`:
```yaml
windows-pwsh:
  runs-on: windows-latest
  steps:
    - uses: actions/checkout@v4
    - name: Run via PowerShell shim
      shell: pwsh
      run: cli/conjure.ps1 version
```

**New file:** `cli/conjure.ps1`

---

## Modified Components

### `cli/conjure` — MODIFIED (4 changes)

**Change 1 — Add `cmd_check` function (DRIFT-01/02):**
```bash
cmd_check() {
  local target="$(pwd)"
  while [ $# -gt 0 ]; do
    case "$1" in
      --help|-h) echo "Usage: conjure check [target]"; return 0 ;;
      *)         target="$1" ;;
    esac
    shift
  done
  bash "$CONJURE_HOME/scripts/check-drift.sh" "$target"
}
```
Add dispatch: `check) shift; cmd_check "$@" ;;`

**Change 2 — Extend `cmd_update` for `--pr` flag (AUTPR-01/02):**
```bash
cmd_update() {
  local action="--check" target="$(pwd)" do_cron=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --check|--apply|--pr) action="$1" ;;
      --cron)               do_cron=1 ;;
      *)                    target="$1" ;;
    esac
    shift
  done
  # ... existing --check and --apply branches unchanged ...
  if [ "$action" = "--pr" ]; then
    CONJURE_HOME="$CONJURE_HOME" DRY_RUN="${DRY_RUN:-0}" \
      CONJURE_CRON="$do_cron" \
      bash "$CONJURE_HOME/scripts/update-pr.sh" "$target"
    return $?
  fi
  # ... rest of existing function ...
}
```

**Change 3 — Add `cmd_resolve` function (RESOLVE-01/02):**
```bash
cmd_resolve() {
  local target="$(pwd)"
  while [ $# -gt 0 ]; do
    case "$1" in
      --help|-h) echo "Usage: conjure resolve [target]"; return 0 ;;
      *)         target="$1" ;;
    esac
    shift
  done
  source "$CONJURE_HOME/lib/mutate.sh" \
    || { echo "✗ Failed to load lib/mutate.sh"; return 1; }
  bash "$CONJURE_HOME/scripts/resolve-conflicts.sh" "$target"
}
```
Add dispatch: `resolve) shift; cmd_resolve "$@" ;;`

**Change 4 — `cmd_publish_skill` positional arg refactor (DEBT-02):**
Current: `TARGET_REPO="$target_repo" bash "$CONJURE_HOME/scripts/publish-skill.sh" "$skill_name"`
The script reads `TARGET_REPO` env and `$1` for skill name.

Refactor: pass `$target_repo` as second positional arg to the script. The env var
fallback remains for backward compatibility:
```bash
  CONJURE_HOME="$CONJURE_HOME" DRY_RUN="$dryrun" \
    bash "$CONJURE_HOME/scripts/publish-skill.sh" "$skill_name" "$target_repo"
```
In `scripts/publish-skill.sh`: accept `$2` as target repo, defaulting to `TARGET_REPO`
env then to `mohandoz/conjure`:
```bash
SKILL_NAME="${1:-}"
TARGET_REPO="${2:-${TARGET_REPO:-mohandoz/conjure}}"
```
This preserves all existing call sites and removes the undocumented env-only path.

**Usage string update:** Add `check`, `resolve`, `update --pr` to the `usage()` heredoc.

---

### `scripts/publish-skill.sh` — MODIFIED (DEBT-02)

Accept positional `$2` as target repo, shadowing `TARGET_REPO` env. The `--to` flag
path in the script remains; it takes precedence over both `$2` and `TARGET_REPO`.
Priority: `--to` flag > `$2` positional > `TARGET_REPO` env > default.

Current line 24-25:
```bash
SKILL_NAME="${1:-}"
shift || true
```
Change to:
```bash
SKILL_NAME="${1:-}"
TARGET_REPO="${2:-${TARGET_REPO:-mohandoz/conjure}}"
shift 2 2>/dev/null || shift 1 2>/dev/null || true
```
(Remaining `$@` are still parsed by the while loop for `--to`/`--dry-run` flags.)

---

### `lib/mutate.sh` — MODIFIED (add `mutate_rm`)

Add one function:
```bash
# mutate_rm <path>
# In dry-run: prints [dry-run] would rm <path>, increments counter.
# In live mode: removes file (no-op if not found).
mutate_rm() {
  if [ "${DRY_RUN:-0}" = "1" ]; then
    echo "[dry-run] would rm $1"
    CONJURE_DRY_MUTATION_COUNT=$((CONJURE_DRY_MUTATION_COUNT + 1))
    return 0
  fi
  rm -f "$1"
}
```
This is required by `scripts/resolve-conflicts.sh` for sidecar cleanup. It follows
the exact same pattern as the existing three mutate_* functions and requires no
callers to change.

---

### `.github/workflows/release.yml` — MODIFIED (DEBT-01)

**ci-gate empty-check guard (DEBT-01):** The existing `ci-gate` job calls the GitHub
API and fails if any check-run has a failure conclusion. The missing guard: it does
NOT fail when `check_runs` is empty (a tagged commit that skipped CI entirely would
pass silently).

Add after fetching `$result`:
```yaml
total=$(gh api \
  "/repos/${{ github.repository }}/commits/${{ github.sha }}/check-runs" \
  --jq '.total_count')
if [ "$total" -eq 0 ]; then
  echo "FAIL: zero check-runs found for ${{ github.sha }} — CI may not have run"
  exit 1
fi
```
This is a pure YAML/shell addition to the existing step — no new files needed.

---

### `.github/workflows/ci.yml` — MODIFIED (WIN-02)

Add `windows-pwsh` job:
```yaml
windows-pwsh:
  runs-on: windows-latest
  steps:
    - uses: actions/checkout@v4
    - name: Smoke test PowerShell shim
      shell: pwsh
      run: |
        cli/conjure.ps1 version
    - name: Run test suite via PowerShell shim
      shell: pwsh
      run: |
        cli/conjure.ps1 preflight
```
The existing `windows-test` job (shell: bash) remains — it covers Git Bash path.
`windows-pwsh` covers native PowerShell path (WIN-02).

---

### `scripts/preflight.sh` — MODIFIED (soft `gh` check)

Add `gh` as a soft dependency (warn, not fail):
```bash
if ! command -v gh >/dev/null 2>&1; then
  echo "  ⚠  gh not found — conjure update --pr and conjure publish-skill PR flow unavailable"
  echo "     Install: https://cli.github.com"
fi
```
Soft because `conjure check`, `conjure resolve`, and `conjure update --apply` all
work without `gh`. Only `--pr` and the publish PR printing need it.

---

## Integration Points

### lib/mutate.sh chokepoint (unchanged invariant)

All new scripts that write files must source `lib/mutate.sh`:
- `scripts/update-pr.sh` writes `.github/workflows/conjure-update.yml` (via `mutate_write`)
- `scripts/resolve-conflicts.sh` writes resolved files + removes sidecars (via `mutate_write` + new `mutate_rm`)
- `scripts/check-drift.sh` does NOT write anything — pure read path; must not source `mutate.sh` except for the dry-run guard

Scripts that are read-only (`check-drift.sh`) must not call `mutate_summary` and
must not set `DRY_RUN`. This keeps their output clean for CI consumption.

### Conflict sidecar contract (lib/merge.sh → resolve-conflicts.sh)

`lib/merge.sh` produces sidecars with a known naming convention:
```
$target/.claude/.conjure-conflict-<rel_encoded>
```
where `<rel_encoded>` = the relative path with `/` replaced by `_`.

`scripts/resolve-conflicts.sh` must decode this: `tr '_' '/'` on the encoded suffix
to recover the original relative path, then prepend `$target/.claude/` for the
destination write.

The diff3 label format is fixed by `lib/merge.sh:36-40`:
- Ours: `your version (<rel>)`
- Base: `v<pinned_ver> base`
- Theirs: `v<new_ver> upstream`

The `awk` parser in `resolve-conflicts.sh` targets these exact labels.

### Version stamp chain (unchanged, extended)

```
VERSION file
  └─ CONJURE_VERSION in cli/conjure
       ├─ stamped to .claude/.conjure-version on init
       │    └─ read by cmd_update --check / --apply / --pr
       │    └─ read by check-drift.sh → locates snapshot dir
       ├─ snapshot dir: .claude/.conjure-templates-<version>/
       │    └─ base for 3-way merge (lib/merge.sh)
       │    └─ base for drift comparison (check-drift.sh)
       └─ verified in release.yml (tag must match VERSION)
```

### `gh` CLI integration points

Two scripts use `gh`:
1. `scripts/update-pr.sh` — `gh pr create` (required; fails gracefully if absent)
2. `scripts/publish-skill.sh` — `gh pr create` (already exists; prints instructions if absent)

Both follow the same pattern: `command -v gh >/dev/null 2>&1` guard, fallback
instructions printed if `gh` not found.

### PowerShell shim → bash dispatch

`cli/conjure.ps1` does not replace `cli/conjure`. It finds a bash interpreter
(Git Bash > WSL) and delegates. The actual dispatch table in `cli/conjure` handles
all subcommands including `check`, `resolve`, and `update --pr`. No PowerShell-specific
subcommand logic exists.

### ci-gate empty-check guard data flow

```
push v<tag>
  → release.yml: ci-gate job
      → gh api /repos/.../commits/<sha>/check-runs
           → .total_count == 0 → FAIL (DEBT-01 guard)
           → any .conclusion == failure → FAIL (existing guard)
           → all pass → OK → release job proceeds
```

---

## Data Flow Changes

### `conjure check` (new read-only path)

```
cli/conjure cmd_check
  → scripts/check-drift.sh <target>
      reads: <target>/.claude/.conjure-version
      reads: <target>/.claude/.conjure-templates-<pinned>/  (snapshot)
      reads: $CONJURE_HOME/templates/                        (upstream)
      compares with diff -q
      → stdout: delta report (added/modified/removed)
      → exit 0 (no drift) or exit 1 (drift)
      → NO writes
```

### `conjure update --pr` (new write + git + gh path)

```
cli/conjure cmd_update --pr
  → scripts/update-pr.sh <target>
      sources lib/mutate.sh
      sources lib/merge.sh
      → same 3-way merge as --apply (reuses merge_user_files)
      → git checkout -b conjure-update-<ver>
      → git add .claude/
      → git commit -m "chore: update conjure harness to v<ver>"
      → gh pr create ...
      [optionally]
      → mutate_write .github/workflows/conjure-update.yml <content>
```

### `conjure resolve` (new interactive path)

```
cli/conjure cmd_resolve
  → scripts/resolve-conflicts.sh <target>
      sources lib/mutate.sh (for mutate_write + mutate_rm)
      find .claude -name '.conjure-conflict-*'
      for each sidecar:
        → print content (diff3 markers)
        → read user choice [k/t/e/s]
        → awk-extract chosen block
        → mutate_write <original_file> <resolved_content>
        → mutate_rm <sidecar>
      → exit 0 (all resolved) or 1 (some skipped)
```

### `scripts/publish-skill.sh` positional arg refactor (DEBT-02)

```
Before: TARGET_REPO env  ← set by cli/conjure cmd_publish_skill
After:  $2 positional    ← passed by cli/conjure cmd_publish_skill
        (TARGET_REPO env still accepted as fallback for backward compat)
Priority: --to flag > $2 positional > TARGET_REPO env > default
```

---

## Suggested Build Order

Dependencies are explicit. Each step lists what it requires and what it unblocks.

### Step 1 — DEBT-02: `publish-skill.sh` positional arg refactor

**Why first:** Pure refactor, zero new logic, cannot break anything that was not already
broken. Takes 10 minutes. Clears the tech debt before new surface area is added. The
change is self-contained to `scripts/publish-skill.sh` and the two lines in
`cli/conjure cmd_publish_skill`. Tests already cover this path — existing assertions
verify the flag still works.

Requires: nothing
Unblocks: nothing else, but removes fragility before new scripts are added.

---

### Step 2 — Add `mutate_rm` to `lib/mutate.sh`

**Why second:** `scripts/resolve-conflicts.sh` (Step 4) depends on it. A 10-line
addition to a stable, well-tested file. Add tests in `tests/run.sh` for the new
function immediately. This is the lowest-risk change with the highest unblocking value.

Requires: nothing
Unblocks: Step 4 (resolve-conflicts.sh)

---

### Step 3 — DRIFT-01/02: `scripts/check-drift.sh` + `cmd_check`

**Why third:** Pure read path, no mutations, no external dependencies beyond what is
already preflight-required. The snapshot directory already exists (written by `cmd_init`
since v0.4.0). This gives an immediately useful command and validates the snapshot
structure before building update automation on top of it.

The exit-code contract (0 = clean, 1 = drift) makes `conjure check` useful in CI
before `conjure update --pr` exists.

Requires: snapshot dir from `cmd_init` (already shipped)
Unblocks: Step 5 (`update-pr.sh` can call check-drift.sh for pre-flight)

---

### Step 4 — RESOLVE-01/02: `scripts/resolve-conflicts.sh` + `cmd_resolve`

**Why fourth:** Requires `mutate_rm` (Step 2). This completes the conflict-resolution
user story that was left open in v0.4.0 (conflicts surfaced as sidecars; interactive
resolution deferred). Build it before `update --pr` so users have a way to resolve
conflicts that `--pr` might create.

Requires: `mutate_rm` (Step 2), `lib/merge.sh` sidecar naming convention (already shipped)
Unblocks: Step 5 (`update --pr` cycle: apply → conflicts → resolve → clean PR)

---

### Step 5 — AUTPR-01/02: `scripts/update-pr.sh` + `cmd_update --pr`

**Why fifth:** Depends on `lib/merge.sh` (shipped), `gh` CLI (soft dep, already in
publish-skill flow). With `conjure check` (Step 3) and `conjure resolve` (Step 4)
in place, the full update cycle is testable end-to-end. Add the optional cron template
(`AUTPR-02`) in the same step — it is a single `mutate_write` call in `update-pr.sh`.

Requires: `lib/merge.sh` (shipped), `gh` CLI (soft), Steps 3 + 4 complete
Unblocks: full auto-update workflow for teams

---

### Step 6 — WIN-01: `cli/conjure.ps1` PowerShell shim

**Why sixth:** No bash logic to implement — pure PowerShell path detection + delegation.
No dependencies on new scripts. Can be developed independently of Steps 1-5.
Placed sixth because it is low-risk and testable immediately once written; the
CI job (Step 7) is what validates it.

Requires: nothing (delegates to existing `cli/conjure`)
Unblocks: Step 7 (WIN-02 CI job needs the shim to exist)

---

### Step 7 — WIN-02 + DEBT-01: CI jobs

**Why last:** Both are CI-only changes. Win-02 adds the `windows-pwsh` job to
`ci.yml` (requires the `.ps1` shim from Step 6). DEBT-01 adds the empty-check guard
to `release.yml` ci-gate (requires no new code, just a YAML edit).

Group them in one step because both are `.github/workflows/` edits with no
code dependencies on each other.

Requires: Step 6 (`conjure.ps1` must exist for the CI job to test)
Unblocks: release pipeline is fully hardened

---

### Build order summary table

| Step | Work item | New / Modified files | Key dependency | Unblocks |
|------|-----------|----------------------|----------------|----------|
| 1 | DEBT-02: publish-skill positional arg | `scripts/publish-skill.sh` (M), `cli/conjure` (M) | nothing | fragility removed |
| 2 | `mutate_rm` in lib/mutate.sh | `lib/mutate.sh` (M) | nothing | Step 4 |
| 3 | DRIFT: `check-drift.sh` + `cmd_check` | `scripts/check-drift.sh` (N), `cli/conjure` (M) | snapshot dir (shipped) | Step 5 |
| 4 | RESOLVE: `resolve-conflicts.sh` + `cmd_resolve` | `scripts/resolve-conflicts.sh` (N), `cli/conjure` (M) | Step 2, lib/merge.sh | Step 5 |
| 5 | AUTPR: `update-pr.sh` + `cmd_update --pr` | `scripts/update-pr.sh` (N), `cli/conjure` (M) | Steps 3+4, gh CLI | full auto-update |
| 6 | WIN-01: `conjure.ps1` | `cli/conjure.ps1` (N) | nothing | Step 7 |
| 7 | WIN-02 + DEBT-01: CI jobs | `ci.yml` (M), `release.yml` (M) | Step 6 | hardened CI |

N = New file, M = Modified file

---

## Architecture Diagram (v0.5.0 additions highlighted)

```
┌──────────────────────────────────────────────────────────────────────────────┐
│  ENTRYPOINTS                                                                  │
│  ┌────────────────────────────────────────────────────────────────────┐      │
│  │  cli/conjure  (bash dispatcher)                   [existing]        │      │
│  │   init / migrate / audit / update --check/--apply                  │      │
│  │   refresh-graph / refresh-overlay / install-mcp                    │      │
│  │   preflight / publish / publish-skill                              │      │
│  │   check          [NEW — DRIFT-01/02]                               │      │
│  │   resolve        [NEW — RESOLVE-01/02]                             │      │
│  │   update --pr    [NEW flag — AUTPR-01/02]                          │      │
│  └────────────────────────────────────────────────────────────────────┘      │
│  ┌────────────────────────────────────────────────────────────────────┐      │
│  │  cli/conjure.ps1  (PowerShell shim)               [NEW — WIN-01]  │      │
│  │   → finds Git Bash or WSL → delegates to cli/conjure               │      │
│  └────────────────────────────────────────────────────────────────────┘      │
├──────────────────────────────────────────────────────────────────────────────┤
│  WORKER SCRIPTS (subprocess via bash scripts/*.sh)                           │
│  ┌─────────────────────┐  ┌─────────────────────┐  ┌──────────────────────┐ │
│  │ init-project.sh     │  │ check-drift.sh       │  │ resolve-conflicts.sh │ │
│  │ audit-setup.sh      │  │ [NEW — DRIFT-01/02]  │  │ [NEW — RESOLVE-01/02]│ │
│  │ preflight.sh  (+gh) │  │ read-only; no mutate │  │ sources lib/mutate.sh│ │
│  │ publish-skill.sh(M) │  │ exit 0/1 for CI use  │  │ mutate_write (ours/  │ │
│  │ publish-plugin.sh   │  └──────────────────────┘  │ theirs choice)       │ │
│  │ refresh-overlay.sh  │                             │ mutate_rm (sidecars) │ │
│  └─────────────────────┘  ┌─────────────────────┐  └──────────────────────┘ │
│                            │ update-pr.sh         │                          │
│                            │ [NEW — AUTPR-01/02]  │                          │
│                            │ sources lib/merge.sh  │                          │
│                            │ git checkout -b ...   │                          │
│                            │ gh pr create          │                          │
│                            │ [opt] mutate_write    │                          │
│                            │  conjure-update.yml   │                          │
│                            └─────────────────────┘                           │
├──────────────────────────────────────────────────────────────────────────────┤
│  SHARED LIB (sourced, not dispatched)                                        │
│  ┌──────────────────────────────────────────────────────────────────┐        │
│  │ lib/mutate.sh  [MODIFIED — add mutate_rm]                        │        │
│  │  mutate_mkdir / mutate_cp / mutate_write / mutate_rm (NEW)       │        │
│  │  ALL filesystem mutations route here                             │        │
│  └──────────────────────────────────────────────────────────────────┘        │
│  ┌──────────────────────────────────────────────────────────────────┐        │
│  │ lib/merge.sh  [existing — unchanged]                             │        │
│  │  merge_file_3way / write_merge_sidecar / merge_user_files         │        │
│  │  produces: .conjure-conflict-<encoded> sidecars                  │        │
│  └──────────────────────────────────────────────────────────────────┘        │
│  ┌──────────────────────────────────────────────────────────────────┐        │
│  │ lib/cost.sh / lib/exact-count.mjs / lib/prices.json [unchanged] │        │
│  └──────────────────────────────────────────────────────────────────┘        │
├──────────────────────────────────────────────────────────────────────────────┤
│  CI / RELEASE PIPELINE                                                        │
│  ┌──────────────────────────────────────────────────────────────────┐        │
│  │ .github/workflows/ci.yml  [MODIFIED]                             │        │
│  │  test / shellcheck / windows-test / windows-hook-wiring           │        │
│  │  windows-pwsh (NEW — WIN-02): shell: pwsh → conjure.ps1 version  │        │
│  └──────────────────────────────────────────────────────────────────┘        │
│  ┌──────────────────────────────────────────────────────────────────┐        │
│  │ .github/workflows/release.yml  [MODIFIED — DEBT-01]              │        │
│  │  ci-gate: + empty-check guard (total_count == 0 → FAIL)          │        │
│  │  release / docker / homebrew: unchanged                           │        │
│  └──────────────────────────────────────────────────────────────────┘        │
└──────────────────────────────────────────────────────────────────────────────┘

Conflict sidecar lifecycle (key data flow):
  lib/merge.sh        → write_merge_sidecar → .claude/.conjure-conflict-<enc>
  check-drift.sh      → find sidecars → include in drift report
  resolve-conflicts.sh → read sidecar → user choice → mutate_write original
                      → mutate_rm sidecar
```

---

## Anti-Patterns to Avoid

### Anti-Pattern 1: `check-drift.sh` sourcing `lib/mutate.sh`
**What:** Sourcing the mutate library in a read-only script.
**Why bad:** Adds mutation infrastructure to a pure-read path; `mutate_summary` will
print spurious dry-run output; no writes should ever happen in `conjure check`.
**Do this instead:** Do not source `lib/mutate.sh` in `check-drift.sh`. Guard writes
with inline `[ "${DRY_RUN:-0}" = "0" ]` if somehow needed (it should not be).

### Anti-Pattern 2: Re-implementing 3-way merge in `update-pr.sh`
**What:** Duplicating the `git merge-file` loop instead of calling `lib/merge.sh`.
**Why bad:** Two code paths for the same merge logic diverge; bugs fixed in one are
missed in the other.
**Do this instead:** `scripts/update-pr.sh` sources `lib/merge.sh` and calls
`merge_user_files` directly — identical to `cmd_update --apply`.

### Anti-Pattern 3: PowerShell shim re-implementing subcommand logic
**What:** Adding PowerShell-native logic for any conjure subcommand.
**Why bad:** Creates two diverging implementations; Windows behavior diverges from
bash; test coverage for the PowerShell path becomes its own surface area.
**Do this instead:** `conjure.ps1` is purely a bash-finder. All logic stays in
`cli/conjure`. The shim's only job is to find bash and exec it.

### Anti-Pattern 4: `conjure resolve` spawning an editor
**What:** Calling `$EDITOR` or `$VISUAL` or `nano` for the "edit" choice.
**Why bad:** Breaks Docker/CI usage; not available on all Windows setups; hard to
test. This was the original prohibition in v0.4.0.
**Do this instead:** The `[e]dit` option prints the file path and instructs the user
to edit it manually, then re-run `conjure resolve`. No editor is spawned.

### Anti-Pattern 5: Failing `ci-gate` for zero check-runs without distinguishing cause
**What:** Hard-failing when `total_count == 0` regardless of why.
**Why bad:** A new-repo first-push might not have CI runs yet; the error message must
be clear that this is a safety guard, not a random failure.
**Do this instead:** Print an explicit message ("zero check-runs found — CI may not
have run for this SHA") and exit 1. The message disambiguates safety-guard from
test failure.

---

## Sources

- `cli/conjure` (full content read this session) — HIGH confidence
- `lib/merge.sh` (full content read this session) — HIGH confidence
- `lib/mutate.sh` (full content read this session) — HIGH confidence
- `scripts/publish-skill.sh` (full content read this session) — HIGH confidence
- `.github/workflows/ci.yml` (full content read this session) — HIGH confidence
- `.github/workflows/release.yml` (full content read this session) — HIGH confidence
- `.planning/PROJECT.md` v0.5.0 requirements (read this session) — HIGH confidence
- Existing `.planning/research/ARCHITECTURE.md` v0.4.0 (read this session, carried forward) — HIGH confidence

---
*Architecture research for: Conjure v0.5.0 Auto-Update + Healthcheck integration*
*Researched: 2026-05-26*
