#!/usr/bin/env bash
# audit-setup.sh — health-check the .claude/ setup in a repo.
# Usage: bash audit-setup.sh [target-dir]
# Exit codes: 0 = pass, 1 = warnings, 2 = errors.

set -uo pipefail

TARGET="${1:-$(pwd)}"
cd "$TARGET"

PASS=0
WARN=0
FAIL=0
note() { echo "  $1"; }
ok()   { note "✓ $1"; PASS=$((PASS+1)); }
warn() { note "⚠ $1"; WARN=$((WARN+1)); }
err()  { note "✗ $1"; FAIL=$((FAIL+1)); }

echo
echo "Auditing .claude/ setup in: $TARGET"
echo

# CLAUDE.md exists and within budget
if [ -f CLAUDE.md ]; then
  LINES=$(wc -l < CLAUDE.md | tr -d ' ')
  if [ "$LINES" -le 100 ]; then ok "CLAUDE.md: $LINES lines (≤100)"
  elif [ "$LINES" -le 200 ]; then warn "CLAUDE.md: $LINES lines (within hard cap but over practical limit)"
  else err "CLAUDE.md: $LINES lines (HARD CAP exceeded — trim)"
  fi

  if grep -q '^@' CLAUDE.md; then
    err "CLAUDE.md contains @imports — they load eagerly. Replace with prose links."
  else
    ok "CLAUDE.md: no @imports"
  fi
else
  err "CLAUDE.md missing"
fi

# .claudeignore
[ -f .claudeignore ] && ok ".claudeignore present" || warn ".claudeignore missing (Claude may read large generated files)"

# .claude/ structure
[ -d .claude ] && ok ".claude/ directory exists" || { err ".claude/ missing — run init-project.sh"; exit 2; }

# Skills
if [ -d .claude/skills ]; then
  COUNT=$(find .claude/skills -name SKILL.md | wc -l | tr -d ' ')
  ok ".claude/skills/: $COUNT skills"

  while IFS= read -r skill; do
    name=$(basename "$(dirname "$skill")")
    LINES=$(wc -l < "$skill" | tr -d ' ')
    if [ "$LINES" -gt 200 ]; then warn "Skill '$name': $LINES lines (>200)"; fi

    # Check frontmatter
    if ! head -10 "$skill" | grep -q '^name:'; then
      err "Skill '$name': missing 'name:' frontmatter"
    fi
    if ! head -10 "$skill" | grep -q '^description:'; then
      err "Skill '$name': missing 'description:' frontmatter"
    elif head -10 "$skill" | grep -q '^description: ".\{0,30\}"$'; then
      warn "Skill '$name': description very short (<30 chars) — likely won't fire correctly"
    fi
  done < <(find .claude/skills -name SKILL.md)
else
  warn ".claude/skills/ missing"
fi

# Agents
if [ -d .claude/agents ]; then
  COUNT=$(find .claude/agents -maxdepth 1 -name '*.md' | wc -l | tr -d ' ')
  ok ".claude/agents/: $COUNT agents"

  while IFS= read -r agent; do
    name=$(basename "$agent" .md)
    LINES=$(wc -l < "$agent" | tr -d ' ')
    if [ "$LINES" -gt 80 ]; then warn "Agent '$name': $LINES lines (>80)"; fi
  done < <(find .claude/agents -maxdepth 1 -name '*.md')
else
  warn ".claude/agents/ missing"
fi

# Hooks
if [ -f .claude/settings.json ]; then
  if command -v jq >/dev/null 2>&1; then
    if jq empty .claude/settings.json 2>/dev/null; then
      ok ".claude/settings.json: valid JSON"
    else
      err ".claude/settings.json: INVALID JSON"
    fi
  else
    warn "jq not installed — can't validate settings.json"
  fi

  # Hook scripts present (.mjs — invoked via node, not as executables)
  if [ -d .claude/hooks ]; then
    while IFS= read -r hook; do
      if [ -f "$hook" ]; then ok "Hook present: $(basename "$hook")"
      else err "Hook MISSING: $(basename "$hook") — re-run conjure init"
      fi
    done < <(find .claude/hooks -maxdepth 1 -name '*.mjs')
  fi
else
  warn ".claude/settings.json missing — no hooks active"
fi

# Standard docs
[ -f docs/ARCHITECTURE.md ] && ok "docs/ARCHITECTURE.md present" || warn "docs/ARCHITECTURE.md missing"
[ -f docs/RUNBOOK.md ]      && ok "docs/RUNBOOK.md present"      || warn "docs/RUNBOOK.md missing"
[ -d docs/adr ]             && ok "docs/adr/ present"            || warn "docs/adr/ missing"
[ -f .env.example ]         && ok ".env.example present"         || warn ".env.example missing"

# graphify freshness
if [ -f graphify-out/graph.json ]; then
  AGE_DAYS=$(( ($(date +%s) - $(stat -f %m graphify-out/graph.json 2>/dev/null || stat -c %Y graphify-out/graph.json)) / 86400 ))
  if [ "$AGE_DAYS" -gt 7 ]; then warn "graphify graph is $AGE_DAYS days old — run: graphify . --update"
  else ok "graphify graph: $AGE_DAYS days old"
  fi
fi

# Total token estimate
if [ -d .claude ]; then
  TOTAL_CHARS=$(find .claude -type f \( -name '*.md' -o -name '*.json' \) -exec cat {} + 2>/dev/null | wc -c | tr -d ' ')
  EST_TOKENS=$((TOTAL_CHARS / 4))
  if [ "$EST_TOKENS" -lt 15000 ]; then ok ".claude/ token estimate: ~$EST_TOKENS (well-tuned)"
  elif [ "$EST_TOKENS" -lt 25000 ]; then warn ".claude/ token estimate: ~$EST_TOKENS (acceptable, watch for growth)"
  else err ".claude/ token estimate: ~$EST_TOKENS (over budget — prune)"
  fi
fi

# Summary
echo
echo "─────────────────────────────────────"
echo "PASS: $PASS    WARN: $WARN    FAIL: $FAIL"
echo "─────────────────────────────────────"

if [ "${CONJURE_COST:-0}" = "1" ]; then
  : "${CONJURE_HOME:="$(cd "$(dirname "$0")/.." && pwd)"}"
  PRICE_FILE="$CONJURE_HOME/lib/prices.json"

  if ! command -v jq >/dev/null 2>&1; then
    echo "  [--cost] jq not installed — install jq to use cost estimation"
  else
    MODEL=$(jq -r '.default_model' "$PRICE_FILE")
    PRICE_INPUT=$(jq -r --arg m "$MODEL" '.models[] | select(.model==$m) | .input_per_mtok' "$PRICE_FILE")
    PRICING_DATE=$(jq -r --arg m "$MODEL" '.models[] | select(.model==$m) | .pricing_date' "$PRICE_FILE")
    BAND_PCT=$(jq -r --arg m "$MODEL" '.models[] | select(.model==$m) | .band_pct' "$PRICE_FILE")

    TOKENS_TO_USE="${EST_TOKENS:-0}"

    if [ "${CONJURE_EXACT:-0}" = "1" ]; then
      if [ -z "${ANTHROPIC_API_KEY:-}" ]; then
        echo "  [--exact] ANTHROPIC_API_KEY not set — falling back to chars/4 heuristic."
      elif command -v node >/dev/null 2>&1 && [ -f "$CONJURE_HOME/lib/exact-count.mjs" ]; then
        EXACT_TOKENS=$(node "$CONJURE_HOME/lib/exact-count.mjs" "$TARGET" 2>/dev/null)
        if [ $? -eq 0 ] && [ -n "$EXACT_TOKENS" ]; then
          TOKENS_TO_USE="$EXACT_TOKENS"
        else
          echo "  [--exact] exact count failed — falling back to chars/4 heuristic."
        fi
      fi
    fi

    TOTAL_COST=$(awk "BEGIN {printf \"%.2f\", $TOKENS_TO_USE * $PRICE_INPUT / 1000000}")

    COST_TMP=$(mktemp)
    trap 'rm -f "$COST_TMP"' EXIT

    for ctx_file in CLAUDE.md .claude/settings.json; do
      if [ -f "$ctx_file" ]; then
        chars=$(wc -c < "$ctx_file" | tr -d ' ')
        tokens=$((chars / 4))
        cost=$(awk "BEGIN {printf \"%.6f\", $tokens * $PRICE_INPUT / 1000000}")
        printf '%s %s %s %s\n' "$ctx_file" "$chars" "$tokens" "$cost" >> "$COST_TMP"
      fi
    done

    while IFS= read -r skill; do
      chars=$(wc -c < "$skill" | tr -d ' ')
      tokens=$((chars / 4))
      cost=$(awk "BEGIN {printf \"%.6f\", $tokens * $PRICE_INPUT / 1000000}")
      printf '%s %s %s %s\n' "$skill" "$chars" "$tokens" "$cost" >> "$COST_TMP"
    done < <(find .claude/skills -name SKILL.md 2>/dev/null)

    echo
    echo "── Cost Estimate ──────────────────────────────────────"
    printf "  %-30s %8s %8s %12s\n" "File" "Chars" "~Tokens" "Est.Cost"
    printf "  %-30s %8s %8s %12s\n" "----" "-----" "-------" "--------"
    sort -t' ' -k4 -rn "$COST_TMP" | while IFS=' ' read -r name chars tokens cost; do
      printf "  %-30s %8s %8s  \$%10.6f\n" "$name" "$chars" "$tokens" "$cost"
    done
    printf "  %-30s %8s %8s  \$%10.2f\n" "TOTAL" "${TOTAL_CHARS:-0}" "$TOKENS_TO_USE" "$TOTAL_COST"
    echo "  Estimate: \$$TOTAL_COST ±${BAND_PCT}% (chars/4 heuristic · prices: $PRICING_DATE · model: $MODEL)"
  fi
fi

if [ "${CONJURE_RETIRE:-0}" = "1" ]; then
  : "${CONJURE_HOME:="$(cd "$(dirname "$0")/.." && pwd)"}"
  LOG="$TARGET/.claude/telemetry/skill-events.jsonl"

  if ! command -v jq >/dev/null 2>&1; then
    echo "  [--retire-list] jq not installed — install jq to use retire-list"
  elif [ ! -f "$LOG" ]; then
    echo
    echo "── Skill Retire-List ──────────────────────────────────"
    echo "  No telemetry data. Enable with CONJURE_TELEMETRY=1 in .claude/settings.json env."
  else
    CUTOFF=$(date -v-30d -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null \
             || date -u -d '30 days ago' '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null \
             || echo "0000-00-00T00:00:00Z")

    RETIRE_TMP=$(mktemp)
    # Combine with any existing EXIT trap to avoid overwriting COST_TMP cleanup
    trap 'rm -f "${COST_TMP:-}" "${RETIRE_TMP:-}"' EXIT

    # Count skill loads in last 30 days; jq outputs one skill name per matching line
    jq -r --arg c "$CUTOFF" 'select(.ts >= $c) | .skill' "$LOG" 2>/dev/null \
      | sort | uniq -c | sort -rn > "$RETIRE_TMP" 2>/dev/null || true

    echo
    echo "── Skill Retire-List ──────────────────────────────────"

    if ! [ -s "$RETIRE_TMP" ]; then
      echo "  No telemetry data in last 30 days."
    else
      printf "  %-35s %6s %8s\n" "Skill" "Loads" "Status"
      printf "  %-35s %6s %8s\n" "-----" "-----" "------"
      while IFS= read -r line; do
        count=$(printf '%s' "$line" | awk '{print $1}')
        name=$(printf '%s' "$line" | awk '{$1=""; print $0}' | xargs)
        if [ "${count:-0}" -gt 0 ]; then
          status="[active]"
        else
          status="[retire?]"
        fi
        printf "  %-35s %6s %8s\n" "$name" "$count" "$status"
      done < "$RETIRE_TMP"
    fi
  fi
fi

[ "$FAIL" -gt 0 ] && exit 2
[ "$WARN" -gt 0 ] && exit 1
exit 0
