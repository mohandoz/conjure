# Phase 11: Skill Publishing - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-25
**Phase:** 11-skill-publishing
**Areas discussed:** Egress scan scope, PR submission flow, SHA-pinning semantics

---

## Egress Scan Scope

| Option | Description | Selected |
|--------|-------------|----------|
| Shell exfil patterns only | Grep for curl/wget/nc/fetch/http:// in SKILL.md body | |
| Hard-coded URLs only | Only flag http:// and https:// strings | |
| Both patterns + env vars | Flag curl/wget/nc/fetch AND hard-coded URLs AND $HOME/$USER/$SECRET env var refs | ✓ |
| You decide | Leave egress scan scope to researcher/planner | |

**User's choice:** Both patterns + env vars — broadest coverage

---

| Option | Description | Selected |
|--------|-------------|----------|
| Hard block (exit 1) | Scan failure stops publish entirely | ✓ |
| Warn + confirm | Print hits, ask [y/N] to proceed | |
| Warn + log only | Print as warning but continue | |

**User's choice:** Hard block — no override path; user must fix before submitting

---

## PR Submission Flow

| Option | Description | Selected |
|--------|-------------|----------|
| Fork + branch + PR (fully automated) | Clone mohandoz/conjure, create branch, commit, push, run gh pr create | |
| Stage + print gh command | Validate, emit PR content, print exact `gh pr create` command for user to run | ✓ |
| You decide | Leave automation level to planner | |

**User's choice:** Stage + print — user controls when the PR fires

---

| Option | Description | Selected |
|--------|-------------|----------|
| SKILL.md only | Skill file is the contribution | |
| SKILL.md + plugin.json stub | Also emit plugin.json with richer metadata | |
| You decide | Let researcher determine from contribution conventions | ✓ |

**User's choice:** You decide — researcher determines from mohandoz/conjure conventions

---

| Option | Description | Selected |
|--------|-------------|----------|
| Same as default (stage + print) | `--to` just changes target repo in printed command | ✓ |
| More automated for private repos | Actually run gh pr create for private repos | |
| You decide | Leave to planner | |

**User's choice:** Same as default — consistent minimal automation regardless of target

---

## SHA-Pinning Semantics

| Option | Description | Selected |
|--------|-------------|----------|
| Skill must be committed | Skill file has clean git state; records last commit SHA | |
| Conjure kit version must be tagged | plugin.json stub references a tag-pinned conjure version | |
| Both: skill committed + conjure version tagged | Two guards: skill clean + conjure version is a tagged release | ✓ |

**User's choice:** Both guards — strongest pinning guarantees

---

| Option | Description | Selected |
|--------|-------------|----------|
| Specific per-failure messages | Distinct message per failure type (dirty skill vs. untagged version) | ✓ |
| Single generic message | One message covering both failures | |
| You decide | Wording to Claude's discretion | |

**User's choice:** Specific per-failure messages — clearer actionable guidance

---

## Claude's Discretion

- Exact content of plugin.json stub (if emitted) — researcher determines from mohandoz/conjure conventions
- Function naming inside scripts/publish-skill.sh
- Exact PR body/title template for the printed gh pr create command
- Whether to update any audit trail after successful staging

## Deferred Ideas

None — discussion stayed within phase scope.
