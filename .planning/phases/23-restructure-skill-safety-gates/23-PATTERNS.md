# Phase 23: Restructure Skill + Safety Gates - Pattern Map

**Mapped:** 2026-05-29
**Files analyzed:** 8 (2 NEW dirs/files, 2 MODIFY) — 4 gate helpers grouped as one new class
**Analogs found:** 7 / 8 (4 net-new helpers share partial analogs; flagged below)

> Phase 23 is overwhelmingly *orchestration of shipped Phase 22 primitives*. The genuinely
> new code is small: a thin SKILL.md + 4 short `gates/*.sh` helpers + a one-line scaffold
> edit + a Wave-0 test block. The op-executor, manifest atomicity, path containment,
> snapshot/rollback, and TTY/non-TTY conventions are all shipped and tested — do not
> re-implement them. (RESEARCH "Don't Hand-Roll", lines 269-280.)

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `templates/skills/restructure/SKILL.md` (NEW) | skill (orchestration prose) | request-response (runbook) | `templates/skills/release/SKILL.md` + `_anatomy/SKILL.md` | role-match (none declares `allowed-tools`) |
| `templates/skills/restructure/gates/verify-invariants.sh` (NEW) | utility (deterministic gate) | transform / validation | `scripts/audit-setup.sh` (exit 0/1/2 + `note/err`) | partial (net-new matcher logic) |
| `templates/skills/restructure/gates/audit-staged.sh` (NEW) | utility (single-file audit shim) | transform / validation | `scripts/audit-setup.sh` (the audit it wraps) | partial (net-new temp-dir shim) |
| `templates/skills/restructure/gates/decision-scan.sh` (NEW) | utility (vocab scan) | transform / validation | `scripts/audit-setup.sh` conflict-marker grep (lines 139-152) | partial (net-new vocab scan) |
| `templates/skills/restructure/gates/extract-invariants.sh` (NEW) | utility (signal grep → state file) | file-I/O / transform | `scripts/resolve.sh` (tmpfile + `find` discovery) | partial (net-new extraction) |
| `templates/skills/restructure/gates/` approval driver (NEW, if separate) | utility (interactive prompt) | event-driven (TTY) | `scripts/resolve.sh:32-82` + `adopt.sh:367-380` | exact (mirror `/dev/tty` loop) |
| `scripts/init-project.sh` (MODIFY ~line 59) | config (scaffold loop) | batch (file copy) | `scripts/init-project.sh:59` itself (in-place list edit) | exact (one-token append) |
| `tests/run.sh` (MODIFY/APPEND) | test | batch (assertions) | `tests/run.sh:2371-2391` setup + `:2749-2883` block | exact (mirror Phase 22 block) |

**Per-class group-by source field:** `adopt-manifest.schema.json:125` —
`classification` enum = `["core","skill","agent","planning-doc","reference-doc","unknown"]`
(the 6 buckets for D-09 per-class grouped approval). Fixture proves the shape:
`tests/fixtures/_adopt-restructure-steps/adopt-manifest.json:18-37`.

---

## Pattern Assignments

### `templates/skills/restructure/SKILL.md` (skill, runbook)

**Analogs:** `templates/skills/release/SKILL.md` (62 lines), `templates/skills/_anatomy/SKILL.md`
(96 lines, the authoring reference). Both are well under the ≤200 cap — the thin-prose
target (Pitfall 4) is achievable.

**Frontmatter pattern** — `templates/skills/release/SKILL.md:1-4`:
```yaml
---
name: release
description: "Version bump, changelog generation, tag creation, release notes, rollback recipe. Invoke when user asks to cut a release, bump version, or prepare release notes."
---
```
**CRITICAL DIFFERENCE (D-16):** NO existing skill declares `allowed-tools`. This skill MUST
add it. `_anatomy/SKILL.md:8-17` documents the valid form (YAML-list accepted):
```yaml
---
name: restructure
description: "<action trigger phrase — e.g. 'Restructure an oversized CLAUDE.md + doc sprawl into a ≤100-line core + extracted skills/refs/archive. Invoke when user asks to restructure, condense, or adopt a brownfield harness.'>"
allowed-tools: [Read, Bash]      # D-16 — physically excludes Write/Edit on project files (RESTR-02)
# disallowed-tools: [Write, Edit]  # optional belt-and-suspenders (RESEARCH line 109, discretionary)
---
```
Audit enforces `name:` + `description:` only — `audit-setup.sh:61` (`grep '^name:'`) and
`:64` (`grep '^description:'`); a description under 30 chars warns (`:66`). `allowed-tools`
is NOT audited, so its correctness is verified by the Wave-0 scaffold test
(`grep allowed-tools.*Read.*Bash`).

**Body-format pattern** — `_anatomy/SKILL.md:36-72` (the project's own SKILL.md rulebook):
- **≤200 lines** (line 36), tables over prose for catalogs (line 38), cite `file:line` (line 39),
  include forbidden actions (line 40), code snippets only when non-obvious (line 42).
- Subfolders ARE endorsed: `_anatomy/SKILL.md:94-96` — *"Subfolders may hold attached
  resources (templates, scripts) that the skill references and Claude reads on demand."*
  This green-lights the `gates/` subdir (D-01).

**What the SKILL.md body MUST be (D-01, Pitfall 4 mitigation):** orchestration prose ONLY —
"run `gates/verify-invariants.sh <staging> <INVARIANTS.txt>`; if it exits non-zero, STOP and
show the user the missing list." NO bash loops/normalization in the body. Use tables (per
`_anatomy`) for the gate catalog and the `approve/skip/edit` verb semantics. The flow to
narrate is in RESEARCH lines 121-159 (the system diagram). Cross-references mirror
`release/SKILL.md:59-62`.

---

### `templates/skills/restructure/gates/verify-invariants.sh` (utility, validation — GATE A, D-05/07/08)

**Net-new logic** — the normalized-substring invariant matcher has NO direct analog. The
*shape* (exit 0/1/2, stderr messaging) mirrors `audit-setup.sh`. RESEARCH supplies the
bash-3.2-safe sketch (Pattern 2, lines 199-217). Key conventions to copy:

**Exit-code + error-message convention** — `audit-setup.sh:18-21, 296-298`:
```bash
note() { echo "  $1"; }
err()  { note "✗ $1"; FAIL=$((FAIL+1)); }
# ... tail of file:
[ "$FAIL" -gt 0 ] && exit 2     # ✗ → exit 2 (NEVER exit 1 — CLAUDE.md / VALIDATION convention gate)
[ "$WARN" -gt 0 ] && exit 1
exit 0
```
**Normalization (D-07, lowercase + ws-collapse + trim)** — RESEARCH Pattern 2 line 201:
```bash
normalize() { tr '[:upper:]' '[:lower:]' | tr -s '[:space:]' ' ' | sed 's/^ //; s/ $//'; }
HAYSTACK="$(normalize < "$STAGING_CLAUDE")"   # whole proposed file → one normalized line
```
**3.2-safe loop + BLOCK (no mapfile/assoc arrays — bash 3.2.57, CLAUDE.md)** — Pattern 2 lines 203-216:
```bash
missing=""
while IFS= read -r inv; do
  [ -n "$inv" ] || continue
  needle="$(printf '%s' "$inv" | normalize)"
  case "$HAYSTACK" in
    *"$needle"*) ;;                            # present
    *) missing="${missing}${inv}"$'\n' ;;      # newline-delimited (3.2-safe)
  esac
done < "$INVARIANTS_TXT"
if [ -n "$missing" ]; then
  echo "✗ restructure: proposed CLAUDE.md is missing required invariants:" >&2
  printf '  - %s\n' $missing >&2
  exit 2                                        # BLOCK (D-08), never exit 1
fi
```
**Granularity decision (VALIDATION O-2 → resolved):** extract invariants as short CANONICAL
TOKENS (`exit 2`, `@import`, `≤100`, command names) not full sentences — maximizes
substring robustness against LLM paraphrase (Pitfall 3, lines 310-314).

**Test contract (VALIDATION line 45-46):** present → rc 0; omitted → rc 2 + missing list on
stderr; reflowed/case-mangled-but-complete → rc 0.

---

### `templates/skills/restructure/gates/audit-staged.sh` (utility, validation — GATE B, D-13/RESTR-05)

**Net-new logic** — the single-file audit shim has no analog because `audit-setup.sh` is
DIRECTORY-scoped, not file-scoped (Pitfall 1, lines 298-302). It `cd`s into a target dir
(`audit-setup.sh:12-13`) and `exit 2`s if `.claude/` is absent (`audit-setup.sh:48`).

**The two named conditions live here** — `audit-setup.sh:27-39` (cap-breach + `@import`):
```bash
if [ -f CLAUDE.md ]; then
  LINES=$(wc -l < CLAUDE.md | tr -d ' ')
  if [ "$LINES" -le "${CLAUDE_MD_CAP}" ]; then ok "..."          # CLAUDE_MD_CAP=100 (lib/caps.sh:9)
  elif [ "$LINES" -le "${SKILL_MD_CAP}" ]; then warn "..."        # 101-200 = WARN (rc 1)
  else err "CLAUDE.md: $LINES lines (HARD CAP exceeded — trim)"   # >200 = FAIL (rc 2)
  fi
  if grep -q '^@' CLAUDE.md; then
    err "CLAUDE.md contains @imports — they load eagerly. Replace with prose links."  # → FAIL (rc 2)
  fi
fi
```
**Strictness decision (VALIDATION O-1 → resolved):** block on `@import` (always) + HARD cap
breach. Implement as the temp-dir shim that runs the REAL `conjure audit` (faithful to
RESTR-05 "run through conjure audit"), per RESEARCH Pattern 3, lines 223-233:
```bash
audit_staged() {
  local staged="$1" tmp rc
  tmp="$(mktemp -d)"
  cp "$staged" "$tmp/CLAUDE.md"
  mkdir -p "$tmp/.claude"                  # audit-setup.sh:48 exits 2 if .claude/ absent
  bash "$CONJURE_HOME/scripts/audit-setup.sh" "$tmp"; rc=$?
  rm -rf "$tmp"
  return "$rc"                             # 0=pass 1=warn 2=err — block on @import / hard-cap
}
```
**Source caps for direct-check fallback** — `lib/caps.sh:9-11`:
```bash
CLAUDE_MD_CAP="${CLAUDE_MD_CAP:-100}"
SKILL_MD_CAP="${SKILL_MD_CAP:-200}"
AGENT_MD_CAP="${AGENT_MD_CAP:-80}"
```
**`CONJURE_HOME` resolution** (helper must find `audit-setup.sh`) — mirror `resolve.sh:11`:
```bash
CONJURE_HOME="${CONJURE_HOME:-$(cd "$(dirname "$0")/.." && pwd)}"
```
(Note: from inside `.claude/skills/restructure/gates/` in a TARGET repo, the kit's
`audit-setup.sh` is NOT a relative `../..` away — `CONJURE_HOME` must point at the KIT, which
is intentionally NOT sandboxed: `sandbox.sh:32`. The skill exports `CONJURE_HOME` when it
invokes the helper. Flag this in planning.)

**Test contract (VALIDATION line 47-48):** `@import` file → rc 2 + audit output; clean ≤100 → rc 0;
oversized (>hard-cap) → rc ≥ 1.

---

### `templates/skills/restructure/gates/decision-scan.sh` (utility, validation — D-11/RESTR-06)

**Net-new logic** — the decision-vocabulary scan has no direct analog. Closest grep-and-flag
shape is `audit-setup.sh:139-152` (the conflict-marker `grep -rl` + per-file note loop):
```bash
CONFLICT_FILES="$(grep -rl '^<<<<<<<' .claude/ 2>/dev/null | grep -v '\.conjure-conflict-' || true)"
if [ -n "$CONFLICT_FILES" ]; then
  err "..."
  printf '%s\n' "$CONFLICT_FILES" | while IFS= read -r cf; do
    [ -z "$cf" ] && continue
    note "  conflict markers: $cf"
  done
fi
```
**The 5 D-11 terms (case-insensitive):** `decided` / `we chose` / `rationale` / `do not` /
`never`. RESEARCH seed grep (Code Examples, line 347) + over-match guard (Pitfall 5, lines
322-326): scope the scan to ARCHIVE CANDIDATES ONLY, consider `grep -iw` word-boundary to cut
noise on `never`/`do not`. Over-flagging is the SAFE direction (individual confirm never loses
a decision; bulk-archiving one would — CR-6 HIGH). Do NOT relax below the 5 terms.
```bash
grep -iE 'decided|we chose|rationale|do not|never' "$candidate"   # match → individual confirm
```
**Test contract (VALIDATION line 49):** file with `we decided`/`never` → signals "individual";
clean file → signals "bulk".

---

### `templates/skills/restructure/gates/extract-invariants.sh` (utility, file-I/O — D-03/05/06)

**Net-new logic** — writes the confirmed invariant list to
`.conjure-adopt-state/INVARIANTS.txt` (D-03, transient adopt-state — NOT a project file, so
the `[Read, Bash]` skill writes it via a Bash redirect, NOT the Write tool; RESEARCH Pattern 1
caveat, line 192). Closest structural analog is `resolve.sh:19-24` (tmpfile + `find`
discovery into a sorted file):
```bash
tmpfile="$(mktemp)"
trap 'rm -f "$tmpfile"' EXIT
find "$TARGET" -name '.conjure-conflict-*' -type f > "$tmpfile" 2>/dev/null || true
sort "$tmpfile" -o "$tmpfile"
```
**Signal-grep seed (D-06 scope)** — RESEARCH Code Examples lines 345-349:
```bash
grep -niE 'must|never|always|forbidden|required|do not|exit 2|@import|≤[0-9]+|[0-9]+ lines|`[^`]+`' "$SRC_CLAUDE" \
  > "$STATE_DIR/INVARIANTS.candidates"
# Scope to CLAUDE.md + root markdown only (full-tree grep is 30s+ on 2180 files — PITFALLS).
```
The LLM (Read) refines candidates into the final `INVARIANTS.txt`; this grep is the
deterministic checklist the LLM must cover (D-05). Helpers write ONLY under
`.conjure-adopt-state/` — never project files (RESEARCH Security V12, line 468).

---

### `scripts/init-project.sh` (config, MODIFY — D-16, criterion 1)

**Analog: the line itself.** ONE-TOKEN append to the tooling-skills loop —
`scripts/init-project.sh:59` (verified in source this session):
```bash
# BEFORE (init-project.sh:59):
for skill in code-graph docs-lookup web-research ast-search repo-pack sql-explorer _anatomy; do
# AFTER:
for skill in code-graph docs-lookup web-research ast-search repo-pack sql-explorer restructure _anatomy; do
  if [ ! -d ".claude/skills/$skill" ]; then
    mutate_cp "$KIT/templates/skills/$skill" ".claude/skills/$skill"     # init-project.sh:61
    echo "  ✓ created .claude/skills/$skill/"
  fi
done
```
**Assumption A1 RESOLVED (whole-dir copy ships `gates/*.sh`):** `mutate_cp` uses `cp -r` for
directories — `lib/mutate.sh:42-46`:
```bash
if [ -d "$1" ]; then
  cp -r "$1" "$2"          # directories copy recursively → gates/*.sh land in the target
else
  cp "$1" "$2"
fi
```
So scaffolding `restructure` copies the whole dir incl. `gates/`. No second copy step needed.
`adopt.sh:734` runs `init-project.sh existing "$TARGET"`, so the skill lands during
`conjure adopt` automatically (criterion 1).

---

### `tests/run.sh` (test, MODIFY/APPEND — Wave 0)

**Analog: the Phase 22 block** — setup at `tests/run.sh:2371-2391`, op-executor block at
`:2749-2883`. Mirror EXACTLY for the new `▸ Phase 23 — restructure gate helpers` section.

**Presence-guard + graceful-red idiom** — `tests/run.sh:2371-2374` (mirror `P22_ADOPT_OK`):
```bash
P23_RESTR_DIR="$CONJURE_HOME/templates/skills/restructure"
P23_RESTR_OK=0
[ -f "$P23_RESTR_DIR/SKILL.md" ] && P23_RESTR_OK=1
# In each section: if [ "$P23_RESTR_OK" -ne 1 ]; then fail "... Wave 1 must create ..."; else ...; fi
```
**Sandboxed scaffold drive (criterion 1)** — copy fixture + run `init-project.sh existing`,
then assert (mirror `tests/run.sh:2755-2763` setup + `sandbox.sh:46-50`):
```bash
P23_TGT="$(mktemp -d)"; trap 'rm -rf "$P23_TGT"' EXIT
cp -r "$P22_FIXTURE/." "$P23_TGT/"          # reuse brownfield-simple fixture (run.sh:2377)
CONJURE_HOME="$CONJURE_HOME" bash "$CONJURE_HOME/scripts/init-project.sh" existing "$P23_TGT" >/dev/null 2>&1 || true
# assert: SKILL.md present, allowed-tools, ≤200 lines, gates/verify-invariants.sh present
[ -f "$P23_TGT/.claude/skills/restructure/gates/verify-invariants.sh" ] && pass "..." || fail "..."
[ "$(wc -l < "$P23_TGT/.claude/skills/restructure/SKILL.md")" -le 200 ] && pass "..." || fail "..."
```
**Synthetic fixtures via inline `printf`** — mirror `tests/run.sh:2762-2766` heredoc idiom:
```bash
printf '# CLAUDE\n\nhooks must exit 2, never exit 1. CLAUDE.md ≤100 lines. No @import.\n' > "$STAGE/with-invariant.md"
printf '# CLAUDE\n\nNo constraints here.\n' > "$STAGE/missing-invariant.md"
printf '@import ./extra.md\n# CLAUDE\n' > "$STAGE/with-import.md"
printf 'we decided to keep X; never delete Y.\n' > "$STAGE/decision-doc.md"
```
**Reuse the existing manifest fixture for group-by + apply-step** —
`tests/fixtures/_adopt-restructure-steps/adopt-manifest.json` (exists; classification +
restructure_steps[] shape proven). Mirror `tests/run.sh:2759-2760`.
**Non-TTY exit-2 assert** — capture rc from a piped/`</dev/null` drive, expect 2 (mirror the
SIGKILL non-TTY assert `tests/run.sh:2720-2729`).

---

## Shared Patterns

### Interactive approval over `/dev/tty` (non-TTY → exit 2) — D-10/D-12/RESTR-03
**Source:** `scripts/resolve.sh:32-82` + `scripts/adopt.sh:367-380`
**Apply to:** the approval driver in the skill (per-class `approve/skip/edit` loop).

Non-TTY guard (resolve.sh:32-37) — the exact gate to copy:
```bash
if ! { [ -t 0 ] || [ "${CONJURE_FORCE_INTERACTIVE:-0}" = "1" ]; }; then
  echo "conjure resolve: stdin is not a TTY — interactive mode required" >&2
  exit 2                                # D-12: never auto-approve
fi
```
fd-3 walk so inner `read` keeps reading stdin (resolve.sh:41-42, 82) + verb loop with
re-prompt-on-unknown and re-prompt-on-edit (resolve.sh:52-80):
```bash
exec 3< "$tmpfile"
while IFS= read -r item <&3; do
  while true; do
    read -r -p "  [a]pprove / [s]kip / [e]dit: " choice < /dev/tty   # adopt.sh:372 uses </dev/tty
    case "$choice" in
      a|approve) ...; break ;;
      s|skip)    ...; break ;;
      e|edit)    ... ;;                # NO break — re-prompt after edit (resolve.sh:67-69, D-10)
      *)         echo "  enter a, s, or e" ;;   # NO break — no default (adopt.sh:377, D-14)
    esac
  done
done
exec 3<&-
```
**`edit` mechanics (VALIDATION O-3 → resolved):** `edit` = skill (LLM) prompts via `/dev/tty`,
re-drafts staged content, re-writes via `conjure adopt --update-manifest`, then RE-RUNS gates A+B
before re-prompting. NO `$EDITOR` launch (keeps the Read+Bash proposer model). This DIFFERS
from `resolve.sh:68` which does `"${EDITOR:-vi}"` — do NOT copy that line.

### Drive every mutation through the Phase 22 adopt seam — D-04/RESTR-02 (chokepoint)
**Source:** `scripts/adopt.sh:417-443` (update_manifest, inbound) + `:469-607` (apply_step, outbound)
**Apply to:** every project-file mutation the skill performs.

INBOUND — stdin ONLY through the public CLI (Pitfall 2: `cmd_adopt` does NOT forward
`CONJURE_ADOPT_STEP_JSON`, cli/conjure:215-220):
```bash
printf '%s' "$op_json" | conjure adopt --update-manifest
```
`update_manifest` validates `{id, op∈{write,archive,extract}, status}` and appends via
injection-safe `--argjson` (adopt.sh:435-441):
```bash
if ! printf '%s' "$step_json" | jq -e '
    type=="object" and has("id") and has("op") and has("status")
    and (.op=="write" or .op=="archive" or .op=="extract")' >/dev/null 2>&1; then
  echo "✗ ... malformed step ..." >&2; exit 2          # rejected, NEVER executed
fi
manifest_write_atomic '.restructure_steps += [$step]' --argjson step "$step_json"
```
**Build op JSON injection-safe** (mirror the `--arg/--argjson` discipline; never string-interpolate
into JSON): `jq -n --arg id "$id" --arg dest "$dest" --arg src "$src" '{id:$id,op:"write",dest:$dest,src:$src,status:"proposed"}'`.

OUTBOUND — apply after approval (adopt.sh:469-607); routes through `lib/mutate.sh` +
`resolve_under` path containment + protected-dir denylist (adopt.sh:532-537) +
`log_step RESTRUCTURE` (adopt.sh:603):
```bash
conjure adopt --apply-step "$id"          # marks status: applied (adopt.sh:605)
```
The op JSON shape to emit (from the shipped fixture, `_adopt-restructure-steps/adopt-manifest.json:48-60`):
```json
{ "id": "step-claude", "op": "write", "dest": "CLAUDE.md", "src": ".conjure-adopt-state/staging/CLAUDE.md", "status": "proposed" }
{ "id": "step-arch-1", "op": "archive", "src": "docs/OLD.md", "status": "proposed" }
```
Staging content (`src`) is written by the skill into `.conjure-adopt-state/staging/<file>` via a
Bash redirect (transient adopt-state, not a project file — D-04, Pattern 1 caveat).

### Summary-line logging for bulk ops — D-09/SAFE-07
**Source:** `lib/log.sh:29-42` (`log_step <phase> <message>`)
**Apply to:** every applied step / bulk-bucket summary line in RESTRUCTURE-LOG.md.
```bash
log_step RESTRUCTURE "approved core bucket — applied 1 condensed CLAUDE.md"
log_step RESTRUCTURE "archived reference-doc bucket (12 files, summary)"   # ONE line for bulk (D-09)
```
`log_step` is DRY_RUN-safe via `mutate_write --append` (log.sh:41) — never `echo >> file`.
`apply_step` already logs on apply (adopt.sh:603); the skill adds bucket-summary lines for
skip/bulk. Set `RESTRUCTURE_LOG_PATH` first (adopt.sh:498-502 precedent), or `apply-step`
inits the log header itself.

### Exit-code + cap constants — CLAUDE.md / lib/caps.sh
**Source:** `lib/caps.sh:9-11`; convention from `audit-setup.sh:296-298`, `log.sh:47-51`.
**Apply to:** all four gate helpers.
- ✗ / hard-fail → **`exit 2`** (NEVER `exit 1` — VALIDATION convention gate `grep -c 'exit 1'` = 0).
- Source caps: `source "$CONJURE_HOME/lib/caps.sh"` for `CLAUDE_MD_CAP=100`, `SKILL_MD_CAP=200`.
- shellcheck gate: `shellcheck -S error -e SC2164,SC2044,SC2034,SC2155` (VALIDATION line 23) —
  use inline directives like `resolve.sh:16` (`# shellcheck source=/dev/null`) for dynamic sources.

---

## No Analog Found (net-new logic — planner: use RESEARCH patterns, not a codebase copy)

| Logic | Lives In | Reason | RESEARCH Ref |
|-------|----------|--------|--------------|
| Normalized-substring invariant matcher | `gates/verify-invariants.sh` | No normalize-and-substring-match gate exists in the codebase | Pattern 2, lines 194-218 |
| Single-file audit shim (temp-dir → `conjure audit`) | `gates/audit-staged.sh` | `audit-setup.sh` is directory-scoped only; no single-file mode | Pitfall 1 + Pattern 3, lines 220-235, 298-302 |
| Decision-vocabulary scan (5-term grep + escalate) | `gates/decision-scan.sh` | No decision-keyword scan exists (closest is conflict-marker grep) | D-11, Pitfall 5, lines 322-326 |
| Invariant signal-extraction → INVARIANTS.txt | `gates/extract-invariants.sh` | No constraint-extraction pre-pass exists | D-06, Code Examples lines 343-350 |
| Per-class group-by over manifest `classification` | approval driver | New aggregation over the 6-bucket field for grouped approval | D-09, Code Examples lines 330-341 |

All five reuse SHIPPED conventions (exit 2, `/dev/tty`, `jq`, `log_step`, the adopt seam) for
their *scaffolding* — only the core algorithm is new. None requires a new dependency
(RESEARCH "Package Legitimacy Audit", line 113-115).

---

## Metadata

**Analog search scope:** `templates/skills/` (all 19 skill templates), `scripts/`
(adopt.sh, audit-setup.sh, init-project.sh, resolve.sh), `lib/` (caps.sh, log.sh, mutate.sh),
`cli/conjure` (cmd_adopt), `tests/run.sh` (Phase 22 block + setup), `tests/lib/sandbox.sh`,
`tests/fixtures/_adopt-restructure-steps/`, `adopt-manifest.schema.json`.
**Files scanned:** 13 source files read this session (all verified against actual source).
**Pattern extraction date:** 2026-05-29
**Verified assumptions:** A1 RESOLVED (mutate_cp `cp -r` ships `gates/`, lib/mutate.sh:42-46);
Pitfall 1 confirmed (audit dir-scoped, audit-setup.sh:12-13,48); Pitfall 2 confirmed
(cmd_adopt does not forward `CONJURE_ADOPT_STEP_JSON`, cli/conjure:215-220); no SKILL.md
template declares `allowed-tools` (this skill is the first).
