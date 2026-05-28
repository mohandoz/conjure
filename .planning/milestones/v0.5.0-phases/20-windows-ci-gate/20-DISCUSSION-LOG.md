# Phase 20 Discussion Log

**Date:** 2026-05-26
**Mode:** Autonomous (auto-answered)

## Areas Covered

### 1. conjure.ps1 bash discovery order
- **Decision**: `$env:ProgramFiles\Git\bin\bash.exe` → `\usr\bin\bash.exe` → WSL → exit 2
- **Rationale**: Git for Windows standard install path; WSL as secondary fallback

### 2. Exit code propagation mechanism
- **Decision**: `$ErrorActionPreference = 'Continue'` + `exit $LASTEXITCODE`
- **Rationale**: PowerShell default behavior swallows non-zero exits as errors; Continue prevents that

### 3. WIN-02 CI job placement
- **Decision**: Add `windows-ps1-shim` to ci.yml (not release.yml); test `--version` exit 0 and `init` exit 2
- **Rationale**: ci.yml is the test matrix; release.yml is release gating only

### 4. DEBT-01 retry parameters
- **Decision**: 5 attempts, 15s sleep, explicit FAIL message on zero check-runs after all retries
- **Rationale**: 75s total tolerance covers GitHub API lag; reuse stored response to avoid second API call

## Deferred Ideas

- Pure PS port without bash (v0.6.0 per REQUIREMENTS.md)
- Registry-based Git Bash discovery (overkill)

## Auto-Mode

All areas auto-answered.
