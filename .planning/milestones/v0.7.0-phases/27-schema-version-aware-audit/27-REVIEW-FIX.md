---
phase: 27-schema-version-aware-audit
fixed_at: 2026-06-03T00:00:00Z
review_path: .planning/phases/27-schema-version-aware-audit/27-REVIEW.md
iteration: 1
findings_in_scope: 5
fixed: 5
skipped: 0
status: all_fixed
---

# Phase 27: Code Review Fix Report

**Fixed at:** 2026-06-03
**Source review:** .planning/phases/27-schema-version-aware-audit/27-REVIEW.md
**Iteration:** 1

**Summary:**
- Findings in scope: 5 (all WARNING)
- Fixed: 5
- Skipped: 0
- Info items (out of default scope): IN-01 fixed (trivial, non-regressing); IN-02, IN-03 noted and skipped

All fixes verified empirically (boolean-value message, tempfile-leak before/after counts,
porcelain stdout cleanliness, newer-key WARN) plus `bash -n`, `shellcheck -S error -e
SC2164,SC2044,SC2034,SC2155`, and the full suite. Suite went from 521 PASS / 0 FAIL to
**523 PASS / 0 FAIL** (+2 new regression tests for WR-04 and WR-05). Zero regressions.

## Fixed Issues

### WR-02: New EXIT trap in check.sh clobbers MANIFEST cleanup trap (tempfile leak)

**Files modified:** `scripts/check.sh`
**Commit:** 55b37a3
**Applied fix:** Replaced the two competing `trap ... EXIT` registrations with one combined
cleanup function `_check_cleanup() { rm -f "${MANIFEST:-}" "${_SCHM03_TMP:-}" "${_SCHM04_NEWER:-}"; }`
registered once near line 29. Removed the SCHM-03 block's `trap 'rm -f "${_SCHM03_TMP:-}"' EXIT`
(which had been silently overwriting the single EXIT slot and orphaning `$MANIFEST`). Verified:
no tempfile leak in normal or `--schema` mode (TMPDIR file count identical before/after).

### WR-04: `check --porcelain --schema` writes SCHM-04 report to stdout, corrupting machine output

**Files modified:** `scripts/check.sh`
**Commit:** 55b37a3
**Applied fix:** Introduced `_schm04_out()` which routes every SCHM-04 line to stderr when
`PORCELAIN=1` (mirroring SCHM-03's `>&2`) and to stdout otherwise. The Schema Version Report,
the claude-absent WARN, the newer-key WARN, and the staleness WARN all flow through it. Verified
empirically: with `--porcelain --schema` on a drifted harness, stdout contains only `M/R/A` lines
— no "Schema Version Report" / "introduced:" text. New regression test added (see test commit).

### WR-05: SCHM-04 reports introduced_version but never compares/flags against detected CC version

**Files modified:** `scripts/check.sh`
**Commit:** 55b37a3 (fix) + 1aa48d5 (test)
**Applied fix:** Added a forward-compat comparison. While printing each key's `introduced:`
version, keys whose `introduced_version` is a real semver and greater than the detected
`claude --version` are collected (via `sort -V` numeric compare) into a tempfile, then emitted
as advisory `SCHM-04 [warn]` lines after the report. Never fails (exit stays ≤1 for this path);
newer-than-known is advisory per the SCHM-04 non-goal. The comparison is skipped entirely when
`claude` is absent or unparseable (`_CC_PRESENT=0`) — that path already WARNs about absence.
Verified: stubbing `claude` to report 2.1.105 flags `skillOverrides` (introduced 2.1.129) with a
WARN and exits non-2. New regression test added.

**Note:** This finding alters runtime logic (a new version-comparison branch). The implementation
was verified empirically against a stubbed CC version, but the maintainer should confirm the
semver comparison semantics match intent (e.g. behavior for keys valued "all"/"unknown", which are
correctly excluded). Flagged as requires-human-verification per the logic-bug guidance.

### WR-01: SCHM-02 message prints blank value for boolean `false`

**Files modified:** `scripts/audit-setup.sh`
**Commit:** 8a3e508
**Applied fix:** Changed the value extraction from `jq -r "${_dbpm_path} // empty"` (which
collapses falsy `false` to "") to `jq -r "${_dbpm_path} | tostring"`. The check already only runs
when `type=="boolean"`, so the key is always present (no null guard needed). Verified: `false` now
renders `got: false` and `true` still renders `got: true`; both still fail with exit 2 and the
permissions.* path still fails (POL-05c preserved).

### WR-03: New CHECKS_JSONL trap in audit-setup.sh clobbered by COST_TMP trap (tempfile leak)

**Files modified:** `scripts/audit-setup.sh`
**Commit:** 8a3e508
**Applied fix:** Promoted `_audit_cleanup` to the top (near line 25) as
`_audit_cleanup() { rm -f "${CHECKS_JSONL:-}" "${COST_TMP:-}"; }`, registered once on EXIT.
Removed the `--cost` block's re-registration that had been clobbering the CHECKS_JSONL trap.
`COST_TMP` is unset unless `--cost` ran and `:-` expands it to empty harmlessly. Verified: no
tempfile leak in `--cost` or `--json` mode (TMPDIR count identical before/after).

### IN-01: Dead tempfile `_schm01_warn_jchecks` (created, written, never read)

**Files modified:** `scripts/audit-setup.sh`
**Commit:** 8a3e508
**Applied fix (trivial, non-regressing):** Deleted the unused `_schm01_warn_jchecks` mktemp, its
write at the unknown-field branch, and its name from the `rm -f`. The emitted JSON message already
sourced from `_schm01_warn_errs`, so removing the dead parallel file changes no behavior — it only
eliminates the orphaned tempfile. JSON message text is unchanged (still suffix-inclusive).

## Skipped Issues

### IN-02: SCHM-04 `claude --version` parse depends on version being field 1

**File:** `scripts/check.sh:214`
**Reason:** Noted and skipped — out of default `critical_warning` scope and not strictly trivial.
The current `awk '{print $1}'` works for the present CC output (`2.1.161 (Claude Code)`) and fails
safe (falls back to schema baseline + WARN) for hypothetical future formats. Changing to a
`grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1` extractor is a reasonable hardening but carries a
small regression surface against the existing SCHM-04 tests; deferred to avoid scope creep. No
correctness defect today.

### IN-03: BSD `date -j -f "%Y-%m-%d"` uses current time-of-day, fuzzing the 90-day boundary

**File:** `scripts/audit-setup.sh:400-404` and `scripts/check.sh:243-247`
**Reason:** Noted and skipped — out of default scope; cosmetic <1-day fuzz on a strict `>90`
non-blocking advisory WARN, explicitly classified non-correctness by the reviewer. Anchoring to
midnight (`"$DATE 00:00:00"` with a `%H:%M:%S` format) is the documented optional fix but touches
two cross-platform date paths with their own fixture coverage; deferred to avoid risking the
SCHM-STALE / staleness tests for a one-day cosmetic boundary effect.

---

_Fixed: 2026-06-03_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
