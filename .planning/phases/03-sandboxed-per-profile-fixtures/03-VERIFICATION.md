---
phase: 03-sandboxed-per-profile-fixtures
verified: 2026-05-25T12:00:00Z
status: passed
score: 15/15 must-haves verified
overrides_applied: 0
---

# Phase 3: Sandboxed Per-Profile Fixtures Verification Report

**Phase Goal:** As a Conjure developer, I want to run fixture audits in a sandboxed environment, so that test runs never read from or write to my real $HOME.
**Verified:** 2026-05-25
**Status:** passed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

All must-haves are derived from: ROADMAP.md Success Criteria (SC1-SC4) merged with PLAN frontmatter truths across plans 03-01, 03-02, and 03-03.

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | sandbox_setup() can be sourced and called to copy a fixture into an isolated temp dir | VERIFIED | `tests/lib/sandbox.sh` line 32-41; functional test: `source sandbox.sh && sandbox_setup tests/fixtures/ts-next` sets SANDBOX_DIR to a populated temp dir |
| 2 | SANDBOX_DIR is exported after sandbox_setup() with HOME/XDG_CONFIG_HOME/CLAUDE_CONFIG_DIR/PATH pointing into it | VERIFIED | Lines 37-40 of sandbox.sh; functional test confirmed all four exports equal SANDBOX_DIR; PATH first element is `$CONJURE_HOME/cli` |
| 3 | CONJURE_HOME is preserved (not overridden) by sandbox_setup() | VERIFIED | No `CONJURE_HOME=` assignment anywhere in sandbox.sh (grep confirmed); comment at line 27 explicitly documents this per D-05 |
| 4 | regen-fixtures.sh generates all 9 fixture seeds and calls conjure init --profile=<p> for each | VERIFIED | Line 99: `CONJURE_HOME="$CONJURE_HOME" "$CONJURE_HOME/cli/conjure" init --profile="$p" "$seed"`; all 9 profiles in PROFILES var at line 12 |
| 5 | regen-fixtures.sh accepts --profile <p> to regen a single profile | VERIFIED | Lines 16-27: `--profile` argument parsing with `PROFILE_FILTER` and loop guard at line 114 |
| 6 | regen-fixtures.sh prints [regen] <profile> for each fixture processed | VERIFIED | Lines 93, 106: `printf '[regen] %s\n' "$p"` and `printf '[regen] %s done\n' "$p"` |
| 7 | regen-fixtures.sh writes a seed CLAUDE.md with GENERATED header before calling conjure init | VERIFIED | `_write_seed_claude()` at lines 61-87; called at line 98 before init at line 99; first line writes `# GENERATED — do not edit directly; run scripts/regen-fixtures.sh` |
| 8 | monorepo seed includes packages/api/ subdirectory | VERIFIED | Lines 52-54: `if [ "$p" = "monorepo" ]; then mkdir -p "$seed/packages/api"; fi` |
| 9 | All 9 profile fixture directories exist under tests/fixtures/<profile>/ | VERIFIED | `ls tests/fixtures/` shows all 9 + _broken; `.claude/` dir confirmed for each |
| 10 | Each fixture's CLAUDE.md starts with the GENERATED header (D-12) | VERIFIED | `grep -l 'GENERATED' tests/fixtures/*/CLAUDE.md \| wc -l` = 9 |
| 11 | Each fixture audits green: bash scripts/audit-setup.sh exits 0 for all 9 profiles | VERIFIED | Full loop run: all 9 show GREEN; audit output for ts-next: PASS:17 WARN:0 FAIL:0 |
| 12 | tests/fixtures/_broken/ exists with a CLAUDE.md padded to 201+ lines | VERIFIED | `wc -l tests/fixtures/_broken/CLAUDE.md` = 205 |
| 13 | bash scripts/audit-setup.sh tests/fixtures/_broken exits with code 2 (ERR path) | VERIFIED | Confirmed exit code 2; audit output: `HARD CAP exceeded — trim`, PASS:16 FAIL:1 |
| 14 | tests/run.sh sources tests/lib/sandbox.sh and runs fixtures under sandbox isolation | VERIFIED | Line 8: `source "$CONJURE_HOME/tests/lib/sandbox.sh"`; fixture loop lines 248-260 call `sandbox_setup "$fx"` per iteration; audit invocation uses `$SANDBOX_DIR` |
| 15 | bash tests/run.sh exits 0 end-to-end with all fixture audit sections passing | VERIFIED | `bash tests/run.sh` exits 0 with PASS:136 FAIL:0; output contains `fixture audit green: ts-next` and `_broken: found expected finding: HARD CAP exceeded` |

**Score:** 15/15 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `tests/lib/sandbox.sh` | sandbox_setup() exposing SANDBOX_DIR | VERIFIED | Exists; no shebang (first line is comment); no `set -euo pipefail` at top; EXIT trap registered inside sandbox_setup() at line 35; all env exports confirmed |
| `scripts/regen-fixtures.sh` | Fixture regeneration for all 9 profiles | VERIFIED | Exists; executable; shebang line 1; set -euo pipefail line 7; dirname pattern line 9; _write_manifest, _write_seed_claude, regen_profile all defined; [regen] prefix; --profile flag; packages/api; ${FIXTURES_DIR:?} guard; printf throughout (zero echo calls) |
| `tests/fixtures/ts-next/CLAUDE.md` | ts-next profile fixture with GENERATED header | VERIFIED | 47 lines; contains GENERATED; audits green (PASS:17 WARN:0 FAIL:0) |
| `tests/fixtures/monorepo/packages/api` | monorepo subpackage dir | VERIFIED | Directory exists |
| `tests/fixtures/java-spring/.claude/settings.json` | node .mjs hook wiring (SAFE-03) | VERIFIED | `grep -c 'node.*\.mjs' settings.json` = 5 |
| `tests/fixtures/_broken/CLAUDE.md` | 201+ line CLAUDE.md triggering HARD CAP exceeded ERR | VERIFIED | 205 lines; no @imports; exits audit with code 2 |
| `tests/fixtures/_broken/EXPECT` | Declarative EXPECT pattern file | VERIFIED | Contains `HARD CAP exceeded`; comment and blank lines present; at least one non-comment pattern |
| `tests/fixtures/_broken/.claude` | Valid .claude/ dir so audit proceeds past early-exit guard | VERIFIED | settings.json exists; 5 .mjs hook files copied from ts-next |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `tests/lib/sandbox.sh` | `tests/run.sh` | source directive | WIRED | Line 8 of run.sh: `source "$CONJURE_HOME/tests/lib/sandbox.sh"` |
| `scripts/regen-fixtures.sh` | `cli/conjure` | conjure init --profile invocation | WIRED | Line 99: `"$CONJURE_HOME/cli/conjure" init --profile="$p" "$seed"` |
| `tests/run.sh fixture loop` | `scripts/audit-setup.sh` | bash invocation against $SANDBOX_DIR | WIRED | Line 252: `bash "$CONJURE_HOME/scripts/audit-setup.sh" "$SANDBOX_DIR" 2>&1"` |
| `tests/run.sh _broken section` | `tests/fixtures/_broken/EXPECT` | while IFS= read -r pattern loop | WIRED | Lines 274-282: reads EXPECT file, skips blank/comment lines, grep -qE per pattern |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| sandbox_setup() isolation: HOME overridden | `source tests/lib/sandbox.sh && sandbox_setup tests/fixtures/ts-next && [ "$HOME" = "$SANDBOX_DIR" ]` | PASS | PASS |
| All 9 fixtures audit green | `for p in ...; do bash scripts/audit-setup.sh tests/fixtures/$p; done` | All 9 GREEN, exit 0 | PASS |
| _broken fixture triggers ERR | `bash scripts/audit-setup.sh tests/fixtures/_broken; echo $?` | Exit code 2, "HARD CAP exceeded", FAIL:1 | PASS |
| Full test suite exits 0 | `bash tests/run.sh` | PASS:136 FAIL:0 | PASS |
| _broken specific finding asserted | `bash tests/run.sh 2>&1 \| grep 'found expected finding'` | `_broken: found expected finding: HARD CAP exceeded` | PASS |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| TEST-01 | 03-02, 03-03 | One committed example fixture per stack profile under `tests/fixtures/<profile>/` | SATISFIED | All 9 profile directories exist; each contains .claude/ + CLAUDE.md; audits green |
| TEST-02 | 03-01, 03-03 | Fixtures run sandboxed (isolated HOME/XDG_CONFIG_HOME/PATH, copied to a temp dir) with no leakage to real $HOME | SATISFIED | sandbox_setup() exports HOME/XDG_CONFIG_HOME/CLAUDE_CONFIG_DIR/PATH to SANDBOX_DIR; tests/run.sh calls sandbox_setup before each audit invocation |
| TEST-04 | 03-03 | At least one fixture intentionally fails audit, and assertions check specific findings | SATISFIED | _broken fixture (205 lines) exits audit with code 2; run.sh asserts non-zero exit AND greps for "HARD CAP exceeded" from EXPECT file |

Note: REQUIREMENTS.md traceability table still shows these as "Pending" — documentation was not updated after phase completion. This is a documentation artifact only; the implementations are complete and verified.

### Anti-Patterns Found

| File | Pattern | Severity | Impact |
|------|---------|----------|--------|
| None | — | — | — |

No TBD, FIXME, XXX, TODO, HACK, or PLACEHOLDER markers found in any phase-modified file. No stub return patterns. No hardcoded empty data. No `|| true` on audit capture lines (T-03-14 mitigated). No `echo` for manifest stubs (printf used throughout regen-fixtures.sh).

### Human Verification Required

None. All must-haves are verifiable programmatically and confirmed via direct execution.

---

_Verified: 2026-05-25_
_Verifier: Claude (gsd-verifier)_
