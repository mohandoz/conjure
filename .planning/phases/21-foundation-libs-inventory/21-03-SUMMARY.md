---
phase: 21-foundation-libs-inventory
plan: "03"
subsystem: foundation-libs
tags:
  - snapshot
  - inventory
  - classify
  - manifest
  - wave-2
  - inv-01
  - inv-02
  - inv-03
  - inv-04
  - sc-2
dependency_graph:
  requires:
    - 21-02 (lib/caps.sh, lib/log.sh, mutate_archive already in lib/mutate.sh)
    - lib/mutate.sh (mutate_write for snapshot-meta.json and manifest write)
    - lib/log.sh (log_step for SNAPSHOT and INVENTORY log entries)
    - lib/caps.sh (CLAUDE_MD_CAP/SKILL_MD_CAP/AGENT_MD_CAP for size_cap_exceeded)
    - tests/fixtures/brownfield-simple/ (fixture for unit tests)
  provides:
    - lib/snapshot.sh (snapshot_create / snapshot_rollback / snapshot_list — timestamped backup primitive)
    - lib/inventory.sh (inventory_scan / inventory_classify / inventory_emit_manifest — 6-bucket classifier + adopt-manifest.json emitter)
  affects:
    - tests/run.sh (3 bug fixes — CONJURE_HOME injection, symlink test uses cp -a, SC2295 shellcheck fix)
tech_stack:
  added: []
  patterns:
    - snapshot_create uses raw cp -a (NOT mutate_cp) — safety primitive bypass of DRY_RUN gate
    - DRY_RUN=1 for snapshot_create: prints would-be path, sets CONJURE_SNAPSHOT_PATH, skips cp
    - cp -a with cp -Rp POSIX fallback for cross-platform compatibility (Pitfall 5)
    - jq -cn --slurpfile for manifest construction (avoids ARG_MAX on large inventories — Pitfall 6)
    - D-10 harness-first budget: 3 separate find passes (CLAUDE.md first, then .claude/.planning, then rest)
    - inventory_classify: path-first case statement decision tree; never frontmatter-based (D-03)
    - D-02 invariant: exactly 6 buckets emitted; no candidate-*/stale-candidate from LLM judgment
    - extract_claude_md_links: single grep pass for ](path) links from CLAUDE.md (D-06)
    - emit_file_entry: jq -cn with --arg/--argjson (injection-safe; no shell string concat for JSON)
    - POSIX bash 3.2+ mktemp + while IFS= read -r pattern throughout (no process substitution)
key_files:
  created:
    - lib/snapshot.sh
    - lib/inventory.sh
  modified:
    - tests/run.sh (3 test bug fixes)
decisions:
  - "snapshot_create uses raw cp -a bypassing mutate_cp — snapshot is the safety primitive before all mutations; DRY_RUN must not suppress it"
  - "inventory_classify is path-based only (D-03) — files outside harness directories stay unknown regardless of frontmatter content"
  - "D-02 invariant enforced: classification never emits candidate-skill/candidate-agent/stale-candidate — those are LLM judgment owned by Phase 23 restructure skill"
  - "DRY_RUN=1 for inventory_emit_manifest redirects to /tmp/adopt-manifest-dryrun.json; mutate_write is still called (write always happens; only location differs)"
  - "jq --slurpfile used for files[] and violations[] arrays (Pitfall 6 — avoids ARG_MAX on 500+ file inventories)"
  - "total_found is raw find count before symlink/binary filtering; total_files is post-filter count — these intentionally differ"
metrics:
  duration: ~20 minutes
  completed: "2026-05-28"
  tasks_completed: 2
  tasks_total: 2
  files_created: 2
  files_modified: 1
---

# Phase 21 Plan 03: snapshot.sh + inventory.sh Summary

Implemented lib/snapshot.sh (timestamped backup primitive using raw cp -a) and lib/inventory.sh (read-only markdown scanner with 6-bucket path-based classifier and adopt-manifest.json emitter) — the two most complex files in Phase 21.

## What Was Built

### Task 1: lib/snapshot.sh (commit 2044f77)

**lib/snapshot.sh** — Full timestamped snapshot primitive (SC-2, SAFE-01):

- `snapshot_create <target> <backup_root>`:
  - Computes UTC timestamp: `date -u '+%Y%m%dT%H%M%SZ'`
  - DRY_RUN=1: echoes `[dry-run] would snapshot target → snap_dir`, sets `CONJURE_SNAPSHOT_PATH`, returns 0 — no cp executed
  - DRY_RUN=0: `mkdir -p snap_dir` + `cp -a target/. snap_dir/` (preserves symlinks + timestamps per M-4)
  - Cross-platform fallback: `cp -Rp` if `cp -a` fails (Pitfall 5)
  - Writes `.snapshot-meta.json` via `mutate_write` with `created_at`, `target`, `git_head`, `git_stash_list`
  - Sets `CONJURE_SNAPSHOT_PATH="${snap_dir}"`
  - Calls `log_step SNAPSHOT` when `RESTRUCTURE_LOG_PATH` is set (silently skips if not set)
  - Never increments `CONJURE_DRY_MUTATION_COUNT` — snapshot is the safety primitive, not a counted mutation
- `snapshot_rollback <snapshot_path> <target>`: validates snapshot exists, restores via `cp -a`, calls `log_step ROLLBACK`
- `snapshot_list <backup_root>`: `ls -1t conjure-adopt-*` newest-first with `shellcheck disable=SC2012` annotation
- Passes shellcheck with 0 errors

**Bug fix in tests/run.sh [Rule 1]:**
- `CONJURE_HOME="$CONJURE_HOME"` injected into DRY_RUN=1 test subshell (same pattern as Plan 02 fixes)

### Task 2: lib/inventory.sh (commit f81a70f)

**lib/inventory.sh** — Read-only markdown scanner + 6-bucket classifier (INV-01..INV-04):

**`inventory_classify <filepath_abs> <target_abs> <claude_md_links_file>`:**
- Path-based case statement decision tree (D-03 path-first, conservative):
  - `CLAUDE.md` → `core`
  - `.claude/skills/*/SKILL.md` → `skill`
  - `.claude/agents/*.md` → `agent`
  - `.planning/*` → `planning-doc`
  - `docs/*|README.md|CHANGELOG*|*.adr.md|ARCHITECTURE.md|CONTRIBUTING.md` → `reference-doc` (D-07)
  - File in CLAUDE.md outbound `](path)` links → `reference-doc` (D-06)
  - Symlinks → `SKIP:symlink` (M-2)
  - Everything else → `unknown` (D-03 conservative)
- D-02 invariant: exactly 6 buckets emitted; never `candidate-skill`/`candidate-agent`/`stale-candidate`

**`inventory_scan <target>`:**
- D-04: markdown-only (`-name '*.md'`)
- Exclusions: `.git/`, `node_modules/`, `.conjure-adopt-backups/`, `.conjure-archive-*/`
- D-08 two-step count: `find | wc -l` for `total_found` (before cap)
- D-10 harness-first budget: 3 separate find passes (Pass 1: root CLAUDE.md, Pass 2: `.claude/` + `.planning/`, Pass 3: all other) → deduplicate → `head -500`
- Per-file skips: symlinks (`test -L`), binary files (`LC_ALL=C grep -Pc '\x00'`)
- Sets `CONJURE_INVENTORY_ITEMS`, `CONJURE_INVENTORY_TOTAL_FOUND`, `CONJURE_INVENTORY_SCAN_CAPPED`

**`inventory_emit_manifest <target_abs> <output_path>`:**
- Internal guard: calls `inventory_scan` if `CONJURE_INVENTORY_ITEMS` is empty
- Calls `extract_claude_md_links` for D-06 CLAUDE.md link data
- Per-file: `wc -l < file` (cap detection), `wc -c < file` (bytes), `emit_file_entry` → JSONL accumulator
- `jq -cn --slurpfile` for `files[]`, `size_cap_violations[]`, `harness_missing_layers[]` (Pitfall 6)
- DRY_RUN=1: redirects to `/tmp/adopt-manifest-dryrun.json`; `mutate_write` always called
- All required top-level keys: `schema_version`, `generated_at`, `conjure_version`, `target`, `snapshot_path`, `summary`, `files`, `size_cap_violations`, `harness_missing_layers`, `restructure_steps`
- `restructure_steps: []` always empty at inventory time
- Calls `log_step INVENTORY` when `RESTRUCTURE_LOG_PATH` is set
- Passes shellcheck with 0 errors

**Bug fixes in tests/run.sh [Rule 1]:**
- Symlink test (INV-03): changed `cp -r` to `cp -a` — `cp -r` dereferences symlinks, making `test -L` fail and symlink-target.md appear in `files[]`
- SC2295: `${filepath#"${target}/"}` quoting inside parameter expansion

## Verification Results

```
shellcheck lib/snapshot.sh lib/inventory.sh
→ All pass (0 errors)

bash tests/run.sh 2>&1 | tail -3
→ PASS: 354    FAIL: 1
→ rc=1 (1 stub for Plan 04 — expected)

Failures remaining (all stubs for future plans):
  ✗ audit-setup.sh not yet updated — Plan 04 required to source lib/caps.sh (SC-5)

Phase 21 SC-2 tests: all ✓ (4 tests)
Phase 21 INV-01..INV-04 tests: all ✓ (14 tests)
Phase 21 CR-7 perf gate: ✓ (6s < 30s limit)
Pre-existing tests: 0 regressions (was 331 pass before, now 354 — 23 new passes)
```

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] CONJURE_HOME not injected in snapshot.sh DRY_RUN test subshell**
- **Found during:** Task 1 verification (snapshot.sh DRY_RUN=1 test)
- **Issue:** Test uses `bash -c '...'` with `$CONJURE_HOME` in single-quoted string; without injecting `CONJURE_HOME="$CONJURE_HOME"` in the env prefix, the subshell sees empty path → `/lib/mutate.sh: No such file or directory`
- **Fix:** Added `CONJURE_HOME="$CONJURE_HOME"` to env var injection prefix (same pattern as Plan 02 fixes for log.sh and mutate_archive)
- **Files modified:** tests/run.sh
- **Commit:** 2044f77

**2. [Rule 1 - Bug] tests/run.sh INV-03 symlink test used cp -r (dereferences symlinks)**
- **Found during:** Task 2 verification (INV-03 symlink skip test)
- **Issue:** `cp -r` dereferences symlinks — `symlink-target.md` becomes a regular file in the test target. `test -L` check in `inventory_scan` fails (not a symlink), so the file is included in `files[]` — exactly what the test checks must NOT happen
- **Fix:** Changed `cp -r "$BF_FIXTURE/." "$P21_INV_WORK/target/"` to `cp -a "$BF_FIXTURE/." ...` with `cp -r` fallback. `cp -a` preserves symlinks, so `test -L` succeeds and the file is correctly skipped
- **Files modified:** tests/run.sh
- **Commit:** f81a70f

**3. [Rule 1 - Bug] shellcheck SC2295 — unquoted expansion inside parameter substitution**
- **Found during:** Task 2 implementation (shellcheck run)
- **Issue:** `${filepath#${target}/}` — shellcheck SC2295 warns that unquoted `${target}` inside `${..#..}` matches as a glob pattern, not a literal string
- **Fix:** Changed to `${filepath#"${target}"/}` (inner expansion quoted separately)
- **Files modified:** lib/inventory.sh
- **Commit:** f81a70f

## Known Stubs

None — all deliverables are fully wired with real behavior. No placeholder values or TODOs.

## Threat Flags

No new threat surface introduced beyond what the plan's threat model covers (T-21-07 through T-21-11). All mitigations applied:
- T-21-07 (path traversal): relative paths in files[] via `${filepath#"${target}"/}` stripping
- T-21-08 (shell injection): `jq --arg` for all path/string fields; never eval'd
- T-21-09 (DRY_RUN bypass): `inventory_emit_manifest` redirects to `/tmp` path before calling `mutate_write`
- T-21-11 (snapshot to wrong location): `snap_dir` derived from `backup_root + "conjure-adopt-" + ts`

## Self-Check: PASSED

All created files found:
- `lib/snapshot.sh` — FOUND
- `lib/inventory.sh` — FOUND

All modified files verified:
- `tests/run.sh` — FOUND, CONJURE_HOME fix + symlink cp -a fix applied — CONFIRMED

Commits verified:
- `2044f77`: feat(21-03): implement lib/snapshot.sh — FOUND
- `f81a70f`: feat(21-03): implement lib/inventory.sh — FOUND
