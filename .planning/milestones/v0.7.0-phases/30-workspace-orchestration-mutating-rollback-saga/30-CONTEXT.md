# Phase 30: Workspace Orchestration — Mutating + Rollback Saga - Context

**Gathered:** 2026-06-04
**Status:** Ready for planning
**Mode:** Smart discuss (autonomous — all grey areas accepted as recommended)

<domain>
## Phase Boundary

Developers can run MUTATING harness operations across many repos in one command:
`conjure workspace update` (serial per-repo `conjure update`) and `conjure workspace adopt`
(serial per-repo adopt under a saga: ALL repos snapshotted before ANY apply), with a
saga-pattern `--rollback` that survives SIGKILL and restores every repo to its pre-run state
(per-repo sha256 zero-diff proof). Implements WS-05, WS-06, WS-07.

This is the FINAL and highest-risk phase of v0.7.0. It builds directly on Phase 29's
manifest/validation/aggregation plumbing (`lib/workspace.sh`, `scripts/workspace.sh`) and on
the proven single-repo saga in `scripts/adopt.sh` (`.conjure-adopt-state/` crash-durable
state.json via atomic jq>tmp+mv, Phase 22 SIGKILL tests, sha256 zero-diff rollback).

</domain>

<decisions>
## Implementation Decisions

### Saga State Machine (WS-06)
- `.conjure-workspace-state.json` schema:
  `{ run_id, started, phase: "snapshot"|"apply"|"done", repos: [ { name, snapshot_ref,
  sha256_pre, status: "pending"|"snapshotted"|"applied"|"failed"|"rolled_back" } ] }`.
- Stored at the WORKSPACE ROOT next to `.conjure-workspace.json`.
- SIGKILL durability: state written atomically (jq > tmp && mv) BEFORE each repo operation
  and updated after — mirroring `scripts/adopt.sh`'s `.conjure-adopt-state/` discipline.

### Snapshot Strategy (WS-06)
- Reuse `snapshot_create` (lib/snapshot.sh — the blessed raw-cp/tar exception, excludes
  .git/node_modules) per repo. SAGA INVARIANT: ALL repos snapshotted before ANY apply.
- A per-repo content sha256 manifest is recorded pre-run (`sha256_pre`) — the input for the
  rollback zero-diff proof (mirror the Phase 22 per-file before-hash pattern in tests/run.sh).
- Disk-space estimate (du-based) runs BEFORE the snapshot phase; >2 GB total → warn and
  require `--allow-large-snapshots` to proceed.

### Rollback Semantics (WS-07)
- `workspace adopt --rollback` restores each repo INDEPENDENTLY from its snapshot recorded in
  the state file. A repo whose rollback fails does NOT stop the others — continue per repo,
  report each (independence is the saga's point).
- Idempotent: already-rolled-back repos are skipped; if everything is already rolled back →
  exit 0 no-op; if NO state file exists → exit 2 "nothing to roll back".
- After a successful rollback the state file is marked rolled_back and ARCHIVED with a
  timestamp (audit trail), not deleted.
- SIGKILL CI fixture proof (SC): kill -9 a `workspace adopt` mid-batch against a
  `_workspace-trio` fixture (3 small repos) → `--rollback` → per-repo sha256 zero-diff
  (mirror the Phase 22 SIGKILL test pattern at workspace scale).

### update vs adopt Scope (WS-05)
- The SAGA (snapshot-all-first + state file) applies to `adopt` ONLY.
- `workspace update` runs `conjure update` per repo SERIALLY; default stop-on-first-error
  (fail-fast); `--continue-on-error` opt-in; per-repo merge/conflict status reported and
  conflict sidecars from individual repos surfaced in the aggregate report. It relies on
  `conjure update`'s own per-repo backup discipline (no workspace-level snapshots).
- `workspace adopt` supports an optional `--tag X` filter over the manifest `tags[]` field
  (shipped in Phase 29); serial; stop-on-fail.
- `workspace adopt --dry-run`: ALL preflight + snapshot-size checks run, ZERO files written;
  exit 2 is never emitted from a dry run unless a preflight check itself fails.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `scripts/adopt.sh` — THE saga precedent: `.conjure-adopt-state/` state dir (state.json via
  atomic jq>tmp+mv), staging, `--rollback`, never-overwrite, SIGKILL recovery. The workspace
  saga orchestrates this per repo and lifts the state machine one level up.
- `lib/snapshot.sh` (`snapshot_create`) — blessed per-repo backup (excludes .git/node_modules).
- `lib/workspace.sh` (Phase 29) — manifest load/validate + path-traversal boundary guard
  (MUST be applied to every repo before any mutating op — same execution-time re-check
  discipline as Phase 29's check/audit).
- `scripts/workspace.sh` (Phase 29) — subcommand dispatch + `_ws_cleanup` single EXIT trap +
  serial per-repo loop + table/report patterns; extend with update/adopt/rollback subcommands.
- `scripts/update.sh` / `cmd_update` — the per-repo op `workspace update` drives; its
  merge/conflict sidecar outputs are what the aggregate report surfaces.
- Phase 22 test patterns in tests/run.sh (~lines 2407-2750): per-file sha256 before-hash
  recording, SIGKILL mid-run (`kill -9` after snapshot lands), rollback zero-diff assertions —
  mirror at workspace scale with a `_workspace-trio` fixture.
- `cli/conjure` `cmd_workspace` — forwards "$@" verbatim; new subcommands parse their own flags.

### Established Patterns
- POSIX bash 3.2+; shellcheck `-S error -e SC2164,SC2044,SC2034,SC2155`; exit 2 never exit 1
  (documented aggregate exceptions from Phase 29 stay as-is for read-only ops; mutating ops
  use exit 2 on failure, stop-on-fail default).
- /dev/tty prompts; non-TTY → exit 2 never auto-mutate (mutating workspace ops in non-TTY
  need explicit consent flags, mirroring `workspace init --yes`).
- Single combined `_ws_cleanup` EXIT trap (extend, never re-register).
- All mutations via lib/mutate.sh / snapshot_create; backup-before-mutate; validate-before-write.

### Integration Points
- `scripts/workspace.sh`: new `update`, `adopt` (+`--rollback`, `--tag`, `--dry-run`,
  `--allow-large-snapshots`, `--continue-on-error` on update) subcommand branches.
- `lib/workspace.sh`: state-file read/write/validate helpers (workspace_state_write atomic,
  workspace_state_read).
- `.conjure-workspace-state.json` at workspace root; archived copies timestamped.
- Per-repo ops invoke the existing `conjure update` / `conjure adopt` machinery via
  `bash "$CONJURE_HOME/cli/conjure" <op> ... "$repo"` with flags (argv, not env — Phase 29 lesson).

</code_context>

<specifics>
## Specific Ideas

- The SIGKILL saga proof is THE phase-defining test: `_workspace-trio` fixture (3 small repos),
  kill -9 mid-batch after ≥1 repo applied, then `--rollback`, then per-repo sha256 zero-diff.
- Snapshot-all-before-any-apply must be observable in the state file phases (all repos reach
  "snapshotted" before the first "applied").
- Path-traversal boundary re-check before every mutating per-repo operation (Phase 29 CR-02
  lesson — validate-time AND execution-time).
- Mutating ops in non-TTY require explicit consent (--yes or equivalent) — never auto-mutate.

</specifics>

<deferred>
## Deferred Ideas

- WS-F1: `conjure workspace report`; WS-F2: `workspace emit-managed` — future.
- Parallel per-repo apply — saga stays serial by design (deterministic, stop-on-fail).

</deferred>
