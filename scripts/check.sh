#!/usr/bin/env bash
# scripts/check.sh — compare installed harness against upstream kit snapshot.
# Usage: CONJURE_HOME=<path> CONJURE_PORCELAIN=<0|1> CONJURE_SCHEMA=<0|1> bash check.sh [target]
# Exit codes: 0 = harness is current, 1 = drift detected, 2 = schema error (renamed/unknown hook event)
# Read-only: no mutations, no lib/mutate.sh required.

set -uo pipefail

TARGET="${1:-$(pwd)}"
CONJURE_HOME="${CONJURE_HOME:-$(cd "$(dirname "$0")/.." && pwd)}"
PORCELAIN="${CONJURE_PORCELAIN:-0}"

# Validate target directory (T-17-01: prevent path traversal on invalid arg)
[ -d "$TARGET" ] || { echo "✗ target is not a directory: $TARGET" >&2; exit 2; }

# sha256_file <path> — cross-platform sha256 hash of a single file.
# D-cross-platform: sha256sum on Linux; shasum -a 256 on macOS fallback.
sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

# Build manifest (relative harness paths) into a temp file.
# bash 3.2 compatible: no declare -A, no mapfile, no local -n.
MANIFEST="$(mktemp)"
# Single EXIT trap for ALL tempfiles. bash has one EXIT trap slot — registering
# a second `trap ... EXIT` later would silently clobber this one and leak files
# (WR-02). The cleanup function rm -f's every tempfile the script may create;
# unset vars expand to empty via the :- default and are harmless.
_check_cleanup() { rm -f "${MANIFEST:-}" "${_SCHM03_TMP:-}" "${_SCHM04_NEWER:-}"; }
trap _check_cleanup EXIT

# Root dotfiles (3)
printf '%s\n' ".editorconfig" ".gitattributes" ".claudeignore" >> "$MANIFEST"

# Core config (1) — harness path strips .tmpl suffix
printf '%s\n' ".claude/settings.json" >> "$MANIFEST"

# Hooks (6 — *.mjs only; README.md excluded by glob)
for hook in "$CONJURE_HOME"/templates/hooks-nodejs/*.mjs; do
  printf '%s\n' ".claude/hooks/$(basename "$hook")" >> "$MANIFEST"
done

# Skills. Only count a directory as a skill if it actually contains a SKILL.md — a
# partial skill dir (e.g. helper scripts staged before the SKILL.md ships) is not yet
# an installable skill and must not register as drift. For an installable skill,
# register EVERY file the kit ships under it (SKILL.md plus any attached resources
# such as gates/*.sh), since init-project.sh copies the whole dir recursively
# (mutate_cp cp -r). Registering only SKILL.md would flag the attached helper files
# as spurious "added" drift.
for skill_dir in "$CONJURE_HOME"/templates/skills/*/; do
  [ -f "$skill_dir/SKILL.md" ] || continue
  skill_name="$(basename "$skill_dir")"
  while IFS= read -r kit_skill_file; do
    rel_in_skill="${kit_skill_file#"$skill_dir"}"
    printf '%s\n' ".claude/skills/$skill_name/$rel_in_skill" >> "$MANIFEST"
  done < <(find "$skill_dir" -type f 2>/dev/null | sort)
done

# Agents (6)
for agent in "$CONJURE_HOME"/templates/agents/*.md; do
  printf '%s\n' ".claude/agents/$(basename "$agent")" >> "$MANIFEST"
done

# Classify kit files: modified or removed
modified="" removed="" added=""

while IFS= read -r rel; do
  # Resolve kit source file — settings.json strips .tmpl; others map directly.
  case "$rel" in
    .claude/settings.json)
      kit_file="$CONJURE_HOME/templates/settings.json.tmpl" ;;
    .claude/hooks/*)
      kit_file="$CONJURE_HOME/templates/hooks-nodejs/$(basename "$rel")" ;;
    .claude/skills/*)
      # Map any harness path under a skill dir (SKILL.md or an attached resource
      # like gates/*.sh) back to its kit source under templates/skills/.
      skill_rel="${rel#.claude/skills/}"
      kit_file="$CONJURE_HOME/templates/skills/$skill_rel" ;;
    .claude/agents/*)
      kit_file="$CONJURE_HOME/templates/agents/$(basename "$rel")" ;;
    .editorconfig|.gitattributes|.claudeignore)
      kit_file="$CONJURE_HOME/templates/$rel" ;;
    *) continue ;;
  esac

  harness_file="$TARGET/$rel"
  if [ ! -f "$harness_file" ]; then
    removed="$removed$rel\n"
  else
    kit_hash="$(sha256_file "$kit_file")"
    harness_hash="$(sha256_file "$harness_file")"
    if [ "$kit_hash" != "$harness_hash" ]; then
      modified="$modified$rel\n"
    fi
  fi
done < "$MANIFEST"

# Detect added files: in harness .claude/ but not in kit manifest.
# Skip conjure-internal state files (Pitfall 6).
while IFS= read -r harness_file; do
  rel="${harness_file#$TARGET/}"
  case "$rel" in
    .claude/.conjure-*) continue ;;
    .claude/COMPOUND-CANDIDATES.md) continue ;;
    .claude/docs/*) continue ;;
  esac
  # IN-04: anchor to a WHOLE-LINE match (-x). Manifest entries are bare relative
  # paths one-per-line, so an unanchored -qF substring match would falsely treat a
  # short added path as "registered" when it is a substring of a longer manifest
  # path (more likely now that nested skill-resource paths are registered).
  if ! grep -qxF "$rel" "$MANIFEST" 2>/dev/null; then
    added="$added$rel\n"
  fi
done < <(find "$TARGET/.claude" -type f 2>/dev/null | sort)

# Determine drift flag
drift=0
if [ -n "$modified" ] || [ -n "$removed" ] || [ -n "$added" ]; then
  drift=1
fi

# Output report
if [ "$PORCELAIN" = "1" ]; then
  # Machine-readable: one line per file, "<M|R|A> <path>", no headers
  printf '%b' "$modified" | while IFS= read -r f; do [ -n "$f" ] && printf 'M %s\n' "$f"; done
  printf '%b' "$removed"  | while IFS= read -r f; do [ -n "$f" ] && printf 'R %s\n' "$f"; done
  printf '%b' "$added"    | while IFS= read -r f; do [ -n "$f" ] && printf 'A %s\n' "$f"; done
else
  if [ "$drift" -eq 0 ]; then
    echo "Harness is current."
  else
    mod_count=$(printf '%b' "$modified" | grep -c '[^[:space:]]' || true)
    rem_count=$(printf '%b' "$removed"  | grep -c '[^[:space:]]' || true)
    add_count=$(printf '%b' "$added"    | grep -c '[^[:space:]]' || true)
    total=$((mod_count + rem_count + add_count))
    echo "Drift detected: $total file(s) differ from upstream kit"
    echo "Note: modified files may include user customizations"
    echo
    if [ -n "$modified" ]; then
      echo "Modified ($mod_count):"
      printf '%b' "$modified" | while IFS= read -r f; do [ -n "$f" ] && echo "  $f"; done
    fi
    if [ -n "$removed" ]; then
      echo "Removed ($rem_count):"
      printf '%b' "$removed" | while IFS= read -r f; do [ -n "$f" ] && echo "  $f"; done
    fi
    if [ -n "$added" ]; then
      echo "Added ($add_count):"
      printf '%b' "$added" | while IFS= read -r f; do [ -n "$f" ] && echo "  $f"; done
    fi
  fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# Phase 27 — Schema checks (SCHM-03 + SCHM-04)
# SCHM-03: hook event name validation — always-on, not gated on --schema flag.
# SCHM-04: per-key CC-version report   — gated on CONJURE_SCHEMA=1 (--schema).
# SCHEMA_FAIL counter is separate from drift; schema exit 2 > drift exit 1.
# ─────────────────────────────────────────────────────────────────────────────

SCHEMA_FILE="${CONJURE_HOME}/lib/cc-schema.json"
SCHEMA_FAIL=0

# SCHM-03 — Hook event name validation (always-on)
if [ -f "${TARGET}/.claude/settings.json" ] && \
   command -v jq >/dev/null 2>&1 && \
   [ -f "$SCHEMA_FILE" ]; then
  _SCHM03_TMP="$(mktemp)"
  # No per-block EXIT trap here — _check_cleanup (registered near line 29)
  # already rm -f's _SCHM03_TMP. Re-registering would clobber the MANIFEST
  # cleanup and leak it (WR-02).

  _KNOWN_EVENTS="$(jq -r '.hook_events[]' "$SCHEMA_FILE" 2>/dev/null)"
  _RENAMED_ENTRIES="$(jq -r '.renamed_events // {} | to_entries[] | "\(.key)=\(.value)"' "$SCHEMA_FILE" 2>/dev/null)"
  _HOOK_EVENTS_IN_SETTINGS="$(jq -r '.hooks // {} | keys[]' "${TARGET}/.claude/settings.json" 2>/dev/null)"

  printf '%s\n' "$_HOOK_EVENTS_IN_SETTINGS" | while IFS= read -r _ev; do
    [ -z "$_ev" ] && continue
    _rn="$(printf '%s\n' "$_RENAMED_ENTRIES" | grep "^${_ev}=" | head -1)"
    if [ -n "$_rn" ]; then
      printf 'SCHM03_RENAMED:%s:%s\n' "$_ev" "${_rn#*=}"
    elif ! printf '%s\n' "$_KNOWN_EVENTS" | grep -qxF "$_ev"; then
      printf 'SCHM03_UNKNOWN:%s\n' "$_ev"
    fi
  done > "$_SCHM03_TMP"

  while IFS= read -r _finding; do
    case "$_finding" in
      SCHM03_RENAMED:*)
        _old="${_finding#SCHM03_RENAMED:}"; _old="${_old%%:*}"
        _new="${_finding#*:}"; _new="${_new#*:}"
        printf 'SCHM-03 [fail] Hook event "%s" was renamed — use "%s" instead (settings.json)\n' \
          "$_old" "$_new" >&2
        SCHEMA_FAIL=$((SCHEMA_FAIL+1))
        ;;
      SCHM03_UNKNOWN:*)
        _unk="${_finding#SCHM03_UNKNOWN:}"
        _cc_ver="$(jq -r '.cc_version // "unknown"' "$SCHEMA_FILE" 2>/dev/null)"
        printf 'SCHM-03 [fail] Unknown hook event "%s" — not in CC schema v%s (settings.json)\n' \
          "$_unk" "$_cc_ver" >&2
        SCHEMA_FAIL=$((SCHEMA_FAIL+1))
        ;;
    esac
  done < "$_SCHM03_TMP"
  rm -f "$_SCHM03_TMP"
fi  # end SCHM-03

# SCHM-04 — Per-key CC-version report (gated on CONJURE_SCHEMA=1)
CONJURE_SCHEMA="${CONJURE_SCHEMA:-0}"
if [ "$CONJURE_SCHEMA" = "1" ] && \
   [ -f "${TARGET}/.claude/settings.json" ] && \
   command -v jq >/dev/null 2>&1 && \
   [ -f "$SCHEMA_FILE" ]; then
  # WR-04: under --porcelain the human-readable report must NOT land on stdout
  # (it interleaves with the M/R/A machine lines and corrupts any consumer).
  # Route every SCHM-04 line through _schm04_out: stderr when porcelain (mirrors
  # SCHM-03's >&2), stdout otherwise.
  _schm04_out() { if [ "$PORCELAIN" = "1" ]; then printf '%s\n' "$1" >&2; else printf '%s\n' "$1"; fi; }

  # CC version detection (Pattern 5: parse claude --version; absent → warn + use schema baseline)
  _CC_VER=""
  _CC_PRESENT=0
  if command -v claude >/dev/null 2>&1; then
    _CC_PRESENT=1
    _CC_VER="$(claude --version 2>/dev/null | awk '{print $1}')"
    if ! printf '%s\n' "$_CC_VER" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
      _CC_VER=""
    fi
  fi
  _SCHEMA_CC_VER="$(jq -r '.cc_version // "unknown"' "$SCHEMA_FILE" 2>/dev/null)"
  if [ -z "$_CC_VER" ]; then
    _schm04_out "$(printf 'SCHM-04 [warn] claude not found on PATH — using bundled schema baseline (cc_version: %s)' "$_SCHEMA_CC_VER")"
    _CC_VER="$_SCHEMA_CC_VER"
    # claude absent (or unparseable) → skip the forward-compat comparison below.
    _CC_PRESENT=0
  fi

  _SCHEMA_GEN="$(jq -r '.generated // "unknown"' "$SCHEMA_FILE" 2>/dev/null)"
  _schm04_out ""
  _schm04_out "── Schema Version Report (--schema) ──────────────────────────"
  _schm04_out "$(printf '  Bundled schema: CC v%s (lib/cc-schema.json generated %s)' "$_SCHEMA_CC_VER" "$_SCHEMA_GEN")"
  _schm04_out "$(printf '  Detected CC version: %s' "$_CC_VER")"
  _schm04_out ""
  _schm04_out "  Settings keys in this harness and CC version introduced:"
  # WR-05: collect keys whose introduced_version is NEWER than the detected CC
  # version into a tempfile so the post-loop WARN runs in the main shell
  # (the while-loop body is a subshell under the jq pipe).
  _SCHM04_NEWER="$(mktemp)"
  jq -r 'keys[]' "${TARGET}/.claude/settings.json" 2>/dev/null | while IFS= read -r _key; do
    _intro="$(jq -r --arg k "$_key" '.settings_keys[$k] // "unknown"' "$SCHEMA_FILE" 2>/dev/null)"
    _schm04_out "$(printf '    %-40s introduced: %s' "$_key" "$_intro")"
    # WR-05 comparison: flag keys the running CC cannot yet honor. Only when CC
    # was actually detected (_CC_PRESENT=1), the introduced version is a real
    # semver (not "all"/"unknown"), and introduced_version > detected CC version.
    if [ "$_CC_PRESENT" = "1" ] && \
       printf '%s\n' "$_intro" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
      # POSIX-safe numeric semver compare via sort -V: if the GREATER of the two
      # is _intro AND they differ, _intro is newer than the detected CC version.
      _greater="$(printf '%s\n%s\n' "$_CC_VER" "$_intro" | sort -V | tail -1)"
      if [ "$_greater" = "$_intro" ] && [ "$_intro" != "$_CC_VER" ]; then
        printf '%s|%s\n' "$_key" "$_intro" >> "$_SCHM04_NEWER"
      fi
    fi
  done
  _schm04_out "─────────────────────────────────────────────────────────────"

  # WR-05: emit an advisory WARN (never fail — newer-than-known is advisory per
  # the SCHM-04 non-goal) for each key introduced after the detected CC version.
  if [ -s "$_SCHM04_NEWER" ]; then
    while IFS='|' read -r _nk _nv; do
      [ -z "$_nk" ] && continue
      _schm04_out "$(printf 'SCHM-04 [warn] settings key "%s" was introduced in CC v%s, newer than detected CC v%s — your installed Claude Code may not honor it yet' "$_nk" "$_nv" "$_CC_VER")"
    done < "$_SCHM04_NEWER"
  fi
  rm -f "$_SCHM04_NEWER"

  # Staleness advisory (Pattern 4: BSD date || GNU date || skip)
  _GEN_FIELD="$(jq -r '.generated // empty' "$SCHEMA_FILE" 2>/dev/null)"
  if [ -n "$_GEN_FIELD" ]; then
    _GEN_EPOCH=$(date -j -f "%Y-%m-%d" "$_GEN_FIELD" "+%s" 2>/dev/null \
      || date -d "$_GEN_FIELD" "+%s" 2>/dev/null \
      || echo 0)
    if [ "$_GEN_EPOCH" != "0" ]; then
      _SCHEMA_AGE_DAYS=$(( ($(date +%s) - _GEN_EPOCH) / 86400 ))
      if [ "$_SCHEMA_AGE_DAYS" -gt 90 ]; then
        _schm04_out "$(printf 'SCHM-04 [warn] cc-schema.json is %s days old (>90) — Conjure update recommended' "$_SCHEMA_AGE_DAYS")"
      fi
    fi
  fi
fi  # end SCHM-04

# Schema failures override drift: exit 2 > exit 1 > exit 0
[ "$SCHEMA_FAIL" -gt 0 ] && exit 2
exit "$drift"
