---
phase: 25
slug: plugin-marketplace-emission
status: draft
nyquist_compliant: true
wave_0_complete: false
created: 2026-06-03
---

# Phase 25 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Hand-rolled `tests/run.sh` (existing; extend per CLAUDE.md — no shellspec/bats at fixture level) |
| **Config file** | none — `tests/run.sh` is self-contained |
| **Quick run command** | `bash tests/run.sh 2>&1 \| grep -E "PLUG\|FAIL"` |
| **Full suite command** | `bash tests/run.sh` |
| **Estimated runtime** | ~30 seconds |

---

## Sampling Rate

- **After every task commit:** Run `bash tests/run.sh 2>&1 | grep -E "PLUG|FAIL"` (Phase 25 block)
- **After every plan wave:** Run `bash tests/run.sh` (full suite)
- **Before `/gsd-verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 25-00-01 | 00 | 0 | — | — | golden fixture harness exists | infra | `test -d tests/fixtures/_emit-plugin` | ❌ W0 | ⬜ pending |
| 25-00-02 | 00 | 0 | PLUG-02 | T-25-badpath | `--path` pointing at non-existent dir exits 2 (D-02 negative case) | unit | `bash tests/run.sh 2>&1 \| grep PLUG-02-badpath` | ❌ W0 | ⬜ pending |
| 25-01-01 | 01 | 1 | PLUG-01 | — | plugin.json emits correct skills/agents/hooks/mcpServers/version | golden-fixture | `bash tests/run.sh 2>&1 \| grep PLUG-01` | ❌ W0 | ⬜ pending |
| 25-01-02 | 01 | 1 | PLUG-01 | — | merge-preserve: re-run keeps description/keywords/author/license | golden-fixture | `bash tests/run.sh 2>&1 \| grep PLUG-01-merge` | ❌ W0 | ⬜ pending |
| 25-01-03 | 01 | 1 | PLUG-05 | — | version chain `.conjure-version`→SHA→0.0.0 | unit | `bash tests/run.sh 2>&1 \| grep PLUG-05` | ❌ W0 | ⬜ pending |
| 25-02-01 | 02 | 1 | PLUG-04 | T-25-malformed | bundled schema check blocks write on invalid manifest | unit | `bash tests/run.sh 2>&1 \| grep PLUG-04` | ❌ W0 | ⬜ pending |
| 25-02-02 | 02 | 1 | PLUG-04 | T-25-secret | secret-pattern in manifest → exit 2 before write | unit | `bash tests/run.sh 2>&1 \| grep PLUG-04-secret` | ❌ W0 | ⬜ pending |
| 25-02-03 | 02 | 1 | PLUG-04 | T-25-validate-absent | `--validate` with absent `claude` CLI exits 2 | unit | `bash tests/run.sh 2>&1 \| grep PLUG-04-absent` | ❌ W0 | ⬜ pending |
| 25-03-01 | 03 | 2 | PLUG-02 | — | `--marketplace` emits name/owner/plugins[]/source | golden-fixture | `bash tests/run.sh 2>&1 \| grep PLUG-02` | ❌ W0 | ⬜ pending |
| 25-03-02 | 03 | 2 | PLUG-02 | T-25-squat | reserved-name guard exits 2 | unit | `bash tests/run.sh 2>&1 \| grep PLUG-02-reserved` | ❌ W0 | ⬜ pending |
| 25-03-03 | 03 | 2 | PLUG-03 | — | `extraKnownMarketplaces` written as object into settings.json | golden-fixture | `bash tests/run.sh 2>&1 \| grep PLUG-03` | ❌ W0 | ⬜ pending |
| 25-03-04 | 03 | 2 | PLUG-03 | — | re-run updates sha in place, never appends duplicate | golden-fixture re-run | `bash tests/run.sh 2>&1 \| grep PLUG-03-idem` | ❌ W0 | ⬜ pending |
| 25-04-01 | 03 | 2 | PLUG-01..05 | — | audit reconciliation: plugin.json out-of-sync → warning exit 0 | smoke | `bash tests/run.sh 2>&1 \| grep PLUG-REC` | ❌ W0 | ⬜ pending |
| 25-04-02 | 03 | 2 | PLUG-03 | — | audit ref-without-sha entry → warning exit 0 | smoke | `bash tests/run.sh 2>&1 \| grep PLUG-REFSHA` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `tests/fixtures/_emit-plugin/` — golden fixture: minimal `.claude/` harness (skills + agents + hooks + settings.json + optional `.mcp.json`)
- [ ] `tests/fixtures/_emit-plugin/expected-plugin.json` — golden expected plugin manifest
- [ ] `tests/fixtures/_emit-plugin/expected-marketplace.json` — golden expected marketplace manifest
- [ ] `tests/fixtures/_emit-plugin/expected-settings.json` — golden expected settings after wiring
- [ ] `tests/run.sh` — new `▸ Phase 25 — Plugin + Marketplace Emission (PLUG-01..PLUG-05)` block
- [ ] `tests/fixtures/_emit-plugin-secret/` — fixture harness with a secret-pattern value (drives PLUG-04-secret exit-2)

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| `claude plugin validate .` live-loads emitted plugin | PLUG-04 | requires `claude` CLI + interactive load; CI uses bundled-schema tier only | After `conjure publish-plugin --validate` on a real harness, confirm exit 0 and "valid" output |

*Live `claude plugin validate` is the opt-in tier-2 gate (D-09/D-10). CI relies on the bundled-schema tier; the live gate is manual.*

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references
- [x] No watch-mode flags
- [x] Feedback latency < 30s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
