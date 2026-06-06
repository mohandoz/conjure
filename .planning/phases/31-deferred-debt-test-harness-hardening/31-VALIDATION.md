---
phase: 31
slug: deferred-debt-test-harness-hardening
status: ready
nyquist_compliant: true
wave_0_complete: true
created: 2026-06-04
---

# Phase 31 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | hand-rolled `tests/run.sh` (POSIX bash fixture harness) |
| **Config file** | none — harness is self-contained |
| **Quick run command** | `bash tests/run.sh` |
| **Full suite command** | `bash tests/run.sh` |
| **Live-test run** | `CONJURE_LIVE_TEST=1 ANTHROPIC_API_KEY=<key> bash tests/run.sh` |
| **Strict live-test run** | `CONJURE_STRICT=1 CONJURE_LIVE_TEST=1 ANTHROPIC_API_KEY=<key> bash tests/run.sh` |
| **Estimated runtime** | ~60–120 seconds (existing suite ~90s; new live sections add ~30s when keys present) |

---

## Sampling Rate

- **After every task commit:** Run `bash tests/run.sh`
- **After every plan wave:** Run `bash tests/run.sh`
- **Before `/gsd-verify-work`:** Full suite must be green
- **Max feedback latency:** ~120 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 31-01-T1 | 01 | 1 | DEBT-04 | T-31-02 | preflight.sh exits 2 (not 1) when required dep missing | unit (existing preflight test at run.sh:148-197) | `bash tests/run.sh` | ✅ | ⬜ pending |
| 31-01-T1 | 01 | 1 | DEBT-03 | T-31-01 | mk_tmpd() aborts suite with exit 2 on mktemp failure | unit (sandbox.sh function + grep verification) | `grep -n 'mk_tmpd' tests/lib/sandbox.sh` | ✅ | ⬜ pending |
| 31-01-T2 | 01 | 1 | DEBT-05 | — | PASS/FAIL/SKIP summary line; skip() routes to fail() under CONJURE_STRICT=1 | observable output | `bash tests/run.sh \| grep -E 'PASS:.*FAIL:.*SKIP:'` | ✅ | ⬜ pending |
| 31-02-T1 | 02 | 1 | UAT-03 | T-31-03 | MANUAL-UAT.md exists with required sections and checkboxes | smoke (file existence + grep) | `grep -c '\- \[ \]' tests/MANUAL-UAT.md` | ❌ W0 new file | ⬜ pending |
| 31-03-T1 | 03 | 2 | DEBT-03 | T-31-05 | No raw $(mktemp -d) outside sandbox.sh; regression gate passes | convention self-test | `bash tests/run.sh \| grep 'convention: no raw'` | ✅ | ⬜ pending |
| 31-03-T2 | 03 | 2 | DEBT-06 | T-31-04 | SCHM-STALE test uses CONJURE_SCHEMA_FILE; lib/cc-schema.json unchanged after run | unit (existing SCHM-STALE test, reworked) | `bash tests/run.sh \| grep 'SCHM-STALE'` + `git diff lib/cc-schema.json` | ✅ | ⬜ pending |
| 31-04-T1 | 04 | 3 | UAT-01 | T-31-08 | Skip verdict emitted when CONJURE_LIVE_TEST not set | unit (skip verdict in output) | `bash tests/run.sh \| grep '○.*UAT-01'` | ✅ (section added) | ⬜ pending |
| 31-04-T1 | 04 | 3 | UAT-02 | T-31-07 | Skip verdict emitted when ANTHROPIC_API_KEY not set; key never in output | unit (skip verdict in output) | `bash tests/run.sh \| grep '○.*UAT-02'` | ✅ (section added) | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

Existing infrastructure covers all phase requirements. No new test framework, no new config files, no pre-creation stubs needed. The sole new file is `tests/MANUAL-UAT.md` (Plan 02, pure documentation — no test framework dependency).

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| MDM plist pushed to enrolled macOS device enforces Claude Code policy | UAT-26a | Requires physical MDM-enrolled hardware | Follow `tests/MANUAL-UAT.md § UAT-26a` |
| Windows PS1 writes registry keys and Claude Code enforces policy | UAT-26b | Requires Windows device with registry access | Follow `tests/MANUAL-UAT.md § UAT-26b` |
| managed-settings.json loaded by Claude Code on startup | UAT-26c | Requires Claude Code app in a known state | Follow `tests/MANUAL-UAT.md § UAT-26c` |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify commands
- [x] Sampling continuity: every task commit triggers `bash tests/run.sh` (< 120s)
- [x] Wave 0 covers all MISSING references (none — all changes land in existing files or one new doc)
- [x] No watch-mode flags
- [x] Feedback latency < 120s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** ready for execution
