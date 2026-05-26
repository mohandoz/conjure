# Phase 17 Discussion Log

**Date:** 2026-05-26
**Mode:** Autonomous (auto-answered)

## Areas Covered

### 1. Drift classification algorithm
- **Decision**: sha256 comparison against kit templates; 3-way (user-edit) suppression deferred to v0.5.x
- **Rationale**: Simple and correct for v0.5.0 scope; REQUIREMENTS.md explicitly defers the user-edit false-positive case

### 2. --porcelain format
- **Decision**: `<A|M|R> <path>` one line per file, no color, no headers
- **Rationale**: Standard convention (git porcelain); machine-readable for CI pipelines per DRIFT-02

### 3. Implementation structure
- **Decision**: `cmd_check` in cli/conjure.sh + `scripts/check.sh` worker
- **Rationale**: Consistent with cmd_update/scripts/update.sh pattern already in codebase

### 4. Exit codes
- **Decision**: 0 = current, 1 = drift; exact match to DRIFT-02 requirement

## Deferred Ideas

- `conjure check --json` → v0.5.x (already in REQUIREMENTS.md future section)
- 3-way base snapshot → v0.5.x

## Auto-Mode

All gray areas auto-answered — well-defined requirement with clear codebase analogs.
