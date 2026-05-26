---
phase: 15-release-pipeline
verified: 2026-05-26T00:00:00Z
status: human_needed
score: 5/5 must-haves verified (all require live tag push for full confirmation)
overrides_applied: 0
human_verification:
  - test: "Push a version tag and verify ci-gate blocks release if CI is red"
    expected: "ci-gate job queries check-runs API, finds failing check, exits non-zero, release job is skipped"
    why_human: "Requires a real GitHub Actions tag push with a deliberately failing CI check; not simulatable locally"
  - test: "Push a version tag with green CI and verify all artifacts publish"
    expected: "Docker image appears at ghcr.io/mohandoz/conjure:v<tag> and ghcr.io/mohandoz/conjure:latest; mohandoz/homebrew-conjure formula is bumped; marketplace.json version matches tag"
    why_human: "Requires real GITHUB_TOKEN with packages: write, HOMEBREW_TAP_GITHUB_TOKEN secret, and mohandoz/homebrew-conjure tap repo"
---

# Phase 15: Release Pipeline — Verification Report

**Phase Goal:** A single `release.yml` workflow gates all distribution artifacts behind green CI and fires Homebrew bump, Docker build, and marketplace version check on every version tag push
**Verified:** 2026-05-26
**Status:** human_needed (code verified; all items require live tag push for full confirmation)
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths (Static Verification)

**REL-02: ci-gate job exists and blocks release**
```bash
grep -c 'ci-gate' .github/workflows/release.yml  # → 2 PASS
grep -c 'needs: \[ci-gate\]' .github/workflows/release.yml  # → 1 PASS
grep -c 'check-runs' .github/workflows/release.yml  # → 1 PASS
grep -c 'failure.*timed_out.*cancelled.*action_required' .github/workflows/release.yml  # → 1 PASS
```
Status: **PASS (code-verified; live gate test human-needed)**

**REL-01: release job fires all three distribution targets**
```bash
grep -c 'Marketplace version check' .github/workflows/release.yml  # → 1 PASS
grep -c 'push: true' .github/workflows/release.yml                  # → 1 PASS
grep -c 'ghcr.io/mohandoz/conjure' .github/workflows/release.yml   # → 2 PASS
grep -c 'bump-homebrew-formula-action' .github/workflows/release.yml  # → 1 PASS
```
Status: **PASS (code-verified; live publish human-needed)**

**DOCK-03: Docker push to ghcr.io with semver + latest**
```bash
python3 -c "
import yaml
w = yaml.safe_load(open('.github/workflows/release.yml'))
bp = next(s for s in w['jobs']['release']['steps'] if 'build-push-action' in s.get('uses',''))
assert bp['with']['push'] == True
assert 'linux/amd64,linux/arm64' in bp['with']['platforms']
tags = bp['with']['tags']
assert 'ghcr.io/mohandoz/conjure' in tags
assert 'latest' in tags
print('PASS')
"
```
Status: **PASS (code-verified; live image publish human-needed)**

**Release job permissions include packages: write**
```bash
python3 -c "
import yaml
w = yaml.safe_load(open('.github/workflows/release.yml'))
perms = w['jobs']['release']['permissions']
assert perms['packages'] == 'write'
assert perms['contents'] == 'write'
print('PASS')
"
```
Status: **PASS**

**Step order (fail-fast before publishing)**
```bash
python3 -c "
import yaml
w = yaml.safe_load(open('.github/workflows/release.yml'))
steps = w['jobs']['release']['steps']
names = [s.get('name','') for s in steps]
marketplace_idx = names.index('Marketplace version check')
changelog_idx = names.index('Extract CHANGELOG entry')
create_idx = names.index('Create release')
brew_idx = names.index('Bump Homebrew formula')
assert marketplace_idx < changelog_idx < create_idx < brew_idx
print('PASS: step order correct')
"
```
Status: **PASS**

---

## Human-Needed Verifications

1. **REL-02 gate (live):** Push a tag to a branch with a failing CI check. Verify ci-gate job fails and release job is skipped.

2. **REL-01 + DOCK-03 (live):** Push a valid version tag (e.g., `v0.4.0`) with green CI. Verify:
   - `ghcr.io/mohandoz/conjure:v0.4.0` and `ghcr.io/mohandoz/conjure:latest` appear on ghcr.io
   - `mohandoz/homebrew-conjure` formula sha256 is updated by bump-homebrew-formula-action
   - marketplace.json version field matches tag

3. **Secrets pre-flight:**
   - `HOMEBREW_TAP_GITHUB_TOKEN` must be set in repo secrets before first tag push
   - `mohandoz/homebrew-conjure` tap repo must exist

---

## Requirements Coverage

| Requirement | Source Plan | Status | Evidence |
|-------------|-------------|--------|----------|
| REL-01 | 15-01 | human_needed | All three distribution targets present in release.yml; live tag push needed |
| REL-02 | 15-01 | human_needed | ci-gate job with check-runs API verified; live gate test needed |
| DOCK-03 | 15-01 | human_needed | push: true + ghcr.io tags in release.yml; live publish needed |

---

## Tech Debt

- Docker push failure silently skips Homebrew bump (both in same sequential `release` job). A transient GHCR outage blocks Homebrew bump with no independent retry path. Mitigation deferred to v0.4.x — can split into separate jobs with `needs:` dependencies.
- No preflight check for `HOMEBREW_TAP_GITHUB_TOKEN` secret existence before the Homebrew bump step. If absent, the step fails with a cryptic error. Low priority since it requires one-time secret setup.
