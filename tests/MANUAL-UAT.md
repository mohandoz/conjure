# Conjure — Manual UAT Checklists

These tests require real hardware or live binary access and cannot be automated.
They address the deferred HUMAN-UAT items from v0.7.0 Phases 25 and 26:
Phase 25 deferred `claude plugin validate` live smoke, and Phase 26 deferred
MDM hardware deploy (macOS plist + Windows PS1) and managed-settings deploy.

Run the automated live-test gates first before performing these manual steps
(see the Notes section at the end of this document).

---

## UAT-25: Live claude plugin validate Smoke Test

**Addresses:** Phase 25 HUMAN-UAT — live `claude plugin validate` deferred item.

### Prerequisites

- `claude` CLI installed (`command -v claude` returns a path)
- `conjure` installed (`command -v conjure` returns a path)
- Write access to a temporary directory

### Steps

1. Create a temporary working directory:
   ```bash
   TMPDIR_UAT25="$(mktemp -d)"
   echo "Working in: $TMPDIR_UAT25"
   ```
2. Scaffold a plugin into the temp directory:
   ```bash
   conjure emit-plugin --output "$TMPDIR_UAT25"
   ```
3. Verify the `.claude-plugin/` structure was emitted:
   ```bash
   ls "$TMPDIR_UAT25/.claude-plugin/"
   ```
4. Run `claude plugin validate` against the scaffolded plugin:
   ```bash
   claude plugin validate "$TMPDIR_UAT25"
   echo "Exit code: $?"
   ```
5. Confirm exit code is 0 and no error messages appear in the output.
6. Clean up:
   ```bash
   rm -rf "$TMPDIR_UAT25"
   ```

### Expected Result

`claude plugin validate` exits 0 with no errors on a conjure-emitted plugin.
The `.claude-plugin/` directory contains a valid plugin manifest accepted by
the Claude CLI.

### Checklist

- [ ] `conjure emit-plugin` emits a `.claude-plugin/` directory without errors
- [ ] `.claude-plugin/` contains at least a `plugin.json` manifest
- [ ] `claude plugin validate` exits 0
- [ ] No error messages in `claude plugin validate` output
- [ ] Cleanup succeeded (temp directory removed)

**Verified:** <!-- date --> · conjure <!-- version --> · claude <!-- version -->

---

## UAT-26a: MDM Hardware Deploy — macOS Managed Plist

**Addresses:** Phase 26 HUMAN-UAT — MDM hardware deploy (macOS) deferred item.

### Prerequisites

- macOS device enrolled in an MDM solution (e.g. Jamf, Mosyle, Kandji, Intune)
- `conjure` installed on the deployment machine
- Access to the MDM admin console to push a configuration profile
- A separate enrolled test device to receive the profile

### Steps

1. Generate the MDM policy artifacts on the deployment machine:
   ```bash
   TMPDIR_UAT26A="$(mktemp -d)"
   conjure emit-policy --overlay mdm --output "$TMPDIR_UAT26A"
   echo "Generated files:"
   ls "$TMPDIR_UAT26A"
   ```
2. Review the emitted `com.anthropic.claude-code.plist` for required keys:
   ```bash
   cat "$TMPDIR_UAT26A/com.anthropic.claude-code.plist"
   # Verify: PayloadType, disableBypassPermissionsMode, and sandbox block present
   ```
3. Import the plist into the MDM console as a custom configuration profile and
   scope it to the test device or a test device group.
4. Push the profile from the MDM console and wait for the enrolled test device
   to confirm receipt (check MDM console for acknowledgement status).
5. On the enrolled test device, verify the managed plist is present:
   ```bash
   ls -la /Library/Managed\ Preferences/com.anthropic.claude-code.plist
   ```
6. Open Claude Code on the enrolled test device and confirm that
   policy-restricted behaviour is enforced (e.g. `disableBypassPermissionsMode`
   blocks the bypass permission mode option in Claude Code settings).
7. Clean up:
   ```bash
   rm -rf "$TMPDIR_UAT26A"
   ```

### Expected Result

Claude Code on the enrolled device respects the managed policy. The plist is
present in `/Library/Managed Preferences/` and `disableBypassPermissionsMode`
prevents users from enabling bypass permissions mode in Claude Code.

### Checklist

- [ ] `conjure emit-policy --overlay mdm` generates plist without error
- [ ] Plist contains `PayloadType` and `disableBypassPermissionsMode` keys
- [ ] Plist contains a sandbox block with tool deny entries
- [ ] MDM push succeeds (check MDM console — device acknowledged)
- [ ] Managed plist present at `/Library/Managed Preferences/com.anthropic.claude-code.plist` on enrolled device
- [ ] Claude Code enforces the managed policy on the enrolled device

**Verified:** <!-- date --> · conjure <!-- version --> · macOS <!-- version --> · MDM <!-- product -->

---

## UAT-26b: MDM Hardware Deploy — Windows Managed Policy (PS1)

**Addresses:** Phase 26 HUMAN-UAT — MDM hardware deploy (Windows) deferred item.

### Prerequisites

- Windows device or VM (Windows 10/11 or Windows Server 2019+)
- PowerShell 5.1+ (verify: `$PSVersionTable.PSVersion`)
- Administrator access to run the policy script and write to `HKLM:\`
- `conjure` installed (Git Bash or WSL on the Windows machine, or generate
  artifacts on another machine and transfer)

### Steps

1. Generate the MDM policy artifacts:
   ```bash
   TMPDIR_UAT26B="$(mktemp -d)"
   conjure emit-policy --overlay mdm --output "$TMPDIR_UAT26B"
   echo "Generated files:"
   ls "$TMPDIR_UAT26B"
   ```
2. Transfer `apply-claude-policy.ps1` to the Windows test machine if generated
   on a separate machine.
3. Review the emitted `apply-claude-policy.ps1` for expected registry keys:
   ```powershell
   Get-Content .\apply-claude-policy.ps1
   # Verify: HKLM:\SOFTWARE\Anthropic\ClaudeCode key and DisableBypassPermissionsMode value
   ```
4. If needed, allow script execution (run PowerShell as Administrator):
   ```powershell
   Set-ExecutionPolicy RemoteSigned -Scope LocalMachine
   ```
5. Run the policy script as Administrator:
   ```powershell
   .\apply-claude-policy.ps1
   ```
6. Verify the registry key is present after execution:
   ```powershell
   Get-ItemProperty -Path "HKLM:\SOFTWARE\Anthropic\ClaudeCode" -Name "DisableBypassPermissionsMode"
   # Expected: DisableBypassPermissionsMode = 1 (or "disable")
   ```
7. Open Claude Code on the test device and confirm that policy-restricted
   behaviour is enforced (bypass permissions mode option is unavailable or
   locked).
8. Clean up (optional — remove the registry key to restore the device):
   ```powershell
   Remove-Item -Path "HKLM:\SOFTWARE\Anthropic\ClaudeCode" -Recurse -Force
   ```

### Expected Result

Claude Code on the Windows device respects the managed policy after PS1
execution. The registry key `HKLM:\SOFTWARE\Anthropic\ClaudeCode` contains
`DisableBypassPermissionsMode` and Claude Code enforces the restriction.

### Checklist

- [ ] `conjure emit-policy --overlay mdm` generates PS1 without error
- [ ] PS1 contains expected `HKLM:\SOFTWARE\Anthropic\ClaudeCode` registry key writes
- [ ] PS1 executes without errors as Administrator
- [ ] Registry key `DisableBypassPermissionsMode` present under `HKLM:\SOFTWARE\Anthropic\ClaudeCode` after PS1 execution
- [ ] Claude Code enforces the managed policy on the Windows device

**Verified:** <!-- date --> · conjure <!-- version --> · Windows <!-- version -->

---

## UAT-26c: Managed-Settings Deploy (managed-settings.json)

**Addresses:** Phase 26 HUMAN-UAT — managed-settings deploy deferred item.

### Prerequisites

- `conjure` installed
- A target repo or test directory
- Write access to `~/.claude/` on the test user account

### Steps

1. Generate the managed-settings policy artifact:
   ```bash
   TMPDIR_UAT26C="$(mktemp -d)"
   conjure emit-policy --overlay managed --output "$TMPDIR_UAT26C"
   echo "Generated files:"
   ls "$TMPDIR_UAT26C"
   ```
2. Review the emitted `managed-settings.json` for required keys:
   ```bash
   cat "$TMPDIR_UAT26C/managed-settings.json"
   # Verify: permissions block and sandbox block present
   # Verify: disableBypassPermissionsMode is string "disable" (not boolean)
   ```
3. Place `managed-settings.json` in the `~/.claude/` directory of the target
   user:
   ```bash
   cp "$TMPDIR_UAT26C/managed-settings.json" ~/.claude/managed-settings.json
   ```
4. Open Claude Code on the target machine. Verify the managed settings are
   applied — Claude Code should load without an "invalid settings" error, and
   the behaviour configured in `managed-settings.json` should be in effect
   (e.g. sandbox permissions applied, bypass mode disabled).
5. Run `conjure audit` on a target repo and confirm no policy-related warnings:
   ```bash
   conjure audit /path/to/target-repo
   echo "Exit code: $?"
   ```
6. Clean up:
   ```bash
   rm -f ~/.claude/managed-settings.json
   rm -rf "$TMPDIR_UAT26C"
   ```

### Expected Result

Claude Code loads `managed-settings.json` from `~/.claude/` and applies the
permissions and sandbox configuration without errors. `conjure audit` exits 0
and reports no policy-related warnings on the target repo.

### Checklist

- [ ] `conjure emit-policy --overlay managed` generates `managed-settings.json` without error
- [ ] File contains `permissions` and `sandbox` keys
- [ ] `disableBypassPermissionsMode` is present as a string value `"disable"` (not boolean)
- [ ] Claude Code loads the file on startup (no "invalid settings" error in UI or logs)
- [ ] `conjure audit` passes on target repo (exit 0, no policy warnings)

**Verified:** <!-- date --> · conjure <!-- version --> · claude <!-- version -->

---

## Notes

Run the automated live-test gates first (`CONJURE_LIVE_TEST=1 bash tests/run.sh`)
before performing manual UAT. The automated gates cover UAT-01 (claude plugin
validate in a sandbox) and UAT-02 (live promptfoo eval) and are prerequisites
for the manual steps above.

To run all automated gates including the live-system tests with strict enforcement
(where any skip is treated as a failure):

```bash
CONJURE_STRICT=1 CONJURE_LIVE_TEST=1 ANTHROPIC_API_KEY="<key>" bash tests/run.sh
```

The manual steps in this file address scenarios that require real managed hardware
(MDM-enrolled devices) or manual operator actions that cannot be scripted safely
from a test harness. They are intended to be run once per release on hardware
representative of the target deployment environment, and the results recorded in
the Verified fields above.
