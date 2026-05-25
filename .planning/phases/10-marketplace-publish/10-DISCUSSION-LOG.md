# Phase 10: Marketplace Publish - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-25
**Phase:** 10-marketplace-publish
**Areas discussed:** claude plugin validate in CI, marketplace.json structure, conjure publish --submit output, SHA vs tag in install field

---

## claude plugin validate in CI

| Option | Description | Selected |
|--------|-------------|----------|
| Install claude CLI in CI | Add step to download claude CLI binary; real validation, +~30s CI time | |
| jq schema validation instead | Validate against SCHEMAS/ using jq; faster, no binary, may miss semantic checks | |
| Both: jq schema + claude validate | Run jq always + install claude CLI + run validate; belt-and-suspenders | ✓ |

**User's choice:** Both: jq schema + claude validate

| Option | Description | Selected |
|--------|-------------|----------|
| Official install script, fail CI on install failure | If install fails, CI fails; ensures validate always runs | ✓ |
| Official install script, skip validate on install failure | Prevents flaky CI if network issues | |
| Pin to specific claude CLI release tag | Deterministic; no surprise breakage | |

**User's choice:** Official install script, fail CI on install failure

| Option | Description | Selected |
|--------|-------------|----------|
| I don't know — researcher should figure this out | Let researcher read official docs | ✓ |
| It validates the whole .claude-plugin/ dir | Assumes validate scans all files in the dir | |
| It only validates plugin.json | plugin.json is the canonical manifest target | |

**User's choice:** Researcher investigates `claude plugin validate .` behavior (which files, exit codes, output format)

---

## marketplace.json Structure

| Option | Description | Selected |
|--------|-------------|----------|
| Restructure existing marketplace.json to owner+plugins[] | One canonical file in community catalog format | |
| Keep existing file, generate catalog entry separately | conjure publish --submit generates separate snippet | |
| Researcher decides — study catalog format first | Researcher reads anthropics/claude-plugins-community before touching the file | ✓ |

**User's choice:** Researcher determines correct format from anthropics/claude-plugins-community before any restructuring

---

## conjure publish --submit Output

| Option | Description | Selected |
|--------|-------------|----------|
| Print to stdout — checklist + PR URL | Human-readable to terminal; no file written; no mutation needed | |
| Write PUBLISH-CHECKLIST.md to cwd | Markdown file user can track; mutation via mutate_write | |
| Stdout + write JSON snippet to .claude-plugin/submit-entry.json | Stdout for steps; JSON file for machine-readable catalog entry | ✓ |

**User's choice:** Stdout checklist + write `.claude-plugin/submit-entry.json`

| Option | Description | Selected |
|--------|-------------|----------|
| Committed to repo (Recommended) | Auditable record of what was submitted and when | ✓ |
| Gitignored — ephemeral | Treat as build artifact; never commit | |
| Claude decides | Planner picks based on audit patterns | |

**User's choice:** `submit-entry.json` committed to repo (through mutate_write)

---

## SHA vs Tag in Install Field

| Option | Description | Selected |
|--------|-------------|----------|
| Write HEAD SHA + require no uncommitted changes | git rev-parse HEAD; abort if dirty tree; guards against publishing wrong SHA | ✓ |
| Require release tag — abort if HEAD isn't tagged | HEAD must have a v* tag; writes tag ref + SHA; more ceremony | |
| Write HEAD SHA unconditionally | Always write HEAD; no dirty-tree check; could publish dev commits | |

**User's choice:** Write HEAD SHA + abort on dirty working tree

| Option | Description | Selected |
|--------|-------------|----------|
| Update SHA + version fields in both files | conjure publish bumps version in marketplace.json + plugin.json to match VERSION AND writes SHA | ✓ |
| SHA only — version is a separate manual step | User manually edits version before running conjure publish | |
| SHA only — CI catches version mismatch (MKTPL-02) | CI validates; publish doesn't auto-update version | |

**User's choice:** `conjure publish` updates both SHA and version in both files

---

## Claude's Discretion

- Exact JSON field layout inside `submit-entry.json` (researcher determines from catalog format)
- Exact wording of stdout checklist messages beyond items specified in D-11
- Whether cmd_publish in cli/conjure needs ~10 lines or more structure
- Function naming inside `scripts/publish-plugin.sh`

## Deferred Ideas

None — discussion stayed within phase scope.
