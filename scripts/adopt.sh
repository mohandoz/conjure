#!/usr/bin/env bash
# scripts/adopt.sh — conjure adopt pipeline orchestrator.
#
# Wires the Phase 21 primitives (snapshot/inventory/log/mutate/caps) into a
# complete, audited, snapshot-backed adoption run:
#   preconditions → snapshot → inventory → scaffold → audit → report
#
# Three genuinely-new pieces of logic live here (everything else is orchestrated):
#   - .conjure-adopt-state/ crash-durable step manifest (atomic jq>tmp+mv)
#   - INT/TERM signal trap (SIGKILL handled by write-before-step durability)
#   - dirty-tree precondition gate (git status --porcelain; exit 2 / --force)
#
# Usage: [CONJURE_HOME=<path>] [DRY_RUN=1] [CONJURE_ADOPT_*=...] bash adopt.sh [target]
# Exit codes: 0 = success, 2 = hard failure / non-TTY recovery / dirty-tree refusal.
# NEVER exit 1 (project convention — log_fail / hard failures use exit 2).
set -uo pipefail

CONJURE_HOME="${CONJURE_HOME:-$(cd "$(dirname "$0")/.." && pwd)}"

# Resolve TARGET. The flag contract is carried by CONJURE_ADOPT_* env vars (set by
# cmd_adopt), but callers (and tests) may also pass the flags positionally. Skip
# any leading flag tokens — and the value that follows --apply-step — so the first
# bare positional is the target. Defaults to $(pwd) when none is given.
TARGET="$(pwd)"
while [ $# -gt 0 ]; do
  case "$1" in
    --apply-step) shift ;;                         # consume its value token too
    --*) ;;                                        # ignore other flags (env carries them)
    *) TARGET="$1" ;;
  esac
  shift
done

# Source the five Phase 21 libs in dependency order: mutate first (everything
# depends on it), then caps/log, then snapshot/inventory (which require mutate+log).
# shellcheck source=/dev/null
source "$CONJURE_HOME/lib/mutate.sh"    || { echo "adopt.sh: cannot source lib/mutate.sh" >&2; exit 2; }
# shellcheck source=/dev/null
source "$CONJURE_HOME/lib/caps.sh"      || { echo "adopt.sh: cannot source lib/caps.sh" >&2; exit 2; }
# shellcheck source=/dev/null
source "$CONJURE_HOME/lib/log.sh"       || { echo "adopt.sh: cannot source lib/log.sh" >&2; exit 2; }
# shellcheck source=/dev/null
source "$CONJURE_HOME/lib/snapshot.sh"  || { echo "adopt.sh: cannot source lib/snapshot.sh" >&2; exit 2; }
# shellcheck source=/dev/null
source "$CONJURE_HOME/lib/inventory.sh" || { echo "adopt.sh: cannot source lib/inventory.sh" >&2; exit 2; }

# .conjure-adopt-state is a DIRECTORY (per D-07's literal staging/<file> path and
# RESEARCH Open Question 1): state.json + staging/ live inside it.
STATE_DIR="$TARGET/.conjure-adopt-state"
STATE_PATH="$STATE_DIR/state.json"
# STAGING_DIR holds skill-proposed content (D-07); consumed by the Wave 2
# --apply-step executor. Declared here so the layout is one source of truth.
# shellcheck disable=SC2034
STAGING_DIR="$STATE_DIR/staging"
BACKUP_ROOT="$TARGET/.conjure-adopt-backups"
MANIFEST_PATH="$TARGET/adopt-manifest.json"

# SAFE-05: graceful INT/TERM handling. SIGKILL is untrappable — durability
# (write state BEFORE each mutating step) is what makes kill -9 recovery work.
trap 'echo "interrupted — partial state at $STATE_DIR; recover with --rollback | --resume | --start-fresh" >&2; exit 2' INT TERM

# ── sha256 helper (cross-platform; exact mutate.sh 113-123 pattern) ───────────
sha_of() {
  # tr -d '\r': on Windows Git Bash (MSYS) the coreutils sha256sum can emit a
  # CR before the line terminator; an unstripped \r poisons every later string
  # compare (recorded before-hash vs verify-hash) and fabricates a rollback
  # mismatch on an unchanged file. No-op on macOS/Linux (no CR to strip).
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" 2>/dev/null | cut -d' ' -f1 | tr -d '\r'
  else
    shasum -a 256 "$1" 2>/dev/null | cut -d' ' -f1 | tr -d '\r'
  fi
}

# ── atomic state writes (SAFE-04, Pitfall 2: jq>tmp+mv same-dir rename) ───────
# state_record <jq-filter> [args...]
# Applies <jq-filter> to the current state.json (or builds it with jq -n on first
# write) and atomically replaces it via a same-dir temp file. Extra args are
# passed through to jq (--arg/--argjson). Never truncates state on a crash.
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

# state_init — write the first state.json record (schema_version, target, steps).
state_init() {
  local started_at
  started_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  state_record '{
      schema_version: "1",
      started_at: $started_at,
      target: $target,
      snapshot_path: "",
      current_step: "preconditions",
      steps: {
        preconditions: "pending",
        snapshot: "pending",
        inventory: "pending",
        scaffold: "pending",
        audit: "pending"
      },
      created: [],
      mutated: []
    }' \
    --arg started_at "$started_at" \
    --arg target "$(cd "$TARGET" && pwd)"
}

# state_set_step <step> <status> — mark a step pending/started/completed and set current_step.
state_set_step() {
  state_record '.steps[$step] = $status | .current_step = $step' \
    --arg step "$1" --arg status "$2"
}

# state_set_snapshot <path> — record the snapshot dir for recovery/rollback.
state_set_snapshot() {
  state_record '.snapshot_path = $p' --arg p "$1"
}

# state_add_created <rel_path> — append a scaffolded harness path to created[] (D-02).
state_add_created() {
  state_record '.created += [$p]' --arg p "$1"
}

# state_add_mutated <rel_path> <before_sha> <after_sha> — record a mutated file (SAFE-04).
state_add_mutated() {
  state_record '.mutated += [{path: $p, before: $b, after: $a}]' \
    --arg p "$1" --arg b "$2" --arg a "$3"
}

# state_set_last_mutated_after <after_sha> — finalize the after-hash of the most
# recently appended mutated[] entry (WR-01: intent recorded with "pending" before
# the mutation, after-hash written once the write completes).
state_set_last_mutated_after() {
  state_record '.mutated[-1].after = $a' --arg a "$1"
}

# ── dirty-tree precondition (Step 0, ADOPT-03 + SAFE-06, Pitfall 5) ───────────
# git status --porcelain: empty = clean (catches tracked-modified AND untracked).
# dirty && !force → exit 2 (never exit 1). dirty && force → log_step WARN + echo.
# non-git target (porcelain errors) → skip the gate with a note (snapshot works).
precondition_git() {
  if ! git -C "$TARGET" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "preconditions: not a git repo — skipping dirty-tree gate (snapshot still backs up the filesystem)"
    return 0
  fi
  # Ignore conjure's OWN in-flight artifacts: log_init may have already written
  # RESTRUCTURE-LOG.md, and a prior/interrupted run may have left .conjure-adopt-state,
  # .conjure-adopt-backups, .conjure-archive-*, or adopt-manifest.json. These are NOT
  # the user's uncommitted work — a clean USER tree must pass the gate even though
  # conjure has touched the directory. (Without this filter, a clean committed repo is
  # wrongly reported dirty on the first run because log_init runs before this gate.)
  local dirty
  dirty="$(git -C "$TARGET" status --porcelain 2>/dev/null \
    | grep -vE '(RESTRUCTURE-LOG\.md|adopt-manifest\.json|\.conjure-adopt-state|\.conjure-adopt-backups|\.conjure-archive-)' \
    || true)"
  if [ -n "$dirty" ]; then
    if [ "${CONJURE_ADOPT_FORCE:-0}" != "1" ]; then
      echo "✗ preconditions: working tree is dirty — commit/stash first, or pass --force" >&2
      exit 2
    fi
    log_step WARN "--force on dirty tree; uncommitted changes are in the snapshot. --rollback restores from snapshot, NOT git."
    echo "⚠ --force: uncommitted changes included in snapshot (rollback is snapshot-based, not git)"
  else
    echo "preconditions: git clean ✓"
  fi
}

# ── Pitfall 3 self-copy guard (snapshot outside target, then relocate) ────────
# snapshot_create does `cp -a target/. snap_dir/` and `snap_dir` is normally
# INSIDE target ($BACKUP_ROOT). Because mkdir -p creates snap_dir before the copy,
# `target/.` includes the destination → macOS `cp -a` recurses infinitely
# ("File name too long") and any prior .conjure-adopt-backups gets nested too.
# Orchestrator-level fix (no lib change, RESEARCH Open Question 2): snapshot into
# a temp root OUTSIDE the target, then relocate the snapshot dir into the
# in-target $BACKUP_ROOT. The raw cp then never sees its own destination, and any
# prior backups already excluded by inventory are simply not re-copied because the
# destination lives outside the copied tree. Final layout matches D-02/D-03/D-04
# (backups live in the target). Sets CONJURE_SNAPSHOT_PATH to the final in-target path.
snapshot_guarded() {
  if [ "${DRY_RUN:-0}" = "1" ]; then
    # Dry-run: lib prints the would-be path and writes nothing. Point it at the
    # final in-target location so the plan reads correctly.
    snapshot_create "$TARGET" "$BACKUP_ROOT"
    return 0
  fi
  # Temporarily move any prior in-target backups aside so they are NOT inside the
  # copied tree (defense-in-depth; the temp-root copy already avoids self-copy).
  local stash=""
  if [ -d "$BACKUP_ROOT" ]; then
    stash="$(mktemp -d)"
    mv "$BACKUP_ROOT" "$stash/backups"
  fi
  local tmp_backup_root
  tmp_backup_root="$(mktemp -d)"
  snapshot_create "$TARGET" "$tmp_backup_root"
  # Relocate the freshly-created snapshot dir into the in-target backup root.
  mkdir -p "$BACKUP_ROOT"
  local snap_name
  snap_name="$(basename "$CONJURE_SNAPSHOT_PATH")"
  mv "$CONJURE_SNAPSHOT_PATH" "$BACKUP_ROOT/$snap_name"
  CONJURE_SNAPSHOT_PATH="$BACKUP_ROOT/$snap_name"
  rm -rf "$tmp_backup_root"
  # Restore prior backups alongside the new one (preserve snapshot history, D-04).
  if [ -n "$stash" ] && [ -d "$stash/backups" ]; then
    local entry
    for entry in "$stash/backups"/*; do
      [ -e "$entry" ] || continue
      [ -e "$BACKUP_ROOT/$(basename "$entry")" ] && continue
      mv "$entry" "$BACKUP_ROOT/"
    done
  fi
  [ -n "$stash" ] && rm -rf "$stash"
}

# ── adoption report (Step 5, ADOPT-06 / D-09) ─────────────────────────────────
# Labeled plain-text sections + a before/after delta block (echo lines, no deps).
report() {
  local before_lines="$1" after_lines="$2"
  local inv_total inv_unknown created_count
  inv_total="0"; inv_unknown="0"; created_count="0"
  if [ -f "$REPORT_MANIFEST" ]; then
    inv_total="$(jq -r '.summary.total_files // 0' "$REPORT_MANIFEST" 2>/dev/null || echo 0)"
    inv_unknown="$(jq -r '.summary.unknown // 0' "$REPORT_MANIFEST" 2>/dev/null || echo 0)"
  fi
  if [ -f "$STATE_PATH" ]; then
    created_count="$(jq -r '.created | length' "$STATE_PATH" 2>/dev/null || echo 0)"
  fi
  echo
  echo "Adoption report"
  echo "  Inventory:   ${inv_total} files (${inv_unknown} unknown)"
  echo "  Scaffolded:  ${created_count} layer files"
  [ "${created_count:-0}" -eq 0 ] && echo "  Scaffolded:  nothing to scaffold"  # O-1: emit ROADMAP criterion-3 literal phrase on a zero-scaffold (idempotent) re-run
  echo "  Archived:    ${ARCHIVED_COUNT:-0} files"
  echo "  CLAUDE.md:   ${before_lines} → ${after_lines} lines (cap ${CLAUDE_MD_CAP:-100})"
  echo "  Snapshot:    ${CONJURE_SNAPSHOT_PATH:-(dry-run)}"
  echo "  Audit:       before rc=${AUDIT_BEFORE_RC:-NA} → after rc=${AUDIT_AFTER_RC:-NA}"
  echo "  Next:        open Claude Code → run the restructure skill"
  echo "  Note:        --rollback restores from the filesystem snapshot, NOT git (SAFE-06)"
}

# ── rollback (D-01: 3-step full-restore-plus-delete-created → zero-diff) ──────
# D-01 exactly: (1) snapshot_rollback whole-tree restore (un-archives originals +
# restores mutated, since both live in the snapshot); (2) mutate_rm every created[]
# path (scaffolded harness files the snapshot can't undo — D-02 keeps conjure's own
# dirs out of created[]); (3) sha256(p)==before for every mutated[] path. Then
# log_step ROLLBACK and delete ONLY .conjure-adopt-state (D-04 keeps snapshot/
# archive/log). Yields Phase 24's sha256-identical before/after (D-03 scope).
#
# CRITICAL ordering (CR-2-adjacent): the snapshot was taken at the "snapshot" step,
# BEFORE scaffold, so it carries a STALE state.json with an empty created[]. The
# whole-tree restore overwrites the live state.json with that stale copy — so
# created[]/mutated[] MUST be captured into temp files BEFORE the restore, or the
# delete-created + verify loops read the wrong (emptied) arrays.
rollback_path() {
  if [ ! -f "$STATE_PATH" ]; then
    echo "✗ adopt.sh: --rollback: no .conjure-adopt-state found — nothing to roll back" >&2
    exit 2
  fi
  local snap
  snap="$(jq -r '.snapshot_path // ""' "$STATE_PATH" 2>/dev/null)"
  if [ -z "$snap" ] || [ ! -d "$snap" ]; then
    echo "✗ adopt.sh: --rollback: no snapshot recorded at '${snap:-(none)}' — nothing to restore" >&2
    exit 2
  fi

  # D-15 / SAFE-06: surface that rollback restores from the FILESYSTEM snapshot, not git.
  echo "⚠ --rollback restores from the filesystem snapshot at $snap — NOT from git (SAFE-06)"

  # Capture created[]/mutated[] BEFORE the restore clobbers state.json (see header note).
  local created_list mutated_list
  created_list="$(mktemp)"; mutated_list="$(mktemp)"
  jq -r '.created[]?' "$STATE_PATH" > "$created_list" 2>/dev/null || true
  jq -r '.mutated[]? | "\(.path)\t\(.before)"' "$STATE_PATH" > "$mutated_list" 2>/dev/null || true

  # WR-03 (SAFE-07 / D-04): the snapshot was taken at the "snapshot" step, so its
  # copy of RESTRUCTURE-LOG.md holds only the header + SNAPSHOT entry. The whole-tree
  # restore below would overwrite the LIVE log (carrying the full forward-run
  # INVENTORY/SCAFFOLD/AUDIT trail) with that stale copy, and the ROLLBACK entry would
  # then append to the truncated file — losing the durable audit history D-04 says to
  # preserve. Capture the live log aside (like created_list/mutated_list) and restore
  # it after the snapshot restore, so the trail stays [forward entries] ... [ROLLBACK].
  local log_preserved=""
  if [ -f "$TARGET/RESTRUCTURE-LOG.md" ]; then
    log_preserved="$(mktemp)"
    cp "$TARGET/RESTRUCTURE-LOG.md" "$log_preserved"
  fi

  # Set the log path so snapshot_rollback auto-logs ROLLBACK and our log_step lands here.
  RESTRUCTURE_LOG_PATH="$TARGET/RESTRUCTURE-LOG.md"

  # 3-point sha256 diagnostic (quiet; CONJURE_ADOPT_ROLLBACK_DIAG=1 -> stderr only).
  # Pin EXACTLY where a CLAUDE.md byte-divergence enters the snapshot<->restore path
  # on Windows Git Bash (cannot reproduce locally -- surfaces on the windows-test log):
  #   (a) live target right before restore (== bytes recorded as the before-hash)
  #   (b) the snapshot's OWN copy (snap/CLAUDE.md)
  #   (c) restored target after snapshot_rollback (printed below, post-restore)
  # (a)!=(b) => tar CREATE corrupts; (b)!=(c) => tar RESTORE corrupts; all equal =>
  # corruption is elsewhere. No-op unless the diag flag is set.
  if [ "${CONJURE_ADOPT_ROLLBACK_DIAG:-0}" = "1" ]; then
    [ -f "$TARGET/CLAUDE.md" ] && printf '  [diag] sha CLAUDE.md (a) live-pre-restore = %s\n' "$(sha_of "$TARGET/CLAUDE.md")" >&2
    [ -f "$snap/CLAUDE.md" ]   && printf '  [diag] sha CLAUDE.md (b) snapshot-copy    = %s\n' "$(sha_of "$snap/CLAUDE.md")" >&2
  fi

  # Step 1: whole-tree restore (restores mutated files + un-archives originals).
  if ! snapshot_rollback "$snap" "$TARGET"; then
    echo "✗ adopt.sh: --rollback: snapshot restore failed from $snap" >&2
    rm -f "$created_list" "$mutated_list"
    [ -n "$log_preserved" ] && rm -f "$log_preserved"
    exit 2
  fi
  # WR-03: restore the live forward-run log over the stale snapshot copy so the
  # ROLLBACK entry (appended below) continues the full trail, not the truncated one.
  if [ -n "$log_preserved" ]; then
    cp "$log_preserved" "$TARGET/RESTRUCTURE-LOG.md"
    rm -f "$log_preserved"
  fi
  # The snapshot dir carries a .snapshot-meta.json at its root; cp -a snapshot/.
  # leaks it into the target root. Remove it so the post-rollback tree is clean (D-03).
  rm -f "$TARGET/.snapshot-meta.json"

  # 3-point diag (c): restored target after snapshot_rollback. Compare to (a)/(b) above.
  if [ "${CONJURE_ADOPT_ROLLBACK_DIAG:-0}" = "1" ]; then
    [ -f "$TARGET/CLAUDE.md" ] && printf '  [diag] sha CLAUDE.md (c) restored-target = %s\n' "$(sha_of "$TARGET/CLAUDE.md")" >&2
  fi

  # Step 2: delete every scaffolded created[] path (D-02), then prune any directory
  # that became empty AND is not present in the snapshot (scaffold-created dirs the
  # snapshot can't account for) — keeps the post-rollback tree byte-identical (D-03).
  local created_count=0 p
  while IFS= read -r p; do
    p="${p%$'\r'}"
    [ -n "$p" ] || continue
    mutate_rm "$TARGET/$p"
    created_count=$((created_count + 1))
  done < "$created_list"
  # NOTE: the prior per-file `rm -f` orphan net (e.g. .claude/COMPOUND-CANDIDATES.md)
  # is gone. created[] is now populated authoritatively from init-project.sh's emitted
  # manifest (CONJURE_CREATED_MANIFEST), which records every file it scaffolds —
  # including the gitignored COMPOUND-CANDIDATES.md — so the step-2 loop above already
  # deletes them. The Windows find/comm lossiness that made the band-aid necessary no
  # longer feeds created[]; the manifest is separator/locale-independent.
  # Bottom-up empty-dir prune (longest paths first). Only remove dirs absent from the
  # snapshot — any original dir (even if it ended up empty) lives in the snapshot and
  # is preserved. rmdir is a no-op on non-empty dirs, so this never deletes content.
  local d rel
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    [ "$d" = "$TARGET" ] && continue
    rel="${d#"$TARGET"/}"
    [ -d "$snap/$rel" ] && continue
    rmdir "$d" 2>/dev/null || true
  done < <(find "$TARGET" -type d \
              -not -path "$TARGET/.conjure-adopt-backups*" \
              -not -path "$TARGET/.conjure-archive-*" \
              -not -path "$TARGET/.conjure-adopt-state*" \
              2>/dev/null | awk '{ print length, $0 }' | sort -rn | cut -d' ' -f2-)

  # Step 3: verify every mutated[] file's sha256 == recorded before-hash (SAFE-02).
  local mismatch=0 path before got
  while IFS=$'\t' read -r path before; do
    # Strip any MSYS-injected CR from the tab-split fields (Windows Git Bash).
    path="${path%$'\r'}"; before="${before%$'\r'}"
    [ -n "$path" ] || continue
    got="$(sha_of "$TARGET/$path")"
    if [ "$got" != "$before" ]; then
      # Bracket-delimited values surface trailing CR/whitespace vs a real byte
      # divergence on the windows-test log (cannot reproduce locally).
      echo "✗ adopt.sh: --rollback: sha256 mismatch after restore: $path (got=[$got] want=[$before])" >&2
      mismatch=1
    fi
  done < "$mutated_list"
  rm -f "$created_list" "$mutated_list"
  if [ "$mismatch" -ne 0 ]; then
    echo "✗ adopt.sh: --rollback: one or more files do not match their pre-adopt hash — restore incomplete" >&2
    exit 2
  fi

  log_step ROLLBACK "restored from $snap; deleted $created_count created path(s)"
  # D-04: keep snapshot/archive/RESTRUCTURE-LOG.md; delete ONLY the state dir so a
  # stale state file never triggers a false recovery prompt on the next run.
  rm -rf "$STATE_DIR"
  echo "✓ rollback complete — restored from snapshot, removed $created_count scaffolded file(s)"
}

# ── partial-run recovery (D-12/D-13/D-14, SAFE-05) ────────────────────────────
# recovery_prompt <last_step>: invoked when a prior partial .conjure-adopt-state is
# detected with no explicit recovery flag. Non-TTY callers never reach here (the
# mode dispatch exits 2 with the flag list first, D-13). In a TTY (or with the
# CONJURE_FORCE_INTERACTIVE escape hatch) loop the [r]/[c]/[s] prompt reading from
# /dev/tty, with NO default — unknown/empty input re-prompts (D-14).
recovery_prompt() {
  local last_step="${1:-unknown}"
  echo "conjure adopt: partial run detected (last completed: $last_step)" >&2
  local choice
  while true; do
    read -r -p "  [r]ollback / [c]ontinue / [s]tart-fresh: " choice < /dev/tty
    case "$choice" in
      r|rollback)    rollback_path; break ;;
      c|continue)    resume_pipeline; break ;;
      s|start-fresh) rm -rf "$STATE_DIR"; run_pipeline; break ;;
      *)             echo "  enter r, c, or s" ;;   # D-14: no default; empty re-prompts
    esac
  done
}

# resume_pipeline (= --resume, and the [c]ontinue choice; D-12): continue at the
# first incomplete step REUSING the existing snapshot dir. Phase 22's forward
# pipeline is short and its mutating steps are idempotent (init-project.sh never
# overwrites, inventory/audit re-emit cleanly), so resume re-enters run_pipeline
# with CONJURE_ADOPT_REUSE_SNAPSHOT=1 — run_pipeline then skips snapshot_guarded and
# reuses the recorded snapshot_path instead of creating a second backup (CR-2).
resume_pipeline() {
  if [ ! -f "$STATE_PATH" ]; then
    echo "✗ adopt.sh: --resume: no .conjure-adopt-state to resume from" >&2
    exit 2
  fi
  export CONJURE_ADOPT_REUSE_SNAPSHOT=1
  run_pipeline
}

# ── op-executor: the Phase 23 skill seam (D-05/06/07/08) ──────────────────────
# manifest_write_atomic <jq-filter> [jq args...]: apply <jq-filter> to the manifest
# and atomically replace it via a same-dir temp file (Pitfall 2 — never truncate).
manifest_write_atomic() {
  local filter="$1"; shift
  local tmp="$MANIFEST_PATH.tmp.$$"
  if jq "$@" "$filter" "$MANIFEST_PATH" > "$tmp" 2>/dev/null; then
    mv "$tmp" "$MANIFEST_PATH"
  else
    rm -f "$tmp"
    echo "✗ adopt.sh: failed to update manifest at $MANIFEST_PATH" >&2
    exit 2
  fi
}

# update_manifest (D-06, inbound half): read a proposed op as JSON from --step-json
# <json> or stdin, jq-validate it has id/op/status (malformed → exit 2, NEVER
# executed — T-22-11), and append it to restructure_steps[] via injection-safe
# --argjson (no shell string interpolation into JSON). This is how the Phase 23
# skill writes proposals; --apply-step is the outbound half that consumes them.
update_manifest() {
  if [ ! -f "$MANIFEST_PATH" ]; then
    echo "✗ adopt.sh: --update-manifest: no adopt-manifest.json at $MANIFEST_PATH (run inventory first)" >&2
    exit 2
  fi
  # Source the step JSON: explicit arg ($CONJURE_ADOPT_STEP_JSON) wins, else stdin.
  local step_json="${CONJURE_ADOPT_STEP_JSON:-}"
  if [ -z "$step_json" ]; then
    step_json="$(cat)"
  fi
  if [ -z "$step_json" ]; then
    echo "✗ adopt.sh: --update-manifest: no step JSON provided (pass via stdin or CONJURE_ADOPT_STEP_JSON)" >&2
    exit 2
  fi
  # Parse-check + required-fields {id, op, status} (RESEARCH Open Q3 validation depth).
  # WR-05: also assert op ∈ {write, archive, extract} at write time (defense in depth
  # on the inbound half — apply_step enforces it again on the outbound half, but a
  # persisted invalid op is a latent confusion for the Phase 23 skill + schema checks).
  if ! printf '%s' "$step_json" | jq -e '
      type == "object" and has("id") and has("op") and has("status")
      and (.op == "write" or .op == "archive" or .op == "extract")' >/dev/null 2>&1; then
    echo "✗ adopt.sh: --update-manifest: malformed step — requires {id, op∈{write,archive,extract}, status} (rejected, not executed)" >&2
    exit 2
  fi
  manifest_write_atomic '.restructure_steps += [$step]' --argjson step "$step_json"
  echo "✓ update-manifest: appended proposed op $(printf '%s' "$step_json" | jq -r '.id') to restructure_steps[]"
}

# resolve_under <base_abs> <candidate_rel_or_abs> → echo the resolved absolute path
# IFF it lies inside <base_abs>; else return 1. Rejects '..' traversal and absolute
# escapes WITHOUT requiring the path to exist (T-22-09 path-traversal guard).
resolve_under() {
  local base="$1" cand="$2" abs
  case "$cand" in
    /*) abs="$cand" ;;          # absolute candidate — validate containment below
    *)  abs="$base/$cand" ;;    # relative — anchor under base
  esac
  # Reject any literal traversal segment before normalization (defense in depth).
  case "/$abs/" in
    */../*) return 1 ;;
  esac
  # Containment check by string prefix (base is already canonical-absolute).
  case "$abs/" in
    "$base"/*) printf '%s\n' "$abs"; return 0 ;;
    *) return 1 ;;
  esac
}

# apply_step <id> (D-05, outbound half): read op #id from restructure_steps[],
# validate op ∈ {write, archive, extract} + path safety, dispatch to the mutate_*
# chokepoint (RESTR-02), log RESTRUCTURE, mark status: applied. Every validation
# failure exits 2 and NEVER executes a partial op (T-22-09/10/11).
apply_step() {
  local id="$1"
  if [ ! -f "$MANIFEST_PATH" ]; then
    echo "✗ adopt.sh: --apply-step: no adopt-manifest.json at $MANIFEST_PATH" >&2
    exit 2
  fi
  # Read the op object. Missing id → exit 2.
  local op_json
  op_json="$(jq -c --arg id "$id" '.restructure_steps[]? | select(.id == $id)' "$MANIFEST_PATH" 2>/dev/null)"
  if [ -z "$op_json" ]; then
    echo "✗ adopt.sh: --apply-step: no restructure step with id '$id'" >&2
    exit 2
  fi
  local op dest src
  op="$(printf '%s' "$op_json" | jq -r '.op // ""')"
  dest="$(printf '%s' "$op_json" | jq -r '.dest // ""')"
  src="$(printf '%s' "$op_json" | jq -r '.src // ""')"
  # Op-type allowlist (T-22-11): reject anything outside {write, archive, extract}.
  case "$op" in
    write|archive|extract) ;;
    *) echo "✗ adopt.sh: --apply-step: unsupported op '$op' (allowed: write, archive, extract)" >&2; exit 2 ;;
  esac

  local staging_abs target_abs archive_root
  staging_abs="$(cd "$TARGET" && pwd)/.conjure-adopt-state/staging"
  target_abs="$(cd "$TARGET" && pwd)"

  # Set the log path so log_step RESTRUCTURE lands in the durable trail. log_init is
  # NOT called here (apply-step runs post-pipeline; reuse or create the log header).
  if [ ! -f "$TARGET/RESTRUCTURE-LOG.md" ]; then
    log_init "$TARGET"
  else
    RESTRUCTURE_LOG_PATH="$TARGET/RESTRUCTURE-LOG.md"
  fi

  # ── write half (used by write + extract) ───────────────────────────────────
  apply_write_op() {
    local d_rel="$dest" s_ref="$src" abs_src dest_abs
    if [ -z "$d_rel" ] || [ -z "$s_ref" ]; then
      echo "✗ adopt.sh: --apply-step: write op requires dest + src" >&2; exit 2
    fi
    # src is target-relative (D-07: ".conjure-adopt-state/staging/<file>"). Resolve it
    # under the target, then REQUIRE the resolved path to live under the staging dir
    # — reject any escape/'..' (T-22-09/10). resolve_under rejects traversal segments.
    if ! abs_src="$(resolve_under "$target_abs" "$s_ref")"; then
      echo "✗ adopt.sh: --apply-step: write src '$s_ref' escapes the target or contains '..' (rejected)" >&2
      exit 2
    fi
    case "$abs_src/" in
      "$staging_abs"/*) ;;
      *) echo "✗ adopt.sh: --apply-step: write src '$s_ref' must resolve under .conjure-adopt-state/staging/ (rejected)" >&2; exit 2 ;;
    esac
    if [ ! -f "$abs_src" ]; then
      echo "✗ adopt.sh: --apply-step: write src not found at $abs_src" >&2; exit 2
    fi
    # dest MUST resolve under the target and contain no traversal (T-22-09).
    if ! dest_abs="$(resolve_under "$target_abs" "$d_rel")"; then
      echo "✗ adopt.sh: --apply-step: write dest '$d_rel' escapes the target (rejected)" >&2
      exit 2
    fi
    # WR-04: reject dest paths that resolve under conjure's own control dirs (the
    # snapshot rollback depends on) or .git/ (a code-execution foot-gun on a tool
    # that mutates arbitrary user repos). resolve_under only guards traversal/escape.
    case "$dest_abs/" in
      "$target_abs"/.git/*|"$target_abs"/.conjure-adopt-backups/*|\
      "$target_abs"/.conjure-adopt-state/*|"$target_abs"/.conjure-archive-*)
        echo "✗ adopt.sh: --apply-step: write dest '$d_rel' targets a protected dir (rejected)" >&2
        exit 2 ;;
    esac
    # WR-01 (crash durability): record intent in state BEFORE the mutation so a
    # kill -9 between the write and the state record is still recoverable. For an
    # overwrite, append the mutated[] entry with a "pending" after-hash first, then
    # finalize it; for a new file, append to created[] before the write.
    local existed=0 before_sha=""
    if [ -f "$dest_abs" ]; then existed=1; before_sha="$(sha_of "$dest_abs")"; fi
    if [ "${DRY_RUN:-0}" != "1" ]; then
      if [ "$existed" -eq 1 ]; then
        state_add_mutated "$d_rel" "$before_sha" "pending"
      else
        state_add_created "$d_rel"
      fi
    fi
    # CR-01: byte-exact copy (preserves the trailing newline). The old
    # mutate_write "$dest_abs" "$(cat ...)" stripped trailing newlines, so the
    # applied file never byte-matched the staged content and the recorded after-sha
    # was the hash of the corrupted file. Route through the mutate.sh chokepoint.
    mutate_write_file "$dest_abs" "$abs_src"
    if [ "${DRY_RUN:-0}" != "1" ] && [ "$existed" -eq 1 ]; then
      state_set_last_mutated_after "$(sha_of "$dest_abs")"
    fi
  }

  # ── archive half (used by archive + extract) ────────────────────────────────
  # CR-02: the source-to-archive is passed EXPLICITLY as $1 rather than read from the
  # outer $src. For a plain `archive` op the caller passes "$src" (the manifest src);
  # for `extract` the caller passes the OLD dest path so the original dest content is
  # preserved BEFORE the write overwrites it (never the new staging source).
  apply_archive_op() {
    local s_ref="$1" abs_src
    if [ -z "$s_ref" ]; then
      echo "✗ adopt.sh: --apply-step: archive op requires src" >&2; exit 2
    fi
    # Resolve src to an ABSOLUTE, traversal-free path under the target. mutate_archive
    # also rejects relative/'..' (lib lines 96-102), but pre-validate for a clean error.
    if ! abs_src="$(resolve_under "$target_abs" "$s_ref")"; then
      echo "✗ adopt.sh: --apply-step: archive src '$s_ref' escapes the target or contains '..' (rejected)" >&2
      exit 2
    fi
    if [ ! -e "$abs_src" ]; then
      echo "✗ adopt.sh: --apply-step: archive src not found at $abs_src" >&2; exit 2
    fi
    archive_root="$target_abs/.conjure-archive-$(date -u '+%Y%m%dT%H%M%SZ')"
    mkdir -p "$archive_root"
    if ! mutate_archive "$abs_src" "$archive_root"; then
      echo "✗ adopt.sh: --apply-step: archive failed for $abs_src" >&2; exit 2
    fi
    ARCHIVED_COUNT=$((${ARCHIVED_COUNT:-0} + 1))
  }

  case "$op" in
    write)   apply_write_op ;;
    archive) apply_archive_op "$src" ;;
    extract)
      # D-08: write-new + archive-OLD composed. CR-02: archive the OLD dest content
      # FIRST (before the write overwrites it), then write the staging source to dest.
      # Never archive the staging source — that would destroy the new content and lose
      # the original. The OLD dest is archived only if it exists.
      if [ -n "$dest" ] && [ -f "$target_abs/$dest" ]; then
        apply_archive_op "$dest"
      fi
      apply_write_op
      ;;
  esac

  log_step RESTRUCTURE "applied $op step '$id'${dest:+ → $dest}${src:+ (src $src)}"
  # Mark the step applied in the manifest (atomic temp+mv, injection-safe --arg).
  manifest_write_atomic '(.restructure_steps[] | select(.id == $id) | .status) = "applied"' --arg id "$id"
  echo "✓ apply-step: $op op '$id' applied (status: applied)"
}

# ── the 5-step forward pipeline (ADOPT-01/04/05/06, SAFE-01/04/07) ────────────
run_pipeline() {
  REPORT_MANIFEST=""           # manifest path the report reads (target or temp)
  ARCHIVED_COUNT=0
  AUDIT_BEFORE_RC="NA"
  AUDIT_AFTER_RC="NA"

  # Step 0.5: init the log FIRST so the dirty-tree --force WARN (and snapshot/
  # inventory auto-logs) land in RESTRUCTURE-LOG.md (SAFE-07). log_init is
  # DRY_RUN-aware (mutate_write), so dry-run writes nothing under the target.
  # On --resume (D-12) the log + state already exist from the interrupted run; do
  # NOT re-init either (log_init replaces the file; state_init resets created[]),
  # just set the path so subsequent log_step appends continue the durable trail.
  if [ "${CONJURE_ADOPT_REUSE_SNAPSHOT:-0}" = "1" ] && [ -f "$TARGET/RESTRUCTURE-LOG.md" ]; then
    # Consumed by log_step/snapshot_* in the sourced libs (invisible to shellcheck).
    # shellcheck disable=SC2034
    RESTRUCTURE_LOG_PATH="$TARGET/RESTRUCTURE-LOG.md"
  else
    log_init "$TARGET"
  fi

  # Step 0: preconditions (dirty-tree gate). Runs for real in dry-run too (D-10).
  # On exit-2 (dirty + no --force) no state has been written yet, so a refused
  # run leaves no .conjure-adopt-state to trigger a false recovery prompt.
  # WR-02: SKIP the dirty-tree gate on resume. resume_pipeline sets
  # CONJURE_ADOPT_REUSE_SNAPSHOT=1 and legitimately continues an already-snapshotted
  # run — the snapshot already captured the (possibly dirty, possibly --force'd) tree,
  # and scaffold has since added untracked files making it dirtier. Re-running the
  # gate without the original --force would exit 2 and deadlock the very recovery
  # resume exists to provide.
  echo "Step 1/5 preconditions"
  if [ "${CONJURE_ADOPT_REUSE_SNAPSHOT:-0}" = "1" ]; then
    echo "preconditions: [resume] dirty-tree gate skipped — continuing an already-snapshotted run"
  else
    precondition_git
  fi

  # State (SAFE-04 crash durability) — only after the gate passes; dry-run writes
  # zero state (ADOPT-02 zero-writes-under-target). On resume, reuse the existing
  # state (D-12) rather than re-initializing it.
  if [ "${DRY_RUN:-0}" != "1" ]; then
    if [ "${CONJURE_ADOPT_REUSE_SNAPSHOT:-0}" = "1" ] && [ -f "$STATE_PATH" ]; then
      state_set_step preconditions completed
    else
      state_init
      state_set_step preconditions completed
    fi
  fi

  # Capture CLAUDE.md "before" line count from the live tree (Pitfall 6: wc -l <).
  # NOTE: the "before" sha256 is captured AFTER snapshot_guarded (below), NOT here.
  # The rollback contract is "restore to the SNAPSHOT state", and snapshot_rollback
  # reproduces the bytes the snapshot captured. Capturing the before-hash pre-snapshot
  # risks recording a hash the restore cannot reproduce — e.g. on a Windows runner with
  # core.autocrlf=true the live checkout is CRLF and the tar/cp snapshot↔restore round
  # trip can diverge from a pre-snapshot reading — making the step-3 sha256 verify abort
  # rollback even though nothing was actually mutated (the bug this fixes).
  local before_lines after_lines claude_before_sha
  before_lines=0
  if [ -f "$TARGET/CLAUDE.md" ]; then
    before_lines="$(wc -l < "$TARGET/CLAUDE.md" | tr -d ' ')"
  fi

  # Audit BEFORE scaffold (ADOPT-05): capture rc, do NOT abort.
  if [ "${DRY_RUN:-0}" != "1" ]; then
    AUDIT_BEFORE_RC=0
    bash "$CONJURE_HOME/scripts/audit-setup.sh" "$TARGET" >/dev/null 2>&1 || AUDIT_BEFORE_RC=$?
  fi

  # Step 1: snapshot (SAFE-01). Write state BEFORE the mutating step (Pattern 3).
  # On --resume (D-12) REUSE the existing snapshot — a second snapshot would back up
  # the already-mutated tree (CR-2). Read snapshot_path back from the durable state.
  echo "Step 2/5 snapshot"
  if [ "${CONJURE_ADOPT_REUSE_SNAPSHOT:-0}" = "1" ] && [ -f "$STATE_PATH" ]; then
    CONJURE_SNAPSHOT_PATH="$(jq -r '.snapshot_path // ""' "$STATE_PATH" 2>/dev/null)"
    echo "  [resume] reusing existing snapshot → ${CONJURE_SNAPSHOT_PATH:-(none recorded)}"
  else
    if [ "${DRY_RUN:-0}" != "1" ]; then
      state_set_step snapshot started
    fi
    snapshot_guarded
    if [ "${DRY_RUN:-0}" != "1" ]; then
      state_set_snapshot "$CONJURE_SNAPSHOT_PATH"
      state_set_step snapshot completed
    fi
  fi

  # Capture CLAUDE.md "before" sha256 from the just-snapshotted tree (SAFE-02 source
  # of truth). The live CLAUDE.md here is byte-identical to the snapshot copy, so the
  # recorded before-hash is exactly what snapshot_rollback will reproduce — the step-3
  # rollback verify (adopt.sh ~352) then matches on every platform (cross-platform fix:
  # Windows core.autocrlf=true CRLF round-trips no longer fabricate a sha mismatch).
  if [ -f "$TARGET/CLAUDE.md" ]; then
    claude_before_sha="$(sha_of "$TARGET/CLAUDE.md")"
  fi

  # Step 2: inventory (ADOPT-01). Read-only scan, then emit the manifest.
  echo "Step 3/5 inventory"
  # --full-inventory wiring: lift the 500-file cap by exporting a high max BEFORE
  # the scan (lib default stays 500 so Phase 21 tests are unaffected).
  if [ "${CONJURE_ADOPT_FULL_INVENTORY:-0}" = "1" ]; then
    export CONJURE_INVENTORY_MAX=1000000
  fi
  inventory_scan "$TARGET"
  if [ "${DRY_RUN:-0}" = "1" ]; then
    # Pitfall 1 / D-11: write the manifest to a mktemp dir OUTSIDE the target.
    # The manifest is a read-only artifact (D-10), so emit it with DRY_RUN=0 for
    # this single call — that bypasses the lib's hardcoded /tmp redirect AND
    # keeps zero files under the target (ADOPT-02).
    local tmp_manifest_dir
    tmp_manifest_dir="$(mktemp -d)"
    DRY_RUN=0 inventory_emit_manifest "$TARGET" "$tmp_manifest_dir/adopt-manifest.json"
    REPORT_MANIFEST="$tmp_manifest_dir/adopt-manifest.json"
    echo "[dry-run] would write manifest under target; wrote inspection copy → $REPORT_MANIFEST"
  else
    state_set_step inventory started
    inventory_emit_manifest "$TARGET" "$MANIFEST_PATH"
    REPORT_MANIFEST="$MANIFEST_PATH"
    state_set_step inventory completed
  fi

  # Step 3: scaffold missing layers (ADOPT-04). Idempotent subprocess; never overwrites.
  echo "Step 4/5 scaffold"
  if [ "${DRY_RUN:-0}" != "1" ]; then
    state_set_step scaffold started
  fi
  # Record newly-created harness paths into created[] (D-02) so rollback deletes them.
  #
  # Windows fix: the legacy find/comm before/after DIFF is lossy on Git Bash -- path
  # separator / locale edges in `comm` silently drop scaffolded paths, leaving
  # created[] incomplete so rollback misses files (the zero-diff contract breaks, and
  # the leftover wandered file-to-file as we patched it). PRIMARY source of truth is
  # now a created-manifest EMITTED by init-project.sh itself (it knows exactly which
  # top-level paths it wrote): export CONJURE_CREATED_MANIFEST and read it back. Each
  # manifest entry is a target-relative path that may be a FILE or a DIRECTORY (skill
  # dirs are copied whole); expand directory entries to their constituent files here
  # because rollback's mutate_rm is per-file (rm -f never removes a non-empty dir).
  # The find/comm diff stays ONLY as a fallback when no manifest is produced.
  local pre_files post_files created_manifest
  pre_files="$(mktemp)"; post_files="$(mktemp)"; created_manifest="$(mktemp)"
  if [ "${DRY_RUN:-0}" != "1" ]; then
    ( cd "$TARGET" && find . -type f \
        -not -path './.conjure-adopt-backups/*' \
        -not -path './.conjure-archive-*/*' \
        -not -path './.conjure-adopt-state/*' \
        -not -name 'RESTRUCTURE-LOG.md' \
        -not -name 'adopt-manifest.json' \
        2>/dev/null | sort ) > "$pre_files"
  fi
  export CONJURE_HOME
  export DRY_RUN="${DRY_RUN:-0}"
  CONJURE_CREATED_MANIFEST="$created_manifest" \
    bash "$CONJURE_HOME/scripts/init-project.sh" existing "$TARGET" >/dev/null 2>&1 || true
  if [ "${DRY_RUN:-0}" != "1" ]; then
    ( cd "$TARGET" && find . -type f \
        -not -path './.conjure-adopt-backups/*' \
        -not -path './.conjure-archive-*/*' \
        -not -path './.conjure-adopt-state/*' \
        -not -name 'RESTRUCTURE-LOG.md' \
        -not -name 'adopt-manifest.json' \
        2>/dev/null | sort ) > "$post_files"
    # Build a normalized, deduped flat file list into $created_flat, then record it.
    local created_flat newf created_n=0
    created_flat="$(mktemp)"
    if [ -s "$created_manifest" ]; then
      # PRIMARY (Windows-safe): trust init-project.sh's own created list. Normalize a
      # leading ./, expand any directory entry to its files (relative to $TARGET).
      while IFS= read -r newf; do
        newf="${newf%$'\r'}"; newf="${newf#./}"
        [ -n "$newf" ] || continue
        if [ -d "$TARGET/$newf" ]; then
          ( cd "$TARGET" && find "$newf" -type f 2>/dev/null ) >> "$created_flat"
        elif [ -e "$TARGET/$newf" ]; then
          printf '%s\n' "$newf" >> "$created_flat"
        fi
      done < "$created_manifest"
    else
      # FALLBACK (no manifest): legacy find/comm diff (present in post, absent in pre).
      comm -13 "$pre_files" "$post_files" >> "$created_flat"
    fi
    # Record deduped, ./-normalized paths into created[]; mutate_rm is per-file (D-02).
    while IFS= read -r newf; do
      newf="${newf%$'\r'}"; newf="${newf#./}"
      [ -n "$newf" ] || continue
      state_add_created "$newf"
      created_n=$((created_n + 1))
    done < <(sort -u "$created_flat")
    rm -f "$created_flat"
    log_step SCAFFOLD "scaffolded ${created_n} missing-layer file(s)"
    state_set_step scaffold completed
  else
    log_step SCAFFOLD "[dry-run] would scaffold missing layers via init-project.sh existing"
  fi
  rm -f "$pre_files" "$post_files" "$created_manifest"

  # CLAUDE.md "after" line count + mutated[] record (SAFE-04). Phase 22 does not
  # condense CLAUDE.md, so before==after; recording it satisfies the .mutated[]
  # SAFE-04 contract and seeds the Wave 2 rollback sha256-verify loop.
  after_lines="$before_lines"
  if [ -f "$TARGET/CLAUDE.md" ]; then
    after_lines="$(wc -l < "$TARGET/CLAUDE.md" | tr -d ' ')"
    if [ "${DRY_RUN:-0}" != "1" ]; then
      local claude_after_sha
      claude_after_sha="$(sha_of "$TARGET/CLAUDE.md")"
      state_add_mutated "CLAUDE.md" "${claude_before_sha:-}" "$claude_after_sha"
    fi
  fi

  # Step 4: audit AFTER scaffold (ADOPT-05). Capture rc, log, do NOT abort.
  echo "Step 5/5 audit"
  if [ "${DRY_RUN:-0}" != "1" ]; then
    state_set_step audit started
    AUDIT_AFTER_RC=0
    bash "$CONJURE_HOME/scripts/audit-setup.sh" "$TARGET" >/dev/null 2>&1 || AUDIT_AFTER_RC=$?
    log_step AUDIT "harness health before rc=${AUDIT_BEFORE_RC} → after rc=${AUDIT_AFTER_RC}"
    state_set_step audit completed
  else
    echo "[dry-run] would run audit-setup.sh and report harness health before/after"
    log_step AUDIT "[dry-run] would run audit-setup.sh"
  fi

  # Step 5: report (ADOPT-06) + mutate_summary.
  report "$before_lines" "$after_lines"
  mutate_summary
}

# ── mode dispatch (mutually exclusive sub-ops) ────────────────────────────────
# rollback / apply-step / update-manifest route to their handlers (Wave 2 stubs);
# a prior partial .conjure-adopt-state triggers recovery; otherwise run_pipeline.
if [ "${CONJURE_ADOPT_ROLLBACK:-0}" = "1" ]; then
  rollback_path
elif [ -n "${CONJURE_ADOPT_APPLY_STEP:-}" ]; then
  apply_step "$CONJURE_ADOPT_APPLY_STEP"
elif [ "${CONJURE_ADOPT_UPDATE_MANIFEST:-0}" = "1" ]; then
  update_manifest
elif [ "${CONJURE_ADOPT_RESUME:-0}" = "1" ]; then
  # --resume (D-12): continue at the next incomplete step, reusing the snapshot.
  resume_pipeline
elif [ "${CONJURE_ADOPT_START_FRESH:-0}" = "1" ]; then
  rm -rf "$STATE_DIR"
  run_pipeline
elif [ -f "$STATE_PATH" ] && [ "${DRY_RUN:-0}" != "1" ]; then
  # A prior partial run left state. Without an explicit recovery flag, detect it
  # and (non-TTY) exit 2 with the recovery instructions (D-13). The full
  # interactive prompt + resume/rollback bodies land in Wave 2 (Plan 03).
  LAST_STEP="$(jq -r '.current_step // "unknown"' "$STATE_PATH" 2>/dev/null || echo unknown)"
  if ! { [ -t 0 ] || [ "${CONJURE_FORCE_INTERACTIVE:-0}" = "1" ]; }; then
    echo "conjure adopt: partial run detected (last completed: $LAST_STEP)" >&2
    echo "  non-interactive — choose: --rollback | --resume | --start-fresh" >&2
    exit 2
  fi
  recovery_prompt "$LAST_STEP"
else
  run_pipeline
fi
