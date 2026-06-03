---
phase: 26-sandbox-managed-settings-mdm
plan: "02"
subsystem: policy-emission
tags: [wave-2, managed-settings, mdm, plist, ps1, pol-03, pol-04, type-safety, posix-bash]
dependency_graph:
  requires:
    - "26-01"
  provides:
    - lib/policy-helpers.sh (Wave 2: validate_managed_settings_json, build_managed_settings, build_plist_xml, build_ps1_script)
    - scripts/emit-policy.sh (Wave 2 stubs replaced: managed-settings.json + plist + ps1 emit fully implemented)
  affects:
    - tests/run.sh (POL-03, POL-03-type, POL-04-macos, POL-04-win now PASS; FAIL 8→4)
tech_stack:
  added: []
  patterns:
    - validate-before-write discipline (validate_managed_settings_json type-safety gate before any mutate_write)
    - fixed-template plist renderer with plutil -lint post-validation gate on macOS
    - ps1 renderer using $env:ProgramFiles + UTF8Encoding($false) BOM-free output
    - build_managed_settings: disableBypassPermissionsMode as STRING "disable" (never boolean)
    - no _conjure_regime/_conjure_unreviewed top-level keys (RESEARCH.md Q1 RESOLVED)
    - XML metacharacter validation on denyRead paths before plist embed
    - secret_scan on MANAGED_JSON before any write (extends Wave 1 pattern to managed-settings)
key_files:
  created: []
  modified:
    - lib/policy-helpers.sh
    - scripts/emit-policy.sh
decisions:
  - "DENY_ENTRIES_JSON derived by piping build_deny_read_entries output through jq -R/jq -sc — consistent with existing Wave 1 merge_deny_read_permissions pattern"
  - "build_managed_settings always called even under --mdm-only since MANAGED_JSON is needed for ps1 heredoc content; only the managed-settings.json file write is conditional"
  - "validate_managed_settings_json uses two separate local variables (dbpm_type and dbpm_val) to avoid SC2155; pattern is explicit per RESEARCH.md Code Examples"
  - "build_plist_xml uses string concatenation (not heredoc) to allow conditional array sections — avoids heredoc quoting pitfalls in POSIX bash 3.2+"
metrics:
  duration: "~20 min"
  tasks_completed: 2
  files_created: 0
  files_modified: 2
  completed: "2026-06-03T10:00:00Z"
---

# Phase 26 Plan 02: Wave 2 — managed-settings.json emission (POL-03) and MDM artifact generation — macOS plist + Windows ps1 (POL-04) Summary

Wave 2 delivers the three-artifact MDM emission path: `managed-settings.json` (POL-03), macOS `com.anthropic.claudecode.plist` (POL-04-macos), and Windows `Set-ClaudeCodePolicy.ps1` (POL-04-win). The critical type-safety gate (`validate_managed_settings_json`) blocks boolean `disableBypassPermissionsMode` before any write. Tests POL-03, POL-03-type, POL-04-macos, POL-04-win are now GREEN.

## What Was Built

**Task 1: 4 new functions in lib/policy-helpers.sh**

`lib/policy-helpers.sh` now has 10 functions (6 from Wave 1 + 4 new):

- `validate_managed_settings_json(content)`: CRITICAL type-safety gate (T-26-07). Uses `jq -r '... | type'` to get the type of `disableBypassPermissionsMode` in a separate variable (SC2155-safe). Returns 1 if: (a) type is boolean, (b) type is string but value != "disable", (c) `allowManagedPermissionRulesOnly` is non-boolean (when present), (d) `forceLoginOrgUUID` is non-string (when present). Caller: `validate_managed_settings_json "$MANAGED_JSON" || exit 2`.
- `build_managed_settings(regime, deny_entries_json, sandbox_json)`: builds managed-settings JSON with `disableBypassPermissionsMode: "disable"` (string literal via jq), `allowManagedPermissionRulesOnly: true`, `forceLoginOrgUUID: "REPLACE_WITH_ORG_UUID"`. No `_conjure_regime` or `_conjure_unreviewed` top-level keys per RESEARCH.md Q1 RESOLVED.
- `build_plist_xml(deny_read_json, deny_entries_json, sandbox_json)`: fixed-template plist renderer. `disableBypassPermissionsMode` is hardcoded as `<string>disable</string>` (never `<true/>`). Validates denyRead paths for XML metacharacters (`&`, `<`, `>`) before embed (T-26-10). Runs `plutil -lint` post-render on macOS if available; skips on Linux.
- `build_ps1_script(regime, managed_settings_json)`: PowerShell renderer. Uses `$env:ProgramFiles` exclusively (never `C:\ProgramData\ClaudeCode\`); uses `[System.IO.File]::WriteAllText` with `UTF8Encoding($false)` for BOM-free output; embeds JSON via `jq '.'` into `@'...'@` heredoc.

**Task 2: Wave 1 stubs replaced in scripts/emit-policy.sh**

Stub block replaced with:
1. `DENY_ENTRIES_JSON` built from `build_deny_read_entries` output piped through `jq -R | jq -sc`
2. `MANAGED_JSON` always built via `build_managed_settings` (needed for both managed-settings.json and ps1 heredoc content)
3. `secret_scan "$MANAGED_JSON" "managed-settings.json" || exit 2` (T-26-11)
4. `validate_managed_settings_json "$MANAGED_JSON" || exit 2` (T-26-07)
5. `managed-settings.json` written to `$OUTPUT_DIR` (skipped when `--mdm-only`)
6. `com.anthropic.claudecode.plist` written via `build_plist_xml` (skipped when `--managed-only`)
7. `Set-ClaudeCodePolicy.ps1` written via `build_ps1_script` (skipped when `--managed-only`)
8. `VERIFY.txt` updated with 5-step verification including REPLACE_WITH_ORG_UUID check (step 5)
9. Success report lists all 5 artifacts conditionally (based on `MANAGED_ONLY`/`MDM_ONLY` flags)

## Verification Results

```
bash tests/run.sh 2>&1 | grep "POL"
  ✓ emit-policy merges sandbox block into settings.json (POL-01)
  ✓ emit-policy is idempotent: re-run produces identical settings.json (POL-01-idem)
  ✓ emit-policy mirrors denyRead paths into permissions.deny (POL-02)
  ✓ emit-policy produces managed-settings.json with correct keys and types (POL-03)
  ✓ disableBypassPermissionsMode is STRING 'disable' not boolean (POL-03-type)
  ✓ emit-policy produces macOS plist with correct XML (POL-04-macos)
  ✓ emit-policy produces Windows ps1 with correct path (no deprecated ProgramData) (POL-04-win)
  ✗ audit-setup rc=1 did not fail on missing sandbox.enabled (POL-05a)      ← Wave 3
  ✗ audit-setup rc=1 did not fail on unmirrored denyRead path (POL-05b)     ← Wave 3
  ✗ audit-setup rc=1 did not fail on boolean disableBypassPermissionsMode (POL-05c) ← Wave 3
  ✗ audit-setup rc=0 — expected non-2 exit and REPLACE_WITH_ORG_UUID advisory (POL-05-advisory) ← Wave 3
  ✓ emit-policy --dry-run prints mutations but writes no files (POL-dryrun)

PASS: 498    FAIL: 4
```

- 4 new PASSes: POL-03, POL-03-type, POL-04-macos, POL-04-win
- 4 remaining FAILs are exactly Wave 3 stubs (POL-05a, POL-05b, POL-05c, POL-05-advisory)
- Pre-existing 494 tests still pass (no regression)
- shellcheck clean: lib/policy-helpers.sh, scripts/emit-policy.sh

## Deviations from Plan

None — plan executed exactly as written.

## Known Stubs

None — all Wave 2 stubs are replaced. Wave 3 stubs (POL-05 audit checks in `scripts/audit-setup.sh`) remain as planned.

## Threat Flags

None — all mitigations from the plan's threat register (T-26-07 through T-26-13) are implemented:
- T-26-07: `validate_managed_settings_json()` blocks boolean `disableBypassPermissionsMode`
- T-26-08: `build_plist_xml()` hardcodes `<string>disable</string>` for this field
- T-26-09: `build_ps1_script()` uses `$env:ProgramFiles` exclusively; `ProgramData` grep verified absent
- T-26-10: XML metacharacter validation in `build_plist_xml()` + `plutil -lint` gate
- T-26-11: `secret_scan()` runs on `MANAGED_JSON` before any `mutate_write`
- T-26-12: `forceLoginOrgUUID: "REPLACE_WITH_ORG_UUID"` placeholder; VERIFY.txt step 5 checks it
- T-26-13: No `managed-settings.d/` creation in any code path; grep-verified absent

## Commits

| Hash | Description |
|------|-------------|
| df192c9 | feat(26-02): add 4 Wave 2 builder functions to policy-helpers.sh |
| 2e82bc8 | feat(26-02): replace Wave 1 stubs with full managed-settings and MDM emit |

## Self-Check: PASSED
