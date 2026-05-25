---
status: partial
phase: 13-homebrew-tap
source: [13-VERIFICATION.md]
started: 2026-05-26
updated: 2026-05-26
---

## Current Test

[awaiting human testing]

## Tests

### 1. Full brew install
expected: `brew tap mohandoz/conjure && brew install mohandoz/conjure/conjure && conjure --version` exits 0 with greppable version output
result: [pending]

### 2. Automatic CONJURE_HOME resolution
expected: In a clean shell with no env vars, `conjure version` output shows the Cellar path (confirming formula wrapper injected CONJURE_HOME)
result: [pending]

### 3. Live bump-action trigger
expected: Pushing a new tag causes `mohandoz/homebrew-conjure/Formula/conjure.rb` sha256 to update within ~2 minutes via the bump action
result: [pending]

## Summary

total: 3
passed: 0
issues: 0
pending: 3
skipped: 0
blocked: 0

## Gaps
