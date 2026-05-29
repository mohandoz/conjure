# Phase 23: Restructure Skill + Safety Gates - Research

**Researched:** 2026-05-29
**Domain:** Human-gated LLM restructure skill (`[Read, Bash]`) + deterministic pre-write bash safety gates riding the Phase 22 `conjure adopt` seam
**Confidence:** HIGH

## Summary

Phase 23 ships the *proposer* half of the v0.6.0 split-responsibility model: a `restructure` SKILL.md (installed into target repos by `conjure adopt`) plus a set of deterministic bash gate helpers shipped alongside it. The CLI half — `conjure adopt --update-manifest` (inbound: skill writes proposed ops) and `--apply-step <id>` (outbound: CLI applies them through `lib/mutate.sh`) — is **already shipped and tested** in Phase 22 (`scripts/adopt.sh` lines 397–607, 394 tests passing). Phase 23 builds *only* the skill body, the gate helpers it invokes via Bash, and the one-line scaffold-list edit that makes the skill land in targets. It does NOT touch the adopt pipeline.

The architecture is fully constrained by 16 locked decisions (D-01..D-16) and 6 success criteria. The skill is `[Read, Bash]`-restricted: it reads `adopt-manifest.json` + source files via Read, proposes ops, and routes *every* mutation through `conjure adopt` via Bash — it physically cannot call Write/Edit on project files (RESTR-02 chokepoint). Before the user ever sees an approval prompt, two deterministic gates run on the *proposed staging content*: (1) the invariant gate (the skill extracts invariants from the old CLAUDE.md into `.conjure-adopt-state/INVARIANTS.txt`, then a bash helper verifies each appears in the proposed condensed CLAUDE.md via normalized case-insensitive whitespace-collapsed substring match) and (2) the `conjure audit` `@import`/cap-breach gate. Failures BLOCK with the list of missing invariants / audit findings — no approval prompt for invalid content.

**Primary recommendation:** Build a thin `templates/skills/restructure/SKILL.md` (≤200 lines, orchestration prose) plus `templates/skills/restructure/gates/*.sh` helpers (extract-invariants, verify-invariants, decision-scan, audit-staged-file). The skill drives the existing Phase 22 seam: `Read` manifest → write staged content to `.conjure-adopt-state/staging/<file>` via `conjure adopt --update-manifest` (op references the staging path) → run gate helpers + `conjure audit` on the staged file → present `/dev/tty` per-class `approve/skip/edit` (mirror `recovery_prompt` in adopt.sh:367 and `resolve.sh:52`) → `conjure adopt --apply-step <id>` on approve. Add `restructure` to the `init-project.sh:59` tooling-skills loop so it scaffolds during `conjure adopt`. Test the gate helpers + a synthetic-manifest integration drive directly in `tests/run.sh` (mirror the Phase 22 op-executor block, lines 2750–2883); the interactive `/dev/tty` loop is verified by the non-TTY exit-2 path automatically + manual UAT (Phase 22 precedent).

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| RESTR-01 | `restructure` skill reads manifest + oversized CLAUDE.md + doc sprawl; proposes plan (≤100-line core, what extracts to skills/subagents, what stays linked-ref, what archives) | Skill body reads `adopt-manifest.json` (schema §below) via Read; manifest already records 6-bucket `classification` + `size_cap_exceeded`/`size_cap_violations[]` per file. Skill emits proposed ops to `restructure_steps[]` via `--update-manifest`. Source files: `adopt-manifest.schema.json`, fixture `tests/fixtures/_adopt-restructure-steps/adopt-manifest.json`. |
| RESTR-02 | Skill applies changes ONLY through `conjure adopt` primitives; skill restricted to `[Read, Bash]` | Frontmatter `allowed-tools: [Read, Bash]` (VERIFIED valid YAML-list syntax — Claude Code docs). Skill shells out to `conjure adopt --update-manifest`/`--apply-step` via Bash; every mutation routes through `lib/mutate.sh` (adopt.sh apply_step at line 469). Optional hardening: `disallowed-tools: [Write, Edit]`. |
| RESTR-03 | User approves each step; large corpora use per-class grouped approvals, never one-per-file | Group `files[]` by `classification` (6 buckets); one `/dev/tty` prompt per bucket. `RESTRUCTURE-LOG.md` summary-line via `log_step` (lib/log.sh:34). Mirror `recovery_prompt` (adopt.sh:367) + `resolve.sh:52` walk loop. |
| RESTR-04 | Constraint-extraction pre-pass captures invariants; proposed output verified to contain every invariant; approval blocked if any missing | Skill (LLM via Read) proposes invariants → `.conjure-adopt-state/INVARIANTS.txt` (D-03). Deterministic bash `verify-invariants` gate: normalize both INVARIANTS lines and proposed staging CLAUDE.md (lowercase, whitespace-collapse), substring-match each; missing → print list + BLOCK (D-05/07/08). |
| RESTR-05 | Proposed content run through `conjure audit` before approval; `@imports`/cap breaches blocked pre-write | `audit-setup.sh` is directory-scoped on `$TARGET/CLAUDE.md` (no single-file mode). Run it on the staging file via a temp-dir shim (copy staging file in as CLAUDE.md → `audit-setup.sh <tmpdir>` → inspect rc/output). See Pitfall 1 for the exact mechanism. |
| RESTR-06 | Archive steps sequenced last, individually confirmed, gated by decision-vocabulary scan | `decision-scan` helper greps each archive candidate for `decided`/`we chose`/`rationale`/`do not`/`never` (case-insensitive); matches pulled OUT of bulk archive into individual `/dev/tty` confirmation. Archive ops emitted/applied LAST (D-15). |
</phase_requirements>

<user_constraints>
## User Constraints (from 23-CONTEXT.md)

### Locked Decisions (D-01..D-16 — do NOT relitigate; research is HOW to implement)
- **D-01:** Thin `SKILL.md` = orchestration prose ONLY; heavy logic in bash helper scripts in the skill dir (`gates/*.sh`), invoked via Bash. Resolves the ≤200-line open question without a spike. Cramming logic into SKILL.md is REJECTED.
- **D-02:** Safety-gate validators are bash helpers the skill invokes (constraint-extract, invariant-verify, decision-vocabulary scan); RESTR-05 pre-write audit reuses existing `conjure audit`. New `adopt.sh` subcommands REJECTED — gates live in the skill's dir, not CLI core.
- **D-03:** `INVARIANTS.txt` written to `.conjure-adopt-state/INVARIANTS.txt` (transient, beside `staging/`), NOT target root.
- **D-04:** Skill mutates files ONLY via `conjure adopt --update-manifest` (write proposed ops + staged content) then `--apply-step <id>` (apply) — the Phase 22 seam. Skill stays `[Read, Bash]` (RESTR-02). Direct staging writes REJECTED.
- **D-05:** Skill (LLM, reading via Read) proposes invariant list → `INVARIANTS.txt`; deterministic bash gate verifies the PROPOSED condensed CLAUDE.md contains every invariant. Pure keyword heuristic REJECTED; verification is deterministic + reproducible.
- **D-06:** Invariant scope = imperative/prohibition lines (`must`/`never`/`always`/`do not`), exit-code rules (`exit 2`), size caps, named commands / backtick'd tokens. Only-explicit-"MUST" REJECTED (too narrow).
- **D-07:** Gate match strictness = normalized substring (case-insensitive, whitespace-collapsed) so legitimate reflow/condensing doesn't false-block. Exact byte match REJECTED.
- **D-08:** Gate failure = BLOCK before approval; print missing invariants; user never sees the proposal until it passes (criterion 4). Warn-but-allow REJECTED.
- **D-09:** 50+ file corpora use per-class grouped approval — ONE prompt per classification bucket (Phase 21 6-bucket taxonomy), never one-per-file; `RESTRUCTURE-LOG.md` records only a summary line for bulk ops (criterion 3, RESTR-03).
- **D-10:** Per-step verbs = `approve / skip / edit`. `approve` applies; `skip` leaves file as-is; `edit` re-opens staged file for adjustment, then RE-RUNS the gates before re-prompting (criterion 2). Never proceeds without explicit response.
- **D-11:** Decision-vocabulary scan: files matching `decided`/`we chose`/`rationale`/`do not`/`never` pulled OUT of bulk archive into INDIVIDUAL confirmation (RESTR-06). Flag-but-keep-in-bulk REJECTED.
- **D-12:** No-TTY behavior = `exit 2`, never auto-approve (mirror adopt D-13 / `resolve.sh` `/dev/tty`). Read approval from `/dev/tty`.
- **D-13:** Pre-write audit (RESTR-05): run `conjure audit` on the PROPOSED staging file BEFORE the approval prompt; block on `@import` / cap breaches, show audit output; no approval prompt for invalid content (criterion 5).
- **D-14:** Gate order = invariant-check (D-05/D-08) + audit-gate (D-13) BOTH run before approval (criteria 4 & 5).
- **D-15:** Archive steps sequenced LAST in the proposed plan (criterion 6); combined with D-11's individual confirmation.
- **D-16:** Install path: adopt scaffolds `templates/skills/restructure/` into target's `.claude/skills/restructure/` (criterion 1). Frontmatter `allowed-tools: [Read, Bash]`; SKILL.md ≤200 lines. Separate `conjure restructure` CLI command REJECTED — it's a skill (RESTR-01).

### Claude's Discretion
- Exact helper-script names/layout under the skill dir; the precise `INVARIANTS.txt` line format; the normalized-substring matcher implementation; the per-bucket approval prompt wording; how `edit` surfaces the staged file (e.g. print path + re-read). All at Claude's discretion during planning, consistent with adopt's existing `/dev/tty` + summary-log conventions.

### Deferred Ideas (OUT OF SCOPE)
- Integration tests + Argus brownfield fixture exercising the full adopt+restructure pipeline — **Phase 24**.
- Any TUI/rich-rendering of the approval plan — out of scope; plain-text + `/dev/tty` mirrors `resolve.sh`.
</user_constraints>

## Project Constraints (from CLAUDE.md)

| Directive | Source | Impact on Phase 23 |
|-----------|--------|--------------------|
| POSIX bash 3.2+: no associative arrays, no `mapfile`, no `local -n` | CLAUDE.md Constraints | Gate helpers + skill scripts must be 3.2-compatible. **VERIFIED machine runs bash 3.2.57** — newline-delimited internal state only. |
| Node stdlib `.mjs` only; no heavy runtime deps; `dependencies: {}` empty | CLAUDE.md / STACK.md | Gates are pure bash + `jq`/`grep`/`sed`/`tr`/`awk` (all VERIFIED present). No new deps. |
| Hooks/CLI `exit 2`, never `exit 1` | CLAUDE.md Constraints | Every gate helper hard-fails with `exit 2`. CI gate `grep -c 'exit 1'` must be 0. |
| Size caps: CLAUDE.md ≤100, **SKILL.md ≤200**, agent ≤80 — enforced by audit/CI | CLAUDE.md / lib/caps.sh | The restructure SKILL.md itself must be ≤200 lines (criterion 1, D-01). `audit-setup.sh:58` warns >200; thin-prose design (D-01) is the mitigation. |
| `@imports` forbidden in CLAUDE.md | CLAUDE.md | The skill must propose `](path)` prose links, never `@import`; the audit gate (RESTR-05) enforces this on proposed content. |
| Every PR passes shellcheck, JSON Schema, frontmatter, size-cap, coverage | CLAUDE.md Quality gate | Gate helpers must be shellcheck-clean at error severity (`-S error -e SC2164,SC2044,SC2034,SC2155`, the adopt.sh precedent). SKILL.md frontmatter must have `name:` + `description:` (audit-setup.sh:61/64). |
| All filesystem mutations route through `lib/mutate.sh` | CLAUDE.md Architecture / locked v0.3.0 | Skill never writes project files — only `conjure adopt --apply-step` (which routes through `mutate.sh`). Gate helpers may write ONLY transient files under `.conjure-adopt-state/` (INVARIANTS.txt) — never project files. |

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Read manifest + source files; judge what to extract/condense/archive | Skill (LLM, in-session) | — | LLM judgment (D-02: candidate/stale is skill-owned). Read tool only. |
| Propose invariant list from old CLAUDE.md | Skill (LLM) | — | D-05: nuance requires LLM; the *verification* is deterministic. |
| Verify proposed CLAUDE.md contains each invariant | Gate helper (bash, deterministic) | — | D-05/07: reproducible normalized-substring match. No LLM in the verify loop. |
| `@import` + cap-breach check on proposed content | `conjure audit` (existing CLI) | Gate helper shim | D-13: reuse `audit-setup.sh`; shim adapts directory-scope to single-file. |
| Decision-vocabulary scan on archive candidates | Gate helper (bash, grep) | — | D-11: deterministic keyword scan; matches escalate to individual confirm. |
| Stage proposed content + register ops | Skill via Bash → `conjure adopt --update-manifest` | CLI op-executor | D-04: skill proposes; CLI persists to `restructure_steps[]`. |
| Apply an approved op (write/archive/extract) | CLI `conjure adopt --apply-step` → `lib/mutate.sh` | — | RESTR-02 chokepoint; already shipped + tested (Phase 22). |
| Per-step approval prompt (`approve/skip/edit`) | Skill via Bash, `/dev/tty` read | — | D-10/12: mirror `recovery_prompt` (adopt.sh:367). Non-TTY → exit 2. |
| Append per-step / summary log line | `log_step` (lib/log.sh) via apply-step + skill | — | D-09/SAFE-07: bulk ops = one summary line. |

## Standard Stack

### Core
| Library / Tool | Version | Purpose | Why Standard |
|----------------|---------|---------|--------------|
| POSIX bash | 3.2+ (VERIFIED 3.2.57 on dev machine) | Gate helpers + skill-invoked scripts | Project envelope; cross-platform incl. Git Bash. `[CITED: CLAUDE.md]` |
| `jq` | (VERIFIED present) | Read `adopt-manifest.json` `files[]`/`restructure_steps[]`, build proposed-op JSON for `--update-manifest`, group-by classification | Already the manifest contract tool (adopt.sh, inventory.sh). `--argjson` injection-safe. `[VERIFIED: codebase]` |
| `grep` / `sed` / `tr` / `awk` | (VERIFIED present) | Invariant extraction signal-grep, normalize (lowercase/whitespace-collapse), decision-vocabulary scan | Already used across scripts/. No new deps. `[VERIFIED: codebase]` |
| `conjure adopt` seam | shipped Phase 22 | `--update-manifest` (inbound), `--apply-step <id>` (outbound) | The ONLY mutation path for the skill (D-04, RESTR-02). `[VERIFIED: scripts/adopt.sh 397–607]` |
| `audit-setup.sh` (`conjure audit`) | shipped | RESTR-05 `@import` + cap-breach gate | Exit 0/1/2 contract; sources `lib/caps.sh`. `[VERIFIED: scripts/audit-setup.sh]` |
| `lib/log.sh` `log_step` | shipped | `RESTRUCTURE-LOG.md` summary-line logging (D-09, SAFE-07) | `log_step <phase> <message>` appends via `mutate_write --append`. `[VERIFIED: lib/log.sh:34]` |

### Supporting (existing patterns to mirror — not new code)
| Asset | Path:line | Mirror For |
|-------|-----------|-----------|
| `recovery_prompt` `/dev/tty` loop | scripts/adopt.sh:367–380 | The `approve/skip/edit` prompt; `read -r -p "..." choice < /dev/tty`; no default; unknown re-prompts (D-10/12/14). |
| `resolve.sh` non-TTY guard + walk | scripts/resolve.sh:32–82 | Non-TTY `exit 2` (`[ -t 0 ] || CONJURE_FORCE_INTERACTIVE`); fd-3 walk over a list; `edit` verb re-prompt pattern (resolve.sh:67). |
| init scaffold skills loop | scripts/init-project.sh:59 | Add `restructure` to the tooling-skills list (D-16, criterion 1). |
| `_anatomy` SKILL.md | templates/skills/_anatomy/SKILL.md | Frontmatter format, ≤200-line rule, "subfolders may hold attached scripts the skill references". |
| Phase 22 op-executor test block | tests/run.sh:2750–2883 | Wave 0 test idiom: synthetic manifest + staging dir + invoke via env + jq-assert status + non-TTY exit-2. |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `audit-setup.sh` temp-dir shim for single-file audit | New `--file` flag on audit-setup.sh | D-02 rejects new CLI subcommands; shim keeps gate logic in the skill dir. Shim is ~5 lines (Pitfall 1). |
| Skill pipes op-JSON via stdin to `--update-manifest` | `CONJURE_ADOPT_STEP_JSON` env var | **`cmd_adopt` does NOT plumb `CONJURE_ADOPT_STEP_JSON` through** (cli/conjure:215–220) — only `update_manifest=1`. Through the CLI, stdin is the ONLY supported path. The env var works only on direct `bash adopt.sh`. Skill MUST use stdin: `printf '%s' "$op" \| conjure adopt --update-manifest`. (See Pitfall 2.) |
| `disallowed-tools: [Write, Edit]` hardening | rely on `allowed-tools` whitelist alone | `allowed-tools: [Read, Bash]` already excludes Write/Edit; `disallowed-tools` is belt-and-suspenders. Optional, at discretion. |

**Installation:** No new packages. All tools verified present (jq, grep, sed, awk, tr, fold, cmp). The phase ships bash + a SKILL.md template only.

## Package Legitimacy Audit

This phase installs **zero external packages**. It ships bash scripts and a markdown SKILL.md template using only the existing runtime envelope (bash 3.2+, jq, coreutils). No npm/PyPI/crates dependency is added. `dependencies: {}` remains empty per CLAUDE.md. The Package Legitimacy Gate is N/A — no slopcheck run required.

## Architecture Patterns

### System Architecture Diagram

```
                       ┌─────────────────────────────────────────────┐
  conjure adopt run    │  (Phase 22, already shipped)                 │
  scaffolds skill ───► │  init-project.sh:59 copies                   │
  into target          │  templates/skills/restructure/ → target      │
                       │  .claude/skills/restructure/                 │
                       └─────────────────────────────────────────────┘
                                          │
            user opens Claude Code in target, invokes restructure skill
                                          ▼
   ┌──────────────────────────── restructure SKILL.md ([Read, Bash]) ───────────────────────────┐
   │                                                                                              │
   │  (1) Read adopt-manifest.json ──► summary + files[] (classification, size_cap_exceeded)      │
   │  (2) Read oversized CLAUDE.md + flagged docs (Read tool)                                     │
   │  (3) LLM proposes invariants ──Bash──► gates/extract-invariants writes                       │
   │                                         .conjure-adopt-state/INVARIANTS.txt  (D-03/05)        │
   │  (4) LLM drafts condensed CLAUDE.md / extracted skills / archive list                        │
   │      └─Bash──► conjure adopt --update-manifest  (stdin op JSON)                              │
   │                  ├─ writes staged content to .conjure-adopt-state/staging/<file>             │
   │                  └─ appends {id,op,dest,src,status:proposed} to restructure_steps[]          │
   │                                                                                              │
   │  ┌─── PRE-APPROVAL GATES (D-14: BOTH run before the user sees the proposal) ──────────────┐  │
   │  │  GATE A (D-05/07/08): gates/verify-invariants <staging/CLAUDE.md> <INVARIANTS.txt>      │  │
   │  │     normalize(lowercase+ws-collapse) both; substring-match each invariant               │  │
   │  │     any missing ──► print list, BLOCK, exit 2  (criterion 4)                            │  │
   │  │  GATE B (D-13): gates/audit-staged <staging file>  (temp-dir shim → conjure audit)      │  │
   │  │     @import (^@) or cap breach ──► print audit output, BLOCK, exit 2  (criterion 5)     │  │
   │  └────────────────────────────────────────────────────────────────────────────────────────┘ │
   │                                          │ both pass                                         │
   │                                          ▼                                                   │
   │  (5) PER-CLASS approval (D-09): group files[] by classification; ONE /dev/tty prompt/bucket  │
   │       read -r -p "...[a]pprove/[s]kip/[e]dit" choice < /dev/tty   (non-TTY → exit 2, D-12)   │
   │       edit ──► re-open staged file, RE-RUN gates A+B, re-prompt (D-10)                       │
   │       approve ──Bash──► conjure adopt --apply-step <id>  ──► lib/mutate.sh (RESTR-02)        │
   │                          └─ log_step RESTRUCTURE (summary line for bulk, D-09/SAFE-07)       │
   │  (6) ARCHIVE steps LAST (D-15): gates/decision-scan each candidate                           │
   │       match decided/we chose/rationale/do not/never ──► individual /dev/tty confirm (D-11)  │
   │       else bulk per-class archive prompt                                                     │
   └──────────────────────────────────────────────────────────────────────────────────────────────┘
```

### Recommended Project Structure
```
templates/skills/restructure/
├── SKILL.md          # orchestration prose, ≤200 lines, allowed-tools: [Read, Bash] (D-01/16)
└── gates/            # bash helpers invoked via Bash (D-01/02); subfolder allowed per _anatomy
    ├── extract-invariants.sh   # (writes INVARIANTS.txt from a confirmed invariant list)  [discretionary name]
    ├── verify-invariants.sh    # deterministic normalized-substring gate (D-05/07/08) → exit 2 on miss
    ├── audit-staged.sh         # temp-dir shim → conjure audit on one staged file (D-13/RESTR-05)
    └── decision-scan.sh        # decision-vocabulary scan on archive candidates (D-11/RESTR-06)
scripts/init-project.sh         # ONE-LINE edit: add "restructure" to the line-59 tooling-skills loop (D-16)
tests/run.sh                    # NEW Phase 23 block: gate-helper unit tests + synthetic-manifest drive
```
*Note: helper names/layout are discretionary (CONTEXT.md Claude's Discretion). The `gates/` subfolder is endorsed by `_anatomy` ("subfolders may hold attached resources the skill references and Claude reads on demand").*

### Pattern 1: Read+Bash skill drives a CLI (RESTR-02 chokepoint)
**What:** The skill never writes project files. It reads context (Read), runs gate helpers + `conjure adopt` (Bash). All mutation is `conjure adopt --apply-step`, which routes through `lib/mutate.sh`.
**When to use:** Every project-file mutation in the skill.
**Example:**
```bash
# Source: scripts/adopt.sh:417-443 (update_manifest, shipped) — inbound half via stdin.
# The skill stages content and registers a proposed op. NOTE: stdin, not env var
# (cmd_adopt does not plumb CONJURE_ADOPT_STEP_JSON — see Pitfall 2).
printf '%s' '{"id":"step-claude","op":"write","dest":"CLAUDE.md","src":".conjure-adopt-state/staging/CLAUDE.md","status":"proposed"}' \
  | conjure adopt --update-manifest
# (staging file itself is written by the skill into .conjure-adopt-state/staging/CLAUDE.md;
#  this is a transient adopt-state path, not a project file — does not violate Read+Bash)

# Source: scripts/adopt.sh:469-607 (apply_step, shipped) — outbound half, after approval.
conjure adopt --apply-step step-claude
```
**Caveat — staging writes:** the skill writes the *staged content* to `.conjure-adopt-state/staging/<file>` itself (the op only references it via `src`, per D-07 / Phase 22 22-03-SUMMARY). With `[Read, Bash]` the skill writes that file via a Bash redirect/heredoc, NOT the Write tool. This is a transient adopt-state file, not a project file — consistent with D-04 ("write proposed ops + staged content" via the seam). Confirm in planning that the staging-file write is expressed as a Bash command, not a Write-tool call.

### Pattern 2: Deterministic normalized-substring invariant gate (D-05/07)
**What:** Given the LLM-proposed `INVARIANTS.txt` (one invariant per line) and the proposed condensed CLAUDE.md, verify every invariant is present after normalization.
**When to use:** GATE A, before approval (D-14).
**Normalization (D-07):** lowercase + collapse all runs of whitespace to a single space + trim. This survives reflow/condensing without false-blocking.
**Example (bash 3.2-safe sketch):**
```bash
# Source: derived from D-07 spec + project bash 3.2 constraints (no mapfile/assoc arrays)
normalize() { tr '[:upper:]' '[:lower:]' | tr -s '[:space:]' ' ' | sed 's/^ //; s/ $//'; }
HAYSTACK="$(normalize < "$STAGING_CLAUDE")"      # whole proposed file, one normalized line
missing=""
while IFS= read -r inv; do
  [ -n "$inv" ] || continue
  needle="$(printf '%s' "$inv" | normalize)"
  case "$HAYSTACK" in
    *"$needle"*) ;;                               # present
    *) missing="${missing}${inv}"$'\n' ;;         # newline-delimited (3.2-safe)
  esac
done < "$INVARIANTS_TXT"
if [ -n "$missing" ]; then
  echo "✗ restructure: proposed CLAUDE.md is missing required invariants:" >&2
  printf '  - %s\n' $missing >&2
  exit 2                                          # BLOCK (D-08) — never exit 1
fi
```
**Edge cases (Open Question O-1):** multi-line invariants (an invariant spanning lines in the source) — extract should emit each as a single logical line; backtick'd commands (`` `exit 2` ``) normalize fine since backticks survive `tr`; reflowed prose where the LLM splits one sentence across two lines is handled because the *haystack* is normalized to a single line (whitespace-collapsed across newlines). The genuine risk is the LLM *rephrasing* an imperative (e.g. "must exit 2" → "exits with code 2") — substring match would miss it. D-05 mitigates by having the LLM confirm each invariant verbatim/by-reference at draft time, and the gate is the deterministic backstop; planning should decide whether to extract invariants as short canonical tokens (e.g. `exit 2`, `≤100 lines`, `@import`) rather than full sentences to maximize match robustness (recommended).

### Pattern 3: Single-file audit via temp-dir shim (D-13 / RESTR-05)
**What:** `audit-setup.sh` audits a *directory's* `CLAUDE.md` (audit-setup.sh:28–42), not an arbitrary file. To gate one proposed staging file, stage it as `CLAUDE.md` in a throwaway dir.
**Example:**
```bash
# Source: scripts/audit-setup.sh:28-48 (CLAUDE.md + @import + cap checks are dir-scoped)
audit_staged() {
  local staged="$1" tmp rc
  tmp="$(mktemp -d)"
  cp "$staged" "$tmp/CLAUDE.md"
  mkdir -p "$tmp/.claude"                   # audit-setup.sh:48 errors+exit 2 if .claude/ absent
  bash "$CONJURE_HOME/scripts/audit-setup.sh" "$tmp"; rc=$?
  rm -rf "$tmp"
  return "$rc"                              # 0=pass 1=warn 2=err — block on the @import err / cap-breach
}
```
**Important:** audit-setup.sh treats >200 lines as a hard `err`(FAIL→exit 2) and `@import` as `err`. A CLAUDE.md at 101–200 lines is a *warn* (rc=1), not a fail — but the restructure goal is ≤100 (CLAUDE_MD_CAP). Planning should decide whether the gate blocks on rc≥1 (strict, enforces ≤100) or rc≥2 (only hard errors). **Recommendation:** block on `@import` (always a hard error) and on >100 lines specifically; a pure `grep '^@'` + `wc -l` check on the staged file is simpler and exactly matches RESTR-05's two named conditions ("@imports or cap breaches") without the temp-dir `.claude/` ceremony. Both approaches are viable — temp-dir shim reuses `conjure audit` verbatim (D-13 literal wording: "run `conjure audit`"); the direct grep is leaner. (See Open Question O-2.)

### Pattern 4: Per-class grouped approval over /dev/tty (D-09/10/12)
**What:** Group `restructure_steps[]` (or `files[]`) by `classification`; present ONE prompt per non-empty bucket. Walk via fd-3 (resolve.sh pattern) so the inner `/dev/tty` read isn't consumed.
**Example:**
```bash
# Source: scripts/resolve.sh:40-82 + scripts/adopt.sh:367-380 (both shipped)
if ! { [ -t 0 ] || [ "${CONJURE_FORCE_INTERACTIVE:-0}" = "1" ]; }; then
  echo "restructure: stdin is not a TTY — interactive approval required" >&2
  exit 2                                                  # D-12: never auto-approve
fi
for bucket in core skill agent planning-doc reference-doc unknown; do
  # ... emit the bucket summary (count, sample paths) ...
  while true; do
    read -r -p "  [a]pprove / [s]kip / [e]dit: " choice < /dev/tty
    case "$choice" in
      a|approve) conjure adopt --apply-step "$id"; break ;;   # routes through mutate.sh
      s|skip)    log_step RESTRUCTURE "skipped $bucket bucket"; break ;;
      e|edit)    "${EDITOR:-vi}" "$STAGING_FILE"; rerun_gates || continue ;;  # D-10 re-run + re-prompt
      *)         echo "  enter a, s, or e" ;;                 # D-14-style: no default
    esac
  done
done
```

### Anti-Patterns to Avoid
- **Skill calling Write/Edit on a project file** — breaks RESTR-02 chokepoint, bypasses `mutate.sh` + audit trail. `allowed-tools: [Read, Bash]` physically prevents it; never rationalize a workaround.
- **Passing op JSON to `conjure adopt --update-manifest` via the env var** — `cmd_adopt` does not forward `CONJURE_ADOPT_STEP_JSON`; through the CLI only stdin works (Pitfall 2).
- **Auditing/verifying AFTER apply** — both gates MUST run on the *staging* file before approval (D-13/14). Post-write is too late (CR-1/CR-5).
- **One prompt per file at scale** — D-09 mandates per-class grouping; per-file at 50+ files is approval fatigue (CR-7).
- **Archive before write/extract** — archive steps are LAST (D-15); decision-vocabulary files individually confirmed (D-11).
- **`exit 1` on gate failure** — project convention is `exit 2` (CLAUDE.md). CI greps for `exit 1`.
- **Cramming gate logic into SKILL.md** — D-01: logic lives in `gates/*.sh`; SKILL.md is orchestration prose only (and must stay ≤200 lines).

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Apply a write/archive/extract op safely | A bespoke mutation path in the skill | `conjure adopt --apply-step` | Shipped + tested: op-allowlist, `resolve_under` path-containment, protected-dir denylist (.git/.conjure-*), sha256 state recording (adopt.sh:469–607). |
| Persist a proposed op into the manifest | Manual `jq`/heredoc edit of adopt-manifest.json | `conjure adopt --update-manifest` (stdin) | Shipped: atomic temp+mv (`manifest_write_atomic`, adopt.sh:400), required-field + op-allowlist validation, `--argjson` injection-safe. |
| `@import` / cap-breach detection | Reimplement cap logic in the skill | `conjure audit` / `audit-setup.sh` (or its `grep '^@'`+`wc -l` core) | Single source of truth via `lib/caps.sh`; D-13 says reuse it. |
| Interactive TTY prompt with non-TTY safety | Custom stdin reader | Mirror `recovery_prompt`/`resolve.sh` `/dev/tty` + `[ -t 0 ]` guard | Established, tested pattern; exit-2-on-non-TTY is the project trust model (D-12). |
| Append a human-readable per-step log | `echo >> RESTRUCTURE-LOG.md` | `log_step <phase> <msg>` (lib/log.sh) | DRY_RUN-safe via `mutate_write --append`; structured `[TS][PHASE]` format (SAFE-07). |
| Scaffold the skill into the target | A new copy step in adopt.sh | Add `restructure` to `init-project.sh:59` loop | adopt.sh already calls `init-project.sh existing "$TARGET"` (adopt.sh:734); the skill lands automatically (D-16). |

**Key insight:** Phase 23 is overwhelmingly *orchestration of shipped primitives*. The genuinely new code is small: 3–4 short gate helpers + the SKILL.md prose + a one-line scaffold edit. The op-executor, manifest atomicity, path containment, snapshot/rollback, and TTY/non-TTY conventions are all done and tested. Resist re-implementing any of them.

## Runtime State Inventory

> This phase ships a NEW skill template + gate helpers; it does not rename/migrate existing runtime state. The relevant "state" is the transient adopt-state the skill reads/writes.

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | `adopt-manifest.json` (`restructure_steps[]`, `files[]` with `classification`/`size_cap_exceeded`) — read by skill, appended via `--update-manifest`. Transient `.conjure-adopt-state/staging/<file>` + new `.conjure-adopt-state/INVARIANTS.txt` (D-03). | Skill reads manifest (Read); writes staging + INVARIANTS.txt via Bash (transient adopt-state, not project files). No migration. |
| Live service config | None — no external services. | None. |
| OS-registered state | None. | None. |
| Secrets/env vars | `CONJURE_HOME` (kit root, used by gate helpers to find `audit-setup.sh`/`lib`); `CONJURE_FORCE_INTERACTIVE` (test escape hatch, mirror existing). `EDITOR` for the `edit` verb (resolve.sh:68 precedent: `${EDITOR:-vi}`). | Skill/helpers must resolve `CONJURE_HOME` (the kit may be elsewhere than the target — `CONJURE_HOME` is intentionally NOT sandboxed, sandbox.sh note). |
| Build artifacts / installed packages | None — no compiled output. The scaffolded `.claude/skills/restructure/` in the target IS the artifact, produced by `init-project.sh`. | Verify scaffold lands all of `SKILL.md` + `gates/*.sh` (recursive `mutate_cp` of the dir, init-project.sh:61 copies the whole dir). |

**Verified explicitly:** No databases, no live-service config, no OS registrations, no secrets keyed on a renamed string. The only persistent project artifacts the skill creates go through `conjure adopt --apply-step` (mutate.sh chokepoint, recorded for rollback).

## Common Pitfalls

### Pitfall 1: `conjure audit` has no single-file mode (RESTR-05 blocker)
**What goes wrong:** `audit-setup.sh` cds into a TARGET *directory* and audits `$TARGET/CLAUDE.md` (line 13, 28). Pointing it at a staging file path does nothing useful, and it `exit 2`s immediately if `.claude/` is absent (line 48).
**Why it happens:** The audit was built as a whole-repo health check (Phase 21), not a per-file linter.
**How to avoid:** Use the temp-dir shim (Pattern 3) — stage the proposed file as `CLAUDE.md` in a `mktemp -d` with an empty `.claude/`, then `audit-setup.sh <tmpdir>`. OR (leaner, recommended) run the two named checks directly on the staged file: `grep -q '^@' "$staged"` (→ block) and `[ "$(wc -l < "$staged")" -gt "$CLAUDE_MD_CAP" ]` (→ block), sourcing `lib/caps.sh` for the cap. Decide in planning (Open Question O-2). Either way the gate runs BEFORE approval (D-13).
**Warning signs:** The gate "passes" on content with an `@import` because audit was pointed at the wrong path.

### Pitfall 2: `--update-manifest` op-JSON must go via stdin through the CLI
**What goes wrong:** Skill sets `CONJURE_ADOPT_STEP_JSON=...; conjure adopt --update-manifest` and the op is silently read from stdin (empty) → `exit 2` "no step JSON provided".
**Why it happens:** `cmd_adopt` (cli/conjure:196–220) parses flags into `CONJURE_ADOPT_*` env vars but does NOT forward `CONJURE_ADOPT_STEP_JSON` to the `bash adopt.sh` exec. The env var path works only on a direct `bash scripts/adopt.sh --update-manifest` (used in the Phase 22 tests with explicit env). Through the public `conjure adopt` command the supported path is stdin.
**How to avoid:** Skill always does `printf '%s' "$op_json" | conjure adopt --update-manifest`. Verified at adopt.sh:422–426 (stdin fallback) and cli/conjure:218 (env not forwarded).
**Warning signs:** "no step JSON provided" exit 2 when the skill thinks it set the env var.

### Pitfall 3: Invariant rephrasing defeats substring match (CR-1 residual)
**What goes wrong:** The LLM condenses "hooks must `exit 2`, never `exit 1`" into "hooks exit with code 2", and a substring match on "must exit 2" misses it → false BLOCK (annoying) or, worse, the invariant was extracted as loose prose and a too-permissive match passes a genuinely-dropped constraint.
**Why it happens:** Substring matching is literal; LLM paraphrase is not (CR-1 / arXiv "lost in the middle").
**How to avoid:** Extract invariants as **short canonical tokens**, not full sentences — e.g. `exit 2`, `@import`, `≤100`, `mutate.sh`, named commands in backticks — per D-06's scope ("named commands / backtick'd tokens"). Tokens survive reflow and paraphrase far better than sentences. The LLM-confirms-verbatim step (D-05) plus token-level verification is the layered defense. Planning should specify the extraction granularity.
**Warning signs:** Frequent false blocks on legitimately-condensed files, or an audit-passing CLAUDE.md that later violates a constraint.

### Pitfall 4: SKILL.md exceeding 200 lines (criterion 1 failure)
**What goes wrong:** Orchestration prose + gate-invocation detail + approval-flow narration blows past 200 lines; `audit-setup.sh:58` warns; criterion 1 fails.
**Why it happens:** The flow is genuinely multi-step (load/extract/propose/gate-A/gate-B/approve/archive).
**How to avoid:** D-01 is the resolution — push ALL logic into `gates/*.sh`; SKILL.md narrates "run `gates/verify-invariants.sh`; if it exits non-zero, STOP and show the user the missing list." Use tables (per `_anatomy`) for the gate catalog and the approval-verb semantics. The skill body is a runbook, not an implementation.
**Warning signs:** SKILL.md contains bash logic (loops, normalization) instead of "invoke helper X, interpret its exit code."

### Pitfall 5: Decision-vocabulary scan over-matching pulls everything to individual confirm
**What goes wrong:** `do not` / `never` are common English; grepping them across all archive candidates flags most files → defeats bulk approval (re-introduces fatigue, CR-7).
**Why it happens:** The keywords (D-11) are deliberately broad to catch active decisions (CR-6), but they're also common words.
**How to avoid:** Scope the scan to archive candidates only (not the whole corpus), and consider anchoring (`decided`, `we chose`, `rationale` are stronger signals than bare `never`). D-11 is explicit about the five terms; planning may add word-boundary `grep -iw` to reduce noise. Accept that over-flagging is the *safe* failure direction (individual confirm never loses a decision; bulk-archiving one would — CR-6 is HIGH severity). Tune toward false-positives.
**Warning signs:** 30 of 35 planning docs flagged for individual confirmation — re-examine the scan precision, but don't relax below the five D-11 terms.

## Code Examples

### Group proposed steps by classification for per-class approval (D-09)
```bash
# Source: adopt-manifest.schema.json (files[].classification enum) + jq manual
# Distinct non-empty buckets present in the manifest, in archive-last order handled separately.
for bucket in core skill agent planning-doc reference-doc unknown; do
  count="$(jq -r --arg b "$bucket" '[.files[] | select(.classification==$b)] | length' "$MANIFEST")"
  [ "${count:-0}" -gt 0 ] || continue
  echo "── $bucket ($count files) ──"
  jq -r --arg b "$bucket" '.files[] | select(.classification==$b) | "    " + .path' "$MANIFEST" | head -5
  # ... one /dev/tty approval prompt for the whole bucket ...
done
```

### Extract invariant signal lines from the source CLAUDE.md (D-06, the LLM-assisted pre-pass backstop)
```bash
# Source: PITFALLS.md CR-1 signal patterns + D-06 scope. The skill (LLM) refines this into
# INVARIANTS.txt; this grep is the deterministic seed/checklist the LLM must cover.
grep -niE 'must|never|always|forbidden|required|do not|exit 2|@import|≤[0-9]+|[0-9]+ lines|`[^`]+`' "$SRC_CLAUDE" \
  > "$STATE_DIR/INVARIANTS.candidates"
# Scope to CLAUDE.md + root markdown only (PITFALLS.md: full-tree grep is 30s+ on 2180 files).
```

### Scaffold-list edit (D-16, criterion 1)
```bash
# Source: scripts/init-project.sh:59 (the tooling-skills loop adopt calls as a subprocess)
# BEFORE: for skill in code-graph docs-lookup web-research ast-search repo-pack sql-explorer _anatomy; do
# AFTER:  for skill in code-graph docs-lookup web-research ast-search repo-pack sql-explorer restructure _anatomy; do
# adopt.sh:734 runs `init-project.sh existing "$TARGET"`, so restructure lands during conjure adopt.
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `allowed-tools` as space-separated string only | Accepts space- OR comma-separated string **OR a YAML list** | current Claude Code docs | `allowed-tools: [Read, Bash]` (D-16's exact spec) is VALID — no need to rewrite as `Read Bash`. `[VERIFIED: code.claude.com/docs/en/skills]` |
| Custom commands in `.claude/commands/` | Merged into skills (`.claude/skills/<name>/SKILL.md`) | current Claude Code docs | The restructure skill is a standard skill; user invokes via `/restructure` or Claude auto-loads on relevant request. `disable-model-invocation: true` available if manual-only is desired (discretionary). |
| Patch files under `.claude/adopt-patches/` (early research, STACK.md) | `restructure_steps[]` in the manifest + staging-path content refs | Phase 21/22 lock-in (D-07) | Research SUMMARY Open Question O-4 is RESOLVED: manifest `restructure_steps[]` + `--apply-step` won (one-file state). Ignore the patch-file variant. |

**Deprecated/outdated:**
- The 11-tag classification scheme in early ARCHITECTURE.md — superseded by the 6 deterministic buckets (Phase 21 D-01). The skill groups by these 6.
- `CONJURE_ADOPT_STEP_JSON` as the skill's update path — works only on direct `adopt.sh` calls (tests), NOT through `conjure adopt`. Skill uses stdin.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | The `init-project.sh:61` `mutate_cp "$KIT/templates/skills/$skill" ".claude/skills/$skill"` recursively copies the whole skill dir (so `gates/*.sh` land too) | Don't Hand-Roll / scaffold | If `mutate_cp` is file-only, the gates wouldn't ship; criterion 1 partially fails. MITIGATION: planning verifies `mutate_cp` directory behavior (it copies dirs for every other skill, which have subfiles — LOW risk). `[ASSUMED]` |
| A2 | Block-on-rc threshold for the audit gate (rc≥1 strict vs rc≥2 errors-only) | Pattern 3 / Pitfall 1 | Too-strict blocks legitimate 101–200-line intermediate states; too-loose lets a >100 file through to approval. Decide in planning (O-2). `[ASSUMED]` |
| A3 | Invariant extraction granularity = canonical tokens (not full sentences) is the robust choice | Pattern 2 / Pitfall 3 | If sentences are used, paraphrase causes false blocks (D-07 explicitly chose normalized substring to avoid this). Recommendation, not locked. `[ASSUMED]` |
| A4 | The staging-file write by the `[Read, Bash]` skill (Bash redirect into `.conjure-adopt-state/staging/`) is acceptable under D-04 ("write proposed ops + staged content") | Pattern 1 caveat | If the user intends staging content to also route through a CLI primitive, the skill would need a `--stage-file` flag (not shipped). D-04 wording + Phase 22 22-03-SUMMARY ("skill writes staged content to staging/<file>") support the Bash-redirect reading. Confirm in planning. `[ASSUMED]` |

## Open Questions (RESOLVED)

> All three resolved during planning; resolutions recorded in 23-VALIDATION.md "## Planning Resolutions" and encoded in the plans (23-01/23-02).

1. **Audit gate strictness (O-1)**
   - What we know: `audit-setup.sh` treats `@import` and >200 lines as hard errors (exit 2), 101–200 lines as warn (exit 1). RESTR-05 names two conditions: "`@imports` or cap breaches."
   - **RESOLVED — block on the two NAMED conditions, not the audit rc.** `gates/audit-staged.sh` runs the real `conjure audit` (temp-dir shim) to SURFACE the human-readable WHY (faithful to D-13/RESTR-05), but the deterministic BLOCK decision is: `@import` present (`grep -q '^@'`) OR line count > `CLAUDE_MD_CAP` (100, the restructure target). This avoids the checker-found trap where `conjure audit` returns rc=1 for unrelated harness-completeness WARNs and would block every clean proposal. See 23-02 Task 1.

2. **Invariant extraction granularity (O-2)**
   - What we know: D-06 scope = imperatives/prohibitions + exit-code rules + caps + named/backtick'd tokens; D-07 = normalized substring match.
   - **RESOLVED — short canonical TOKENS** (e.g. `exit 2`, `@import`, `≤100`, command names), not full sentences — maximizes normalized-substring robustness against LLM paraphrase (CR-1). The LLM lists + confirms each invariant at draft time; the bash gate (`verify-invariants.sh`) is the deterministic backstop. See 23-01 Task 2 (INVARIANTS.txt) + 23-02 Task 1/2.

3. **`edit` verb mechanics (O-3, discretionary)**
   - What we know: `edit` re-opens the staged file and RE-RUNS gates before re-prompt (D-10); `resolve.sh:68` uses `${EDITOR:-vi}`.
   - **RESOLVED — LLM re-draft via `--update-manifest`, no `$EDITOR` launch.** On `edit`, the skill prompts the user (via `/dev/tty`) for the change, re-drafts the staged content, re-writes it through `conjure adopt --update-manifest`, then RE-RUNS both gates before re-prompting. Keeps the Read+Bash proposer model intact (the LLM is the editor). See 23-03.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| bash | All gate helpers + skill Bash calls | ✓ | 3.2.57 (dev); CI matrix incl. Git Bash | — (must be 3.2-safe) |
| jq | manifest read, op-JSON build, group-by | ✓ | present | — (already a hard dep of adopt) |
| grep/sed/tr/awk | invariant grep, normalize, decision-scan | ✓ | present | — |
| `conjure adopt` (--update-manifest/--apply-step) | RESTR-02 mutation seam | ✓ | shipped Phase 22, 394 tests green | — (hard dependency; roadmap gates Phase 23 on it) |
| `conjure audit`/audit-setup.sh | RESTR-05 gate | ✓ | shipped | direct grep/wc fallback (Pattern 3) |
| `/dev/tty` | interactive approval | ✓ (dev) | — | non-TTY → exit 2 (D-12); `CONJURE_FORCE_INTERACTIVE=1` test hatch |

**Missing dependencies with no fallback:** None — every dependency is shipped and tested.
**Missing dependencies with fallback:** `conjure audit` single-file mode (use temp-dir shim or direct grep/wc — Pattern 3).

## Validation Architecture

**Test framework:** Hand-rolled `tests/run.sh` (2925 lines) with `pass`/`fail` helpers + `tests/lib/sandbox.sh` isolation; `bats-core` only at unit level (STACK.md). NO new test deps.

### Test Framework
| Property | Value |
|----------|-------|
| Framework | `tests/run.sh` (hand-rolled pass/fail) + `tests/lib/sandbox.sh` |
| Config file | none — `bash tests/run.sh` |
| Quick run command | `bash tests/run.sh 2>&1 \| grep -iE 'restructure\|RESTR\|Phase 23'` |
| Full suite command | `bash tests/run.sh` (expect PASS ≥ 394 + new Phase 23 asserts, FAIL 0) |
| Lint gate | `shellcheck -S error -e SC2164,SC2044,SC2034,SC2155 templates/skills/restructure/gates/*.sh scripts/init-project.sh` |
| Convention gate | `grep -v '^#' templates/skills/restructure/gates/*.sh \| grep -c 'exit 1'` → must be 0 |
| Skill frontmatter gate | SKILL.md has `name:`+`description:` (audit-setup.sh:61/64); `wc -l` ≤ 200 (criterion 1) |

### Phase Requirements → Test Map
| Req / Criterion | Behavior | Test Type | Automated Command (sketch) | Deterministic? | File Exists? |
|-----------------|----------|-----------|----------------------------|----------------|--------------|
| Crit-1 / RESTR-01/02 | `restructure` scaffolded at `.claude/skills/restructure/SKILL.md`; frontmatter `allowed-tools: [Read, Bash]`; ≤200 lines | unit | scaffold a sandbox via `init-project.sh existing`, assert file exists, `grep -q 'allowed-tools:.*Read.*Bash'`, `[ $(wc -l <SKILL.md) -le 200 ]` | YES | ❌ Wave 0 |
| Crit-1 | `gates/*.sh` ship alongside SKILL.md (whole dir copied) | unit | assert `.claude/skills/restructure/gates/verify-invariants.sh` present after scaffold | YES | ❌ Wave 0 |
| RESTR-04 / Crit-4 | invariant present → gate passes; invariant omitted → gate exits 2 with missing list | unit | `gates/verify-invariants.sh <staging-with-invariant> <INVARIANTS.txt>` → rc 0; `<staging-missing>` → rc 2 + stdout lists missing | YES | ❌ Wave 0 |
| RESTR-04 | normalized match: reflowed/condensed CLAUDE.md still passes (case + whitespace) | unit | feed a whitespace-/case-mangled but content-complete file → rc 0 | YES | ❌ Wave 0 |
| RESTR-05 / Crit-5 | proposed CLAUDE.md with `@import` → audit gate exits 2 with audit output; clean file → rc 0 | unit | `gates/audit-staged.sh <file-with-@import>` → rc 2; clean ≤100-line file → rc 0 | YES | ❌ Wave 0 |
| RESTR-05 | >100-line proposed CLAUDE.md → cap-breach block | unit | `gates/audit-staged.sh <file-101-lines>` → rc≥1 (per O-2 decision) | YES | ❌ Wave 0 |
| RESTR-06 / Crit-6 | file with `we decided`/`never` → flagged individual; clean file → bulk-eligible | unit | `gates/decision-scan.sh <file-with-decided>` → rc/exit signals "individual"; clean → "bulk" | YES | ❌ Wave 0 |
| RESTR-03 / Crit-3 | non-TTY approval → exit 2 (never auto-approve); summary line logged for bulk | unit | drive the approval entry with piped/non-TTY stdin → exit 2; assert one `RESTRUCTURE` summary line in log for a bulk apply | YES (non-TTY path) | ❌ Wave 0 |
| RESTR-03 / Crit-2 | interactive `approve/skip/edit` loop; `edit` re-runs gates; never proceeds without response | manual / expect | manual UAT (Phase 22 precedent) OR `expect`-driven; `CONJURE_FORCE_INTERACTIVE=1` + `/dev/tty` | NO (interactive) | manual harness |
| RESTR-02 | applied op routed through `conjure adopt --apply-step` (mutate.sh); manifest `status: applied` | integration | synthetic manifest + staging (mirror tests/run.sh:2750), `--apply-step`, jq-assert `status==applied` + dest changed | YES | ❌ Wave 0 (reuses P22 fixture) |
| RESTR-01 | skill reads manifest summary + per-file classification | integration | drive group-by helper against `_adopt-restructure-steps` fixture; assert correct bucket counts | YES | ✓ fixture exists |
| Crit-6 | archive ops sequenced last in the proposed plan | integration | assert the skill's proposed-step ordering places `op:archive` after `write`/`extract` | YES | ❌ Wave 0 |

### Sampling Rate
- **Per task commit:** `bash tests/run.sh 2>&1 \| grep -iE 'restructure|RESTR|Phase 23'` (the new block) + `shellcheck -S error ... gates/*.sh`.
- **Per wave merge:** full `bash tests/run.sh` (no regression below 394 + new asserts green) + `grep -c 'exit 1'` on new scripts = 0.
- **Phase gate:** full suite green + SKILL.md ≤200 lines + frontmatter audit clean before `/gsd-verify-work`.

### Deterministic vs Interactive Split (per output mandate)
- **Deterministically testable (automate fully):** all four gate helpers (verify-invariants, audit-staged, decision-scan, extract-invariants), the scaffold-install (criterion 1), the invariant BLOCK (criterion 4), the audit BLOCK (criterion 5), archive-last sequencing (criterion 6), the non-TTY exit-2 approval guard (criterion 3 partial), and the `--apply-step` routing (RESTR-02). These mirror the Phase 22 op-executor block (tests/run.sh:2750–2883) and the resolve.sh non-TTY test (tests/run.sh:1496–1506).
- **Interactive (manual UAT or `expect`):** the live `approve/skip/edit` `/dev/tty` loop and the `edit`→re-run-gates→re-prompt cycle (criterion 2). Phase 22 precedent (STATE.md: "SIGKILL recovery test asserts the non-TTY exit-2 + last-completed form; interactive prompt deferred to manual verification"; 22-HUMAN-UAT.md). The automatable half (non-TTY exit 2) is in Wave 0; the interactive half is a documented manual UAT, OR an optional `expect` harness if the planner wants CI coverage.

### Wave 0 Gaps
- [ ] `tests/run.sh` — NEW `▸ Phase 23 — restructure gate helpers` block (graceful-red before the helpers exist, mirroring Phase 22 Wave 0 — STATE.md: "graceful-red test block gates every later verification").
- [ ] Synthetic gate fixtures: a staging CLAUDE.md WITH an invariant, one WITHOUT (for the BLOCK test); one with `@import`; one >100 lines; one with `we decided`/`never`; one clean reference-doc. Small inline `printf` heredocs (Phase 22 idiom, tests/run.sh:2762).
- [ ] Reuse `tests/fixtures/_adopt-restructure-steps/adopt-manifest.json` (exists) for the group-by + apply-step integration drive.
- [ ] `tests/lib/sandbox.sh` — reuse existing; `init-project.sh existing` scaffold test for criterion 1.
- [ ] (Optional) `expect` harness for the interactive approval loop — only if planner opts for CI coverage of criterion 2; otherwise manual UAT doc.

## Security Domain

`security_enforcement` is not set to `false` in config.json → treat as enabled.

### Applicable ASVS Categories
| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V1 Architecture | yes | Split-responsibility chokepoint: skill `[Read, Bash]` cannot mutate project files; all writes via `conjure adopt --apply-step` → `lib/mutate.sh`. |
| V5 Input Validation | yes | Op JSON validated by `--update-manifest` (`{id,op,status}` + op-allowlist, `--argjson` injection-safe, adopt.sh:435). Gate helpers read manifest via `jq` (no eval). INVARIANTS.txt is read as data. |
| V12 Files & Resources | yes | Path containment: `apply_step`'s `resolve_under` rejects `..`/absolute escape; protected-dir denylist (.git/.conjure-*) at adopt.sh:532. Gate helpers must only write under `.conjure-adopt-state/` (transient) — never project files. |
| V6 Cryptography | no | No crypto in this phase (sha256 verification lives in adopt rollback, already shipped). |
| V2/V3/V4 Auth/Session/Access | no | No auth surface; local CLI/skill on the user's own repo. |

### Known Threat Patterns for the restructure skill
| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Skill bypasses chokepoint via Write/Edit on a project file | Tampering | `allowed-tools: [Read, Bash]` (physical); optional `disallowed-tools: [Write, Edit]`; CI/audit verifies frontmatter (RESTR-02). |
| Malicious/garbled op JSON corrupts manifest | Tampering | `--update-manifest` jq-validate + atomic temp+mv (shipped, adopt.sh:400/435); skill builds JSON via `jq -n --arg`, never string interpolation. |
| Staged-file path traversal to write outside target | Tampering / EoP | `apply_step` `resolve_under` + staging-containment + protected-dir denylist (shipped, adopt.sh:513–537). Gate helpers must validate any path they touch is under `.conjure-adopt-state/`. |
| LLM silently drops a security/compliance invariant during condensation | Tampering (info-integrity) | Invariant gate (RESTR-04/D-05/08) blocks before approval; D-06 scope includes prohibitions + named commands. CR-1 (HIGH). |
| LLM re-introduces `@import` (eager-load foot-gun) while "fixing" | Tampering | Pre-write audit gate (RESTR-05/D-13) — `grep '^@'` blocks before approval. CR-5. |
| Auto-approval in non-interactive context (no human consent) | EoP / repudiation | Non-TTY `exit 2`, never auto-approve (D-12); mirrors resolve.sh/adopt.sh recovery. |
| Bulk-archiving a file holding an active, undocumented decision | Tampering (loss) | Decision-vocabulary scan → individual confirm (RESTR-06/D-11); archive sequenced last (D-15). CR-6 (HIGH). |
| Gate helper writing a project file (chokepoint leak) | Tampering | Helpers write ONLY `.conjure-adopt-state/INVARIANTS.txt`; assert in code review + test no helper touches a path outside adopt-state. |

## Sources

### Primary (HIGH confidence)
- Conjure source read this session: `scripts/adopt.sh` (op-executor 397–607, recovery_prompt 367, scaffold 715–755, mode dispatch 788–816), `scripts/audit-setup.sh` (full), `scripts/resolve.sh` (1–82), `scripts/init-project.sh` (40–80), `cli/conjure` (cmd_adopt 193–221), `lib/caps.sh`, `lib/log.sh`, `lib/mutate.sh` (signatures), `adopt-manifest.schema.json`, `tests/fixtures/_adopt-restructure-steps/adopt-manifest.json`, `tests/run.sh` (Phase 22 block 2750–2883; resolve 1496–1562), `tests/lib/sandbox.sh`, `templates/skills/_anatomy/SKILL.md`, `templates/skills/{release,code-graph}/SKILL.md`
- `.planning/phases/23-restructure-skill-safety-gates/23-CONTEXT.md` (D-01..D-16) — authoritative spec
- `.planning/phases/22-conjure-adopt-cli-core-rollback/{22-CONTEXT.md, 22-03-SUMMARY.md}` — the shipped seam contract
- `.planning/phases/21-foundation-libs-inventory/21-CONTEXT.md` — 6-bucket taxonomy + manifest schema decisions
- `.planning/REQUIREMENTS.md`, `.planning/ROADMAP.md` (Phase 23 goal + 6 criteria), `.planning/STATE.md`, `.planning/config.json`
- `.planning/research/SUMMARY.md`, `.planning/research/PITFALLS.md` (CR-1/CR-5/CR-6, decision-vocabulary)
- [Claude Code Skills docs](https://code.claude.com/docs/en/skills) — `allowed-tools` accepts space/comma string OR YAML list; `disallowed-tools`; `disable-model-invocation`; frontmatter reference. `[VERIFIED]`

### Secondary (MEDIUM confidence)
- PITFALLS.md cited arXiv summarization-failure sources (CR-1 LLM constraint-drop, "lost in the middle") — used to justify token-level invariant extraction (Pitfall 3).

### Tertiary (LOW confidence)
- None — every claim is grounded in read source or official docs.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all primitives shipped + verified in-repo; zero new deps.
- Architecture: HIGH — the seam is shipped & tested (Phase 22, 394 tests); skill is pure orchestration of read code.
- Pitfalls: HIGH for structural (audit single-file mode, stdin-not-env, scaffold-list edit — all verified against source); MEDIUM for the LLM-specific invariant-rephrase risk (derived from CR-1 research, mitigated by token extraction).
- Validation: HIGH — gate helpers are deterministic bash, directly testable; interactive loop has a documented manual/expect precedent.

**Research date:** 2026-05-29
**Valid until:** 2026-06-28 (stable — internal codebase + a locked Phase 22 contract; the only external dep is Claude Code skills frontmatter, which is backward-compatible)
