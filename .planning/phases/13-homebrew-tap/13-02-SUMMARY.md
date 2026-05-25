---
plan: 13-02
phase: 13-homebrew-tap
status: complete
started: 2026-05-26
completed: 2026-05-26
commit: e0836ba
requirements-satisfied:
  - BREW-04
key-files:
  modified:
    - .github/workflows/release.yml
deviations: none
self-check: PASSED
---

## Summary

Appended the `mislav/bump-homebrew-formula-action@v3` step to the `release`
job in `.github/workflows/release.yml`, immediately after the existing
"Create release" step.

## What Was Built

**`.github/workflows/release.yml`** (1 step added):
- Step name: "Bump Homebrew formula"
- Uses `homebrew-tap: mohandoz/homebrew-conjure` (not `tap-repo:` — critical)
- `download-url` references `${{ github.ref_name }}` for tagged tarball URL
- `env.COMMITTER_TOKEN` injects `secrets.HOMEBREW_TAP_GITHUB_TOKEN`
- No new permissions entry needed — existing `contents: write` is sufficient
- YAML remains valid; existing steps unchanged

On every `v*` tag push, the action fetches the tarball, computes SHA256, and
pushes an updated `Formula/conjure.rb` to `mohandoz/homebrew-conjure`.

## Verification

1. `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/release.yml'))"` → passes
2. `grep -c 'bump-homebrew-formula-action'` → 1
3. `grep 'homebrew-tap: mohandoz/homebrew-conjure'` → matches
4. `grep 'HOMEBREW_TAP_GITHUB_TOKEN'` → matches
5. `grep 'github.ref_name'` → matches in download-url
6. `grep -c 'tap-repo'` → 0 (wrong input name absent)

## Deviations

None. Task executed as specified. Pre-release prerequisites (tap repo creation,
PAT secret) documented in 13-VALIDATION.md (Plan 13-03).
