---
name: restructure
description: "Restructure an oversized CLAUDE.md + doc sprawl into a ≤100-line core plus extracted skills/refs and an archive. Invoke when the user asks to restructure, condense, slim down, or adopt a brownfield Claude Code harness."
allowed-tools: [Read, Bash]
disallowed-tools: [Write, Edit]
---

# restructure

Human-gated runbook for turning a brownfield repo's oversized `CLAUDE.md` and
scattered docs into a ≤100-line core harness with extracted skills/references and a
safe archive. You are the **proposer**: you read context and draft proposals, but you
NEVER mutate a project file directly — every change crosses the
`conjure adopt --apply-step` chokepoint into `lib/mutate.sh` (RESTR-02).

## The hard rule (RESTR-02)

- **NEVER call Write or Edit on a project file.** This skill is granted only
  `[Read, Bash]`. All mutation routes through the Phase 22 adopt seam
  (`scripts/adopt.sh`).
- Staged CONTENT (your draft of the condensed file) is written to
  `.conjure-adopt-state/staging/<file>` via a **Bash redirect** — a transient
  adopt-state path, not a project file.
- Register the proposed OP over **stdin**:
  `printf '%s' "$op" | conjure adopt --update-manifest`. NOTE: `adopt.sh` accepts the
  op from `CONJURE_ADOPT_STEP_JSON` *or* stdin, and the env var is **inherited by the
  child process** and read at **higher priority than stdin** (adopt.sh ~423). So the
  skill MUST use stdin AND MUST NOT have a stale `CONJURE_ADOPT_STEP_JSON` exported —
  if it might be set, `unset CONJURE_ADOPT_STEP_JSON` first so it cannot shadow the
  stdin payload.
- Build op JSON injection-safe with `jq -n --arg` — never string-interpolate into JSON.

## Inputs

| Input | Where | Read via |
| --- | --- | --- |
| Classified file inventory | `adopt-manifest.json` (`summary`, `files[].classification`, `files[].size_cap_exceeded`, `restructure_steps[]`) | Read |
| Oversized core | `CLAUDE.md` flagged in `size_cap_violations[]` | Read |
| Flagged docs | each `files[].path` (reference-doc / planning-doc / unknown) | Read |

Buckets follow the Phase 21 6-class taxonomy: `core skill agent planning-doc
reference-doc unknown` (see `adopt-manifest.schema.json`).

## Step sequence

1. **Read the manifest.** Load `adopt-manifest.json`; note `size_cap_violations[]`
   and the per-file `classification` buckets.
2. **Extract invariants.** Run `gates/extract-invariants.sh <CLAUDE.md>
   <.conjure-adopt-state>` to grep candidate constraints, then (LLM judgement)
   confirm the canonical token list into `.conjure-adopt-state/INVARIANTS.txt`
   (D-03/05/06). These are the non-negotiable rules the condensed core must keep.
   WR-03: GATE A is a substring backstop, NOT a semantic checker — confirm
   **distinctive multi-word** tokens (e.g. `hooks exit 2`, `do not delete user files`),
   never short/common ones (`exit 2`, `delete`), so the match cannot pass incidentally.
3. **Draft + stage proposals.** Draft the condensed `CLAUDE.md`, any extracted
   skill/reference files, and the archive list. Stage each draft to
   `.conjure-adopt-state/staging/<file>` (Bash redirect), then register the op over
   stdin. Order the proposed plan so the content-producing ops come first:
   - `op: write` — overwrite the condensed `CLAUDE.md` from its staging src.
   - `op: extract` — write a new skill/reference file and archive the old source.
   - `op: archive` — **LAST** (see step 6); move a now-redundant doc to the archive.
4. **PRE-APPROVAL GATES (D-14 — BOTH run on the STAGING file BEFORE the user sees the
   proposal).** Never audit/verify after apply.
   - **GATE A** — `gates/verify-invariants.sh <staging/CLAUDE.md>
     <.conjure-adopt-state/INVARIANTS.txt>`. Non-zero (exit 2) → STOP, show the
     missing-invariant list, re-draft (criterion 4).
   - **GATE B** — `gates/audit-staged.sh <staging-file>`. Non-zero (exit 2) → STOP,
     show the surfaced `conjure audit` output (an `@import` line or a cap breach),
     re-draft (criterion 5).
5. **Per-class approval.** Once both gates pass, run `gates/approve.sh <target>`. It
   presents ONE `/dev/tty` prompt per non-empty classification bucket (D-09),
   never one prompt per file at scale, and on a non-TTY stdin it exits 2 — it NEVER
   auto-approves (D-12). It logs ONE RESTRUCTURE summary line per bucket.
6. **Archive LAST (D-15).** Only after the write/extract ops are approved, process
   `op: archive` candidates. For each candidate run `gates/decision-scan.sh <file>`
   first: an `individual` signal pulls that file OUT of the bulk bucket into a single
   `/dev/tty` confirm (D-11, criterion 6); a `bulk` signal leaves it in the per-class
   archive bucket. Apply approved archives via `conjure adopt --apply-step <id>`.

## Gate catalog

| Helper | Purpose | Block condition | Criterion |
| --- | --- | --- | --- |
| `gates/extract-invariants.sh` | Grep candidate constraints → `INVARIANTS.candidates` | exit 2 on unreadable source / unsafe state dir | 4 |
| `gates/verify-invariants.sh` (GATE A) | Every confirmed invariant present in the condensed core | exit 2 if any invariant dropped | 4 |
| `gates/audit-staged.sh` (GATE B) | `conjure audit` shim on the staged file | exit 2 on `@import` (`^@`) or > `CLAUDE_MD_CAP` lines | 5 |
| `gates/decision-scan.sh` | Decision-vocabulary scan on an archive candidate | prints `individual` (escalate) vs `bulk` | 6 |
| `gates/approve.sh` | Per-class `/dev/tty` approve/skip/edit driver | exit 2 on non-TTY stdin | 3 |

## Verb semantics (D-10)

| Verb | Effect |
| --- | --- |
| `approve` | Apply the bucket's steps via `conjure adopt --apply-step <id>`; log one summary line |
| `skip` | Leave the file(s) as-is; log one summary line |
| `edit` | Re-draft the staged content, re-register via `conjure adopt --update-manifest`, RE-RUN GATE A + GATE B, then re-prompt (NO external editor — O-3) |

## Forbidden actions

- ❌ NEVER call Write or Edit on a project file — every mutation routes through
  `conjure adopt --apply-step` (RESTR-02). The skill is `[Read, Bash]` only.
- ❌ NEVER rely on `CONJURE_ADOPT_STEP_JSON` to pass the op — it is INHERITED by the
  child and wins over stdin (adopt.sh ~423). Pass the op via stdin and `unset` the env
  var if it may be set, so the intended stdin payload is never shadowed.
- ❌ NEVER audit or verify AFTER apply — GATE A + GATE B run on the staging file
  BEFORE the approval prompt (D-13/14).
- ❌ NEVER prompt once per file at scale — group by classification bucket (D-09).
- ❌ NEVER archive before the write/extract ops are approved — archive is sequenced
  LAST (D-15) and routed through `gates/decision-scan.sh`.
- ❌ NEVER auto-proceed on a non-TTY stdin — `gates/approve.sh` exits 2 (D-12).
- ❌ NEVER set or inherit `CONJURE_FORCE_INTERACTIVE` — it is a TEST-ONLY hatch that
  bypasses the non-TTY guard; in production it would let a piped `a` auto-approve with
  no human at a terminal (defeats D-12). The skill must run with it unset.
- ❌ NEVER `exit 1` in a helper — use `exit 2` to block (project convention).

## Cross-references

- The adopt seam (`--update-manifest` / `--apply-step`) → `scripts/adopt.sh`.
- The mutation chokepoint → `lib/mutate.sh`; the durable trail → `RESTRUCTURE-LOG.md`.
- Gate helpers → `gates/*.sh` in this skill dir.
- SKILL authoring rules → `skills/_anatomy/SKILL.md`.
