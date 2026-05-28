# Phase 18 Discussion Log

**Date:** 2026-05-26
**Mode:** Autonomous (auto-answered)

## Areas Covered

### 1. Sidecar discovery
- **Decision**: `find . -name ".conjure-conflict-*"` from harness root; sorted order
- **Rationale**: Naming from lib/merge.sh is the canonical source of truth

### 2. Prompt actions (k/a/e/s)
- **Decision**: keep removes sidecar; apply writes sidecar content to current + removes sidecar; edit opens $EDITOR + loops; skip leaves both
- **Rationale**: Exact spec from RESOLVE-01

### 3. Non-interactive guard
- **Decision**: `[ -t 0 ]` check, exit 2 with TTY message
- **Rationale**: RESOLVE-01 explicit; exit 2 = hard prerequisite per project convention

### 4. Dry-run
- **Decision**: Pass DRY_RUN through to mutate_rm — no additional logic needed
- **Rationale**: mutate_rm already handles it

## Deferred Ideas

- TUI diff viewer → v0.6.0
- Batch --all keep/apply → future

## Auto-Mode

All areas auto-answered — requirements are precise and codebase patterns are clear.
