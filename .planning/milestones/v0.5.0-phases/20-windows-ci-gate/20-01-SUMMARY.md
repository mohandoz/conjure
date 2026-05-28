# Plan 20-01 Summary: conjure.ps1 PowerShell shim

**Date:** 2026-05-26
**Status:** COMPLETE

## Deliverable

Created `conjure.ps1` at repo root (24 lines, ≤30 limit met).

## What was built

PowerShell shim that:
1. Discovers Git Bash at standard Git for Windows install paths
2. Falls back to WSL with correct `/mnt/<drive>` path conversion
3. Exits 2 with `Write-Error` if neither found
4. Uses `$ErrorActionPreference = 'Continue'` + `exit $LASTEXITCODE` throughout

## Files modified

- `conjure.ps1` — new file (24 lines)
