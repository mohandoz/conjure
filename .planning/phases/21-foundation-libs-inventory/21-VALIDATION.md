---
phase: 21
slug: foundation-libs-inventory
status: approved
nyquist_compliant: true
wave_0_complete: true
created: 2026-05-28
audited: 2026-05-28
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

| Requirement | Wave | Behavior | Test Type | Automated Command | Status |
|-------------|------|----------|-----------|-------------------|--------|
| INV-01 | 1 | classify markdown files into 6 buckets | unit | `bash tests/run.sh 2>&1 \| grep -E "INV-01\|classify"` | ✅ green |
| INV-01 | 1 | unknown bucket for file outside harness dirs | unit | inline in run.sh | ✅ green |
| INV-02 | 1 | emit adopt-manifest.json with required top-level keys | unit | `jq '.schema_version' adopt-manifest.json` | ✅ green |
| INV-02 | 1 | summary.* counts match files[] classifications | unit | inline in run.sh | ✅ green |
| INV-03 | 1 | symlinks skipped; RESTRUCTURE-LOG records skip reason | unit | inline in run.sh (fixture symlink) | ✅ green |
| INV-03 | 1 | >500 file cap: summary.scan_capped=true, total_found>500 | unit | inline in run.sh (synthetic 510-file fixture) | ✅ green |
| INV-03 | 1 | harness-first budget: .claude/** never cut by cap | unit | inline in run.sh | ✅ green |
| INV-03 | 1 | binary .md (NUL bytes) skipped, text kept | unit | inline in run.sh (CR-01) | ✅ green |
| INV-04 | 1 | size_cap_exceeded=true for file over cap | unit | inline in run.sh | ✅ green |
| INV-04 | 1 | size_cap_violations[] populated | unit | inline in run.sh | ✅ green |
| SAFE-03 | 1 | mutate_archive: file moved not deleted | unit | inline in run.sh | ✅ green |
| SAFE-03 | 1 | mutate_archive: copy failure aborts, src preserved (D-13) | unit | inline in run.sh (chmod 555 archive_root) | ✅ green |
| SAFE-03 | 1 | mutate_archive: '..' / non-absolute src aborts, src preserved | unit | inline in run.sh (CR-02) | ✅ green |
| SAFE-03 | 1 | mutate_archive DRY_RUN: prints [dry-run] would archive, no move | unit | inline in run.sh | ✅ green |
| SAFE-03 | 1 | archive ledger entry written with src path | unit | inline in run.sh | ✅ green |
| ADOPT-03 / SC-1 | 1 | log_init creates RESTRUCTURE-LOG.md header | unit | inline in run.sh | ✅ green |
| ADOPT-03 / SC-1 | 1 | log_step appends [TIMESTAMP] [PHASE] msg (newline check) | unit | inline in run.sh | ✅ green |
| ADOPT-03 / SC-1 | 1 | DRY_RUN=1 prints entries, no file write | unit | inline in run.sh | ✅ green |
| SC-2 | 1 | snapshot dir non-empty, contains CLAUDE.md | unit | inline in run.sh | ✅ green |
| SC-2 | 1 | snapshot DRY_RUN=1 prints path, no cp | unit | inline in run.sh | ✅ green |
| SC-4 | 1 | adopt-manifest schema valid JSON, 6-value enum, required keys | unit | `jq 'empty' < adopt-manifest.schema.json && echo ok` | ✅ green |
| SC-5 | 1 | caps.sh exports CLAUDE_MD_CAP=100/SKILL_MD_CAP=200/AGENT_MD_CAP=80 | unit | inline in run.sh | ✅ green |
| SC-5 | 1 | audit-setup.sh uses $CLAUDE_MD_CAP (not literal 100) | smoke | `grep -c 'CLAUDE_MD_CAP' scripts/audit-setup.sh` | ✅ green |
| CR-7 perf | 1 | inventory on 510-file fixture completes <30s | perf | inline in run.sh (5s measured) | ✅ green |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [x] `tests/fixtures/brownfield-simple/` — representative fixture with CLAUDE.md, a skill, an agent, docs/, .planning/, and a symlink for M-2 tests
- [x] `tests/fixtures/brownfield-simple/generate-large.sh` — generates 510+ .md files for cap tests (synthetic, not committed; generated at test time)
- [x] Phase 21 test block in `tests/run.sh` — covering every Req ID above
- [x] `adopt-manifest.schema.json` — JSON Schema (draft-07) for manifest validation

*Existing 302+ test infrastructure covers other phases; Wave 0 adds the brownfield-simple fixture and the Phase 21 test block only.*

---

## Manual-Only Verifications

*All phase behaviors have automated verification (deterministic filesystem + JSON output).*

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references
- [x] No watch-mode flags
- [x] Feedback latency < 30s (CR-7 perf gate enforces <30s on the 500-file fixture)
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** approved 2026-05-28 (strategy approved at plan time; `wave_0_complete` flips true once the Phase 21 test block + brownfield-simple fixture are built and green during execution)

---

## Validation Audit 2026-05-28

Post-execution audit (State A). All 4 plans complete; full suite green.

| Metric | Count |
|--------|-------|
| Requirements in map | 24 |
| COVERED | 24 |
| PARTIAL | 0 |
| MISSING | 0 |
| Gaps found | 0 |
| Resolved | 0 |
| Escalated | 0 |

**Suite state:** `bash tests/run.sh` → PASS: 359, FAIL: 0 (rc=0).

**Findings:**
- All planned Wave 0 artifacts built (fixture, generate-large.sh, schema, test block).
- All four libs present and green: `lib/caps.sh`, `lib/log.sh`, `lib/snapshot.sh`, `lib/inventory.sh`, plus `mutate_archive` in `lib/mutate.sh`.
- Coverage exceeds the original plan-time map: review fixes added CR-01 (binary `.md` skip) and CR-02 (`..` / non-absolute src archive abort) assertions.
- No gaps → no `gsd-nyquist-auditor` spawn needed. No new test files generated.

`wave_0_complete` flipped `false` → `true`. Phase 21 is Nyquist-compliant.
