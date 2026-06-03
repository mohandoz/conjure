---
status: partial
phase: 26-sandbox-managed-settings-mdm
source: [26-VERIFICATION.md]
started: 2026-06-03
updated: 2026-06-03
---

## Current Test

[awaiting human testing on real systems]

## Tests

### 1. Live Claude Code managed-settings enforcement
expected: Deploy the emitted `conjure-policy/managed-settings.json` to a real Claude Code installation (system managed-settings path) and confirm `/status` reports "Enterprise managed settings (file)" and that `disableBypassPermissionsMode: "disable"` is actually enforced (bypass mode unavailable). Static analysis confirms the STRING value; runtime enforcement needs a live install.
result: [pending]

### 2. MDM plist/ps1 deployment on real hardware
expected: Deploy `com.anthropic.claudecode.plist` via Jamf/manually on macOS (or run `Set-ClaudeCodePolicy.ps1` as Administrator on Windows) and confirm Claude Code reads the MDM policy. `plutil -lint` passes on the plist in CI, but actual MDM read/enforcement needs real hardware + admin rights.
result: [pending]

## Summary

total: 2
passed: 0
issues: 0
pending: 2
skipped: 0
blocked: 0

## Notes

- Verifier item 3 (cross-regime emit spot-check for gdpr/soc2/pci) was VERIFIED by the orchestrator during the human_needed routing: all three regimes emit rc=0 with correct baseline+delta deny lists, full 1:1 denyRead→permissions.deny Read() mirroring (gdpr 19, soc2 16, pci 21), `permissions.disableBypassPermissionsMode == "disable"` (string), `forceLoginOrgUUID == "REPLACE_WITH_ORG_UUID"`, no `_conjure_*` top-level keys, and zero `ProgramData` references in the .ps1. No longer pending.

## Gaps
