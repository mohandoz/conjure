# Plan 20-02 Summary: WIN-02 CI job + DEBT-01 ci-gate fix

**Date:** 2026-05-26
**Status:** COMPLETE

## Deliverables

1. Added `windows-ps1-shim` job to `ci.yml` (WIN-02)
2. Fixed `ci-gate` in `release.yml` with retry loop + empty-check guard (DEBT-01)

## What was built

### ci.yml (WIN-02)
New `windows-ps1-shim` job (lines 117-140):
- `runs-on: windows-latest`, two `shell: pwsh` steps
- Step 1: `conjure.ps1 --version` → assert exit 0
- Step 2: `conjure.ps1 init` → assert exit 2 (exit code propagation)

### release.yml (DEBT-01)
Replaced ci-gate run block with:
- 5-attempt retry loop with 15s sleep between attempts
- Breaks when `total_count > 0`
- Explicit FAIL message after all retries exhausted with zero check-runs
- Reuses `$response` variable for failure-conclusion check (no second API call)

## Files modified

- `.github/workflows/ci.yml` — added `windows-ps1-shim` job
- `.github/workflows/release.yml` — ci-gate retry loop + empty-check guard
