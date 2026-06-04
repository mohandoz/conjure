---
phase: 25-plugin-marketplace-emission
fixed_at: 2026-06-03T00:00:00Z
review_path: .planning/phases/25-plugin-marketplace-emission/25-REVIEW.md
iteration: 3
findings_in_scope: 2
fixed: 2
skipped: 0
status: all_fixed
---

# Phase 25: Code Review Fix Report

**Fixed at:** 2026-06-03T00:00:00Z
**Source review:** .planning/phases/25-plugin-marketplace-emission/25-REVIEW.md
**Iteration:** 3

**Summary:**
- Findings in scope: 2 (CR-01 critical; IN-01 info — fixed as trivial/non-regressing)
- Fixed: 2
- Skipped: 0
- Test suite after fixes: **485 PASS / 0 FAIL** (was 484/0; +1 new regression test)
- `shellcheck -S error -e SC2164,SC2044,SC2034,SC2155` clean on both modified shell files

## Fixed Issues

### CR-01: First-time `publish-plugin` always exits 2 — emitted plugin.json has no `name`

**Files modified:** `lib/plugin-helpers.sh`, `scripts/emit-plugin.sh`, `tests/run.sh`
**Commit:** 8b49651
**Classification:** Critical blocker (correctness — breaks the core greenfield happy path)

**Applied fix:**

1. **`plugin_build_plugin_json` now derives and sets `.name`** (lib/plugin-helpers.sh).
   Added a third parameter `fallback_name` (`local fallback_name="${3:-}"`). When the
   caller passes nothing, the name is derived from the target repo basename using the
   SAME kebab normalization already used for the marketplace name in emit-plugin.sh:
   `basename | tr '[:upper:]' '[:lower:]' | tr '_.' '-' | tr -cd 'a-z0-9-'`, then
   validated against the marketplace/plugin schema constraint `^[a-z][a-z0-9-]{0,63}$`
   (leading letter, ≤64 chars). A non-conforming derived name is dropped (set empty)
   so the validator surfaces a clear "name required" error rather than emitting a bad
   name.

2. **Merge-preserve, never overwrite.** The jq pipeline gained
   `(if (.name // "") == "" and $name != "" then .name = $name else . end)` placed
   before `.version = $version`. A user-set `.name` in an existing manifest is left
   untouched (re-run idempotency, verified by the existing PLUG-01-merge test); the
   derived name is only applied when the existing manifest has no name.

3. **`--name` / `CONJURE_PLUGIN_MKT_NAME` seeds the plugin name too.** Documented choice:
   the caller `scripts/emit-plugin.sh` now threads `MKT_NAME` (the marketplace name,
   possibly empty) as the third argument. When set, it seeds plugin.json's `name`; when
   empty, the helper derives from the basename. This keeps a single source of truth and
   means an explicit `--name` makes a first-time greenfield emit succeed (previously it
   could not — `--name` was wired only to the marketplace name).

4. **Regression test added** (`tests/run.sh`, `PLUG-01-greenfield/CR-01`). Creates a
   fresh git repo in a dir named `My_Cool_Repo` (mixed case + underscore, to exercise
   kebab normalization), copies the shared harness fixture, **removes the fixture's
   pre-existing `.claude-plugin/plugin.json`** so the merge base is `{}`, runs a
   first-time emit, and asserts exit 0 plus a schema-valid non-empty `.name`. This path
   was previously untested — the shared fixture ships a `plugin.json` carrying
   `"name": "test-plugin"`, which masked the greenfield bug.

5. **Pre-existing `PLUG-04` test updated to preserve its intent.** `PLUG-04` asserts
   that validation exits 2 when no name can be inferred. Since name derivation now
   succeeds for any kebab-able basename, the target was moved into a subdir named `123`
   (starts with a digit → fails `^[a-z]…` → derived name dropped → validator exits 2),
   keeping the original "no name available → exit 2" assertion meaningful. Trap/cleanup
   updated to the new parent dir.

**Conventions honored:** scripts exit 2 never 1 (unchanged paths preserved); POSIX bash
3.2+ (no associative arrays/mapfile/local -n; only bash parameter expansion + `tr` +
`grep -E`); shellcheck clean with the project's ignore set.

### IN-01: `.conjure-version` with a blank first line silently resolves to 0.0.0

**Files modified:** `lib/plugin-helpers.sh`
**Commit:** d599a49
**Classification:** Info (trivial, non-regressing — fixed per reviewer's optional suggestion)

**Applied fix:** `resolve_version` Tier 1 now reads the first **non-blank** line:
`grep -m1 -v '^[[:space:]]*$' "$target/.conjure-version" | tr -d '[:space:]'` replacing
`head -1 … | tr -d '[:space:]'`. A stray leading newline followed by a real version on
line 2 now resolves to that version instead of falling through to `0.0.0`. A wholly
blank / whitespace-only file still yields an empty result and correctly falls through to
the git-SHA / 0.0.0 tiers (verified — `PLUG-05-blank` writes a `\n`-only file and still
passes). Non-regressing: no existing test asserts the old leading-blank-line → 0.0.0
behavior.

---

_Fixed: 2026-06-03T00:00:00Z_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 3_
