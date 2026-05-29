# Phase 24: Integration Tests + Argus Fixture - Context

**Gathered:** 2026-05-29
**Status:** Ready for planning
**Mode:** Auto-generated (infrastructure phase — discuss skipped per smart-discuss infrastructure detection)

<domain>
## Phase Boundary

Verify the COMPLETE `conjure adopt` + restructure-skill pipeline (built in Phases
21–23) end-to-end against a representative 500-file brownfield fixture
(`brownfield-argus`), with CI assertions on every safety invariant and the
performance bound. This is a VERIFICATION phase — it adds a fixture + integration
tests, it does NOT add product features. **Requirements: None** (all 23 v0.6.0
requirements map to Phases 21–23; this phase proves they hold together).

The five things that must be TRUE (ROADMAP success criteria):
1. `conjure adopt --dry-run` on the 500-file `brownfield-argus` fixture completes
   in <30s AND writes zero files to the fixture dir.
2. Live `conjure adopt` then `conjure adopt --rollback` → zero diff before/after
   (sha256 of every file matches; excluding conjure's own dirs per Phase 22 D-03).
3. A second `conjure adopt` on an already-adopted fixture (idempotent re-run) makes
   zero mutations and reports "nothing to scaffold".
4. SIGKILL after snapshot, before scaffold → re-run triggers the partial-state
   recovery prompt; rollback restores the fixture cleanly.
5. A symlink fixture file is skipped by inventory; a proposed CLAUDE.md with an
   `@import` line is blocked by the pre-write audit gate and never written.

**Not this phase:** any change to adopt.sh / the gate helpers / the skill (those
are shipped + tested in 21–23 — if a test reveals a bug, fix at the source as a
deviation, but the phase's job is the fixture + the E2E assertions, not new
features).

</domain>

<decisions>
## Implementation Decisions

### Claude's Discretion
All implementation choices are at Claude's discretion — pure infrastructure phase,
discuss skipped. Decide during plan-phase, guided by the ROADMAP success criteria,
the v0.6.0 research, and the established test conventions. Known constraints to
respect (NOT open for relitigation — they are project locks):

- **Test harness:** extend the hand-rolled `tests/run.sh` + `tests/lib/sandbox.sh`
  (the project standard; STACK.md: `bats-core` is unit-level only, no new test
  deps). Mirror the existing `▸ Phase 21/22/23` block idioms (pass/fail helpers,
  mktemp sandboxes, set/reset EXIT-trap discipline). The ROADMAP phase line mentions
  "bats-core tests" — defer to STACK.md (extend run.sh) unless planning finds a
  concrete reason bats is required; flag if so.
- **Fixture naming:** the `brownfield-argus` fixture dir MUST be `_`-prefixed
  (`tests/fixtures/_brownfield-argus/`) so the generic `tests/fixtures/[^_]*/`
  audit/golden-EXPECT loops (run.sh:326/368/390) do NOT sweep it (STATE.md lesson;
  Phase 22/23 precedent). Decide fixture generation strategy (committed files vs a
  generator script that materializes 500 files into a sandbox at test time) during
  planning — a generator keeps the repo lean and is the likely choice for 500 files.
- **Perf gate:** the <30s dry-run bound is measured in CI; decide the timing
  mechanism (e.g. `SECONDS`/`date` delta around the dry-run) and a sane CI margin.
- **SIGKILL simulation:** reuse the Phase 22 background-launch + bounded-poll +
  `kill -9` harness pattern (tests/run.sh Phase 22 SIGKILL section). The
  non-TTY recovery exit-2 path is the automatable assertion; the interactive prompt
  was already PTY-verified in Phases 22/23.
- **Zero-diff comparison:** `diff -r` with excludes for conjure's own dirs
  (`.conjure-adopt-backups`, `.conjure-archive-*`, `RESTRUCTURE-LOG.md`,
  `adopt-manifest.json`, `.conjure-adopt-state`) per Phase 22 D-03.
- **Conventions:** POSIX bash 3.2+, `exit 2` never `exit 1`, shellcheck CI gate
  (`-S error -e SC2164,SC2044,SC2034,SC2155`), no new deps.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `tests/run.sh` (now PASS 429/0) + `tests/lib/sandbox.sh` — the harness to extend;
  the Phase 22 SIGKILL/rollback sections and the Phase 23 gate sections are the
  closest analogs for the E2E assertions.
- `tests/fixtures/brownfield-simple/` — the existing small brownfield fixture
  (Phase 22 reused it via `cp -r`); `brownfield-argus` is its 500-file sibling.
- The SHIPPED pipeline under test: `cli/conjure adopt`, `scripts/adopt.sh`
  (dry-run/snapshot/inventory/scaffold/audit/rollback/recovery/apply-step),
  `templates/skills/restructure/` (SKILL.md + gates), `scripts/init-project.sh`,
  `scripts/audit-setup.sh`, the Phase 21 libs (`lib/inventory.sh` 500-file cap +
  `--full-inventory`, `lib/snapshot.sh`, `lib/mutate.sh`, `lib/caps.sh`).
- The `_adopt-restructure-steps` + `_restructure-gates` fixtures (the `_`-prefix
  convention to follow for `_brownfield-argus`).

### Established Patterns
- Test-first Wave 0 (graceful-red block before any new code) is the project idiom —
  but this phase adds mostly TESTS, so Wave 0 may BE the deliverable; planning
  decides the wave shape.
- Inventory already excludes symlinks / `.git` / `node_modules` /
  `.conjure-adopt-backups` (criterion 5 symlink-skip likely already holds — the test
  proves it).

### Integration Points
- The fixture + tests live under `tests/`; no product code changes expected (the
  phase verifies, it doesn't build features).

</code_context>

<specifics>
## Specific Ideas

No specific requirements beyond the five ROADMAP success criteria — infrastructure
phase. Refer to the ROADMAP phase description and the Phase 21–23 SUMMARY/VERIFICATION
artifacts for the exact pipeline behavior to assert against.

</specifics>

<deferred>
## Deferred Ideas

None — verification phase; discussion stayed within scope.

</deferred>

---

*Phase: 24-integration-tests-argus-fixture*
*Context auto-generated: 2026-05-29 (infrastructure phase, discuss skipped)*
