---
phase: 28
slug: promptfoo-eval-context-budget-linter
status: draft
nyquist_compliant: true
wave_0_complete: false
created: 2026-06-03
---

# Phase 28 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Hand-rolled `tests/run.sh` fixture harness (project convention) |
| **Config file** | none — fixtures under `tests/fixtures/_eval*/` |
| **Quick run command** | `bash tests/run.sh` (grep the EVAL-* block) |
| **Full suite command** | `bash tests/run.sh` |
| **Estimated runtime** | ~30–60 seconds |

---

## Sampling Rate

- **After every task commit:** Run `bash tests/run.sh`
- **After every plan wave:** Run `bash tests/run.sh` + `shellcheck -S error -e SC2164,SC2044,SC2034,SC2155 <changed .sh>`
- **Before `/gsd-verify-work`:** Full suite must be green
- **Max feedback latency:** 60 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Correct Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 28-00-01 | 00 | 0 | EVAL-01..05 | — | Fixtures (harness with skills + CLAUDE.md rules; expected config; eval-coverage-gap fixture) + graceful-red EVAL block; peer-dep/provider integration probe (A1/A2/A3) | fixture | `bash tests/run.sh` (EVAL red) | ❌ W0 | ⬜ pending |
| 28-01-01 | 01 | 1 | EVAL-01 | T-28-01 | `eval init` scaffolds .conjure/eval/promptfooconfig.yaml: claude-agent-sdk provider, skill-used per skill, llm-rubric per CLAUDE.md rule line, evaluateOptions.repeat:3 (config-level flakiness guard) | fixture | `bash tests/run.sh` (EVAL-01) | ❌ W0 | ⬜ pending |
| 28-01-02 | 01 | 1 | EVAL-02 | T-28-02 | `eval run` Node≥20.20 preflight + `npx --yes promptfoo@0.121.14` exit passthrough; promptfoo absent → exit 2; audit with promptfoo absent → exit 0 (decoupled) | fixture | `bash tests/run.sh` (EVAL-02) | ❌ W0 | ⬜ pending |
| 28-02-01 | 02 | 2 | EVAL-03 | T-28-03 | `eval --emit-workflow` writes .github/workflows/conjure-eval.yml via mutate_write: pull_request, promptfoo/promptfoo-action, fail-on-threshold:80, repeat:3/repeat-min-pass:2, path filters .claude/** + CLAUDE.md; breaking a hook fails the suite | fixture | `bash tests/run.sh` (EVAL-03) | ❌ W0 | ⬜ pending |
| 28-03-01 | 03 | 3 | EVAL-04 | T-28-04 | `audit --budget` chars/4 on CLAUDE.md + SKILL.md indexes; reuses 15k/25k tiers (≥25k err exit 2); top-5 contributors; --porcelain {total,threshold,over,contributors[]} | fixture | `bash tests/run.sh` (EVAL-04) | ❌ W0 | ⬜ pending |
| 28-03-02 | 03 | 3 | EVAL-05 | T-28-05 | `audit` reports installed skills with no skill-used coverage in promptfooconfig.yaml → note() advisory (exit 0); skill added after init appears in gap report; config absent → note() | fixture | `bash tests/run.sh` (EVAL-05) | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `tests/fixtures/_eval/harness/` — harness with ≥2 installed skills + a CLAUDE.md with rule lines
- [ ] `tests/fixtures/_eval/expected-promptfooconfig.yaml` — golden config (claude-agent-sdk provider, skill-used per skill, llm-rubric per rule, evaluateOptions.repeat:3)
- [ ] `tests/fixtures/_eval-coverage-gap/` — harness with a skill that has no skill-used assertion in an existing config (EVAL-05)
- [ ] `tests/fixtures/_eval-overbudget/` — harness whose CLAUDE.md + SKILL.md indexes exceed the 25k tier (EVAL-04 over-budget)
- [ ] Provider/peer-dep integration probe documenting A1/A2/A3 resolution (claude-agent-sdk auto-install, working_dir/setting_sources behavior) — gated to skip cleanly when promptfoo/node absent
- [ ] Phase 28 graceful-red EVAL block appended to `tests/run.sh`

*Wave 0 establishes the Nyquist invariant: fixtures + goldens before any eval/budget logic.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| `conjure eval run` against a real promptfoo + claude-agent-sdk + ANTHROPIC_API_KEY | EVAL-02 | CI has no promptfoo/Node20.20/API key; real LLM eval is non-deterministic + costs tokens | On a machine with Node≥20.20 + key: `conjure eval init && conjure eval run` → promptfoo runs, exit code passes through |
| Enforcement test: breaking a hook binary fails the emitted PR-gate | EVAL-03 | Requires a live promptfoo run in CI/locally | Break a hook, run the emitted workflow locally via `act` or a real PR → eval suite fails |

---

## Validation Sign-Off

- [x] All tasks have automated verify (fixture/test) or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references (fixtures + goldens + integration probe)
- [x] No watch-mode flags
- [x] Feedback latency < 60s
- [x] `nyquist_compliant: true` set in frontmatter (Wave 0 wired)

**Approval:** pending (wave_0_complete: false — Wave 0 not yet executed)
