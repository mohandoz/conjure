---
phase: 25-plugin-marketplace-emission
fixed_at: 2026-06-03T00:00:00Z
review_path: .planning/phases/25-plugin-marketplace-emission/25-REVIEW.md
iteration: 2
findings_in_scope: 3
fixed: 3
skipped: 0
status: all_fixed
---

# Phase 25: Code Review Fix Report (Iteration 2)

**Fixed at:** 2026-06-03T00:00:00Z
**Source review:** .planning/phases/25-plugin-marketplace-emission/25-REVIEW.md
**Iteration:** 2

**Summary:**
- Findings in scope: 3 (Warnings WR-01, WR-02, WR-03; Info findings out of scope)
- Fixed: 3
- Skipped: 0

Verification: `bash tests/run.sh` → **484 PASS / 0 FAIL** (was 483; one regression
test added for WR-01). `shellcheck -S error -e SC2164,SC2044,SC2034,SC2155` clean on
`lib/plugin-helpers.sh`, `scripts/emit-plugin.sh`, `cli/conjure`, and `tests/run.sh`.

## Fixed Issues

### WR-01: blank `.conjure-version` emitted `"version": ""` (regression from iteration-1 WR-05 fix)

**Files modified:** `lib/plugin-helpers.sh`, `tests/run.sh`
**Commit:** ff57cd9
**Applied fix:** In `resolve_version`, captured the `head -1 … | tr -d '[:space:]'`
result into `_ver` and only `printf`/`return 0` when it is non-empty. A blank or
whitespace-only file now logs `WARN: .conjure-version is empty` and falls through to
the Tier 2 (git SHA) / Tier 3 (`0.0.0`) fallbacks instead of returning the empty
string. Added regression test **PLUG-05-blank**: a whitespace-only `.conjure-version`
must yield a 40-char git SHA in the emitted `plugin.json`. Verified manually that a
blank file now resolves to the HEAD SHA and a populated file (`v1.2.3`) is still
honoured verbatim.

### WR-02: `validate_plugin_json` accepted empty `name` and empty `version`

**Files modified:** `lib/plugin-helpers.sh`
**Commit:** b3fb0c0
**Applied fix:** Tightened the two required-field jq predicates in the bundled
validator (the last gate before `mutate_write`). `name` now requires
`(.name | type) == "string" and (.name | length > 0)`; `version`, when present
(`.version != null`), requires a non-empty string. This rejects `"name": ""` /
`"version": ""` that previously flowed through unchanged via the `.`-based jq merge
base, and catches a blank version independently of WR-01 as defence in depth.

### WR-03: marketplace `--name` override was plumbed end-to-end but unreachable from the CLI

**Files modified:** `cli/conjure`, `scripts/emit-plugin.sh`
**Commit:** 08bad8a
**Applied fix:** Chose the wire-the-flag option (lower risk than removing the
plumbing, since the override is a genuine escape hatch for repo basenames that
auto-derivation cannot turn into a schema-valid name — e.g. digit-leading or
all-hyphen, which otherwise hard-`exit 2`). Added `--name`/`--name=*` cases to both
arg loops (`cmd_publish_plugin` in `cli/conjure` and the arg loop in
`scripts/emit-plugin.sh`), feeding `mkt_name` / `MKT_NAME` which were already
threaded into the marketplace path. Surfaced `[--name <kebab-name>]` in both usage
strings and the emit-plugin.sh Options header comment. `CONJURE_PLUGIN_MKT_NAME`
remains the env path; `--name` is now the documented CLI route.

---

_Fixed: 2026-06-03T00:00:00Z_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 2_
