---
phase: 29
plan: "00"
subsystem: workspace
tags: [workspace, fixtures, tdd, graceful-red, test-infrastructure]
dependency_graph:
  requires: []
  provides:
    - tests/fixtures/_workspace/ (3 good repos + gamma-bad audit-fail variant)
    - tests/fixtures/_workspace-badpath/ (bad-path manifest)
    - Phase 29 graceful-red WS test block in tests/run.sh
  affects:
    - tests/run.sh (11 WS-* test stubs added)
tech_stack:
  added: []
  patterns:
    - POSIX bash 3.2+ fixture construction
    - Nyquist Wave 0: tests before implementation
    - mktemp + trap EXIT discipline
    - chmod 000 with trap-restore for unreadable-repo simulation
key_files:
  created:
    - tests/fixtures/_workspace/repos/alpha/CLAUDE.md
    - tests/fixtures/_workspace/repos/alpha/.claude/settings.json
    - tests/fixtures/_workspace/repos/beta/CLAUDE.md
    - tests/fixtures/_workspace/repos/beta/.claude/settings.json
    - tests/fixtures/_workspace/repos/gamma/CLAUDE.md
    - tests/fixtures/_workspace/repos/gamma/.claude/settings.json
    - tests/fixtures/_workspace/repos/gamma-bad/CLAUDE.md
    - tests/fixtures/_workspace/repos/gamma-bad/.claude/settings.json
    - tests/fixtures/_workspace/.conjure-workspace.json
    - tests/fixtures/_workspace-badpath/.conjure-workspace.json
  modified:
    - tests/run.sh (Phase 29 WS block: 259 lines added)
decisions:
  - "gamma-bad settings.json uses only top-level disableBypassPermissionsMode:true (not nested permissions.disableBypassPermissionsMode) — matches the SCHM-02 check trigger pattern"
  - "_workspace-badpath/ manifest references alpha/beta via ../workspace/repos relative traversal so the paths resolve without copying fixtures; nonexistent-repo path stays invalid"
  - "settings.json files force-added with git add -f because .claude/ appears in global gitignore; this is a project fixture not user config"
  - "WS-04-audit-failfast test places gamma-bad first in the manifest so --fail-fast fires before alpha is processed — avoiding false passes"
metrics:
  duration: "~8 minutes"
  completed_date: "2026-06-03"
  tasks_completed: 2
  files_created: 10
  files_modified: 1
---

# Phase 29 Plan 00: Workspace Fixture Trees + Graceful-Red WS Test Block Summary

Wave 0 workspace fixture trees and all 11 WS-01..04 graceful-red test stubs wired in tests/run.sh before lib/workspace.sh and scripts/workspace.sh exist.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Create workspace fixture trees | dbdbae6, fc88a3d | 10 files created under tests/fixtures/_workspace/ and tests/fixtures/_workspace-badpath/ |
| 2 | Add Phase 29 graceful-red WS test block | b08e017 | tests/run.sh (+259 lines) |

## Fixture Tree

```
tests/fixtures/_workspace/
  .conjure-workspace.json       — valid manifest (alpha, beta, gamma by relative path)
  repos/
    alpha/CLAUDE.md + .claude/settings.json  — {"hooks":{}}  — passes audit
    beta/CLAUDE.md  + .claude/settings.json  — {"hooks":{}}  — passes audit
    gamma/CLAUDE.md + .claude/settings.json  — {"hooks":{}}  — passes audit
    gamma-bad/CLAUDE.md + .claude/settings.json — {"disableBypassPermissionsMode":true} — triggers audit fail

tests/fixtures/_workspace-badpath/
  .conjure-workspace.json       — bad-path manifest (alpha, beta valid + nonexistent-repo invalid)
```

## Test Results

- Pre-existing tests: PASS 541 FAIL 0 (unchanged baseline)
- After Wave 0: PASS 541 FAIL 11 (all WS-* graceful-red)
- shellcheck -S error -e SC2164,SC2044,SC2034,SC2155 tests/run.sh: PASS

## WS Test Stubs (all graceful-red)

| Tag | Guarded by | Correct failure message |
|-----|-----------|------------------------|
| WS-01-manifest-valid | P29_WS_LIB_OK | "lib/workspace.sh not implemented — Wave 1 must create it" |
| WS-01-manifest-invalid | P29_WS_LIB_OK | "lib/workspace.sh not implemented — Wave 1 must create it" |
| WS-02-init-writes | P29_WS_SH_OK | "scripts/workspace.sh not implemented — Wave 1 must create it" |
| WS-02-init-no-tty | P29_WS_SH_OK | "scripts/workspace.sh not implemented — Wave 1 must create it" |
| WS-03-check-table | P29_WS_SH_OK | "scripts/workspace.sh not implemented — Wave 1 must create it" |
| WS-03-check-fail-tolerant | P29_WS_SH_OK | "scripts/workspace.sh not implemented — Wave 1 must create it" |
| WS-03-check-badpath | P29_WS_SH_OK | "scripts/workspace.sh not implemented — Wave 1 must create it" |
| WS-04-audit-pass | P29_WS_SH_OK | "scripts/workspace.sh not implemented — Wave 2 must create it" |
| WS-04-audit-fail | P29_WS_SH_OK | "scripts/workspace.sh not implemented — Wave 2 must create it" |
| WS-04-audit-failfast | P29_WS_SH_OK | "scripts/workspace.sh not implemented — Wave 2 must create it" |
| WS-04-audit-badpath | P29_WS_SH_OK | "scripts/workspace.sh not implemented — Wave 2 must create it" |

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing functionality] settings.json files needed force-add**
- **Found during:** Task 1 commit
- **Issue:** Global gitignore excludes `.claude/` directories; `git add tests/fixtures/_workspace` silently omitted all settings.json files
- **Fix:** Followed up with `git add -f` on all four settings.json fixture files in a second commit (fc88a3d)
- **Files modified:** tests/fixtures/_workspace/repos/{alpha,beta,gamma,gamma-bad}/.claude/settings.json
- **Commit:** fc88a3d

## Known Stubs

None — this plan only adds fixture files and test stubs; no application logic.

## Threat Flags

None — no new network endpoints, auth paths, or trust boundary changes introduced. Fixture files contain only synthetic minimal content.

## Self-Check: PASSED

All files exist:
- tests/fixtures/_workspace/.conjure-workspace.json: FOUND
- tests/fixtures/_workspace-badpath/.conjure-workspace.json: FOUND
- tests/fixtures/_workspace/repos/gamma-bad/.claude/settings.json: FOUND
- tests/run.sh (Phase 29 block): FOUND

All commits exist:
- dbdbae6: FOUND
- fc88a3d: FOUND
- b08e017: FOUND
