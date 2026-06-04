# Requirements: Conjure v0.8.0 — Operability + DX

**Defined:** 2026-06-04
**Core Value:** A developer can turn any repo into a production-grade, eval-backed Claude Code harness with one trustworthy command — and keep it healthy over time.

## v0.8.0 Requirements

Requirements for this milestone. Each maps to roadmap phases.

### Deferred Debt + Test Harness (DEBT)

- [ ] **DEBT-03**: Test sandboxes guard `git -C "$VAR"` with a non-empty check after every `mktemp` (closes proven sandbox-escape vector)
- [ ] **DEBT-04**: `preflight.sh` exits 2 (never 1), with caller audit confirming no `$? -eq 1` equality checks break
- [ ] **DEBT-05**: `tests/run.sh` supports a `skip()` counter — PASS/FAIL/SKIP reporting for gated tests
- [ ] **DEBT-06**: SCHM-STALE swap verified kill-safe; atomic `jq > tmp && mv` applied where a write path exists, documented otherwise

### Live-System UAT (UAT)

- [ ] **UAT-01**: User can run a gated live `claude`-binary smoke test (`CONJURE_LIVE_TEST=1` + `command -v claude`); skipped cleanly otherwise
- [ ] **UAT-02**: User can run a gated live promptfoo eval (requires `ANTHROPIC_API_KEY`); skipped cleanly otherwise
- [ ] **UAT-03**: `tests/MANUAL-UAT.md` documents manual-only verification steps (MDM hardware, managed-settings deploy) with checklists

### conjure doctor (DOCT)

- [ ] **DOCT-01**: User can run `conjure doctor` for a dependency/version table with OS-detected install hints
- [ ] **DOCT-02**: Doctor probes Node `.mjs` ESM execution (mirrored probe, mktemp-based)
- [ ] **DOCT-03**: Doctor gates Claude Code version against minimum (≥2.1.117) and the `.conjure-version` pin
- [ ] **DOCT-04**: User can get machine-readable diagnostics via `conjure doctor --json`
- [ ] **DOCT-05**: Doctor validates installed harness structure (hooks wired, skills present, settings sane)
- [ ] **DOCT-06**: User can auto-remediate safe findings via `conjure doctor --fix` (all writes through `lib/mutate.sh`, backup-before-mutate)

### conjure stats (STAT)

- [ ] **STAT-01**: User can see per-skill fire counts from telemetry JSONL via `conjure stats`
- [ ] **STAT-02**: User can see dead skills (installed but never fired)
- [ ] **STAT-03**: User can see cost estimates (chars/4 heuristic × `lib/prices.json`)
- [ ] **STAT-04**: User can filter by `--window <days>` and emit `--json`
- [ ] **STAT-05**: User can see a per-session summary (session count, skills per session)
- [ ] **STAT-06**: User can export stats via `--export-csv`
- [ ] **STAT-07**: All JSONL reads use a per-line `try fromjson` guard; `audit --retire-list` migrated to the same pattern

### Eval Expansion (EVAL — continues v0.7.0 numbering)

- [ ] **EVAL-06**: User gets per-profile eval assertion templates for all 9 profiles, appended when profile markers are detected
- [ ] **EVAL-07**: User can snapshot a baseline and compare regressions (`eval snapshot` / `eval compare`)
- [ ] **EVAL-08**: Emitted eval workflow guards fork PRs and caps cost (`repeat: 1` for structural assertions)
- [ ] **EVAL-09**: User can assert tool trajectory from `allowed-tools` frontmatter via `metadata.skillCalls`

### Init Wizard (WIZ)

- [ ] **WIZ-01**: Init auto-detects profile from project fingerprints (package.json, go.mod, Cargo.toml, pyproject.toml, pom.xml, monorepo markers)
- [ ] **WIZ-02**: TTY-gated confirm picker (`read -r </dev/tty`); non-TTY logs detection, never auto-applies
- [ ] **WIZ-03**: User can accept detected defaults non-interactively via `--yes`
- [ ] **WIZ-04**: Wizard offers compliance overlay selection during init

### Docs Refresh (DOCS)

- [ ] **DOCS-01**: README rewritten — doctor→init→audit quick start, feature tour covering v0.3–v0.8
- [ ] **DOCS-02**: Command reference covers every `usage()` subcommand; CI grep gate enforces README coverage
- [ ] **DOCS-03**: MIGRATION-GUIDE.md + FAILURE-MODES.md synced to current behavior

## Future Requirements

Deferred to a later release. Tracked but not in current roadmap.

### Operability

- **DOCT-F1**: `conjure doctor --watch` continuous mode
- **STAT-F1**: Stats trend graphs over time

### Docs

- **DOCS-F1**: Asciicast demo in README
- **DOCS-F2**: Dedicated docs website

## Out of Scope

Explicitly excluded. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| Network probes in doctor | Zero-egress principle — doctor checks local state only |
| Central telemetry / egress | Telemetry stays local-only, opt-in, PII-free — trust asset |
| Auto-install of missing binaries | Doctor hints, never mutates the system — no `curl \| sh` foot-guns |
| ncurses TUI for any command | Out of envelope; guided line prompts suffice |
| Remote profile fetching | Profiles ship with the kit; no runtime downloads |
| Bundling promptfoo | `dependencies: {}` stays empty; pinned `npx` shell-out only |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| — | — | Pending roadmap |

**Coverage:**
- v0.8.0 requirements: 31 total
- Mapped to phases: 0
- Unmapped: 31 ⚠️ (roadmap pending)

---
*Requirements defined: 2026-06-04*
*Last updated: 2026-06-04 after initial definition*
