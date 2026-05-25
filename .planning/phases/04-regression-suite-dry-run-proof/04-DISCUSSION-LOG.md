# Phase 4: Regression Suite & Dry-Run Proof - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-25
**Phase:** 4-Regression Suite & Dry-Run Proof
**Areas discussed:** EXPECT scope for green fixtures, Dry-run byte-identical strategy, Failure-mode test selection, Windows CI leg design

---

## EXPECT Scope for Green Fixtures

| Option | Description | Selected |
|--------|-------------|----------|
| Positive-pass patterns | Each green fixture has EXPECT with specific positive patterns like 'PASS:' or '0 errors'. Tests fail if those strings disappear — detects silent regressions. | ✓ |
| Exit-code only | Keep green fixtures as-is (exit 0 = pass). Only _broken/ needs EXPECT. Simpler but doesn't catch output drift. | |

**User's choice:** Positive-pass patterns

| Option | Description | Selected |
|--------|-------------|----------|
| Regex patterns that avoid paths | EXPECT files use grep-E patterns matching semantic content (e.g. 'PASS:.*CLAUDE.md' not full paths). Same format as _broken/EXPECT. | ✓ |
| Normalize output before comparison | Pipe audit output through sed to strip sandbox paths before grepping. More robust but adds complexity. | |
| You decide | Claude picks the normalization approach. | |

**User's choice:** Regex patterns that avoid paths

| Option | Description | Selected |
|--------|-------------|----------|
| Committed alongside fixtures | EXPECT files live in tests/fixtures/<profile>/EXPECT, committed. scripts/regen-fixtures.sh can regenerate them. Golden-file drift = test failure. | ✓ |
| Generated at test time | First run creates baseline; subsequent runs diff against it. Risk: baseline created from broken state. | |

**User's choice:** Committed alongside fixtures

---

## Dry-Run Byte-Identical Strategy

| Option | Description | Selected |
|--------|-------------|----------|
| diff -r snapshot before/after | cp fixture to snapshot dir, run conjure init --dry-run against it, diff -r snapshot original. Any mutation = test failure. | ✓ |
| sha256sum file manifest | Hash every file before and after dry-run. Detects content changes but not deletions/creations without extra work. | |
| find + stat manifest | Record find output + file sizes before and after. Catches new/deleted files but not content mutations. | |

**User's choice:** diff -r before/after

| Option | Description | Selected |
|--------|-------------|----------|
| All 9 green fixtures | Run dry-run snapshot assertion on every profile fixture. Stronger coverage. | ✓ |
| One representative fixture | Pick ts-next as canonical dry-run test. Faster but misses profile-specific mutation paths. | |
| You decide | Claude picks based on test time vs coverage tradeoff. | |

**User's choice:** All 9 green fixtures

| Option | Description | Selected |
|--------|-------------|----------|
| Run against existing fixture (tests re-init idempotence) | Sandbox copy of each fixture, run dry-run init against it. Proves re-running init --dry-run mutates nothing. | ✓ |
| Run against fresh seed (manifest stub only) | Strip .claude/ from copy, run dry-run init. Less representative of real use. | |
| Both | Run against both existing fixture and stripped seed. Double coverage but more test time. | |

**User's choice:** Run against existing fixture

---

## Failure-Mode Test Selection

| Option | Description | Selected |
|--------|-------------|----------|
| Only Conjure-auditable modes | Focus on modes conjure audit can detect: size cap, wrong exit code, version mismatch. Skip runtime/infra modes. | ✓ |
| All testable modes + skip annotations | Same selection but add skipped/stub tests for untestable modes. | |
| You decide | Claude picks the feasible test set. | |

**User's choice:** Only Conjure-auditable modes

| Option | Description | Selected |
|--------|-------------|----------|
| New section in tests/run.sh | Add '▸ Failure-mode reproductions (TEST-07)' to existing run.sh. One file, consistent output. | ✓ |
| Separate tests/test-failure-modes.sh | Standalone script. Cleaner separation but adds another entrypoint. | |
| Reuse _broken/ + add more _broken-* fixtures | Each failure mode gets its own fixture. More fixtures but no new test runner code. | |

**User's choice:** New section in tests/run.sh

| Option | Description | Selected |
|--------|-------------|----------|
| Mini synthetic fixtures per mode | Each failure mode gets a minimal in-test fixture dir (mktemp -d, write offending file). Self-contained. | ✓ |
| Extend _broken/ with additional violations | Add more violations to single _broken/ fixture. Simpler but harder to isolate. | |
| You decide | Claude picks fixture strategy per mode. | |

**User's choice:** Mini synthetic fixtures per mode

---

## Windows CI Leg Design

| Option | Description | Selected |
|--------|-------------|----------|
| Targeted hook-wiring smoke test | windows-latest: install Node, run conjure init, verify settings.json contains 'node' hook commands. Fast, focused on SAFE-03 regression. | ✓ |
| Full test suite on Windows | Run bash tests/run.sh on windows-latest via Git Bash. High maintenance. | |
| Node .mjs hook invocation test | Actually invoke a generated .mjs hook with node on Windows. Requires mock event payload. | |

**User's choice:** Targeted hook-wiring smoke test

| Option | Description | Selected |
|--------|-------------|----------|
| Git Bash via shell: bash | GitHub Actions windows-latest has Git Bash; use 'shell: bash'. Node is pre-installed. No extra deps. | ✓ |
| WSL2 leg | Run via WSL2 Ubuntu. Higher setup cost; obscures native Windows path. | |
| PowerShell wrapper | Complex, doesn't reflect real user workflow. | |

**User's choice:** Git Bash via shell: bash

| Option | Description | Selected |
|--------|-------------|----------|
| grep node in generated settings.json + node --version exits 0 | After conjure init: node --version exits 0, grep 'node' .claude/settings.json, grep -v 'bash .claude/hooks'. Proves SAFE-03 intact. | ✓ |
| Actually invoke a generated .mjs hook | Write synthetic event JSON, pipe to node .mjs hook, assert exit 0. Requires mock payload. | |
| You decide | Claude designs Windows assertion. | |

**User's choice:** grep node in settings.json + node --version exits 0

---

## Claude's Discretion

- Exact positive patterns in green fixture EXPECT files (which specific PASS: line to match)
- Whether dry-run diff section re-uses sandbox_setup or manages its own temp copy
- Which specific exit 1 pattern constitutes the "wrong exit code" synthetic fixture
- Whether regen-fixtures.sh gets a --update-expect flag

## Deferred Ideas

None — discussion stayed within phase scope.
