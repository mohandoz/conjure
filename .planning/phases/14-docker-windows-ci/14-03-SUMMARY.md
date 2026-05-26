---
phase: 14
plan: 03
subsystem: ci-docs
tags: [windows-ci, docker-docs, validation]
dependency_graph:
  requires: [14-01, 14-02]
  provides: [windows-test-job, readme-docker-section, 14-VALIDATION.md]
  affects: [ci.yml, README.md]
tech_stack:
  added: []
  patterns: [windows-git-bash-ci, docker-volume-mount-docs]
key_files:
  created:
    - .planning/phases/14-docker-windows-ci/14-VALIDATION.md
  modified:
    - .github/workflows/ci.yml
    - README.md
decisions:
  - "windows-test job has exactly two steps: checkout + bash tests/run.sh (no apt-get/choco/winget)"
  - "Docker README section placed between Quickstart and Features as specified"
  - "DOCK-03 (ghcr.io publish) deferred to Phase 15 in VALIDATION.md"
metrics:
  duration: "~5 minutes"
  completed: "2026-05-26T00:00:00Z"
  tasks_completed: 3
  files_created: 2
---

# Phase 14 Plan 03: Windows CI + README Docker + Validation Summary

**One-liner:** Added `windows-test` CI job (two steps, no install), README `## Docker` section with bash/PowerShell/cmd forms, and per-requirement validation document for Phase 14.

## What Was Done

### Task 1: windows-test job added to ci.yml

Added a new `windows-test` job to `.github/workflows/ci.yml` immediately before the existing `windows-hook-wiring` job. The job has exactly two steps:

1. `actions/checkout@v4`
2. "Run kit test suite (Git Bash)" — `shell: bash`, `run: bash tests/run.sh`

No `apt-get`, `sudo`, `choco`, or `winget` install steps were added — Git Bash on `windows-latest` already provides `bash`, and `tests/run.sh` has no external tool dependencies beyond what the runner provides. The existing `windows-hook-wiring` job was not modified.

### Task 2: ## Docker section added to README.md

Inserted a new `## Docker` section between `## 🚀 Quickstart` and `## 🧰 Features`. The section documents three volume-mount forms:

- **bash/zsh:** `-v $(pwd):/work --user $(id -u):$(id -g)`
- **PowerShell:** `-v ${PWD}:/work --user "${env:UID}:${env:GID}"`
- **Windows cmd:** `-v %CD%:/work` (without `--user` — handled by WSL2 backend)

Includes a blockquote explaining `--user` behavior on Linux/macOS vs. Docker Desktop for Windows.

### Task 3: 14-VALIDATION.md created

Created `.planning/phases/14-docker-windows-ci/14-VALIDATION.md` following the Phase 13 format. Contains:

- Per-requirement verify commands for DOCK-01, DOCK-02, DOCK-04, DOCK-05, and TECH-03
- Deferred section noting DOCK-03 (ghcr.io publish) is Phase 15 work
- Manual-only verification table for behaviors requiring Docker runtime or GitHub Actions
- Sign-off checklist

## Verification Results

```
# Task 1
grep -c 'windows-test' ci.yml           → 1    PASS
python3 yaml.safe_load(ci.yml)          → ci.yml YAML valid   PASS
grep -c 'windows-hook-wiring' ci.yml    → 1    PASS (unchanged)

# Task 2
grep -c '## Docker' README.md          → 1    PASS
grep -c 'pwd.*:/work' README.md        → 1    PASS
grep -c '%CD%:/work' README.md         → 1    PASS

# Task 3
grep -E 'DOCK-01|DOCK-02|DOCK-04|DOCK-05|TECH-03' 14-VALIDATION.md | wc -l → 19   PASS
```

## Deviations from Plan

None — plan executed exactly as specified.

## Self-Check: PASSED

- `/Users/mohandoz/u01/innovate/conjure/.github/workflows/ci.yml` — modified, windows-test job present
- `/Users/mohandoz/u01/innovate/conjure/README.md` — modified, ## Docker section present
- `/Users/mohandoz/u01/innovate/conjure/.planning/phases/14-docker-windows-ci/14-VALIDATION.md` — created
- All verification checks passed (see above)
