---
phase: 21
slug: foundation-libs-inventory
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-05-28
---

# Phase 21 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Hand-rolled `tests/run.sh` (pass/fail/t helpers; sandbox in `tests/lib/sandbox.sh`) |
| **Config file** | none — `tests/run.sh` is self-contained |
| **Quick run command** | `bash tests/run.sh 2>&1 \| tail -20` |
| **Full suite command** | `bash tests/run.sh` |
| **Estimated runtime** | ~<30 seconds (Nyquist quick-check gate; CR-7 perf gate enforces <30s on the 500-file fixture) |

---

## Sampling Rate

- **After every task commit:** Run `bash tests/run.sh 2>&1 | grep -E "✓|✗|PASS|FAIL"` — verify no regressions against existing 302+ assertions
- **After every plan wave:** Run `bash tests/run.sh` (full suite incl. new Phase 21 lib tests)
- **Before `/gsd-verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

> Task IDs are assigned by the planner. The Requirement→Behavior→Command map below
> comes from RESEARCH.md §Validation Architecture; bind each row to a task ID once
> PLAN.md files exist.

| Requirement | Wave | Behavior | Test Type | Automated Command | File Exists |
|-------------|------|----------|-----------|-------------------|-------------|
| INV-01 | 1 | classify markdown files into 6 buckets | unit | `bash tests/run.sh 2>&1 \| grep -E "INV-01\|classify"` | ❌ W0 |
| INV-01 | 1 | unknown bucket for file outside harness dirs | unit | inline in run.sh | ❌ W0 |
| INV-02 | 1 | emit adopt-manifest.json with required top-level keys | unit | `jq '.schema_version' adopt-manifest.json` | ❌ W0 |
| INV-02 | 1 | summary.* counts match files[] classifications | unit | inline in run.sh | ❌ W0 |
| INV-03 | 1 | symlinks skipped; RESTRUCTURE-LOG records skip reason | unit | inline in run.sh (fixture symlink) | ❌ W0 |
| INV-03 | 1 | >500 file cap: summary.scan_capped=true, total_found>500 | unit | inline in run.sh (synthetic 510-file fixture) | ❌ W0 |
| INV-03 | 1 | harness-first budget: .claude/** never cut by cap | unit | inline in run.sh | ❌ W0 |
| INV-04 | 1 | size_cap_exceeded=true for file over cap | unit | inline in run.sh | ❌ W0 |
| INV-04 | 1 | size_cap_violations[] populated | unit | inline in run.sh | ❌ W0 |
| SAFE-03 | 1 | mutate_archive: file moved not deleted | unit | inline in run.sh | ❌ W0 |
| SAFE-03 | 1 | mutate_archive: sha256 mismatch aborts, src preserved | unit | inline in run.sh (corrupt dest before verify) | ❌ W0 |
| SAFE-03 | 1 | mutate_archive DRY_RUN: prints [dry-run] would archive, no move | unit | inline in run.sh | ❌ W0 |
| SAFE-03 | 1 | archive ledger entry written with ts + sha256 | unit | inline in run.sh | ❌ W0 |
| ADOPT-03 / SC-1 | 1 | log_init creates RESTRUCTURE-LOG.md header | unit | inline in run.sh | ❌ W0 |
| ADOPT-03 / SC-1 | 1 | log_step appends [TIMESTAMP] [PHASE] msg | unit | inline in run.sh | ❌ W0 |
| ADOPT-03 / SC-1 | 1 | DRY_RUN=1 prints entries, no file write | unit | inline in run.sh | ❌ W0 |
| SC-2 | 1 | snapshot dir non-empty, contains CLAUDE.md and .claude/ | unit | inline in run.sh | ❌ W0 |
| SC-2 | 1 | snapshot DRY_RUN=1 prints path, no cp | unit | inline in run.sh | ❌ W0 |
| SC-4 | 1 | adopt-manifest.json sample validates against schema | unit | `jq 'empty' < adopt-manifest.schema.json && echo ok` | ❌ W0 |
| SC-5 | 1 | caps.sh exports CLAUDE_MD_CAP=100/SKILL_MD_CAP=200/AGENT_MD_CAP=80 | unit | inline in run.sh | ❌ W0 |
| SC-5 | 1 | audit-setup.sh uses $CLAUDE_MD_CAP (not literal 100) | smoke | `grep -c 'CLAUDE_MD_CAP' scripts/audit-setup.sh` | ❌ W0 |
| CR-7 perf | 1 | --dry-run on 500-file fixture completes <30s | perf | `time bash tests/run.sh` | ❌ W0 |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `tests/fixtures/brownfield-simple/` — representative fixture with CLAUDE.md, a skill, an agent, docs/, .planning/, and a symlink for M-2 tests
- [ ] `tests/fixtures/brownfield-simple/generate-large.sh` — generates 510+ .md files for cap tests (synthetic, not committed; generated at test time)
- [ ] Phase 21 test block in `tests/run.sh` — covering every Req ID above
- [ ] `adopt-manifest.schema.json` — JSON Schema (draft-07) for manifest validation

*Existing 302+ test infrastructure covers other phases; Wave 0 adds the brownfield-simple fixture and the Phase 21 test block only.*

---

## Manual-Only Verifications

*All phase behaviors have automated verification (deterministic filesystem + JSON output).*

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
