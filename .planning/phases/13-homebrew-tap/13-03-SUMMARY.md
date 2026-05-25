---
plan: 13-03
phase: 13-homebrew-tap
status: complete
started: 2026-05-26
completed: 2026-05-26
commits:
  - 5f87136
  - 6fc22ed
requirements-satisfied:
  - BREW-01
  - BREW-02
  - BREW-03
  - BREW-04
key-files:
  modified:
    - tests/run.sh
  created:
    - .planning/phases/13-homebrew-tap/13-VALIDATION.md
deviations: none
self-check: PASSED
---

## Summary

Added the BREW regression test block to `tests/run.sh` and created
`13-VALIDATION.md`. All four automated BREW assertions pass. Total suite:
265 PASS, 0 FAIL.

## What Was Built

**`tests/run.sh`** (BREW block appended before Summary, 36 lines):
- BREW-01: `ruby -c Formula/conjure.rb` syntax check
- BREW-02: CONJURE_HOME env override unit test — mktemp fake dir, trap EXIT
  cleanup, `printf '9.8.7\n' > VERSION`, verify `cli/conjure version` prints `9.8.7`
- BREW-03: `grep -qE '\bHEAD\b|\bbranch\b'` — absent in formula
- BREW-04: `grep -q 'bump-homebrew-formula-action'` — present in release.yml

**`13-VALIDATION.md`** (new):
- Phase 12 9-column schema
- All 4 tasks marked ✅ green (Wave 0 satisfied)
- Manual-only table: brew install (BREW-01) and live tap push (BREW-04)
- Pre-release checklist: tap repo, PAT secret, first tag

## Verification

1. `bash tests/run.sh 2>&1 | tail -3` → `PASS: 265  FAIL: 0`
2. `bash tests/run.sh 2>&1 | grep -c 'BREW-0'` → 4 pass lines
3. `grep -c 'BREW homebrew tests' tests/run.sh` → 1
4. `grep 'bump-homebrew-formula-action' tests/run.sh` → matches
5. `grep 'CONJURE_HOME.*cli/conjure version' tests/run.sh` → matches
6. `grep -c 'BREW-0' 13-VALIDATION.md` → 10

## Deviations

None. All tasks executed as specified.
