# lib/merge.sh — 3-way merge for cmd_update --apply.
# Source this file; requires lib/mutate.sh already sourced and DRY_RUN set.
# POSIX bash 3.2+. No associative arrays, no mapfile, no local -n.
# Requires: CONJURE_HOME, DRY_RUN, and mutate_write/mutate_mkdir from lib/mutate.sh.
#
# Public functions:
#   merge_file_3way  <current> <base> <new> <rel> <pinned_ver> <new_ver>
#   write_merge_sidecar  <current_file> <rel> <content>
#   merge_user_files  <target> <snap_dir> <conjure_ver> <pinned_ver>

# Initialize conflict tracking state.
# Safe under set -u; idempotent on re-source.
CONJURE_MERGE_CONFLICT_COUNT="${CONJURE_MERGE_CONFLICT_COUNT:-0}"
CONJURE_MERGE_CONFLICT_FILES=""

# merge_file_3way <current> <base> <new> <rel> <pinned_ver> <new_ver>
# Performs a 3-way merge of <current> (live user file) against <base> (snapshot ancestor)
# and <new> (upstream template). Argument order follows git merge-file convention:
#   current = user's live file (ours)
#   base    = snapshot ancestor (base/middle)
#   new     = upstream template (theirs)
# Returns:
#   0 = clean merge, <current> updated via mutate_write
#   1 = conflict, sidecar written, <current> untouched (D-05)
#   2 = git error (rc=255), caller should abort
merge_file_3way() {
  local current="$1"
  local base="$2"
  local new="$3"
  local rel="$4"
  local pinned_ver="$5"
  local new_ver="$6"
  local merged
  local rc
  # SC2155: capture separately to preserve exit code
  merged="$(git merge-file -p --diff3 \
    -L "your version (${rel})" \
    -L "v${pinned_ver} base" \
    -L "v${new_ver} upstream" \
    "$current" "$base" "$new" 2>/dev/null)"
  rc=$?
  if [ "$rc" -eq 0 ]; then
    mutate_write "$current" "$merged"
    return 0
  elif [ "$rc" -lt 255 ]; then
    write_merge_sidecar "$current" "$rel" "$merged"
    return 1
  else
    echo "✗ git merge-file error on ${rel} (rc=${rc})" >&2
    return 2
  fi
}

# write_merge_sidecar <current_file> <rel> <content>
# Writes merged content (with conflict markers) to a sidecar file next to <current_file>.
# Sidecar filename: .conjure-conflict-<encoded> where <encoded> = rel with '/' replaced by '_'.
# Uses mutate_write (not direct printf) — DRY_RUN is handled internally by mutate_write.
# Tracks conflict count and sidecar paths in module-level variables.
write_merge_sidecar() {
  local current_file="$1"
  local rel="$2"
  local content="$3"
  local encoded
  encoded="$(printf '%s' "$rel" | tr '/' '_')"
  local sidecar_name=".conjure-conflict-${encoded}"
  local sidecar_dir
  sidecar_dir="$(dirname "$current_file")"
  local sidecar_path="${sidecar_dir}/${sidecar_name}"
  mutate_write "$sidecar_path" "$content"
  CONJURE_MERGE_CONFLICT_COUNT=$((CONJURE_MERGE_CONFLICT_COUNT+1))
  # Conditional-space expansion — no leading space when list is empty (Blocker 6)
  CONJURE_MERGE_CONFLICT_FILES="${CONJURE_MERGE_CONFLICT_FILES:+$CONJURE_MERGE_CONFLICT_FILES }$sidecar_path"
}

# merge_user_files <target> <snap_dir> <conjure_ver> <pinned_ver>
# Iterates all user-owned template types and calls merge_file_3way for each
# installed file that has a corresponding snapshot ancestor.
# Resets conflict tracking at start; caller checks CONJURE_MERGE_CONFLICT_COUNT afterward.
# Returns:
#   0 = all merges complete (may have conflicts tracked in CONJURE_MERGE_CONFLICT_COUNT)
#   2 = git error on a file (caller should abort immediately)
merge_user_files() {
  local target="$1"
  local snap_dir="$2"
  local conjure_ver="$3"
  local pinned_ver="$4"

  # Reset conflict tracking
  CONJURE_MERGE_CONFLICT_COUNT=0
  CONJURE_MERGE_CONFLICT_FILES=""

  # CLAUDE.md template (single file — installed as CLAUDE.md, not CLAUDE.md.tmpl)
  local tmpl_file="$CONJURE_HOME/templates/CLAUDE.md.tmpl"
  local current="$target/.claude/CLAUDE.md"
  local base="$snap_dir/CLAUDE.md.tmpl"
  local rel="CLAUDE.md"
  local _rc
  if [ -f "$current" ] && [ -f "$base" ]; then
    merge_file_3way "$current" "$base" "$tmpl_file" "$rel" "$pinned_ver" "$conjure_ver"
    _rc=$?
    # No tempfile to clean here — CLAUDE.md is a single-file check.
    if [ "$_rc" -eq 2 ]; then return 2; fi
  fi

  # Skills — POSIX-safe find loop using mktemp (no process substitution; bash 3.2 compat)
  local _merge_list_skills
  _merge_list_skills="$(mktemp)"
  find "$CONJURE_HOME/templates/skills" -name SKILL.md > "$_merge_list_skills"
  while IFS= read -r tmpl_file; do
    rel="${tmpl_file#$CONJURE_HOME/templates/}"
    current="$target/.claude/$rel"
    base="$snap_dir/$rel"
    if [ -f "$current" ] && [ -f "$base" ]; then
      merge_file_3way "$current" "$base" "$tmpl_file" "$rel" "$pinned_ver" "$conjure_ver"
      _rc=$?
      if [ "$_rc" -eq 2 ]; then
        rm -f "$_merge_list_skills"
        return 2
      fi
    fi
  done < "$_merge_list_skills"
  rm -f "$_merge_list_skills"

  # Agents — POSIX-safe find loop using mktemp
  local _merge_list_agents
  _merge_list_agents="$(mktemp)"
  find "$CONJURE_HOME/templates/agents" -name '*.md' > "$_merge_list_agents"
  while IFS= read -r tmpl_file; do
    rel="${tmpl_file#$CONJURE_HOME/templates/}"
    current="$target/.claude/$rel"
    base="$snap_dir/$rel"
    if [ -f "$current" ] && [ -f "$base" ]; then
      merge_file_3way "$current" "$base" "$tmpl_file" "$rel" "$pinned_ver" "$conjure_ver"
      _rc=$?
      if [ "$_rc" -eq 2 ]; then
        rm -f "$_merge_list_agents"
        return 2
      fi
    fi
  done < "$_merge_list_agents"
  rm -f "$_merge_list_agents"

  # Hooks (.mjs files) — POSIX-safe find loop using mktemp
  local _merge_list_hooks
  _merge_list_hooks="$(mktemp)"
  find "$CONJURE_HOME/templates/hooks-nodejs" -name '*.mjs' > "$_merge_list_hooks"
  while IFS= read -r tmpl_file; do
    local rel_hooks="${tmpl_file#$CONJURE_HOME/templates/hooks-nodejs/}"
    current="$target/.claude/hooks/$rel_hooks"
    base="$snap_dir/hooks/$rel_hooks"
    rel="hooks/$rel_hooks"
    if [ -f "$current" ] && [ -f "$base" ]; then
      merge_file_3way "$current" "$base" "$tmpl_file" "$rel" "$pinned_ver" "$conjure_ver"
      _rc=$?
      if [ "$_rc" -eq 2 ]; then
        rm -f "$_merge_list_hooks"
        return 2
      fi
    fi
  done < "$_merge_list_hooks"
  rm -f "$_merge_list_hooks"

  return 0
}
