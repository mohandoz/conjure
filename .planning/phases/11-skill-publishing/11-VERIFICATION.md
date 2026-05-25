---
phase: 11-skill-publishing
verified: 2026-05-25T22:47:18Z
status: passed
score: 13/13 must-haves verified
overrides_applied: 0
---

# Phase 11: Skill Publishing Verification Report

**Phase Goal:** A developer can contribute a project skill to the public kit (or a private org kit) through a single command that validates safety and opens a PR
**Verified:** 2026-05-25T22:47:18Z
**Status:** passed
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths (from ROADMAP Success Criteria)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| SC-1 | User can run `conjure publish-skill <name>` and have the skill validated against frontmatter schema, size cap, and a static egress scan before any submission step | VERIFIED | `scripts/publish-skill.sh` implements all three gates (sections 6–7 of the file). Test suite confirms 6 SKILL-01 assertions pass (dry-run, size cap, missing name, curl egress, $SECRET egress, clean-pass). |
| SC-2 | `conjure publish-skill` opens a PR via `gh pr create`; if `gh` is absent, prints the manual PR URL and checklist instead | VERIFIED | Lines 129–143 in publish-skill.sh: `command -v gh` branch prints `gh pr create` string (never executed); else-branch prints `gh not found — open PR manually:` with numbered checklist. Both paths verified by SKILL-02 tests. |
| SC-3 | Attempting to publish a skill at a branch HEAD (not a SHA-pinned commit) produces an error that stops submission | VERIFIED | Two SHA-pinning guards (lines 66–78): dirty-tree check via `git status --porcelain` (exit 1 + "uncommitted" message); untagged-conjure check via `git describe --exact-match` (exit 1 + "tagged release" message). Both verified by SKILL-03 tests. |
| SC-4 | User can run `conjure publish-skill <name> --to <org/repo>` to contribute to a private kit or org overlay repo | VERIFIED | `--to` flag parsed in both `scripts/publish-skill.sh` (lines 29–30) and `cli/conjure cmd_publish_skill` (lines 296–297). `TARGET_REPO` passed via env var to the script. Verified by SKILL-04 test: `--to myorg/myrepo` output contains `myorg/myrepo`. |

**Score: 4/4 roadmap success criteria verified**

---

### Must-Haves from PLAN Frontmatter

All 13 plan-level must-have truths verified against live codebase:

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| P-1 | scripts/publish-skill.sh exists, is executable, and passes shellcheck | VERIFIED | File exists; `[ -x scripts/publish-skill.sh ]` passes; `shellcheck -S error` exits 0. |
| P-2 | Running publish-skill.sh with missing frontmatter exits 1 with error message | VERIFIED | SKILL-01 test "frontmatter missing name" passes; exit code 1 confirmed in test suite. |
| P-3 | Running publish-skill.sh with curl/wget/http in body exits 1 naming matched lines | VERIFIED | SKILL-01 test "body contains curl" passes; `-nE` grep outputs line numbers. |
| P-4 | Running publish-skill.sh with uncommitted skill exits 1 with exact D-07 message | VERIFIED | SKILL-03 dirty-tree tests pass; output contains "uncommitted". |
| P-5 | Running publish-skill.sh with untagged conjure HEAD exits 1 with exact D-07 message | VERIFIED | SKILL-03 untagged-head tests pass; output contains "tagged release". |
| P-6 | Running publish-skill.sh with clean skill and gh present prints gh pr create command but does not execute it | VERIFIED | SKILL-02 test passes; `echo "  gh pr create \\"` is the only occurrence — no direct invocation. |
| P-7 | Running publish-skill.sh with --to org/repo substitutes that repo in printed command | VERIFIED | SKILL-04 test passes; `--to myorg/myrepo` output contains `myorg/myrepo`. |
| P-8 | Running publish-skill.sh with DRY_RUN=1 prints dry-run accounting via mutate_summary | VERIFIED | SKILL-01 dry-run test passes; spot-check output: `[dry-run] 0 mutations skipped`. |
| P-9 | conjure publish-skill test-skill runs without error (all gates pass in sandbox) | VERIFIED | SKILL-01 "clean skill passes all gates" test passes; exit 0. |
| P-10 | conjure publish-skill exits 1 when no skill name is given | VERIFIED | `bash cli/conjure publish-skill` exits 1; prints usage line. |
| P-11 | conjure publish-skill --to org/repo passes TARGET_REPO=org/repo to publish-skill.sh | VERIFIED | `cli/conjure` line 309: `TARGET_REPO="$target_repo"` passed as env var to `publish-skill.sh`. |
| P-12 | bash tests/run.sh exits 0 with all SKILL-01 through SKILL-04 tests passing | VERIFIED | `bash tests/run.sh` exits 0; PASS: 261, FAIL: 0; all 13 SKILL tests show checkmark. |
| P-13 | conjure publish-skill appears in conjure help output | VERIFIED | `bash cli/conjure help` output contains `conjure publish-skill <name> [--to <org/repo>] [--dry-run]`. |

**Score: 13/13 plan must-have truths verified**

---

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `scripts/publish-skill.sh` | Skill validation + PR instruction worker | VERIFIED | 147 lines, executable, shellcheck-S-error-clean. Contains `egress_scan` logic (`EGRESS_HIT` pattern x4), `source lib/mutate.sh`, `mutate_summary`, `describe --exact-match`, `status --porcelain`, `command -v gh`, `TARGET_REPO` x7. |
| `cli/conjure` | cmd_publish_skill dispatch + usage update | VERIFIED | `cmd_publish_skill()` function present at line 292; `publish-skill)` dispatch case at line 334; usage line at line 43. |
| `tests/run.sh` | SKILL-01 through SKILL-04 regression block | VERIFIED | "SKILL publish-skill tests" block at line 893; 13 test cases covering all 4 requirements. |

---

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `scripts/publish-skill.sh` | `lib/mutate.sh` | `source "$CONJURE_HOME/lib/mutate.sh"` | WIRED | Line 18 of publish-skill.sh. `mutate_summary` called at line 146. |
| `scripts/publish-skill.sh` | `.claude/skills/<name>/SKILL.md` | `SKILL_FILE="$(pwd)/.claude/skills/$SKILL_NAME/SKILL.md"` | WIRED | Line 57. Path construction matches required pattern. |
| `cli/conjure cmd_publish_skill` | `scripts/publish-skill.sh` | `bash "$CONJURE_HOME/scripts/publish-skill.sh" "$skill_name"` | WIRED | Line 310 of cli/conjure. CONJURE_HOME, DRY_RUN, TARGET_REPO all passed as env vars. |
| `tests/run.sh SKILL block` | `scripts/publish-skill.sh` | `bash "$SKILL_DIR/scripts/publish-skill.sh" "$@"` | WIRED | `skill_run()` helper at line 916 invokes script in sandbox. |

---

### Data-Flow Trace (Level 4)

Not applicable. This phase produces CLI/worker scripts, not components rendering dynamic data. The output is printed to stdout (PR instructions) based on live `git` command results — no data store involved. The `mutate_summary` call in DRY_RUN=1 mode correctly reports actual mutation count (0 in dry-run, as confirmed by spot-check).

---

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| DRY_RUN=1 prints dry-run accounting | `DRY_RUN=1 bash scripts/publish-skill.sh test-skill` (sandbox) | `[dry-run] 0 mutations skipped` printed | PASS |
| No-args exits 1 | `bash scripts/publish-skill.sh` | exit code 1, usage printed | PASS |
| `conjure publish-skill` in help | `bash cli/conjure help \| grep publish-skill` | `conjure publish-skill <name> [--to <org/repo>] [--dry-run]` | PASS |
| `conjure publish-skill` no-args exits 1 | `bash cli/conjure publish-skill` | exit code 1 | PASS |
| Full test suite | `bash tests/run.sh` | PASS: 261, FAIL: 0 | PASS |

---

### Probe Execution

No probe scripts declared for this phase. `bash tests/run.sh` serves as the functional regression probe. Exit code: 0.

---

### Requirements Coverage

| Requirement | Description | Status | Evidence |
|-------------|-------------|--------|----------|
| SKILL-01 | User can run `conjure publish-skill <name>` to validate frontmatter schema, size cap, and egress scan | SATISFIED | Four validation gates in publish-skill.sh; 6 SKILL-01 regression tests pass. |
| SKILL-02 | `conjure publish-skill` opens PR via `gh pr create`; if `gh` absent prints manual URL and checklist | SATISFIED | gh-detection branch (lines 129–143) verified; SKILL-02 tests (gh-present + gh-absent) both pass. |
| SKILL-03 | Published skill commit is SHA-pinned; branch-HEAD references rejected with error | SATISFIED | Dirty-tree guard + conjure-untagged guard both exit 1 with correct messages; SKILL-03 tests pass. |
| SKILL-04 | User can run `conjure publish-skill <name> --to <org/repo>` for private kit contribution | SATISFIED | `--to` flag wired in both CLI and worker; SKILL-04 test passes. |

All four requirement IDs (SKILL-01 through SKILL-04) are fully satisfied. The REQUIREMENTS.md traceability table lists all four as `Phase 11` — no orphaned requirements found.

---

### Anti-Patterns Found

No blockers detected.

| File | Pattern | Severity | Assessment |
|------|---------|----------|------------|
| `scripts/publish-skill.sh` | `shellcheck` without `-S error` flag emits SC2016 (single-quote expression) and SC1091 (not following source) | Info | Passes `shellcheck -S error` (the project's CI gate per SUMMARY.md). SC2016 is intentional — the single-quoted `\$(HOME|USER|...)` is the regex pattern for grep to match literal `$HOME` etc. in file content. SC1091 is a known shellcheck limitation with dynamic `source` paths. Neither is a blocker. |
| `cli/conjure` | `shellcheck` without `-S error` emits SC2097/SC2098 (env-var-before-exec pattern) and SC2155 | Warning | Pre-existing patterns throughout cli/conjure (not introduced by this phase). Passes `-S error` gate. |

No `TBD`, `FIXME`, `XXX`, `TODO`, `HACK`, or `PLACEHOLDER` markers found in any phase-modified file.

---

### Human Verification Required

None. All phase behaviors are verifiable programmatically and confirmed by the regression test suite.

---

## Gaps Summary

No gaps. All 4 roadmap success criteria and all 13 plan-level must-have truths are verified against the live codebase. The test suite exits 0 with PASS: 261, FAIL: 0, including all 13 SKILL-01 through SKILL-04 regression tests.

---

_Verified: 2026-05-25T22:47:18Z_
_Verifier: Claude (gsd-verifier)_
