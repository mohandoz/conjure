---
phase: 23
slug: restructure-skill-safety-gates
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-05-29
---

# Phase 23 — Validation Strategy

> Per-phase validation contract. Source: 23-RESEARCH.md "## Validation Architecture".

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Hand-rolled `tests/run.sh` + `tests/lib/sandbox.sh` (no new deps; bats unit-only per STACK.md) |
| **Quick run command** | `bash tests/run.sh 2>&1 \| grep -iE 'restructure\|RESTR\|Phase 23'` |
| **Full suite command** | `bash tests/run.sh` (expect ≥401 baseline + new Phase 23 asserts, FAIL 0) |
| **Lint gate** | `shellcheck -S error -e SC2164,SC2044,SC2034,SC2155 templates/skills/restructure/gates/*.sh scripts/init-project.sh` |
| **Convention gate** | `grep -v '^#' templates/skills/restructure/gates/*.sh \| grep -c 'exit 1'` → 0 |
| **Skill cap gate** | SKILL.md has `name:`+`description:`; `wc -l SKILL.md` ≤ 200 (criterion 1) |
| **Estimated runtime** | ~30–60s full suite |

---

## Sampling Rate

- **After every task commit:** `bash tests/run.sh 2>&1 | grep -iE 'restructure|RESTR|Phase 23'` + shellcheck on new gates
- **After every plan wave:** full `bash tests/run.sh` (no regression below baseline) + `exit 1` count = 0 on new scripts
- **Before `/gsd-verify-work`:** full suite green + SKILL.md ≤200 lines + frontmatter audit clean
- **Max feedback latency:** ~60s

---

## Per-Task Verification Map

| Req / Criterion | Wave | Behavior | Test Type | Automated Command (sketch) | Deterministic | Status |
|-----------------|------|----------|-----------|----------------------------|---------------|--------|
| Crit-1 / RESTR-01,02 | 0 | `restructure` scaffolded at `.claude/skills/restructure/SKILL.md`; `allowed-tools: [Read, Bash]`; ≤200 lines | unit | scaffold sandbox via `init-project.sh existing`; assert file, `grep allowed-tools.*Read.*Bash`, `wc -l ≤200` | YES | ⬜ |
| Crit-1 | 0 | `gates/*.sh` ship alongside SKILL.md | unit | assert `.claude/skills/restructure/gates/verify-invariants.sh` present after scaffold | YES | ⬜ |
| RESTR-04 / Crit-4 | 0 | invariant present → gate rc0; omitted → rc2 + missing list | unit | `gates/verify-invariants.sh <staging> <INVARIANTS.txt>` rc0 / rc2 | YES | ⬜ |
| RESTR-04 | 0 | normalized match: reflowed/case-mangled but complete → rc0 | unit | feed whitespace/case-mangled complete file → rc0 | YES | ⬜ |
| RESTR-05 / Crit-5 | 0 | proposed CLAUDE.md w/ `@import` → audit gate rc2 + output; clean → rc0 | unit | `gates/audit-staged.sh <@import-file>` rc2; clean ≤100 → rc0 | YES | ⬜ |
| RESTR-05 | 0 | >hard-cap proposed file → cap-breach block | unit | `gates/audit-staged.sh <oversized-file>` rc≥1 | YES | ⬜ |
| RESTR-06 / Crit-6 | 0 | file w/ `we decided`/`never` → flagged individual; clean → bulk | unit | `gates/decision-scan.sh <decided-file>` → individual; clean → bulk | YES | ⬜ |
| RESTR-03 / Crit-3 | 0 | non-TTY approval → exit 2 (never auto-approve); bulk → one summary log line | unit | pipe non-TTY stdin → exit 2; assert single `RESTRUCTURE` summary line | YES (non-TTY) | ⬜ |
| RESTR-03 / Crit-2 | — | interactive `approve/skip/edit`; `edit` re-runs gates; never proceeds without response | manual/expect | PTY/`expect` UAT (Phase 22 precedent) | NO (interactive) | manual |
| RESTR-02 | 0 | applied op routed via `conjure adopt --apply-step` → mutate.sh; `status: applied` | integration | synthetic manifest+staging; `--apply-step`; jq `status==applied` + dest changed | YES | ⬜ |
| RESTR-01 | 0 | skill group-by reads manifest per-file classification | integration | group-by helper vs `_adopt-restructure-steps` fixture; assert bucket counts | YES | ⬜ (fixture exists) |
| Crit-6 | 0 | archive ops sequenced last in proposed plan | integration | assert proposed-step ordering: `op:archive` after write/extract | YES | ⬜ |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Planning Resolutions (open questions O-1..O-3, within CONTEXT "Claude's Discretion")

- **O-1 (audit gate strictness):** pre-write gate blocks on `@import` (always) + HARD cap breach (CLAUDE.md >100 per `lib/caps.sh`, SKILL >200). Implement `gates/audit-staged.sh` as a temp-dir shim that seeds the staged file as `CLAUDE.md` + a minimal `.claude/` and runs the REAL `conjure audit` (faithful to RESTR-05 "run through conjure audit"), falling back to direct `grep '^@'` + `wc -l` only if the shim is infeasible.
- **O-2 (invariant granularity):** extract invariants as short CANONICAL TOKENS (`exit 2`, `@import`, `≤100`, command names, short prohibition fragments) per D-06 — maximizes normalized-substring robustness against LLM paraphrase (CR-1).
- **O-3 (`edit` mechanics):** `edit` = skill (LLM) prompts the user (via `/dev/tty`) for the change, re-drafts the staged content, re-writes via `conjure adopt --update-manifest`, then RE-RUNS the gates before re-prompting (keeps the Read+Bash proposer model; no `$EDITOR` launch).

---

## Wave 0 Requirements

- [ ] NEW `▸ Phase 23 — restructure gate helpers` block in `tests/run.sh` (graceful-red before helpers exist, mirroring Phase 22 Wave 0)
- [ ] Synthetic gate fixtures (small inline `printf` heredocs): CLAUDE.md WITH invariant, WITHOUT invariant, with `@import`, oversized, with `we decided`/`never`, clean reference-doc
- [ ] Reuse `tests/fixtures/_adopt-restructure-steps/adopt-manifest.json` (exists) for group-by + apply-step drive
- [ ] `init-project.sh existing` scaffold test for criterion 1 (uses `tests/lib/sandbox.sh`)
- [ ] (Optional) `expect` harness for the interactive approval loop — else manual UAT doc

> No framework install — `tests/run.sh` + `sandbox.sh` exist. All gaps are new assertions/fixtures.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Interactive `approve/skip/edit` loop over `/dev/tty` | RESTR-03 / Crit-2 | TTY read not driveable by the plain harness; non-TTY exit-2 IS automated | Drive via a real PTY (`expect`, as Phase 22's recovery prompt was tested): confirm per-class grouped prompt, approve applies, skip leaves as-is, edit re-drafts + re-gates + re-prompts, empty/unknown re-prompts, never proceeds without input |

---

## Validation Sign-Off

- [ ] All gate-helper tasks have `<automated>` verify or Wave 0 dependency
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 60s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
