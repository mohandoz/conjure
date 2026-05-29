---
phase: 23-restructure-skill-safety-gates
plan: 02
subsystem: restructure-skill
tags: [bash, safety-gates, restructure, invariants, audit-shim, decision-scan, nyquist]

# Dependency graph
requires:
  - phase: 23-restructure-skill-safety-gates
    provides: "Wave 0 graceful-red gate-helper assertions + _restructure-gates fixtures (INVARIANTS.txt, with/missing/reflowed-invariant.md, with-import/oversized/clean-doc/decision-doc.md)"
  - phase: 21-audit-drift
    provides: "scripts/audit-setup.sh exit 0/1/2 contract, lib/caps.sh CLAUDE_MD_CAP, scripts/check.sh drift manifest"
provides:
  - "GATE A verify-invariants.sh — normalized-substring invariant verifier (pre-approval BLOCK, D-05/07/08)"
  - "GATE B audit-staged.sh — single-file @import/cap-breach audit shim (pre-approval BLOCK, D-13/O-1)"
  - "extract-invariants.sh — D-06 signal-grep pre-pass → INVARIANTS.candidates under .conjure-adopt-state/"
  - "decision-scan.sh — D-11 archive guard signalling individual/bulk routing"
affects: [23-03-skill-scaffold, restructure-skill, scripts/check.sh]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Normalized-substring invariant matching (lowercase + ws-collapse + trim) survives reflow/case mangling (D-07)"
    - "Named-condition BLOCK decision (grep ^@ + line count > cap) decoupled from conjure-audit return code — audit shim surfaces WHY, the two named conditions decide the block (O-1/checker B1)"
    - "Chokepoint-confined file write: extract-invariants resolves output strictly under a .conjure-adopt-state component and refuses .. traversal (T-23-08)"
    - "stdout-token routing contract (individual/bulk) with always-exit-0-on-success, exit 2 only on unreadable input — never exit 1 (decision-scan)"
    - "Drift check only counts skill dirs that contain a SKILL.md — a partial skill dir (helpers staged before SKILL.md) does not register as drift"

key-files:
  created:
    - "templates/skills/restructure/gates/verify-invariants.sh"
    - "templates/skills/restructure/gates/audit-staged.sh"
    - "templates/skills/restructure/gates/extract-invariants.sh"
    - "templates/skills/restructure/gates/decision-scan.sh"
  modified:
    - "scripts/check.sh"

key-decisions:
  - "audit-staged BLOCK keys on two NAMED deterministic conditions (^@ @import, line count > CLAUDE_MD_CAP), NOT the conjure-audit return code — audit returns rc=1 for unrelated harness-completeness WARNs even on a clean CLAUDE.md, so keying on rc>=1 would block every clean proposal (checker B1 / O-1)"
  - "extract-invariants accepts both a bare base dir (nests .conjure-adopt-state) and an explicit .conjure-adopt-state dir; the security guard refuses .. traversal rather than the literal /tmp/not-adopt-state example, because the binding Wave 0 test passes a bare temp dir that must succeed"
  - "Fixed scripts/check.sh (Rule 1): the drift manifest enumerated every templates/skills/*/ dir and expected a SKILL.md; the Wave-1 partial restructure/ dir (gate helpers, no SKILL.md yet) registered as drift and broke DRIFT-01/02 + AUTPR-01. Now only skill dirs containing a SKILL.md are counted."

patterns-established:
  - "Pre-approval gate convention: both validation gates (A+B) run on the STAGING file before any human approval (D-14), hard-fail with exit 2, never exit 1"
  - "Over-flag-is-safe decision scan: word-boundary on bare terms (never/do not) to cut noise, but never relax below the 5 D-11 terms (CR-6 HIGH)"

requirements-completed: [RESTR-04, RESTR-05, RESTR-06]

# Metrics
duration: 35min
completed: 2026-05-29
---

# Phase 23 Plan 02: Restructure Safety Gate Helpers Summary

**Four deterministic bash gate helpers (verify-invariants = GATE A, audit-staged = GATE B, extract-invariants pre-pass, decision-scan archive guard) that block invalid LLM restructure proposals — dropped invariants, @imports, cap breaches, undocumented-decision archives — before any human approval, flipping all 12 Wave 0 gate-helper assertions green (406→418 PASS).**

## Performance

- **Duration:** ~35 min
- **Started:** 2026-05-29 (Phase 23 Wave 1 execution session)
- **Completed:** 2026-05-29
- **Tasks:** 2
- **Files modified:** 4 created, 1 modified

## Accomplishments
- **GATE A — verify-invariants.sh (60 lines):** normalizes the proposed CLAUDE.md to one lowercase/ws-collapsed/trimmed haystack line, then substring-matches each canonical token from INVARIANTS.txt with a bash-3.2-safe newline-delimited accumulator. Present/reflowed/case-mangled → rc 0; a dropped token → exit 2 with the intact missing list (`exit 2`, `do not delete`) on stderr (D-05/07/08).
- **GATE B — audit-staged.sh (72 lines):** stages the proposed file as CLAUDE.md in a `mktemp -d` with an empty `.claude/`, runs the REAL `conjure audit` to SURFACE the human-readable WHY, then makes the BLOCK decision on two NAMED conditions independent of the audit rc — `grep -q '^@'` (@import) and `grep -c '' > CLAUDE_MD_CAP` (cap breach). `@import`/oversized → exit 2 + surfaced output; clean ≤100-line file → exit 0. `trap 'rm -rf "$tmp"' EXIT` cleans the shim (T-23-10).
- **extract-invariants.sh (81 lines):** D-06 signal grep over the single source file → non-empty `INVARIANTS.candidates`, written strictly under a `.conjure-adopt-state` component; refuses `..` traversal (T-23-08). Captures the `exit 2` token the Wave 0 test asserts.
- **decision-scan.sh (39 lines):** scans the 5 D-11 terms (word-boundary on `never`/`do not` per Pitfall 5) over the single archive candidate; prints `individual` (with matching lines on stderr) or `bulk` to stdout, always exit 0 on success (D-11, CR-6).
- All four exit 2 never exit 1, are shellcheck-clean at error severity, and write no project files. Full suite: **418 PASS / 4 FAIL** (the 4 fails are the intentional Wave 2 graceful-reds: SKILL.md scaffold, archive-last, non-TTY approval, bulk summary).

## Task Commits

Each task was committed atomically:

1. **Task 1: GATE A + GATE B (verify-invariants.sh + audit-staged.sh)** — `dd37c64` (feat)
2. **Task 2: extract-invariants.sh + decision-scan.sh + check.sh drift fix** — `079a5c7` (feat)

## Files Created/Modified
- `templates/skills/restructure/gates/verify-invariants.sh` — GATE A normalized-substring invariant verifier (D-05/07/08).
- `templates/skills/restructure/gates/audit-staged.sh` — GATE B temp-dir conjure-audit shim + two-named-condition BLOCK (D-13/O-1).
- `templates/skills/restructure/gates/extract-invariants.sh` — D-06 signal-grep pre-pass → INVARIANTS.candidates under .conjure-adopt-state/ (T-23-08 chokepoint).
- `templates/skills/restructure/gates/decision-scan.sh` — D-11 archive guard, individual/bulk stdout signal.
- `scripts/check.sh` — drift manifest now only counts skill dirs that contain a SKILL.md (Rule 1 fix).

## Decisions Made
- **BLOCK keys on named conditions, not audit rc (O-1 / checker B1):** `conjure audit` returns rc=1 for unrelated harness-completeness WARNs (missing `.claudeignore`, `docs/`, `settings.json`) even on a perfectly clean CLAUDE.md in a minimal temp dir. Keying the gate on `rc>=1` would block every clean proposal and make criterion 5's clean-pass unsatisfiable. The shim runs verbatim to surface the human-readable output (faithful to RESTR-05 "run through conjure audit"); the two named greps (`^@`, line count vs `CLAUDE_MD_CAP`) are the authoritative, satisfiable block decision and stand alone as the fallback if the shim is absent.
- **Missing-list print preserves multi-word tokens:** the first draft used `printf '  - %s\n' $missing` which word-split `exit 2` into `exit`/`2`. Replaced with a newline-delimited `while read` so `exit 2` and `do not delete` print intact. The Wave 0 test only greps for "missing", but the intact list is the correct human signal (criterion 4).
- **extract-invariants state-dir contract:** the binding Wave 0 test passes a bare temp dir (`$P23_EX_TARGET`) and expects the candidates under `$P23_EX_TARGET/.conjure-adopt-state/`. So the helper nests `.conjure-adopt-state` when the passed dir doesn't already name one, and uses it as-is when it does (the plan's own AC form). The security guard refuses `..` traversal — the real T-23-08 attack vector — rather than the plan's literal `/tmp/not-adopt-state` example (which, after nesting, would resolve safely under a `.conjure-adopt-state` dir). The chokepoint invariant (write only under `.conjure-adopt-state`) is fully honored.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed scripts/check.sh drift over-enumeration of partial skill dirs**
- **Found during:** Task 2 full-suite verification.
- **Issue:** `scripts/check.sh:43` enumerated every `templates/skills/*/` directory and expected each to install a `SKILL.md`. The Wave-1 `restructure/` dir ships gate helpers but no `SKILL.md` yet (that lands in Wave 2). `conjure init` (which has no `restructure` in its skill loop yet) therefore did not install it, but `check` still expected `.claude/skills/restructure/SKILL.md` → classified it `removed` → drift → exit 1. This deterministically broke the DRIFT-01, DRIFT-02, and AUTPR-01 zero-drift assertions (which scaffold a harness then assert `check` reports no drift).
- **Fix:** `check.sh` now skips skill dirs lacking a `SKILL.md` (`[ -f "$skill_dir/SKILL.md" ] || continue`). A partial skill dir is not yet an installable skill and must not register as drift. This also future-proofs against any partial skill dir.
- **Files modified:** `scripts/check.sh`
- **Commit:** `079a5c7`
- **Verification:** DRIFT-01/02 + AUTPR-01 restored to green; suite 418 PASS / 4 FAIL (4 = Wave 2 graceful-reds). shellcheck-clean.

### Documented contract deviation (non-bug)

- **extract-invariants refusal AC:** the plan's acceptance criterion used `/tmp/not-adopt-state → exit 2` as the out-of-state-dir refusal example. Because the binding Wave 0 test requires a bare base dir to succeed (by nesting `.conjure-adopt-state`), the implemented guard refuses `..` traversal (the genuine T-23-08 escape) instead of a bare sibling dir. The chokepoint security property (write only under `.conjure-adopt-state`) is preserved; only the refusal trigger differs from the literal plan example. Verified: `..`-traversal state-dir → exit 2, no file written.

## Issues Encountered
- The full-suite DRIFT/AUTPR failures initially looked like flaky `fatal: not a git repository` noise (they intermittently appeared/disappeared depending on whether the suite was invoked once vs. multiple times in a chained command). Isolating with a single captured `$OUT` invocation showed the failure was deterministic and traced to `check.sh` (above), not a race. Fixed at the source.

## User Setup Required
None — no external service configuration. The helpers are pure bash + `grep`/`sed`/`tr`/`mktemp` (all verified present); `dependencies: {}` stays empty.

## Next Phase Readiness
- **Wave 2 (23-03)** can now create `templates/skills/restructure/SKILL.md` (orchestration prose, ≤200 lines, `allowed-tools: [Read, Bash]`), add `restructure` to the `init-project.sh` skill loop, and ship `gates/approve.sh` (per-class `/dev/tty` approval driver, non-TTY → exit 2, one RESTRUCTURE bulk-summary line per bucket). When `SKILL.md` lands, the `check.sh` skip guard stops applying to `restructure/` (it then has a SKILL.md and is correctly counted).
- The 4 gate helpers the skill invokes via Bash are shipped, fixture-verified, and shellcheck-clean.
- No blockers. Suite at 418 PASS / 4 FAIL where all 4 fails are intentional Wave 2 graceful-red guards; zero pre-Phase-23 regression.

## TDD Gate Compliance
This plan's tasks are `tdd="true"`, but the RED gate was satisfied in Wave 0 (23-01): the graceful-red gate-helper assertions in `tests/run.sh` are the failing tests that existed before these helpers. This wave is the GREEN gate — both task commits are `feat(...)` commits that turn those reds green (12 gate-helper assertions: 0 ✗). This matches the established Phase 22/23 Wave 0→1 test-first precedent. No separate per-task `test(...)` RED commit is expected because the RED already shipped in the prior wave.

## Self-Check: PASSED

All 4 gate helpers + the SUMMARY exist on disk; both task commits (`dd37c64`, `079a5c7`) are present in git history; `scripts/check.sh` carries the SKILL.md-presence guard. All four helpers are shellcheck-clean at error severity with zero `exit 1`; the 12 Wave 0 gate-helper assertions are green and DRIFT-01/02 + AUTPR-01 are restored (418 PASS / 4 FAIL, 4 = Wave 2 graceful-reds). No project files written by the helpers; extract-invariants confined to .conjure-adopt-state/.

---
*Phase: 23-restructure-skill-safety-gates*
*Completed: 2026-05-29*
