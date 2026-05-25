---
phase: 07-skill-firing-telemetry
fixed_at: 2026-05-25T00:00:00Z
review_path: .planning/phases/07-skill-firing-telemetry/07-REVIEW.md
iteration: 1
findings_in_scope: 7
fixed: 7
skipped: 0
status: all_fixed
---

# Phase 07: Code Review Fix Report

**Fixed at:** 2026-05-25T00:00:00Z
**Source review:** .planning/phases/07-skill-firing-telemetry/07-REVIEW.md
**Iteration:** 1

**Summary:**
- Findings in scope: 7 (1 Critical, 6 Warning; Info findings excluded by fix_scope)
- Fixed: 7
- Skipped: 0

## Fixed Issues

### CR-01: awk expression injection when price-model lookup returns empty string

**Files modified:** `scripts/audit-setup.sh`
**Commit:** 7fd7f98
**Applied fix:** Added a guard for `PRICE_FILE` existence (`[ ! -f "$PRICE_FILE" ]`) as the first
branch of the cost block. Changed `jq -r '.default_model'` to `jq -r '.default_model // empty'` to
produce an empty string rather than the literal `"null"` when the key is absent. Added an explicit
`if [ -z "$PRICE_INPUT" ]` check that emits a clear diagnostic and skips the entire cost estimate
block, preventing the unsafe `awk "BEGIN {printf ... $PRICE_INPUT ...}"` expression from ever
executing with an empty variable. Corrected indentation of the nested cost block to match the new
three-level branching structure.

---

### WR-01: p.cwd used without null guard — silent data loss for UserPromptExpansion events

**Files modified:** `templates/hooks-nodejs/skill-telemetry.mjs`
**Commit:** 24afec9
**Applied fix:** Introduced `const cwd = p.cwd ?? process.cwd()` immediately before the record
construction. Both `project_cwd: p.cwd` and `path.join(p.cwd, ...)` were replaced with the safe
`cwd` variable. This prevents `path.join(undefined, ...)` from throwing a `TypeError` inside the
`try/catch`, which was silently swallowing all `UserPromptExpansion` telemetry records.

---

### WR-02: [retire?] status branch is dead code — retire-list feature cannot fulfil its purpose

**Files modified:** `scripts/audit-setup.sh`
**Commit:** 8fbb0ba
**Applied fix:** Replaced the `uniq -c` loop approach with a loop over installed `SKILL.md` files
found under `$TARGET/.claude/skills/`. For each installed skill, the telemetry log is queried
directly with `jq` to count matches in the last 30 days. Skills with zero fires correctly display
`[retire?]`; skills that appear in the log display `[active]`. This makes the `[retire?]` branch
reachable for the first time and fulfils the feature's stated purpose.

---

### WR-03: Sandbox temp directories leaked across fixture-loop iterations in tests/run.sh

**Files modified:** `tests/run.sh`
**Commit:** b585415
**Applied fix:** Added `rm -rf "$SANDBOX_DIR"` and `trap - EXIT` at the end of each loop body for
the fixture audit loop (TEST-01/02), the golden-file EXPECT loop (TEST-03), and the broken-fixture
block (TEST-04). This ensures each sandbox is cleaned immediately after use rather than relying on
an EXIT trap that gets overwritten on each subsequent `sandbox_setup` call.

---

### WR-04: source lib/mutate.sh failure is silently ignored

**Files modified:** `cli/conjure`
**Commit:** 3f550db
**Applied fix:** Added `|| { echo "✗ Failed to load lib/mutate.sh — check CONJURE_HOME ($CONJURE_HOME)"; return 1; }` after the `source` call. A missing or unreadable `lib/mutate.sh` now causes `cmd_init` to return 1 with a diagnostic message rather than silently proceeding to call undefined functions and exit 0.

---

### WR-05: UserPromptExpansion hook path not covered by any test

**Files modified:** `tests/run.sh`
**Commit:** 1b94ba4
**Applied fix:** Added TLMY-02b test block after the existing TLMY-02 field checks. The new block
constructs a `UserPromptExpansion` payload with `command_name: "/test-skill"` and `session_id:
"sess-002"`, pipes it to the hook with `CONJURE_TELEMETRY=1`, and asserts: (a) exit code 0,
(b) a second JSONL line was appended, (c) the new record contains `skill_typed` event type,
the correct skill name, and a `project_cwd` field. This test would have caught the WR-01
data-loss bug.

---

### WR-06: Description-length check silently misses unquoted descriptions

**Files modified:** `scripts/audit-setup.sh`, `tests/run.sh`
**Commit:** 3ffa7e6
**Applied fix:**
- `audit-setup.sh`: Changed the BRE `grep -q '^description: ".\{0,30\}"$'` to ERE
  `grep -qE '^description: "?.{0,29}"?$'`. The optional `"?` quotes now match both quoted
  (`description: "Short"`) and unquoted (`description: Short text`) frontmatter values.
  The character limit is correctly 29 (0-29 chars = fewer than 30) to match the `<30 chars`
  warning text.
- `tests/run.sh`: Replaced `echo "$desc_line" | ...` with `printf '%s' "$desc_line" | ...` to
  avoid the trailing newline that `echo` appends, which was inflating the measured length by 1 and
  causing 29-character descriptions to silently pass the threshold.

---

_Fixed: 2026-05-25T00:00:00Z_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
