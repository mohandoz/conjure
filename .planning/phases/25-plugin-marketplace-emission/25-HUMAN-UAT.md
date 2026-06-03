---
status: partial
phase: 25-plugin-marketplace-emission
source: [25-VERIFICATION.md]
started: 2026-06-03
updated: 2026-06-03
---

## Current Test

[awaiting human testing]

## Tests

### 1. `conjure publish-plugin --validate` with the `claude` CLI installed
expected: On a valid conjure-scaffolded harness, `conjure publish-plugin --validate` calls `claude plugin validate .`, the validation passes, and the command exits 0 with the validator output visible. (The absent-`claude` path — exit 2 when no binary — is already covered by automated test PLUG-04-absent; only the success path needs a real `claude` binary.)
result: [pending]

## Summary

total: 1
passed: 0
issues: 0
pending: 1
skipped: 0
blocked: 0

## Gaps
