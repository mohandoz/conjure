# Phase 26: Sandbox + Managed-Settings / MDM — Research

**Researched:** 2026-06-03
**Domain:** Claude Code settings.json sandbox schema, managed-settings.json MDM policy, POSIX bash jq merge patterns
**Confidence:** HIGH (schema facts directly from official Claude Code docs + anthropics/claude-code MDM examples repo)

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- New dedicated command `conjure emit-policy --regime hipaa|soc2|gdpr|pci [--output DIR]`, parallel to `emit-plugin`/`publish-plugin`. Do NOT overload `--overlay=<git-url>`.
- The `sandbox{}` block is written into `.claude/settings.json` via `jq` + `mutate_write` (POL-01 mandates in-settings merge, not a sidecar file).
- `managed-settings.json` + MDM artifacts written to caller-specified `--output DIR`; default `./conjure-policy/` inside the target. NEVER auto-place at system paths.
- Single `emit-policy` command emits all three artifact types together; `--managed-only` and `--mdm-only` subset flags.
- POL-05 severities: `fail` (exit 2) for wrong-type `disableBypassPermissionsMode` (boolean instead of string) + overlay active but sandbox missing or `enabled:false`. Advisory `note` (exit 0) for "unreviewed policy template".
- `denyRead` path with no mirrored `Read(...)` permissions.deny entry → `fail` (exit 2).
- Policy checks auto-run when `<!-- compliance:REGIME -->` marker detected in CLAUDE.md + sandbox block present; `--compliance` flag forces full audit.
- "Unreviewed template" detection: `REPLACE_WITH_ORG_UUID` placeholder still present and/or `_conjure_unreviewed` marker.
- `forceLoginOrgUUID` ships as literal placeholder `"REPLACE_WITH_ORG_UUID"`.
- `disableBypassPermissionsMode` is the STRING `"disable"` (never boolean).
- Single `managed-settings.json` for v1. `managed-settings.d/` drop-in = POL-F1, deferred.
- MDM bundle: macOS `com.anthropic.claudecode.plist` + Windows `Set-ClaudeCodePolicy.ps1` (registry root `HKLM\SOFTWARE\Policies\ClaudeCode`). Deprecated Windows path `C:\ProgramData\ClaudeCode\` NEVER emitted.
- Per-regime `denyRead`/`denyWrite`/`network.allowedDomains` deny lists ship as standard patterns under `compliance/<regime>/` (no repo scanning).
- Shared secure baseline + per-regime deltas; `network.allowedDomains` defaults to EMPTY = deny-all.
- Every `sandbox.filesystem.denyRead` path mirrored 1:1 into `permissions.deny` as `Read(<path>)`.
- Each emitted artifact ships with a printed, testable verification assertion to stdout AND persisted to a file in the output dir.
- All settings.json mutation routes through `mutate_write` with idempotent jq merge.

### Claude's Discretion

All grey areas were autonomously resolved (per CONTEXT.md: "all 4 grey areas accepted as recommended"). No discretion areas remain open.

### Deferred Ideas (OUT OF SCOPE)

- POL-F1: `managed-settings.d/` numbered drop-in fragments (composable layered policy).
- POL-F2: `_conjure_source` provenance annotations in emitted managed-settings.
- POL-F3: `policyHelper` script generation for dynamic org policy.
- WS-F2: `conjure workspace emit-managed` (union managed-settings across mixed-compliance repos).
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| POL-01 | Each compliance overlay emits a regime-specific `sandbox{}` block (`denyRead`/`denyWrite`/`network.allowedDomains`) merged into `.claude/settings.json` via jq + mutate_write | Sandbox schema verified from official docs; jq merge pattern documented in Code Examples section |
| POL-02 | Every `sandbox.filesystem.denyRead` path mirrored into `permissions.deny` as `Read(<path>)` (closes Read-tool enforcement gap #32226) | Issue #32226 analysed; permissions.deny Read() format verified from official docs |
| POL-03 | Each overlay emits `managed-settings.json` with `disableBypassPermissionsMode:"disable"` (string), `allowManagedPermissionRulesOnly`, `forceLoginOrgUUID` placeholder, and the sandbox block | Exact key names, types, and file paths verified from official docs + anthropics/claude-code MDM examples |
| POL-04 | MDM artifact generation — macOS plist (`com.anthropic.claudecode`) + Windows PowerShell/registry (`Set-ClaudeCodePolicy.ps1` → `HKLM\SOFTWARE\Policies\ClaudeCode`) written to caller-specified output dir | Plist XML structure and Set-ClaudeCodePolicy.ps1 pattern verified from anthropics/claude-code repo |
| POL-05 | `conjure audit` flags: (a) overlay active but missing/`enabled:false` sandbox, (b) denyRead path with no mirrored Read(...) deny, (c) `disableBypassPermissionsMode` wrong type | Audit patterns documented; jq type-check idioms in Code Examples section |
</phase_requirements>

---

## Summary

Phase 26 implements a `conjure emit-policy` command that emits three artifact types for each of the four compliance regimes (hipaa, soc2, gdpr, pci): (1) a regime-specific `sandbox{}` block merged into `.claude/settings.json`, (2) a `managed-settings.json` suitable for system-level MDM deployment, and (3) MDM platform artifacts (macOS `.plist` + Windows `.ps1` registry setter). The phase also extends `conjure audit` with five POL-05 checks that verify these artifacts are present and internally consistent.

The authoritative Claude Code settings schema has been verified directly from the official Claude Code documentation and the `anthropics/claude-code` MDM examples repository. All key technical unknowns have been resolved: the `disableBypassPermissionsMode` value is the string `"disable"` (not boolean), confirmed in the official plist/ps1 examples; the Windows managed path is `C:\Program Files\ClaudeCode\managed-settings.json` (the `C:\ProgramData\ClaudeCode\` path was deprecated at v2.1.75); the macOS plist domain is `com.anthropic.claudecode`; and the Read-tool enforcement gap (#32226) explains why every `sandbox.filesystem.denyRead` path must also appear as a `Read(<path>)` entry in `permissions.deny`.

The implementation mirrors the Phase 25 `emit-plugin` worker pattern almost exactly: a new `scripts/emit-policy.sh` + `lib/policy-helpers.sh` pair, with shared jq-merge logic, validate-before-write gates, snapshot-before-mutate, and idempotent output. The audit checks attach after the existing plugin-reconciliation advisory block in `scripts/audit-setup.sh`.

**Primary recommendation:** Implement `lib/policy-helpers.sh` first (sandbox block builder, managed-settings builder, jq merge, plist/ps1 renderers, validate_sandbox_json, validate_managed_settings_json), then the `scripts/emit-policy.sh` worker, then the `scripts/audit-setup.sh` policy checks, and finally per-regime data files under `compliance/<regime>/policy.sh`. Use the Phase 25 emit-plugin fixture structure as the exact template for `_emit-policy*` test fixtures.

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Sandbox block emission into settings.json | CLI (scripts/emit-policy.sh) | lib/policy-helpers.sh (jq builder) | All filesystem mutations route through lib/mutate.sh; jq logic is lib-extracted for testability |
| managed-settings.json emission | CLI (scripts/emit-policy.sh) | lib/policy-helpers.sh (builder + validator) | Same CLI-owns-mutations principle |
| macOS plist generation | CLI (scripts/emit-policy.sh) | No system plist write — output dir only | Artifact written to ./conjure-policy/; operator deploys via MDM |
| Windows .ps1 generation | CLI (scripts/emit-policy.sh) | — | ps1 is a template file rendered with regime-specific JSON content |
| POL-05 audit checks | scripts/audit-setup.sh | lib/caps.sh (note/warn/fail functions) | Audit checks attach to existing audit-setup.sh advisory pattern |
| Per-regime deny-path data | compliance/<regime>/policy.sh | — | Sourced by emit-policy.sh; keeps regime data separate from emission logic |
| Idempotent jq sandbox merge | lib/policy-helpers.sh | — | Reusable merge function that other callers (audit verifier) can also invoke |

---

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| jq | 1.8.1 (system; minimum 1.6) | JSON build, merge, validation, type-check | Already in runtime envelope; used by all existing emit workers |
| bash (POSIX 3.2+) | System bash | Script runtime | Project constraint — no associative arrays, mapfile, local -n |
| plutil | System (macOS) | Validate generated plist XML | Zero-install on macOS; `plutil -lint` verifies plist syntax |
| python3 plistlib | System (3.14.5 on dev box) | Alternative plist generation if plutil absent | Already in runtime envelope per STATE.md decision |

[VERIFIED: official Claude Code docs] — jq already in runtime envelope per CLAUDE.md.
[VERIFIED: npm registry / system tools] — plutil is a macOS system binary; python3 plistlib is stdlib.

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| shellcheck | CI gate | Lint emit-policy.sh + policy-helpers.sh | CI gate enforces `-S error -e SC2164,SC2044,SC2034,SC2155` |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Hand-rolled plist XML string | python3 plistlib | python3 is more robust for plist encoding (handles escaping, encoding); BUT a simple heredoc with known-safe string values is fine for a template with no user-supplied keys. Use heredoc for simplicity; add `plutil -lint` gate to catch malformed output. |
| Single jq `* (deep-merge)` operator | Custom deepmerge function | `.*` merges objects recursively but replaces arrays (not concatenates). For `sandbox.filesystem.denyRead` (an array), use explicit jq: `.sandbox.filesystem.denyRead = ((.sandbox.filesystem.denyRead // []) + $new_deny | unique)` to merge-and-deduplicate. |

**Installation:** No new packages to install. All tools already in the runtime envelope.

---

## Package Legitimacy Audit

> No external packages are installed in this phase. All tooling (jq, bash, plutil, python3) is already in the project runtime envelope (CLAUDE.md) or is a macOS/Linux system binary.

**Packages removed due to slopcheck [SLOP] verdict:** none
**Packages flagged as suspicious [SUS]:** none

---

## Architecture Patterns

### System Architecture Diagram

```
conjure emit-policy --regime hipaa [--output DIR] [--managed-only|--mdm-only] [--dry-run]
         │
         ▼
scripts/emit-policy.sh
  │
  ├─ source compliance/<regime>/policy.sh   ← per-regime denyRead/denyWrite/allowedDomains data
  │
  ├─ lib/policy-helpers.sh
  │     ├─ build_sandbox_block()            ← constructs sandbox{} JSON from regime data
  │     ├─ build_managed_settings()         ← constructs managed-settings JSON
  │     ├─ build_plist_xml()                ← renders com.anthropic.claudecode.plist XML
  │     ├─ build_ps1_script()              ← renders Set-ClaudeCodePolicy.ps1
  │     ├─ validate_sandbox_json()          ← jq type-checks before write
  │     └─ validate_managed_settings_json() ← jq type-checks before write
  │
  ├─ Validate before every write (exit 2 on invalid)
  │
  ├─ snapshot_create() [lib/snapshot.sh]    ← backup-before-mutate when .claude/settings.json exists
  │
  ├─ mutate_write() [lib/mutate.sh]         ← write .claude/settings.json (sandbox merge)
  │
  ├─ mutate_mkdir + mutate_write            ← write to --output DIR:
  │     conjure-policy/managed-settings.json
  │     conjure-policy/com.anthropic.claudecode.plist
  │     conjure-policy/Set-ClaudeCodePolicy.ps1
  │     conjure-policy/VERIFY.txt           ← testable verification commands
  │
  └─ Print verification assertions to stdout

scripts/audit-setup.sh (existing, extended)
  │
  ├─ detect <!-- compliance:REGIME --> marker in CLAUDE.md
  │
  ├─ [POL-05a] if overlay active: check sandbox.enabled == true → fail() if missing or false
  ├─ [POL-05b] for each denyRead path: check matching Read(<path>) in permissions.deny → fail() if missing
  ├─ [POL-05c] check disableBypassPermissionsMode type == "string" → fail() if boolean
  └─ [advisory] check REPLACE_WITH_ORG_UUID placeholder → note() if still present
```

### Recommended Project Structure

```
compliance/
├── hipaa/
│   ├── apply.sh              # existing — unmodified
│   ├── CLAUDE.md.fragment    # existing — unmodified
│   ├── CONTROLS.md           # existing — unmodified
│   ├── pre-commit-phi-scan.sh # existing — unmodified
│   └── policy.sh             # NEW — denyRead/denyWrite/allowedDomains data for hipaa
├── soc2/
│   ├── apply.sh
│   ├── CLAUDE.md.fragment
│   └── policy.sh             # NEW
├── gdpr/
│   ├── apply.sh
│   ├── CLAUDE.md.fragment
│   └── policy.sh             # NEW
└── pci/
    ├── apply.sh
    ├── CLAUDE.md.fragment
    └── policy.sh             # NEW

lib/
└── policy-helpers.sh         # NEW — sandbox/managed-settings builders + validators

scripts/
└── emit-policy.sh            # NEW — emit worker (mirrors emit-plugin.sh structure)

tests/fixtures/
├── _emit-policy/             # NEW — happy-path fixture (harness + expected artifacts)
│   ├── harness/
│   │   ├── CLAUDE.md         # with <!-- compliance:hipaa --> marker
│   │   └── .claude/settings.json
│   └── expected-sandbox.json # expected sandbox block shape
├── _emit-policy-broken/      # NEW — negative fixture: wrong-type disableBypassPermissionsMode
└── _emit-policy-unreviewed/  # NEW — fixture: REPLACE_WITH_ORG_UUID still present
```

---

### Pattern 1: Idempotent jq sandbox block deep-merge into settings.json

**What:** Read existing settings.json, deep-merge the sandbox block (preserving all other keys), validate, then write via mutate_write.

**When to use:** POL-01 — every `conjure emit-policy` run must be safely re-runnable.

**Key rule:** `sandbox.filesystem.denyRead` is an ARRAY. jq's `.*` operator replaces arrays rather than merging them. Use explicit array union + dedup to be idempotent.

```bash
# Source: verified pattern from lib/plugin-helpers.sh + Claude Code docs
# POSIX bash 3.2+ safe. Caller already sources lib/mutate.sh.

merge_sandbox_block() {
  local settings_file="$1"
  local sandbox_json="$2"   # complete sandbox{} block as JSON string

  local CURRENT
  CURRENT="$(cat "$settings_file" 2>/dev/null || printf '{}')"

  # Deep-merge: preserve all existing keys; merge sandbox sub-keys.
  # For array keys (denyRead, denyWrite, allowWrite, allowRead, allowedDomains,
  # excludedCommands): union + unique so re-runs are idempotent and existing
  # user-added entries are preserved.
  # For scalar keys (enabled, failIfUnavailable, etc.): new value wins.
  local UPDATED
  UPDATED="$(printf '%s' "$CURRENT" | jq \
    --argjson sb "$sandbox_json" \
    '
    # Helper: merge two arrays with dedup (order: existing first, then new)
    def array_merge(a; b): (a // []) + (b // []) | unique;

    .sandbox = (
      (.sandbox // {}) as $old |
      $sb as $new |
      $old * $new |
      # Array fields need explicit union (jq * replaces arrays, not merges)
      .filesystem.denyRead  = array_merge($old.filesystem.denyRead;  $new.filesystem.denyRead) |
      .filesystem.denyWrite = array_merge($old.filesystem.denyWrite; $new.filesystem.denyWrite) |
      .filesystem.allowWrite = array_merge($old.filesystem.allowWrite; $new.filesystem.allowWrite) |
      .filesystem.allowRead  = array_merge($old.filesystem.allowRead;  $new.filesystem.allowRead) |
      .network.allowedDomains = array_merge($old.network.allowedDomains; $new.network.allowedDomains) |
      .excludedCommands = array_merge($old.excludedCommands; $new.excludedCommands)
    )
    ')"

  printf '%s' "$UPDATED" | jq empty 2>/dev/null || {
    echo "✗ jq produced invalid JSON for settings.json (sandbox merge)" >&2
    return 1
  }

  mutate_write "$settings_file" "$UPDATED"
}
```

**Idempotency guarantee:** Re-running `emit-policy` with the same regime produces the same sandbox block because `unique` deduplicates the arrays and scalar keys overwrite with the same value.

---

### Pattern 2: permissions.deny Read() mirror (POL-02 — enforcement gap #32226)

**What:** For every path in `sandbox.filesystem.denyRead`, emit a matching `Read(<path>)` entry in `permissions.deny`.

**Why:** `sandbox.filesystem.denyRead` only controls the OS-level Bash sandbox. The Claude Code Read/Grep/Glob tools bypass the sandbox entirely and read files directly. Without a corresponding `permissions.deny` `Read(...)` entry, Claude can still read protected paths via the Read tool even though Bash is blocked. This is issue #32226.

**Path format rule:** `permissions.deny` Read rules use a different path convention than sandbox paths:

| sandbox.filesystem.denyRead | permissions.deny Read() equivalent | Meaning |
|----------------------------|-------------------------------------|---------|
| `~/.aws/credentials` | `Read(~/.aws/credentials)` | home-relative |
| `~/.ssh/` | `Read(~/.ssh/**)` | home-relative dir (add ** for recursive) |
| `~/.env` | `Read(~/.env)` | home-relative exact file |
| `/etc/passwd` | `Read(//etc/passwd)` | absolute — note DOUBLE slash `//` prefix |
| `./secrets/` | `Read(/secrets/**)` | project-root-relative — single `/` prefix |

**Critical:** For absolute paths in `permissions.deny` Read rules, the `//path` (double slash) form is used. A single `/path` is project-root-relative, NOT absolute. When converting sandbox `denyRead` paths to `permissions.deny` entries:
- Path starts with `~/` → keep as `Read(~/path)` or `Read(~/path/**)` for dirs
- Path starts with `/` (absolute) → convert to `Read(//path)` (double slash)
- Path starts with `./` → convert to `Read(/path)` (single slash, project-root-relative)

```bash
# Source: verified from official Claude Code permissions docs
# Build permissions.deny Read() entries from denyRead array
build_deny_read_entries() {
  local deny_read_json="$1"   # JSON array of denyRead paths
  # For each denyRead path, produce a Read(<path>) permissions.deny entry
  printf '%s' "$deny_read_json" | jq -r '.[]' | while IFS= read -r path; do
    case "$path" in
      ~/*)  printf 'Read(%s)\n' "$path" ;;           # home-relative: keep as-is
      /*)   printf 'Read(/%s)\n' "$path" ;;          # absolute: prepend extra /
      ./*)  printf 'Read(%s)\n' "${path#.}" ;;       # project-relative: strip leading .
      *)    printf 'Read(%s)\n' "$path" ;;           # bare name: pass through
    esac
  done
}
```

**Merge into permissions.deny:** Use the same jq array-union pattern as sandbox merge. The `permissions.deny` array may already contain other entries (Bash rules etc.); only Read() entries are added for the denyRead paths.

---

### Pattern 3: managed-settings.json exact schema (POL-03)

**What:** Emit a `managed-settings.json` with the exact key names and types the Claude Code runtime expects.

[VERIFIED: official Claude Code docs — code.claude.com/docs/en/permissions, code.claude.com/docs/en/server-managed-settings, anthropics/claude-code MDM examples]

```json
{
  "permissions": {
    "disableBypassPermissionsMode": "disable",
    "deny": [
      "Read(~/.aws/credentials)",
      "Read(~/.ssh/**)"
    ]
  },
  "allowManagedPermissionRulesOnly": true,
  "forceLoginOrgUUID": "REPLACE_WITH_ORG_UUID",
  "sandbox": {
    "enabled": true,
    "failIfUnavailable": true,
    "allowUnsandboxedCommands": false,
    "filesystem": {
      "denyRead": ["~/.aws", "~/.ssh"],
      "denyWrite": []
    },
    "network": {
      "allowedDomains": []
    }
  },
  "_conjure_regime": "hipaa",
  "_conjure_unreviewed": true
}
```

**Key type facts** (all VERIFIED from official docs):
- `disableBypassPermissionsMode`: STRING `"disable"` — NOT boolean. The plist file from the official MDM examples repo shows `<string>disable</string>`. A boolean `true` has no effect.
- `allowManagedPermissionRulesOnly`: boolean `true` — managed-only setting (no effect if placed in user/project settings).
- `forceLoginOrgUUID`: string (single UUID) or array of strings (multiple orgs accepted). Ships as `"REPLACE_WITH_ORG_UUID"` placeholder — obviously fake, fails Claude login validation, prompts operator to replace.
- `_conjure_regime` and `_conjure_unreviewed`: custom marker keys; Claude Code ignores unknown keys, so these are safe to include as metadata.

**`allowManagedPermissionRulesOnly` placement:** Per official docs, this is a managed-only setting — it MUST be at the top level of the JSON object (not nested under `permissions`). The server-managed settings docs example shows it at top level alongside `permissions`.

---

### Pattern 4: macOS plist XML structure (POL-04)

**What:** Emit `com.anthropic.claudecode.plist` with the managed-settings content encoded as a plist.

[VERIFIED: anthropics/claude-code/examples/mdm/macos/com.anthropic.claudecode.plist — verified by fetching raw file]

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>permissions</key>
    <dict>
        <key>disableBypassPermissionsMode</key>
        <string>disable</string>
        <key>deny</key>
        <array>
            <string>Read(~/.aws/credentials)</string>
            <string>Read(~/.ssh/**)</string>
        </array>
    </dict>
    <key>allowManagedPermissionRulesOnly</key>
    <true/>
    <key>forceLoginOrgUUID</key>
    <string>REPLACE_WITH_ORG_UUID</string>
    <key>sandbox</key>
    <dict>
        <key>enabled</key>
        <true/>
        <key>failIfUnavailable</key>
        <true/>
        <key>allowUnsandboxedCommands</key>
        <false/>
        <key>filesystem</key>
        <dict>
            <key>denyRead</key>
            <array>
                <string>~/.aws</string>
                <string>~/.ssh</string>
            </array>
            <key>denyWrite</key>
            <array/>
        </dict>
        <key>network</key>
        <dict>
            <key>allowedDomains</key>
            <array/>
        </dict>
    </dict>
</dict>
</plist>
```

**Plist encoding rules:**
- JSON strings → `<string>value</string>`
- JSON boolean `true` → `<true/>` (self-closing tag, no value)
- JSON boolean `false` → `<false/>`
- JSON arrays → `<array>...<string>item</string>...</array>`
- JSON objects → `<dict>...<key>k</key><value-type>v</value-type>...</dict>`
- JSON null → omit the key entirely
- **CRITICAL — disableBypassPermissionsMode:** must be `<string>disable</string>`. NEVER `<true/>`. This is the single most common type-coercion pitfall.

**Generation approach (POSIX bash):** Use a shell heredoc with jq-derived values, not a plist-generating library. The plist structure is fixed; only the array contents vary by regime. Validate with `plutil -lint` after generation (macOS system tool; if absent on Linux, skip validation and note in VERIFY.txt).

---

### Pattern 5: Windows Set-ClaudeCodePolicy.ps1 (POL-04)

**What:** Emit a PowerShell script that writes `C:\Program Files\ClaudeCode\managed-settings.json`.

[VERIFIED: anthropics/claude-code/examples/mdm/windows/Set-ClaudeCodePolicy.ps1 — fetched raw file]

```powershell
<#
Deploys Claude Code managed settings as a JSON file.

Intune: Devices > Scripts and remediations > Platform scripts > Add (Windows 10 and later).
  Run this script using the logged on credentials: No
  Run script in 64 bit PowerShell Host: Yes

Claude Code reads C:\Program Files\ClaudeCode\managed-settings.json at startup
and treats it as a managed policy source. Edit the JSON below to change the
deployed settings; see https://code.claude.com/docs/en/settings for available keys.

NOTE: This script is generated by conjure emit-policy --regime <REGIME>.
The forceLoginOrgUUID value MUST be replaced with your organization's UUID
before deploying. See https://code.claude.com/docs/en/settings for details.
Compliance disclaimer: this configuration reduces non-compliant output risks
but does not make your project compliant. Engage your compliance officer.
#>

$ErrorActionPreference = 'Stop'

$dir = Join-Path $env:ProgramFiles 'ClaudeCode'
New-Item -ItemType Directory -Path $dir -Force | Out-Null

$json = @'
{
  "permissions": {
    "disableBypassPermissionsMode": "disable",
    "deny": []
  },
  "allowManagedPermissionRulesOnly": true,
  "forceLoginOrgUUID": "REPLACE_WITH_ORG_UUID",
  "sandbox": {
    "enabled": true,
    "failIfUnavailable": true,
    "allowUnsandboxedCommands": false,
    "filesystem": { "denyRead": [], "denyWrite": [] },
    "network": { "allowedDomains": [] }
  }
}
'@

$path = Join-Path $dir 'managed-settings.json'
[System.IO.File]::WriteAllText($path, $json, (New-Object System.Text.UTF8Encoding($false)))
Write-Output "Wrote $path"
Write-Output "Verify: open Claude Code and run /status — confirm managed policy source is active"
```

**Critical implementation notes:**
- Use `[System.IO.File]::WriteAllText($path, $json, (New-Object System.Text.UTF8Encoding($false)))` — the `$false` arg to `UTF8Encoding` suppresses the BOM. Claude Code expects UTF-8 without BOM.
- NEVER use `Set-Content` or `Out-File` for JSON — both add CRLF line endings on Windows and `Set-Content` defaults to UTF-16. The `WriteAllText` pattern from the official example is correct.
- The registry setter path `HKLM\SOFTWARE\Policies\ClaudeCode` is for GROUP POLICY / REGISTRY policy delivery. The file-based path (`C:\Program Files\ClaudeCode\managed-settings.json`) is for Intune/file deployment. This phase ships the file-based ps1; the registry approach uses ADMX templates (ClaudeCode.admx), which are separate and not generated by Conjure.
- When generating the ps1 from bash, use `mutate_write` with the content as a string. The JSON inside the PowerShell heredoc (`@'...'@`) must have its single quotes handled carefully; use jq to build the JSON string first, then embed it via printf into the ps1 template.

**Line ending concern:** When generating the .ps1 from macOS/Linux bash, the file will have Unix LF line endings. PowerShell on Windows handles LF line endings correctly (PS 5.1+), but some older Intune deployment pipelines may expect CRLF. The official example from Anthropic uses LF endings — follow the same pattern.

---

### Pattern 6: POL-05 audit check idioms

**What:** jq and grep patterns for each of the three fail() checks in audit-setup.sh.

```bash
# POL-05a: overlay active but sandbox missing or enabled:false
# Detect active overlay via CLAUDE.md marker
_pol_regime="$(grep -oE '<!-- compliance:(hipaa|soc2|gdpr|pci) -->' CLAUDE.md 2>/dev/null \
  | sed 's/<!-- compliance://;s/ -->//' | head -1)"
if [ -n "$_pol_regime" ] && [ -f ".claude/settings.json" ] && command -v jq >/dev/null 2>&1; then
  _sandbox_enabled="$(jq -r '.sandbox.enabled // false' .claude/settings.json 2>/dev/null)"
  if [ "$_sandbox_enabled" != "true" ]; then
    err "[policy:$_pol_regime] compliance overlay active but sandbox.enabled is not true — run: conjure emit-policy --regime $_pol_regime"
  fi
fi

# POL-05b: denyRead path with no matching Read() entry in permissions.deny
# For each denyRead path, check that a Read(<path>) appears in permissions.deny
if [ -n "$_pol_regime" ] && [ -f ".claude/settings.json" ] && command -v jq >/dev/null 2>&1; then
  _deny_paths="$(jq -r '.sandbox.filesystem.denyRead // [] | .[]' .claude/settings.json 2>/dev/null)"
  _perm_deny="$(jq -r '.permissions.deny // [] | .[]' .claude/settings.json 2>/dev/null)"
  printf '%s\n' "$_deny_paths" | while IFS= read -r dpath; do
    [ -z "$dpath" ] && continue
    # The Read() entry may use the path verbatim or with // prefix for absolute paths
    if ! printf '%s\n' "$_perm_deny" | grep -qF "Read($dpath)"; then
      err "[policy:$_pol_regime] denyRead path '$dpath' has no matching Read($dpath) in permissions.deny (POL-02 enforcement gap)"
    fi
  done
fi

# POL-05c: disableBypassPermissionsMode wrong type (boolean instead of string "disable")
if [ -f ".claude/settings.json" ] && command -v jq >/dev/null 2>&1; then
  _dbpm_type="$(jq -r '.permissions.disableBypassPermissionsMode | type' .claude/settings.json 2>/dev/null)"
  _dbpm_val="$(jq -r '.permissions.disableBypassPermissionsMode // empty' .claude/settings.json 2>/dev/null)"
  if [ "$_dbpm_type" = "boolean" ]; then
    err "[policy] disableBypassPermissionsMode is boolean (got: $_dbpm_val) — must be string \"disable\". Re-run: conjure emit-policy"
  fi
fi

# Advisory: unreviewed template (note, exit 0)
if [ -f "conjure-policy/managed-settings.json" ] && command -v jq >/dev/null 2>&1; then
  if jq -e '._conjure_unreviewed == true' conjure-policy/managed-settings.json >/dev/null 2>&1 \
     || grep -qF "REPLACE_WITH_ORG_UUID" conjure-policy/managed-settings.json 2>/dev/null; then
    note "⚠ [policy] managed-settings.json contains unreviewed template values (REPLACE_WITH_ORG_UUID) — customize before deploying"
  fi
fi
```

---

### Anti-Patterns to Avoid

- **Type coercion in jq:** `jq '.sandbox.enabled = true'` is correct; `jq '.sandbox.enabled = "true"'` (string) is wrong and will silently produce a non-boolean that Claude Code ignores. Always use jq boolean literals (`true`/`false`) not strings.
- **disableBypassPermissionsMode as boolean:** `jq '.permissions.disableBypassPermissionsMode = true'` is WRONG. Must be string: `jq '.permissions.disableBypassPermissionsMode = "disable"'`. Validate at emit time.
- **Absolute paths in permissions.deny without `//` prefix:** `Read(/home/user/.aws)` is project-root-relative (`<project>/home/user/.aws`). Must be `Read(//home/user/.aws)` for true absolute path enforcement.
- **Using `jq .*` for array merge:** The `*` operator replaces arrays, not concatenates them. A second `emit-policy` run would truncate any user-added denyRead entries. Use explicit `array_merge` pattern.
- **Writing ps1 with `echo` or `printf` without BOM-control:** Use the `[System.IO.File]::WriteAllText` approach in the ps1; from bash, `mutate_write` is correct (no BOM added).
- **Writing plist with user-supplied string values un-escaped:** XML entities `<`, `>`, `&`, `"`, `'` in string values must be escaped. Since all denyRead paths are file-system paths (no XML metacharacters expected), this is low risk but worth noting.
- **Checking for overlay with `--compliance` flag absent:** The auto-detect path uses only the CLAUDE.md marker. The `--compliance` flag forces a full policy audit even when no marker is found.
- **`warn()` vs `note()` confusion (Phase 25 lesson):** `warn()` increments WARN counter and flips audit exit code to 1. Use `note()` (advisory, exit 0) for the "unreviewed template" case; use `err()` / `fail()` (increments FAIL, exit 2) for the three hard correctness bugs.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Plist XML generation | Custom recursive XML serializer | Shell heredoc with fixed structure + `plutil -lint` validation | The plist structure is fixed; only array contents vary. A heredoc is simpler, auditable, and shellcheck-clean. |
| JSON deep merge | Recursive bash string manipulation | jq with explicit array-union idiom | jq handles quoting, Unicode, and edge cases reliably; bash string manipulation is fragile for JSON |
| Type checking emitted JSON | grep/sed | `jq -e '(.x | type) == "string"'` | jq type() is authoritative; grep misses edge cases (whitespace, encoding) |
| "Is this an absolute path?" logic | Complex bash case/sed | Prefix convention + jq string manipulation | The three prefix conventions (`~/`, `/`, `./`) are well-defined; simple `case "$path" in` is sufficient and shellcheck-clean |
| Plist binary format | plutil conversion | Emit XML plist directly | MDM tools accept XML plist natively; binary plist is unnecessary complexity |

**Key insight:** The hardest correctness bugs in this domain are type coercion bugs (boolean vs string) and path-convention mismatches (single-slash vs double-slash in permissions.deny). Both are fully catchable with jq type checks at emit time and a negative fixture in the test suite.

---

## Per-Regime Deny-Path Conventions

[ASSUMED] — Based on training knowledge of HIPAA, PCI DSS, SOC 2, and GDPR security requirements. No authoritative Claude Code source defines these paths; they are conventional, standard-practice deny patterns that represent what a reasonable compliance engineer would configure. The operator is expected to review and extend them.

### Shared Baseline (all regimes)

```bash
# compliance/baseline/policy.sh (sourced by all regime policy.sh files)
BASELINE_DENY_READ=(
  "~/.aws"                    # AWS credentials
  "~/.aws/credentials"
  "~/.ssh"                    # SSH keys
  "~/.gnupg"                  # GPG keys
  "~/.config/gcloud"          # GCP credentials
  ".env"                      # project .env files (any depth)
  "**/.env"
  "**/.env.*"
  "**/secrets"
  "**/credentials"
  "**/*.pem"
  "**/*.key"
  "**/*.p12"
  "**/*.pfx"
)

BASELINE_DENY_WRITE=(
  "~/.ssh"
  "~/.gnupg"
  "~/.aws"
)

BASELINE_ALLOWED_DOMAINS=()  # empty = deny-all egress (operator adds as needed)
```

### HIPAA Delta (PHI paths)

```bash
# compliance/hipaa/policy.sh
REGIME_DENY_READ=(
  "**/phi"
  "**/phi/**"
  "**/patient*"
  "**/medical*"
  "**/health-records/**"
  "**/ehr/**"
  "**/mrn*"           # Medical Record Number
  "**/ssn*"           # Social Security Number
  "**/dob*"           # Date of Birth
)

REGIME_DENY_WRITE=(
  "**/phi/**"
  "**/patient*"
)
```

### PCI DSS Delta (cardholder data / PAN)

```bash
# compliance/pci/policy.sh
REGIME_DENY_READ=(
  "**/cardholder*"
  "**/pan*"           # Primary Account Number
  "**/card-data/**"
  "**/cde/**"         # Cardholder Data Environment
  "**/cvv*"
  "**/card-numbers*"
  "**/payment-data/**"
)

REGIME_DENY_WRITE=(
  "**/pan*"
  "**/cardholder*"
)
```

### SOC 2 Delta (audit logs, access control artifacts)

```bash
# compliance/soc2/policy.sh — narrower, SOC 2 is process-oriented
REGIME_DENY_READ=(
  "**/audit-logs/**"
  "**/access-logs/**"
)

REGIME_DENY_WRITE=(
  "**/audit-logs/**"   # append-only invariant — no overwrite
)
```

### GDPR Delta (personal data paths)

```bash
# compliance/gdpr/policy.sh
REGIME_DENY_READ=(
  "**/personal-data/**"
  "**/pii/**"
  "**/gdpr/**"
  "**/user-data/**"
  "**/data-subjects/**"
)

REGIME_DENY_WRITE=(
  "**/personal-data/**"
  "**/pii/**"
)
```

---

## Common Pitfalls

### Pitfall 1: disableBypassPermissionsMode type coercion

**What goes wrong:** jq emits `true` (boolean) instead of `"disable"` (string). The managed-settings.json looks correct visually, but Claude Code ignores a boolean value and bypass mode remains available.

**Why it happens:** jq defaults to boolean for `true`/`false` literals. A developer writes `.permissions.disableBypassPermissionsMode = true` instead of `= "disable"`.

**How to avoid:** In `validate_managed_settings_json()`, run: `jq -e '(.permissions.disableBypassPermissionsMode | type) == "string" and .permissions.disableBypassPermissionsMode == "disable"'`. Fail the emit if this assertion fails. Add a negative fixture with the boolean form and verify audit catches it.

**Warning signs:** If `claude /status` shows managed settings active but bypass mode is still accessible, this is the likely cause.

---

### Pitfall 2: Single-slash vs double-slash in permissions.deny absolute paths

**What goes wrong:** `Read(/etc/passwd)` is PROJECT-ROOT-RELATIVE, resolving to `<project>/etc/passwd` (a path that does not exist). Absolute paths require `Read(//etc/passwd)` (double slash).

**Why it happens:** The permissions.deny path syntax differs from standard filesystem paths. The docs warn: "A pattern like /Users/alice/file is NOT an absolute path. It's relative to the project root. Use //Users/alice/file for absolute paths."

**How to avoid:** When converting `sandbox.filesystem.denyRead` absolute paths (starting with `/`) to `permissions.deny` Read() entries, prepend an extra `/`. Only `~/` paths and `./` paths are converted verbatim.

**Warning signs:** POL-05b audit passes (Read() entry exists) but Claude can still read the protected file — check if the generated Read() entry uses single slash for an absolute path.

---

### Pitfall 3: jq array merge (idempotency failure)

**What goes wrong:** Using `jq '.sandbox.filesystem.denyRead = $new_paths'` replaces the entire denyRead array on re-run. Any paths the operator added manually are silently deleted.

**Why it happens:** jq assignment replaces; it does not merge. The `*` deep-merge operator also replaces arrays.

**How to avoid:** Use the `array_merge(a;b)` pattern: `(a // []) + (b // []) | unique`. The existing entries come first; new regime entries are appended; `unique` deduplicates.

**Warning signs:** Re-running `emit-policy` removes a path the operator manually added to the denyRead array.

---

### Pitfall 4: Non-TTY safety in emit-policy.sh

**What goes wrong:** `emit-policy.sh` is invoked in a CI pipeline or non-TTY context and hangs waiting for interactive input, or auto-mutates without confirmation.

**Why it happens:** A safety-check prompt (e.g., "overwrite existing settings.json?") reads from stdin, which is closed in CI.

**How to avoid:** Follow the established project convention: if non-TTY and a destructive action is needed, exit 2 with a human-readable message. Use `[ -t 0 ]` (stdin is a terminal) to detect non-TTY. For `emit-policy`, since the operator is explicitly invoking the command, no interactive confirmation is required — just snapshot-before-mutate and proceed. Non-TTY means no interactive prompts at all; exit 2 if the operation would require one.

---

### Pitfall 5: plist XML metacharacter escaping

**What goes wrong:** A deny-path containing `&`, `<`, or `>` (unlikely but possible) would produce malformed XML in the plist.

**Why it happens:** Shell heredocs write strings verbatim; XML requires entity-escaping.

**How to avoid:** Validate all denyRead paths against a safe-path whitelist (alphanumeric + `/`, `.`, `~`, `*`, `_`, `-`) before embedding in the plist. Reject paths with XML metacharacters (exit 2). Since Conjure ships standard regime paths (not user-supplied), this is a defense-in-depth check. Alternatively, use `plutil -lint` post-generation to catch any malformed output.

---

### Pitfall 6: managed-settings.d/ NOT emitted (deferred scope confusion)

**What goes wrong:** A planner task creates `conjure-policy/managed-settings.d/` fragments because the drop-in directory behavior was researched.

**Why it happens:** The drop-in directory is documented in official Claude Code docs and is a natural extension of managed-settings.json. It is easy to accidentally implement it.

**How to avoid:** `managed-settings.d/` is explicitly deferred as POL-F1. Emit only a single `managed-settings.json`. The planner MUST NOT include tasks for drop-in fragment generation.

---

### Pitfall 7: Windows Registry vs File-Based delivery confusion

**What goes wrong:** `Set-ClaudeCodePolicy.ps1` writes to the REGISTRY instead of the file system, or vice versa — or emits both and confuses operators.

**Why it happens:** Claude Code supports two Windows managed-settings delivery mechanisms: (1) the file `C:\Program Files\ClaudeCode\managed-settings.json` (Intune-style) and (2) `HKLM\SOFTWARE\Policies\ClaudeCode` registry key (Group Policy/ADMX-style). The official ps1 example uses the FILE approach.

**How to avoid:** The Phase 26 ps1 uses the file approach exclusively (matching the official Anthropic template). Registry/ADMX delivery (`ClaudeCode.admx`) is a separate artifact not generated by Conjure. Document this choice in the generated ps1 header comment.

---

## Code Examples

### Building and validating the sandbox JSON block

```bash
# Source: official Claude Code sandbox docs + jq 1.8.1 verified locally
# Build sandbox JSON from regime deny lists
build_sandbox_block() {
  local regime="$1"      # hipaa|soc2|gdpr|pci
  local deny_read_json="$2"   # JSON array of denyRead paths
  local deny_write_json="$3"  # JSON array of denyWrite paths

  jq -n \
    --arg regime "$regime" \
    --argjson deny_read "$deny_read_json" \
    --argjson deny_write "$deny_write_json" \
    '{
      enabled: true,
      failIfUnavailable: true,
      allowUnsandboxedCommands: false,
      filesystem: {
        denyRead: $deny_read,
        denyWrite: $deny_write
      },
      network: {
        allowedDomains: []
      }
    }'
}

# Validate sandbox block: all required keys present and correct types
validate_sandbox_json() {
  local content="$1"
  local errors=0

  if ! printf '%s' "$content" | jq -e '(.enabled | type) == "boolean"' >/dev/null 2>&1; then
    echo "✗ sandbox: 'enabled' must be a boolean" >&2
    errors=$((errors + 1))
  fi

  if ! printf '%s' "$content" | jq -e '(.filesystem.denyRead | type) == "array"' >/dev/null 2>&1; then
    echo "✗ sandbox: 'filesystem.denyRead' must be an array" >&2
    errors=$((errors + 1))
  fi

  if ! printf '%s' "$content" | jq -e '(.network.allowedDomains | type) == "array"' >/dev/null 2>&1; then
    echo "✗ sandbox: 'network.allowedDomains' must be an array" >&2
    errors=$((errors + 1))
  fi

  [ "$errors" -gt 0 ] && return 1
  return 0
}
```

### Validate managed-settings (type-safety for disableBypassPermissionsMode)

```bash
# Source: official Claude Code permissions docs + MDM examples repo
validate_managed_settings_json() {
  local content="$1"
  local errors=0

  # CRITICAL: disableBypassPermissionsMode must be STRING "disable", NOT boolean
  local dbpm_type dbpm_val
  dbpm_type="$(printf '%s' "$content" | jq -r '.permissions.disableBypassPermissionsMode | type' 2>/dev/null)"
  dbpm_val="$(printf '%s' "$content" | jq -r '.permissions.disableBypassPermissionsMode // empty' 2>/dev/null)"
  if [ "$dbpm_type" = "boolean" ]; then
    echo "✗ managed-settings: disableBypassPermissionsMode is boolean (got: $dbpm_val) — must be string \"disable\"" >&2
    errors=$((errors + 1))
  elif [ "$dbpm_type" = "string" ] && [ "$dbpm_val" != "disable" ]; then
    echo "✗ managed-settings: disableBypassPermissionsMode is \"$dbpm_val\" — must be \"disable\"" >&2
    errors=$((errors + 1))
  fi

  # allowManagedPermissionRulesOnly must be boolean
  if ! printf '%s' "$content" | jq -e 'if .allowManagedPermissionRulesOnly != null then (.allowManagedPermissionRulesOnly | type) == "boolean" else true end' >/dev/null 2>&1; then
    echo "✗ managed-settings: 'allowManagedPermissionRulesOnly' must be a boolean" >&2
    errors=$((errors + 1))
  fi

  # forceLoginOrgUUID must be a string (placeholder or real UUID)
  if ! printf '%s' "$content" | jq -e 'if .forceLoginOrgUUID != null then (.forceLoginOrgUUID | type) == "string" else true end' >/dev/null 2>&1; then
    echo "✗ managed-settings: 'forceLoginOrgUUID' must be a string" >&2
    errors=$((errors + 1))
  fi

  [ "$errors" -gt 0 ] && return 1
  return 0
}
```

### Verification assertion output (testable, persisted to VERIFY.txt)

```bash
# Print and persist verification commands to stdout + conjure-policy/VERIFY.txt
emit_verification_assertions() {
  local regime="$1"
  local output_dir="$2"

  local assertions
  assertions="$(printf '%s\n' \
    "=== conjure emit-policy ($regime) — Verification ===" \
    "" \
    "1. Sandbox enabled in project settings:" \
    "   jq '.sandbox.enabled' .claude/settings.json   # must return: true" \
    "" \
    "2. disableBypassPermissionsMode type and value:" \
    "   jq '.permissions.disableBypassPermissionsMode | [type, .]' .claude/settings.json" \
    "   # must return: [\"string\",\"disable\"]" \
    "" \
    "3. Managed settings active (after deploying conjure-policy/managed-settings.json):" \
    "   claude /status   # look for 'Enterprise managed settings (file)' in Setting sources" \
    "" \
    "4. denyRead paths mirrored in permissions.deny:" \
    "   jq '[.sandbox.filesystem.denyRead // [], .permissions.deny // []]' .claude/settings.json" \
    "" \
    "5. Unreviewed template check (must be false before deploying):" \
    "   grep -c REPLACE_WITH_ORG_UUID conjure-policy/managed-settings.json   # must return 0" \
    "" \
    "Compliance disclaimer: this configuration reduces non-compliant output risks" \
    "but does NOT make your project compliant. Engage your compliance officer.")"

  printf '%s\n' "$assertions"
  mutate_write "$output_dir/VERIFY.txt" "$assertions"
}
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Windows managed path `C:\ProgramData\ClaudeCode\` | `C:\Program Files\ClaudeCode\managed-settings.json` | Deprecated at v2.1.75 | Must NEVER emit the old path; audit should fail if it detects the old path |
| `managed-settings.json` only (single file) | `managed-settings.d/` drop-in directory supported | Current in latest docs | Conjure Phase 26 ships single-file only (POL-F1 deferred) |
| No plist/registry MDM artifacts | Official MDM examples in `anthropics/claude-code/examples/mdm/` | Added in recent releases | MDM examples are now authoritative; mirror their structure exactly |
| `disableBypassPermissionsMode: true` (boolean) | `disableBypassPermissionsMode: "disable"` (string) | Issue #44642 — the boolean form had no effect until a bug was fixed, but string was always the documented form | Emit string always; the boolean form is wrong regardless of CC version |
| sandbox.denyRead only (Bash-level) | sandbox.denyRead PLUS permissions.deny Read() (both layers) | Issue #32226 (active enforcement gap) | Both layers required for complete protection; denyRead alone leaves Read tool unblocked |

**Deprecated/outdated:**
- `C:\ProgramData\ClaudeCode\` Windows path: deprecated at v2.1.75. NEVER emit.
- `disableBypassPermissionsMode: true` (boolean): always wrong. The string `"disable"` is the only valid value.

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Per-regime deny-path lists (HIPAA PHI paths, PCI PAN paths, SOC2 audit-log paths, GDPR PII paths) are sensible defaults | Per-Regime Deny-Path Conventions | Operator must review and customize — the paths are clearly advisory ("standard patterns, no repo scanning" per requirements). Risk is low: wrong deny-paths are a policy gap, not a correctness bug, and the VERIFY.txt instructs operators to review. |
| A2 | `plutil -lint` on macOS validates generated plist XML correctly and exits 0 for valid XML | Pattern 4 (plist generation) | If plutil has edge-case behavior for unknown keys or whitespace, the validation gate could false-positive or false-negative. Low risk: plutil is a system tool with stable behavior. |
| A3 | Claude Code ignores unknown JSON keys (`_conjure_regime`, `_conjure_unreviewed`) in managed-settings.json | Pattern 3 (managed-settings schema) | If Claude Code rejects JSON with unknown top-level keys, the markers would break the managed-settings deployment. Mitigation: make the markers opt-in or strip them from the deployed file (emit a clean version for deployment, keep markers in the template). |
| A4 | `forceLoginOrgUUID` as an array of strings (multiple accepted orgs) is supported on Claude Code ≥2.1.117 | Pattern 3 (managed-settings) | The settings docs show both string and array forms; if the array form was added after 2.1.117, single-org-only orgs would need a string. Low risk: Conjure ships string form as the placeholder default. |

**If this table is empty:** All claims in this research were verified or cited — no user confirmation needed.

(Table has 4 assumed items, all low risk.)

---

## Open Questions

1. **Unknown key behavior in managed-settings.json**
   - What we know: jq/JSON spec allows unknown keys; Claude Code docs do not state it rejects them.
   - What's unclear: Whether Claude Code validates managed-settings.json against a strict schema and rejects files with unknown top-level keys like `_conjure_regime`.
   - Recommendation: Strip `_conjure_regime` and `_conjure_unreviewed` from the DEPLOYED managed-settings.json (the one written to `conjure-policy/managed-settings.json`). Keep only the `REPLACE_WITH_ORG_UUID` placeholder as the "unreviewed" sentinel — it is self-evidently fake and Claude Code will reject it at login time anyway.

2. **plutil availability on Linux CI**
   - What we know: `plutil` is a macOS system binary. Not present on Linux.
   - What's unclear: Whether the CI runner for this project is macOS or Linux.
   - Recommendation: Gate plist validation with `command -v plutil >/dev/null 2>&1` and skip on Linux; note in VERIFY.txt that plist should be linted on macOS before deploying.

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| jq | All JSON emit/validate | ✓ | 1.8.1 | None — project runtime requirement |
| bash | Script runtime | ✓ | POSIX 3.2+ | None — project constraint |
| plutil | plist XML validation | ✓ (macOS) | System | Skip validation on Linux; note in VERIFY.txt |
| python3 plistlib | Alternative plist generation | ✓ | 3.14.5 | plutil/heredoc (plutil is simpler for this use case) |
| git | Snapshot meta, version resolution | ✓ | System | Handled by existing snapshot.sh |

**Missing dependencies with no fallback:** none

**Missing dependencies with fallback:**
- plutil: macOS-only. Linux CI skips plist lint. Operator should validate on macOS before MDM deployment.

---

## Validation Architecture

> nyquist_validation is enabled (config.json `workflow.nyquist_validation: true`).

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Hand-rolled `tests/run.sh` fixture harness (project standard; bats-core for unit tests only) |
| Config file | `tests/run.sh` — no separate config file |
| Quick run command | `bash tests/run.sh 2>&1 \| grep -E "(POL|emit-policy)"` |
| Full suite command | `bash tests/run.sh` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| POL-01 | `emit-policy --regime hipaa` merges sandbox block into `.claude/settings.json` | fixture | `bash tests/run.sh` (grep POL-01) | ❌ Wave 0 |
| POL-01-idem | Re-running emit-policy produces identical sandbox block | fixture | `bash tests/run.sh` (grep POL-01-idem) | ❌ Wave 0 |
| POL-02 | Every denyRead path appears as `Read(<path>)` in permissions.deny | fixture | `bash tests/run.sh` (grep POL-02) | ❌ Wave 0 |
| POL-03 | managed-settings.json has correct keys and types | fixture | `bash tests/run.sh` (grep POL-03) | ❌ Wave 0 |
| POL-03-type | disableBypassPermissionsMode is string "disable", not boolean | fixture | `bash tests/run.sh` (grep POL-03-type) | ❌ Wave 0 |
| POL-04-macos | com.anthropic.claudecode.plist emitted with correct XML structure | fixture | `bash tests/run.sh` (grep POL-04-macos) | ❌ Wave 0 |
| POL-04-win | Set-ClaudeCodePolicy.ps1 emitted with correct JSON content | fixture | `bash tests/run.sh` (grep POL-04-win) | ❌ Wave 0 |
| POL-05a | audit fails when overlay active but sandbox.enabled false | fixture | `bash tests/run.sh` (grep POL-05a) | ❌ Wave 0 |
| POL-05b | audit fails when denyRead path has no matching permissions.deny Read() | fixture | `bash tests/run.sh` (grep POL-05b) | ❌ Wave 0 |
| POL-05c | audit fails when disableBypassPermissionsMode is boolean | fixture | `bash tests/run.sh` (grep POL-05c) | ❌ Wave 0 |
| POL-05-advisory | audit issues note (exit 0) for unreviewed template | fixture | `bash tests/run.sh` (grep POL-05-advisory) | ❌ Wave 0 |
| POL-dryrun | `--dry-run` prints mutations, writes no files | fixture | `bash tests/run.sh` (grep POL-dryrun) | ❌ Wave 0 |

### Sampling Rate
- **Per task commit:** `bash tests/run.sh 2>&1 | tail -5` (smoke: overall pass/fail count)
- **Per wave merge:** `bash tests/run.sh` (full suite green)
- **Phase gate:** Full suite green before `/gsd-verify-work`

### Wave 0 Gaps

All test fixtures and test blocks are new (Phase 26 is a new feature). Wave 0 must create:

- [ ] `tests/fixtures/_emit-policy/harness/CLAUDE.md` — with `<!-- compliance:hipaa -->` marker
- [ ] `tests/fixtures/_emit-policy/harness/.claude/settings.json` — minimal valid settings
- [ ] `tests/fixtures/_emit-policy/expected-sandbox.json` — expected sandbox block shape for hipaa
- [ ] `tests/fixtures/_emit-policy-broken/harness/.claude/settings.json` — with `disableBypassPermissionsMode: true` (boolean) for negative POL-05c test
- [ ] `tests/fixtures/_emit-policy-unreviewed/conjure-policy/managed-settings.json` — with REPLACE_WITH_ORG_UUID for POL-05-advisory test
- [ ] Test blocks in `tests/run.sh` for POL-01 through POL-05 (mirror _emit-plugin test block structure)
- [ ] `scripts/emit-policy.sh` (graceful-red stubs: test blocks must fail on missing script per test-first convention)
- [ ] `lib/policy-helpers.sh` (sourced by emit-policy.sh)
- [ ] `compliance/hipaa/policy.sh`, `compliance/soc2/policy.sh`, `compliance/gdpr/policy.sh`, `compliance/pci/policy.sh`

*(Test-first: graceful-red blocks land before implementation per CLAUDE.md conventions.)*

---

## Security Domain

> security_enforcement is enabled (not set to false in config).

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | yes (forceLoginOrgUUID) | String placeholder; operator replaces with org UUID |
| V3 Session Management | no | Not relevant to policy emission |
| V4 Access Control | yes (allowManagedPermissionRulesOnly, denyRead) | Permissions.deny + sandbox.filesystem.denyRead |
| V5 Input Validation | yes | jq type-check validation at emit time (validate_managed_settings_json, validate_sandbox_json) |
| V6 Cryptography | no | No cryptographic operations in this phase |

### Known Threat Patterns for Policy Emission Stack

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Type coercion: boolean instead of string for disableBypassPermissionsMode | Tampering | validate_managed_settings_json() type check at emit time + POL-05c audit check |
| Absolute path escape in permissions.deny (single slash vs double slash) | Tampering | Path-prefix conversion logic in build_deny_read_entries() + POL-05b audit verifies mirroring |
| Deprecated Windows path emission (C:\ProgramData\ClaudeCode\) | Tampering | Hard-coded to `C:\Program Files\ClaudeCode\` only; test fixture verifies correct path |
| XML injection via denyRead path in plist | Tampering | Sanitize paths before embedding; `plutil -lint` gate rejects malformed plist |
| Secret in emitted managed-settings.json | Information Disclosure | Extend secret_scan() pattern from plugin-helpers.sh to check managed-settings content before write |
| REPLACE_WITH_ORG_UUID deployed unreviewed | Tampering (auth bypass) | `_conjure_unreviewed` sentinel + POL-05 advisory note; VERIFY.txt step explicitly checks |

---

## Sources

### Primary (HIGH confidence)
- [code.claude.com/docs/en/sandboxing](https://code.claude.com/docs/en/sandboxing) — full sandbox settings schema with all key types and defaults
- [code.claude.com/docs/en/settings](https://code.claude.com/docs/en/settings) — managed-settings file paths by platform, plist domain, Windows registry path, deprecated path
- [code.claude.com/docs/en/permissions](https://code.claude.com/docs/en/permissions) — permissions.deny Read() format, path conventions (single vs double slash), managed-only settings table
- [code.claude.com/docs/en/server-managed-settings](https://code.claude.com/docs/en/server-managed-settings) — disableBypassPermissionsMode type and value, allowManagedPermissionRulesOnly, forceLoginOrgUUID (string/array forms), example JSON
- [github.com/anthropics/claude-code/examples/mdm/macos/com.anthropic.claudecode.plist](https://github.com/anthropics/claude-code/tree/main/examples/mdm) — exact plist XML structure (raw file fetched and verified)
- [github.com/anthropics/claude-code/examples/mdm/windows/Set-ClaudeCodePolicy.ps1](https://github.com/anthropics/claude-code/tree/main/examples/mdm) — exact ps1 structure (raw file fetched and verified)
- [github.com/anthropics/claude-code/examples/settings/settings-bash-sandbox.json](https://github.com/anthropics/claude-code/tree/main/examples/settings) — official sandbox settings example

### Secondary (MEDIUM confidence)
- [github.com/anthropics/claude-code/issues/32226](https://github.com/anthropics/claude-code/issues/32226) — denyRead enforcement gap (Read tool not blocked by sandbox.filesystem.denyRead)
- [github.com/anthropics/claude-code/issues/44642](https://github.com/anthropics/claude-code/issues/44642) — disableBypassPermissionsMode boolean had no effect (confirmed string is correct form)

### Tertiary (LOW confidence)
- Per-regime deny-path lists (HIPAA/PCI/SOC2/GDPR) — training knowledge, not from authoritative source; operator should review.

---

## Metadata

**Confidence breakdown:**
- Sandbox schema (enabled, filesystem.*, network.*): HIGH — verified from official Claude Code sandboxing docs
- managed-settings.json key names and types: HIGH — verified from official permissions docs + server-managed-settings docs + MDM examples repo
- macOS plist XML structure: HIGH — raw plist file fetched from anthropics/claude-code repo
- Windows ps1 structure: HIGH — raw ps1 file fetched from anthropics/claude-code repo
- Windows deprecated path: HIGH — explicitly documented as deprecated at v2.1.75
- permissions.deny Read() path format: HIGH — verified from permissions docs with explicit examples
- denyRead enforcement gap (#32226): HIGH — documented GitHub issue + confirmed in search results
- Per-regime deny-path contents: LOW — training knowledge; advisory defaults only

**Research date:** 2026-06-03
**Valid until:** 2026-07-03 (stable schema — Claude Code settings schema changes slowly; MDM artifact structure is very stable)
