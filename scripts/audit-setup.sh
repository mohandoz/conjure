#!/usr/bin/env bash
# audit-setup.sh — health-check the .claude/ setup in a repo.
# Usage: bash audit-setup.sh [target-dir]
# Exit codes: 0 = pass, 1 = warnings, 2 = errors.

set -uo pipefail

: "${CONJURE_HOME:="$(cd "$(dirname "$0")/.." && pwd)"}"
# shellcheck source=lib/caps.sh
source "${CONJURE_HOME}/lib/caps.sh"
# build_deny_read_entries is the single source of truth for the denyRead→Read()
# path-prefix convention (WR-02). Sourcing policy-helpers.sh only defines
# functions (no top-level side effects); build_deny_read_entries depends solely
# on jq, so this is safe in the audit context without mutate/snapshot sourced.
# shellcheck source=lib/policy-helpers.sh
source "${CONJURE_HOME}/lib/policy-helpers.sh"

TARGET="${1:-$(pwd)}"
cd "$TARGET" || { echo "✗ Cannot cd to target: $TARGET"; exit 2; }

# SCHM-05: JSON mode — CONJURE_JSON=1 routes all human text to stderr and emits
# a single JSON object to stdout at the end (Phase 29 aggregation contract).
# CONJURE_PORCELAIN=1 (--budget --porcelain) similarly routes human text to
# stderr so stdout carries only the budget JSON object.
JSON_MODE="${CONJURE_JSON:-0}"
CONJURE_PORCELAIN="${CONJURE_PORCELAIN:-0}"
CHECKS_JSONL="$(mktemp)"
# Single EXIT trap for ALL tempfiles. bash has one EXIT trap slot — the later
# `--cost` block used to re-register its own trap and silently clobber this one,
# leaking CHECKS_JSONL (WR-03). _audit_cleanup rm -f's every tempfile the script
# may create; COST_TMP is unset unless --cost ran, and :- expands it to empty.
_audit_cleanup() { rm -f "${CHECKS_JSONL:-}" "${COST_TMP:-}" "${BUDGET_TMP:-}"; }
trap _audit_cleanup EXIT

PASS=0
WARN=0
FAIL=0

# human() — output one line of human-readable text.
# In normal mode: stdout. In JSON mode: stderr (stdout is reserved for the JSON object).
human() { { [ "$JSON_MODE" = "1" ] || [ "$CONJURE_PORCELAIN" = "1" ]; } && printf '%s\n' "$1" >&2 || printf '%s\n' "$1"; }

note() { human "  $1"; }
ok()   { note "✓ $1"; PASS=$((PASS+1)); }
warn() { note "⚠ $1"; WARN=$((WARN+1)); }
err()  { note "✗ $1"; FAIL=$((FAIL+1)); }

# json_check() — append a check record to CHECKS_JSONL when JSON_MODE=1.
# json_check <id> <severity> <message>
# No-op when JSON_MODE=0 (zero impact on normal mode).
json_check() {
  local _jc_id="$1" _jc_sev="$2" _jc_msg="$3"
  [ "$JSON_MODE" != "1" ] && return 0
  jq -cn \
    --arg id "$_jc_id" \
    --arg severity "$_jc_sev" \
    --arg message "$_jc_msg" \
    '{id: $id, severity: $severity, message: $message}' \
    >> "$CHECKS_JSONL"
}

human ""
human "Auditing .claude/ setup in: $TARGET"
human ""

# CLAUDE.md exists and within budget
if [ -f CLAUDE.md ]; then
  LINES=$(wc -l < CLAUDE.md | tr -d ' ')
  if [ "$LINES" -le "${CLAUDE_MD_CAP}" ]; then ok "CLAUDE.md: $LINES lines (≤${CLAUDE_MD_CAP})"
  elif [ "$LINES" -le "${SKILL_MD_CAP}" ]; then warn "CLAUDE.md: $LINES lines (within hard cap but over practical limit)"
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
    if [ "$LINES" -gt "${SKILL_MD_CAP}" ]; then warn "Skill '$name': $LINES lines (>${SKILL_MD_CAP})"; fi

    # Check frontmatter
    if ! head -10 "$skill" | grep -q '^name:'; then
      err "Skill '$name': missing 'name:' frontmatter"
    fi
    if ! head -10 "$skill" | grep -q '^description:'; then
      err "Skill '$name': missing 'description:' frontmatter"
    elif head -10 "$skill" | grep -qE '^description: "?.{0,29}"?$'; then
      warn "Skill '$name': description very short (<30 chars) — likely won't fire correctly"
    fi
  done < <(find .claude/skills -name SKILL.md)
else
  warn ".claude/skills/ missing"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Phase 27 — Schema checks (SCHM-01: SKILL.md frontmatter type validation)
# ─────────────────────────────────────────────────────────────────────────────

SCHEMA_FILE="${CONJURE_HOME}/lib/cc-schema.json"
if [ ! -f "$SCHEMA_FILE" ] || ! command -v jq >/dev/null 2>&1; then
  note "[schema] cc-schema.json not found at $SCHEMA_FILE — SCHM-01 skipped"
else
  while IFS= read -r skill; do
    _skill_name="$(basename "$(dirname "$skill")")"
    # shellcheck disable=SC2155
    _fm_block="$(awk '/^---$/{n++; if(n==2)exit; next} n==1{print}' "$skill")"
    # shellcheck disable=SC2155
    _known_fields="$(jq -r '.skill_frontmatter | keys[]' "$SCHEMA_FILE" 2>/dev/null)"

    # Check for unknown fields — warn (not fail)
    # Also collect JSON check records (id|message pairs) for --json mode.
    # IN-01: a parallel `_schm01_warn_jchecks` tempfile used to be written but
    # never read (the JSON record below sources `$_msg` from _schm01_warn_errs).
    # Removed the dead file. The emitted JSON message therefore carries the same
    # text as the human warning (suffix-inclusive) — unchanged behavior, no leak.
    _schm01_warn_errs="$(mktemp)"
    printf '%s\n' "$_fm_block" | grep -E '^[a-zA-Z]' | while IFS= read -r _fmline; do
      _field="$(printf '%s\n' "$_fmline" | cut -d: -f1)"
      if ! printf '%s\n' "$_known_fields" | grep -qxF "$_field"; then
        printf '%s\n' "Skill '$_skill_name': unknown frontmatter field '$_field' (not in CC schema — SCHM-01)" >> "$_schm01_warn_errs"
      fi
    done
    if [ -s "$_schm01_warn_errs" ]; then
      while IFS= read -r _msg; do
        warn "$_msg"
        json_check "SCHM-01-skill-unknown" "warn" "$_msg"
      done < "$_schm01_warn_errs"
    fi
    rm -f "$_schm01_warn_errs"

    # Detect object-typed fields using awk two-line lookahead (Pattern 1 from RESEARCH)
    # Inline object: fieldname: {  — Block mapping: empty-value key followed by indented word:
    _schm01_err_errs="$(mktemp)"
    printf '%s\n' "$_fm_block" | awk '
      /^[a-zA-Z]/ {
        split($0, a, /:[[:space:]]*/); key=a[1]; val=substr($0, index($0,":")+1); gsub(/^[[:space:]]+/,"",val)
        prev_key=key; prev_val=val
        if (val ~ /^\{/) { print "OBJECT_FIELD:" key }
        next
      }
      /^[[:space:]]+[a-zA-Z_-]+:/ && prev_key != "" && prev_val == "" {
        print "OBJECT_FIELD:" prev_key; prev_key=""
      }
    ' | while IFS= read -r _result; do
      _ofield="${_result#OBJECT_FIELD:}"
      # shellcheck disable=SC2155
      _expected="$(jq -r --arg f "$_ofield" '.skill_frontmatter[$f] // "unknown"' "$SCHEMA_FILE" 2>/dev/null)"
      if [ "$_expected" = "array-or-space-string" ] || [ "$_expected" = "string" ]; then
        printf '%s\n' "Skill '$_skill_name': field '$_ofield' is an object (YAML mapping) — expected $_expected (SCHM-01)" >> "$_schm01_err_errs"
      fi
    done
    if [ -s "$_schm01_err_errs" ]; then
      while IFS= read -r _msg; do
        err "$_msg"
        json_check "SCHM-01-skill-field" "fail" "$_msg"
      done < "$_schm01_err_errs"
    fi
    rm -f "$_schm01_err_errs"

  done < <(find .claude/skills -name SKILL.md 2>/dev/null)
fi

# Agents
if [ -d .claude/agents ]; then
  COUNT=$(find .claude/agents -maxdepth 1 -name '*.md' | wc -l | tr -d ' ')
  ok ".claude/agents/: $COUNT agents"

  while IFS= read -r agent; do
    name=$(basename "$agent" .md)
    LINES=$(wc -l < "$agent" | tr -d ' ')
    if [ "$LINES" -gt "${AGENT_MD_CAP}" ]; then warn "Agent '$name': $LINES lines (>${AGENT_MD_CAP})"; fi
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
  _mtime="$(stat -f %m graphify-out/graph.json 2>/dev/null \
             || stat -c %Y graphify-out/graph.json 2>/dev/null \
             || echo 0)"
  AGE_DAYS=$(( ( $(date +%s) - _mtime ) / 86400 ))
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

# EVAL-04 — Context Budget Linter (--budget flag)
# CONJURE_BUDGET=1 enables per-file token breakdown + threshold flags.
# CONJURE_PORCELAIN=1 emits JSON (budget --porcelain combination).
# BUDGET_TMP declared at top level so _audit_cleanup's ${BUDGET_TMP:-} is safe
# even when --budget was not passed.
BUDGET_TMP=""
if [ "${CONJURE_BUDGET:-0}" = "1" ]; then
  BUDGET_TMP="$(mktemp)"
  # ALWAYS-LOADED: CLAUDE.md
  if [ -f CLAUDE.md ]; then
    _chars="$(wc -c < CLAUDE.md | tr -d ' ')"
    _tokens=$((_chars / 4))
    printf '%s %s\n' "$_tokens" "CLAUDE.md" >> "$BUDGET_TMP"
  fi
  # ALWAYS-LOADED: each skill's SKILL.md (entire file — conservative)
  while IFS= read -r _skill_md; do
    [ -z "$_skill_md" ] && continue
    _chars="$(wc -c < "$_skill_md" | tr -d ' ')"
    _tokens=$((_chars / 4))
    _rel="${_skill_md#./}"
    printf '%s %s\n' "$_tokens" "$_rel" >> "$BUDGET_TMP"
  done < <(find .claude/skills -name SKILL.md 2>/dev/null)

  TOTAL_BUDGET_TOKENS="$(awk '{s+=$1} END{print s+0}' "$BUDGET_TMP")"

  # Thresholds: reuse existing 15k/25k tiers
  BUDGET_THRESHOLD_WARN=15000
  BUDGET_THRESHOLD_ERR=25000

  if [ "${CONJURE_PORCELAIN:-0}" = "1" ]; then
    # --porcelain JSON: { total_tokens, threshold, over, contributors[] }
    _top5_tmp="$(mktemp)"
    sort -rn "$BUDGET_TMP" | head -5 > "$_top5_tmp"
    _over="false"
    [ "$TOTAL_BUDGET_TOKENS" -ge "$BUDGET_THRESHOLD_ERR" ] && _over="true"
    _contrib_jsonl="$(mktemp)"
    while IFS=' ' read -r _tok _path; do
      jq -cn --arg path "$_path" --argjson tokens "$_tok" \
        '{path: $path, tokens: $tokens}' >> "$_contrib_jsonl"
    done < "$_top5_tmp"
    # WR-04: the process exit code here is the HOLISTIC audit verdict (governed
    # by the global FAIL/WARN summary gate at the bottom of this script), NOT the
    # budget status. A caller may see exit 1 purely because of unrelated warnings
    # (missing .claudeignore, docs/, …) even when the budget is well under
    # threshold (over:false). Consumers of --budget --porcelain MUST branch on
    # the JSON `over` field for budget status, not on $?. This contract is made
    # explicit via the `_comment` field below; the exit-code behaviour is the
    # established audit-summary-gate contract and is deliberately UNCHANGED.
    jq -cn \
      --argjson total "$TOTAL_BUDGET_TOKENS" \
      --argjson threshold "$BUDGET_THRESHOLD_ERR" \
      --argjson over "$_over" \
      --arg comment "budget status is the 'over' field; process exit code is the holistic audit verdict, not budget status" \
      --slurpfile contributors "$_contrib_jsonl" \
      '{total_tokens: $total, threshold: $threshold, over: $over, contributors: ($contributors | flatten), _comment: $comment}'
    rm -f "$_top5_tmp" "$_contrib_jsonl"
  else
    # Human output
    human "── Context Budget ─────────────────────────────────────"
    human "  Always-loaded: CLAUDE.md + skill SKILL.md indexes"
    human "  Estimated tokens: ~$TOTAL_BUDGET_TOKENS (chars/4 heuristic)"
    # Top 5 contributors
    sort -rn "$BUDGET_TMP" | head -5 | while IFS=' ' read -r _tok _path; do
      human "  $(printf '%-40s' "$_path") ~${_tok} tokens"
    done
    if [ "$TOTAL_BUDGET_TOKENS" -ge "$BUDGET_THRESHOLD_ERR" ]; then
      err "context budget: ~$TOTAL_BUDGET_TOKENS tokens (>=${BUDGET_THRESHOLD_ERR} — prune CLAUDE.md or skills)"
    elif [ "$TOTAL_BUDGET_TOKENS" -ge "$BUDGET_THRESHOLD_WARN" ]; then
      warn "context budget: ~$TOTAL_BUDGET_TOKENS tokens (>=${BUDGET_THRESHOLD_WARN} — watch for growth)"
    else
      ok "context budget: ~$TOTAL_BUDGET_TOKENS tokens (well-tuned)"
    fi
  fi
  rm -f "$BUDGET_TMP"
fi

# Conflict markers — detect unresolved 3-way merge conflicts (MERGE-05)
if [ -d .claude ]; then
  CONFLICT_FILES="$(grep -rl '^<<<<<<<' .claude/ 2>/dev/null \
    | grep -v '\.conjure-conflict-' || true)"
  if [ -n "$CONFLICT_FILES" ]; then
    err "Unresolved merge conflicts found in .claude/ — resolve and delete .conjure-conflict-* sidecars"
    printf '%s\n' "$CONFLICT_FILES" | while IFS= read -r cf; do
      [ -z "$cf" ] && continue
      note "  conflict markers: $cf"
    done
  else
    ok ".claude/: no unresolved conflict markers"
  fi
fi

# Org overlay presence and drift check (OVLY-04)
OVERLAY_MARKER="$TARGET/.claude/.conjure-org-overlay"
if [ ! -f "$OVERLAY_MARKER" ]; then
  ok "no org overlay configured"
else
  OVERLAY_URL="$(grep '^url=' "$OVERLAY_MARKER" | cut -d= -f2-)"
  PINNED_SHA="$(grep '^sha=' "$OVERLAY_MARKER" | cut -d= -f2)"
  if [ -z "$OVERLAY_URL" ]; then
    warn "[overlay] marker missing url= field — run conjure init --overlay again"
  else
    note "[overlay] url: $OVERLAY_URL"
    note "[overlay] pinned: $PINNED_SHA"
    UPSTREAM_SHA="$(git ls-remote -- "$OVERLAY_URL" HEAD 2>/dev/null | awk '{print $1}')" || true
    if [ -z "$UPSTREAM_SHA" ]; then
      warn "[overlay] drift check skipped (git ls-remote failed)"
    elif [ "$PINNED_SHA" = "$UPSTREAM_SHA" ]; then
      ok "[overlay] up to date ($PINNED_SHA)"
    else
      warn "[overlay] DRIFT — pinned=$PINNED_SHA upstream=$UPSTREAM_SHA — run: conjure refresh-overlay"
    fi
  fi
fi

# Plugin reconciliation (D-12 / PLUG-04): plugin.json out-of-sync with .claude/ harness → advisory note (exit 0)
# Advisory only — does not break CI gate. Nudges user to re-run: conjure publish-plugin
if [ -f ".claude-plugin/plugin.json" ] && command -v jq >/dev/null 2>&1; then
  PLUG_SKILLS_PATH="$(jq -r '.skills // empty' .claude-plugin/plugin.json 2>/dev/null)"
  if [ -n "$PLUG_SKILLS_PATH" ]; then
    if [ -d "$PLUG_SKILLS_PATH" ]; then
      ON_DISK_SKILL_COUNT="$(find "$PLUG_SKILLS_PATH" -name "SKILL.md" 2>/dev/null | wc -l | tr -d ' ')"
      if [ "$ON_DISK_SKILL_COUNT" -eq 0 ]; then
        note "⚠ [plugin] plugin.json lists skills path '$PLUG_SKILLS_PATH' but no SKILL.md found — re-run: conjure publish-plugin"
      else
        ok "[plugin] plugin.json skills path '$PLUG_SKILLS_PATH' matches on-disk skills ($ON_DISK_SKILL_COUNT found)"
      fi
    else
      note "⚠ [plugin] plugin.json lists skills path '$PLUG_SKILLS_PATH' but directory not found — re-run: conjure publish-plugin"
    fi
  else
    if [ -d ".claude/skills" ]; then
      ON_DISK_SKILL_COUNT="$(find ".claude/skills" -name "SKILL.md" 2>/dev/null | wc -l | tr -d ' ')"
      if [ "$ON_DISK_SKILL_COUNT" -gt 0 ]; then
        note "⚠ [plugin] plugin.json has no skills path but $ON_DISK_SKILL_COUNT skill(s) found in .claude/skills — re-run: conjure publish-plugin"
      fi
    fi
  fi
fi

# extraKnownMarketplaces ref-without-sha check (D-12 / D-16): advisory note (exit 0)
# Advisory only — sha pinning ensures reproducible installs. To fix: re-run: conjure publish-plugin --marketplace
if [ -f ".claude/settings.json" ] && command -v jq >/dev/null 2>&1; then
  REF_WITHOUT_SHA="$(jq -r '
    (.extraKnownMarketplaces // {}) | to_entries[] |
    select((.value.source.ref != null) and (.value.source.sha == null)) |
    .key' .claude/settings.json 2>/dev/null)" || true
  if [ -n "$REF_WITHOUT_SHA" ]; then
    while IFS= read -r mkt_name; do
      [ -z "$mkt_name" ] && continue
      note "⚠ [plugin] extraKnownMarketplaces '$mkt_name': has ref but no sha — re-run: conjure publish-plugin --marketplace"
    done <<MKT_NAMES_EOF
$REF_WITHOUT_SHA
MKT_NAMES_EOF
  fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# Phase 26 — Policy checks (POL-05a/b/c + advisory)
# ─────────────────────────────────────────────────────────────────────────────

# Detect active compliance overlay via <!-- compliance:REGIME --> marker in CLAUDE.md.
# The same marker is emitted by compliance/<regime>/apply.sh.
_pol_regime="$(grep -oE '<!-- compliance:(hipaa|soc2|gdpr|pci) -->' CLAUDE.md 2>/dev/null \
  | sed 's/<!-- compliance://;s/ -->//' | head -1)"

# SCHM-02 — disableBypassPermissionsMode type check (replaces Phase 26 POL-05c).
# Checks BOTH the top-level path AND the permissions.* sub-path.
# A boolean disableBypassPermissionsMode is always wrong; the correct value is string "disable".
# (D-SCHM-02 per 27-CONTEXT.md; subsumes POL-05c which only checked the permissions. path)
if [ -f ".claude/settings.json" ] && command -v jq >/dev/null 2>&1; then
  _schm02_errs="$(mktemp)"
  printf '%s\n' '.permissions.disableBypassPermissionsMode' '.disableBypassPermissionsMode' | while IFS= read -r _dbpm_path; do
    # shellcheck disable=SC2155
    _dbpm_type="$(jq -r "${_dbpm_path} | type" .claude/settings.json 2>/dev/null || echo null)"
    # WR-01: use `tostring` (not `// empty`). jq treats boolean `false` as falsy,
    # so `// empty` collapsed `false` to "" and the failure message printed a
    # blank value. `tostring` yields "true"/"false" verbatim; this branch only
    # runs when type=="boolean", so the key is always present (no null guard).
    # shellcheck disable=SC2155
    _dbpm_val="$(jq -r "${_dbpm_path} | tostring" .claude/settings.json 2>/dev/null || echo '')"
    if [ "$_dbpm_type" = "boolean" ]; then
      printf '%s\n' "[schema] disableBypassPermissionsMode is boolean (got: $_dbpm_val at ${_dbpm_path}) — must be string \"disable\" (SCHM-02)" >> "$_schm02_errs"
    fi
  done
  if [ -s "$_schm02_errs" ]; then
    while IFS= read -r _msg; do
      err "$_msg"
      json_check "SCHM-02-disablebypass" "fail" "$_msg"
    done < "$_schm02_errs"
  fi
  rm -f "$_schm02_errs"
fi

# POL-05a — compliance overlay active but sandbox.enabled not true.
if [ -n "$_pol_regime" ] && [ -f ".claude/settings.json" ] && command -v jq >/dev/null 2>&1; then
  _sandbox_enabled="$(jq -r '.sandbox.enabled // false' .claude/settings.json 2>/dev/null)"
  if [ "$_sandbox_enabled" != "true" ]; then
    err "[policy:$_pol_regime] compliance overlay active but sandbox.enabled is not true — run: conjure emit-policy --regime $_pol_regime"
  fi
elif [ -n "$_pol_regime" ] && [ -f ".claude/settings.json" ] && ! command -v jq >/dev/null 2>&1; then
  note "[policy] jq not found — policy checks skipped (install jq to enable POL-05 audit)"
fi

# POL-05b — denyRead path with no matching Read() in permissions.deny.
# Uses a tempfile to collect errors from the while-loop subshell so the FAIL
# counter (incremented by err()) is updated in the main shell (not the subshell).
if [ -n "$_pol_regime" ] && [ -f ".claude/settings.json" ] && command -v jq >/dev/null 2>&1; then
  _deny_paths="$(jq -r '.sandbox.filesystem.denyRead // [] | .[]' .claude/settings.json 2>/dev/null)"
  _perm_deny="$(jq -r '.permissions.deny // [] | .[]' .claude/settings.json 2>/dev/null)"
  _pol_b_errs="$(mktemp)"
  printf '%s\n' "$_deny_paths" | while IFS= read -r _dpath; do
    [ -z "$_dpath" ] && continue
    # Derive the expected Read() entry via build_deny_read_entries — the SAME
    # path-prefix convention emit uses (WR-02). Grepping the raw path produced a
    # double-slash mismatch (emit writes Read(//abs); raw grep sought Read(/abs)),
    # falsely failing audit on the first absolute denyRead path. Reuse the helper
    # as single source of truth instead of re-implementing the prefix rules.
    _expect="$(build_deny_read_entries "$(jq -nc --arg p "$_dpath" '[$p]')")"
    if ! printf '%s\n' "$_perm_deny" | grep -qF "$_expect"; then
      printf '%s\n' "[policy:$_pol_regime] denyRead path '$_dpath' has no matching $_expect in permissions.deny (POL-02 enforcement gap)" >> "$_pol_b_errs"
    fi
  done
  if [ -s "$_pol_b_errs" ]; then
    while IFS= read -r _msg; do err "$_msg"; done < "$_pol_b_errs"
  fi
  rm -f "$_pol_b_errs"
fi

# POL-05-advisory — unreviewed template placeholder still present.
# Detection keys off REPLACE_WITH_ORG_UUID ONLY (RESEARCH.md Open Questions RESOLVED Q1).
# Uses note() — does NOT increment any counter; exits 0 for advisory-only findings.
if [ -f "conjure-policy/managed-settings.json" ]; then
  if grep -qF "REPLACE_WITH_ORG_UUID" "conjure-policy/managed-settings.json" 2>/dev/null; then
    note "⚠ [policy] managed-settings.json contains unreviewed template values (REPLACE_WITH_ORG_UUID) — customize forceLoginOrgUUID before deploying"
  fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# SCHM-STALE — cc-schema.json staleness advisory (>90 days → WARN, never FAIL)
# ─────────────────────────────────────────────────────────────────────────────
if [ -f "$SCHEMA_FILE" ] && command -v jq >/dev/null 2>&1; then
  SCHEMA_GENERATED="$(jq -r '.generated // empty' "$SCHEMA_FILE" 2>/dev/null)"
  if [ -n "$SCHEMA_GENERATED" ]; then
    # Cross-platform epoch: BSD date (macOS) || GNU date (Linux) || 0 (skip)
    GEN_EPOCH=$(date -j -f "%Y-%m-%d" "$SCHEMA_GENERATED" "+%s" 2>/dev/null \
      || date -d "$SCHEMA_GENERATED" "+%s" 2>/dev/null \
      || echo 0)
    if [ "$GEN_EPOCH" != "0" ]; then
      SCHEMA_AGE_DAYS=$(( ( $(date +%s) - GEN_EPOCH ) / 86400 ))
      if [ "$SCHEMA_AGE_DAYS" -gt 90 ]; then
        warn "cc-schema.json is ${SCHEMA_AGE_DAYS} days old (>90) — Conjure update recommended for latest CC schema"
        json_check "SCHM-STALE" "warn" "cc-schema.json is ${SCHEMA_AGE_DAYS} days old (>90) — Conjure update recommended"
      fi
    fi
  fi
fi

# EVAL-05 — Coverage Gap Report: diff installed skills vs skill-used assertions.
# Always runs (no gate condition) — advisory note() only; never exit 2.
# _eval_extract_skill_used defined BEFORE its call site (no forward reference).
_eval_extract_skill_used() {
  # Anchor extraction to the `type: skill-used` assertion and stay in-block until
  # the next list item (`- `) regardless of intervening keys (e.g. description:),
  # so a reordered `type: ... / description: ... / value: ...` block still
  # extracts. Comment lines (#) are skipped so commented-out assertions do not
  # leak ghost skill names into the gap diff (WR-03).
  awk '
    /^[[:space:]]*#/ { next }
    /type:[[:space:]]*skill-used/ { in_assert=1; next }
    in_assert && /^[[:space:]]*value:[[:space:]]*/ {
      sub(/^[[:space:]]*value:[[:space:]]*/, "")
      sub(/[[:space:]]*$/, "")
      gsub(/'"'"'/, "")
      gsub(/"/, "")
      print
      in_assert=0
      next
    }
    /^[[:space:]]*-[[:space:]]/ { in_assert=0 }
  ' "$1"
}

# cwd is already $TARGET (the `cd "$TARGET"` on line 19), so reference the config
# relative to cwd. Using "$TARGET/..." here doubled the path for RELATIVE target
# args (e.g. `audit-setup.sh myrepo` → myrepo/myrepo/.conjure/...), silently
# disabling the whole EVAL-05 coverage report with a misleading "no eval config"
# note. This matches the sibling cwd-relative `find .claude/skills` call below (WR-01).
_eval_cfg=".conjure/eval/promptfooconfig.yaml"
if [ ! -f "$_eval_cfg" ]; then
  note "no eval config — run \`conjure eval init\` (EVAL-05)"
  json_check "EVAL-05-no-config" "note" "no eval config — run conjure eval init"
else
  _asserted_tmp="$(mktemp)"
  _installed_tmp="$(mktemp)"
  _gap_tmp="$(mktemp)"
  _eval_extract_skill_used "$_eval_cfg" | sort > "$_asserted_tmp"
  find .claude/skills -name SKILL.md 2>/dev/null \
    | sed 's|.*/skills/||;s|/SKILL.md||' \
    | sort > "$_installed_tmp"
  comm -23 "$_installed_tmp" "$_asserted_tmp" > "$_gap_tmp"
  if [ -s "$_gap_tmp" ]; then
    while IFS= read -r _skill; do
      [ -z "$_skill" ] && continue
      note "⚠ [eval] skill '$_skill' has no skill-used assertion — run \`conjure eval init\` to update"
      json_check "EVAL-05-gap" "note" "skill '$_skill' has no skill-used assertion in eval config"
    done < "$_gap_tmp"
  else
    ok "eval coverage: all installed skills have skill-used assertions"
  fi
  rm -f "$_asserted_tmp" "$_installed_tmp" "$_gap_tmp"
fi

# Summary
human ""
human "─────────────────────────────────────"
human "PASS: $PASS    WARN: $WARN    FAIL: $FAIL"
human "─────────────────────────────────────"

if [ "${CONJURE_COST:-0}" = "1" ]; then
  : "${CONJURE_HOME:="$(cd "$(dirname "$0")/.." && pwd)"}"
  PRICE_FILE="$CONJURE_HOME/lib/prices.json"

  if [ ! -f "$PRICE_FILE" ]; then
    human "  [--cost] prices.json missing at $PRICE_FILE"
  elif ! command -v jq >/dev/null 2>&1; then
    human "  [--cost] jq not installed — install jq to use cost estimation"
  else
    MODEL=$(jq -r '.default_model // empty' "$PRICE_FILE")
    PRICE_INPUT=$(jq -r --arg m "$MODEL" '.models[] | select(.model==$m) | .input_per_mtok' "$PRICE_FILE")
    if [ -z "$PRICE_INPUT" ]; then
      human "  [--cost] model '$MODEL' not found in prices.json — skipping cost estimate"
    else
      PRICING_DATE=$(jq -r --arg m "$MODEL" '.models[] | select(.model==$m) | .pricing_date' "$PRICE_FILE")
      BAND_PCT=$(jq -r --arg m "$MODEL" '.models[] | select(.model==$m) | .band_pct' "$PRICE_FILE")

      TOKENS_TO_USE="${EST_TOKENS:-0}"

      if [ "${CONJURE_EXACT:-0}" = "1" ]; then
        if [ -z "${ANTHROPIC_API_KEY:-}" ]; then
          human "  [--exact] ANTHROPIC_API_KEY not set — falling back to chars/4 heuristic."
        elif command -v node >/dev/null 2>&1 && [ -f "$CONJURE_HOME/lib/exact-count.mjs" ]; then
          EXACT_TOKENS=$(node "$CONJURE_HOME/lib/exact-count.mjs" "$TARGET" 2>/dev/null)
          if [ $? -eq 0 ] && [ -n "$EXACT_TOKENS" ]; then
            TOKENS_TO_USE="$EXACT_TOKENS"
          else
            human "  [--exact] exact count failed — falling back to chars/4 heuristic."
          fi
        fi
      fi

      TOTAL_COST=$(awk "BEGIN {printf \"%.2f\", $TOKENS_TO_USE * $PRICE_INPUT / 1000000}")

      COST_TMP=$(mktemp)
      # No per-block EXIT trap here — _audit_cleanup (registered near line 25)
      # already rm -f's COST_TMP. Re-registering would clobber the CHECKS_JSONL
      # cleanup and leak it (WR-03).

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

      human ""
      human "── Cost Estimate ──────────────────────────────────────"
      [ "$JSON_MODE" != "1" ] && printf "  %-30s %8s %8s %12s\n" "File" "Chars" "~Tokens" "Est.Cost"
      [ "$JSON_MODE" != "1" ] && printf "  %-30s %8s %8s %12s\n" "----" "-----" "-------" "--------"
      [ "$JSON_MODE" != "1" ] && sort -t' ' -k4 -rn "$COST_TMP" | while IFS=' ' read -r name chars tokens cost; do
        printf "  %-30s %8s %8s  \$%10.6f\n" "$name" "$chars" "$tokens" "$cost"
      done
      [ "$JSON_MODE" != "1" ] && printf "  %-30s %8s %8s  \$%10.2f\n" "TOTAL" "${TOTAL_CHARS:-0}" "$TOKENS_TO_USE" "$TOTAL_COST"
      human "  Estimate: \$$TOTAL_COST ±${BAND_PCT}% (chars/4 heuristic · prices: $PRICING_DATE · model: $MODEL)"
    fi
  fi
fi

if [ "${CONJURE_RETIRE:-0}" = "1" ]; then
  : "${CONJURE_HOME:="$(cd "$(dirname "$0")/.." && pwd)"}"
  LOG="$TARGET/.claude/telemetry/skill-events.jsonl"

  if ! command -v jq >/dev/null 2>&1; then
    human "  [--retire-list] jq not installed — install jq to use retire-list"
  elif [ ! -f "$LOG" ]; then
    human ""
    human "── Skill Retire-List ──────────────────────────────────"
    human "  No telemetry data. Enable with CONJURE_TELEMETRY=1 in .claude/settings.json env."
  else
    CUTOFF=$(date -v-30d -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null \
             || date -u -d '30 days ago' '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null \
             || echo "0000-00-00T00:00:00Z")

    human ""
    human "── Skill Retire-List ──────────────────────────────────"

    # Cross-reference installed skills against telemetry counts.
    # Skills with zero fires in the last 30 days are invisible in the JSONL log;
    # iterating installed SKILL.md files is the only way to surface them.
    SKILL_PATHS=()
    while IFS= read -r skill_path; do
      SKILL_PATHS+=("$skill_path")
    done < <(find "$TARGET/.claude/skills" -name SKILL.md 2>/dev/null)

    if [ "${#SKILL_PATHS[@]}" -eq 0 ]; then
      human "  No installed skills found in $TARGET/.claude/skills/."
    else
      [ "$JSON_MODE" != "1" ] && printf "  %-35s %6s %8s\n" "Skill" "Loads" "Status"
      [ "$JSON_MODE" != "1" ] && printf "  %-35s %6s %8s\n" "-----" "-----" "------"
      for skill_path in "${SKILL_PATHS[@]}"; do
        name=$(basename "$(dirname "$skill_path")")
        count=$(jq -r --arg c "$CUTOFF" --arg s "$name" \
          'select(.ts >= $c and .skill == $s) | .skill' "$LOG" 2>/dev/null | wc -l | tr -d ' ')
        if [ "${count:-0}" -gt 0 ]; then
          status="[active]"
        else
          status="[retire?]"
        fi
        [ "$JSON_MODE" != "1" ] && printf "  %-35s %6s %8s\n" "$name" "$count" "$status"
      done
    fi
  fi
fi

# SCHM-05 — JSON emission: emit single JSON object to stdout when CONJURE_JSON=1.
# All human-readable output has been routed to stderr via human() above.
# Exit codes are PRESERVED: same [ "$FAIL" -gt 0 ] && exit 2 gate applies.
if [ "$JSON_MODE" = "1" ]; then
  _json_status="pass"
  [ "$FAIL" -gt 0 ] && _json_status="fail"
  [ "$WARN" -gt 0 ] && [ "$_json_status" = "pass" ] && _json_status="warn"
  jq -cn \
    --arg schema_version "1" \
    --arg status "$_json_status" \
    --argjson summary "{\"pass\":$PASS,\"warn\":$WARN,\"fail\":$FAIL}" \
    --slurpfile checks "$CHECKS_JSONL" \
    '{schema_version: $schema_version, status: $status, checks: ($checks | flatten), summary: $summary}'
fi

[ "$FAIL" -gt 0 ] && exit 2
[ "$WARN" -gt 0 ] && exit 1
exit 0
