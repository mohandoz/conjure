---
phase: quick
plan: 260605-sdw
subsystem: dev-tooling
tags: [makefile, install, developer-experience]
dependency_graph:
  requires: []
  provides: [make-install, make-uninstall, make-help]
  affects: []
tech_stack:
  added: []
  patterns: [POSIX-make, live-symlink-install]
key_files:
  created:
    - Makefile
  modified: []
decisions:
  - "Use ln -sf with absolute CURDIR path so symlink works regardless of cwd after install"
  - "Default BINDIR=~/.local/bin (user-owned, no sudo); PREFIX override follows FHS convention"
  - "PATH check runs in recipe shell (not make variable expansion) for GNU make 3.81 compat"
  - "conjure version invoked via full BINDIR path in recipe to work even when BINDIR not on PATH yet"
metrics:
  duration: "~72 seconds"
  completed: "2026-06-05"
  tasks_completed: 2
  files_created: 1
  files_modified: 0
---

# Phase quick Plan 260605-sdw: Add Makefile with install/uninstall targets — Summary

**One-liner:** POSIX Makefile with live-symlink `make install`, idempotent `make uninstall`, and PATH-aware confirmation for contributor developer-environment setup.

## What Was Built

Added `Makefile` to the repo root with three targets:

- `help` (default): prints a concise target listing with variable overrides shown
- `install`: `chmod +x cli/conjure`, `mkdir -p BINDIR`, `ln -sf CURDIR/cli/conjure BINDIR/conjure`, then prints confirmation and either the installed version (if BINDIR is on PATH) or the exact `export PATH=...` line the contributor needs
- `uninstall`: `rm -f BINDIR/conjure` with confirmation

Variables support `PREFIX ?= $(HOME)/.local` and `BINDIR ?= $(PREFIX)/bin` overrides on the command line.

## Task Outcomes

### Task 1: Create Makefile
- **Status:** COMPLETE
- **Commit:** 67f36bf
- **Files:** Makefile (created, 31 lines)
- **Verification:** `make --dry-run install` shows `chmod +x`, `mkdir -p`, `ln -sf`; `make --dry-run uninstall` shows `rm -f`; `make help` prints correctly

### Task 2: Smoke-test install end-to-end
- **Status:** COMPLETE (verification-only, no commit needed)
- **Result:** PASS
  - `make install BINDIR=$TMPBIN` created symlink at `$TMPBIN/conjure`
  - symlink pointed to `cli/conjure` in repo (absolute path)
  - `$TMPBIN/conjure version` exited 0 and printed `conjure unknown`
  - `make uninstall BINDIR=$TMPBIN` removed the symlink cleanly
  - No files outside BINDIR were modified

## Deviations from Plan

None — plan executed exactly as written.

## Known Stubs

None.

## Threat Flags

None. Makefile targets operate entirely within user-controlled BINDIR; no privilege escalation paths introduced.

## Self-Check: PASSED

- Makefile exists at worktree root: FOUND
- Commit 67f36bf: FOUND (`git log --oneline | grep 67f36bf`)
- `make --dry-run install` shows `ln -sf`: VERIFIED
- Smoke test: PASS (full cycle completed in sandbox-writable temp dir)
