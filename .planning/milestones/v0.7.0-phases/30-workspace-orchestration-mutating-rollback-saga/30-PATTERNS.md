# Phase 30: Workspace Orchestration — Mutating + Rollback Saga - Pattern Map

**Mapped:** 2026-06-04
**Files analyzed:** 7 new/modified surfaces
**Analogs found:** 6 / 7 (1 net-new: disk-estimate via `du`)

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `scripts/workspace.sh` (extend: `update`, `adopt`, `rollback` branches) | orchestrator | CRUD + event-driven (saga) | `scripts/workspace.sh` itself (Phase 29 `ws_do_check`/`ws_do_audit`) | exact |
| `lib/workspace.sh` (extend: `workspace_state_write`, `workspace_state_read`) | utility/lib | CRUD + atomic-write | `scripts/adopt.sh` `state_record` function | exact |
| `tests/fixtures/_workspace-trio/` (new fixture: 3 small adoptable repos) | fixture | — | `tests/fixtures/_workspace/` (3-repo manifest, alpha/beta/gamma) | exact |
| `tests/run.sh` (Phase 30 block: SIGKILL saga + rollback zero-diff) | test | event-driven | `tests/run.sh` Phase 24 SIGKILL block (~lines 3470–3564) | exact |
| `cli/conjure` `cmd_workspace` (extend: `update`, `adopt` subcommand tokens) | CLI dispatcher | request-response | `cli/conjure` `cmd_workspace` (lines 573–589) | exact |
| `scripts/workspace.sh` `ws_do_update` (new function) | orchestrator | request-response | `scripts/workspace.sh` `ws_do_check` (lines 49–127) | role-match |
| disk-estimate (`du`-based pre-snapshot check) | utility inline | transform | **NO ANALOG** — no `du` usage exists anywhere in the codebase | none |

---

## Pattern Assignments

### `lib/workspace.sh` — `workspace_state_write` / `workspace_state_read` helpers

**Analog:** `scripts/adopt.sh` `state_record` function (lines 76–101)

**Atomic-write idiom** (adopt.sh lines 80–101):
```bash
# state_record <jq-filter> [args...]
# Applies <jq-filter> to the current state.json and atomically replaces it via
# a same-dir temp file. Never truncates state on a crash.
state_record() {
  local filter="$1"; shift
  local tmp="$STATE_PATH.tmp.$$"
  [ -d "$STATE_DIR" ] || mkdir -p "$STATE_DIR"
  if [ -f "$STATE_PATH" ]; then
    if jq "$@" "$filter" "$STATE_PATH" > "$tmp" 2>/dev/null; then
      mv "$tmp" "$STATE_PATH"
    else
      rm -f "$tmp"
      echo "adopt.sh: failed to update state at $STATE_PATH" >&2
      exit 2
    fi
  else
    if jq -n "$@" "$filter" > "$tmp" 2>/dev/null; then
      mv "$tmp" "$STATE_PATH"
    else
      rm -f "$tmp"
      echo "adopt.sh: failed to create state at $STATE_PATH" >&2
      exit 2
    fi
  fi
}
```

**How `workspace_state_write` must differ:**
- The state lives at `$WORKSPACE_ROOT/.conjure-workspace-state.json` (a single file, not a directory); there is no `STATE_DIR` to `mkdir -p`.
- First write uses `jq -n` to build the full initial object (with `run_id`, `started`, `phase`, `repos[]`); subsequent writes apply a filter to the existing file — same two-branch logic above.
- The `tmp` path must be same-dir (`.conjure-workspace-state.json.tmp.$$`) to guarantee atomic `mv` on POSIX.
- Always `rm -f "$tmp"` in the failure branch before `exit 2`.

**`workspace_state_read` pattern** — reads a jq expression from the state file, printing to stdout:
```bash
# adopt.sh pattern for reading from state (inline, not a function):
snap="$(jq -r '.snapshot_path // ""' "$STATE_PATH" 2>/dev/null)"
LAST_STEP="$(jq -r '.current_step // "unknown"' "$STATE_PATH" 2>/dev/null || echo unknown)"
```
New `workspace_state_read <jq-expr>` can be a one-liner wrapper with the same `// ""` default and `2>/dev/null` suppression.

---

### `scripts/workspace.sh` — `ws_do_update` (new function, `update` subcommand)

**Analog:** `scripts/workspace.sh` `ws_do_check` (lines 49–127)

**Per-repo loop structure** (ws_do_check lines 66–117):
```bash
while IFS= read -r repo_json; do
  repo_name="$(printf '%s' "$repo_json" | jq -r '.name')"
  repo_relpath="$(printf '%s' "$repo_json" | jq -r '.path')"
  repo_abs="$manifest_dir/$repo_relpath"

  # Bad-path guard: skip with warning, set partial-success
  if [ ! -d "$repo_abs" ]; then
    printf '%-30s %-15s %s\n' "$repo_name" "SKIP" "bad-path"
    printf '  ⚠ skipping %s: path not found (%s)\n' "$repo_name" "$repo_abs" >&2
    overall_rc=1
    continue
  fi

  # Defense-in-depth traversal re-check (CR-02)
  repo_real="$(cd "$repo_abs" 2>/dev/null && pwd -P)" || {
    printf '%-30s %-15s %s\n' "$repo_name" "SKIP" "bad-path"
    printf '  ⚠ skipping %s: cannot resolve path (%s)\n' "$repo_name" "$repo_abs" >&2
    overall_rc=1
    continue
  }
  case "$repo_real" in
    "$manifest_root"|"$manifest_root/"*) ;;
    *)
      printf '%-30s %-15s %s\n' "$repo_name" "SKIP" "out-of-bounds"
      printf '  ⚠ SECURITY: skipping %s: escapes workspace root (%s)\n' "$repo_name" "$repo_real" >&2
      overall_rc=1
      continue
      ;;
  esac

  # Per-repo invocation — flags MUST be argv, NOT env vars
  repo_rc=0
  porcelain_out="$(bash "$CONJURE_HOME/cli/conjure" check --porcelain "$repo_abs" 2>/dev/null)" \
    || repo_rc=$?

done < <(jq -c '.repos[]' "$manifest_path")
```

**Per-repo invocation idiom for `conjure update`** (argv, not env):
```bash
repo_rc=0
bash "$CONJURE_HOME/cli/conjure" update "$repo_abs" 2>"$TMPERR" || repo_rc=$?
```
Flags like `--continue-on-error` affect the outer loop, not the inner subprocess call.

**Stop-on-fail vs continue-on-error pattern** (adapt from ws_do_audit `--fail-fast`, lines 240–244):
```bash
# --fail-fast: abort at first failure
if [ "$fail_fast" -eq 1 ] && [ "$overall_rc" -eq 2 ]; then
  printf '\n✗ --fail-fast: aborting after first failure (%s)\n' "$repo_name" >&2
  return 2
fi
```
For `ws_do_update`: default is stop-on-first-error (`CONTINUE_ON_ERROR=0`); `--continue-on-error` inverts this. Replace `fail_fast` check with: `[ "$CONTINUE_ON_ERROR" -eq 0 ] && [ "$repo_rc" -ne 0 ] && return 2`.

**Conflict-sidecar surfacing** — `cmd_update` in `cli/conjure` (lines 428–437) sets:
- `CONJURE_MERGE_CONFLICT_COUNT` — integer count of conflicted files
- `CONJURE_MERGE_CONFLICT_FILES` — space-separated list of sidecar paths

These are module-level variables in `lib/merge.sh`. Since `ws_do_update` invokes `conjure update` as a subprocess, it cannot read these variables directly. The aggregate report must capture them from stdout/stderr of the subprocess — specifically, look for `✗ Conflicts in the following files:` lines in the per-repo output, or capture the sidecar paths from `conjure update`'s printed output.

**`cmd_update` conflict output pattern** (cli/conjure lines 428–438):
```bash
if [ "${CONJURE_MERGE_CONFLICT_COUNT:-0}" -gt 0 ]; then
  echo
  echo "✗ Conflicts in the following files:"
  printf '%s\n' "$CONJURE_MERGE_CONFLICT_FILES" | while IFS= read -r sf; do
    [ -z "$sf" ] && continue
    echo "    $sf"
  done
  echo "  Resolve conflicts, delete the .conjure-conflict-* sidecars, then run:"
  echo "  echo '${CONJURE_VERSION}' > $target/.claude/.conjure-version"
  return 1
fi
```
Exit code: `return 1` on conflicts (the documented exception for update's per-repo conflict state); `return 0` on clean update; `return 2` on hard errors. `ws_do_update` treats `repo_rc=1` as "conflict" status, `repo_rc=2` as "error".

**`manifest_root` one-time resolve** (ws_do_check line 61–64):
```bash
manifest_root="$(cd "$manifest_dir" 2>/dev/null && pwd -P)" || {
  echo "✗ cannot resolve workspace root: $manifest_dir" >&2
  return 2
}
```
Copy verbatim for `ws_do_update` and `ws_do_adopt`.

---

### `scripts/workspace.sh` — `ws_do_adopt` (new function, `adopt` subcommand + saga)

**Primary analog:** `scripts/adopt.sh` `run_pipeline` + `rollback_path` functions

**Saga invariant — snapshot-all-before-apply:** The workspace saga orchestrates single-repo `snapshot_create` calls for ALL repos before invoking `conjure adopt` on ANY. This is NOT how single-repo `run_pipeline` works (it snapshots its own target inline); the workspace layer adds a dedicated phase loop.

**State machine progression** (based on adopt.sh `state_set_step` pattern, lines 127–131):
```bash
# adopt.sh state_set_step: mark a step pending/started/completed
state_set_step() {
  state_record '.steps[$step] = $status | .current_step = $step' \
    --arg step "$1" --arg status "$2"
}
```
Workspace equivalent writes to `.conjure-workspace-state.json` with the schema from CONTEXT.md:
```
{ run_id, started, phase: "snapshot"|"apply"|"done",
  repos: [ { name, snapshot_ref, sha256_pre, status: "pending"|"snapshotted"|"applied"|"failed"|"rolled_back" } ] }
```
Write state BEFORE each per-repo operation (the same SIGKILL-durability discipline as adopt.sh).

**Per-repo `conjure adopt` invocation** (mirrors the adopt.sh subprocess call pattern — argv not env):
```bash
bash "$CONJURE_HOME/cli/conjure" adopt "$repo_abs" 2>&1
```
To pass `--dry-run` or `--tag`: add as argv flags before `"$repo_abs"`.

**`_ws_cleanup` single EXIT trap** (workspace.sh lines 27–30):
```bash
_ws_cleanup() {
  rm -f "${TMPJSON:-}"
}
trap _ws_cleanup EXIT
```
Extend (do not re-register) by adding workspace-state temp file variables to `_ws_cleanup`. Never call `trap` a second time for new temp files — add them to `_ws_cleanup`'s body or to the same `TMPJSON`-style module-level variable list.

---

### `scripts/workspace.sh` — `ws_do_rollback` (new function, `adopt --rollback`)

**Primary analog:** `scripts/adopt.sh` `rollback_path` function (lines 273–402)

**No-state-file guard** (adopt.sh lines 274–278):
```bash
if [ ! -f "$STATE_PATH" ]; then
  echo "✗ adopt.sh: --rollback: no .conjure-adopt-state found — nothing to roll back" >&2
  exit 2
fi
```
Workspace equivalent: check `.conjure-workspace-state.json` at workspace root; if absent → exit 2.

**Capture-before-restore pattern** (adopt.sh lines 289–292):
```bash
# Capture created[]/mutated[] BEFORE the restore clobbers state.json
local created_list mutated_list
created_list="$(mktemp)"; mutated_list="$(mktemp)"
jq -r '.created[]?' "$STATE_PATH" > "$created_list" 2>/dev/null || true
jq -r '.mutated[]? | "\(.path)\t\(.before)"' "$STATE_PATH" > "$mutated_list" 2>/dev/null || true
```
Workspace equivalent: capture the repos array (with `snapshot_ref` and `sha256_pre`) into a temp file BEFORE any rollback modifies the state.

**Independence of per-repo rollback** (CONTEXT.md decision): unlike `adopt.sh` which exits 2 on any mismatch, workspace rollback continues per repo even if one fails. Pattern:
```bash
local repo_rb_failed=0
# for each repo in captured list:
#   snapshot_rollback "$snapshot_ref" "$repo_abs" || { log warn; repo_rb_failed=1; continue; }
#   workspace_state_write per-repo status = rolled_back
# overall exit: 0 if all succeeded, 2 if any failed
```

**Idempotent skip pattern**: before restoring a repo, check `status == "rolled_back"` in state; skip with a note. If ALL repos already `rolled_back` → exit 0 no-op.

**Archive-not-delete pattern** (CONTEXT.md): after successful rollback, archive (not delete) the state file:
```bash
local archive_name=".conjure-workspace-state-$(date -u '+%Y%m%dT%H%M%SZ').json"
mv ".conjure-workspace-state.json" "$WORKSPACE_ROOT/$archive_name"
```
Do not `rm -rf` the state file — preserves audit trail.

**Per-repo sha256 zero-diff verify loop** (adopt.sh lines 378–395):
```bash
local mismatch=0 path before got
while IFS=$'\t' read -r path before; do
  path="${path%$'\r'}"; before="${before%$'\r'}"
  [ -n "$path" ] || continue
  got="$(sha_of "$TARGET/$path")"
  if [ "$got" != "$before" ]; then
    echo "✗ adopt.sh: --rollback: sha256 mismatch after restore: $path (got=[$got] want=[$before])" >&2
    mismatch=1
  fi
done < "$mutated_list"
rm -f "$created_list" "$mutated_list"
if [ "$mismatch" -ne 0 ]; then
  echo "✗ adopt.sh: --rollback: one or more files do not match their pre-adopt hash — restore incomplete" >&2
  exit 2
fi
```
Workspace version: the `sha256_pre` is a per-repo CONTENT HASH (not per-file), so the verify loop computes `sha256sum` of the directory contents list and compares to `sha256_pre` from the state file. OR: adopt a per-file approach by recording a manifest of individual file hashes inside `snapshot_ref` at snapshot time. The planner must decide which approach — the per-file loop above is the CONTEXT.md-endorsed pattern ("mirror the Phase 22 per-file before-hash pattern").

---

### `tests/fixtures/_workspace-trio/` (new fixture)

**Analog:** `tests/fixtures/_workspace/` (existing 3-repo fixture)

**Existing fixture manifest** (`tests/fixtures/_workspace/.conjure-workspace.json`):
```json
{
  "schema_version": 1,
  "generated": "2026-06-03T00:00:00Z",
  "repos": [
    {"name": "alpha", "path": "repos/alpha", "tags": []},
    {"name": "beta",  "path": "repos/beta",  "tags": []},
    {"name": "gamma", "path": "repos/gamma", "tags": []}
  ]
}
```
**Existing repo layout:** `repos/{alpha,beta,gamma}/` each has a `CLAUDE.md` (and `.claude/` structure sufficient for `conjure check` to pass).

**What `_workspace-trio` must add over `_workspace`:** Each member repo must be adoptable (have enough content that `snapshot_create` takes measurable time, so the SIGKILL window is reliably catchable). The repos should NOT have a pre-existing `.conjure-adopt-state/` so they run the full pipeline on each test. They must be small enough (no `node_modules`, no `.git` objects) to satisfy the snapshot-all-before-apply discipline within seconds. Gamma-bad from the existing fixture shows the bad-path pattern — `_workspace-trio` may not need that variant.

---

### `tests/run.sh` — Phase 30 SIGKILL saga block

**Primary analog:** Phase 24 SIGKILL block (tests/run.sh lines 3470–3564) + Phase 22 rollback block (lines 2580–2632)

**Background-launch + bounded-poll + kill pattern** (Phase 24, lines 3491–3518):
```bash
# Relaunch loop: catch the kill strictly AFTER snapshot, BEFORE apply.
P30_SK_INWINDOW=0
for _attempt in 1 2 3; do
  DRY_RUN=0 CONJURE_HOME="$CONJURE_HOME" \
    bash "$CONJURE_HOME/scripts/workspace.sh" adopt "$WS_MANIFEST" >/dev/null 2>&1 &
  P30_SK_PID=$!
  # Bounded poll on workspace-state.json .phase field
  P30_SK_LASTPHASE=""
  for _i in $(seq 1 200); do
    _phase="$(jq -r '.phase // ""' "$WS_ROOT/.conjure-workspace-state.json" 2>/dev/null || true)"
    [ -n "$_phase" ] && P30_SK_LASTPHASE="$_phase"
    case "$_phase" in snapshot) break ;; esac
    kill -0 "$P30_SK_PID" 2>/dev/null || break
    sleep 0.05
  done
  kill -9 "$P30_SK_PID" 2>/dev/null || true
  wait "$P30_SK_PID" 2>/dev/null || true
  case "$P30_SK_LASTPHASE" in
    snapshot) P30_SK_INWINDOW=1; break ;;
    *)
      rm -rf "$WS_ROOT/.conjure-workspace-state.json"
      # reset per-repo adopt-state dirs and restore from PRE copy
      ;;
  esac
done
```
The poll condition differs from Phase 24: workspace polls `.phase == "snapshot"` in `.conjure-workspace-state.json` (not `.current_step` in a per-repo `state.json`).

**Per-file sha256 before-hash recording loop** (Phase 22, lines 2586–2589):
```bash
# Record sha256 of every pre-adopt file (relative paths) for per-file verify.
( cd "$P30_WS_ROOT" && find . -type f -not -path './.git/*' | sort | while IFS= read -r f; do
    printf '%s  %s\n' "$(p30_sha "$f")" "$f"
  done ) > "$P30_RB_HASHES" 2>/dev/null
```
At workspace scale: run this loop PER REPO, writing one hash file per repo, stored OUTSIDE the repo trees. Use `mktemp` files outside `$WS_ROOT`.

**Zero-diff assertion loop** (Phase 22, lines 2597–2606):
```bash
P30_RB_MISMATCH=0
while IFS= read -r line; do
  [ -n "$line" ] || continue
  _h="${line%%  *}"; _f="${line##*  }"
  _now="$(p30_sha "$REPO_ABS/$_f" 2>/dev/null || echo MISSING)"
  [ "$_h" = "$_now" ] || P30_RB_MISMATCH=$((P30_RB_MISMATCH+1))
done < "$P30_RB_HASHES"
```
Run per repo after `--rollback`, summing mismatches across all repos.

**diff -r zero-diff pattern** (Phase 22, lines 2622–2629):
```bash
P30_RB_DIFF="$(diff -r \
  -x '.conjure-adopt-backups' -x '.conjure-archive-*' \
  -x 'RESTRUCTURE-LOG.md' -x 'adopt-manifest.json' -x '.conjure-adopt-state' \
  "$PRE_COPY" "$REPO_ABS" 2>&1)"
if [ -z "$P30_RB_DIFF" ]; then
  pass "workspace rollback: diff -r pre vs post-rollback empty (excl. conjure dirs)"
fi
```
Run per repo; the `-x` exclusions stay the same as Phase 22/24 (conjure's own dirs).

**sha helper definition** (adopt.sh lines 63–73):
```bash
sha_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" 2>/dev/null | cut -d' ' -f1 | tr -d '\r'
  else
    shasum -a 256 "$1" 2>/dev/null | cut -d' ' -f1 | tr -d '\r'
  fi
}
```
Copy verbatim into the Phase 30 test block as `p30_sha` (or reuse the `p22_sha` local alias pattern already used in tests/run.sh).

---

### `cli/conjure` `cmd_workspace` — extend with `update` and `adopt` tokens

**Analog:** `cli/conjure` `cmd_workspace` (lines 573–589)

**Current dispatch** (lines 580–585):
```bash
while [ $# -gt 0 ]; do
  case "$1" in
    init|check|audit) subcmd="$1"; shift; break ;;
    --dry-run)        dryrun=1; shift ;;
    --help|-h)        echo "Usage: conjure workspace init|check|audit [args]"; return 0 ;;
    *)                break ;;
  esac
done
[ -z "$subcmd" ] && { echo "Usage: conjure workspace init|check|audit" >&2; return 2; }
CONJURE_HOME="$CONJURE_HOME" DRY_RUN="$dryrun" \
  bash "$CONJURE_HOME/scripts/workspace.sh" "$subcmd" "$@"
```

**Extension pattern:** Add `update|adopt` to the subcommand token list. The remainder (`"$@"`) is forwarded verbatim — `--tag`, `--rollback`, `--dry-run`, `--allow-large-snapshots`, `--continue-on-error` all parse inside `workspace.sh`'s subcommand branches, not in `cmd_workspace`. This is the Phase 29 lesson: forward `"$@"` without stripping flags.

**Non-TTY consent guard for mutating ops** (mirrors `workspace init` non-TTY pattern, workspace.sh lines 287–292):
```bash
# Non-TTY guard: require --yes in non-interactive environments
if [ "$YES" -eq 0 ]; then
  if ! [ -t 0 ]; then
    echo "✗ Not a TTY. Use --yes for non-interactive environments." >&2
    exit 2
  fi
fi
```
Apply the same guard inside `ws_do_adopt` and `ws_do_update` (mutating ops) when not in `--dry-run` mode. Read from `/dev/tty` for consent prompts.

---

## Shared Patterns

### Atomic State Write (jq > tmp + mv)
**Source:** `scripts/adopt.sh` lines 76–101 (`state_record`)
**Apply to:** `lib/workspace.sh` `workspace_state_write`, every per-repo state transition in `ws_do_adopt`, `ws_do_rollback`
```bash
local tmp="${STATE_PATH}.tmp.$$"
if jq "$@" "$filter" "$STATE_PATH" > "$tmp" 2>/dev/null; then
  mv "$tmp" "$STATE_PATH"
else
  rm -f "$tmp"
  echo "✗ failed to update state at $STATE_PATH" >&2
  exit 2
fi
```

### Traversal Re-check (execution-time, CR-02)
**Source:** `scripts/workspace.sh` `ws_do_check` lines 83–97
**Apply to:** `ws_do_adopt` (per repo, before snapshot AND before apply), `ws_do_update` (per repo)
```bash
repo_real="$(cd "$repo_abs" 2>/dev/null && pwd -P)" || { ... skip ... }
case "$repo_real" in
  "$manifest_root"|"$manifest_root/"*) ;;
  *) printf '  ⚠ SECURITY: skipping %s: escapes workspace root\n' "$repo_name" >&2; continue ;;
esac
```

### Single EXIT Trap (extend, never re-register)
**Source:** `scripts/workspace.sh` lines 27–30
**Apply to:** All new temp files introduced by Phase 30 functions — add them to `_ws_cleanup`, do not add a new `trap ... EXIT` call.
```bash
_ws_cleanup() {
  rm -f "${TMPJSON:-}" "${TMPERR:-}" "${WS_STATE_TMP:-}"
}
trap _ws_cleanup EXIT  # registered once at script startup
```

### sha256 Helper (cross-platform)
**Source:** `scripts/adopt.sh` lines 63–73 (`sha_of`)
**Apply to:** `ws_do_adopt` (per-repo `sha256_pre` recording), `ws_do_rollback` (zero-diff verify), Phase 30 test block
```bash
sha_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" 2>/dev/null | cut -d' ' -f1 | tr -d '\r'
  else
    shasum -a 256 "$1" 2>/dev/null | cut -d' ' -f1 | tr -d '\r'
  fi
}
```

### DRY_RUN Zero-Write Contract
**Source:** `scripts/adopt.sh` lines 692–697, `lib/snapshot.sh` lines 24–27
**Apply to:** `ws_do_adopt --dry-run`, `ws_do_update --dry-run` (if added)
- `DRY_RUN=1`: print `[dry-run] would ...` and return 0 WITHOUT touching any file under the target.
- Preflight checks (path-traversal, disk estimate) still execute.
- State file is NOT written.
- `snapshot_create` already handles `DRY_RUN=1` internally (prints would-be path, returns 0).

### Exit-2-Never-Exit-1 (except documented aggregates)
**Source:** Project convention (CLAUDE.md), documented in `scripts/workspace.sh` header comments
**Apply to:** All new Phase 30 subcommand functions
- `ws_do_adopt`, `ws_do_rollback`: exit 2 on any hard error.
- `ws_do_update`: exit 2 on hard error; exit 1 ONLY for the documented aggregate partial-success (some repos conflicted, some clean) — mirror the Phase 29 `check`/`audit` documented exception.
- Per-repo ops invoked via subprocess; their exit codes are captured, not propagated directly.

### `/dev/tty` Consent Gate (mutating ops, non-TTY)
**Source:** `scripts/workspace.sh` `init` subcommand lines 287–292, `scripts/adopt.sh` `recovery_prompt` lines 410–423
**Apply to:** `ws_do_adopt` and `ws_do_update` when `--yes` not passed and not `--dry-run`
```bash
if [ "$YES" -eq 0 ] && ! [ -t 0 ]; then
  echo "✗ Not a TTY. Use --yes for non-interactive environments." >&2
  exit 2
fi
```

---

## No Analog Found

| File / Feature | Role | Data Flow | Reason |
|----------------|------|-----------|--------|
| Disk-space estimate (`du`-based, `--allow-large-snapshots`) | utility inline | transform | No `du` usage exists anywhere in the codebase. Net-new. Use `du -sk "$repo_abs" 2>/dev/null \| awk '{print $1}'` to get KiB; sum across repos; compare to 2097152 (2 GiB in KiB). Warn and `exit 2` unless `ALLOW_LARGE_SNAPSHOTS=1`. |

---

## Key Structural Mismatches the Planner Must Bridge

1. **State-file scope mismatch:** `scripts/adopt.sh` state lives in `$TARGET/.conjure-adopt-state/state.json` (a DIRECTORY per repo). The workspace state lives at `$WORKSPACE_ROOT/.conjure-workspace-state.json` (a single JSON file at the workspace root). The atomic-write idiom is identical; the location and schema differ. `workspace_state_write` must NOT mkdir a directory — it writes directly to the `.json` file.

2. **snapshot_guarded vs snapshot_create:** `adopt.sh` uses `snapshot_guarded` (a wrapper that moves prior backups to a temp dir to prevent self-copy). For workspace adopt, each repo's backup lives inside THAT REPO's `.conjure-adopt-backups/` (not the workspace root). The workspace orchestrator calls `snapshot_create` (or `snapshot_guarded`) per repo against that repo's own backup root. The orchestrator does NOT manage a workspace-level backup root.

3. **per-repo `sha256_pre` granularity:** CONTEXT.md says "per-repo content sha256 manifest" (a manifest of individual file hashes, not a single directory hash). This mirrors Phase 22's per-file hash loop. The workspace state stores `sha256_pre` as a reference to the per-file hash file — not an inline string. Planner must decide: store the hash-file path as `sha256_pre_ref` in the state, or bake a directory-level hash. Per the CONTEXT.md "mirror the Phase 22 per-file before-hash pattern" decision, a per-file hash file is preferred.

4. **Rollback independence vs single-repo abort-on-mismatch:** `adopt.sh` `rollback_path` exits 2 on the first sha256 mismatch. `ws_do_rollback` continues per repo even if one fails (`continue` not `exit 2`). Track `repo_rb_rc` per repo, set a global `any_failed` flag, and exit 2 at the end if any repo failed — never exit mid-loop.

5. **`conjure adopt` subprocess vs inline saga:** The workspace orchestrator does NOT call `conjure adopt` as a black-box subprocess for the saga. Instead, it calls `snapshot_create` per repo directly (for the snapshot-all-first phase), then calls `bash "$CONJURE_HOME/cli/conjure" adopt "$repo_abs"` for the apply phase. If the adopt subprocess uses its OWN `adopt.sh` state, the workspace state and the per-repo state coexist without conflict — they live at different paths.

---

## Metadata

**Analog search scope:** `scripts/`, `lib/`, `cli/conjure`, `tests/run.sh`, `tests/fixtures/_workspace*/`
**Files scanned:** 8 source files + 1 test file (~6221 lines) + fixture directories
**Pattern extraction date:** 2026-06-04
