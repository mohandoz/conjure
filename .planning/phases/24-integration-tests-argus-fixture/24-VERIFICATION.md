---
phase: 24-integration-tests-argus-fixture
verified: 2026-05-29T00:00:00Z
status: passed
score: 5/5 must-haves verified
overrides_applied: 0
re_verification: # not applicable — initial verification
  previous_status: null
---

# Phase 24: Integration Tests + Argus Fixture Verification Report

**Phase Goal:** The complete `conjure adopt` + restructure-skill pipeline is verified end-to-end against a representative brownfield fixture, with CI assertions on all safety invariants and performance bounds.
**Verified:** 2026-05-29
**Status:** passed
**Re-verification:** No — initial verification

## Goal Achievement

This is a **verification phase**: it adds a 500-file brownfield fixture generator and the `▸ Phase 24` E2E test block (5 sections, C1–C5) that drive the SHIPPED Phases 21–23 pipeline and assert all five ROADMAP success criteria. The phase goal is "the pipeline is verified end-to-end with CI assertions" — so the goal is achieved iff each of the 5 criteria maps to a real, green assertion exercised against the real fixture (not a stub, not a SUMMARY claim). The verifier ran the full suite independently and confirmed PASS 447 / FAIL 0 (exit 0), with 18 green `✓ argus` assertions and zero `✗` lines anywhere in the run.

### Observable Truths (= the 5 ROADMAP Success Criteria)

| # | Truth | Status | Evidence |
| --- | ----- | ------ | -------- |
| 1 | `conjure adopt --dry-run` on the 500-file argus fixture completes <30s AND writes zero files to the fixture dir | ✓ VERIFIED | run.sh:3300-3335. Independent run: `✓ ...completed in 6s (< 30s)`, `✓ no adopt-manifest.json under target`, `✓ no .conjure-adopt-state under target`. Real assertions: `date +%s` delta `< 30`; `find -name adopt-manifest.json \| wc -l == 0`; `find -name .conjure-adopt-state \| wc -l == 0`. |
| 2 | Live adopt then `--rollback` → zero diff before/after (sha256 every file) | ✓ VERIFIED | run.sh:3337-3391. `✓ every pre-adopt file sha256 == recorded before-hash`, `✓ [ROLLBACK] entry in RESTRUCTURE-LOG.md`, `✓ diff -r pre-adopt vs post-rollback empty (excl. D-03 dirs)`. Per-file `p22_sha` recorded into a hash file OUTSIDE both trees; mismatch count asserted == 0; `diff -r` with the 5 D-03 excludes asserted empty. |
| 3 | Idempotent re-run: second adopt makes zero mutations + reports "nothing to scaffold" | ✓ VERIFIED | run.sh:3393-3442. `✓ re-run reports 'Scaffolded: 0 layer files'`, `✓ state.json .created\|length == 0`, `✓ diff -r run1-after vs run2-after empty — zero mutations`, `✓ re-run emits literal 'nothing to scaffold'`. State cleared between runs (the :2896 idiom) so run-2 is a clean idempotent scaffold; the literal phrase is the Plan 01 O-1 `report()` deviation. |
| 4 | SIGKILL after snapshot before scaffold → re-run triggers partial-state recovery; rollback restores cleanly | ✓ VERIFIED | run.sh:3444-3539. `✓ kill landed in window (current_step=snapshot)`, `✓ non-TTY re-run exits 2`, `✓ re-run prints 'last completed:'`, `✓ re-run lists --rollback/--resume/--start-fresh`, `✓ CONJURE_ADOPT_ROLLBACK=1 re-run → diff -r vs PRE empty`. Real background-launch + `current_step` bounded-poll + `kill -9` in a 3-attempt anti-flake relaunch loop; the interactive `[r]/[c]/[s]` prompt of the SAME unchanged `recovery_prompt()` code path was PTY-verified upstream (Phase 22: 11/11; Phase 23: 13/13) — see Human Verification note below. |
| 5 | Symlink fixture file skipped by inventory; proposed CLAUDE.md with @import blocked by pre-write audit gate, never written | ✓ VERIFIED | run.sh:3541-3580. `✓ docs/linked.md absent from manifest files[] — inventory skipped it`, `✓ audit-staged.sh on staged @import CLAUDE.md → exit 2 BLOCK`, `✓ target CLAUDE.md never gained an ^@ line — @import never written`. `jq -e select` on the symlink path asserted non-matching; `audit-staged.sh` exit asserted == 2 (independently reproduced: rc=2); target CLAUDE.md `grep -q '^@'` asserted absent. |

**Score:** 5/5 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
| -------- | -------- | ------ | ------- |
| `tests/fixtures/_brownfield-argus/generate-argus.sh` | 500-file brownfield generator (bulk .md + real `ln -s` + oversized CLAUDE.md + @import seed) | ✓ VERIFIED | 88 lines; `set -uo pipefail`; `exit 2` usage guard (lines 28-31) + fail-loud `mkdir` guard (37-44); 120-line CLAUDE.md body (53); 255 doc + 250 gen .md loops (62-76); genuine `ln -sf real.md docs/linked.md` (81); `@import` seed (84). Independent run: 509 .md, real symlink present, exit 0. |
| `scripts/adopt.sh` `report()` O-1 deviation | additive "nothing to scaffold" on zero-scaffold run | ✓ VERIFIED | Line 239: `[ "${created_count:-0}" -eq 0 ] && echo "  Scaffolded:  nothing to scaffold"`. Count line (238) preserved. `git show 66d19ff --numstat`: exactly **1 insertion, 0 deletions**. Reviewed CLEAN in 24-REVIEW.md. |
| `tests/run.sh` `▸ Phase 24` block | 5 criterion sections behind a `P24_ARGUS_OK` guard, after :3280 | ✓ VERIFIED | Block at lines 3283-3584; preamble + `P24_ARGUS_GEN`/`P24_ARGUS_OK` guard (3296-3298); 5 sections (C1@3301, C2@3338, C3@3394, C4@3445, C5@3542); "End Phase 24 test block" banner @3583 before gh-stub cleanup @3587. |

### Key Link Verification

| From | To | Via | Status | Details |
| ---- | -- | --- | ------ | ------- |
| `▸ Phase 24` block | `generate-argus.sh` | `P24_ARGUS_GEN` presence guard + `bash "$P24_ARGUS_GEN" "$target"` per section | ✓ WIRED | `P24_ARGUS_OK` set from `[ -f "$P24_ARGUS_GEN" ]` (3298); each section invokes the generator (3308/3349/3402/3461/3549). |
| `▸ Phase 24` block | `scripts/adopt.sh` | `DRY_RUN`/`CONJURE_ADOPT_ROLLBACK` env-var invocation of `$P22_ADOPT_SH` | ✓ WIRED | Reuses in-scope `P22_ADOPT_SH` (run.sh:2372) + `p22_sha` (2388); drives the shipped pipeline at 3311/3357/3404/3467/3551. |
| C4 SIGKILL section | `state.json .current_step` | bounded poll on `current_step ∈ {snapshot,inventory}` before `kill -9` | ✓ WIRED | `jq -r '.current_step'` poll (3473), `case ... snapshot\|inventory) break` (3475/3482). Independent run observed `current_step=snapshot` in-window. |
| C5 @import sub-check | `audit-staged.sh` | run shipped gate on staged @import CLAUDE.md, assert exit 2 | ✓ WIRED | Gate exists at `templates/skills/restructure/gates/audit-staged.sh`; invoked at 3564; rc asserted == 2 (independently reproduced rc=2). |

### Data-Flow Trace (Level 4)

Not applicable in the rendering sense — this phase produces no UI/dynamic-data component. The "data" under test is the live pipeline output (manifest, state.json, sha256 hashes, report stdout), and every assertion consumes real generated/runtime values: the 509-file fixture is materialized at test time, `p22_sha` hashes real files, `jq` reads the real `state.json`, and the report phrase is grepped from real `adopt.sh` stdout. No hardcoded/empty stand-ins. The Plan 01 O-1 report phrase flows from `created_count == 0` (sourced from `jq -r '.created | length'`) → the additive echo → the C3 `grep -qi 'nothing to scaffold'` assertion. Flow confirmed FLOWING.

### Behavioral Spot-Checks (run independently by the verifier)

| Behavior | Command | Result | Status |
| -------- | ------- | ------ | ------ |
| Full suite green | `bash tests/run.sh` | PASS 447 / FAIL 0, exit 0, 0 `✗` lines | ✓ PASS |
| Phase 24 assertions | `grep -c '✓ argus'` on run output | 18 green, 0 `✗ argus` | ✓ PASS |
| shellcheck CI gate | `shellcheck -S error -e SC2164,SC2044,SC2034,SC2155 tests/run.sh generate-argus.sh adopt.sh` | rc 0 | ✓ PASS |
| `exit 1` project lock | `grep -v '^#' <file> \| grep -c 'exit 1'` | generator 0, adopt.sh 0 | ✓ PASS |
| Generator fail-loud (CR-01 fix) | `TF=$(mktemp); bash generate-argus.sh "$TF"` | rc=2, single clean stderr line (no flood) | ✓ PASS |
| Generator idempotent re-run (WR-01 fix) | run generator twice into same dir | run2 rc=0, 0 stderr bytes, symlink intact, 509 .md | ✓ PASS |
| audit-staged @import block | `bash audit-staged.sh <staged @import CLAUDE.md>` | rc=2 | ✓ PASS |
| O-1 minimality | `git show 66d19ff --numstat -- scripts/adopt.sh` | 1 insertion, 0 deletions | ✓ PASS |

### Probe Execution

No conventional `scripts/*/tests/probe-*.sh` probes exist in this repo; the project's runnable check is the full `bash tests/run.sh` suite, which the verifier executed (PASS 447 / FAIL 0, exit 0). No `MISSING_PROBE`.

### Requirements Coverage

Per ROADMAP and 24-CONTEXT: **Requirements: None** — this is a verification phase; all 23 v0.6.0 requirements map to Phases 21–23. No `requirements:` IDs in either plan's frontmatter (both `requirements: []`). No orphaned REQ IDs mapped to Phase 24 in REQUIREMENTS.md. Nothing to flag.

### Code Review Closure (24-REVIEW.md → 24-REVIEW-FIX.md)

| Finding | Severity | Disposition | Confirmed in codebase |
| ------- | -------- | ----------- | --------------------- |
| CR-01: bad target exits 0 instead of 2 | Critical | Fixed (commit 7fd0fc8) | generate-argus.sh:37-44 fail-loud `mkdir` guard + writable-dir assertion, both `exit 2`. Spot-checked: rc=2 on a regular-file target. |
| WR-01: re-run `ln: File exists` swallowed | Warning | Fixed (commit 7fd0fc8) | generate-argus.sh:81 now `ln -sf`. Spot-checked: re-run rc=0, 0 stderr bytes, symlink intact. |
| IN-01: stale 505/255 count comment | Info | Fixed (commit 7fd0fc8) | generate-argus.sh:59-61 comment now reads 256 docs / 250 gen / 509 .md total — matches actual `find`. |
| IN-02: header provenance note | Info | Accepted (no code change) | CR-01 fix makes the "honors the project lock" claim fully true; reviewer's own Fix note said no change required. |
| report() O-1 deviation | (reviewed) | CLEAN | adopt.sh:239 additive echo, count line preserved, +1/-0 diff, fires only when `created_count == 0`. |

Commit 7fd0fc8 verified present in `git log`. Full suite stayed green after the fixes.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
| ---- | ---- | ------- | -------- | ------ |
| (none) | — | No `TBD`/`FIXME`/`XXX`/`TODO`/`HACK`/`PLACEHOLDER` in any modified file (generator, report() region, P24 block) | — | None |

No stubs, no empty implementations, no hardcoded-empty data flowing to assertions, no debt markers. The `_brownfield-argus` fixture dir is correctly `_`-prefixed and excluded from all three generic `tests/fixtures/[^_]*/` sweep loops (run.sh:326/368/390) — the naming lock from 24-CONTEXT is honored. Only the generator script is committed (no bulk .md / symlink committed — repo-lean as designed).

### Human Verification Required

**None for this phase.** The only human-gated sub-check in scope is criterion 4's interactive `[r]/[c]/[s]` recovery prompt, which:

1. Exercises the SAME `recovery_prompt()` `/dev/tty` code path (scripts/adopt.sh:367-380) that was already **PTY-verified via `expect`** upstream — Phase 22 (`22-VERIFICATION.md`: "11/11 assertions passed across all three branches"; `[r]` zero-diff restore, `[c]` resume without re-snapshot, `[s]` start-fresh, empty/unknown re-prompts D-14) and Phase 23 (`23-VERIFICATION.md`: 13/13).
2. Is **unchanged by Phase 24** — this phase modifies no product code except the additive `report()` echo (which does not touch the recovery path).
3. Has its automatable half (non-TTY exit-2 + the three recovery flags + the explicit `CONJURE_ADOPT_ROLLBACK=1` auto-rollback zero-diff) fully automated and GREEN in the C4 section, independently confirmed by the verifier.

Because the interactive prompt is already manually verified upstream on the identical unchanged code path, and the Phase 24 automated C4 path is green, no new human verification item is raised. Status is `passed` rather than `human_needed`. (A `# NOTE:` at run.sh:3447-3454 correctly documents the interactive prompt as manual-only.)

### Gaps Summary

No gaps. All five ROADMAP success criteria map to real, green assertions exercised end-to-end against the materialized 500-file `_brownfield-argus` fixture; the full suite is PASS 447 / FAIL 0 (independently run, exit 0); shellcheck is clean (rc 0) with zero `exit 1`; the 1 Critical + 1 Warning + 2 Info code-review findings are resolved/accepted (commit 7fd0fc8 present, fixes spot-checked); the O-1 `report()` deviation is the minimal +1-line additive change and was reviewed CLEAN. The phase goal — the complete pipeline verified end-to-end with CI assertions on all safety invariants and the performance bound — is achieved in the codebase.

---

_Verified: 2026-05-29_
_Verifier: Claude (gsd-verifier)_
