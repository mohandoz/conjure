# Phase 31: Deferred Debt + Test-Harness Hardening - Context

**Gathered:** 2026-06-04
**Status:** Ready for planning

<domain>
## Phase Boundary

Close v0.7.0's safety-critical test debt and make the test harness honestly report gated tests. Four debt items (DEBT-03 `git -C` empty-var guard, DEBT-04 `preflight.sh` exit 2, DEBT-05 `skip()` counter, DEBT-06 SCHM-STALE kill-safety) plus three UAT items (UAT-01 gated live `claude` smoke, UAT-02 gated live promptfoo eval, UAT-03 `tests/MANUAL-UAT.md`). No new user-facing features — `doctor`/`stats`/eval-expansion belong to Phases 32–34.

</domain>

<decisions>
## Implementation Decisions

### SKIP semantics (DEBT-05)
- **D-01:** `skip()` prints `  ○ <name> (reason)` inline at the point of skip, mirroring existing `pass()`/`fail()` style.
- **D-02:** Summary line becomes `PASS: N    FAIL: N    SKIP: N`.
- **D-03:** SKIP never affects exit code by default — exit stays `[ "$FAIL" -eq 0 ]`.
- **D-04:** Strict mode via env var `CONJURE_STRICT=1` (no CLI arg parser in run.sh; consistent with `CONJURE_LIVE_TEST`/`CONJURE_COST` style). In strict mode `skip()` routes to `fail()` with the reason — per-test granularity, exits non-zero via existing FAIL path. Intended for release machines where live tests MUST run.
- **D-05:** `skip()` applies to NEW gates only (UAT-01/02 and future gated tests). Existing soft gates (`IS_WINDOWS` conditionals, `PERF_CEILING`, gh-absent paths) are NOT migrated — zero regression risk in the 5000-line suite; migration is optional future debt.

### Live-test gating (UAT-01/02/03)
- **D-06:** Gates follow the roadmap success criteria exactly: claude smoke runs when `CONJURE_LIVE_TEST=1` AND `command -v claude` succeeds (skip with reason otherwise); promptfoo eval runs when `ANTHROPIC_API_KEY` is non-empty (skip otherwise). No master switch, no extra env vars.
- **D-07:** Live tests live inline in `tests/run.sh` as a new gated `▸ Live-system tests` section at the end — one suite, one summary, SKIP counts integrated.
- **D-08:** The claude-binary smoke exercises `claude plugin validate` against a scaffolded `.claude-plugin/` — the exact deferred Phase 25 HUMAN-UAT item. Narrow, deterministic, consumes no API tokens.
- **D-09:** The live promptfoo eval is a minimal probe: 1-test eval in a temp sandbox proving live enforcement wiring (broken hook → eval FAILS — the deferred Phase 28 item). One API call per run; not the full scaffold suite.
- **D-10:** `tests/MANUAL-UAT.md` uses checklist-per-scenario format: one section per manual item (MDM hardware: macOS plist + Windows PS1; managed-settings deploy), each with prerequisites, numbered steps, expected result, `- [ ]` checkboxes, and a field to record date/version verified.

### git -C guard (DEBT-03)
- **D-11:** Root-cause fix via a single `mk_tmpd()` helper in `tests/lib/sandbox.sh`: wraps `mktemp -d`, verifies result non-empty AND directory exists, hard-exits the suite (exit 2) on failure. `git -C` call sites need no change — an empty var can never reach them.
- **D-12:** Sweep scope: ALL test files — `tests/run.sh`, `tests/lib/sandbox.sh` (including `sandbox_setup`'s own `mktemp`), and any `tests/*.sh` helpers. Production `scripts/` untouched (beyond DEBT-03's "test sandboxes" wording).
- **D-13:** Regression gate: a self-test in `run.sh` greps `tests/` for raw `$(mktemp -d)` outside `sandbox.sh` and fails on new offenders — same pattern as existing convention gates.

### SCHM-STALE kill-safety (DEBT-06)
- **D-14:** Eliminate the swap entirely: add a `CONJURE_SCHEMA_FILE` env override to the schema lookup in `scripts/audit-setup.sh`; the SCHM-STALE test points it at the stale fixture. Production `lib/cc-schema.json` is never touched — kill-safe by construction (SIGKILL-proof, unlike trap-based restore).
- **D-15:** The "atomic `jq > tmp && mv` where a write path exists" clause is satisfied by documentation only: no schema-mutating code exists today (`conjure update` replaces the whole kit). Add a comment block at the schema lookup in `audit-setup.sh` (and/or a FAILURE-MODES.md note) mandating tmp-&&-mv atomic swap for any future `cc-schema.json` write. No speculative `_atomic_write()` helper.
- **D-16:** Quick audit of other tests mutating production kit files in place: grep `run.sh` for `cp`/`mv` targeting `$CONJURE_HOME` paths; any other production-file swap gets the same no-swap/env-override (or trap) treatment. RETROSPECTIVE.md flagged the pattern, not just the one instance.

### Claude's Discretion
- **DEBT-04 rollout:** scout confirmed `scripts/preflight.sh:109` holds the sole `exit 1`; all callers (`cli/conjure:84,172,174,234`) use generic `|| return 1` with no `$? -eq 1` equality checks. Mechanical change + caller-audit note in the plan; planner decides where to record the audit evidence.
- Exact `skip()` glyph/wording, section placement details, MANUAL-UAT.md exact headings — planner/executor judgment within the decisions above.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Requirements + deferred-debt provenance
- `.planning/REQUIREMENTS.md` — DEBT-03/04/05/06 + UAT-01/02/03 definitions (lines 10–21)
- `.planning/ROADMAP.md` — Phase 31 goal + 5 success criteria (lines 52–62)
- `.planning/STATE.md` — Deferred Items table mapping v0.7.0 debt to Phase 31; Blockers section notes the preflight caller-audit condition
- `.planning/RETROSPECTIVE.md` §line 159 — the real SCHM-STALE incident: interrupted run shipped the stale fixture into production `lib/cc-schema.json`

### Research
- `.planning/research/STACK.md` §"SCHM-STALE atomic swap" (~lines 2044, 2283, 2341) — atomic `jq > tmp && mv` pattern already used in `scripts/workspace.sh`; documents the future-write-path expectation

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `tests/lib/sandbox.sh` — sourced helper lib; natural home for `mk_tmpd()`; its own `sandbox_setup()` uses raw `mktemp -d` and must migrate too
- `tests/run.sh:10-16` — `PASS`/`FAIL` counters + `pass()`/`fail()` one-liners; `skip()` slots in beside them; summary block at file tail (`PASS: $PASS    FAIL: $FAIL`)
- `scripts/eval.sh:277` — existing `ANTHROPIC_API_KEY` advisory warn; the live promptfoo probe gates on the same var
- `scripts/workspace.sh` — has the `jq > tmp && mv` atomic-swap pattern to cite in the DEBT-06 documentation comment

### Established Patterns
- Env-var gating convention: `CONJURE_COST`, `CONJURE_EXACT`, `IS_WINDOWS` — `CONJURE_LIVE_TEST` and `CONJURE_STRICT` follow it
- Convention self-tests (grep gates) already exist in run.sh — the raw-mktemp gate copies that shape
- Scripts/hooks exit 2, never exit 1 (project constraint) — drives DEBT-04 and `mk_tmpd()` failure exit code

### Integration Points
- `scripts/preflight.sh:109` — the only `exit 1`; callers at `cli/conjure:84,172,174,234` all use `|| return 1` (generic non-zero check — safe to change)
- SCHM-STALE test at `tests/run.sh:5107-5139` — the cp-swap to replace with `CONJURE_SCHEMA_FILE` override
- Schema lookup in `scripts/audit-setup.sh` (~line 484, SCHM-STALE section) — where the env override + documentation comment land
- ~30+ `git -C "$VAR"` sites in `tests/run.sh` all downstream of `mktemp -d` assignments — fixed at source by `mk_tmpd()`

</code_context>

<specifics>
## Specific Ideas

- Strict mode exists for release machines: `CONJURE_STRICT=1 CONJURE_LIVE_TEST=1 ANTHROPIC_API_KEY=… tests/run.sh` must fail if any live test would skip.
- Kill-safety "by construction" preferred over trap choreography — user explicitly chose eliminating the swap over trap-based restore because SIGKILL defeats traps.

</specifics>

<deferred>
## Deferred Ideas

- Migrating existing soft gates (`IS_WINDOWS`, `PERF_CEILING`, gh-absent) onto `skip()` for fully accurate SKIP counts — optional future debt, not this phase.

</deferred>

---

*Phase: 31-Deferred Debt + Test-Harness Hardening*
*Context gathered: 2026-06-04*
