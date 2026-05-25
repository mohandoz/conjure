---
phase: 10-marketplace-publish
plan: "04"
subsystem: publish-regression-tests
tags: [marketplace, publish, testing, mktpl, regression, sandbox]
dependency_graph:
  requires: [publish-plugin-sh, ci-marketplace-validation]
  provides: [mktpl-regression-coverage]
  affects: [tests/run.sh]
tech_stack:
  added: []
  patterns: [script-copy-sandbox-isolation, mktemp-isolation, pass-fail-inline-tests]
key_files:
  created: []
  modified:
    - tests/run.sh
decisions:
  - "Script-copy sandbox isolation used instead of env-var CONJURE_HOME override — publish-plugin.sh derives CONJURE_HOME from script path (not env), so env-var override does not work; copying scripts into mktemp sandbox gives correct isolation"
  - "MKTPL-04 tested with CONJURE_SUBMIT=1 env var (not --submit flag) — matches how cmd_publish calls the worker"
metrics:
  duration: "2m"
  completed: "2026-05-25"
  tasks_completed: 1
  tasks_total: 1
---

# Phase 10 Plan 04: MKTPL Regression Tests Summary

**One-liner:** Appended 10 MKTPL regression assertions to tests/run.sh covering dry-run isolation, dirty-tree abort, version/SHA update, version-consistency drift detection, and submit-entry writing (MKTPL-01, -02, -04).

## What Was Built

### tests/run.sh (extended, +133 lines)

A new "Marketplace publish tests (MKTPL-01 through MKTPL-04)" section appended after the 3-way merge tests and before the summary block.

**Sandbox isolation strategy (deviation from plan):** The plan's test template used `CONJURE_HOME="$MKTPL_DIR" bash "$CONJURE_HOME/scripts/publish-plugin.sh"`. This does not work because `publish-plugin.sh` line 17 overwrites `CONJURE_HOME` by self-resolving: `CONJURE_HOME="$(cd "$(dirname "$0")/.." && pwd)"`. The env var is ignored. The correct approach copies `scripts/publish-plugin.sh` and `lib/mutate.sh` into each mktemp sandbox and invokes the sandbox copy. This gives correct CONJURE_HOME resolution pointing to the isolated temp dir.

**Tests implemented:**

1. **MKTPL-01 dry-run** — `DRY_RUN=1 bash "$MKTPL_DIR/scripts/publish-plugin.sh"`: output contains `[dry-run]`, sandbox `marketplace.json` is byte-for-byte identical to the original copy (no mutation).

2. **MKTPL-01 dirty-tree abort** — Appends `dirty` to `plugin.json` without committing, runs the script, verifies exit code 2. Then `git checkout -- .claude-plugin/plugin.json` restores the file.

3. **MKTPL-01 version update** — Live run (no DRY_RUN) in clean sandbox verifies `.plugins[0].version` in `marketplace.json` matches the `VERSION` file.

4. **MKTPL-01 SHA update** — Same live run verifies `.plugins[0].source.sha` is a 40-character lowercase hex string.

5. **MKTPL-02 version-consistency pass** — Inline bash check reads `VERSION`, `marketplace.json .plugins[0].version`, and `plugin.json .version` from the real repo; asserts all three are equal.

6. **MKTPL-02 version-consistency fail** — Creates a temp dir with `marketplace.json` patched to version `0.0.0` and `VERSION` set to `9.9.9`; verifies the drift is detectable (values differ).

7. **MKTPL-04 submit-entry written** — Fresh sandbox with `CONJURE_SUBMIT=1`; verifies `$SUBMIT_DIR/.claude-plugin/submit-entry.json` exists after the run.

8. **MKTPL-04 submit-entry fields** — `jq -e` assertions for `.name`, `.source`, `.homepage` in `submit-entry.json`.

9. **MKTPL-04 stdout checklist URL** — Verifies `SUBMIT_OUT` contains `claude.ai/settings/plugins/submit`.

10. (Combined: dry-run also covers "no modify marketplace.json" as a separate assertion.)

**Test count:** 217 → 227 assertions, 0 failures.

## Verification Results

| Check | Result |
|-------|--------|
| `bash tests/run.sh` exits 0 | PASS |
| 0 FAIL in output | PASS |
| 10 MKTPL assertions all show ✓ | PASS |
| No temp directories left after run | PASS (each sandbox has `rm -rf` cleanup) |
| Real `.claude-plugin/` untouched by tests | PASS (script-copy isolation) |
| Version-consistency drift detected | PASS |
| MKTPL section header present | PASS |

## Commits

| Task | Description | Hash |
|------|-------------|------|
| Task 1 | Add MKTPL inline tests to tests/run.sh | 16896fc |

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Script-copy sandbox isolation instead of env-var CONJURE_HOME override**

- **Found during:** Task 1 implementation
- **Issue:** The plan's test template passes `CONJURE_HOME="$MKTPL_DIR"` as an env var to `bash scripts/publish-plugin.sh`. However, `publish-plugin.sh` line 17 immediately overwrites `CONJURE_HOME` by self-resolving its own path: `CONJURE_HOME="$(cd "$(dirname "$0")/.." && pwd)"`. The env var is silently ignored. Additionally, the real repo has uncommitted changes (planning artifact deletions), which would cause the dirty-tree guard to fire on every test against the real `CONJURE_HOME`.
- **Fix:** Copy `scripts/publish-plugin.sh` and `lib/mutate.sh` into each mktemp sandbox and invoke the sandbox copy. The sandbox copy self-resolves `CONJURE_HOME` to the sandbox root, giving correct isolation.
- **Files modified:** tests/run.sh (implementation inline)
- **Commit:** 16896fc

## Known Stubs

None. All tests run against the live `publish-plugin.sh` implementation with real git operations.

## Threat Flags

No new threat surface. All test mutations happen inside `mktemp -d` sandboxes; `rm -rf` cleanup runs after each sandbox block. The real `.claude-plugin/` directory is never written to by the tests.

## Self-Check: PASSED

- [x] `tests/run.sh` modified (133 lines added)
- [x] `bash tests/run.sh` exits 0 with 227 PASS, 0 FAIL
- [x] MKTPL section header "Marketplace publish tests (MKTPL-01 through MKTPL-04)" present in tests/run.sh
- [x] All 10 MKTPL assertions show ✓ in test output
- [x] Commit 16896fc exists (`feat(10-04): add MKTPL regression tests to tests/run.sh`)
- [x] No temp directories left after test run
- [x] Real `.claude-plugin/` directory untouched
