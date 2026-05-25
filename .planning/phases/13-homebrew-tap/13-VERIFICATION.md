---
phase: 13-homebrew-tap
verified: 2026-05-26T00:00:00Z
status: human_needed
score: 3/4 must-haves verified (SC-1 requires human)
overrides_applied: 0
human_verification:
  - test: "Install Conjure via Homebrew"
    expected: "`brew install mohandoz/conjure/conjure` succeeds, `conjure --version` exits 0 with version output"
    why_human: "Requires real brew installation, mohandoz/homebrew-conjure tap repo to exist with valid sha256 (currently PLACEHOLDER), and a published tagged release"
  - test: "Automatic CONJURE_HOME resolution after brew install"
    expected: "After brew install, running `conjure version` with no env vars set prints a path under $(brew --prefix)/share/conjure/"
    why_human: "Requires actual Homebrew Cellar installation; the wrapper-injects-CONJURE_HOME path is code-verified but the end-to-end behavior needs a real brew-installed binary"
  - test: "bump-homebrew-formula-action fires on real tag push"
    expected: "After pushing a v* tag, mohandoz/homebrew-conjure/Formula/conjure.rb sha256 updates within ~2 minutes"
    why_human: "Requires a real GitHub release event; COMMITTER_TOKEN secret and mohandoz/homebrew-conjure repo must be created (pre-release checklist items)"
---

# Phase 13: Homebrew Tap — Verification Report

**Phase Goal:** macOS and Linux developers can install Conjure with `brew install mohandoz/conjure/conjure` and receive automatic SHA updates on every release
**Verified:** 2026-05-26
**Status:** human_needed
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths (from ROADMAP.md Success Criteria)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| SC-1 | `brew install mohandoz/conjure/conjure` succeeds and `conjure --version` exits 0 with greppable version output | ? UNCERTAIN (human) | Formula exists with valid Ruby syntax and correct structure. sha256 is PLACEHOLDER — actual install blocked until tap repo exists and a tagged release is published. The automated proxy (ruby -c) passes; end-to-end install untestable programmatically. |
| SC-2 | `CONJURE_HOME` resolves automatically to `$(brew --prefix)/share/conjure/` without manual env var | VERIFIED (automated partial, human for full) | Formula wrapper injects `export CONJURE_HOME="#{share}/conjure"` before exec. cli/conjure line 24 is the conditional form `${CONJURE_HOME:-...}` so external value wins. BREW-02 test proves override works at `bash tests/run.sh` (265 PASS, 0 FAIL). Full path (no manual env) needs actual brew install. |
| SC-3 | Homebrew formula references a tagged tarball URL + SHA256 (never a branch HEAD reference) | VERIFIED | `Formula/conjure.rb` url points to `refs/tags/v0.3.0.tar.gz`. `grep -qE '\bHEAD\b|\bbranch\b' Formula/conjure.rb` — no match. BREW-03 test in test suite passes. |
| SC-4 | Publishing a new GitHub release automatically triggers `mislav/bump-homebrew-formula-action@v3` to update SHA256 in `mohandoz/homebrew-conjure` | VERIFIED (code-level) | `.github/workflows/release.yml` contains the bump step at line 44; uses `homebrew-tap: mohandoz/homebrew-conjure` (not `tap-repo:`); `download-url` references `${{ github.ref_name }}`; env injects `COMMITTER_TOKEN: ${{ secrets.HOMEBREW_TAP_GITHUB_TOKEN }}`. Live trigger requires real GitHub release — documented as manual. |

**Score:** 3/4 truths fully verified (SC-1 blocked on human/live test; SC-2 code-level verified, full end-to-end human; SC-4 code-level verified, live trigger human)

---

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `Formula/conjure.rb` | Homebrew formula template | VERIFIED | Exists, 22 lines, passes `ruby -c`. Contains `(share/"conjure").install`, heredoc wrapper with `CONJURE_HOME` export, `test do` block. No HEAD or branch reference. |
| `cli/conjure` (line 24) | Conditional CONJURE_HOME assignment | VERIFIED | Line 24: `CONJURE_HOME="${CONJURE_HOME:-$(cd "$(dirname "$0")/.." && pwd)}"`. Conditional form confirmed. |
| `.github/workflows/release.yml` | Release workflow with bump step | VERIFIED | File exists, YAML valid. Bump step appended after "Create release". All required fields present. |
| `tests/run.sh` (BREW block) | Four BREW regression assertions | VERIFIED | Lines 1248-1282. All four assertions present and passing. Suite: 265 PASS, 0 FAIL. |
| `.planning/phases/13-homebrew-tap/13-VALIDATION.md` | Phase validation contract | VERIFIED | Exists with correct 7-key frontmatter (phase: 13, slug: homebrew-tap). 10 occurrences of `BREW-0`. Manual-only table covers BREW-01 install and BREW-04 live tap push. Pre-release checklist present. |

---

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `Formula/conjure.rb` bin wrapper | `share/conjure/cli/conjure` | `exec "#{share}/conjure/cli/conjure" "$@"` | WIRED | Line 15 of formula: `exec "#{share}/conjure/cli/conjure" "$@"`. Pattern match confirmed. |
| `cli/conjure` | `$CONJURE_HOME/VERSION` | `cat "$CONJURE_HOME/VERSION"` | WIRED | Line 25: `CONJURE_VERSION="$(cat "$CONJURE_HOME/VERSION" 2>/dev/null || echo unknown)"`. Reads VERSION from conditional CONJURE_HOME. |
| `.github/workflows/release.yml` "Create release" step | `bump-homebrew-formula-action@v3` | Step ordering — bump fires after `softprops/action-gh-release@v2` | WIRED | Bump step at line 43 is after the Create release step (lines 36-41). Step sequence confirmed. |
| `bump-homebrew-formula-action` | `mohandoz/homebrew-conjure` Formula | `COMMITTER_TOKEN` secret with repo write scope | WIRED (code) | `homebrew-tap: mohandoz/homebrew-conjure` at line 47; `COMMITTER_TOKEN: ${{ secrets.HOMEBREW_TAP_GITHUB_TOKEN }}` at line 50. Tap repo itself must be created (pre-release checklist). |
| `tests/run.sh` BREW-02 test | `cli/conjure` line 24 | `CONJURE_HOME` env var override | WIRED | Test at line 1263 sets `CONJURE_HOME="$BREW_FAKE"` and calls `cli/conjure version`; verifies `9.8.7` output. D-03 conditional is the prerequisite — confirmed applied. |
| `tests/run.sh` BREW-03 test | `Formula/conjure.rb` | static grep for HEAD/branch | WIRED | Test at line 1272 greps `$CONJURE_HOME/Formula/conjure.rb`. |

---

### Data-Flow Trace (Level 4)

Not applicable — this phase produces CLI tooling, a formula file, a workflow file, and test additions. There are no components rendering dynamic data from a store or API.

---

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Formula/conjure.rb passes Ruby syntax check | `ruby -c Formula/conjure.rb` | `Syntax OK` | PASS |
| All four BREW assertions pass in test suite | `bash tests/run.sh 2>&1 \| tail -10` | `PASS: 265  FAIL: 0`, all four BREW lines show checkmarks | PASS |
| release.yml is valid YAML | `python3 -c "import yaml; yaml.safe_load(open(...))"` | exits 0 | PASS |
| Formula has no HEAD or branch reference | `grep -qE '\bHEAD\b|\bbranch\b' Formula/conjure.rb` | no match | PASS |
| bump step uses correct input name `homebrew-tap` (not `tap-repo`) | `grep 'homebrew-tap: mohandoz/homebrew-conjure' release.yml` | matches line 47 | PASS |
| Wrong input name `tap-repo` is absent | `grep -c 'tap-repo' release.yml` | 0 | PASS |
| CONJURE_HOME conditional form in cli/conjure | `grep -c 'CONJURE_HOME="${CONJURE_HOME:-' cli/conjure` | 1 | PASS |

---

### Probe Execution

No `scripts/*/tests/probe-*.sh` declared or applicable for this phase.

---

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|---------|
| BREW-01 | 13-01, 13-03 | User can install Conjure with `brew install mohandoz/conjure/conjure`; `conjure --version` exits 0 | PARTIALLY SATISFIED (automated proxy passing; full install is human/live) | `ruby -c Formula/conjure.rb` passes; BREW-01 test in run.sh passes; end-to-end install blocked on tap repo + live tag |
| BREW-02 | 13-01, 13-03 | `CONJURE_HOME` resolves automatically to Homebrew share path without manual env var | SATISFIED (code level) | Formula wrapper injects CONJURE_HOME; cli/conjure conditional form confirmed; BREW-02 test proves override behavior; full end-to-end requires human test |
| BREW-03 | 13-01, 13-03 | Formula pinned to tagged tarball URL + SHA256, never branch HEAD | SATISFIED | `refs/tags/v0.3.0.tar.gz` in url field; no HEAD/branch in file; BREW-03 grep test passes |
| BREW-04 | 13-02, 13-03 | `mislav/bump-homebrew-formula-action@v3` fires on every GitHub release to auto-update SHA256 | SATISFIED (code level) | Bump step present in release.yml with correct inputs; live trigger requires real release event (human) |

All four BREW requirement IDs (BREW-01 through BREW-04) declared in plan frontmatter are accounted for. No REQUIREMENTS.md-assigned BREW IDs are orphaned — all four appear in the Traceability table under Phase 13.

---

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `Formula/conjure.rb` | 5 | `sha256 "PLACEHOLDER_SHA256_REPLACE_ON_FIRST_RELEASE"` | INFO (intentional) | Not a stub — this is the correct design per D-02 and RESEARCH.md. The bump action replaces this value on first release. Homebrew will fail `brew install` until replaced, which is expected and documented. |

No `TBD`, `FIXME`, or `XXX` markers found in any phase-modified file (`Formula/conjure.rb`, `cli/conjure`, `.github/workflows/release.yml`, `tests/run.sh`).

No empty return stubs, hardcoded empty collections, or console-log-only implementations found.

---

### Human Verification Required

#### 1. Full brew install end-to-end

**Test:** Create `mohandoz/homebrew-conjure` repo with `Formula/conjure.rb` in a `Formula/` subdirectory. Add `HOMEBREW_TAP_GITHUB_TOKEN` PAT secret to conjure repo. Tag and push `v0.3.0`. After the bump action updates sha256, run:
```
brew tap mohandoz/conjure && brew install mohandoz/conjure/conjure && conjure --version
```
**Expected:** `brew install` succeeds. `conjure --version` exits 0 and prints a version string containing the release number.
**Why human:** Requires a live Homebrew environment, a real published GitHub tag, the tap repo to exist, and the sha256 placeholder to be replaced by the bump action. Cannot simulate with static file checks.

#### 2. Automatic CONJURE_HOME resolution (no manual env var)

**Test:** After the brew install above, in a clean shell (no CONJURE_HOME in env), run:
```
env -i HOME="$HOME" PATH="$PATH" conjure version
```
**Expected:** Output includes a path containing `share/conjure` (the Cellar path). No error about missing VERSION file.
**Why human:** The formula wrapper hard-codes `CONJURE_HOME` at install time via Ruby interpolation. Confirming the wrapper is actually installed and the path is correct requires the Cellar to exist.

#### 3. Live bump-homebrew-formula-action trigger

**Test:** Push a new tag (e.g., `v0.3.1`) to the conjure repo. Wait ~2 minutes and check `mohandoz/homebrew-conjure/Formula/conjure.rb`.
**Expected:** The `sha256` field in the tap repo formula is updated to the real SHA256 of the v0.3.1 tarball within ~2 minutes of the tag push.
**Why human:** Requires a real GitHub Actions runner, a real tag event, and the `HOMEBREW_TAP_GITHUB_TOKEN` secret configured with write access to the tap repo.

---

### Gaps Summary

No code-level gaps found. All four BREW artifacts exist, are substantive, and are correctly wired:

- `Formula/conjure.rb` — correct install layout using `(share/"conjure").install`, correct wrapper heredoc, no HEAD/branch reference, valid Ruby syntax
- `cli/conjure` line 24 — conditional CONJURE_HOME form confirmed
- `.github/workflows/release.yml` — bump step present with all correct inputs (homebrew-tap not tap-repo, COMMITTER_TOKEN, github.ref_name)
- `tests/run.sh` — BREW block with all four assertions, passing cleanly (265 PASS, 0 FAIL)
- `13-VALIDATION.md` — complete validation contract with manual-only table and pre-release checklist

The phase is blocked on human verification for the full end-to-end `brew install` path (SC-1) which requires the external `mohandoz/homebrew-conjure` tap repo to exist with a real sha256, and a published tagged release. This is a pre-release infrastructure dependency, not a code defect — all mechanical code deliverables for the phase goal are in place.

The `nyquist_compliant: false` and `wave_0_complete: false` frontmatter values in `13-VALIDATION.md` are intentional — the document marks these as pending human sign-off, which is the correct state prior to the pre-release checklist being executed.

---

_Verified: 2026-05-26_
_Verifier: Claude (gsd-verifier)_
