# Phase 19 Discussion Log

**Date:** 2026-05-26
**Mode:** Autonomous (auto-answered)

## Areas Covered

### 1. Branch naming / idempotency
- **Decision**: `conjure/update-<short-hash-of-version>` — deterministic per kit version
- **Rationale**: Same version → same branch name → gh pr list idempotency check works naturally

### 2. cron template delivery (AUTPR-02)
- **Decision**: `conjure update --cron` writes the template; no changes to `conjure init`
- **Rationale**: Simpler; init flow already complex; standalone flag is more discoverable

### 3. PR body content
- **Decision**: Run `conjure check --porcelain`, convert to markdown table
- **Rationale**: Reuse Phase 17 deliverable; clean separation of concerns

### 4. Worker structure
- **Decision**: Inline in cmd_update (no separate script) — ~30 lines of git/gh operations
- **Rationale**: Short enough to not warrant a separate file; follows project's script-for-heavy-workers pattern (heavy logic in scripts/, CLI dispatch in cli/conjure)

## Deferred Ideas

- Auto-merge on clean apply → REQUIREMENTS.md says "never"
- conjure update --pr with auto-resolve → future

## Auto-Mode

All areas auto-answered.
