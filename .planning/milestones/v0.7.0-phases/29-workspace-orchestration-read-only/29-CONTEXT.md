# Phase 29: Workspace Orchestration — Read-Only - Context

**Gathered:** 2026-06-03
**Status:** Ready for planning
**Mode:** Smart discuss (autonomous — all grey areas accepted as recommended)

<domain>
## Phase Boundary

Developers can declare a multi-repo workspace (`.conjure-workspace.json` + `conjure workspace
init` discovery) and run READ-ONLY harness health checks across all repos in one command
(`conjure workspace check`, `conjure workspace audit`) with a per-repo status table.

Implements WS-01..04. STRICTLY read-only: WS-05 (`workspace update`), WS-06 (`workspace adopt`
saga), WS-07 (`--rollback`) are Phase 30 — no mutating workspace op ships in this phase.
WS-F1 (`workspace report` single-pane markdown/JSON) and WS-F2 (`workspace emit-managed`) deferred.

This phase consumes Phase 27's stable `conjure audit --json` contract
(`{schema_version,status,checks:[{id,severity,message}],summary}`) and `conjure check --porcelain`.

</domain>

<decisions>
## Implementation Decisions

### Manifest Schema & Discovery (WS-01/02)
- `.conjure-workspace.json` shape: `{ schema_version, generated, repos: [ { name, path, tags: [] } ] }`.
  `tags[]` ships now (empty allowed) so Phase 30's optional tag filter has a stable field.
- Repo `path` values are RELATIVE to the manifest's directory (portable across machines).
- `conjure workspace init` discovers SIBLING directories (of cwd) containing `.claude/`;
  TTY confirmation prompt reads `/dev/tty`; non-TTY requires `--yes`, else exit 2 (never auto-mutate).
- Manifest discovery walks parent directories (same pattern as `.conjure-version`).
- Manifest written via `mutate_write` (backup-before-mutate). `workspace init` with any invalid
  repo path exits 2 BEFORE writing anything (validate-before-write).

### Aggregation Semantics (WS-03/04)
- `conjure workspace check`: runs `conjure check --porcelain` per repo → aggregated table
  (repo name, drift status, exit code). FAIL-TOLERANT default: a repo with a permissions error
  → overall exit 1 (partial success), remaining repos still processed. Exit 0 only when all clean.
  Never exit 2 for per-repo issues.
- `conjure workspace audit`: runs `conjure audit --json` per repo → per-repo pass/fail table +
  global summary. Exit 2 if ANY repo audit FAILs; exit 1 if warns only; exit 0 all pass.
  `--fail-fast` switches to abort-on-first-failure.
- Output: human-readable table only (machine aggregate = WS-F1, deferred).
- Execution is SERIAL per repo (matches Phase 30's serial saga; deterministic output order).

### Bad-Path Handling
- `workspace init`: any invalid path → exit 2 before any write.
- `workspace check` AND `workspace audit` on an existing manifest containing a bad path: SKIP
  that repo with a warning and process the remaining repos (consistent behavior across both).

### Placement
- `lib/workspace.sh` — shared manifest read/validate/discovery helpers (independent library).
- `scripts/workspace.sh` — the subcommand worker (init/check/audit dispatch).
- `cmd_workspace` + `workspace)` dispatch + usage line in `cli/conjure`.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- Phase 27's `conjure audit --json` (stable contract: {schema_version,status,checks,summary})
  and `conjure check --porcelain` — the per-repo primitives this phase aggregates. Parse with jq.
- `.conjure-version` parent-dir discovery pattern — reuse for `.conjure-workspace.json` lookup.
- `lib/mutate.sh` (`mutate_write`) + validate-before-write discipline (Phase 25/26 emit workers).
- `cli/conjure` — command/dispatch/usage addition pattern (Phases 25-28 added publish-plugin,
  emit-policy, eval; workspace follows identically).
- `/dev/tty` interactive-prompt + non-TTY→exit-2 convention (existing CLAUDE.md rule; see how
  init/adopt handle it).
- `tests/run.sh` + fixtures — add `_workspace*/` fixtures (a fake workspace of 2-3 mini repos
  with .claude/ dirs) + graceful-red WS block first.
- jq for manifest validation + audit --json parsing (already in envelope).

### Established Patterns
- POSIX bash 3.2+; shellcheck `-S error -e SC2164,SC2044,SC2034,SC2155`; exit 2 never exit 1
  (the fail-tolerant `workspace check` exit 1 partial-success is a DOCUMENTED, SC-mandated
  aggregate semantic — mirror how audit's WARN→exit-1 gate is the documented exception).
- Single combined EXIT-trap cleanup per script (Phase 27 lesson).
- Bundled-not-fetched; zero egress; no new runtime deps.

### Integration Points
- New `lib/workspace.sh` + `scripts/workspace.sh` + `cmd_workspace` in cli/conjure.
- Reads `conjure check --porcelain` + `conjure audit --json` outputs per repo (subprocess
  invocations of the same conjure CLI with CONJURE_HOME preserved).
- Phase 30 will extend `scripts/workspace.sh` with mutating ops (update/adopt/rollback) — keep
  the init/check/audit structure extensible (subcommand case dispatch).

</code_context>

<specifics>
## Specific Ideas

- SC fixture test: a manifest with 3 repos where 1 has an invalid path → `workspace init` exits 2
  pre-write; `workspace check` skips the bad repo with a warning and processes the other 2.
- The per-repo status table shows: repo name, drift/audit status, exit code.
- A repo with a permissions error during `workspace check` → exit 1 partial success (NOT 2),
  remaining repos processed.
- Keep `CONJURE_HOME` propagation correct when invoking conjure per repo (subprocess env).

</specifics>

<deferred>
## Deferred Ideas

- WS-05/06/07: workspace update / adopt saga / rollback — Phase 30.
- WS-F1: `conjure workspace report` (single-pane markdown/JSON health).
- WS-F2: `conjure workspace emit-managed` (union managed-settings across repos).

</deferred>
