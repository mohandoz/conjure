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
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" 2>/dev/null | cut -d' ' -f1
  else
    shasum -a 256 "$1" 2>/dev/null | cut -d' ' -f1
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

# ── dirty-tree precondition (Step 0, ADOPT-03 + SAFE-06, Pitfall 5) ───────────
# git status --porcelain: empty = clean (catches tracked-modified AND untracked).
# dirty && !force → exit 2 (never exit 1). dirty && force → log_step WARN + echo.
# non-git target (porcelain errors) → skip the gate with a note (snapshot works).
precondition_git() {
  if ! git -C "$TARGET" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "preconditions: not a git repo — skipping dirty-tree gate (snapshot still backs up the filesystem)"
    return 0
  fi
  local dirty
  dirty="$(git -C "$TARGET" status --porcelain 2>/dev/null)"
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
  echo "  Archived:    ${ARCHIVED_COUNT:-0} files"
  echo "  CLAUDE.md:   ${before_lines} → ${after_lines} lines (cap ${CLAUDE_MD_CAP:-100})"
  echo "  Snapshot:    ${CONJURE_SNAPSHOT_PATH:-(dry-run)}"
  echo "  Audit:       before rc=${AUDIT_BEFORE_RC:-NA} → after rc=${AUDIT_AFTER_RC:-NA}"
  echo "  Next:        open Claude Code → run the restructure skill"
  echo "  Note:        --rollback restores from the filesystem snapshot, NOT git (SAFE-06)"
}

# ── Wave 2 stubs (Plan 03 fills these bodies; wired here so dispatch is complete) ──
rollback_path() {
  echo "adopt.sh: --rollback is not yet implemented (Wave 2 / Plan 03)" >&2
  exit 2
}
recovery_prompt() {
  echo "adopt.sh: partial-run recovery is not yet implemented (Wave 2 / Plan 03)" >&2
  echo "  last completed: ${1:-unknown}" >&2
  echo "  non-interactive — choose: --rollback | --resume | --start-fresh" >&2
  exit 2
}
apply_step() {
  echo "adopt.sh: --apply-step is not yet implemented (Wave 2 / Plan 03)" >&2
  exit 2
}
update_manifest() {
  echo "adopt.sh: --update-manifest is not yet implemented (Wave 2 / Plan 03)" >&2
  exit 2
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
  log_init "$TARGET"

  # Step 0: preconditions (dirty-tree gate). Runs for real in dry-run too (D-10).
  # On exit-2 (dirty + no --force) no state has been written yet, so a refused
  # run leaves no .conjure-adopt-state to trigger a false recovery prompt.
  echo "Step 1/5 preconditions"
  precondition_git

  # State (SAFE-04 crash durability) — only after the gate passes; dry-run writes
  # zero state (ADOPT-02 zero-writes-under-target).
  if [ "${DRY_RUN:-0}" != "1" ]; then
    state_init
    state_set_step preconditions completed
  fi

  # Capture CLAUDE.md "before" line count from the live tree (Pitfall 6: wc -l <).
  local before_lines after_lines claude_before_sha
  before_lines=0
  if [ -f "$TARGET/CLAUDE.md" ]; then
    before_lines="$(wc -l < "$TARGET/CLAUDE.md" | tr -d ' ')"
    claude_before_sha="$(sha_of "$TARGET/CLAUDE.md")"
  fi

  # Audit BEFORE scaffold (ADOPT-05): capture rc, do NOT abort.
  if [ "${DRY_RUN:-0}" != "1" ]; then
    AUDIT_BEFORE_RC=0
    bash "$CONJURE_HOME/scripts/audit-setup.sh" "$TARGET" >/dev/null 2>&1 || AUDIT_BEFORE_RC=$?
  fi

  # Step 1: snapshot (SAFE-01). Write state BEFORE the mutating step (Pattern 3).
  echo "Step 2/5 snapshot"
  if [ "${DRY_RUN:-0}" != "1" ]; then
    state_set_step snapshot started
  fi
  snapshot_guarded
  if [ "${DRY_RUN:-0}" != "1" ]; then
    state_set_snapshot "$CONJURE_SNAPSHOT_PATH"
    state_set_step snapshot completed
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
  # Capture the file set before/after to record newly-created harness paths (D-02).
  local pre_files post_files
  pre_files="$(mktemp)"; post_files="$(mktemp)"
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
  bash "$CONJURE_HOME/scripts/init-project.sh" existing "$TARGET" >/dev/null 2>&1 || true
  if [ "${DRY_RUN:-0}" != "1" ]; then
    ( cd "$TARGET" && find . -type f \
        -not -path './.conjure-adopt-backups/*' \
        -not -path './.conjure-archive-*/*' \
        -not -path './.conjure-adopt-state/*' \
        -not -name 'RESTRUCTURE-LOG.md' \
        -not -name 'adopt-manifest.json' \
        2>/dev/null | sort ) > "$post_files"
    # New files = present in post, absent in pre. Record into created[] (D-02 —
    # scaffolded harness paths only; the find excludes conjure's own dirs).
    local newf
    while IFS= read -r newf; do
      [ -n "$newf" ] || continue
      state_add_created "${newf#./}"
    done < <(comm -13 "$pre_files" "$post_files")
    log_step SCAFFOLD "scaffolded $(comm -13 "$pre_files" "$post_files" | grep -c . | tr -d ' ') missing-layer file(s)"
    state_set_step scaffold completed
  else
    log_step SCAFFOLD "[dry-run] would scaffold missing layers via init-project.sh existing"
  fi
  rm -f "$pre_files" "$post_files"

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
  # Wave 2 fills resume; for now route through the stub recovery handler.
  recovery_prompt "$( [ -f "$STATE_PATH" ] && jq -r '.current_step // "unknown"' "$STATE_PATH" 2>/dev/null || echo unknown )"
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
