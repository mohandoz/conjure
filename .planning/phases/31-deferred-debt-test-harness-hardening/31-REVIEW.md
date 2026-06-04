---
phase: 31-deferred-debt-test-harness-hardening
reviewed: 2026-06-04T00:00:00Z
depth: standard
files_reviewed: 6
files_reviewed_list:
  - scripts/preflight.sh
  - scripts/audit-setup.sh
  - tests/lib/sandbox.sh
  - tests/run.sh
  - tests/MANUAL-UAT.md
  - FAILURE-MODES.md
findings:
  critical: 1
  warning: 4
  info: 3
  total: 8
status: issues_found
---

# Phase 31: Code Review Report

**Reviewed:** 2026-06-04
**Depth:** standard
**Files Reviewed:** 6
**Status:** issues_found

## Summary

This phase paid down deferred debt and hardened the test harness: a `skip()`/`SKIP`
counter with a `CONJURE_STRICT` gate, a sweep replacing raw `$(mktemp -d)` with a
validating `mk_tmpd()` helper, a `CONJURE_SCHEMA_FILE` env override in
`audit-setup.sh` (kill-safe replacement for the live-file swap), preflight exit-code
correction (1 → 2), self-inspection regression gates (DEBT-04/05, UAT-01/02), and a
new `▸ Live-system tests` section plus a `MANUAL-UAT.md` checklist.

The `mktemp → mk_tmpd` sweep, the preflight exit-code fix, and the `CONJURE_SCHEMA_FILE`
override are correct and well-motivated. However the new `mk_tmpd()` helper does **not**
deliver the fail-closed guarantee it documents, and the new live-system UAT-02 block
has a provider/credential mismatch that makes it unable to pass and a gating
inconsistency versus its own documentation. Details below.

## Critical Issues

### CR-01: UAT-02 live promptfoo probe uses an OpenAI provider with a Claude model — cannot pass, and is gated on the wrong credential

**File:** `tests/run.sh:6851-6896`
**Issue:** The UAT-02 block is entered when `ANTHROPIC_API_KEY` is non-empty
(`if [ -n "${ANTHROPIC_API_KEY:-}" ]`, line 6852), but both generated promptfoo
configs declare the provider as `openai:chat:claude-3-haiku-20240307`
(lines 6858, 6871). promptfoo's `openai:chat:*` provider authenticates with
`OPENAI_API_KEY` and targets the OpenAI API — `claude-3-haiku-20240307` is not a
valid OpenAI model. As written, the baseline run (`UAT02_BASELINE_RC`) will fail
the moment the block executes with only `ANTHROPIC_API_KEY` set, tripping the
`elif [ "$UAT02_BASELINE_RC" -ne 0 ]` branch and emitting a hard `fail` (line 6893).
Because the block is gated on `ANTHROPIC_API_KEY` alone (not `CONJURE_LIVE_TEST`),
any developer/CI run that merely has `ANTHROPIC_API_KEY` exported — a very common
condition — will start a billable `npx promptfoo eval` network call and then report
a spurious suite failure. This is a correctness + false-failure defect in a gate
that is supposed to *prove* enforcement wiring.

Additionally, the provider/credential mismatch means the "enforcement-wiring
verified" pass can never be reached via the Anthropic key the block keys off.

**Fix:** Use the Anthropic provider so the declared credential matches, and gate on
`CONJURE_LIVE_TEST` (consistent with UAT-01 and with `MANUAL-UAT.md`):
```bash
# UAT-02: gate on CONJURE_LIVE_TEST=1 AND ANTHROPIC_API_KEY (per MANUAL-UAT.md Notes)
if [ "${CONJURE_LIVE_TEST:-0}" = "1" ] && [ -n "${ANTHROPIC_API_KEY:-}" ]; then
  ...
  cat > "$UAT02_DIR/promptfooconfig.yaml" << 'PFEOF'
providers:
  - anthropic:messages:claude-3-haiku-20240307
...
PFEOF
  ...
elif [ "${CONJURE_LIVE_TEST:-0}" = "1" ]; then
  skip "live promptfoo eval: ANTHROPIC_API_KEY not set (UAT-02)"
else
  skip "live promptfoo eval: CONJURE_LIVE_TEST not set (UAT-02)"
fi
```
Verify the exact promptfoo provider id against the pinned promptfoo version
(`anthropic:messages:<model>` is the current form).

## Warnings

### WR-01: `mk_tmpd()`'s `exit 2` does not propagate out of command substitution — fail-closed guarantee is not delivered

**File:** `tests/lib/sandbox.sh:47-55` (and every call site, e.g. `:61`, `tests/run.sh:45`, `…:6832`, `…:6853`)
**Issue:** Every call to `mk_tmpd` is in a command substitution
(`SANDBOX_DIR="$(mk_tmpd)"`, `stub="$(mk_tmpd)"`, etc.). The helper's `exit 2` on
failure runs *inside the `$(...)` subshell only* — it terminates the subshell, not
the parent script. `tests/run.sh` runs under `set -uo pipefail` (no `set -e`), and
no call site checks the substitution's exit status, so on a real `mktemp -d` failure
the assignment silently becomes the empty string and the script continues. The very
next operations then run against a bad path (`cp -r "$fixture/." "$SANDBOX_DIR/"`
→ `cp ... /`, `trap 'rm -rf "$SANDBOX_DIR"'` → `rm -rf ""`, etc.). This is the exact
"non-existent path" failure mode DEBT-03/T-31-01 set out to close, and the helper's
own docstring ("Exits 2 if mktemp fails or returns a non-existent directory") is
therefore false in practice.

Reproduced: a stubbed-failure `mk_tmpd` captured via `X="$(mk_tmpd)"` prints `FATAL`
to stderr but the parent reaches the next line with `X=""` and exits 0.

**Fix:** Either guard each call site, or (preferred, central) keep the validation but
make the failure abort the parent. One option is to validate in the caller after
capture:
```bash
SANDBOX_DIR="$(mktemp -d)"
if [ -z "$SANDBOX_DIR" ] || [ ! -d "$SANDBOX_DIR" ]; then
  printf 'FATAL: mktemp -d failed\n' >&2; exit 2
fi
```
Or have `mk_tmpd` signal failure via return status and require callers to check:
`d="$(mk_tmpd)" || exit 2`. At minimum, fix the docstring to stop claiming a
guarantee the call pattern cannot honor.

### WR-02: UAT-02 lacks `CONJURE_LIVE_TEST` gate, contradicting its own documentation

**File:** `tests/run.sh:6851-6852` vs `tests/MANUAL-UAT.md:259-268`
**Issue:** `MANUAL-UAT.md` instructs operators to run automated live gates with
`CONJURE_LIVE_TEST=1 ... ANTHROPIC_API_KEY=<key> bash tests/run.sh` and states the
automated gates "cover UAT-01 … and UAT-02". UAT-01 honors `CONJURE_LIVE_TEST`
(line 6831) but UAT-02 ignores it and triggers on `ANTHROPIC_API_KEY` alone. The
documented opt-in contract is thus not enforced for half the live suite, and a key
present for unrelated reasons silently activates a network/billing path. (Same root
gating issue called out in CR-01; tracked separately because it is a
doc/behavior-contract divergence independent of the provider bug.)
**Fix:** Add the `CONJURE_LIVE_TEST=1` conjunct to the UAT-02 guard as shown in
CR-01, so both live blocks share one opt-in switch.

### WR-03: Live-test failures become hard suite FAILs even outside strict mode (flaky-by-network)

**File:** `tests/run.sh:6839-6843`, `6890-6896`
**Issue:** The live UAT blocks emit `fail` (not `skip`) on any non-zero result once
entered. These calls are real network/CLI invocations (`claude plugin validate`,
`npx promptfoo eval`) subject to transient outages, rate limits, version drift, and
cost. With CR-01/WR-02 unfixed they will fail deterministically; even after fixing
those, a transient network error turns the whole suite red (`[ "$FAIL" -eq 0 ]` at
EOF). Live, externally-dependent assertions should distinguish "wiring is broken"
(fail) from "environment unavailable / transient" (skip), or be quarantined behind
strict mode.
**Fix:** Treat unreachable-service / non-deterministic transport errors as `skip`
(or only `fail` under `CONJURE_STRICT=1`), reserving `fail` for a definitive
wiring contradiction (baseline-pass + broken-fail both observed but inverted).

### WR-04: `# shellcheck disable=SC2091` on the `claude plugin validate` line is the wrong directive

**File:** `tests/run.sh:6837`
**Issue:** SC2091 warns about running the *output* of `$(...)` as a command. The
line it precedes — `( cd "$UAT01_DIR" && claude plugin validate . )` — contains no
command substitution being executed, so the suppression is inert and misleading; it
signals a misunderstanding of what was being silenced and may mask a future, real
SC finding on that line.
**Fix:** Remove the `# shellcheck disable=SC2091` directive (the line needs no
suppression), or replace it with the directive that actually applies if shellcheck
flags something specific.

## Info

### IN-01: Convention gate regex only catches the canonical `$(mktemp -d)` spelling

**File:** `tests/run.sh:140-143`
**Issue:** The "no raw mktemp -d" gate greps `\$[(]mktemp -d[)]`. Alternate spellings
that bypass the helper — backticked `` `mktemp -d` ``, `mktemp --directory`, or
`mktemp -d -t ...` — would not be flagged, so the convention can silently erode.
**Fix:** Broaden to e.g. `grep -rnE 'mktemp[[:space:]]+(-d|--directory)' tests/
--include='*.sh' --exclude='sandbox.sh'` (and allow the helper's own line).

### IN-02: `mk_tmpd` docstring overstates the guarantee

**File:** `tests/lib/sandbox.sh:44-46`
**Issue:** "Exits 2 if mktemp fails…" reads as a whole-program guarantee but, per
WR-01, only holds when `mk_tmpd` is invoked outside command substitution — which it
never is. Update the comment once WR-01 is resolved so the contract matches reality.
**Fix:** Reword to describe actual behavior (e.g. "fails the subshell; callers must
check the captured value or invoke via `d=$(mk_tmpd) || exit 2`").

### IN-03: Stale-schema test no longer needs its removed backup var — confirm no orphaned cleanup

**File:** `tests/run.sh` SCHM-STALE block (around `:5153-5167` post-change)
**Issue:** The migration to `CONJURE_SCHEMA_FILE` correctly drops the
`P27_STALE_SCHEMA_BAK` swap/restore (kill-safe improvement). This is a positive
change; flagged only as a note to confirm no other block still references the
removed backup variable or the old in-place `cp "$P27_SCHEMA_FILE"` swap (a grep for
`P27_STALE_SCHEMA_BAK` should return nothing). `P27_SCHEMA_FILE` itself remains
legitimately used for the schema-shape assertions (`:4866-4882`) and is not orphaned.
**Fix:** None required; verification note only.

---

_Reviewed: 2026-06-04_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
