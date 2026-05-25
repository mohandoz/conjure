# Phase 6: Cost Estimator - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-25
**Phase:** 6-Cost Estimator
**Areas discussed:** Code location, Price table format, --cost flag scope, --exact flag depth, Per-skill breakdown format, ±band width, --exact fallback behavior, Relationship to existing estimate

---

## Code Location

| Option | Description | Selected |
|--------|-------------|----------|
| Extend audit-setup.sh inline | Add --cost logic after existing token estimate block | ✓ |
| New lib/cost-estimate.sh | Sourced shared helper | |
| New scripts/cost-estimate.sh | Separate script called from cmd_audit | |

**User's choice:** Extend audit-setup.sh inline
**Notes:** Smallest change; cost logic co-located with file-size data already measured there.

---

## Price Table Format

| Option | Description | Selected |
|--------|-------------|----------|
| lib/prices.json | JSON file: model, pricing_date, $/Mtok, band_pct | ✓ |
| Static bash variables in audit-setup.sh | Inline variables | |
| Embedded in cli/conjure as here-doc | Centralized in CLI | |

**User's choice:** lib/prices.json
**Notes:** Readable, easy to grep-diff on updates; consistent with lib/ as shared-data home.

---

## --cost Flag Scope

| Option | Description | Selected |
|--------|-------------|----------|
| Flag on `conjure audit` — cost appended | Full audit + cost section after summary | ✓ |
| Flag on `conjure audit` — cost replaces | Skips health checks, cost-only view | |
| New `conjure cost` subcommand | Standalone top-level command | |

**User's choice:** Flag on `conjure audit` — cost appended to audit output
**Notes:** Consistent with existing flag pattern; keeps "audit tells you about cost" discoverable.

---

## --exact Flag Depth

| Option | Description | Selected |
|--------|-------------|----------|
| Implement now via lib/exact-count.mjs | Node .mjs calling Anthropic SDK countTokens() | ✓ |
| Stub with advisory message | Defer SDK dependency to Phase 7+ | |
| You decide | Planner chooses | |

**User's choice:** Implement now via lib/exact-count.mjs
**Notes:** Keeps phase self-contained; satisfies COST-03 fully; consistent with hook .mjs pattern.

---

## Per-Skill Breakdown Format

| Option | Description | Selected |
|--------|-------------|----------|
| Sorted ASCII table with totals | Skill \| Chars \| ~Tokens \| Est. Cost, sorted by cost desc, TOTAL footer | ✓ |
| Simple ranked list | One line per skill: "$0.0012  skill-name (1,234 tokens)" | |
| You decide | Planner picks format | |

**User's choice:** Sorted ASCII table with totals
**Notes:** Matches existing tabular style of conjure audit output.

---

## ±Band Width

| Option | Description | Selected |
|--------|-------------|----------|
| ±20% fixed | Simple, honest, easy to code | ✓ |
| ±15–25% based on content type | Varies by code vs. prose density | |
| You decide | Planner chooses | |

**User's choice:** ±20% fixed
**Notes:** Matches "no false precision" goal of COST-02; simple to explain and implement.

---

## --exact Fallback Behavior

| Option | Description | Selected |
|--------|-------------|----------|
| Print advisory, fall back to heuristic, exit 0 | Non-disruptive for missing key | ✓ |
| Print advisory and exit non-zero | Strict failure signal | |
| You decide | Planner picks | |

**User's choice:** Print advisory, fall back to heuristic, exit 0
**Notes:** Non-disruptive for CI users who forget to set ANTHROPIC_API_KEY.

---

## Relationship to Existing Estimate

| Option | Description | Selected |
|--------|-------------|----------|
| Keep existing line; --cost adds section below | No regression to existing audit output | ✓ |
| Promote existing line to always show ±band | Always shows basic cost without --cost | |
| Replace existing line when --cost is used | Suppresses existing line with --cost | |

**User's choice:** Keep existing line always; --cost adds detailed section below
**Notes:** Avoids breaking EXPECT files or changing existing audit output format.

---

## Claude's Discretion

- Exact column widths and padding in the ASCII table
- Whether lib/exact-count.mjs reads all .claude/ files or only context files
- Whether jq is required for prices.json parsing or bash grep/sed is used
- Exact wording of advisory/fallback messages beyond locked strings

## Deferred Ideas

None — discussion stayed within phase scope.
