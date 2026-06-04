# Phase 31: Deferred Debt + Test-Harness Hardening - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-04
**Phase:** 31-Deferred Debt + Test-Harness Hardening
**Areas discussed:** SKIP semantics, Live-test gating, git -C guard style, SCHM-STALE kill-safety

---

## SKIP semantics

| Option | Description | Selected |
|--------|-------------|----------|
| Inline + summary | `skip()` prints `  ○ <name> (reason)` inline + `PASS/FAIL/SKIP` summary line | ✓ |
| Summary count only | Silent inline; only summary shows SKIP count | |
| Inline + end-of-run list | Inline marks plus a "Skipped:" block before summary | |

**User's choice:** Inline + summary

| Option | Description | Selected |
|--------|-------------|----------|
| Never | Exit stays `[ "$FAIL" -eq 0 ]`; skips expected without claude/key | |
| Strict-mode flag | Opt-in mode that turns any skip into fail — for release machines | ✓ |
| Fail if ALL live skipped in CI | Auto-detect CI env and fail on gated skips there | |

**User's choice:** Strict-mode flag

| Option | Description | Selected |
|--------|-------------|----------|
| Env var CONJURE_STRICT=1 | Consistent with CONJURE_LIVE_TEST/CONJURE_COST; no arg parser | ✓ |
| CLI flag --strict | More discoverable but first-ever arg parsing in run.sh | |
| Both | Env var + flag alias | |

**User's choice:** Env var `CONJURE_STRICT=1`

| Option | Description | Selected |
|--------|-------------|----------|
| Skips become failures | In strict mode `skip()` calls `fail()` with reason; per-test granularity | ✓ |
| Exit check only | Tests print as skipped; final exit non-zero when SKIP>0 | |

**User's choice:** Skips become failures

| Option | Description | Selected |
|--------|-------------|----------|
| New gates only | skip() for UAT-01/02 + future gates; existing IS_WINDOWS conditionals untouched | ✓ |
| Migrate all gates | Sweep all existing conditional-skip patterns onto skip() | |
| Migrate obvious ones | New gates + clearly-gated Windows blocks | |

**User's choice:** New gates only

---

## Live-test gating

| Option | Description | Selected |
|--------|-------------|----------|
| Per success-criteria | claude smoke: CONJURE_LIVE_TEST=1 AND command -v claude; promptfoo: ANTHROPIC_API_KEY non-empty | ✓ |
| Single master switch | CONJURE_LIVE_TEST gates both; key additionally required for promptfoo | |
| Separate vars each | CONJURE_LIVE_TEST + CONJURE_LIVE_EVAL | |

**User's choice:** Per success-criteria

| Option | Description | Selected |
|--------|-------------|----------|
| Inline in run.sh | New gated "Live-system tests" section at end; one suite, one summary | ✓ |
| Separate tests/live.sh | Standalone gated suite; splits accounting | |
| Both-file hybrid | Bodies in live.sh, sourced by run.sh | |

**User's choice:** Inline in run.sh

| Option | Description | Selected |
|--------|-------------|----------|
| Plugin validate | `claude plugin validate` against scaffolded .claude-plugin/ — exact Phase 25 deferred item | ✓ |
| Validate + version gate | Plus claude version ≥2.1.117 assert (overlaps Phase 32 doctor) | |
| Full init smoke | conjure init temp repo, validate end-to-end | |

**User's choice:** Plugin validate

| Option | Description | Selected |
|--------|-------------|----------|
| Minimal probe | 1-test eval in temp sandbox proving enforcement wiring; one API call | ✓ |
| Full scaffold suite | Whole emitted eval config; costlier per run | |
| You decide | Planner picks | |

**User's choice:** Minimal probe

| Option | Description | Selected |
|--------|-------------|----------|
| Checklist per scenario | Sections with prerequisites, steps, expected result, checkboxes, verified date/version | ✓ |
| Terse runbook | Commands + expected output only | |
| You decide | Planner derives from milestone-audit descriptions | |

**User's choice:** Checklist per scenario

---

## git -C guard style

| Option | Description | Selected |
|--------|-------------|----------|
| mk_tmpd() helper | Helper in sandbox.sh wrapping mktemp -d; non-empty + dir check; exit 2 on failure | ✓ |
| Inline guards | `[ -n "$VAR" ]` after each of ~30 mktemp sites | |
| tgit() wrapper | Guarded git wrapper — misses cp/rm on same empty var | |

**User's choice:** mk_tmpd() helper

| Option | Description | Selected |
|--------|-------------|----------|
| All test files | run.sh + sandbox.sh (incl. sandbox_setup) + tests/*.sh helpers | ✓ |
| run.sh only | Leaves sandbox_setup unguarded | |
| Tests + scripts/ | Beyond DEBT-03 scope | |

**User's choice:** All test files

| Option | Description | Selected |
|--------|-------------|----------|
| Self-test grep gate | Test greps tests/ for raw `$(mktemp -d)` outside sandbox.sh | ✓ |
| No gate | Rely on review | |
| Shellcheck-style CI job | Separate CI step | |

**User's choice:** Self-test grep gate

---

## SCHM-STALE kill-safety

| Option | Description | Selected |
|--------|-------------|----------|
| No-swap env override | CONJURE_SCHEMA_FILE override in audit-setup.sh; production file never touched; SIGKILL-proof | ✓ |
| Trap-based restore | Keep swap, trap restores — SIGKILL still loses | |
| Copy-the-kit | Swap in a temp copy of CONJURE_HOME; slow | |

**User's choice:** No-swap env override

| Option | Description | Selected |
|--------|-------------|----------|
| Document only | Comment at schema lookup mandating tmp && mv for future writes; no speculative code | ✓ |
| Ship _atomic_write() now | Dead code until something writes the schema | |
| You decide | Planner verifies then picks | |

**User's choice:** Document only

| Option | Description | Selected |
|--------|-------------|----------|
| Quick audit + fix offenders | Grep run.sh for cp/mv targeting $CONJURE_HOME; fix any other swap | ✓ |
| SCHM-STALE only | Fix the named instance | |
| Audit + grep gate | Also add a self-test grep — may be noisy | |

**User's choice:** Quick audit + fix offenders

---

## Claude's Discretion

- DEBT-04 preflight exit-2 rollout: callers verified safe (generic `|| return 1`, no `$? -eq 1` checks); planner decides where to record audit evidence
- Exact skip() glyph/wording, section placement, MANUAL-UAT.md exact headings

## Deferred Ideas

- Migrating existing soft gates (IS_WINDOWS, PERF_CEILING, gh-absent) onto skip() for fully accurate SKIP counts — future debt
