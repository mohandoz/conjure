---
phase: 25-plugin-marketplace-emission
fixed_at: 2026-06-03T03:38:19Z
review_path: .planning/phases/25-plugin-marketplace-emission/25-REVIEW.md
iteration: 1
findings_in_scope: 9
fixed: 8
skipped: 1
status: partial
---

# Phase 25: Code Review Fix Report

**Fixed at:** 2026-06-03T03:38:19Z
**Source review:** .planning/phases/25-plugin-marketplace-emission/25-REVIEW.md
**Iteration:** 1

**Summary:**
- Findings in scope (Critical + Warning): 9
- Fixed: 8
- Skipped: 1 (WR-07 — assessed CORRECT by reviewer; intentionally not changed)

All 8 applied fixes verified with re-read + `bash -n` + `shellcheck -S error -e SC2164,SC2044,SC2034,SC2155`, plus targeted functional tests. Full suite `bash tests/run.sh` ends at **483 PASS / 0 FAIL** (matches pre-fix baseline — no regression).

## Fixed Issues

### CR-01: publish-plugin.sh violates `exit 2 never exit 1` convention

**Files modified:** `scripts/publish-plugin.sh`
**Commit:** cd35371
**Applied fix:** Replaced all six `exit 1` paths (unknown-arg, two invalid-existing-JSON, two jq-produced-invalid-JSON, invalid submit-entry JSON) with `exit 2`, and rewrote the header exit-code block to the single `2 = hard failure` contract. Verified no `exit 1` remains in the file.

### CR-02: Emission overwrites manifests with no backup-before-mutate

**Files modified:** `scripts/emit-plugin.sh`, `scripts/publish-plugin.sh`, `tests/run.sh`
**Commits:** ea85f52 (source code), 08d48d6 (test fixture)
**Applied fix:** Both emission workers now `source lib/log.sh` + `lib/snapshot.sh` and call `snapshot_create` into `.conjure-adopt-backups` before the first overwriting write, in live mode only (skipped under `DRY_RUN=1` and, for `emit-plugin.sh`, skipped when no pre-existing `plugin.json`/`marketplace.json`/`settings.json` would be overwritten). Mirrors the blessed `adopt.sh` snapshot mechanism. The backup path is echoed to the success report.

Adding the two new lib dependencies to `publish-plugin.sh` broke its test sandboxes (MKTPL-01, MKTPL-04), which copy only the scripts' dependency set into a temp dir — they did not copy `log.sh`/`snapshot.sh`, so the new `source` lines failed under `set -euo pipefail`. The fixture fix copies both new libs into the MKTPL and SUBMIT sandboxes, restoring the suite to green. (The emit-plugin tests invoke the real `$CONJURE_HOME/scripts/emit-plugin.sh` against the real `lib/`, so they needed no fixture change.)

**Requires human verification:** confirm the chosen backup root (`<target>/.conjure-adopt-backups` for emit; `<CONJURE_HOME>/.conjure-adopt-backups` for self-publish) and the skip-when-nothing-to-overwrite condition match intended product behavior.

### WR-01: Bash marketplace-name validator inconsistent with JSON schema

**Files modified:** `scripts/emit-plugin.sh`
**Commit:** 664e9db
**Applied fix:** Tightened the emitter gate from `^[a-z0-9][a-z0-9-]*$` to `^[a-z][a-z0-9-]{0,63}$` (leading letter only, ≤64 chars) to match `marketplace.schema.json`. Updated the error message accordingly.

### WR-02: Bash validators skip schema-required constraints

**Files modified:** `lib/plugin-helpers.sh`
**Commit:** 9ff5268
**Applied fix:** `validate_marketplace_json` now also enforces the schema `name` kebab pattern, the required string `owner.name`, and that each plugin `source` is an **object** (not merely non-null). Verified via functional tests: missing `owner.name`, string `source`, and leading-digit `name` are all now rejected; a valid manifest still passes.

### WR-03: Unescaped `$target` in `sed` substitution breaks on special characters

**Files modified:** `lib/plugin-helpers.sh`
**Commit:** 9ff5268
**Applied fix:** Replaced the `sed "s|$target/||"` prefix strip in `plugin_build_plugin_json` with a bash parameter-expansion loop (`${f#"$target/"}`) over `find` output via process substitution — no regex, no delimiter collision. Verified the emitted `agents` array contains correct relative `.claude/agents/*.md` paths.

### WR-04: `plugin_build_plugin_json` allowlist intent diverges from passthrough behavior

**Files modified:** `lib/plugin-helpers.sh`
**Commit:** 9ff5268
**Applied fix:** Documentation-only change (no behavior change). Added a comment on the merge stating the base is `.` (so all existing fields, including `displayName`/`commands`/`defaultEnabled`, pass through verbatim) and that the `($orig.x // null)` lines only re-assert specific fields — with an explicit warning not to switch the base to `{}` without carrying over every schema-known optional field.

### WR-05: `resolve_version` emits raw `.conjure-version` content with no validation/trim

**Files modified:** `lib/plugin-helpers.sh`
**Commit:** 9ff5268
**Applied fix:** Tier 1 now does `head -1 | tr -d '[:space:]'` instead of bare `cat`, so a trailing newline / multi-line / padded version file yields a clean single-line version. Verified a padded multi-line `.conjure-version` resolves to `1.2.3`.

### WR-06: Secret-scan regex relies on `\s` under POSIX `grep -E`

**Files modified:** `lib/plugin-helpers.sh`
**Commit:** 9ff5268
**Applied fix:** Replaced both `\s` occurrences (and the `\s` inside the negated char class) in the `secret_scan` pattern with the POSIX `[[:space:]]` class so whitespace matches on BSD/macOS `grep -E`, not just GNU. Verified a credential-assignment line written with spaces around the operator is now BLOCKed while clean JSON still passes.

## Skipped Issues

### WR-07: `note()` substituted for `warn()` in audit advisories

**File:** `scripts/audit-setup.sh:177-217`
**Reason:** Skipped per reviewer assessment and explicit task instruction — `note()` is CORRECT as-is. Switching back to `warn()` would increment `WARN`, flipping the audit from `exit 0` to `exit 1` purely on stale plugin metadata, breaking the documented advisory-only (exit 0) contract and the CI gate. The secondary nit (warning-glyph prefix on `note()` lines) is cosmetic and out of scope for this fix pass.
**Original issue:** Plan 25-03 specified `warn()`; executor used `note()`. Reviewer judged `note()` correct because `warn()` would have been a BLOCKER-class CI false-failure regression.

---

_Fixed: 2026-06-03T03:38:19Z_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
