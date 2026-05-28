# Phase 20: Windows + CI Gate — Verification

**Date:** 2026-05-26
**Verdict:** PASS

---

## Success Criteria Check

| # | Criterion | Status | Evidence |
|---|-----------|--------|----------|
| 1 | `conjure.ps1` invokes full `conjure` CLI on Windows without requiring manual PATH setup | PASS | `conjure.ps1` uses `$PSScriptRoot\cli\conjure` — self-relative, no PATH required |
| 2 | `conjure.ps1` propagates exit codes: `--version` exits 0; command that exits 2 propagates 2 | PASS | `exit $LASTEXITCODE` after both Git Bash and WSL invocations; `$ErrorActionPreference = 'Continue'` prevents swallowing |
| 3 | CI matrix includes `windows-latest` job with `shell: pwsh` smoke-testing `conjure.ps1 --version` and exit code propagation | PASS | `windows-ps1-shim` job in `ci.yml` lines 117-140; two `shell: pwsh` steps |
| 4 | `ci-gate` fails with explicit error message on zero check-runs; includes retry loop | PASS | `release.yml` lines 17-32: 5-attempt loop, `FAIL: no GitHub check-runs found...` message, 15s sleep |

---

## Deliverable Verification

### WIN-01: conjure.ps1

```
$ wc -l conjure.ps1
      24 conjure.ps1
```
- 24 lines ≤ 30 ✓
- `$ErrorActionPreference = 'Continue'` at line 1 ✓
- Git Bash discovery: `$env:ProgramFiles\Git\bin\bash.exe` + `\usr\bin\bash.exe` ✓
- WSL fallback with `/mnt/<drive>` path conversion ✓
- `exit $LASTEXITCODE` × 2 (lines 13, 20) ✓
- Error path: `Write-Error` + `exit 2` (lines 23-24) ✓

### WIN-02: windows-ps1-shim CI job

- Job present in `ci.yml` at line 117 ✓
- `runs-on: windows-latest` ✓
- Step 1 (`shell: pwsh`): runs `conjure.ps1 --version`, asserts `$LASTEXITCODE -ne 0` fails ✓
- Step 2 (`shell: pwsh`): runs `conjure.ps1 init`, asserts `$LASTEXITCODE -ne 2` fails ✓

### DEBT-01: ci-gate retry loop

- `max_attempts=5` ✓
- `sleep 15` (75s total tolerance) ✓
- Empty-check guard: `FAIL: no GitHub check-runs found for <sha> after 5 attempts` ✓
- Response stored in `$response`, reused for failure check (no second API call) ✓
- Existing failed-conclusion check preserved ✓

---

## Regression Check

```
PASS: 302    FAIL: 0
```

All 302 existing tests pass. No regressions.

---

## Requirements Coverage

| Requirement | Status |
|-------------|--------|
| WIN-01 | COMPLETE |
| WIN-02 | COMPLETE |
| DEBT-01 | COMPLETE |
