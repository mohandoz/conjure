#!/usr/bin/env bash
# gates/approve.sh — per-class /dev/tty approve/skip/edit approval driver.
# Usage: CONJURE_HOME=<kit-root> bash approve.sh [manifest|target] [target]
#   - If $1 is a directory it is the TARGET; the manifest is <target>/adopt-manifest.json.
#   - If $1 is a file it is the MANIFEST; the TARGET is $2 (default: the manifest's dir).
#   - With no args, manifest = ./adopt-manifest.json and target = $(pwd).
# Exit codes: 0 = every non-empty bucket processed; 2 = non-TTY stdin / hard fail.
#   This driver NEVER exits 1 (project convention).
#
# The skill invokes this AFTER GATE A (verify-invariants) + GATE B (audit-staged)
# have already passed on the staging file (D-14). It groups files[] by the Phase 21
# 6-bucket classification (core skill agent planning-doc reference-doc unknown) in
# NON-archive order (D-15: archive ops are sequenced last by the SKILL.md, with each
# candidate routed through decision-scan.sh for individual-vs-bulk confirmation, D-11).
# For each non-empty bucket it presents ONE /dev/tty prompt (D-09): [a]pprove applies
# each proposed step in the bucket via `conjure adopt --apply-step` (the RESTR-02
# chokepoint through lib/mutate.sh) and logs ONE RESTRUCTURE summary line; [s]kip
# leaves the bucket as-is (one summary line); [e]dit signals the skill to re-draft and
# re-run the gates (no external editor is launched — O-3). Non-TTY stdin → exit 2,
# never auto-approve (D-12).

set -uo pipefail

# ── resolve CONJURE_HOME (kit root) ─────────────────────────────────────────────
# From a TARGET repo's .claude/skills/restructure/gates/, the kit is not a relative
# hop away, so the skill exports CONJURE_HOME. Default to a best-effort resolution.
CONJURE_HOME="${CONJURE_HOME:-$(cd "$(dirname "$0")/../../../.." && pwd)}"

# ── NON-TTY GUARD FIRST (D-12) — fires before any arg interpretation so that a
#    non-interactive drive (< /dev/null) always exits 2 and NEVER auto-approves.
#    WR-02: CONJURE_FORCE_INTERACTIVE=1 is a TEST-ONLY escape hatch (mirrors
#    resolve.sh:34 / adopt.sh:808) — the production skill MUST NEVER set or inherit it,
#    or a piped 'a' would auto-approve with no human at a terminal (SKILL.md forbids it).
if ! { [ -t 0 ] || [ "${CONJURE_FORCE_INTERACTIVE:-0}" = "1" ]; }; then
  echo "restructure: stdin is not a TTY — interactive approval required" >&2
  exit 2
fi

# ── resolve manifest + target from the (flexible) positional args ───────────────
ARG1="${1:-}"
ARG2="${2:-}"
if [ -n "$ARG1" ] && [ -d "$ARG1" ]; then
  TARGET="$ARG1"
  MANIFEST="$TARGET/adopt-manifest.json"
elif [ -n "$ARG1" ] && [ -f "$ARG1" ]; then
  MANIFEST="$ARG1"
  TARGET="${ARG2:-$(cd "$(dirname "$ARG1")" && pwd)}"
else
  TARGET="${ARG2:-$(pwd)}"
  MANIFEST="${ARG1:-$TARGET/adopt-manifest.json}"
fi

# ── source the mutation chokepoint + the durable log writer ─────────────────────
# DRY_RUN defaults to live so the bulk-summary log line is actually written.
export DRY_RUN="${DRY_RUN:-0}"
# shellcheck source=/dev/null
source "$CONJURE_HOME/lib/mutate.sh" || { echo "approve.sh: cannot source lib/mutate.sh" >&2; exit 2; }
# shellcheck source=/dev/null
source "$CONJURE_HOME/lib/log.sh" || { echo "approve.sh: cannot source lib/log.sh" >&2; exit 2; }

# Point the durable trail at the target. Reuse an existing log (apply-step may have
# created one); otherwise lay down a fresh header so log_step has a file to append to.
if [ -f "$TARGET/RESTRUCTURE-LOG.md" ]; then
  RESTRUCTURE_LOG_PATH="$TARGET/RESTRUCTURE-LOG.md"
else
  log_init "$TARGET"
fi

# ── locate the conjure CLI (the RESTR-02 seam) without depending on $PATH ────────
CONJURE_BIN="$CONJURE_HOME/cli/conjure"

if [ ! -r "$MANIFEST" ]; then
  echo "restructure: no manifest to approve at $MANIFEST" >&2
  exit 2
fi

# ── choose where the verb is read from ──────────────────────────────────────────
# In a genuine interactive session (stdin is a TTY) we read the verb from /dev/tty
# so a redirected stdin (the manifest/step lists, fed on other fds) does not consume
# the prompt. When the run is FORCED interactive (CONJURE_FORCE_INTERACTIVE=1 — the
# test harness and any non-/dev/tty context), /dev/tty may not exist, so we read the
# verb from stdin (fd 0) where the harness pipes it.
if [ -t 0 ]; then
  PROMPT_SRC="/dev/tty"
else
  PROMPT_SRC="/dev/stdin"
fi

# read_choice <out-var-is-CHOICE>: read one verb from PROMPT_SRC into the global
# CHOICE. Returns non-zero on EOF/read failure (so the caller can break cleanly under
# set -u instead of crashing on an unbound variable).
read_choice() {
  CHOICE=""
  if [ "$PROMPT_SRC" = "/dev/tty" ]; then
    read -r -p "  [a]pprove / [s]kip / [e]dit: " CHOICE < /dev/tty 2>/dev/null || return 1
  else
    printf '  [a]pprove / [s]kip / [e]dit: '
    read -r CHOICE || return 1
  fi
  return 0
}

# ── per-class grouped approval over the 6 NON-archive buckets (D-09) ─────────────
# Archive ops are sequenced LAST by the SKILL.md (D-15) and routed through
# decision-scan.sh; this driver groups only the non-archive classification buckets.
BUCKETS="core skill agent planning-doc reference-doc unknown"

for bucket in $BUCKETS; do
  count="$(jq -r --arg b "$bucket" '[.files[]?|select(.classification==$b)]|length' "$MANIFEST" 2>/dev/null)"
  [ "${count:-0}" -gt 0 ] || continue

  echo ""
  echo "Bucket: $bucket ($count file(s))"
  jq -r --arg b "$bucket" '.files[]?|select(.classification==$b)|.path' "$MANIFEST" 2>/dev/null \
    | head -5 | sed 's/^/  - /'
  [ "$count" -gt 5 ] && echo "  … and $((count - 5)) more"

  while true; do
    if ! read_choice; then
      # EOF / no more input — treat as skip so the bucket still logs one summary line.
      log_step RESTRUCTURE "skipped $bucket bucket (no response)"
      echo "  skipped (no response)"
      break
    fi
    case "$CHOICE" in
      a|approve)
        applied=0
        # IN-02: track failed applies too so the bucket summary does not silently
        # under-report (a path-rejected write must be visible to the human).
        failed=0
        # Apply every proposed step whose dest/src belongs to a file in this bucket.
        # Bucket membership keys on the file path appearing as the step dest or src.
        paths_tmp="$(mktemp)"
        jq -r --arg b "$bucket" '.files[]?|select(.classification==$b)|.path' "$MANIFEST" 2>/dev/null > "$paths_tmp"
        steps_tmp="$(mktemp)"
        # Collect step ids whose dest OR src references a path in this bucket. Read the
        # path list on fd 3 so the per-step apply can still use stdin/tty if needed.
        exec 3< "$paths_tmp"
        while IFS= read -r p <&3; do
          [ -n "$p" ] || continue
          # CR-01: EXCLUDE op:archive here. An archive step records the project file
          # being archived as .src, and that same file also appears in files[] under a
          # non-archive classification — so an unfiltered path match would apply the
          # archive DURING a non-archive bucket approval, violating D-15 (archive
          # sequenced LAST) and bypassing decision-scan.sh's individual-vs-bulk confirm
          # (the CR-6 bulk-archive-of-an-active-decision failure mode). Archive ops are
          # handled ONLY in the dedicated archive-last pass (SKILL.md step 6), which
          # routes each candidate through gates/decision-scan.sh (D-11). Also restrict
          # to status=="proposed" so an already-applied/skipped step is never re-applied.
          jq -r --arg p "$p" \
            '.restructure_steps[]?
             | select(.op != "archive")
             | select(.status == "proposed")
             | select((.dest==$p) or (.src==$p) or ((.src // "")|endswith("/"+$p)))
             | .id' \
            "$MANIFEST" 2>/dev/null >> "$steps_tmp"
        done
        exec 3<&-
        # Apply each distinct step id via the adopt seam (RESTR-02 chokepoint).
        exec 4< "$steps_tmp"
        while IFS= read -r id <&4; do
          [ -n "$id" ] || continue
          if bash "$CONJURE_BIN" adopt --apply-step "$id" "$TARGET" >/dev/null 2>&1; then
            applied=$((applied + 1))
          else
            failed=$((failed + 1))
          fi
        done
        exec 4<&-
        rm -f "$paths_tmp" "$steps_tmp"
        # ONE summary line for the whole bucket (D-09 / SAFE-07). IN-02: include the
        # failed count so a partially-applied bucket is not reported as fully done.
        log_step RESTRUCTURE "approved $bucket bucket — applied $applied step(s), $failed failed"
        echo "  approved ($applied step(s) applied, $failed failed)"
        break
        ;;
      s|skip)
        log_step RESTRUCTURE "skipped $bucket bucket"
        echo "  skipped"
        break
        ;;
      e|edit)
        # O-3: edit does NOT launch an external editor. It signals the skill (LLM) to re-draft the
        # staged content for this bucket, re-register it via `conjure adopt
        # --update-manifest`, and RE-RUN GATE A + GATE B before this prompt repeats.
        echo "  edit requested for the $bucket bucket:"
        echo "    1. The skill re-drafts the staged file(s) under .conjure-adopt-state/staging/."
        echo "    2. The skill re-registers the op: printf '%s' \"\$op\" | conjure adopt --update-manifest"
        echo "    3. The skill RE-RUNS gates/verify-invariants.sh (GATE A) + gates/audit-staged.sh (GATE B)."
        echo "  Re-run this approval once the re-draft passes both gates."
        # No break — re-prompt after the re-draft (D-10).
        ;;
      *)
        echo "  enter a, s, or e"
        # No break — no default (D-14: never auto-proceed on empty/unknown).
        ;;
    esac
  done
done

mutate_summary
exit 0
