---
phase: 04-regression-suite-dry-run-proof
verified: 2026-05-25T00:00:00Z
status: human_needed
score: 5/5 must-haves verified
overrides_applied: 0
human_verification:
  - test: "Push to GitHub and confirm windows-hook-wiring CI job runs green on windows-latest runner"
    expected: "The windows-hook-wiring job completes successfully — Scaffold fixture step runs cli/conjure init, Assert node hook wiring step finds 'node' in settings.json, Assert no bash hook regression step does not find bash .claude/hooks in settings.json"
    why_human: "CI job runs on windows-latest; there is no way to run a Windows GitHub Actions runner locally. Static YAML analysis confirms the job is syntactically correct and structurally sound, but actual execution on the Windows runner requires a push to GitHub."
---

# Phase 4: Regression Suite & Dry-Run Proof — Verification Report

**Phase Goal:** As a Conjure maintainer, running `bash tests/run.sh` verifies every green fixture's audit output matches committed golden files, proves `--dry-run` leaves every fixture byte-identical, and detects three documented failure modes.
**Verified:** 2026-05-25
**Status:** human_needed
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | `bash tests/run.sh` exits 0 with FAIL: 0 | VERIFIED | Live run: `PASS: 175    FAIL: 0`; exit code 0 |
| 2 | Each of the 9 green profiles has a committed EXPECT file alongside its fixture | VERIFIED | `find tests/fixtures -name EXPECT` returns 10 (9 green + 1 _broken); content confirmed for all 9 |
| 3 | The EXPECT loop section iterates all 9 green fixtures and skips _broken | VERIFIED | Section at run.sh line 285; uses `[^_]*/` glob; live run shows 27 pass lines (9 fixtures x 3 patterns) |
| 4 | Dry-run snapshot section asserts diff -r exits 0 for all 9 green fixtures after conjure init --dry-run | VERIFIED | Section at run.sh line 305; live run shows 9 `dry-run snapshot identical` pass lines |
| 5 | Failure-mode section encodes FM-1 (size cap), FM-2 (hook exit 1), FM-3 (version mismatch) | VERIFIED | Section at run.sh line 323; live run shows 3 FM pass lines: size cap, hook exit 1, version mismatch |

**Score:** 5/5 truths verified

---

## Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `tests/fixtures/ts-next/EXPECT` | Golden file with 3 grep-E patterns | VERIFIED | Contains `PASS: [0-9]`, `WARN: 0`, `FAIL: 0` |
| `tests/fixtures/java-spring/EXPECT` | Golden file with 3 grep-E patterns | VERIFIED | Identical format; no absolute paths |
| `tests/fixtures/rust-axum/EXPECT` | Golden file with 3 grep-E patterns | VERIFIED | Identical format; no absolute paths |
| `tests/fixtures/go-gin/EXPECT` | Golden file with 3 grep-E patterns | VERIFIED | Identical format; no absolute paths |
| `tests/fixtures/python-fastapi/EXPECT` | Golden file with 3 grep-E patterns | VERIFIED | Identical format; no absolute paths |
| `tests/fixtures/node-nest/EXPECT` | Golden file with 3 grep-E patterns | VERIFIED | Identical format; no absolute paths |
| `tests/fixtures/monorepo/EXPECT` | Golden file with 3 grep-E patterns | VERIFIED | Identical format; no absolute paths |
| `tests/fixtures/polyglot/EXPECT` | Golden file with 3 grep-E patterns | VERIFIED | Identical format; no absolute paths |
| `tests/fixtures/data-science/EXPECT` | Golden file with 3 grep-E patterns | VERIFIED | Identical format; no absolute paths |
| `tests/run.sh` | EXPECT loop + dry-run + FM sections | VERIFIED | 3 new sections at lines 284, 305, 323; exits 0 |
| `scripts/regen-fixtures.sh` | `_write_expect` function + `--update-expect` flag | VERIFIED | Function at line 98; flag parsed at line 24; called in regen_profile (line 129) and standalone mode (line 142) |
| `.github/workflows/ci.yml` | `windows-hook-wiring` job | VERIFIED | Job at line 54; 4 `shell: bash` steps; all D-12 assertions present |

---

## Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `tests/run.sh` EXPECT loop | `tests/fixtures/<profile>/EXPECT` | `for fx` loop with `[^_]*/` glob, `expect_file="${fx}EXPECT"` | WIRED | Line 286-302; guard `[ ! -f "$expect_file" ] && continue` present |
| `tests/run.sh` EXPECT loop | `scripts/audit-setup.sh` | `AUDIT_OUT=$(bash audit-setup.sh $SANDBOX_DIR)`, then `grep -qE "$pattern"` | WIRED | Lines 292-301; output captured and each pattern checked |
| `tests/run.sh` dry-run section | `cli/conjure init --dry-run` | `CONJURE_HOME=$CONJURE_HOME cli/conjure init --dry-run $DRY_SNAP` | WIRED | Line 312; `|| true` handles non-zero exit |
| `tests/run.sh` dry-run section | `diff -r $DRY_SNAP $DRY_ORIG` | byte-identical comparison of two mktemp copies | WIRED | Line 313; failure path shows diagnostic diff at line 317 |
| `tests/run.sh` FM-3 | `cli/conjure update` | `CONJURE_HOME=$CONJURE_HOME cli/conjure update $FM_DIR` | WIRED | Line 355; double assertion `pinned to` AND `! Up to date` at lines 356-357 |
| `.github/workflows/ci.yml` windows job | `cli/conjure init /tmp/fixture` | `CONJURE_HOME="$GITHUB_WORKSPACE" cli/conjure init /tmp/fixture` | WIRED | Line 63; matches existing audit-on-fixture pattern |
| `.github/workflows/ci.yml` Assert step | `/tmp/fixture/.claude/settings.json` | `grep 'node' /tmp/fixture/.claude/settings.json` | WIRED | Line 71; negative assertion at lines 76-78 |
| `scripts/regen-fixtures.sh` `_write_expect` | `tests/fixtures/<profile>/EXPECT` | `printf` writes 6 lines to `$FIXTURES_DIR/$p/EXPECT` | WIRED | Lines 98-110; called at line 129 in `regen_profile` and line 142 in `--update-expect` path |

---

## Data-Flow Trace (Level 4)

The phase delivers test infrastructure (bash scripts, config files) rather than data-rendering components. Level 4 data-flow tracing applies to artifacts that render dynamic data from stores/APIs. These artifacts do not apply. All assertions are verified via behavioral spot-checks (Step 7b) instead.

---

## Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| `bash tests/run.sh` exits 0 with FAIL: 0 | `bash tests/run.sh 2>&1 \| tail -5` | `PASS: 175    FAIL: 0` | PASS |
| EXPECT loop fires for all 9 green fixtures | `bash tests/run.sh 2>&1 \| grep "Golden-file EXPECT loop" -A 30` | 27 pass lines (9 x 3 patterns) | PASS |
| Dry-run snapshot passes for all 9 fixtures | `bash tests/run.sh 2>&1 \| grep -c 'dry-run snapshot identical'` | `9` | PASS |
| FM-1 size cap detected | `bash tests/run.sh 2>&1 \| grep 'FM: size cap'` | `FM: size cap detected by audit` | PASS |
| FM-2 hook exit 1 detectable | `bash tests/run.sh 2>&1 \| grep 'FM: hook exit 1'` | `FM: hook exit 1 detectable via grep` | PASS |
| FM-3 version mismatch detected | `bash tests/run.sh 2>&1 \| grep 'FM: version mismatch'` | `FM: version mismatch detected by conjure update` | PASS |
| `--update-expect` flag regenerates EXPECT files | `bash scripts/regen-fixtures.sh --update-expect --profile ts-next` | `[regen] ts-next: wrote EXPECT`; exit 0 | PASS |

---

## Probe Execution

No probe scripts defined for this phase (`scripts/*/tests/probe-*.sh` not present). Step 7b behavioral spot-checks cover all runnable verification needs.

---

## Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| TEST-03 | 04-01-PLAN.md | `tests/run.sh` drives per-fixture audit assertions via golden-file EXPECT comparison | SATISFIED | EXPECT loop at run.sh line 285; 9 EXPECT files; 27 pass lines from live run |
| TEST-05 | 04-03-PLAN.md | Regression suite asserts `--dry-run` leaves fixture tree byte-identical | SATISFIED | Dry-run section at run.sh line 305; 9 pass lines from live run |
| TEST-06 | 04-02-PLAN.md | CI includes `windows-latest` leg validating `.mjs` hook wiring | SATISFIED (static) | Job at ci.yml line 54; YAML structurally correct; Windows CI execution requires human verification |
| TEST-07 | 04-03-PLAN.md | Documented failure modes have reproductions encoded as tests | SATISFIED | FM section at run.sh line 323; 3 pass lines from live run; D-07 scoping limits to CI-testable modes only |

**Note on TEST-06:** The ci.yml job is syntactically correct and structurally complete. "Satisfied" here means the artifact exists and is wired correctly. Actual runtime validation on the Windows runner requires a push to GitHub — see Human Verification section.

**Note on REQUIREMENTS.md status:** The requirements file still shows `[ ]` and "Pending" for TEST-03, TEST-05, TEST-06, TEST-07 at lines 22-26 and the traceability table. ROADMAP.md correctly marks Phase 4 as `[x]` complete. The requirements file was not updated to reflect completion. This is a documentation inconsistency (WARNING severity) — it does not block the phase goal since the actual implementations are verified, but REQUIREMENTS.md should be updated to `[x]` and "Complete" for all four TEST requirements.

---

## Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `.planning/REQUIREMENTS.md` | 22-26, 84-87 | TEST-03/05/06/07 still shows `[ ]` unchecked and "Pending" status | WARNING | Documentation inconsistency only — ROADMAP.md correctly marks phase complete; actual code is verified working |

No TBD, FIXME, or XXX markers found in any phase-modified files (`tests/run.sh`, `scripts/regen-fixtures.sh`, `.github/workflows/ci.yml`).

---

## Deviation from Plan: FM-1 Line Count (Auto-Fixed — Correct)

The plan specified `seq 1 105` (106 total lines, intended to exceed the "100-line hard cap"). The executor correctly identified that `audit-setup.sh` uses 200 as the HARD CAP threshold, not 100. The actual code uses `seq 1 205` (206 total lines). This deviation is **correct behavior** — the plan contained an error about the actual threshold, and the implementation matches the real code. Verified at `audit-setup.sh` lines 26-28: `≤100 = PASS`, `101-200 = WARN`, `>200 = ERR ("HARD CAP exceeded")`.

---

## Human Verification Required

### 1. Windows CI Job Runtime Validation

**Test:** Push to GitHub (or open a PR to main/develop) and observe the `windows-hook-wiring` CI job in the Actions tab.

**Expected:**
- The `Scaffold fixture` step completes without error: `cli/conjure init /tmp/fixture` runs successfully via Git Bash on the Windows runner.
- The `Assert node hook wiring in settings.json` step outputs a match for `node` in `/tmp/fixture/.claude/settings.json`.
- The `Assert no bash hook regression` step completes without printing the FAIL message (no `bash .claude/hooks` lines found).
- The overall `windows-hook-wiring` job shows a green checkmark.

**Why human:** GitHub Actions `windows-latest` runners cannot be executed locally. Static analysis confirms the YAML is syntactically valid (`shell: bash` on all 4 steps, correct `CONJURE_HOME` pattern, correct grep assertions), but runtime behavior on Windows — particularly whether Git Bash resolves `cli/conjure` correctly, whether `/tmp/fixture` is writable, and whether `grep 'node'` finds the expected hook wiring — requires an actual Windows runner invocation.

---

## Gaps Summary

No implementation gaps found. All 5 observable truths are verified by live test execution. The one identified issue (REQUIREMENTS.md not updated to reflect completion) is a documentation WARNING that does not affect the phase goal.

---

_Verified: 2026-05-25_
_Verifier: Claude (gsd-verifier)_
