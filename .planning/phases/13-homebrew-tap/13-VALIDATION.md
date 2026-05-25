---
phase: 13
slug: homebrew-tap
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-05-26
---

# Phase 13 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Hand-rolled bash test runner |
| **Config file** | none |
| **Quick run command** | `bash tests/run.sh` |
| **Full suite command** | `bash tests/run.sh` |
| **Estimated runtime** | ~15 seconds |

---

## Sampling Rate

- **After every task commit:** Run `bash tests/run.sh`
- **After every plan wave:** Run `bash tests/run.sh`
- **Before `/gsd-verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------------|-----------|-------------------|-------------|--------|
| 13-01-T1 | 13-01 | 1 | BREW-01 | Formula/conjure.rb has valid Ruby syntax | unit (static) | `bash tests/run.sh` (ruby -c check) | Formula/conjure.rb | ✅ green |
| 13-01-T1b | 13-01 | 1 | BREW-03 | Formula has no HEAD or branch reference | static grep | `bash tests/run.sh` (BREW-03 block) | Formula/conjure.rb | ✅ green |
| 13-01-T2 | 13-01 | 1 | BREW-02 | CONJURE_HOME env var overrides default resolution | unit | `bash tests/run.sh` (BREW-02 block) | cli/conjure | ✅ green |
| 13-02-T1 | 13-02 | 2 | BREW-04 | release.yml references bump-homebrew-formula-action | static grep | `bash tests/run.sh` (BREW-04 block) | .github/workflows/release.yml | ✅ green |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [x] BREW test block in `tests/run.sh` — all 4 automated assertions (created in Plan 13-03 Wave 3)
- [x] `Formula/conjure.rb` — must exist for ruby -c and BREW-03 tests to pass (created in Plan 13-01 Wave 1)
- [x] `cli/conjure` D-03 conditional — must be applied for BREW-02 test to pass (Plan 13-01 Wave 1)

*No separate test infrastructure needed — all tests inline in `tests/run.sh` following established pattern.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| `brew install mohandoz/conjure/conjure` succeeds; `conjure --version` exits 0 | BREW-01 | Requires a real brew installation, a published tag, and the tap repo to exist with a valid sha256 | 1. Create mohandoz/homebrew-conjure repo on GitHub with Formula/conjure.rb inside a Formula/ subdirectory. 2. Tag and push v0.3.0. 3. Let bump action update sha256. 4. Run: `brew tap mohandoz/conjure && brew install mohandoz/conjure/conjure && conjure --version` |
| CONJURE_HOME resolves to $(brew --prefix)/share/conjure/ automatically | BREW-02 | Requires actual brew-installed binary in Cellar | After brew install: run `conjure version` — output must include the Cellar path |
| bump-homebrew-formula-action fires and pushes updated formula to tap repo | BREW-04 | Requires real GitHub release event to trigger | Push a new tag (e.g., v0.3.1); verify that mohandoz/homebrew-conjure/Formula/conjure.rb sha256 is updated within ~2 minutes |

---

## Pre-release Checklist

- [ ] Create `mohandoz/homebrew-conjure` repo on GitHub with `Formula/conjure.rb` inside a `Formula/` subdirectory (copy from this repo's `Formula/conjure.rb`)
- [ ] Create a GitHub PAT with `repo` and `workflow` scopes; add it as repository secret `HOMEBREW_TAP_GITHUB_TOKEN` in `mohandoz/conjure` settings
- [ ] Tag and push `v0.3.0` to trigger the first release
- [ ] Verify the bump action updates the sha256 in `mohandoz/homebrew-conjure/Formula/conjure.rb`
- [ ] Run `brew tap mohandoz/conjure && brew install mohandoz/conjure/conjure && conjure --version` to confirm BREW-01

---

## Validation Sign-Off

- [x] All tasks have automated verify assertions in `tests/run.sh`
- [x] Sampling continuity: all tasks covered
- [x] Wave 0 covers all BREW requirements
- [x] No watch-mode flags
- [x] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter (pending human sign-off)

The automated BREW assertions in `tests/run.sh` (ruby -c, env override, static greps)
provide regression coverage. The manual pre-release checklist covers the full
end-to-end distribution path.

**Approval:** pending
