---
phase: 01-pre-flight-cross-platform-hooks
plan: 02
subsystem: testing
tags: [bash, hooks, node, cross-platform, windows, settings-json, safe-03]

# Dependency graph
requires:
  - phase: 01-01
    provides: scripts/preflight.sh (standalone dep checker; gate for conjure init/audit)
provides:
  - templates/settings.json.tmpl: 5 node .mjs hook commands (no bash commands, no arg strings)
  - scripts/init-project.sh: hook copy loop sourcing templates/hooks-nodejs/*.mjs without chmod
  - scripts/audit-setup.sh: .mjs file-existence check replacing .sh executable-bit check
  - tests/run.sh: 4-assertion template lint section catching SAFE-03 regressions
affects: [phase-02, phase-03, phase-04, phase-07]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "node .claude/hooks/*.mjs command strings in settings.json — no arg strings, no shell expansion"
    - "File-existence check (-f) for .mjs hooks in audit; executable-bit check (-x) only for .sh scripts"
    - "Template lint assertions: grep-based negative/positive checks for regression prevention"

key-files:
  created: []
  modified:
    - templates/settings.json.tmpl
    - scripts/init-project.sh
    - scripts/audit-setup.sh
    - tests/run.sh

key-decisions:
  - "D-01 enforced: node .mjs commands used universally — no OS branching in settings template"
  - "D-02 enforced: relative paths (node .claude/hooks/foo.mjs) — matches Claude Code project-root execution"
  - "No arg strings in node commands — hooks read process.env directly (RESEARCH.md Pitfall 3)"
  - "pre-commit-quality-gate.mjs wired as second PreToolUse[Bash] hook (gates itself internally)"
  - "chmod removed from hook copy loop — .mjs files invoked via node, not as executables"

patterns-established:
  - "Template lint section in tests/run.sh: four grep assertions protect against SAFE-03 regression"
  - "backup-before-mutate: cp file file.bak before edit, rm bak after jq-validated success"
  - ".mjs hooks checked with -f (file existence) not -x (executable bit) in audit"

requirements-completed: [SAFE-03]

# Metrics
duration: 2min
completed: 2026-05-24
---

# Phase 01 Plan 02: Node Hook Wiring Summary

**Replaced all bash .claude/hooks/*.sh commands with 5 node .claude/hooks/*.mjs commands in the settings template, updated the init hook copy loop to source hooks-nodejs/*.mjs without chmod, updated audit to check .mjs file existence, and added 4 template lint assertions to the test suite**

## Performance

- **Duration:** 2 min
- **Started:** 2026-05-24T18:57:11Z
- **Completed:** 2026-05-24T18:59:11Z
- **Tasks:** 2
- **Files modified:** 4 (templates/settings.json.tmpl, scripts/init-project.sh, scripts/audit-setup.sh, tests/run.sh)

## Accomplishments
- Replaced 4 bash hook commands with 5 node hook commands in templates/settings.json.tmpl (adds pre-commit-quality-gate.mjs as second PreToolUse[Bash] hook)
- Removed shell arg expansion ($CLAUDE_FILE_PATH, $CLAUDE_COMMAND) from hook command strings — node hooks read process.env directly
- Updated scripts/init-project.sh hook copy loop from templates/hooks/*.sh (with chmod) to templates/hooks-nodejs/*.mjs (no chmod)
- Updated scripts/audit-setup.sh to check .mjs file existence instead of .sh executable bit
- Added "Template lint" section to tests/run.sh with 4 SAFE-03 regression guards; test count 117 → 121

## Task Commits

Each task was committed atomically:

1. **Task 1: Update templates/settings.json.tmpl and scripts/init-project.sh** - `151fee8` (feat)
2. **Task 2: Update scripts/audit-setup.sh + add template lint to tests/run.sh** - `7a53eb9` (feat)

**Plan metadata:** (docs commit — see below)

## Files Created/Modified
- `templates/settings.json.tmpl` - All 4 bash hook commands replaced with 5 node hook commands; PreToolUse[Bash] gains second hook (pre-commit-quality-gate.mjs); no arg strings
- `scripts/init-project.sh` - Hook copy loop updated from templates/hooks/*.sh (+ chmod) to templates/hooks-nodejs/*.mjs (no chmod); idempotency guard preserved
- `scripts/audit-setup.sh` - Hook check updated from *.sh -x (executable bit) to *.mjs -f (file existence); error message updated from "chmod +x" to "re-run conjure init"
- `tests/run.sh` - New "Template lint" section with 4 assertions: no bash hooks, node hooks present, sources hooks-nodejs, no chmod on hook files

## Decisions Made
- Removed "chmod" from audit-setup.sh comment text to satisfy acceptance criteria (grep -q "chmod" must return false — no references at all, including in comments)
- Followed RESEARCH.md Pitfall 3 strictly: no arg strings in node hook commands; hooks read process.env.CLAUDE_FILE_PATH etc. directly

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Removed "chmod" from comment text in audit-setup.sh**
- **Found during:** Task 2 (scripts/audit-setup.sh)
- **Issue:** Comment read "invoked via node, no chmod needed" — the word "chmod" in the comment caused acceptance criteria `grep -q "chmod" scripts/audit-setup.sh` to return true (FAIL)
- **Fix:** Changed comment to "invoked via node, not as executables" — functionally equivalent, no chmod reference
- **Files modified:** scripts/audit-setup.sh
- **Verification:** `grep -q "chmod" scripts/audit-setup.sh` returns false; `bash tests/run.sh` exits 0
- **Committed in:** `7a53eb9` (Task 2 commit)

---

**Total deviations:** 1 auto-fixed (Rule 1 - bug)
**Impact on plan:** Minor comment wording adjustment to satisfy acceptance criteria. No functional change.

## Issues Encountered
None beyond the comment wording deviation documented above.

## Threat Model Verification
- T-02-01 (Tampered invalid JSON): jq empty validates before backup removal; test suite includes JSON validity test
- T-02-02 (Hooks silent no-op on Windows): Fixed — bash commands fully replaced with node commands
- T-02-03 (init-project copies .sh while settings expects .mjs): Fixed — copy loop now sources hooks-nodejs/*.mjs; template lint assertion enforces this
- T-02-04 (chmod +x on .mjs hook): Mitigated — no chmod in init-project.sh hook block; template lint assertion enforces absence
- T-02-05 (arg-passing shell expansion): Mitigated — no arg strings in any node hook commands
- T-02-SC (npm installs): Phase installs zero new packages; dependencies: {} remains empty

## Stub Scan
No stubs detected. All changes are structural (command strings and file patterns). No UI components, no hardcoded empty values.

## Threat Flags
None. This change reduces attack surface (removes shell arg expansion from hook commands). No new network endpoints, auth paths, or schema changes introduced.

## Next Phase Readiness
- All five node .mjs hooks are now wired in the settings template — Phase 1 SAFE-03 fix complete
- Template lint assertions in tests/run.sh will catch any future regression back to bash hooks
- All 121 tests green
- Phase 2 (lib/mutate.sh + dry-run fix) can proceed with full confidence in hook wiring

## Self-Check: PASSED
- templates/settings.json.tmpl: 0 bash hooks, 5 node hooks (verified via grep counts)
- scripts/init-project.sh: hooks-nodejs present, no chmod, no templates/hooks/ (verified)
- scripts/audit-setup.sh: *.mjs find pattern, -f check, no chmod reference (verified)
- tests/run.sh: 4 template lint assertions, all pass in bash tests/run.sh (121 pass, 0 fail)
- Task 1 commit: 151fee8 (verified in git log)
- Task 2 commit: 7a53eb9 (verified in git log)

---
*Phase: 01-pre-flight-cross-platform-hooks*
*Completed: 2026-05-24*
