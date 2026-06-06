---
phase: 31-deferred-debt-test-harness-hardening
fixed_at: 2026-06-04T00:00:00Z
review_path: .planning/phases/31-deferred-debt-test-harness-hardening/31-REVIEW.md
iteration: 1
findings_in_scope: 5
fixed: 5
skipped: 0
status: all_fixed
---

# Phase 31: Code Review Fix Report

**Fixed at:** 2026-06-04
**Source review:** .planning/phases/31-deferred-debt-test-harness-hardening/31-REVIEW.md
**Iteration:** 1

**Summary:**
- Findings in scope: 5 (CR-01, WR-01, WR-02, WR-03, WR-04)
- Fixed: 5
- Skipped: 0

Info findings (IN-01, IN-02, IN-03) were out of scope (`fix_scope: critical_warning`).
Note: IN-02 (mk_tmpd docstring overstating the guarantee) was incidentally
corrected as part of the WR-01 fix — the rewritten docstring now describes the
actual fail-closed mechanism.

## Fixed Issues

### WR-01: `mk_tmpd()`'s `exit 2` does not propagate out of command substitution

**Files modified:** `tests/lib/sandbox.sh`
**Commit:** 8065c5d
**Applied fix:** Captured the test-runner PID once at source time
(`MK_TMPD_MAIN_PID="$$"`). On `mktemp -d` failure, `mk_tmpd` now signals that PID
with `kill -TERM` before `exit 2`. Because every call site invokes the helper as
`VAR="$(mk_tmpd)"`, a bare `exit 2` previously only killed the `$(...)` subshell
and let the parent continue with `VAR=""`. The SIGTERM propagates to the parent
script (run under `set -uo pipefail`, no TERM trap), aborting the whole suite —
delivering the documented fail-closed guarantee without touching the ~180 call
sites. The docstring was rewritten to describe this actual mechanism (also
resolving IN-02). POSIX bash 3.2 compatible; passes `bash -n` and the project
shellcheck gate.
**Note:** This is a behavioral/logic change to the failure path — flagged for
human verification that the SIGTERM-on-failure semantics are acceptable for the
harness.

### WR-04: `# shellcheck disable=SC2091` on the `claude plugin validate` line is the wrong directive

**Files modified:** `tests/run.sh`
**Commit:** e2d245f
**Applied fix:** Removed the inert `# shellcheck disable=SC2091` directive
preceding `( cd "$UAT01_DIR" && claude plugin validate . )`. The line contains no
executed command substitution, so the suppression was misleading and could mask a
future real finding. shellcheck `-S error` still passes with no new findings on
that line.

### WR-03: Live-test failures become hard suite FAILs even outside strict mode (UAT-01 portion)

**Files modified:** `tests/run.sh`
**Commit:** e2d245f
**Applied fix:** The UAT-01 `claude plugin validate` failure branch now emits
`skip` instead of `fail`. A non-zero rc on a known-good scaffold is most plausibly
transient (CLI version drift, network), not a wiring defect. Under
`CONJURE_STRICT=1`, `skip()` already escalates to `fail`, preserving a hard gate
for operators who opt in.

### CR-01: UAT-02 live promptfoo probe uses an OpenAI provider with a Claude model

**Files modified:** `tests/run.sh`
**Commit:** b5bf898
**Applied fix:** Both generated promptfoo configs now declare the provider as
`anthropic:messages:claude-3-5-haiku-20241022`, so the provider authenticates with
the `ANTHROPIC_API_KEY` the block keys off (the previous `openai:chat:*` provider
targeted the OpenAI API and would reject the Claude model id). The
provider/credential mismatch that made the "enforcement-wiring verified" pass
unreachable is resolved.
**Note:** The exact promptfoo provider id (`anthropic:messages:<model>`) and model
slug should be confirmed against the pinned promptfoo version (0.121.14) during
live UAT — flagged for human verification since it is only exercised under the live
gate.

### WR-02: UAT-02 lacks `CONJURE_LIVE_TEST` gate, contradicting its own documentation

**Files modified:** `tests/run.sh`
**Commit:** b5bf898
**Applied fix:** The UAT-02 guard is now
`[ "${CONJURE_LIVE_TEST:-0}" = "1" ] && [ -n "${ANTHROPIC_API_KEY:-}" ]`, matching
`MANUAL-UAT.md` and the UAT-01 gate. Distinct `skip` messages are emitted for the
`ANTHROPIC_API_KEY`-missing and `CONJURE_LIVE_TEST`-missing cases. A bare
`ANTHROPIC_API_KEY` export no longer silently triggers a billable network path.
The UAT-02 baseline-failure branch was also converted from `fail` to `skip` as the
UAT-02 portion of WR-03 (transient/network errors no longer redden the suite;
baseline-pass-with-broken-hook-not-failing remains a hard `fail` for a genuine
wiring contradiction).

## Skipped Issues

None — all in-scope findings were fixed.

---

_Fixed: 2026-06-04_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
