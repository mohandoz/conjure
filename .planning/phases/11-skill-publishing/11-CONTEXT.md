# Phase 11: Skill Publishing - Context

**Gathered:** 2026-05-25
**Status:** Ready for planning

<domain>
## Phase Boundary

Implement `conjure publish-skill <name>` — a command that validates a project
skill against schema, size cap, and a static egress scan, then stages the
contribution and prints the `gh pr create` command for the user to run.

Delivers:
- `scripts/publish-skill.sh` + `cmd_publish_skill` dispatch in `cli/conjure`
- Frontmatter validation against `.claude-plugin/SCHEMAS/skill.schema.json`
- Size cap check (≤200 lines, consistent with CLAUDE.md constraint)
- Static egress scan: grep for `curl`/`wget`/`nc`/`fetch`/`http(s)://` patterns
  AND `$HOME`/`$USER`/`$SECRET` env var refs — hard block (exit 1) on any hit
- SHA-pinning guards: skill file must be committed (no dirty state); conjure
  version must be a tagged release (not a branch HEAD)
- `gh pr create` command printed (not executed) when `gh` is present; manual
  PR URL + checklist when `gh` is absent
- `--to <org/repo>` flag: same staged + print flow, just targets a different repo
- `--dry-run` honored via `CONJURE_DRYRUN` env var

Does NOT introduce the org overlay system (Phase 12), Homebrew (Phase 13),
Docker (Phase 14), or automated fork+PR execution.

</domain>

<decisions>
## Implementation Decisions

### Egress Scan (SKILL-01)
- **D-01:** Scan scope covers three categories in the SKILL.md body:
  - Shell exfil tool patterns: `curl`, `wget`, `nc`, `fetch`
  - Hard-coded URL patterns: `http://`, `https://`
  - Sensitive env var refs: `$HOME`, `$USER`, `$SECRET` (and common variants)
- **D-02:** Any egress scan hit is a hard block — exit 1 and print which lines
  matched. User must remove the pattern before the skill can be submitted.
  No warn-and-continue option.

### PR Submission Flow (SKILL-02, SKILL-04)
- **D-03:** When `gh` is present: `conjure publish-skill` validates + stages
  the skill content, then **prints** the exact `gh pr create` command for the
  user to run. Does NOT execute `gh pr create` itself — user controls when the
  PR fires. Consistent with ARCHITECTURE.md's "print instructions" intent and
  Phase 10's `--submit` checklist pattern.
- **D-04:** When `gh` is absent: print the manual PR URL for
  `mohandoz/conjure` (or the `--to` target) plus a step-by-step checklist.
  Matches Phase 10's fallback pattern.
- **D-05:** `--to <org/repo>` uses the same staged + print flow, just
  substitutes the target repo in the printed `gh pr create` command. No extra
  automation for private repos — same minimal touch as the default path.
- **D-06:** What gets submitted (SKILL.md vs. SKILL.md + plugin.json stub) is
  left to researcher/planner to determine based on `mohandoz/conjure`
  contribution conventions.

### SHA-Pinning (SKILL-03)
- **D-07:** Two guards run before any submission step:
  1. **Skill clean check:** `git status --porcelain .claude/skills/<name>/` must
     be empty. Failure message: `"Skill has uncommitted changes. Commit first:
     git add .claude/skills/<name>/ && git commit"`
  2. **Conjure version tag check:** `git describe --exact-match HEAD 2>/dev/null`
     must succeed (HEAD is a tagged commit). Failure message: `"Conjure version
     <X> is not a tagged release. Run from a tagged commit."`
- **D-08:** Both checks exit 1 with specific per-failure messages (not a
  combined generic message).

### Claude's Discretion
- Exact content of the plugin.json stub (if any) — researcher determines from
  `mohandoz/conjure` contribution conventions
- Function naming inside `scripts/publish-skill.sh`
- Exact PR body/title template for the printed `gh pr create` command
- Whether to update `.conjure-version` or any audit trail after successful
  staging

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Requirements and success criteria
- `.planning/REQUIREMENTS.md` §"Skill Publishing (DIST-04)"
  — SKILL-01 through SKILL-04, the four locked requirements
- `.planning/ROADMAP.md` §"Phase 11: Skill Publishing"
  — success criteria (4 items) and phase goal

### Architecture decisions
- `.planning/research/ARCHITECTURE.md` §"3. `scripts/publish-skill.sh` (DIST-04)"
  — component design, flow, what it emits
- `.planning/research/ARCHITECTURE.md` §"Modified Components" §`cli/conjure`
  — `cmd_publish_skill` estimated at ~15 lines; dispatch table pattern

### Existing code to read before implementing
- `scripts/publish-plugin.sh` — structural template for publish-skill.sh;
  reuse arg-parsing, mutate.sh sourcing, exit code conventions, and
  `--dry-run` env pattern
- `cli/conjure` lines 264-282 — `cmd_publish()` pattern; `cmd_publish_skill`
  follows the same shape
- `cli/conjure` lines 273-297 — dispatch table; `publish-skill` case slots here
- `lib/mutate.sh` — all filesystem writes MUST route through mutate_write
- `.claude-plugin/SCHEMAS/skill.schema.json` — schema to validate frontmatter
  against (already exists; reuse directly)
- `tests/run.sh` — existing test ID conventions before writing SKILL-NN blocks

### Write chokepoint (invariant)
- `lib/mutate.sh` — all new writes go through `mutate_write`/`mutate_cp`/`mutate_mkdir`
- `CONJURE_DRYRUN` env var — all mutation paths check this before writing

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `scripts/publish-plugin.sh` — identical structure: source mutate.sh, arg
  parsing, prerequisite checks, business logic; copy skeleton, change logic
- `lib/mutate.sh` — `mutate_write`; dry-run handled transparently once sourced
- `.claude-plugin/SCHEMAS/skill.schema.json` — schema exists; validate via
  `jq` against it (same pattern as Phase 10's JSON validation step)
- `cli/conjure cmd_publish()` at line 264 — `cmd_publish_skill` follows same
  ~15-line shell dispatch pattern

### Established Patterns
- `--dry-run` → `CONJURE_DRYRUN=1`; all mutation paths check this
- Dirty-tree abort: `git status --porcelain <path>` → non-empty = abort
- Exit codes: 0 = success, 1 = validation/user-fixable error,
  2 = hard prereq failure (missing dep, missing file)
- All new shell scripts shellcheck-clean; added to shellcheck glob in ci.yml
- Tests inline in `tests/run.sh` with `SKILL-NN` test IDs

### Integration Points
- `cli/conjure` dispatch table at line 297 — add `publish-skill)` case
- `scripts/publish-skill.sh` is a new worker; `cmd_publish_skill` in cli/conjure
  just parses flags + passes them to the script (same as cmd_publish → publish-plugin.sh)
- CI `shellcheck` glob in `.github/workflows/ci.yml` — add `scripts/publish-skill.sh`
  (it should already cover `scripts/*.sh` but confirm the glob)

</code_context>

<specifics>
## Specific Ideas

- Egress scan: hard block on any hit — no warn-and-continue
- SHA-pinning: two distinct checks with per-failure messages (not a combined message)
- PR flow: print the `gh pr create` command, don't execute it; `--to` just swaps the repo target
- Exit code 1 for all validation failures (user-fixable); exit 2 for missing deps

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 11-skill-publishing*
*Context gathered: 2026-05-25*
