---
status: resolved
phase: 22-conjure-adopt-cli-core-rollback
source: [22-VERIFICATION.md]
started: 2026-05-29T00:00:00Z
updated: 2026-05-29T00:00:00Z
---

## Current Test

[complete — verified via PTY automation]

## Tests

### 1. Interactive TTY recovery prompt (`[r]/[c]/[s]`)
expected: Run `conjure adopt` in a real terminal, `kill -9` it mid-run, then re-run interactively. `recovery_prompt()` reads from `/dev/tty` and presents `[r]ollback / [c]ontinue / [s]tart-fresh`. `r` restores from snapshot, `c` resumes reusing the existing snapshot, `s` discards state and snapshots anew; empty/unknown input re-prompts (no default).
result: PASS (2026-05-29) — driven through a real PTY via `expect`. All three branches confirmed: [r] rollback (byte-identical CLAUDE.md restore, [ROLLBACK] logged, state dropped, SAFE-06 warning), [c] resume reusing snapshot (no 2nd backup), [s] start-fresh completes; bad/empty input re-prompts with no default (D-14). 11/11 assertions passed. Note: a SIGKILL in the snapshot_path-flush window makes [r] refuse-closed (safe) — see VERIFICATION known_limitation.

## Summary

total: 1
passed: 1
issues: 0
pending: 0
skipped: 0
blocked: 0

## Gaps
