# Phase 20: Windows + CI Gate — Context

**Date:** 2026-05-26
**Phase:** 20 of 20 — Windows + CI Gate
**Goal:** Native Windows users can invoke `conjure` via a PowerShell shim without Git Bash on PATH, and CI correctly rejects tagged releases with zero check-runs

---

## Domain

Three deliverables:
1. **WIN-01**: `conjure.ps1` PowerShell shim (≤30 lines)
2. **WIN-02**: `windows-ps1-shim` CI job with `shell: pwsh`
3. **DEBT-01**: `ci-gate` empty-check guard + retry loop in `release.yml`

---

## Decisions

### conjure.ps1 — bash discovery order (WIN-01)

- Check `$env:ProgramFiles\Git\bin\bash.exe` first (standard Git for Windows install)
- Check `$env:ProgramFiles\Git\usr\bin\bash.exe` as secondary Git Bash candidate
- Fall back to WSL (`wsl` command) if both Git Bash paths absent
- If neither found: `Write-Error` + `exit 2` (hard prerequisite per project convention)
- Rationale: Git for Windows is the most common Windows dev toolchain; WSL is secondary

### conjure.ps1 — exit code propagation (WIN-01)

- `$ErrorActionPreference = 'Continue'` at top — prevents PowerShell from throwing on non-zero exits
- After each invocation: `exit $LASTEXITCODE`
- This ensures exit 2 from bash passes through to pwsh caller intact

### conjure.ps1 — script self-location (WIN-01)

- Use `$PSScriptRoot` to find `cli/conjure` relative to the shim
- WSL path conversion: `$PSScriptRoot.Substring(0,1).ToLower()` for drive letter → `/mnt/<drive>`
- Rationale: shim lives at repo root; `cli/conjure` is always `$PSScriptRoot\cli\conjure`

### conjure.ps1 — size constraint

- Must be ≤30 lines per REQUIREMENTS.md WIN-01
- Target: ~20 lines (Git Bash check + WSL fallback + error exit)

### WIN-02 — CI job placement

- Add `windows-ps1-shim` job to `.github/workflows/ci.yml` (not release.yml)
- Uses `shell: pwsh` (PowerShell Core, not Git Bash)
- Two test steps:
  1. `conjure.ps1 --version` → assert exit 0 (shim finds bash, runs conjure)
  2. `conjure.ps1 init` without target → assert exit 2 (exit code propagates)
- Rationale: exit 2 from `conjure init` (missing required arg) is guaranteed by project convention

### DEBT-01 — ci-gate retry loop

- 5 attempts with 15s sleep between retries (75s total tolerance before fail)
- Fail condition: `total_count == 0` after all retries → exit 1 with explicit message
- Retry message per attempt: `"Waiting for check-runs to propagate (attempt N/5)..."`
- Keep existing failure check (failed conclusions) unchanged
- Rationale: GitHub API can lag 30-60s on fresh tags; 5×15s covers 99% of cases

### DEBT-01 — response reuse

- Store full API response in `$response` variable; parse `total_count` from it
- Reuse same `$response` for the failed-conclusion check after loop exits
- Rationale: avoid second API call; response is already complete after the retry loop

---

## Canonical Refs

- `.planning/REQUIREMENTS.md` — WIN-01, WIN-02, DEBT-01
- `.github/workflows/ci.yml` — add `windows-ps1-shim` job (WIN-02)
- `.github/workflows/release.yml` — ci-gate lines 9-28 (DEBT-01)
- `conjure.ps1` — new file at repo root (WIN-01)
- `tests/run.sh` — no new tests needed (CI validates WIN-01/WIN-02 end-to-end)

---

## Code Context

### ci-gate current state (release.yml lines 9-28)

```yaml
ci-gate:
  runs-on: ubuntu-latest
  steps:
    - name: Check CI status for tagged commit
      env:
        GH_TOKEN: ${{ github.token }}
      run: |
        echo "Checking CI checks for ${{ github.sha }}..."
        result=$(gh api \
          "/repos/${{ github.repository }}/commits/${{ github.sha }}/check-runs" \
          --jq '.check_runs[] | select(.name != "Release") | ...')
        failed=$(echo "$result" | jq -r 'select(.conclusion == "failure" ...) | .name')
        if [ -n "$failed" ]; then echo "FAIL: ..."; exit 1; fi
        echo "OK: all required checks passed"
```

Missing: empty-check guard, retry loop.

### conjure.ps1 structure

```powershell
$ErrorActionPreference = 'Continue'

$gitBash = $null
foreach ($c in @("$env:ProgramFiles\Git\bin\bash.exe", "$env:ProgramFiles\Git\usr\bin\bash.exe")) {
    if (Test-Path $c) { $gitBash = $c; break }
}

if ($gitBash) {
    & $gitBash "$PSScriptRoot\cli\conjure" @args
    exit $LASTEXITCODE
}

if (Get-Command wsl -ErrorAction SilentlyContinue) {
    $drive = $PSScriptRoot.Substring(0, 1).ToLower()
    $rest  = $PSScriptRoot.Substring(2) -replace '\\', '/'
    wsl -- bash "/mnt/$drive$rest/cli/conjure" @args
    exit $LASTEXITCODE
}

Write-Error "conjure.ps1: Git Bash or WSL required. Install Git for Windows or enable WSL."
exit 2
```

---

## Out of Scope

- Pure PowerShell port of conjure without bash dependency (v0.6.0 per REQUIREMENTS.md)
- Git Bash path discovery via registry (over-engineering; `$env:ProgramFiles\Git` covers 99%)
- `tests/run.sh` unit tests for conjure.ps1 (bash can't invoke pwsh; CI covers it)

---

## Auto-Mode Note

Auto-answered. Decisions follow from WIN-01/WIN-02/DEBT-01 requirements, existing ci.yml structure (windows-test job uses `shell: bash` not `shell: pwsh`), and release.yml ci-gate current state.
