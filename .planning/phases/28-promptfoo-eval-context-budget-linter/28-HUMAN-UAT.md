---
status: partial
phase: 28-promptfoo-eval-context-budget-linter
source: [28-VERIFICATION.md]
started: 2026-06-03
updated: 2026-06-03
---

## Current Test

[awaiting human testing — requires live promptfoo + ANTHROPIC_API_KEY]

## Tests

### 1. EVAL-03 enforcement-not-disposition behavioral check
expected: In a test repo: `conjure eval init && conjure eval --emit-workflow`, then deliberately break a hook binary (e.g. make a PreToolUse hook exit 2 unconditionally), set ANTHROPIC_API_KEY, run `conjure eval run` (Node ≥20.20 / ≥22.22). The promptfoo eval suite must FAIL — confirming the emitted PR-gate workflow would block merges on harness regressions. (The structural half — workflow wiring with promptfoo-action, fail-on-threshold:80, repeat:3/repeat-min-pass:2, path filters — is already auto-verified.)
result: [pending]

## Summary

total: 1
passed: 0
issues: 0
pending: 1
skipped: 0
blocked: 0

## Gaps
