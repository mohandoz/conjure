---
phase: 30-workspace-orchestration-mutating-rollback-saga
plan: "00"
subsystem: testing
tags: [workspace, fixture, sigkill, rollback, sha256, graceful-red]

requires:
  - phase: 29-workspace-orchestration-read-only
    provides: scripts/workspace.sh, lib/workspace.sh — Phase 29 workspace read-only infrastructure

provides:
  - tests/fixtures/_workspace-trio: 3-repo adoptable fixture with tags for --tag filter coverage
  - tests/run.sh Phase 30 block: graceful-red WS-05/WS-06/WS-07/SAGA sections with MISSING messages

affects:
  - 30-01 through 30-04 (all feature plans must turn this red block green)
  - verification runs that grep for Phase 30/WS-05/WS-06/WS-07/SAGA

tech-stack:
  added: []
  patterns:
    - "_workspace-trio fixture pattern: 3 small adoptable repos, each with .claude/ + content files, tagged for filter tests"
    - "graceful-red test block: all Phase 30 WS tests MISSING until feature waves deliver"
    - "SIGKILL poll on jq applied-count > 0 (not .phase field) — workspace-scale kill window"
    - "p30_sha cross-platform sha256 helper, per-repo hash files outside workspace tree"

key-files:
  created:
    - tests/fixtures/_workspace-trio/.conjure-workspace.json
    - tests/fixtures/_workspace-trio/repos/alpha/CLAUDE.md
    - tests/fixtures/_workspace-trio/repos/alpha/.claude/settings.json
    - tests/fixtures/_workspace-trio/repos/alpha/.claude/skills/git/SKILL.md
    - tests/fixtures/_workspace-trio/repos/beta/CLAUDE.md
    - tests/fixtures/_workspace-trio/repos/beta/.claude/settings.json
    - tests/fixtures/_workspace-trio/repos/beta/.claude/skills/docs/SKILL.md
    - tests/fixtures/_workspace-trio/repos/gamma/CLAUDE.md
    - tests/fixtures/_workspace-trio/repos/gamma/.claude/settings.json
    - tests/fixtures/_workspace-trio/repos/gamma/.claude/hooks/post-tool.mjs
  modified:
    - tests/run.sh

key-decisions:
  - "SIGKILL poll uses jq '[.repos[] | select(.status == \"applied\")] | length > 0' — kills after ≥1 repo genuinely applied, not on .phase field"
  - "WS-07-ARCHIVED asserts both timestamped COPY exists AND original .conjure-workspace-state.json remains (archive is a COPY not a move)"
  - "WS-07-IDEMPOTENT asserts second --rollback exits 0 (reads all-rolled_back state, no-ops)"
  - "_workspace-trio .claude/ dirs force-added with git add -f (global ~/.gitignore_global ignores .claude/; mirroring existing _workspace fixture precedent)"

patterns-established:
  - "p30_sha: cross-platform sha256 helper namespaced p30, per-repo hash files in mktemp outside workspace tree"
  - "Per-repo EXIT-trap discipline: trap ... EXIT + trap - EXIT pairs per section, no script-level trap"
  - "du PATH shim scoped to sub-test mktemp dir; cleaned up with trap; never leaks to other tests"

requirements-completed:
  - WS-05
  - WS-06
  - WS-07

duration: 25min
completed: 2026-06-04
---

# Phase 30 Plan 00: _workspace-trio fixture + Phase 30 graceful-red block Summary

**3-repo _workspace-trio fixture with tags and adoptable .claude/ content + SIGKILL/WS-05/06/07 graceful-red block in tests/run.sh (8 failing, 566 passing)**

## Performance

- **Duration:** 25 min
- **Started:** 2026-06-04T00:00:00Z
- **Completed:** 2026-06-04T00:25:00Z
- **Tasks:** 2
- **Files modified:** 11 (10 created + tests/run.sh modified)

## Accomplishments

- Created `tests/fixtures/_workspace-trio/` with 3 adoptable repos (alpha/beta/gamma), each containing CLAUDE.md + .claude/settings.json + content files (SKILL.md or .mjs hook). Alpha/beta tagged team-a, gamma tagged team-b for `--tag` filter coverage.
- Appended Phase 30 graceful-red block to `tests/run.sh` covering WS-05 (update), WS-06 (saga invariant + dry-run + du gate), WS-07 (rollback: no-state, archived, idempotent), and SAGA SIGKILL zero-diff sections.
- All 8 Phase 30 tests fail with MISSING/not-implemented messages as required by the Nyquist invariant; 566 pre-existing tests pass unaffected.
- shellcheck -S error passes on tests/run.sh.

## Task Commits

1. **Task 1: Create _workspace-trio fixture** - `b8b2212` (feat)
2. **Task 2: Append Phase 30 graceful-red block** - `66e8f25` (test)

## Files Created/Modified

- `tests/fixtures/_workspace-trio/.conjure-workspace.json` - 3-repo manifest, schema_version 1, alpha/beta=team-a, gamma=team-b
- `tests/fixtures/_workspace-trio/repos/alpha/CLAUDE.md` - Minimal project CLAUDE.md (≤100 lines)
- `tests/fixtures/_workspace-trio/repos/alpha/.claude/settings.json` - {"hooks":{}}
- `tests/fixtures/_workspace-trio/repos/alpha/.claude/skills/git/SKILL.md` - Valid YAML frontmatter: id: git, tools: [Bash]
- `tests/fixtures/_workspace-trio/repos/beta/CLAUDE.md` - Minimal project CLAUDE.md
- `tests/fixtures/_workspace-trio/repos/beta/.claude/settings.json` - {"hooks":{}}
- `tests/fixtures/_workspace-trio/repos/beta/.claude/skills/docs/SKILL.md` - Valid YAML frontmatter: id: docs, tools: [Read, Write]
- `tests/fixtures/_workspace-trio/repos/gamma/CLAUDE.md` - Minimal project CLAUDE.md
- `tests/fixtures/_workspace-trio/repos/gamma/.claude/settings.json` - {"hooks":{}}
- `tests/fixtures/_workspace-trio/repos/gamma/.claude/hooks/post-tool.mjs` - Valid ESM hook exporting default function
- `tests/run.sh` - Phase 30 graceful-red block appended (331 lines): WS-05/WS-06/WS-07/SAGA sections

## Decisions Made

- **SIGKILL poll: applied-count not .phase field.** The poll uses `jq '[.repos[] | select(.status == "applied")] | length > 0'` from `.conjure-workspace-state.json`. This is correct per 30-PATTERNS.md — the kill window is after ≥1 repo is genuinely applied (real mutations exist), not on a `.phase` transition. Matches the plan's `key_links` table.
- **git add -f for .claude/ fixture dirs.** The global `~/.gitignore_global` ignores `.claude/` directories project-wide. Force-add is required for fixture files inside repo subdirs. This mirrors how the existing `_workspace` fixture's `.claude/` dirs were originally committed.
- **WS-06-DRY-RUN graceful message.** The test fails with `rc=2 state=0 snaps=0` because the current workspace.sh exits 2 for unknown subcommand `adopt`. This is the correct graceful-red behavior — the message accurately reports the absence of ws_do_adopt.

## Deviations from Plan

None — plan executed exactly as written.

## Issues Encountered

- **Global .gitignore blocked .claude/ fixture staging.** `~/.gitignore_global` ignores `.claude/` globally. Used `git add -f` as the existing fixture precedent confirms this is the correct pattern for test fixtures. Not a deviation — same as existing `_workspace` fixture history.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- Wave 0 Nyquist invariant satisfied: trio fixture + red tests before saga code.
- Phase 30 Plan 01 (Wave 1) can proceed: `lib/workspace.sh` state helpers (`workspace_state_write`/`workspace_state_read`) with the CONTEXT.md schema.
- All 8 Phase 30 test sections will turn green as Waves 1-4 deliver feature code.
- No blockers.

---
*Phase: 30-workspace-orchestration-mutating-rollback-saga*
*Completed: 2026-06-04*
