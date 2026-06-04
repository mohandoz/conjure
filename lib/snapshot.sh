# shellcheck shell=bash
# lib/snapshot.sh — full timestamped snapshot for Conjure adopt.
# Source this file; requires lib/mutate.sh and lib/log.sh already sourced.
# POSIX bash 3.2+. No associative arrays, no mapfile, no local -n.

# Module-level state: CONJURE_SNAPSHOT_PATH is set by snapshot_create.
# Safe under set -u; idempotent on re-source.
CONJURE_SNAPSHOT_PATH="${CONJURE_SNAPSHOT_PATH:-}"

# snapshot_create <target> <backup_root>
# Creates a timestamped snapshot of <target> under <backup_root>/conjure-adopt-<UTC-ts>/.
# Uses raw cp -a (NOT mutate_cp) — snapshot is the safety primitive that precedes all
# mutate_* calls; routing through mutate_cp would suppress the backup under DRY_RUN=1.
# DRY_RUN=1: prints would-be path, sets CONJURE_SNAPSHOT_PATH, returns 0 (no cp executed).
# DRY_RUN=0: creates snapshot dir, copies contents, writes snapshot-meta.json, calls log_step.
# Sets CONJURE_SNAPSHOT_PATH to the snapshot directory path in both modes.
snapshot_create() {
  local target="$1"
  local backup_root="$2"
  local ts
  ts="$(date -u '+%Y%m%dT%H%M%SZ')"
  local snap_dir="${backup_root}/conjure-adopt-${ts}"

  if [ "${DRY_RUN:-0}" = "1" ]; then
    echo "[dry-run] would snapshot ${target} → ${snap_dir}"
    CONJURE_SNAPSHOT_PATH="${snap_dir}"
    return 0
  fi

  # Create snapshot directory and copy contents preserving symlinks + timestamps (M-4).
  # Exclude .git and node_modules: adopt never mutates them, so they need no rollback
  # coverage — and copying read-only .git objects makes rollback's overwrite emit
  # "Permission denied" noise on the safety-critical path (milestone-audit WR). tar gives
  # portable exclusion (BSD + GNU) while preserving symlinks/perms/timestamps; the
  # `cd && tar` guards a bad target dir. cp -a is the no-exclusion fallback if tar fails
  # (rare — a stray .git copy is then cosmetic-only, never a correctness problem).
  #
  # Windows fix: archive via a TEMP FILE, not a `tar -cf - | tar -xpf -` PIPE. On
  # MSYS/MinGW (Git Bash) a pipe carrying a binary tar stream gets text-mode CRLF
  # translation that corrupts the archive — the round-trip is NOT byte-faithful, so
  # rollback's sha256-verify later sees a mismatch on an otherwise-unchanged file.
  # Writing the archive to a real file (binary I/O on both ends) avoids the pipe
  # entirely and keeps bytes intact across create→restore.
  mkdir -p "${snap_dir}"
  local _snap_tar
  _snap_tar="$(mktemp)"
  if ! { ( cd "${target}" && tar -cf "${_snap_tar}" --exclude='./.git' --exclude='./node_modules' --exclude='./.conjure-adopt-backups' . ) \
         && ( cd "${snap_dir}" && tar -xpf "${_snap_tar}" ); }; then
    rm -f "${_snap_tar}"
    if ! cp -a "${target}/." "${snap_dir}/"; then
      # Pitfall 5 cross-platform fallback: cp -Rp (POSIX)
      if ! cp -Rp "${target}" "${snap_dir}/"; then
        printf '%s\n' "[snapshot_create] ERROR: copy failed for ${target} → ${snap_dir}" >&2
        return 1
      fi
    fi
  else
    rm -f "${_snap_tar}"
  fi

  # Write snapshot metadata (git state capture for rollback reference)
  local git_head git_stash
  git_head="$(git -C "${target}" rev-parse HEAD 2>/dev/null || printf '')"
  git_stash="$(git -C "${target}" stash list 2>/dev/null | head -10 || printf '')"

  local meta_ts
  meta_ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  local meta_content
  meta_content="$(jq -cn \
    --arg created_at "${meta_ts}" \
    --arg target "$(cd "${target}" && pwd)" \
    --arg git_head "${git_head}" \
    --arg git_stash_list "${git_stash}" \
    '{created_at: $created_at, target: $target, git_head: $git_head, git_stash_list: $git_stash_list}')"
  mutate_write "${snap_dir}/.snapshot-meta.json" "${meta_content}"

  CONJURE_SNAPSHOT_PATH="${snap_dir}"

  # Call log_step SNAPSHOT if RESTRUCTURE_LOG_PATH is set (integration with log.sh)
  if [ -n "${RESTRUCTURE_LOG_PATH:-}" ]; then
    log_step SNAPSHOT "created at ${snap_dir}"
  fi
}

# snapshot_rollback <snapshot_path> <target>
# Restores <target> from a previously created snapshot at <snapshot_path>.
# Validates snapshot_path exists before restoring.
# Calls log_step ROLLBACK after successful restore.
snapshot_rollback() {
  local snapshot_path="$1"
  local target="$2"

  if [ ! -d "${snapshot_path}" ]; then
    printf '%s\n' "[snapshot_rollback] ERROR: snapshot path not found: ${snapshot_path}" >&2
    return 1
  fi

  # Restore via tar (symmetric with snapshot_create): cp -a's --preserve=all fails
  # on Windows Git Bash (can't preserve ownership for a non-root user), which aborted
  # rollback mid-restore. tar -xpf preserves symlinks/perms/timestamps without the
  # ownership-preservation failure. cp -a → cp -Rp remain as POSIX fallbacks.
  #
  # Windows fix (symmetric with snapshot_create): archive via a TEMP FILE, not a
  # `tar -cf - | tar -xpf -` PIPE. The MSYS/MinGW pipe text-mode CRLF translation
  # corrupts the binary tar stream, so the restored bytes diverge from the snapshot —
  # rollback step-3 sha256-verify then aborts on an unchanged file. A real archive
  # file keeps binary I/O on both ends and restores byte-faithfully.
  local _rb_tar
  _rb_tar="$(mktemp)"
  if ! { ( cd "${snapshot_path}" && tar -cf "${_rb_tar}" . ) \
         && ( cd "${target}" && tar -xpf "${_rb_tar}" ); }; then
    rm -f "${_rb_tar}"
    if ! cp -a "${snapshot_path}/." "${target}/"; then
      if ! cp -Rp "${snapshot_path}/." "${target}/"; then
        printf '%s\n' "[snapshot_rollback] ERROR: restore failed for ${snapshot_path} → ${target}" >&2
        return 1
      fi
    fi
  else
    rm -f "${_rb_tar}"
  fi

  if [ -n "${RESTRUCTURE_LOG_PATH:-}" ]; then
    log_step ROLLBACK "restored from ${snapshot_path}"
  fi
}

# snapshot_list <backup_root>
# Lists all conjure-adopt-* directories under <backup_root>, sorted newest-first.
# Uses ls -1t for time-sorted output (newest first).
# POSIX compatible; no associative arrays.
snapshot_list() {
  local backup_root="$1"
  # SC2012: ls used intentionally for time-sorted (newest-first) listing
  # shellcheck disable=SC2012
  ls -1t "${backup_root}"/conjure-adopt-* 2>/dev/null | while IFS= read -r entry; do
    printf '%s\n' "${entry}"
  done
}
