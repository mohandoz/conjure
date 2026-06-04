# Project Research Summary

**Project:** Conjure v0.8.0 — Operability + DX
**Domain:** POSIX bash + Node stdlib .mjs CLI harness scaffolder — preflight diagnostics, telemetry insights, eval regression, init wizard, docs refresh
**Researched:** 2026-06-04
**Confidence:** HIGH (live codebase reads, empirical bash/jq tests, official promptfoo docs)

---

## Executive Summary

Conjure v0.8.0 is an operability and DX layer on top of a fully-shipped v0.7.0 foundation (579 passing tests, 20+ subcommands). The milestone adds six capability areas — `conjure doctor`, `conjure stats`, per-profile eval suites with regression baselines, init wizard polish, live-UAT automation, and docs refresh. All six fit within the existing zero-dependency bash + Node stdlib envelope: `dependencies: {}` stays empty and no new runtime tools are required beyond what is already in the preflight stack.

The two new worker scripts (`scripts/doctor.sh`, `scripts/stats.sh`) are created as separate files — not extensions of `scripts/preflight.sh` (kept as a silent sub-check) or `scripts/audit-setup.sh` (already 695 lines, single concern). Both new scripts are explicitly read-only and must not source `lib/mutate.sh`. The core architectural invariant — every filesystem write routes through `lib/mutate.sh` — is fully preserved.

**Top three risks:**

1. JSONL parse fragility silently truncating stats counts — every JSONL reader must use `jq -R -r 'try (fromjson | ...) // empty'` (per-line try-parse, not whole-file)
2. Advisory checks in doctor/stats calling `warn()` instead of `note()`, which flips `conjure audit` exit from 0 to 1 in CI (burned Phase 25; most frequently re-triggered issue in the codebase)
3. Legacy `exit 1` in `scripts/preflight.sh:109` — must be fixed to `exit 2` in the first phase before doctor inherits any preflight infrastructure

---

## Key Findings by Research File

**STACK.md (v0.8.0 section, lines ~2028+):** Zero net-new runtime dependencies. New usage patterns only: `jq -R -r 'try (fromjson) // empty'` (JSONL safety), `jq -rs 'group_by(.skill)'` (fire aggregation), `comm -23` on sorted lists (dead-skill detection), `_ver_gte` POSIX semver comparator (no `sort -V`, no `bc`), inline `mktemp`/`node`/`rm` ESM probe, `read -r </dev/tty` wizard prompts, `CONJURE_LIVE_TEST=1` gate, `skip()` 3-line TAP helper. `promptfoo@0.121.14` pin is current as of 2026-06-02 — no version bump needed.

**FEATURES.md:** Six feature areas with P1/P2/P3 separation. P1 must-haves: doctor (binary table + `.mjs` probe + `--json`), stats (fire count + dead-skill + cost estimate + `--json` + `--window`), test-harness hardening (git -C guard + skip() counter + SCHM-STALE doc), init wizard (auto-detect + TTY picker + `--yes` flag), eval per-profile configs + snapshot/compare, live-binary smoke (gated), README quick start + command reference. P3/deferred: doctor `--fix`, doctor `--watch`, stats trend, asciicast demo, docs website. Hard anti-features: auto-install binaries, network probes in doctor, central telemetry egress, ncurses TUI, remote profile fetching.

**ARCHITECTURE.md:** 7 new/modified file groups. NEW: `scripts/doctor.sh`, `scripts/stats.sh`, `profiles/{ts-next,node-nest,go-gin,python-fastapi}/eval-assertions.yaml.tmpl` (4 files), `tests/MANUAL-UAT.md`. MODIFIED: `cli/conjure` (cmd_doctor, cmd_stats, _detect_profile(), --baseline/--compare pass-through), `scripts/eval.sh` (_detect_applied_profiles(), per-profile promptfooconfig blocks, baseline/compare flags), `tests/run.sh` (mktemp guards, skip(), doctor/stats tests), CI workflow (conjure doctor step). UNCHANGED: all v0.7.0 libs, preflight.sh, audit-setup.sh, adopt.sh, all profile apply.sh scripts.

**PITFALLS.md:** 7 critical pitfalls, all with phase assignments: JSONL parse fragility (stats phase), doctor false-positives across OS environments (doctor phase), live eval cost bleed + fork-PR blockage (eval phase — 9 profiles × 50 rules × repeat:3 = 1,350 API calls/PR if unguarded), init wizard TTY pitfalls (init phase), `warn()` flipping audit exit (doctor phase — pre-emptive), live-binary smoke polluting CI (deferred-debt phase), README drift from documenting non-existent commands (docs two-pass strategy). Alpine/musl date fallback gap: both `date -v-30d` (BSD) and `date -d` (GNU) fail on Alpine — awk epoch arithmetic needed for stats CUTOFF.

---

## Implications for Roadmap

**Suggested 6-phase structure:**

1. **Deferred-Debt Paydown + Test-Harness Hardening** — `git -C "$VAR"` guards across all affected scripts/tests, `preflight.sh:109` exit 1 → exit 2, `skip()` counter in `tests/run.sh`, `tests/MANUAL-UAT.md`, live-smoke gating (`CONJURE_LIVE_TEST=1`). Safety fixes precede all other phases.
2. **`conjure doctor`** — new `scripts/doctor.sh` + `cmd_doctor`. Self-contained. Exit 2 (never 1). Advisory checks `note()` only. No preflight.sh behavior changes for existing callers.
3. **`conjure stats`** — new `scripts/stats.sh` + `cmd_stats`. Read-only, no mutate.sh. JSONL try-parse guard on every read path. BSD/GNU/awk date fallback chain for `--window` CUTOFF.
4. **Eval Suite Expansion** — per-profile `eval-assertions.yaml.tmpl` (4 profiles), `_detect_applied_profiles()`, `--baseline`/`--compare`, fork-PR guard in emitted workflow, `repeat: 1` for structural assertions. **Flag: shallow per-phase research** (fork-PR guard + assertion-count budget).
5. **Init UX Polish** — `_detect_profile()` + TTY-gated prompt in `cmd_init`. TTY guard FIRST statement. `read -r </dev/tty`. Non-TTY logs detection, never auto-applies. Profile logic stays in dispatcher.
6. **README + Docs Refresh (Two-Pass)** — Pass 1: v0.3–v0.7 current-state coverage. Pass 2: v0.8.0 new commands. CI grep gate: every `conjure <sub>` in usage() must appear in README.

### Research Flags

- Needs per-phase research: **Phase 4 (Eval Expansion)** — fork-PR guard in GitHub Actions + per-profile assertion-count budget
- Standard patterns (skip research-phase): Phases 1, 2, 3, 5, 6

---

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | All patterns verified against live codebase; every tool pre-existing |
| Features | HIGH | Prior art fully documented; eval patterns from official promptfoo docs |
| Architecture | HIGH | Live codebase read; all integration points confirmed from source |
| Pitfalls | HIGH | Derived from live empirical tests and documented PROJECT.md prior failures |

## Gaps to Address During Planning

- **Alpine date fallback in stats:** Verify BSD/GNU/awk three-way CUTOFF chain produces valid ISO8601 on Alpine Linux during Phase 3.
- **`preflight.sh:109` caller audit:** Confirm no caller uses `if [ $? -eq 1 ]` equality checks before fixing to `exit 2` in Phase 1.
- **Profile marker convention for eval:** Confirm all 9 profile `apply.sh` scripts write `<!-- profile:<name> -->` markers to CLAUDE.md. `ts-next` confirmed; other 8 need verification during Phase 4.
