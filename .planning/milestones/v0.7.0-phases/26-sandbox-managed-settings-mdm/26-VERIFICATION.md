---
phase: 26-sandbox-managed-settings-mdm
verified: 2026-06-03T12:00:00Z
status: human_needed
score: 5/5 must-haves verified
overrides_applied: 0
human_verification:
  - test: "Deploy conjure-policy/managed-settings.json to a real macOS machine running Claude Code and verify /status shows 'Enterprise managed settings (file)' in Setting sources"
    expected: "Claude Code picks up the managed-settings.json and reports it as the active policy source"
    why_human: "Requires a Claude Code installation + enterprise org context; cannot be verified by grep or jq against static files"
  - test: "Deploy conjure-policy/com.anthropic.claudecode.plist via MDM (Jamf/Intune) or manually to ~/Library/Preferences/ and confirm Claude Code respects disableBypassPermissionsMode:disable"
    expected: "Claude Code rejects --dangerously-skip-permissions or equivalent bypass attempt when the plist policy is active"
    why_human: "Requires macOS system-level plist deployment and live Claude Code binary interaction; plutil -lint only validates XML structure, not MDM policy enforcement"
  - test: "Run conjure emit-policy --regime gdpr / soc2 / pci (not just hipaa) and verify each regime produces distinct denyRead paths"
    expected: "GDPR run includes personal-data/pii paths; SOC2 includes audit-logs paths; PCI includes cardholder/pan paths"
    why_human: "The automated tests only verify hipaa regime; cross-regime correctness requires spot-checking the three other regime data files in a live emit"
---

# Phase 26: Sandbox + Managed-Settings / MDM Verification Report

**Phase Goal:** Each compliance overlay emits a deployable, testable security policy — sandbox block, managed-settings.json, and platform-tagged MDM artifacts — that `conjure audit` can verify is live and correct.
**Verified:** 2026-06-03T12:00:00Z
**Status:** human_needed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | `conjure emit-policy --regime <X>` emits a regime-specific sandbox{} block into .claude/settings.json via jq + mutate_write; every denyRead path mirrored in permissions.deny as Read(<path>) | VERIFIED | `scripts/emit-policy.sh` sources `lib/policy-helpers.sh`; `merge_sandbox_block` calls `mutate_write` (policy-helpers.sh:146, 205); `merge_deny_read_permissions` wires Read() entries; POL-01, POL-01-idem, POL-02 all PASS in 508-test suite |
| 2 | Each overlay emits managed-settings.json with disableBypassPermissionsMode as STRING "disable" (not boolean), allowManagedPermissionRulesOnly, forceLoginOrgUUID placeholder, and the sandbox block; written to caller-specified output dir only | VERIFIED | `build_managed_settings` in policy-helpers.sh:250; `validate_managed_settings_json` gates write (policy-helpers.sh:212); golden fixture confirmed STRING type: `jq -e '(.permissions.disableBypassPermissionsMode | type) == "string"'` exits 0; no system paths in emit-policy.sh; POL-03 + POL-03-type PASS |
| 3 | MDM artifact generation: macOS com.anthropic.claudecode.plist + Windows Set-ClaudeCodePolicy.ps1, both to caller-specified dir; deprecated C:\ProgramData\ClaudeCode\ never emitted | VERIFIED | `build_plist_xml` (policy-helpers.sh:289) hardcodes `<string>disable</string>`; `build_ps1_script` uses `$env:ProgramFiles` exclusively; `grep -v '^#' scripts/emit-policy.sh | grep -c 'ProgramData'` returns 0; `grep -v '^#' lib/policy-helpers.sh | grep -c 'ProgramData'` returns 0; POL-04-macos + POL-04-win PASS; plutil validates expected-plist.xml |
| 4 | `conjure audit` flags (a) overlay active but sandbox missing/false, (b) denyRead path with no mirrored Read(...), (c) disableBypassPermissionsMode wrong type; advisory warn for unreviewed template | VERIFIED | scripts/audit-setup.sh contains Phase 26 POL-05 block; POL-05c uses `err()` unconditionally; POL-05a/05b use `err()` gated on overlay; advisory uses `note()` not `warn()`; end-to-end test on _emit-policy-broken fixture exits 2 with "disableBypassPermissionsMode is boolean" message; POL-05a, POL-05b, POL-05c, POL-05-advisory all PASS |
| 5 | A deliberately-broken managed-settings artifact is detected by audit; emitted artifacts ship with a printed testable verification assertion | VERIFIED | `tests/fixtures/_emit-policy-broken/harness/.claude/settings.json` has boolean `disableBypassPermissionsMode: true`; end-to-end audit run exits 2 with detection message; `scripts/emit-policy.sh` emits VERIFY.txt with 5 testable jq/grep/claude commands per RESEARCH.md Code Examples |

**Score:** 5/5 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `lib/policy-helpers.sh` | Shared jq builders, validators, merge logic (10 functions) | VERIFIED | 10 functions confirmed: secret_scan, validate_sandbox_json, build_sandbox_block, build_deny_read_entries, merge_sandbox_block, merge_deny_read_permissions, validate_managed_settings_json, build_managed_settings, build_plist_xml, build_ps1_script; shellcheck clean |
| `scripts/emit-policy.sh` | Policy emit worker: sandbox + managed-settings + MDM + VERIFY.txt | VERIFIED | exists, 545+ lines, sources policy-helpers.sh and compliance/$REGIME/policy.sh, builds all 4 artifact types; shellcheck clean |
| `cli/conjure` | cmd_emit_policy + emit-policy) dispatch + usage line | VERIFIED | `grep -c 'emit-policy)'` = 1; `grep -c 'cmd_emit_policy'` = 2; dispatch wired |
| `compliance/hipaa/policy.sh` | HIPAA PHI delta paths (REGIME_DENY_READ, REGIME_DENY_WRITE) | VERIFIED | phi/patient/medical/ehr/mrn/ssn/dob paths present; shellcheck clean; executable bit set |
| `compliance/soc2/policy.sh` | SOC 2 audit-log delta paths | VERIFIED | audit-logs/access-logs paths present; shellcheck clean |
| `compliance/gdpr/policy.sh` | GDPR PII delta paths | VERIFIED | personal-data/pii/gdpr/user-data/data-subjects paths present; shellcheck clean |
| `compliance/pci/policy.sh` | PCI DSS cardholder delta paths | VERIFIED | cardholder/pan/card-data/cde/cvv paths present; shellcheck clean |
| `scripts/audit-setup.sh` | Phase 26 POL-05 policy check block | VERIFIED | Phase 26 block present; _pol_regime overlay detection; POL-05c unconditional; POL-05b uses tempfile pattern; advisory uses note(); shellcheck clean |
| `tests/fixtures/_emit-policy/harness/CLAUDE.md` | Harness with compliance:hipaa marker | VERIFIED | `grep -q "compliance:hipaa"` exits 0 |
| `tests/fixtures/_emit-policy/harness/.claude/settings.json` | Minimal settings.json (hooks only, no sandbox) | VERIFIED | `jq -e '.sandbox == null'` exits 0; `jq -e '.hooks != null'` exits 0 |
| `tests/fixtures/_emit-policy/expected-sandbox.json` | Golden sandbox: enabled:true, denyRead array, allowedDomains array | VERIFIED | `jq -e '.enabled == true and (.filesystem.denyRead | type) == "array" and (.network.allowedDomains | type) == "array"'` exits 0 |
| `tests/fixtures/_emit-policy/expected-managed-settings.json` | Golden: disableBypassPermissionsMode STRING "disable", allowManagedPermissionRulesOnly, forceLoginOrgUUID | VERIFIED | `jq -e '(.permissions.disableBypassPermissionsMode | type) == "string" and .permissions.disableBypassPermissionsMode == "disable"'` exits 0 |
| `tests/fixtures/_emit-policy/expected-plist.xml` | Golden plist with `<string>disable</string>` | VERIFIED | grep confirms; `plutil -lint` exits 0 on macOS |
| `tests/fixtures/_emit-policy/expected-policy.ps1` | Golden ps1 using $env:ProgramFiles | VERIFIED | ProgramFiles present; ProgramData absent |
| `tests/fixtures/_emit-policy-broken/harness/.claude/settings.json` | Negative fixture: boolean disableBypassPermissionsMode | VERIFIED | `jq -e '(.permissions.disableBypassPermissionsMode | type) == "boolean"'` exits 0 |
| `tests/fixtures/_emit-policy-unreviewed/conjure-policy/managed-settings.json` | Advisory fixture: REPLACE_WITH_ORG_UUID, no _conjure_unreviewed key | VERIFIED | grep and `jq -e 'has("_conjure_unreviewed") | not'` both pass |
| `tests/run.sh` | Phase 26 POL-* test block with all 12+ POL-* tags | VERIFIED | 18 POL-* test cases present and all PASS; full suite: 508 PASS / 0 FAIL |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `cli/conjure cmd_emit_policy` | `scripts/emit-policy.sh` | `CONJURE_HOME="$CONJURE_HOME" bash "$CONJURE_HOME/scripts/emit-policy.sh"` | WIRED | `grep -c 'emit-policy)'` = 1 in cli/conjure |
| `scripts/emit-policy.sh` | `lib/policy-helpers.sh` | `source "$CONJURE_HOME/lib/policy-helpers.sh"` | WIRED | Verified by grep; all 10 functions available to emit-policy.sh |
| `scripts/emit-policy.sh` | `compliance/<regime>/policy.sh` | `source "$CONJURE_HOME/compliance/$REGIME/policy.sh"` | WIRED | Regime enum validated before source; all 4 regime files confirmed present and executable |
| `lib/policy-helpers.sh merge_sandbox_block` | `lib/mutate.sh mutate_write` | `mutate_write "$settings_file" "$UPDATED"` | WIRED | policy-helpers.sh:146, 205 — confirmed mutate_write calls present |
| `lib/policy-helpers.sh merge_sandbox_block` | jq array_merge def | `def array_merge(a; b): (a // []) + (b // []) | unique;` | WIRED | `grep -c "array_merge"` = 12 in policy-helpers.sh |
| `scripts/emit-policy.sh` | `lib/policy-helpers.sh build_managed_settings` | `MANAGED_JSON=$(build_managed_settings ...)` | WIRED | Confirmed by grep on emit-policy.sh |
| `scripts/emit-policy.sh` | `lib/policy-helpers.sh validate_managed_settings_json` | `validate_managed_settings_json "$MANAGED_JSON" || exit 2` | WIRED | Type-safety gate confirmed; gates before any write |
| `scripts/audit-setup.sh POL-05 block` | `.claude/settings.json` | `jq -r '... | type'` reads sandbox.enabled and disableBypassPermissionsMode | WIRED | audit-setup.sh contains _dbpm_type and _sandbox_enabled variable assignments using jq |
| `scripts/audit-setup.sh POL-05a` | `CLAUDE.md compliance marker` | `grep -oE '<!-- compliance:(hipaa|soc2|gdpr|pci) -->'` | WIRED | _pol_regime detection confirmed in audit-setup.sh |
| `scripts/audit-setup.sh err() calls` | `FAIL counter + exit 2` | `err()` increments FAIL; summary gate `[ "$FAIL" -gt 0 ] && exit 2` | WIRED | err() used for POL-05a/b/c; note() used for advisory; end-to-end test on broken fixture confirms exit 2 |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|-------------------|--------|
| `scripts/emit-policy.sh` | SANDBOX_JSON | `build_sandbox_block "$DENY_READ_JSON" "$DENY_WRITE_JSON"` | Builds from REGIME_DENY_READ + baseline; jq-constructed | FLOWING |
| `scripts/emit-policy.sh` | MANAGED_JSON | `build_managed_settings "$REGIME" "$DENY_ENTRIES_JSON" "$SANDBOX_JSON"` | Uses real regime data + sandbox from above | FLOWING |
| `scripts/emit-policy.sh` | PLIST_XML | `build_plist_xml "$DENY_READ_JSON" "$DENY_ENTRIES_JSON" "$SANDBOX_JSON"` | Fixed template + regime arrays; plutil-validated on macOS | FLOWING |
| `scripts/emit-policy.sh` | PS1_CONTENT | `build_ps1_script "$REGIME" "$MANAGED_JSON"` | Embeds MANAGED_JSON into PowerShell heredoc | FLOWING |
| `scripts/audit-setup.sh` | _dbpm_type | `jq -r '.permissions.disableBypassPermissionsMode | type' .claude/settings.json` | Reads real settings.json file from target repo | FLOWING |
| `scripts/audit-setup.sh` | _sandbox_enabled | `jq -r '.sandbox.enabled // false' .claude/settings.json` | Reads real settings.json | FLOWING |
| `scripts/audit-setup.sh` | _pol_regime | `grep -oE '<!-- compliance:... -->' CLAUDE.md` | Reads real CLAUDE.md from target repo | FLOWING |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| audit detects boolean disableBypassPermissionsMode in broken fixture | `audit-setup.sh` on _emit-policy-broken harness + CLAUDE.md | exits 2; output: "[policy] disableBypassPermissionsMode is boolean (got: true) — must be string \"disable\". Re-run: conjure emit-policy" | PASS |
| plist XML is well-formed | `plutil -lint tests/fixtures/_emit-policy/expected-plist.xml` | OK | PASS |
| All 18 POL-* tests pass in suite | `bash tests/run.sh \| grep POL-` | 18/18 PASS; full suite 508 PASS / 0 FAIL | PASS |
| No ProgramData in any non-comment code | `grep -v '^#' scripts/emit-policy.sh \| grep -c ProgramData` | 0 | PASS |
| ProgramFiles present in build_ps1_script | `grep -q 'ProgramFiles' lib/policy-helpers.sh` | exits 0 | PASS |
| shellcheck on all modified files | `shellcheck -S error -e SC2164,SC2044,SC2034,SC2155 lib/policy-helpers.sh scripts/emit-policy.sh scripts/audit-setup.sh compliance/*/policy.sh` | All exit 0 | PASS |
| No managed-settings.d creation | `grep -v '^#' scripts/emit-policy.sh \| grep -c 'managed-settings.d'` | 0 | PASS |
| No system paths emitted | `grep -v '^#' scripts/emit-policy.sh \| grep -c '/Library\|ProgramData\|/Applications'` | 0 | PASS |

### Probe Execution

No conventional `scripts/*/tests/probe-*.sh` probes declared for Phase 26. Verification is covered by `tests/run.sh` POL-* cases (Step 7b above).

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|---------|
| POL-01 | 26-00, 26-01 | Regime-specific sandbox{} block merged into .claude/settings.json via jq + mutate_write | SATISFIED | POL-01 + POL-01-idem PASS; merge_sandbox_block + array_merge def confirmed wired |
| POL-02 | 26-00, 26-01 | Every denyRead path mirrored into permissions.deny as Read(<path>) | SATISFIED | POL-02 + POL-02-operator PASS; build_deny_read_entries + merge_deny_read_permissions confirmed |
| POL-03 | 26-00, 26-02 | managed-settings.json with disableBypassPermissionsMode STRING "disable", allowManagedPermissionRulesOnly, forceLoginOrgUUID placeholder, sandbox block | SATISFIED | POL-03 + POL-03-type PASS; validate_managed_settings_json gates write |
| POL-04 | 26-00, 26-02 | macOS plist + Windows ps1 to caller-specified dir; no system paths | SATISFIED | POL-04-macos + POL-04-win PASS; ProgramData grep-verified absent; plutil validates plist |
| POL-05 | 26-00, 26-03 | conjure audit flags missing sandbox, unmirrored denyRead, wrong-type disableBypassPermissionsMode | SATISFIED | POL-05a + POL-05b + POL-05c + POL-05-advisory PASS; err() vs note() usage correct |

All 5 POL requirements mapped to Phase 26 in REQUIREMENTS.md traceability table; all marked [x] complete.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `lib/policy-helpers.sh` | 467 | `XXXXXX` in `mktemp /tmp/conjure-plist-XXXXXX.plist` | Info | This is the standard mktemp template syntax, not a debt marker. No impact. |

No TBD, FIXME, or XXX markers found in any Phase 26 modified file.

### Human Verification Required

The automated checks are fully green (508 PASS / 0 FAIL, all shellcheck clean, all POL-* green). Three items require human/live-system verification that cannot be covered by static code analysis:

### 1. Live Claude Code Managed Settings Enforcement

**Test:** Deploy `conjure-policy/managed-settings.json` to a macOS machine running Claude Code (copy to `~/Library/Application Support/Claude/managed-settings.json` or equivalent enterprise path) and run `claude /status`.
**Expected:** `Setting sources` shows `Enterprise managed settings (file)` confirming Claude Code loaded the policy. The `disableBypassPermissionsMode: "disable"` value is respected — `--dangerously-skip-permissions` is rejected.
**Why human:** Requires a live Claude Code binary + macOS environment with enterprise policy paths. `plutil -lint` only validates XML structure; it cannot confirm Claude Code's runtime enforcement behavior.

### 2. MDM Plist/ps1 Actual Deployment Validation

**Test:** On macOS: deploy `com.anthropic.claudecode.plist` via Jamf or manually to `/Library/Preferences/` and confirm Claude Code picks it up. On Windows: run `Set-ClaudeCodePolicy.ps1` as Administrator and verify `HKLM\SOFTWARE\Policies\ClaudeCode` is populated and read by Claude Code.
**Expected:** Claude Code reports the MDM policy as active; the `disableBypassPermissionsMode` string value is enforced.
**Why human:** Requires real MDM infrastructure (Jamf/Intune) or admin system access; cannot verify MDM policy enforcement through bash or jq checks against static files.

### 3. Cross-Regime Emit Spot-Check (gdpr/soc2/pci)

**Test:** Run `conjure emit-policy --regime gdpr`, `--regime soc2`, `--regime pci` on a fresh harness and inspect the generated artifacts.
**Expected:** GDPR run includes `personal-data`/`pii` paths in sandbox denyRead and managed-settings deny; SOC2 includes `audit-logs` paths; PCI includes `cardholder`/`pan` paths. Each regime's managed-settings.json and plist correctly reflects its unique deny-path set.
**Why human:** The automated test suite only runs the `hipaa` regime for POL-01–POL-04. The compliance data files (compliance/*/policy.sh) are code-inspected and confirmed correct, but a live emit-and-inspect for the other 3 regimes confirms end-to-end path propagation through the entire pipeline.

### Gaps Summary

No blockers or gaps found. All 5 roadmap success criteria are verified against codebase evidence:

1. **SC1 (POL-01 + POL-02):** emit-policy merges sandbox block + mirrors denyRead into permissions.deny — VERIFIED by POL-01, POL-01-idem, POL-02 passing and confirmed wiring from cli/conjure through emit-policy.sh to policy-helpers.sh and mutate_write.
2. **SC2 (POL-03):** managed-settings.json emitted with STRING "disable", allowManagedPermissionRulesOnly, forceLoginOrgUUID placeholder, to caller-specified dir — VERIFIED by POL-03 + POL-03-type passing; validate_managed_settings_json type-safety gate confirmed; no system paths in code.
3. **SC3 (POL-04):** macOS plist + Windows ps1 to caller-specified dir; ProgramData never emitted — VERIFIED by POL-04-macos + POL-04-win passing; grep confirms ProgramData = 0 occurrences; plutil validates plist XML.
4. **SC4 (POL-05 audit):** conjure audit flags three correctness bugs; advisory uses note() — VERIFIED by POL-05a/b/c/advisory passing; err() vs note() usage confirmed; end-to-end broken-fixture test exits 2 with correct message.
5. **SC5 (broken detection + VERIFY.txt assertions):** Broken fixture detected by audit; VERIFY.txt ships with 5 testable commands — VERIFIED by POL-05c end-to-end test and inspection of VERIFY.txt content in emit-policy.sh.

---

_Verified: 2026-06-03T12:00:00Z_
_Verifier: Claude (gsd-verifier)_
