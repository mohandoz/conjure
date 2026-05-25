# Phase 4: Regression Suite & Dry-Run Proof - Context

**Gathered:** 2026-05-25
**Status:** Ready for planning

<domain>
## Phase Boundary

Extend `tests/run.sh` with three new test sections and update CI to add a
Windows leg:

1. **Golden-file EXPECT loop** — per-fixture EXPECT files (committed alongside
   fixtures at `tests/fixtures/<profile>/EXPECT`) with grep-E patterns that
   assert positive pass output; tests/run.sh iterates all fixtures including
   green ones and fails on output drift (TEST-03).

2. **Dry-run byte-identical snapshot** — for each of the 9 green fixtures:
   copy fixture to sandbox, run `conjure init --dry-run` against it,
   `diff -r sandbox original`; any mutation = test failure (TEST-05).

3. **Failure-mode reproductions** — new `▸ Failure-mode reproductions (TEST-07)`
   section in run.sh; mini synthetic fixtures (mktemp -d + write offending
   file) for each Conjure-auditable failure mode; assert specific audit
   findings (TEST-07).

4. **Windows CI leg** — new `windows-latest` job in
   `.github/workflows/ci.yml`; runs `conjure init` via Git Bash, asserts
   `node` hook wiring in generated `settings.json` (TEST-06).

Requirements: TEST-03, TEST-05, TEST-06, TEST-07.

</domain>

<decisions>
## Implementation Decisions

### EXPECT Files for Green Fixtures
- **D-01:** Each green fixture gets a committed `tests/fixtures/<profile>/EXPECT`
  file with positive-pass grep-E patterns (e.g., matching `PASS:` summary
  line or specific passing checks). Fails if audit output drifts — detects
  silent regressions.
- **D-02:** EXPECT patterns are regex patterns that avoid absolute paths (same
  format as `tests/fixtures/_broken/EXPECT` already established in Phase 3).
  Patterns match semantic content, not sandbox temp paths.
- **D-03:** EXPECT files live committed alongside fixtures; `scripts/regen-fixtures.sh`
  is the documented command to regenerate them when profiles change. Golden-file
  drift = test failure.

### Dry-Run Byte-Identical Snapshot
- **D-04:** Method: `cp -r fixture sandbox`, run `conjure init --dry-run "$sandbox"`,
  then `diff -r "$sandbox" "$fixture_original"`. Any mutation = failure with
  visible diff output.
- **D-05:** Scope: all 9 green fixtures (not a single representative). Every
  profile's init path is tested.
- **D-06:** Run against the existing fixture as-is (already has `.claude/`).
  Tests re-init idempotence — the real-world case where a user re-runs
  `conjure init --dry-run` on an already-initialized repo.

### Failure-Mode Reproductions
- **D-07:** Scope: only Conjure-auditable failure modes — those that
  `conjure audit` can detect. Specifically:
  - Size cap exceeded (CLAUDE.md > 100 lines) — already `_broken/` fixture;
    new test section references it or creates a synthetic one for clarity
  - Hook wrong exit code (hook script contains `exit 1`) — synthetic fixture
  - Version mismatch / `.conjure-version` malformed — synthetic fixture
  Skip: runtime/infra modes (MCP down, graphify drift, race conditions) —
  untestable in CI.
- **D-08:** Location: new `▸ Failure-mode reproductions (TEST-07)` section
  inside `tests/run.sh`. Uses same `pass`/`fail` helpers. Single entrypoint.
- **D-09:** Reproduction pattern: `mktemp -d` synthetic fixture + write the
  offending file + run `audit-setup.sh` + assert specific finding string.
  Self-contained; no committed fixtures for this section.

### Windows CI Leg
- **D-10:** New `windows-hook-wiring` job in `.github/workflows/ci.yml` on
  `windows-latest`. Targeted smoke test, not the full test suite.
- **D-11:** Bash via `shell: bash` on each step (Git Bash is pre-installed on
  `windows-latest`). Node is pre-installed. No extra dependency installation.
- **D-12:** Assertions:
  1. `node --version` exits 0 (Node present on Windows runner)
  2. `grep 'node' .claude/settings.json` succeeds (hook wiring uses node, not bash .sh)
  3. `grep -v 'bash .claude/hooks' .claude/settings.json` succeeds (no bash hook regression)
  Proves SAFE-03 wiring is intact on Windows.

### Claude's Discretion
- Exact positive patterns in each green fixture's EXPECT file (e.g., whether
  to match `PASS:.*size` or `PASS:.*CLAUDE.md` or a summary count line).
- Whether the dry-run diff section in run.sh re-uses `sandbox_setup` or
  manages its own temp copy (to avoid clobbering the existing sandbox env).
- Which specific `exit 1` pattern in a hook constitutes the "wrong exit code"
  synthetic fixture for D-09.
- Whether `scripts/regen-fixtures.sh` gets a `--update-expect` flag that
  regenerates EXPECT files alongside fixture content.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Requirements
- `.planning/REQUIREMENTS.md` §Testing — TEST-03, TEST-05, TEST-06, TEST-07
  (the four requirements this phase addresses)
- `.planning/ROADMAP.md` §Phase 4 — Goal, success criteria, and phase boundary

### Prior Phase Context (locked decisions)
- `.planning/phases/03-sandboxed-per-profile-fixtures/03-CONTEXT.md` — D-07/D-08/D-09:
  `_broken/EXPECT` format (grep-E patterns, `#` comments ignored); D-04/D-05:
  `sandbox_setup` interface and env vars; D-10/D-11: `scripts/regen-fixtures.sh` purpose
- `.planning/phases/02-dry-run-enforcement-chokepoint/02-CONTEXT.md` — D-04/D-05:
  `[dry-run]` output prefix format; `CONJURE_DRY_MUTATION_COUNT` env var

### Existing Code to Study
- `tests/run.sh` — existing test runner; Phase 4 adds 3 new sections; do not
  break existing tests or change existing section behavior
- `tests/lib/sandbox.sh` — `sandbox_setup()` function; Phase 4 dry-run section
  may need a separate copy mechanism to avoid clobbering the existing sandbox env
- `tests/fixtures/_broken/EXPECT` — canonical example of EXPECT file format;
  green fixture EXPECT files follow the same pattern
- `.github/workflows/ci.yml` — existing Ubuntu CI; Phase 4 adds `windows-hook-wiring`
  job alongside existing `test` and `audit-on-fixture` jobs
- `FAILURE-MODES.md` — documents all 14 failure modes; Phase 4 encodes only
  the Conjure-auditable subset as tests

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `tests/run.sh` pattern: `sandbox_setup "$fx"` + `trap 'rm -rf "$SANDBOX_DIR"' EXIT`
  + `bash "$CONJURE_HOME/scripts/audit-setup.sh" "$SANDBOX_DIR"` — reuse for
  EXPECT loop and dry-run snapshot sections
- `tests/fixtures/_broken/EXPECT` loop (already in run.sh): `while IFS= read -r pattern; do ... grep -qE "$pattern"` — generalize this to all fixtures for TEST-03
- `tests/run.sh:TMPDIR_TARGET` dry-run block (lines ~130-155): existing basic
  dry-run mutation check; Phase 4 adds per-fixture byte-identical assertion
  alongside it (separate section, not a replacement)

### Established Patterns
- `pass "msg"` / `fail "msg"` helpers — use for all new test assertions
- `echo "▸ Section name"` — section header pattern; new sections follow same format
- `sandbox_setup <dir>` sets global `SANDBOX_DIR` + registers `trap`; dry-run
  snapshot section must manage its own copy (not `sandbox_setup`) to avoid
  HOME/PATH clobbering when comparing trees
- EXPECT file format: one grep-E pattern per line, `#`-prefixed comments and blank
  lines ignored; same for green fixtures
- `shell: bash` in GitHub Actions on `windows-latest` invokes Git Bash

### Integration Points
- `tests/run.sh` — new sections appended after existing `▸ Fixture audits`
  and `▸ Broken fixture` sections
- `.github/workflows/ci.yml` — new `windows-hook-wiring` job at the same level
  as existing `test` and `audit-on-fixture` jobs
- `scripts/regen-fixtures.sh` — should be extended to regenerate EXPECT files
  alongside fixture content (or a separate `--update-expect` flag)

</code_context>

<specifics>
## Specific Ideas

- For the dry-run diff, avoid `sandbox_setup` (which overrides HOME/PATH) — use
  a plain `cp -r "$fx" "$snap_dir"` + `diff -r "$snap_dir" "$fx"` pattern so
  PATH stays real and the diff is clean.
- Green fixture EXPECT patterns should assert the pass summary line, e.g.,
  `PASS:` (the final count line from `audit-setup.sh`). Avoids brittle path
  matches while still failing on unexpected audit output.
- Windows CI job can stay minimal — install nothing extra, just `shell: bash`
  and `node --version` + the grep assertions on the generated `settings.json`.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 4-Regression Suite & Dry-Run Proof*
*Context gathered: 2026-05-25*
