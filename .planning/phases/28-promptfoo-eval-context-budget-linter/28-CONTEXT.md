# Phase 28: promptfoo Eval + Context-Budget Linter - Context

**Gathered:** 2026-06-03
**Status:** Ready for planning
**Mode:** Smart discuss (autonomous — all 4 grey areas accepted as recommended)

<domain>
## Phase Boundary

Developers can scaffold, run, and CI-gate a promptfoo-based prompt-adherence eval suite
(`conjure eval init|run|--emit-workflow`), and `conjure audit` statically measures harness
context load (`--budget`) and reports eval coverage gaps (EVAL-05). Implements EVAL-01..05.

Future EVAL-F1 (`eval snapshot` baseline) and EVAL-F2 (per-skill trajectory stubs from
allowed-tools) are deferred.

Non-goals (locked, from REQUIREMENTS):
- Never bundle promptfoo as a dependency (keep `dependencies: {}` empty) — shell out to a
  pinned `npx --yes promptfoo@<version>`.
- `conjure eval` is opt-in and NEVER invoked from the `conjure audit`/`check` path. `audit`
  with promptfoo absent exits 0; `conjure eval` with promptfoo absent exits 2 (human-readable).
- Zero new runtime deps: promptfoo via npx; everything else jq + bash already in the envelope.

</domain>

<decisions>
## Implementation Decisions

### eval Config Generation
- promptfoo→Claude Code provider is RESEARCH-DETERMINED: prefer a low-risk `exec`/script
  provider that runs Claude Code headless (`claude -p <prompt>`) over the less-mature
  `claude-code-agent` provider. Research finalizes the exact provider block — this is the
  STATE-flagged novel area; the planner must NOT guess it without the research.
- `conjure eval init` scaffolds `.conjure/eval/promptfooconfig.yaml` with: one `skill-used`
  assertion per installed skill (deterministic, no repeat), and one `llm-rubric` assertion per
  CLAUDE.md "rule line" — defined as each imperative/bullet CONTENT line (non-heading,
  non-blank, non-table-row).
- ALL `llm-rubric` assertions use `repeat: 3, minPassCount: 2` (flakiness guard); `skill-used`
  assertions are deterministic (no repeat).
- The promptfoo version is pinned in a single `PROMPTFOO_VERSION` constant (research-confirmed
  known-good release); used by both `eval run` and the emitted workflow.

### eval Run + CI Workflow
- `conjure eval run` shells out to `npx --yes promptfoo@<PROMPTFOO_VERSION>` and passes the
  exit code through. Preflight: Node ≥20.20.0; if Node is missing/too-old → exit 2 with a
  human-readable message. promptfoo unavailable → exit 2 (human-readable). (`audit`/`check`
  never trigger this.)
- `conjure eval --emit-workflow` WRITES `.github/workflows/conjure-eval.yml` via `mutate_write`
  (backup-before-mutate); it is a `pull_request`-triggered gate using `promptfoo/promptfoo-action`
  with `fail-on-threshold`, path-triggered on `.claude/**` and `CLAUDE.md`.
- `fail-on-threshold` defaults to **`80`** (integer percent — high adherence without being
  brittle on the 3×/minPassCount-2 rubric flakiness). **Decision override (D-28-THRESH):** the
  original intent was "0.8" but RESEARCH (Pitfall 9) established `promptfoo/promptfoo-action`'s
  `fail-on-threshold` input is an INTEGER 0–100, not a float — passing `0.8` is read as <1% and
  the gate would never fail. The emitted workflow therefore uses `fail-on-threshold: 80`
  (== the intended 80% adherence). This supersedes the "0.8" wording.

### Context-Budget Linter (`conjure audit --budget`)
- `--budget` is a NEW flag on `conjure audit` (alongside existing `--json`/`--cost`/`--exact`/
  `--retire-list`). It REUSES the existing audit token tiers (≈15k ok / ≈25k over-budget→err)
  for consistency with the current `.claude/ token estimate` check (audit-setup.sh ~lines 233-239).
- "Always-loaded" scope = CLAUDE.md (always loaded) + each installed skill's SKILL.md INDEX
  (frontmatter/description — the always-surfaced part), NOT the lazy skill bodies. chars/4 heuristic.
- `--budget` flags over-threshold and lists the TOP 5 contributors by estimated tokens.
- `--porcelain` JSON shape: `{ total_tokens, threshold, over: bool, contributors: [ { path, tokens } ] }`.
- Over-budget keeps the existing behavior: ≥25k → `err()` (exit 2). `--budget` only enriches
  the human/porcelain output; it does not soften the existing gate.

### EVAL-05 Coverage + Severity
- `conjure audit` reports installed skills that have NO `skill-used` assertion in
  `.conjure/eval/promptfooconfig.yaml`. Severity = `note()` advisory (exit 0) — a coverage gap
  is informational, not a hard failure. A skill added after `conjure eval init` appears in the gap report.
- When `.conjure/eval/promptfooconfig.yaml` is ABSENT entirely → `note()` "no eval config —
  run `conjure eval init`" (informational), not a gap/fail.
- Command placement matches the ROADMAP SC: `eval init/run/--emit-workflow` live under a NEW
  `conjure eval` subcommand; `--budget` and the EVAL-05 coverage report live under `conjure audit`.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `scripts/audit-setup.sh` — already has a `.claude/ token estimate` check with tiers
  (<15k ok / <25k warn / ≥25k err, ~lines 233-239) and a `--cost`/`--exact` chars/4 estimator
  (~lines 435-474, with COST_TMP tempfile + the combined `_audit_cleanup` EXIT trap from Phase 27).
  `--budget` extends this; reuse the chars/4 + tier logic and the JSONL→jq porcelain pattern.
- `cli/conjure` — `cmd_audit` (flags `--json --cost --exact --retire-list`), `cmd_check`.
  Add `--budget` to audit; add a NEW `cmd_eval` + `eval)` dispatch + usage line (mirror how
  Phase 25/26/27 added commands/flags).
- `lib/inventory.sh` — skill discovery (`.claude/skills/*/SKILL.md`); reuse for the skill-used
  assertion list (EVAL-01) and the EVAL-05 coverage diff.
- `lib/mutate.sh` (`mutate_write`) + `lib/snapshot.sh` — for writing
  `.conjure/eval/promptfooconfig.yaml` and `.github/workflows/conjure-eval.yml` (backup-before-mutate).
- `--json`/`--porcelain` emitter pattern from Phase 27 (`json_check()`, JSONL→`jq -cn --slurpfile`,
  `human()` router) — reuse for `--budget --porcelain`.
- `tests/run.sh` + `tests/fixtures/` — fixture harness; add `_eval*` fixtures + a graceful-red
  EVAL block first (test-first; mirror Phase 25/26/27 `_emit-*`/`_schema-audit*` pattern).
- The Phase 26 emit-policy.sh shows the `--emit-workflow`-style file generation pattern
  (build content → validate → mutate_write → printed verification note).

### Established Patterns
- POSIX bash 3.2+ (no associative arrays / mapfile / local -n); inline shellcheck dirs;
  CI gate `shellcheck -S error -e SC2164,SC2044,SC2034,SC2155`.
- Hooks/CLI/scripts `exit 2`, never `exit 1` (audit summary gate's `exit 1` excepted).
- Bundled-not-fetched discipline: promptfoo is the exception (explicitly shelled via npx, never
  bundled), but Conjure itself adds NO dependency — `dependencies: {}` stays empty.
- Single combined EXIT-trap cleanup per script (Phase 27 lesson — bash has one EXIT slot;
  any new tempfile must join `_audit_cleanup`, not register its own trap).

### Integration Points
- New `cmd_eval` in `cli/conjure` + `eval)` dispatch + usage; new `scripts/eval.sh` worker.
- `--budget` + EVAL-05 coverage report added to `scripts/audit-setup.sh` (the EVAL-05 report
  needs `audit --json`/Phase 27 output discipline — feed the checks accumulator).
- `.conjure/eval/promptfooconfig.yaml` (generated) + `.github/workflows/conjure-eval.yml` (emitted).
- promptfoo is invoked ONLY from `conjure eval run`, never from audit/check.

</code_context>

<specifics>
## Specific Ideas

- The `--emit-workflow` output is an enforcement-not-disposition gate: deliberately breaking a
  hook binary must cause the eval suite to FAIL (a real test, per SC EVAL-03).
- `eval init` config: `skill-used` per installed skill + `llm-rubric` per CLAUDE.md rule line,
  all rubrics `repeat: 3, minPassCount: 2`.
- Node ≥20.20.0 preflight is a hard gate for `conjure eval run` (exit 2 if unmet).
- EVAL-05: a skill added AFTER `eval init` must surface in the coverage gap report (diff
  installed skills vs skill-used assertions present in the config).
- Keep `conjure audit`/`check` fully decoupled from promptfoo — promptfoo absent must never
  affect audit/check exit codes.

</specifics>

<deferred>
## Deferred Ideas

- EVAL-F1: `conjure eval snapshot` — local pass/fail baseline for before/after comparison.
- EVAL-F2: per-skill trajectory assertion stubs derived from `allowed-tools` frontmatter.

</deferred>
