# Phase 10: Marketplace Publish - Context

**Gathered:** 2026-05-25
**Status:** Ready for planning

<domain>
## Phase Boundary

Wire the `conjure publish` CLI command and CI validation gates so that the
plugin manifest is always version-consistent and the Anthropic community catalog
submission is guided via structured output.

Delivers:
- `scripts/publish-plugin.sh` + `cmd_publish` dispatch in `cli/conjure`
- `conjure publish` updates `marketplace.json` (SHA + version) and validates locally
- `conjure publish --submit` prints a checklist to stdout and writes
  `.claude-plugin/submit-entry.json` with the catalog PR snippet
- CI version-consistency check (marketplace.json + plugin.json vs VERSION file)
- CI installs claude CLI + runs `claude plugin validate .` + jq schema validation

Does NOT introduce skill publishing (`conjure publish-skill` — Phase 11),
org overlays (Phase 12), Homebrew formula (Phase 13), or Docker (Phase 14).

</domain>

<decisions>
## Implementation Decisions

### CI Validation (MKTPL-03)
- **D-01:** Both jq schema validation AND `claude plugin validate .` run in CI.
  Belt-and-suspenders: jq validates marketplace.json + plugin.json against
  SCHEMAS/ (fast, no deps); claude CLI validates the plugin manifest separately.
- **D-02:** Install the official Anthropic claude CLI via their official install
  script in ci.yml. If installation fails, CI fails — no silent skips.
- **D-03:** The exact behavior of `claude plugin validate .` (which files it
  targets — plugin.json only, or full .claude-plugin/ dir) must be determined
  by the researcher by reading official Anthropic docs and the
  anthropics/claude-plugins-community repo before planning.

### marketplace.json Structure (MKTPL-01)
- **D-04:** The researcher must study the Anthropic community catalog format
  (anthropics/claude-plugins-community) and determine the canonical schema
  before touching the existing file. The current self-describing flat format
  in `.claude-plugin/marketplace.json` may need to be restructured to match
  the catalog's expected owner+plugins[] format — or they may be separate
  concerns. Researcher resolves this.

### `conjure publish` Behavior (MKTPL-01)
- **D-05:** `conjure publish` writes HEAD SHA (`git rev-parse HEAD`) to the
  install field in marketplace.json AND updates the `version` field in both
  `marketplace.json` and `plugin.json` to match the `VERSION` file.
  One command makes both files consistent.
- **D-06:** `conjure publish` aborts if the working tree is dirty (uncommitted
  changes). Guards against publishing a SHA that doesn't match working state.
- **D-07:** `conjure publish` validates the updated JSON locally (jq parse at
  minimum) before committing through `lib/mutate.sh`.
- **D-08:** All filesystem mutations go through `lib/mutate.sh` (mutate_write).
  Dry-run is honored via the existing `CONJURE_DRYRUN` env pattern.

### `conjure publish --submit` Output (MKTPL-04)
- **D-09:** `conjure publish --submit` prints a human-readable checklist of
  pre-submission steps to stdout AND writes `.claude-plugin/submit-entry.json`
  with the exact JSON snippet to paste into the catalog PR.
- **D-10:** `.claude-plugin/submit-entry.json` is committed to the repo (goes
  through mutate_write) — provides an auditable record of what was submitted
  and when.
- **D-11:** The stdout checklist includes: pre-submission checks, the
  `anthropics/claude-plugins-community` PR URL, and step-by-step instructions.
  No automation of the actual PR creation.

### CI Version Consistency (MKTPL-02)
- **D-12:** CI checks that `version` in both `marketplace.json` and `plugin.json`
  matches the `VERSION` file on every PR. Implemented as a bash check step in
  `ci.yml` (not in release.yml — catches drift before merge, not just on tag).

### Claude's Discretion
- Exact JSON field layout inside `submit-entry.json` (researcher determines from
  catalog format)
- Exact wording of stdout checklist messages beyond the items listed in D-11
- Whether `cmd_publish` in cli/conjure is ~10 lines (ARCHITECTURE.md estimate)
  or needs more structure — planner decides based on final script design
- Function naming inside `scripts/publish-plugin.sh`

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Requirements and success criteria
- `.planning/REQUIREMENTS.md` §"Marketplace Publish (DIST-01)"
  — MKTPL-01 through MKTPL-04, the four locked requirements
- `.planning/ROADMAP.md` §"Phase 10: Marketplace Publish"
  — success criteria (4 items) and phase goal

### Architecture decisions
- `.planning/research/ARCHITECTURE.md` §"1. scripts/publish-plugin.sh (DIST-01)"
  and §"2. cmd_publish in cli/conjure (DIST-01)"
  — component design, field list, file layout, CLI dispatch pattern
- `.planning/research/ARCHITECTURE.md` §".github/workflows/ci.yml — MODIFIED"
  — CI modifications already scoped

### Existing manifest files (read before restructuring)
- `.claude-plugin/marketplace.json` — current flat format, version 0.2.0 (VERSION is 0.2.1)
- `.claude-plugin/plugin.json` — current plugin manifest, version 0.2.0
- `.claude-plugin/SCHEMAS/skill.schema.json` — existing schema (pattern for agent.schema)
- `.claude-plugin/SCHEMAS/agent.schema.json` — existing schema

### CI/CD reference
- `.github/workflows/ci.yml` — add version-check step + claude CLI install + validate
- `.github/workflows/release.yml` — existing tag+release pipeline (reference for structure)

### External research required (researcher task)
- `anthropics/claude-plugins-community` GitHub repo — canonical catalog JSON schema,
  PR process, required fields for community submission
- Official claude CLI install method — exact install script URL / command for CI step
- `claude plugin validate .` API — which files it validates, expected output, exit codes

### Write chokepoint (invariant — must not bypass)
- `lib/mutate.sh` — all filesystem writes go through mutate_write/mutate_cp/mutate_mkdir
- `cli/conjure` §cmd_init/cmd_audit/cmd_update — patterns for new cmd_publish dispatch

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `lib/mutate.sh` — mutate_write, mutate_cp, mutate_mkdir; `$CONJURE_DRYRUN` env guard
- `cli/conjure:50` — `cmd_version()` pattern (reads VERSION file); `conjure publish` reads same file
- `cli/conjure:273-282` — dispatch table pattern; cmd_publish slots in here
- `cli/conjure:259` — `cmd_preflight()` — call before publish to verify environment
- `.github/workflows/ci.yml` — JSON validate step (`find .claude-plugin -name '*.json' -exec jq empty {} \;`) — extend, don't replace

### Established Patterns
- `--dry-run` → `CONJURE_DRYRUN=1` env var; all mutations check this before writing
- Dirty-tree abort pattern: `git diff --quiet && git diff --cached --quiet || abort`
  (not currently in cli/conjure but standard bash; add to publish)
- All new shell scripts go under `scripts/` and are shellcheck-clean
- Tests inline in `tests/run.sh` — no new fixture dirs for this phase

### Integration Points
- `conjure publish` is a new top-level command dispatched from `cli/conjure` main case
- `scripts/publish-plugin.sh` sources `lib/mutate.sh` (same as other scripts)
- CI: new step(s) added to existing `test` job in ci.yml (don't create a new job unless
  the claude CLI install warrants isolation)
- `submit-entry.json` written via mutate_write into `.claude-plugin/`

</code_context>

<specifics>
## Specific Ideas

- `conjure publish --submit` → stdout checklist + `.claude-plugin/submit-entry.json` (committed)
- `conjure publish` aborts on dirty tree (not just a warning)
- CI: both jq + claude validate, claude install failure = CI failure
- version bump is part of `conjure publish` (reads VERSION, writes to both JSON files)

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 10-marketplace-publish*
*Context gathered: 2026-05-25*
