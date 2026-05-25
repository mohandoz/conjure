---
phase: 4
slug: regression-suite-dry-run-proof
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-05-25
---

# Phase 4 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | hand-rolled bash — `tests/run.sh` |
| **Config file** | none — all config inlined in run.sh |
| **Quick run command** | `bash tests/run.sh 2>&1 \| tail -30` |
| **Full suite command** | `bash tests/run.sh` |
| **Estimated runtime** | ~45 seconds |

---

## Sampling Rate

- **After every task commit:** Run `bash tests/run.sh 2>&1 | tail -30`
- **After every plan wave:** Run `bash tests/run.sh`
- **Before `/gsd-verify-work`:** Full suite must exit 0 with FAIL: 0
- **Max feedback latency:** ~45 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 04-01-01 | 01 | 1 | TEST-03 | — | EXPECT files contain only regex patterns, no absolute paths | bash | `bash tests/run.sh 2>&1 \| grep -E 'EXPECT\|golden'` | ❌ W0 | ⬜ pending |
| 04-01-02 | 01 | 1 | TEST-03 | — | EXPECT loop iterates all green fixtures | bash | `bash tests/run.sh 2>&1 \| grep 'EXPECT loop'` | ❌ W0 | ⬜ pending |
| 04-01-03 | 01 | 1 | TEST-03 | — | regen-fixtures.sh writes EXPECT files | bash | `bash scripts/regen-fixtures.sh --update-expect --profile ts-next 2>&1 \| grep -q EXPECT` | ❌ W0 | ⬜ pending |
| 04-02-01 | 02 | 1 | TEST-06 | — | windows-hook-wiring job present in ci.yml, uses shell: bash | bash | `grep -q 'windows-hook-wiring' .github/workflows/ci.yml && echo PASS` | ❌ W0 | ⬜ pending |
| 04-03-01 | 03 | 2 | TEST-05 | — | diff -r exits 0 after --dry-run for all 9 fixtures | bash | `bash tests/run.sh 2>&1 \| grep -E 'dry-run.*byte\|snapshot'` | ❌ W0 | ⬜ pending |
| 04-03-02 | 03 | 2 | TEST-07 | — | size-cap, hook exit code, version mismatch reproductions pass | bash | `bash tests/run.sh 2>&1 \| grep 'Failure-mode'` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `tests/fixtures/<profile>/EXPECT` — one file per green profile (9 total); create before TEST-03 loop
- [ ] EXPECT loop section in `tests/run.sh` — stub section `▸ Golden-file EXPECT loop (TEST-03)`
- [ ] Dry-run snapshot section in `tests/run.sh` — stub section `▸ Dry-run byte-identical snapshot (TEST-05)`
- [ ] Failure-mode section in `tests/run.sh` — stub section `▸ Failure-mode reproductions (TEST-07)`

*All Wave 0 items are created in Wave 1 plans.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Windows runner actually executes CI job | TEST-06 | Requires GitHub Actions on windows-latest runner | Push branch, observe `windows-hook-wiring` job passes in GitHub Actions |
| EXPECT patterns catch silent drift | TEST-03 | Requires deliberately breaking a fixture | Modify a fixture's CLAUDE.md, run suite, verify EXPECT loop fails |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 45s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
