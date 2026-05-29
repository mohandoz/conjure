---
phase: 24
slug: integration-tests-argus-fixture
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-05-29
---

# Phase 24 — Validation Strategy

> This phase IS validation — the Validation Architecture is the deliverable.
> Source: 24-RESEARCH.md "## Validation Architecture". No REQ-* IDs (verification phase);
> gated by the 5 ROADMAP success criteria.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Hand-rolled `tests/run.sh` (project standard; bats unit-only per STACK.md) — add a `▸ Phase 24` block |
| **Quick run command** | `bash tests/run.sh 2>&1 \| grep -E "Phase 24\|✗"` |
| **Full suite command** | `bash tests/run.sh` (must not regress the 429 green assertions) |
| **CI invocation** | `.github/workflows/ci.yml` already runs `bash tests/run.sh` on the OS matrix — NO workflow change needed |
| **Lint gate** | `shellcheck -S error -e SC2164,SC2044,SC2034,SC2155` on the new generator + any `report()` deviation |
| **Estimated runtime** | full suite ~60s; the 500-file argus sections add ~6–15s |

---

## Sampling Rate

- **After every task commit:** `bash tests/run.sh 2>&1 | grep -E "Phase 24|✗"`
- **After every wave:** full `bash tests/run.sh` (no regression below 429 baseline)
- **Before `/gsd-verify-work`:** full suite green + shellcheck clean on new scripts
- **Max feedback latency:** ~60s

---

## The 5 Criteria → Observable Test Points

| # | ROADMAP Criterion | Observable Signal(s) | Automatable | Wave | Status |
|---|-------------------|----------------------|-------------|------|--------|
| C1 | dry-run on 500 files: <30s AND zero files written | (a) non-git: no `adopt-manifest.json` + no `.conjure-adopt-state` under target; (b) `date +%s` delta < 30 (measured ~6s, ~5x margin) | YES | 0 | ⬜ |
| C2 | live adopt then `--rollback`: zero diff (sha256 every file) | (a) per-file sha256 == recorded before; (b) `diff -r` w/ D-03 excludes empty; (c) `[ROLLBACK]` in log; (d) created[] gone | YES | 0 | ⬜ |
| C3 | idempotent re-run: zero mutations + "nothing to scaffold" | (a) `Scaffolded: 0 layer files` in report; (b) `state.json .created\|length==0`; (c) `diff -r` (excl D-03) run1-after vs run2-after empty; (d) literal "nothing to scaffold" (via report() deviation, O-1) | YES | 0 | ⬜ |
| C4 | SIGKILL after snapshot/before scaffold → recovery; rollback restores | (a) non-TTY re-run exits 2 + "last completed:" + 3 flags; (b) `CONJURE_ADOPT_ROLLBACK=1` re-run then `diff -r` (excl D-03) empty | YES (interactive prompt manual-only, PTY-verified in 22/23) | 0 | ⬜ |
| C5 | symlink skipped by inventory; @import CLAUDE.md blocked, never written | (a) symlink path absent from manifest `files[]`; (b) `audit-staged.sh` on `@import` staged file exits 2; (c) target CLAUDE.md never gains `^@` | YES | 0 | ⬜ |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Planning Resolutions (research open questions)

- **O-1 (criterion 3 "nothing to scaffold"):** the literal string does NOT exist in code today (report prints `Scaffolded: 0 layer files`). RESOLUTION = do BOTH: assert the already-true signals (a/b/c above) AND make a minimal 1-line `report()` deviation in `scripts/adopt.sh` so it emits the literal "nothing to scaffold" when `created[]` is empty — so the ROADMAP criterion text and the test literally agree. Document as a deviation (a tiny source touch in an otherwise test-only phase, justified by criterion 3's exact wording).
- **O-2:** live adopt needs NO `git init` — `precondition_git` skips the dirty-tree gate on a non-git target, so the sandbox runs the full live path. Confirmed.
- **O-3:** `▸ Phase 24` block inserts after `tests/run.sh:3280` (before the Summary), behind a `P24_ARGUS_OK` presence guard.
- **Fixture strategy:** a `generate-argus.sh` generator (mirroring `generate-large.sh`) materializes 500 `.md` files + a REAL `ln -s` symlink + an oversized/sprawling CLAUDE.md + an `@import` staged seed into a passed target dir — keeps the repo lean (no 500 committed files). Dir is `tests/fixtures/_brownfield-argus/` (leading underscore — excluded from the generic `tests/fixtures/[^_]*/` sweep loops).

---

## Wave 0 Requirements

- [ ] `tests/fixtures/_brownfield-argus/generate-argus.sh` — materializes 500 `.md` + real `ln -s` symlink + oversized CLAUDE.md + `@import` seed into a target dir
- [ ] `▸ Phase 24` block in `tests/run.sh` (after :3280) — 5 sections (one per criterion) behind `P24_ARGUS_OK` guard, mirroring the Phase 22 section shapes
- [ ] (recommended, O-1) 1-line `report()` deviation in `scripts/adopt.sh` for criterion 3's literal "nothing to scaffold"
- [ ] inline `# shellcheck` directives on the generator matching project style

> Framework install: none. `tests/run.sh` + `tests/lib/sandbox.sh` exist; the pipeline under test ships. All gaps are new fixtures/assertions (+ one optional source deviation).

---

## Manual-Only Verifications

| Behavior | Criterion | Why Manual | Test Instructions |
|----------|-----------|------------|-------------------|
| Interactive `[r]/[c]/[s]` recovery prompt via real TTY | C4 | TTY interaction not reliably CI-automatable; the non-TTY exit-2 path IS automated | Already PTY-verified in Phase 22/23 UAT. Optional re-confirm on argus: `conjure adopt`, `kill -9` mid-run, re-run in a terminal, confirm prompt + each choice. |

---

## Validation Sign-Off

- [ ] All criteria have automated assertions (C1–C5) or a documented manual-only note (C4 interactive sub-check)
- [ ] No watch-mode flags
- [ ] Wave 0 generator + `▸ Phase 24` block present
- [ ] Full suite green (no regression below 429)
- [ ] Feedback latency < 60s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
