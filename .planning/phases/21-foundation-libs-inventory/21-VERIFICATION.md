---
phase: 21-foundation-libs-inventory
verified: 2026-05-28T20:00:00Z
status: passed
score: 15/15 must-haves verified
overrides_applied: 0
re_verification:
  previous_status: gaps_found
  previous_score: 13/15
  gaps_closed:
    - "lib/inventory.sh binary-file skip works cross-platform (macOS BSD grep)"
    - "mutate_archive never allows archive destination to escape archive_root via path traversal"
  gaps_remaining: []
  regressions: []
---

# Phase 21: Foundation Libs + Inventory — Verification Report

**Phase Goal:** The shared library layer and inventory contract that every subsequent component depends on are in place and independently testable.
**Verified:** 2026-05-28T20:00:00Z
**Status:** passed — all 15 must-haves verified; both prior BLOCKERs closed in commit 136d824
**Re-verification:** Yes — after gap closure (previous: gaps_found 13/15)

## Re-verification Summary

Both BLOCKERs from the initial verification are confirmed closed by independent code inspection and live test execution.

**CR-01 closed:** `lib/inventory.sh:224` now uses `LC_ALL=C tr -d '\000' < "${filepath}" | cmp -s - "${filepath}"` — a POSIX-portable NUL-byte test that works on BSD grep (macOS) and GNU grep. The old `grep -Pc '\x00'` pattern (GNU-only PCRE) is gone. Regression test "inventory: binary .md (NUL bytes) skipped, text kept (CR-01/INV-03)" passes.

**CR-02 closed:** `lib/mutate.sh:96-102` now validates `src` at the top of `mutate_archive`: (a) rejects non-absolute paths with `ABORT: src must be an absolute path` and (b) rejects any path containing `/../` via `case "/${src}/" in */../*)`. The D-13 never-delete guarantee is intact — source preserved on traversal abort test passes. Three new regression tests all pass (traversal abort, source preserved on traversal abort, relative src aborts).

**Test suite result:** PASS: 359 FAIL: 0 rc=0 (up from 355 in initial verification; 4 new regression tests added for CR-01 and CR-02).

**Shellcheck:** Clean (exit 0, no output) on all 5 libs at `-S error` severity.

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | lib/log.sh writes RESTRUCTURE-LOG.md header and structured [TIMESTAMP] [PHASE] message entries via mutate_write --append; dry-run prints without touching filesystem | VERIFIED | lib/log.sh:34-41 — log_step builds entry with embedded newline, calls mutate_write --append; DRY_RUN honored via mutate_write internals |
| 2 | lib/snapshot.sh creates a full timestamped backup under backup_root using raw cp -a (not mutate_cp); snapshot directory contains CLAUDE.md and .claude/ | VERIFIED | lib/snapshot.sh:32 — raw cp -a bypasses mutate_cp by design; cp -Rp fallback present; log_step SNAPSHOT called when RESTRUCTURE_LOG_PATH set |
| 3 | lib/inventory.sh scans a fixture repo and classifies every markdown file into one of exactly 6 harness buckets (never candidate-* buckets) | VERIFIED | lib/inventory.sh:54-100 — path-based case statement, 6 buckets only; D-02 invariant enforced |
| 4 | lib/inventory.sh skips symlinks correctly (M-2) | VERIFIED | lib/inventory.sh:215-216 — test -L check in inventory_scan; test suite INV-03 symlink test passes |
| 5 | lib/inventory.sh skips binary files cross-platform (macOS BSD grep and Linux GNU grep) | VERIFIED | lib/inventory.sh:224 — `LC_ALL=C tr -d '\000' < "${filepath}" | cmp -s - "${filepath}"` replaces old grep -Pc. Portable on macOS/BSD and Linux. CR-01 regression test passes: "inventory: binary .md (NUL bytes) skipped, text kept (CR-01/INV-03)" |
| 6 | lib/inventory.sh caps at 500 files with harness-first budget (D-10); scan_capped and total_found set correctly | VERIFIED | lib/inventory.sh:157-205 — 3-pass find with awk dedup + head -500; CONJURE_INVENTORY_SCAN_CAPPED set when total_found > 500; INV-03 cap test passes |
| 7 | lib/inventory.sh emits a valid adopt-manifest.json with all required top-level keys | VERIFIED | lib/inventory.sh:357-403 — jq -cn with all 10 required keys (schema_version, generated_at, conjure_version, target, snapshot_path, summary, files, size_cap_violations, harness_missing_layers, restructure_steps); live test confirms valid JSON |
| 8 | adopt-manifest.json schema is finalized with schema_version, summary.*, files[], size_cap_violations[], harness_missing_layers, restructure_steps[]; 6-bucket classification enum | VERIFIED | adopt-manifest.schema.json — JSON Schema draft-07; jq validates; 6-enum classification confirmed; size_cap_exceeded field (D-09) present |
| 9 | lib/caps.sh exports CLAUDE_MD_CAP=100, SKILL_MD_CAP=200, AGENT_MD_CAP=80; idempotent re-source | VERIFIED | lib/caps.sh:9-11 — uses ${VAR:-default} idempotent pattern; `source lib/caps.sh && echo $CLAUDE_MD_CAP` outputs "100" |
| 10 | mutate_archive moves a file via copy→sha256-verify→rm→ledger; never deletes src on sha256 mismatch (D-13) | VERIFIED | lib/mutate.sh:107-130 — correct sequence; hash mismatch path calls rm -f dest and return 1, never touching src; D-13 test passes: "mutate_archive: source preserved on copy abort" |
| 11 | mutate_archive honors DRY_RUN and path-preserving layout (D-12) | VERIFIED | lib/mutate.sh:88-91 — DRY_RUN guard at top; rel="${src#/}" strips leading slash for path-preserving layout; validation guards run before rel derivation |
| 12 | mutate_archive never allows archive destination to escape archive_root via unvalidated relative/.. src paths | VERIFIED | lib/mutate.sh:96-102 — absolute-path check via `case "${src}" in /*)`; traversal check via `case "/${src}/" in */../*)`; both abort with rc=1 and log to stderr. Three CR-02 regression tests all pass: traversal abort (rc=1), source preserved on traversal abort, relative src aborts (rc=1) |
| 13 | scripts/audit-setup.sh sources lib/caps.sh and uses $CLAUDE_MD_CAP/$SKILL_MD_CAP/$AGENT_MD_CAP instead of literal 100/200/80 | VERIFIED | scripts/audit-setup.sh:8-10 — CONJURE_HOME resolution + source caps.sh; lines 30-31 use ${CLAUDE_MD_CAP}/${SKILL_MD_CAP}; lines 58,82 use ${SKILL_MD_CAP}/${AGENT_MD_CAP}; literal grep returns 0 matches |
| 14 | brownfield-simple fixture exists with all required files and passes audit-setup.sh exit 0 | VERIFIED | tests/fixtures/brownfield-simple/ confirmed with CLAUDE.md, .claude/skills/git/SKILL.md, .claude/agents/deploy.md, .claude/settings.json, docs/*.md, .planning/21-PLAN.md, symlink-target.md (symlink); bash scripts/audit-setup.sh exits 0 with PASS:14 WARN:0 FAIL:0 |
| 15 | bash tests/run.sh passes all tests with zero failures; Phase 21 test block covers all 8 requirement groups | VERIFIED | `bash tests/run.sh 2>&1 | tail -3` → PASS:359 FAIL:0 rc=0; 4 new tests added for CR-01/CR-02 closures; 8 Phase 21 section headers confirmed; all Phase 21 sub-assertions show pass |

**Score:** 15/15 truths verified

---

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `lib/caps.sh` | Cap constants CLAUDE_MD_CAP=100, SKILL_MD_CAP=200, AGENT_MD_CAP=80; idempotent | VERIFIED | 11 lines; shellcheck clean; exports confirmed live |
| `lib/log.sh` | log_init/log_step/log_fail; writes via mutate_write --append; DRY_RUN safe | VERIFIED | 52 lines; shellcheck clean; embedded newline in log_step entry |
| `lib/mutate.sh` | mutate_archive with absolute-path + no-traversal validation; D-13 never-delete intact | VERIFIED | Lines 93-102: absolute-path guard + traversal guard present; D-13 sha256-verify-before-rm intact; shellcheck clean |
| `lib/snapshot.sh` | snapshot_create/rollback/list; raw cp -a; log_step SNAPSHOT integration | VERIFIED | 100 lines; shellcheck clean; cp -a with cp -Rp fallback; log_step SNAPSHOT called when RESTRUCTURE_LOG_PATH set |
| `lib/inventory.sh` | inventory_scan/classify/emit_manifest; 6-bucket classifier; portable binary skip; adopt-manifest.json emitter | VERIFIED | 429 lines; shellcheck clean; binary skip via tr+cmp at line 224; all CR-01 tests pass |
| `scripts/audit-setup.sh` | sources lib/caps.sh; uses cap variables | VERIFIED | source line at line 10; all three literals replaced with variables; brownfield-simple exits 0 |
| `adopt-manifest.schema.json` | JSON Schema draft-07; 6-bucket classification enum; size_cap_exceeded field | VERIFIED | Valid JSON; 6 enum values confirmed; all required fields present |
| `tests/fixtures/brownfield-simple/` | 9 files + symlink; audit-setup.sh exit 0 | VERIFIED | All files present including .claude/ (force-added), symlink-target.md; audit exits 0 |
| `tests/fixtures/brownfield-simple/generate-large.sh` | Creates 510+ .md files when run | VERIFIED | CR-7 perf test: generates 511 files, completes in 6s < 30s threshold |
| `tests/run.sh` | Phase 21 test block with 8 section headers; all Req IDs covered; CR-01 + CR-02 regression tests | VERIFIED | 8 section headers; PASS:359 FAIL:0; CR-01 and CR-02 regression tests present and passing |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| lib/caps.sh | lib/mutate.sh | header declares "Requires: lib/mutate.sh already sourced" | VERIFIED | lib/caps.sh:4 — comment present |
| lib/log.sh | lib/mutate.sh | mutate_write --append for all log entries | VERIFIED | lib/log.sh:41 — mutate_write called with --append |
| lib/mutate.sh mutate_archive | .archive-ledger | printf append after rm; sha256 verify gate before rm | VERIFIED | lib/mutate.sh:132-134 — ledger entry appended to ${archive_root}/.archive-ledger |
| lib/snapshot.sh | lib/log.sh | log_step SNAPSHOT called after cp -a | VERIFIED | lib/snapshot.sh:60 — log_step SNAPSHOT "created at ${snap_dir}" when RESTRUCTURE_LOG_PATH set |
| lib/inventory.sh | lib/caps.sh | CLAUDE_MD_CAP/SKILL_MD_CAP/AGENT_MD_CAP for size_cap_exceeded | VERIFIED | lib/inventory.sh:297-299 — cap variables used in case statement |
| lib/inventory.sh inventory_emit_manifest | lib/mutate.sh | mutate_write for manifest output | VERIFIED | lib/inventory.sh:413 — mutate_write called with manifest_content |
| scripts/audit-setup.sh | lib/caps.sh | source CONJURE_HOME/lib/caps.sh near top | VERIFIED | scripts/audit-setup.sh:10 — source present after CONJURE_HOME resolution |
| generate-large.sh | tests/run.sh INV-03 cap test | invoked inside Phase 21 test block at test time | VERIFIED | tests/run.sh Phase 21 block invokes generate-large.sh in INV-03 cap test; CR-7 perf test also uses it |
| adopt-manifest.schema.json | tests/run.sh SC-4 | jq validation in Phase 21 test block | VERIFIED | SC-4 test block validates schema; PASS:359 confirms |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|--------------------|--------|
| lib/inventory.sh → adopt-manifest.json | files[] array | find passes + wc -l/wc -c per file + jq -cn emit_file_entry | Yes — real filesystem data from brownfield-simple fixture | FLOWING |
| lib/inventory.sh → summary block | core_count, skill_count, etc. | integer counters incremented per classification result | Yes — counts match actual fixture files | FLOWING |
| lib/inventory.sh → size_cap_violations[] | line_count vs cap_limit | wc -l per file; cap_limit from CLAUDE_MD_CAP/SKILL_MD_CAP/AGENT_MD_CAP | Yes — 105-line CLAUDE.md correctly produces size_cap_exceeded=true | FLOWING |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| caps.sh exports CLAUDE_MD_CAP=100 | bash -c 'source lib/caps.sh && echo $CLAUDE_MD_CAP' | 100 | PASS |
| audit-setup.sh on brownfield-simple exits 0 | bash scripts/audit-setup.sh tests/fixtures/brownfield-simple | PASS:14 WARN:0 FAIL:0 rc=0 | PASS |
| Binary detection portable (CR-01) | LC_ALL=C tr -d '\000' < file | cmp -s works on macOS /usr/bin; no -P flag required | PASS |
| Full test suite passes | bash tests/run.sh | PASS:359 FAIL:0 rc=0 | PASS |
| CR-01 regression test | tests/run.sh section | "inventory: binary .md (NUL bytes) skipped, text kept (CR-01/INV-03)" shows pass | PASS |
| CR-02 regression tests (3) | tests/run.sh section | traversal abort, source preserved on traversal abort, relative src aborts — all show pass | PASS |
| D-13 never-delete still intact | tests/run.sh section | "mutate_archive: source preserved on copy abort — D-13 guarantee (SAFE-03)" shows pass | PASS |
| Shellcheck all 5 libs | shellcheck -S error lib/*.sh | No output; exit 0 | PASS |

### Probe Execution

No probe scripts declared or conventional for this phase. Test verification performed via `bash tests/run.sh` — see Behavioral Spot-Checks above.

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| INV-01 | 21-01, 21-03 | inventory_classify routes each markdown file into a harness bucket (core/skill/agent/planning-doc/reference-doc/unknown) | SATISFIED | inventory_classify path-based case statement covers all 6 buckets; D-02 invariant enforced; test suite confirms all 5 bucket classifications plus unknown default |
| INV-02 | 21-01, 21-03 | inventory is emitted as adopt-manifest.json (machine-readable CLI/skill contract) | SATISFIED | inventory_emit_manifest creates adopt-manifest.json with all required top-level keys; adopt-manifest.schema.json validates it |
| INV-03 | 21-01, 21-03 | inventory skips binary/symlink/generated/vendored; caps at 500 files with progress indicator | SATISFIED | Symlink skip: verified. Cap-at-500 + harness-first budget: verified. Binary skip: now portable via tr+cmp; CR-01 regression test passes |
| INV-04 | 21-01, 21-03 | manifest flags every size-cap violation (CLAUDE.md over 100 lines) | SATISFIED | size_cap_exceeded field computed per file; size_cap_violations[] populated; live test with 105-line CLAUDE.md confirms |
| SAFE-03 | 21-01, 21-02 | No user file is ever deleted — stale files are archived (moved to archive dir), never rm'd | SATISFIED | mutate_archive copy→sha256-verify→rm→ledger sequence upholds D-13; absolute-path + no-traversal validation (CR-02) closes the path-escape vector; three new regression tests pass |
| ADOPT-03 | 21-02, 21-04 | conjure adopt refuses to run on dirty git tree (exit 2) unless --force (Phase 21 scope: logging primitive for this message) | SATISFIED (scoped) | Phase 21 scope is SC-1: lib/log.sh provides log_init/log_step for the adopt workflow audit trail. Dirty-tree gate is Phase 22 CLI work. lib/log.sh functional with DRY_RUN honored |

### Anti-Patterns Found

The two BLOCKER-class patterns from the initial verification are now resolved. Remaining items are WARNING-class and were present in the initial verification; none are newly introduced.

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| lib/snapshot.sh | 78 | `cp -Rp "${snapshot_path}" "${target}/"` (fallback nests dir) | WARNING | IN-02: fallback copies snapshot directory itself into target instead of restoring contents; only reached when primary cp -a fails; rollback silently wrong on that path |
| lib/inventory.sh | 284 | `wc -l < "${filepath}"` — under-counts files missing trailing newline | WARNING | WR-03: a CLAUDE.md at exactly 100 lines with no trailing newline reports 99; can evade size_cap_exceeded; low probability |
| lib/inventory.sh | 201 | `[ "${total_found}" -gt 500 ]` with no `${total_found:-0}` default | WARNING | WR-02: if find errors, total_found can be empty; bare integer comparison produces "integer expression expected" runtime error |
| lib/snapshot.sh | 43 | `git stash list | head -10` captured as flat string | WARNING | WR-04: multi-line stash blob is opaque to programmatic rollback; INFO-level impact |

No TBD/FIXME/XXX debt markers found in any phase-modified file.

### Human Verification Required

None. All observable behaviors verified programmatically. Both prior BLOCKERs are confirmed fixed by code inspection and live test execution.

### Gaps Summary

No gaps. Both BLOCKER-class gaps from the initial verification are closed:

- CR-01 (binary skip portability): `lib/inventory.sh:224` uses `LC_ALL=C tr -d '\000' < "${filepath}" | cmp -s - "${filepath}"` — confirmed in code and by passing regression test.
- CR-02 (path-traversal in mutate_archive): `lib/mutate.sh:96-102` validates src is absolute and contains no `..` segments before mirroring — confirmed in code and by three passing regression tests. D-13 never-delete guarantee intact.

All 15 must-haves are VERIFIED. The phase goal is achieved.

---

_Verified: 2026-05-28T20:00:00Z_
_Verifier: Claude (gsd-verifier) — re-verification after commit 136d824_
