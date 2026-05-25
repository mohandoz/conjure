# Phase 6: Cost Estimator - Context

**Gathered:** 2026-05-25
**Status:** Ready for planning

<domain>
## Phase Boundary

Extend `conjure audit` with a `--cost` flag that adds an honest,
offline-by-default estimate of per-session harness token cost. Output
includes a dated price table, ±20% band, model name, and a per-skill
breakdown sorted by cost. An opt-in `--exact` flag calls Anthropic's
`count_tokens` endpoint when `ANTHROPIC_API_KEY` is set; otherwise falls
back to the chars/4 heuristic with an advisory.

Requirements: COST-01, COST-02, COST-03.

</domain>

<decisions>
## Implementation Decisions

### Implementation Location
- **D-01:** Cost logic lives inline in `scripts/audit-setup.sh` — added
  after the existing token estimate block (lines 122–128). No new script
  for the main logic path.
- **D-02:** `cli/conjure` `cmd_audit()` parses `--cost` and `--exact` flags
  and passes them through to `scripts/audit-setup.sh` as environment
  variables or positional args. Follows the same flag-parsing pattern used
  by `cmd_init` (while loop + case).

### Price Table
- **D-03:** `lib/prices.json` — JSON file with model name, pricing_date
  (YYYY-MM), input $/Mtok, and band_pct. Lives in `lib/` alongside
  `lib/mutate.sh`. Easy to grep-diff on updates; readable from both bash
  (`jq`) and Node.

### Flag Design
- **D-04:** `--cost` is a flag on `conjure audit` (not a new subcommand).
  The existing audit health checks run first; the cost section appends after
  the `PASS/WARN/FAIL` summary line. Existing audit output is not modified.
- **D-05:** `--exact` is a separate composable flag (e.g.,
  `conjure audit --cost --exact .`). Invokes `lib/exact-count.mjs` when
  `ANTHROPIC_API_KEY` is present; when absent, prints advisory and falls
  back to chars/4 heuristic — exit 0, not an error.

### Cost Output Format
- **D-06:** Per-skill breakdown: sorted ASCII table (columns: Skill | Chars
  | ~Tokens | Est. Cost), sorted by cost descending, TOTAL footer row.
  One row per SKILL.md file found, plus rows for CLAUDE.md and
  settings.json.
- **D-07:** ±band: ±20% fixed. Label format:
  `Estimate: $X.XX ±20% (chars/4 heuristic · prices: YYYY-MM · model: <name>)`.
  Never a bare precise number — always includes the band and the
  pricing-as-of date.
- **D-08:** Existing `.claude/ token estimate: ~N (well-tuned)` health-check
  line stays unchanged (it's already in the PASS/WARN/FAIL section).
  `--cost` adds a new `── Cost Estimate ──` section after the summary
  separator line.

### `--exact` Implementation
- **D-09:** `lib/exact-count.mjs` — calls Anthropic SDK
  `client.beta.messages.countTokens()`. Reads all `.claude/` context files,
  returns an exact token count. Consistent with the hook pattern (Node .mjs
  files in the project).
- **D-10:** When `ANTHROPIC_API_KEY` is absent:
  `[--exact] ANTHROPIC_API_KEY not set — falling back to chars/4 heuristic.`
  Then continues with normal --cost output. Exit 0.

### Claude's Discretion
- Exact column widths and padding in the ASCII table.
- Whether `lib/exact-count.mjs` reads all `.claude/` files or only context
  files (CLAUDE.md + skills + agents).
- Exact wording of advisory/fallback messages beyond what is stated above.
- Whether `jq` is required for `lib/prices.json` parsing or bash
  `grep`/`sed` is used for portability.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Requirements
- `.planning/REQUIREMENTS.md` §Cost Estimation — COST-01, COST-02, COST-03
  (the three requirements this phase addresses)
- `.planning/ROADMAP.md` §Phase 6 — Goal, success criteria, phase boundary

### Existing Code to Study
- `scripts/audit-setup.sh:115-139` — existing token estimate block; the
  `--cost` section extends this; do not break the existing health-check line
- `cli/conjure:113-117` — `cmd_audit()` to extend with `--cost`/`--exact`
  flag parsing; follow the same while/case pattern as `cmd_init` (line 55)
- `lib/mutate.sh` — example of a `lib/` shared file; `lib/prices.json` and
  `lib/exact-count.mjs` follow the same directory convention

### Cross-Cutting Constraints
- `CLAUDE.md` §Constraints — POSIX bash 3.2+ for scripts; no heavy runtime
  deps; `jq` is acceptable (it's in the preflight dependency table); no
  bundled tokenizer

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `scripts/audit-setup.sh` variables `TOTAL_CHARS` and `EST_TOKENS` (lines
  124–125) — already computed; cost section reads these directly rather than
  recomputing
- `cli/conjure cmd_init` flag-parsing loop (lines 55–61) — exact pattern to
  replicate for `--cost`/`--exact` in `cmd_audit`

### Established Patterns
- `pass()` / `warn()` / `err()` helpers in `audit-setup.sh` — use for any
  advisory output from the cost section
- `lib/` convention: shared helpers and data files; `prices.json` and
  `exact-count.mjs` belong here
- Node `.mjs` for on-demand computation (mirrors hook pattern; `lib/exact-count.mjs`
  is called by `audit-setup.sh` via `node "$CONJURE_HOME/lib/exact-count.mjs"`)

### Integration Points
- `cli/conjure:113` — `cmd_audit` entry point; add `--cost` / `--exact` to
  argument parsing here before delegating to `audit-setup.sh`
- `scripts/audit-setup.sh:139` (end of file) — cost section inserted after
  the summary block but before the final `exit` lines
- `tests/run.sh` — existing audit fixture tests should still pass (cost
  section not triggered without `--cost` flag)

</code_context>

<specifics>
## Specific Ideas

- Output label format locked:
  `Estimate: $X.XX ±20% (chars/4 heuristic · prices: YYYY-MM · model: <name>)`
- `lib/prices.json` structure (minimum fields):
  `{ "model": "...", "pricing_date": "YYYY-MM", "input_per_mtok": N, "band_pct": 20 }`
- `--exact` fallback advisory wording locked:
  `[--exact] ANTHROPIC_API_KEY not set — falling back to chars/4 heuristic.`

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 6-Cost Estimator*
*Context gathered: 2026-05-25*
