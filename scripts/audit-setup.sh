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
[ "$FAIL" -gt 0 ] && exit 2
[ "$WARN" -gt 0 ] && exit 1
exit 0
