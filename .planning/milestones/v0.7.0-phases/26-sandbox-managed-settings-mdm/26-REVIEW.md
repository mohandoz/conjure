---
phase: 26-sandbox-managed-settings-mdm
reviewed: 2026-06-03T14:00:00Z
depth: standard
files_reviewed: 3
files_reviewed_list:
  - lib/policy-helpers.sh
  - scripts/emit-policy.sh
  - scripts/audit-setup.sh
findings:
  critical: 0
  warning: 0
  info: 0
  total: 0
status: clean
---

# Phase 26: Code Review Report

**Reviewed:** 2026-06-03
**Depth:** standard
**Files Reviewed:** 3
**Status:** clean

## Summary

FINAL confirmation re-review (iteration 3), focused on commit `6ca9247`
("WR-01 translate merge secret-abort to exit 2 not exit 1"). The commit adds
`|| exit 2` at the two merge call sites in `scripts/emit-policy.sh` (lines 146
and 149) and hardens the `POL-secret-merged` test to assert exit exactly 2 plus
a no-write assertion.

The exit-code fix is correct, introduces no new Critical/Warning defects, and
all previously verified security invariants still hold. All 508 tests pass with
0 failures, and the three files clear the project shellcheck gate
(`-S error -e SC2164,SC2044,SC2034,SC2155`) with exit 0.

No Critical, Warning, or Info findings. Status: clean.

### 1. Exit-code fix correctness — CONFIRMED

- `merge_sandbox_block` (`lib/policy-helpers.sh:144`) and
  `merge_deny_read_permissions` (`:203`) call `secret_scan "$UPDATED" ... || return 1`
  **before** `mutate_write` (`:146`, `:205`). A secret in the operator's existing
  `settings.json` is detected on the merged result and the function returns 1 with
  no write performed.
- At the call sites (`scripts/emit-policy.sh:146,149`), `|| exit 2` translates the
  helper's `return 1` into a hard exit 2, satisfying the CLAUDE.md "scripts exit 2,
  never exit 1" contract. Verified empirically under `set -euo pipefail`: a function
  returning 1 followed by `|| exit 2` yields exit code exactly 2.
- Both merge functions are the **only** call sites; both now carry `|| exit 2`
  (error handling is consistent — no asymmetric site left behind).
- Test `POL-secret-merged` passes: "emit exits exactly 2 when operator's existing
  settings.json contains a credential". Test `POL-secret-merged-nowrite` passes:
  "emit secret-abort leaves operator's settings.json unchanged — no write".
- Normal (no-secret) path: `POL-01`, `POL-01-idem`, `POL-02-operator`,
  `POL-dryrun` all pass — emit writes settings + artifacts and exits 0.

### 2. No new regression from 6ca9247 — CONFIRMED

The diff is limited to two `|| exit 2` additions (plus comment) in
`scripts/emit-policy.sh` and a tightened test in `tests/run.sh`. No logic, no
helper signatures, and no data flow changed. shellcheck clean; full suite green
(508/508).

### 3. Core security invariants — ALL HOLD

- **Idempotent array merge**: `def array_merge(a; b): (a // []) + (b // []) | unique`
  used for both sandbox arrays (`policy-helpers.sh:119`) and `permissions.deny`
  (`:192`). `POL-01-idem` confirms re-run produces identical `settings.json`.
- **disableBypassPermissionsMode STRING "disable"**: managed-settings emits
  `[type, .] == ["string","disable"]` (verified on live emit); plist hardcodes
  `<string>disable</string>` (verified); `validate_managed_settings_json`
  rejects boolean (`:221`); audit `POL-05c` flags boolean unconditionally (`:239`).
- **denyRead → Read() mirror with double-slash**: `build_deny_read_entries`
  maps `/etc/foo → Read(//etc/foo)`, `~/.ssh → Read(~/.ssh)`, `./local → Read(/local)`,
  `bare → Read(bare)` (verified directly). emit/audit agree because audit
  (`audit-setup.sh:268`) reuses `build_deny_read_entries` as the single source of
  truth for the prefix convention.
- **No unknown managed-settings top-level keys**: emitted keys are exactly
  `allowManagedPermissionRulesOnly`, `forceLoginOrgUUID`, `permissions`, `sandbox`
  — no `_conjure_*` sentinel keys (verified on live emit).
- **validate-before-write → exit 2**: `validate_sandbox_json`,
  `validate_managed_settings_json`, and both `secret_scan` calls gate writes via
  `|| exit 2` (`emit-policy.sh:127,130,161,164`).
- **Advisory note() not warn()**: plugin reconciliation, marketplace ref-without-sha,
  and unreviewed-template checks use `note()` (no counter increment, exit 0) —
  `audit-setup.sh:191,196,202,218,251,284`.
- **$env:ProgramFiles not ProgramData**: `build_ps1_script` uses
  `Join-Path $env:ProgramFiles 'ClaudeCode'` (`policy-helpers.sh:531`); 0
  occurrences of `ProgramData` in the emitted ps1.

Per project convention, the pre-existing audit summary gate
`[ "$WARN" -gt 0 ] && exit 1` (`audit-setup.sh:408`) is the established contract
and is intentionally NOT flagged.

## Narrative Findings (AI reviewer)

No Critical, Warning, or Info findings. The exit-code fix is correct and complete,
introduces no regression, and all core security invariants remain intact.

---

_Reviewed: 2026-06-03_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
