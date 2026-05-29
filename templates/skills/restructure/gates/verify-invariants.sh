#!/usr/bin/env bash
# gates/verify-invariants.sh — GATE A: deterministic normalized-substring invariant verifier.
# Usage: bash verify-invariants.sh <staging-claude.md> <INVARIANTS.txt>
# Exit codes: 0 = every invariant present, 2 = one or more dropped (BLOCK) / bad args.
# Runs BEFORE any human approval (D-14). NEVER exits 1 (project convention).
#
# Each line of INVARIANTS.txt is a short canonical token (e.g. `exit 2`, `@import`,
# `≤100`, `mutate.sh`, `do not delete`). The proposed CLAUDE.md is normalized
# (lowercase + whitespace-collapse + trim) into a single haystack line so that
# reflowed/condensed/case-mangled-but-content-complete files still pass (D-07).
#
# WR-03 / RESEARCH CR-1 (KNOWN LIMITATION — residual MEDIUM risk, accepted):
#   The present-check is a normalized SUBSTRING test (case "$HAYSTACK" in *"$needle"*),
#   so it is (a) granularity-blind: a short/common token (e.g. `exit 2`, `never`) can
#   match incidentally in unrelated prose or a code fence, and (b) POLARITY-blind: the
#   token `exit 2` is also satisfied by "do NOT exit 2", so an inverted rule passes.
#   No NLP negation detection is attempted here — it would risk false-BLOCKS on
#   invariants whose canonical token legitimately embeds a negation (e.g. the shipped
#   `do not delete`) and add complexity for little gain. The LLM proposer is the PRIMARY
#   safeguard (it must confirm distinctive multi-word tokens, e.g. `hooks exit 2` not
#   `exit 2`); this deterministic gate is the BACKSTOP that catches a wholesale dropped
#   invariant, not a semantic-inversion detector.

set -uo pipefail

STAGING_CLAUDE="${1:-}"
INVARIANTS_TXT="${2:-}"

if [ -z "$STAGING_CLAUDE" ] || [ -z "$INVARIANTS_TXT" ]; then
  echo "✗ verify-invariants: usage: verify-invariants.sh <staging-claude.md> <INVARIANTS.txt>" >&2
  exit 2
fi
if [ ! -r "$STAGING_CLAUDE" ]; then
  echo "✗ verify-invariants: cannot read staging file: $STAGING_CLAUDE" >&2
  exit 2
fi
if [ ! -r "$INVARIANTS_TXT" ]; then
  echo "✗ verify-invariants: cannot read invariants file: $INVARIANTS_TXT" >&2
  exit 2
fi

# Normalize: lowercase, collapse every run of whitespace to a single space, trim ends.
normalize() { tr '[:upper:]' '[:lower:]' | tr -s '[:space:]' ' ' | sed 's/^ //; s/ $//'; }

HAYSTACK="$(normalize < "$STAGING_CLAUDE")"

# bash-3.2-safe newline-delimited accumulator (no mapfile, no associative arrays).
missing=""
while IFS= read -r inv || [ -n "$inv" ]; do
  [ -n "$inv" ] || continue
  needle="$(printf '%s' "$inv" | normalize)"
  [ -n "$needle" ] || continue
  case "$HAYSTACK" in
    *"$needle"*) ;;                            # present
    *) missing="${missing}${inv}"$'\n' ;;      # dropped
  esac
done < "$INVARIANTS_TXT"

if [ -n "$missing" ]; then
  echo "✗ restructure: proposed CLAUDE.md is missing required invariants:" >&2
  # Print one missing token per line. $missing is newline-delimited; iterate with
  # IFS set to newline only so multi-word tokens (e.g. "do not delete") stay intact.
  while IFS= read -r m; do
    [ -n "$m" ] || continue
    printf '  - %s\n' "$m" >&2
  done <<EOF
$missing
EOF
  exit 2
fi

exit 0
