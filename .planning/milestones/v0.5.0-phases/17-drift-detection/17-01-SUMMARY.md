---
phase: 17-drift-detection
plan: "01"
subsystem: drift-detection
tags: [bash, sha256, drift-classifier, manifest, read-only]
dependency_graph:
  requires: []
  provides: [scripts/check.sh, sha256_file, build_manifest, classify_kit_files, find_added_files]
  affects: [scripts/check.sh]
tech_stack:
  added: []
  patterns: [bash-3.2-compat, temp-file-manifest, grep-qF-membership, cross-platform-sha256]
key_files:
  created:
    - scripts/check.sh
  modified: []
decisions:
  - "Bash 3.2 compatible manifest via mktemp temp-file + grep -qF (no declare -A)"
  - "settings.json -> settings.json.tmpl mapping hard-coded in case branch (Pitfall 2)"
  - "Added-file detection scans .claude/ subtree only; root-level user files excluded"
  - "Internal .conjure-* files skipped in added-file detection (Pitfall 6)"
metrics:
  duration: "~2m"
  completed: "2026-05-26T03:17:42Z"
  tasks_completed: 1
  files_created: 1
  files_modified: 0
requirements:
  - DRIFT-01
  - DRIFT-02
---

# Phase 17 Plan 01: Drift Classifier Worker Summary

**One-liner:** Sha256-based 3-way drift classifier (M/R/A) with 35-entry kit manifest, bash 3.2 compatible, porcelain output mode, and cross-platform sha256 fallback.

## What Was Built

`scripts/check.sh` — a read-only bash worker that compares an installed harness against the upstream kit bundled in `$CONJURE_HOME`. Implements the complete 3-way drift classification: M (modified — in both, sha differs), R (removed — in kit manifest, absent from harness), A (added — in harness .claude/ but not in manifest).

The 35-entry kit manifest covers all files `scripts/init-project.sh` installs: 3 root dotfiles (`.editorconfig`, `.gitattributes`, `.claudeignore`), 1 settings file (`.claude/settings.json`), 6 hooks (`*.mjs`), 19 skill `SKILL.md` files, and 6 agent `.md` files.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Implement scripts/check.sh — manifest builder + sha256 classifier | ddc649c | scripts/check.sh (created) |

## Acceptance Criteria Verification

| # | Criterion | Result |
|---|-----------|--------|
| 1 | scripts/check.sh exists and is executable | PASS |
| 2 | shellcheck -S error -e SC2155 exits 0 | PASS |
| 3 | No declare -A or mapfile in non-comment lines | PASS |
| 4 | sha256_file() with sha256sum/shasum -a 256 fallback | PASS |
| 5 | .claude/settings.json -> templates/settings.json.tmpl mapping | PASS |
| 6 | .claude/.conjure-* skip pattern in added-file detection | PASS |
| 7 | exit "$drift" as final statement | PASS |
| 8 | PORCELAIN=1 produces `<M|R|A> <path>` format with no headers | PASS |

## Deviations from Plan

None — plan executed exactly as written. The comment line "no declare -A, no mapfile, no local -n" in the script header mentions these words, but the plan's actual verification command uses `grep -v '^#'` to exclude comments, which passes as expected.

## Threat Model Coverage

| Threat ID | Status |
|-----------|--------|
| T-17-01: $TARGET path argument tampering | Mitigated — `[ -d "$TARGET" ]` guard before any file ops; `exit 2` on failure |
| T-17-02: sha256 hash information disclosure | Accepted — hashes never printed, comparison is local only |
| T-17-03: DoS via large .claude/ tree | Accepted — .claude/ trees are small |
| T-17-SC: package installs | N/A — zero package installs |

## Known Stubs

None — `scripts/check.sh` is a complete implementation. CLI wiring (`cmd_check` in `cli/conjure`) and regression tests in `tests/run.sh` are deferred to Plan 02 by design (this plan was intentionally isolated).

## Self-Check: PASSED

- [x] scripts/check.sh exists: `ls -la /Users/mohandoz/u01/innovate/conjure/scripts/check.sh`
- [x] Commit ddc649c exists: `git log --oneline | grep ddc649c`
- [x] shellcheck passes: `shellcheck -S error -e SC2155 scripts/check.sh`
- [x] No declare -A in non-comment lines: `grep -v '^#' scripts/check.sh | grep -c 'declare -A'` = 0
