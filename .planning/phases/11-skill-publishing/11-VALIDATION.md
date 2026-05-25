---
phase: 11
slug: skill-publishing
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-05-25
---

# Phase 11 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Hand-rolled bash (`tests/run.sh`) |
| **Config file** | none |
| **Quick run command** | `bash tests/run.sh` |
| **Full suite command** | `bash tests/run.sh` |
| **Estimated runtime** | ~10 seconds |

---

## Sampling Rate

- **After every task commit:** Run `bash tests/run.sh`
- **After every plan wave:** Run `bash tests/run.sh`
- **Before `/gsd-verify-work`:** Full suite must be green
- **Max feedback latency:** 15 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 11-01-01 | 01 | 1 | SKILL-01 | — | Egress scan hard-blocks curl/wget/nc/fetch/http(s) | unit (bash) | `bash tests/run.sh` | ❌ W0 | ⬜ pending |
| 11-01-02 | 01 | 1 | SKILL-01 | — | Egress scan hard-blocks $HOME/$USER/$SECRET refs | unit (bash) | `bash tests/run.sh` | ❌ W0 | ⬜ pending |
| 11-01-03 | 01 | 1 | SKILL-01 | — | Size cap >200 lines → exit 1 | unit (bash) | `bash tests/run.sh` | ❌ W0 | ⬜ pending |
| 11-01-04 | 01 | 1 | SKILL-01 | — | Frontmatter schema validation blocks missing fields | unit (bash) | `bash tests/run.sh` | ❌ W0 | ⬜ pending |
| 11-01-05 | 01 | 1 | SKILL-01 | — | Clean skill passes all gates | unit (bash) | `bash tests/run.sh` | ❌ W0 | ⬜ pending |
| 11-01-06 | 01 | 1 | SKILL-01 | — | CONJURE_DRYRUN suppresses all file mutations | unit (bash) | `bash tests/run.sh` | ❌ W0 | ⬜ pending |
| 11-02-01 | 02 | 1 | SKILL-02 | — | gh present → prints gh pr create command, does not exec | unit (bash) | `bash tests/run.sh` | ❌ W0 | ⬜ pending |
| 11-02-02 | 02 | 1 | SKILL-02 | — | gh absent → prints manual PR URL + checklist | unit (bash) | `bash tests/run.sh` | ❌ W0 | ⬜ pending |
| 11-03-01 | 02 | 1 | SKILL-03 | — | Dirty skill tree → exit 1 with specific message | unit (bash) | `bash tests/run.sh` | ❌ W0 | ⬜ pending |
| 11-03-02 | 02 | 1 | SKILL-03 | — | Untagged conjure HEAD → exit 1 with specific message | unit (bash) | `bash tests/run.sh` | ❌ W0 | ⬜ pending |
| 11-04-01 | 02 | 1 | SKILL-04 | — | --to <org/repo> → correct target repo in printed command | unit (bash) | `bash tests/run.sh` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `tests/run.sh` — SKILL-01 through SKILL-04 test blocks (follow MKTPL sandbox pattern, lines 762-888)
- [ ] `scripts/publish-skill.sh` — new worker script (shellcheck-clean)
- [ ] `cmd_publish_skill` + `publish-skill)` case in `cli/conjure` dispatch table

*No new test framework needed — `tests/run.sh` and its sandbox pattern already cover bash CLI testing.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| `gh pr create` command is syntactically correct | SKILL-02 | Requires live GitHub auth to execute | Run the printed command in a test fork and confirm PR opens |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 15s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
