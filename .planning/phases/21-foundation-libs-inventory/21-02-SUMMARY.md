---
phase: 21-foundation-libs-inventory
plan: "02"
subsystem: foundation-libs
tags:
  - caps
  - log
  - mutate_archive
  - wave-1
  - safe-03
  - adopt-03
dependency_graph:
  requires:
    - 21-01 (brownfield-simple fixture + Phase 21 test block in tests/run.sh)
    - lib/mutate.sh (existing — mutate_write, mutate_rm patterns)
  provides:
    - lib/caps.sh (CLAUDE_MD_CAP=100, SKILL_MD_CAP=200, AGENT_MD_CAP=80 — single source of truth)
    - lib/log.sh (log_init, log_step, log_fail — RESTRUCTURE-LOG.md writer)
    - lib/mutate.sh mutate_archive (copy→sha256-verify→rm→ledger — D-11/D-12/D-13 move-safety)
  affects:
    - lib/mutate.sh (mutate_archive added between mutate_rm and mutate_summary)
    - tests/run.sh (CONJURE_HOME env fix in DRY_RUN test subshells; D-13 abort test improved)
    - tests/fixtures/brownfield-simple/docs/adr/.gitkeep (empty-dir tracking fix)
tech_stack:
  added: []
  patterns:
    - POSIX bash lib file with shellcheck shell=bash directive (no shebang)
    - mutate_write --append with embedded newline for log entries (Pitfall 1 guard)
    - Cross-platform sha256: sha256sum (Linux) with shasum -a 256 (macOS) fallback
    - DRY_RUN guard at top of all mutation functions (consistent with lib/mutate.sh siblings)
    - Module-level state init: ${VAR:-default} idempotent re-source pattern
key_files:
  created:
    - lib/caps.sh
    - lib/log.sh
  modified:
    - lib/mutate.sh (mutate_archive added; header updated; no other changes)
    - tests/run.sh (3 bug fixes — CONJURE_HOME env injection, D-13 abort test scenario)
    - tests/fixtures/brownfield-simple/docs/adr/.gitkeep (fix empty-dir tracking)
decisions:
  - "# shellcheck shell=bash directive used (not shebang) for sourced lib files without executable bit"
  - "log_fail exits 2 (not 1) per CLAUDE.md constraint — hooks and lib fatal errors use exit 2"
  - "mutate_archive D-13 abort test uses chmod 555 archive_root (cp failure) instead of pre-corrupted dest (which cp -a overwrites)"
  - "CONJURE_HOME must be passed as env var in bash -c DRY_RUN test subshells — not inherited from parent"
metrics:
  duration: ~16 minutes
  completed: "2026-05-28"
  tasks_completed: 2
  tasks_total: 2
  files_created: 2
  files_modified: 3
---

# Phase 21 Plan 02: Foundation Libs (caps.sh, log.sh, mutate_archive) Summary

Implemented lib/caps.sh (cap constants), lib/log.sh (RESTRUCTURE-LOG.md writer), and mutate_archive function in lib/mutate.sh — the three Wave 1 deliverables that lib/snapshot.sh and lib/inventory.sh (Plan 03) depend on.

## What Was Built

### Task 1: lib/caps.sh and lib/log.sh (commit 9a46dbd)

**lib/caps.sh** — Single source of truth for harness size cap constants:
- Exports `CLAUDE_MD_CAP=100`, `SKILL_MD_CAP=200`, `AGENT_MD_CAP=80`
- Idempotent re-source via `${VAR:-default}` guard pattern
- No shebang (sourced not executed); `# shellcheck shell=bash` directive
- 11 lines, passes shellcheck

**lib/log.sh** — RESTRUCTURE-LOG.md writer:
- `log_init <target_dir>`: writes YAML-ish header (conjure/target/started/---) via `mutate_write`; sets `RESTRUCTURE_LOG_PATH`
- `log_step <phase> <message>`: appends `[TIMESTAMP] [PHASE] message\n` via `mutate_write --append`; embedded `\n` guards against line-joining (Pitfall 1)
- `log_fail <message>`: calls `log_step FAIL` then `exit 2` per CLAUDE.md convention
- DRY_RUN honored via mutate_write internally — no separate guard needed
- Passes shellcheck

Also fixed in tests/run.sh: `CONJURE_HOME="$CONJURE_HOME"` added to `bash -c` DRY_RUN test subshell so log.sh tests pass (Rule 1 bug — CONJURE_HOME not exported to subshell).

### Task 2: mutate_archive in lib/mutate.sh (commit 00cfc10)

**mutate_archive** — Move-safe archive primitive (D-11/D-12/D-13):
- DRY_RUN guard: `[dry-run] would archive ${src} → ${archive_root}/...`, counter++, return 0
- Mirror path derivation (D-12): `rel="${src#/}"` strips leading slash; `dest="${archive_root}/${rel}"`
- `mkdir -p "$(dirname "${dest}")"` ensures parent dirs exist
- `cp -a "${src}" "${dest}"` with failure check (no cp = no rm = D-13 preserved)
- Cross-platform sha256 (Pitfall 4): `command -v sha256sum` → `shasum -a 256` fallback → abort if neither
- Hash mismatch: `rm -f "${dest}"` (partial copy cleanup), return 1, src untouched (D-13)
- Hash match: `rm -f "${src}"` (only line in function that deletes src)
- Ledger: `printf '%s\t%s\t%s\t%s\n' src dest sha256 timestamp >> .archive-ledger`
- Counter increment after successful rm (one mutation per move)
- Inserted between mutate_rm and mutate_summary per PATTERNS.md
- Header updated to list mutate_archive in call list

Also fixed:
- `CONJURE_HOME` env injection for mutate_archive DRY_RUN=1 test (Rule 1 — same pattern as log.sh fix)
- D-13 abort test rewritten: uses `chmod 555 archive_root` (cp fails, src preserved) instead of pre-corrupted dest (which `cp -a` would overwrite, making hashes match) (Rule 1 — test didn't test intended behavior)
- `docs/adr/.gitkeep` added to brownfield-simple fixture: git ignores empty directories; without .gitkeep the fixture audit emitted a warning and exited rc=1, failing the fixture audit test (Rule 1 — pre-existing Plan 01 gap)

## Verification Results

```
shellcheck lib/caps.sh lib/log.sh lib/mutate.sh
→ All pass (0 errors)

bash -c 'source lib/caps.sh && echo caps=$CLAUDE_MD_CAP/$SKILL_MD_CAP/$AGENT_MD_CAP'
→ caps=100/200/80

bash tests/run.sh 2>&1 | tail -3
→ PASS: 331    FAIL: 4
→ rc=1 (4 stubs for Plans 03+04 — expected)

Failures remaining (all stubs for future plans):
  ✗ lib/snapshot.sh not found — Wave 1 must create it first (SC-2)       [Plan 03]
  ✗ lib/inventory.sh not found — Wave 1 must create it first (INV-01..INV-04) [Plan 03]
  ✗ audit-setup.sh not yet updated — Plan 04 required to source lib/caps.sh (SC-5) [Plan 04]
  ✗ perf gate skipped — lib/inventory.sh not found (CR-7)               [Plan 03]

Phase 21 SC-5, ADOPT-03/SC-1, SAFE-03 tests: all ✓
Pre-existing tests: 0 regressions (was 315 pass before, unchanged)
```

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] shellcheck shell=bash directive required for sourced lib files**
- **Found during:** Task 1 verification
- **Issue:** shellcheck reports SC2148 ("Tips depend on target shell and yours is unknown. Add a shebang or a 'shell' directive.") for files without a shebang
- **Fix:** Added `# shellcheck shell=bash` as first line in lib/caps.sh and lib/log.sh
- **Files modified:** lib/caps.sh, lib/log.sh
- **Commit:** 9a46dbd

**2. [Rule 1 - Bug] CONJURE_HOME not exported to bash -c DRY_RUN test subshells**
- **Found during:** Task 1 verification (log.sh DRY_RUN=1 test); same bug in Task 2 (mutate_archive DRY_RUN=1 test)
- **Issue:** Test uses `bash -c '...'` with single-quoted string containing `$CONJURE_HOME`; since `CONJURE_HOME` is set but not exported in tests/run.sh, `bash -c` subshell sees empty `$CONJURE_HOME`, causing `/lib/mutate.sh: No such file or directory`
- **Fix:** Added `CONJURE_HOME="$CONJURE_HOME"` to env var injection prefix in both DRY_RUN test commands
- **Files modified:** tests/run.sh
- **Commits:** 9a46dbd (log.sh fix), 00cfc10 (mutate_archive fix)

**3. [Rule 1 - Bug] D-13 abort test scenario didn't produce genuine failure**
- **Found during:** Task 2 verification
- **Issue:** Test pre-populated archive dest with "corrupted content" then called mutate_archive. But `cp -a src dest` overwrites the pre-corrupted dest with src content, making hashes match — so mutate_archive succeeds (rc=0, src deleted), opposite of intended test behavior
- **Fix:** Changed test to use `chmod 555 archive_root` so mkdir -p inside the dest path fails, cp fails, mutate_archive returns 1 and preserves src — correctly testing D-13 guarantee
- **Files modified:** tests/run.sh
- **Commit:** 00cfc10

**4. [Rule 1 - Bug] docs/adr/.gitkeep missing — fixture audit exited rc=1**
- **Found during:** Task 2 overall test suite run
- **Issue:** Plan 01 created `tests/fixtures/brownfield-simple/docs/adr/` as an empty directory (deviation fix for audit-setup.sh warning). Git does not track empty directories, so after commit the directory wasn't present — audit-setup.sh emitted `⚠ docs/adr/ missing` (rc=1), failing the fixture audit test
- **Fix:** Added `tests/fixtures/brownfield-simple/docs/adr/.gitkeep` so git tracks the directory
- **Files modified:** tests/fixtures/brownfield-simple/docs/adr/.gitkeep
- **Commit:** 00cfc10

## Known Stubs

None — all three deliverables are fully wired with real behavior. No placeholder values or TODOs.

## Self-Check: PASSED

All created files found:
- `lib/caps.sh` — FOUND
- `lib/log.sh` — FOUND

All modified files verified:
- `lib/mutate.sh` — FOUND, contains `mutate_archive` — CONFIRMED
- `tests/run.sh` — FOUND, CONJURE_HOME fixes applied — CONFIRMED
- `tests/fixtures/brownfield-simple/docs/adr/.gitkeep` — FOUND

Commits verified:
- `9a46dbd`: feat(21-02): implement lib/caps.sh and lib/log.sh — FOUND
- `00cfc10`: feat(21-02): add mutate_archive to lib/mutate.sh and fix test infra — FOUND
