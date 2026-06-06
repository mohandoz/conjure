---
status: partial
phase: 31-deferred-debt-test-harness-hardening
source: [31-VERIFICATION.md]
started: 2026-06-04T19:30:00Z
updated: 2026-06-04T19:30:00Z
---

## Current Test

[awaiting human testing]

## Tests

### 1. UAT-01 live execution — claude binary smoke

expected: Run `CONJURE_LIVE_TEST=1 bash tests/run.sh` on a machine with `claude` installed → `✓ live: claude plugin validate accepts scaffolded .claude-plugin/ (UAT-01)`
result: [pending]

### 2. UAT-02 live execution — promptfoo enforcement wiring

expected: Run `CONJURE_LIVE_TEST=1 ANTHROPIC_API_KEY=<key> bash tests/run.sh` → `✓ live: promptfoo enforcement-wiring verified — hook-gated eval passes, broken-hook eval fails (UAT-02)`. Also validates provider `anthropic:messages:claude-3-5-haiku-20241022` under promptfoo 0.121.14.
result: [pending]

### 3. Accept success criterion 3 deviation (WR-02)

expected: WR-02 review fix gates UAT-02 on BOTH `CONJURE_LIVE_TEST=1` AND `ANTHROPIC_API_KEY` (key alone now skips — prevents accidental billable API calls; documented in tests/MANUAL-UAT.md). Contradicts ROADMAP criterion 3 literal wording ("key alone executes"). Accept or reject deviation; to accept, update `overrides:` in 31-VERIFICATION.md frontmatter.
result: [pending]

## Summary

total: 3
passed: 0
issues: 0
pending: 3
skipped: 0
blocked: 0

## Gaps
