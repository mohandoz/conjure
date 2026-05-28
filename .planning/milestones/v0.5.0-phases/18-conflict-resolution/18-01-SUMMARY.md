---
phase: 18-conflict-resolution
plan: "01"
subsystem: resolve
tags: [bash, interactive, sidecar, mutate, conflict-resolution]
dependency_graph:
  requires: [lib/mutate.sh]
  provides: [scripts/resolve.sh]
  affects: [cli/conjure (cmd_resolve wiring in plan 02)]
tech_stack:
  added: []
  patterns: [fd-3-redirect-for-inner-read, mutate_rm-dry-run-safe, CONJURE_FORCE_INTERACTIVE-escape-hatch]
key_files:
  created: [scripts/resolve.sh]
  modified: []
decisions:
  - "Used fd 3 redirect (`exec 3< $tmpfile; read <&3`) to keep stdin (fd 0) free for inner user-input `read`, enabling piped-stdin testing"
  - "All-clear check (step 3) placed before TTY guard (step 4) so empty-dir path never requires a TTY"
  - "CONJURE_FORCE_INTERACTIVE=1 escape hatch bypasses TTY guard for integration testing with piped input"
metrics:
  duration: "~15 minutes"
  completed: "2026-05-26"
  tasks_completed: 1
  tasks_total: 1
  files_created: 1
  files_modified: 0
---

# Phase 18 Plan 01: scripts/resolve.sh Interactive Sidecar Walker — Summary

**One-liner:** POSIX bash sidecar walker with fd-3 stdin isolation, all-clear-before-TTY-guard ordering, and DRY_RUN-safe mutate_rm actions.

## What Was Built

`scripts/resolve.sh` — the interactive worker for `conjure resolve`. Walks every `.conjure-conflict-*` sidecar left by `conjure update --apply`, prompts `[k]eep / [a]pply / [e]dit / [s]kip` per file, and uses `mutate_rm` / `mutate_write` for dry-run-safe filesystem mutations.

## Execution Order (Critical)

1. Source `lib/mutate.sh` (hard exit 2 on failure)
2. `find "$TARGET" -name '.conjure-conflict-*'` into sorted tmpfile
3. All-clear check: if tmpfile empty, print "No conflicts remain" and exit 0 — **no TTY required**
4. Non-interactive guard: `[ -t 0 ] || [ "${CONJURE_FORCE_INTERACTIVE:-0}" = "1" ] || exit 2`
5. Main prompt loop reading sidecar paths from fd 3 (tmpfile), leaving fd 0 free for user `read`

## Key Design Decisions

**fd 3 redirect for inner read:** The outer `while IFS= read -r sidecar_path <&3` reads from the tmpfile on fd 3, leaving stdin (fd 0) available for the inner `read -r -p "  [k]eep / [a]pply / [e]dit / [s]kip: " choice`. Without this separation, `while ... done < "$tmpfile"` redirects all reads inside the loop to the tmpfile, causing the choice prompt to receive empty input on each iteration.

**All-clear before TTY guard:** Per RESOLVE-02, `bash scripts/resolve.sh "$dir" </dev/null` (no sidecars) must print "No conflicts remain" and exit 0. Moving the TTY guard before sidecar discovery would break this path.

**CONJURE_FORCE_INTERACTIVE=1:** Bypasses the TTY check for integration testing with piped stdin. Unset in production — no security boundary is crossed since the variable only affects whether interactive prompting proceeds.

## Verification Results

All acceptance criteria passed:

- `bash -n scripts/resolve.sh` — PASS
- `shellcheck scripts/resolve.sh` — PASS (zero warnings)
- `[ -x scripts/resolve.sh ]` — PASS
- Empty dir without TTY: exits 0, prints "No conflicts remain" — PASS
- Sidecar present, piped stdin: exits 2, stderr "stdin is not a TTY" — PASS
- `CONJURE_FORCE_INTERACTIVE=1` + `printf 'k\n'`: sidecar removed, current file unchanged — PASS
- `CONJURE_FORCE_INTERACTIVE=1` + `printf 'a\n'`: current file = sidecar content, sidecar removed — PASS
- `DRY_RUN=1` + `CONJURE_FORCE_INTERACTIVE=1` + `printf 'k\n'`: sidecar present, output `[dry-run] would rm ...` — PASS

## Deviations from Plan

**1. [Rule 1 - Bug] Fixed fd conflict between outer sidecar loop and inner choice read**

- **Found during:** Task 1 — first run of keep action test
- **Issue:** Using `while ... done < "$tmpfile"` redirects fd 0 to the tmpfile for all reads inside the loop. The inner `read -r -p "... choice"` read from the tmpfile (already at EOF after sidecar path was consumed), returning empty string on every iteration, triggering the unknown-choice fallback in an infinite loop.
- **Fix:** Changed to `exec 3< "$tmpfile"` and `while IFS= read -r sidecar_path <&3` so the outer loop reads from fd 3, leaving fd 0 (stdin) free for the user-input `read`.
- **Files modified:** `scripts/resolve.sh`
- **Commit:** 4aedaee (included in task commit)

## Known Stubs

None — all actions fully implemented and tested.

## Threat Flags

No new security-relevant surface beyond what is in the plan's threat model. All sidecar paths are quoted in variable expansions (`"$sidecar_path"`, `"$current_file"`); no `eval`; `${EDITOR:-vi}` is the intended user-controlled interaction surface.

## Self-Check: PASSED

- `scripts/resolve.sh` exists and is executable
- Commit `4aedaee` present in git log
- All 8 verification assertions passed
