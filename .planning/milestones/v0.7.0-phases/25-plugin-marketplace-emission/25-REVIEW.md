---
phase: 25-plugin-marketplace-emission
reviewed: 2026-06-03T04:25:00Z
depth: standard
iteration: 4
files_reviewed: 5
files_reviewed_list:
  - lib/plugin-helpers.sh
  - scripts/emit-plugin.sh
  - scripts/publish-plugin.sh
  - scripts/audit-setup.sh
  - cli/conjure
findings:
  critical: 0
  warning: 0
  info: 1
  total: 1
status: clean
---

# Phase 25: Code Review Report (FINAL re-review)

**Reviewed:** 2026-06-03T04:25:00Z
**Depth:** standard
**Files Reviewed:** 5
**Status:** clean

## Summary

Final confirmation re-review of the last two commits in phase 25:

- **8b49651** — CR-01: derive a schema-valid `.name` in `plugin_build_plugin_json`
  on first-time (greenfield) emit, and thread `MKT_NAME` (the `--name` /
  `CONJURE_PLUGIN_MKT_NAME` value) as the plugin-name seed in `scripts/emit-plugin.sh`,
  plus a new greenfield regression test in `tests/run.sh`.
- **d599a49** — IN-01: `resolve_version` now skips blank leading lines in
  `.conjure-version` (`grep -m1 -v '^[[:space:]]*$'`) instead of blindly taking the
  first line.

**Scope note:** Of the five in-scope files, only `lib/plugin-helpers.sh` and
`scripts/emit-plugin.sh` were touched by these two commits. `scripts/publish-plugin.sh`,
`scripts/audit-setup.sh`, and `cli/conjure` were not modified by 8b49651 or d599a49 and
were re-checked only for caller-compatibility with the new `plugin_build_plugin_json`
signature and the new `MKT_NAME` seeding — both remain compatible.

**Verdict: no new Critical or Warning regressions introduced by these commits, and no
real blocker on the core happy path.** Evidence:

- **Greenfield happy path verified live.** A first-time emit into a repo with no
  pre-existing `.claude-plugin/plugin.json` (dir `My_Cool_Repo`) exits 0 and emits
  `"name": "my-cool-repo"` — schema-valid, kebab-normalized, leading-letter constraint
  satisfied. Merge-preserve of existing user fields is intact; an existing user-set
  `.name` is never overwritten (`(if (.name // "") == "" and $name != "" ...)`).
- **CR-01 normalization symmetry confirmed.** The derived-name path reuses the same
  `^[a-z][a-z0-9-]{0,63}$` constraint used for marketplace names; a non-conforming
  derived basename is dropped to empty and validation surfaces a clear "name required"
  error rather than emitting an invalid name. The PLUG-04 test was correctly updated
  (target basename `123`, which is non-conforming because it lacks a leading letter)
  to keep exercising the "no name available → exit 2" path.
- **IN-01 verified.** Leading blank lines are skipped (`\n\n  1.2.3  ` → `1.2.3`),
  a wholly whitespace-only file still resolves empty and falls through to Tier 2/3
  (preserving WR-01), and the first non-blank line wins. `grep -m1 -v` is portable
  across GNU and BSD/macOS grep.
- **Project gate clean.** `shellcheck -S error -e SC2164,SC2044,SC2034,SC2155` passes
  on both modified files. `exit 2` / never-`exit 1` convention upheld; mutations still
  route through `mutate_write` / `mutate_mkdir`; backup-before-mutate snapshot logic
  unchanged.
- **Full suite green.** `tests/run.sh` → PASS: 485, FAIL: 0, including the new
  `PLUG-01-greenfield/CR-01` test and all PLUG-01..PLUG-05 / PLUG-REC / PLUG-REFSHA tests.

Per instruction, WR-07 (note vs warn — intentional) and previously-resolved findings
were not re-litigated.

## Info

### IN-01: Non-conforming explicit `--name` (without `--marketplace`) exits 2 instead of falling back to basename derivation

**File:** `lib/plugin-helpers.sh:231-237`, `scripts/emit-plugin.sh:85`
**Issue:** Now that `MKT_NAME` seeds `plugin_build_plugin_json`'s `fallback_name`, a
caller who passes a malformed `--name` (e.g. `--name "Bad_Caps"`) WITHOUT `--marketplace`
takes a new path: because `fallback_name` is non-empty, the basename-derivation branch
is skipped, then the regex gate drops the malformed value to empty. On a greenfield repo
whose directory basename WOULD have produced a valid name, the emit instead exits 2 with
`✗ plugin.json: 'name' is required and must be a non-empty string`. This is correct
invalid-input rejection (exits 2 cleanly, no data loss, no crash, no bad output written),
but the message reads as "name missing" rather than "name invalid", and the user loses
the would-be basename fallback in this one corner case. The `--marketplace` path is
unaffected — it still hard-rejects a bad `--name` at `emit-plugin.sh:127` with a precise
message before any write. Not a regression on the happy path; flagged Info only.
**Fix (optional, low priority):** If a more precise UX is desired, emit a distinct
warning when a non-empty explicit `fallback_name` is dropped by the regex gate, e.g.
after line 236:
```bash
if [ -n "$3" ]; then
  echo "WARN: --name '$3' is not a valid kebab name (^[a-z][a-z0-9-]{0,63}$) — ignoring" >&2
fi
```
No action required for this phase; behavior is safe and the happy path is unaffected.

---

_Reviewed: 2026-06-03T04:25:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
