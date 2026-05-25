# Requirements: Conjure

**Defined:** 2026-05-24
**Core Value:** A developer can turn any repo into a production-grade, eval-backed Claude Code harness with one trustworthy command — and keep it healthy over time.
**Milestone:** v0.3.0 — Testing + Telemetry ("earn trust before reach")

## v1 Requirements

Requirements for the v0.3.0 milestone. Each maps to a roadmap phase. Theme: close the gap between what Conjure *claims* and what it *verifiably does*.

### Safety & Cross-Platform

- [x] **SAFE-01**: `conjure init --dry-run` performs zero filesystem mutations — dry-run threads through `init-project.sh`, profile `apply.sh`, and the `.conjure-version` stamp (fixes live bug: today only `migrations/*` honor it)
- [x] **SAFE-02**: All writes route through one shared mutation helper (`lib/mutate.sh`) that honors dry-run, so enforcement is a chokepoint not per-call-site
- [x] **SAFE-03**: Generated hook wiring runs on native Windows — init emits portable `node .mjs` hook wiring instead of hardwired `bash .claude/hooks/*.sh` (fixes live bug in `templates/settings.json.tmpl`)
- [x] **SAFE-04**: Pre-flight check reports each missing dependency with a copy-pasteable, OS-detected install fix-it (brew/apt/winget/npm) and never auto-installs

### Testing

- [x] **TEST-01**: One committed example fixture per stack profile under `tests/fixtures/<profile>/`
- [x] **TEST-02**: Fixtures run sandboxed (isolated `HOME`/`XDG_CONFIG_HOME`/`PATH`, copied to a temp dir) with no leakage to the real `$HOME`
- [x] **TEST-03**: `tests/run.sh` drives per-fixture audit assertions via golden-file (`EXPECT`) comparison
- [x] **TEST-04**: At least one fixture intentionally fails audit, and assertions check specific findings (proves the suite can catch regressions, not just exit 0)
- [x] **TEST-05**: Regression suite asserts a `--dry-run` run leaves the fixture tree byte-identical (snapshot invariant)
- [x] **TEST-06**: CI includes a `windows-latest` leg that validates `.mjs` hook wiring
- [x] **TEST-07**: Documented failure modes (FAILURE-MODES.md) have reproductions encoded as tests

### Cost Estimation

- [x] **COST-01**: `conjure audit --cost` estimates per-session token cost from harness size using the chars/4 heuristic and a dated price table
- [x] **COST-02**: Cost output is labeled an estimate with an explicit ±band and names the model + pricing date (no false precision)
- [x] **COST-03**: The default cost path is fully offline; an opt-in `--exact` flag may call Anthropic's `count_tokens` endpoint

### Telemetry

- [x] **TLMY-01**: Skill-firing telemetry is opt-in (off by default) and PII-free
- [x] **TLMY-02**: Telemetry writes local-only append-only JSONL the user owns (`.claude/telemetry/`) with zero network egress
- [x] **TLMY-03**: A build/CI test greps all shipped hooks to assert no network egress from telemetry
- [x] **TLMY-04**: Conjure produces a skill "retire-list" from the local telemetry event log (which skills loaded per session)
- [x] **TLMY-05**: `TELEMETRY.md` schema ships in the same change as the hook, and telemetry honors the `DO_NOT_TRACK` convention

### Docs & Adoption

- [x] **DOCS-01**: README includes an asciinema→GIF demo of `conjure init` + `conjure audit` (recorded against safe dry-run)

## v2 Requirements

Deferred to a later milestone (v0.4.0 — Distribution + ecosystem). Tracked, not in current roadmap.

### Distribution

- **DIST-01**: Publish to Claude Code Marketplace via `.claude-plugin/marketplace.json`
- **DIST-02**: Homebrew formula (`brew install conjure`)
- **DIST-03**: Docker image with all tools preinstalled
- **DIST-04**: `conjure publish-skill <name>` — contribute a project skill back to the kit
- **DIST-05**: Org overlay system (base kit + private overlay repo per org)

## Out of Scope

Explicitly excluded for v0.3.0. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| Non-local / opt-out / silent telemetry | Top star-killer risk; contradicts kit's "trust before reach" + compliance overlays. Local-only opt-in only. |
| Bundled offline Claude tokenizer | No accurate offline Claude 4 tokenizer exists; would add a dependency for a wrong answer. Heuristic + opt-in online `--exact` instead. |
| shellspec test framework | Unmaintained (last release 2021). Extend hand-rolled `tests/run.sh`; bats-core only at unit level if needed. |
| Auto-update 3-way merge / drift detector / auto-PR bot | v0.5.0; needs frozen schemas first. |
| Workspace / cross-repo graph orchestration | v0.6.0; single-repo correctness first. |
| Full 9×4 profile×overlay fixture matrix | Combinatorial explosion; use representative pairs only. |
| Making a project *actually* compliant | Overlays reduce non-compliant output only; real compliance needs people + process + audit. |

## Traceability

Each requirement maps to exactly one phase. See `.planning/ROADMAP.md` for phase detail.

| Requirement | Phase | Status |
|-------------|-------|--------|
| SAFE-01 | Phase 2 | Complete |
| SAFE-02 | Phase 2 | Complete |
| SAFE-03 | Phase 1 | Complete |
| SAFE-04 | Phase 1 | Complete |
| TEST-01 | Phase 3 | Complete |
| TEST-02 | Phase 3 | Complete |
| TEST-03 | Phase 4 | Complete |
| TEST-04 | Phase 3 | Complete |
| TEST-05 | Phase 4 | Complete |
| TEST-06 | Phase 4 | Complete |
| TEST-07 | Phase 4 | Complete |
| COST-01 | Phase 6 | Complete |
| COST-02 | Phase 6 | Complete |
| COST-03 | Phase 6 | Complete |
| TLMY-01 | Phase 7 | Complete |
| TLMY-02 | Phase 7 | Complete |
| TLMY-03 | Phase 7 | Complete |
| TLMY-04 | Phase 7 | Complete |
| TLMY-05 | Phase 7 | Complete |
| DOCS-01 | Phase 5 | Complete |

**Coverage:**
- v1 requirements: 20 total
- Mapped to phases: 20 ✓
- Unmapped: 0 ✓

**Per-phase counts:** Phase 1 (2), Phase 2 (2), Phase 3 (3), Phase 4 (4), Phase 5 (1), Phase 6 (3), Phase 7 (5)

---
*Requirements defined: 2026-05-24*
*Last updated: 2026-05-24 after roadmap creation (traceability populated)*
