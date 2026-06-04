---
status: resolved
trigger: "Phase 30 workspace SIGKILL saga test is timing-flaky: diff -r pre vs post-rollback finds extra file/dir when kill lands mid-apply on a repo with status snapshotted/in-progress"
created: 2026-06-04T00:00:00Z
updated: 2026-06-04T01:30:00Z
---

## Current Focus

hypothesis: CONFIRMED — kill -9 of workspace.sh leaves per-repo conjure adopt subprocesses running as orphans; they continue creating files in the repo concurrently with ws_do_rollback's file-deletion step
test: instrumented reproduction confirmed (file count grew from 8 to 81 in 2 seconds after kill)
next_action: DONE — fix committed

## Symptoms

expected: diff -r pre vs post-rollback empty for all repos after SIGKILL + rollback
actual: intermittently "1 repo(s) have non-empty diff after rollback" — sha256 per-file assertion passes (pre-existing files restored correctly) but diff -r finds an EXTRA file or directory
errors: "1 repo(s) have non-empty diff after rollback"
reproduction: run the Phase 30 SIGKILL test block repeatedly until kill lands mid-apply on a repo still in status "snapshotted"
started: intermittent; timing-dependent on where kill -9 lands

## Eliminated

- hypothesis: ws_do_rollback skips file-deletion for repos with status "snapshotted"
  evidence: code inspection shows file-deletion runs for all repos with valid snap_ref regardless of status
  timestamp: 2026-06-04T00:30:00Z

- hypothesis: process substitution inside heredoc outer loop corrupts stdin
  evidence: bash 3.2 test confirmed process substitution does not interfere with outer heredoc stdin
  timestamp: 2026-06-04T00:45:00Z

- hypothesis: snapshot_rollback introduces adopt-created files into the repo
  evidence: manual tar inspection showed snapshot only contains pre-adopt content
  timestamp: 2026-06-04T01:00:00Z

- hypothesis: snapshot is contaminated by adopt running concurrently
  evidence: snapshot taken in PHASE A before PHASE B; cannot be modified by PHASE B adopt
  timestamp: 2026-06-04T01:05:00Z

## Evidence

- timestamp: 2026-06-04T00:35:00Z
  checked: debug_sigkill.sh output — post-rollback beta tree
  found: all adopt-created files (hooks, skills, agents) present AFTER rollback despite snapshot not containing them
  implication: file-deletion step ran but failed to clean up some files

- timestamp: 2026-06-04T01:10:00Z
  checked: ps aux after kill -9 $P30_SK_PID of workspace.sh
  found: "bash conjure adopt repos/beta" and "bash adopt.sh repos/beta" processes still running AFTER workspace.sh killed; file count grew from 8 to 81 in 2 seconds after kill
  implication: kill -9 of parent bash does NOT kill child processes — they become orphans and continue creating files

- timestamp: 2026-06-04T01:15:00Z
  checked: manual replay of file-deletion step (without orphan running)
  found: correctly deletes all 48 adopt-created files when no orphan is running
  implication: deletion logic is correct; issue is purely TOCTOU — orphan creates files after the deletion pass completes

## Resolution

root_cause: kill -9 of workspace.sh (the PHASE B orchestrator) leaves per-repo conjure adopt subprocess orphaned. This subprocess continues writing files to the repo while ws_do_rollback runs its file-deletion pass. Files created AFTER the deletion pass completes (or DURING it, after those paths were scanned) survive into the post-rollback tree, causing the diff -r failure. The sha256 check passes because it only verifies pre-existing files (from the pre-run hash), not the absence of adopt-created files.
fix: Added two changes to ws_do_rollback in scripts/workspace.sh — (1) pkill -9 the orphaned conjure adopt and adopt.sh processes for the repo before restoring, with a 50ms wait; (2) run the orphan-file deletion pass TWICE so the second pass catches files written by the orphan in the window between the pkill and the first deletion pass.
verification: 50 consecutive PASS (30+20 separate runs of the SIGKILL loop). Full test suite: 574 PASS, 0 FAIL.
files_changed: [scripts/workspace.sh]
