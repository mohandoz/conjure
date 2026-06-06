---
phase: 26-sandbox-managed-settings-mdm
plan: "00"
subsystem: test-infrastructure
tags: [wave-0, fixtures, graceful-red, policy, sandbox, mdm]
dependency_graph:
  requires: []
  provides:
    - tests/fixtures/_emit-policy/ (golden harness + expected artifact goldens)
    - tests/fixtures/_emit-policy-broken/ (negative fixture for POL-05c)
    - tests/fixtures/_emit-policy-unreviewed/ (advisory fixture for POL-05-advisory)
    - Phase 26 POL-* test block in tests/run.sh (graceful-red until Wave 1)
  affects:
    - tests/run.sh (FAIL count +12, PASS unchanged at 485)
tech_stack:
  added: []
  patterns:
    - mktemp+EXIT-trap test sandbox discipline (mirrors Phase 25 PLUG-* pattern)
    - P26_EMIT_OK presence guard (graceful-red when scripts/emit-policy.sh absent)
    - POL-05-advisory pattern: go-gin audit-clean base + unreviewed fixture overlay
key_files:
  created:
    - tests/fixtures/_emit-policy/harness/CLAUDE.md
    - tests/fixtures/_emit-policy/harness/.claude/settings.json
    - tests/fixtures/_emit-policy/harness/.conjure-version
    - tests/fixtures/_emit-policy/expected-sandbox.json
    - tests/fixtures/_emit-policy/expected-managed-settings.json
    - tests/fixtures/_emit-policy/expected-plist.xml
    - tests/fixtures/_emit-policy/expected-policy.ps1
    - tests/fixtures/_emit-policy-broken/harness/.claude/settings.json
    - tests/fixtures/_emit-policy-unreviewed/conjure-policy/managed-settings.json
  modified:
    - tests/run.sh (Phase 26 POL-* block appended, 306 lines)
decisions:
  - "harness/.claude/settings.json has hooks block but no sandbox block — emit-policy must create it (Nyquist Wave 0 invariant)"
  - "negative fixture uses boolean true (not any other value) matching RESEARCH.md Pitfall 1 exact case"
  - "_emit-policy-unreviewed fixture has no _conjure_unreviewed key — mirrors real emit-policy output per Open Questions RESOLVED Q1"
  - "expected-policy.ps1 uses $env:ProgramFiles (not ProgramData) — deprecated path never emitted"
  - "POL-05-advisory test uses go-gin base (audit-clean) + managed-settings overlay so advisory text fires without hard-fail noise"
  - "All fixture dirs are _-prefixed so generic audit/golden loops exclude them per CLAUDE.md conventions"
  - "Force-added harness/.claude/settings.json and negative fixture settings.json (git add -f) because ~/.claude/ is in global .gitignore_global"
metrics:
  duration: "556s (~9 min)"
  tasks_completed: 2
  files_created: 9
  files_modified: 1
  completed: "2026-06-03T09:13:18Z"
---

# Phase 26 Plan 00: Wave 0 — Fixture Harness + Graceful-Red Test Block Summary

Wave 0 test infrastructure for Phase 26 sandbox/managed-settings/MDM emission — golden fixture harness, expected artifact goldens, negative + advisory fixtures, and 12 POL-* graceful-red test cases in tests/run.sh.

## What Was Built

**Task 1: Golden fixture harness and expected output files** — Three fixture trees under `tests/fixtures/`:

- `tests/fixtures/_emit-policy/harness/`: minimal CLAUDE.md (with `<!-- compliance:hipaa -->` marker), `.claude/settings.json` (hooks only, no sandbox block), `.conjure-version` (0.7.0).
- `tests/fixtures/_emit-policy/expected-sandbox.json`: hipaa sandbox block with baseline + PHI denyRead/denyWrite paths, empty `allowedDomains`.
- `tests/fixtures/_emit-policy/expected-managed-settings.json`: `disableBypassPermissionsMode` as STRING `"disable"`, `allowManagedPermissionRulesOnly: true`, `forceLoginOrgUUID: "REPLACE_WITH_ORG_UUID"`.
- `tests/fixtures/_emit-policy/expected-plist.xml`: macOS plist with `<string>disable</string>` (not `<true/>`).
- `tests/fixtures/_emit-policy/expected-policy.ps1`: Windows ps1 using `$env:ProgramFiles` (no deprecated `ProgramData`).
- `tests/fixtures/_emit-policy-broken/harness/.claude/settings.json`: `disableBypassPermissionsMode: true` (boolean) — negative fixture for POL-05c.
- `tests/fixtures/_emit-policy-unreviewed/conjure-policy/managed-settings.json`: `REPLACE_WITH_ORG_UUID` present, no `_conjure_unreviewed` key (mirrors real emit output per RESEARCH.md Open Questions RESOLVED Q1) — advisory fixture for POL-05-advisory.

**Task 2: Phase 26 graceful-red test block** — 306 lines added to `tests/run.sh` immediately before the GH_HIDE_STUBS cleanup loop. All 12 POL-* test cases present (POL-01, POL-01-idem, POL-02, POL-03, POL-03-type, POL-04-macos, POL-04-win, POL-05a, POL-05b, POL-05c, POL-05-advisory, POL-dryrun). All guarded by `P26_EMIT_OK` presence guard.

## Verification Results

```
PASS: 485    FAIL: 12
```

- Pre-existing 485 tests still pass (no regression)
- 12 POL-* tests fail with graceful-red messages ("emit-policy.sh not found — Wave 1 must create scripts/emit-policy.sh")
- `shellcheck -S error -e SC2164,SC2044,SC2034,SC2155 tests/run.sh` exits 0

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing] Force-added .claude/ fixture files bypassing global gitignore**
- **Found during:** Task 1 commit
- **Issue:** The global `~/.gitignore_global` ignores `.claude/` directories. `tests/fixtures/_emit-policy/harness/.claude/settings.json` and `tests/fixtures/_emit-policy-broken/harness/.claude/settings.json` were not tracked by git.
- **Fix:** Used `git add -f` for both fixture `.claude/settings.json` files to force-include them in the repository despite the global gitignore.
- **Files modified:** Both settings.json files in fixture `.claude/` dirs
- **Commit:** 28160cc

None beyond the above auto-fix.

## Commits

| Hash | Description |
|------|-------------|
| 28160cc | feat(26-00): add golden fixture harness and expected output files |
| fa5a013 | feat(26-00): add Phase 26 graceful-red test block to tests/run.sh |

## Known Stubs

None — all fixture files are complete static data; no dynamic wiring required in Wave 0.

## Threat Flags

None — fixture files are static, team-authored test data. No new network endpoints, auth paths, or schema changes at trust boundaries. The `REPLACE_WITH_ORG_UUID` placeholder in `_emit-policy-unreviewed/conjure-policy/managed-settings.json` is a clearly fake value (self-evidently fails Claude login validation) — T-26-W0-01 mitigated per threat register.

## Self-Check: PASSED

All fixture files exist with correct shapes (jq type-checks pass, grep assertions pass). All 12 POL-* tags present in tests/run.sh. Commits 28160cc and fa5a013 exist in git log.
