---
phase: 22
slug: conjure-adopt-cli-core-rollback
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-05-28
---

# Phase 22 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.
> Source signals: 22-RESEARCH.md "## Validation Architecture".

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Hand-rolled `tests/run.sh` (project standard — no new test deps; `bats-core` unit-only per STACK.md). Mirror Phase 21 inline block style. |
| **Config file** | none — `tests/run.sh` self-contained; sandbox via `tests/lib/sandbox.sh` |
| **Quick run command** | `bash tests/run.sh 2>&1 \| grep -E "Phase 22\|✗"` |
| **Full suite command** | `bash tests/run.sh` |
| **Estimated runtime** | ~30–60 seconds (full suite, 300+ assertions) |

---

## Sampling Rate

- **After every task commit:** Run `bash tests/run.sh 2>&1 | grep -E "Phase 22|✗"`
- **After every plan wave:** Run `bash tests/run.sh` (full suite — must not regress Phase 21 / v0.5.0)
- **Before `/gsd-verify-work`:** Full suite green + `shellcheck scripts/adopt.sh cli/conjure` clean
- **Max feedback latency:** ~60 seconds

---

## Per-Task Verification Map

> Task IDs assigned by planner. Maps each ROADMAP success criterion + requirement to an observable signal.

| Criterion / Req | Wave | Behavior (observable signal) | Test Type | Automated Command | File Exists | Status |
|-----------------|------|------------------------------|-----------|-------------------|-------------|--------|
| Crit 1 / ADOPT-02 | 0 | `adopt --dry-run` on brownfield prints 5-step plan, zero writes to target, manifest at temp path | integration | sandbox; `DRY_RUN=1 adopt.sh`; assert `git status --porcelain "$sb"` empty AND no `adopt-manifest.json` under target AND temp manifest exists | ❌ W0 | ⬜ pending |
| Crit 1 / ADOPT-02 | 0 | dry-run stdout has `preconditions/snapshot/inventory/scaffold/audit` + `[dry-run] would` lines | integration | grep dry-run stdout for each step label | ❌ W0 | ⬜ pending |
| Crit 2 / ADOPT-01,04,05,06 | 0 | live adopt: snapshot + manifest + missing layers scaffolded (existing untouched) + audit + before/after CLAUDE.md report | integration | run live in sandbox; assert backup CLAUDE.md, manifest present, new hooks present, pre-existing skill byte-unchanged, report line matches | ❌ W0 | ⬜ pending |
| Crit 2 / ADOPT-04 | 0 | idempotent scaffold: pre-existing file NOT overwritten | integration | sha256 pre-existing skill before/after; assert equal | ❌ W0 | ⬜ pending |
| Crit 3 / ADOPT-03,SAFE-06 | 0 | dirty-tree → `exit 2` clear msg; `--force` → proceeds + WARN in RESTRUCTURE-LOG.md | integration | git sandbox + untracked file; no-force → rc==2; `--force` → rc==0 AND `grep -q 'WARN.*uncommitted'` | ❌ W0 | ⬜ pending |
| Crit 4 / SAFE-02 | 0 | live then `--rollback`: every mutated file sha256 == recorded before; `[ROLLBACK]` in log; created[] gone | integration | capture pre-adopt sha256; rollback; assert per-file equal AND `grep -q '\[ROLLBACK\]'` AND created files removed | ❌ W0 | ⬜ pending |
| Crit 4 / SAFE-02 | 0 | zero-diff pre-adopt vs post-rollback (excl. conjure dirs, D-03) | integration | `diff -r` with excludes → empty | ❌ W0 | ⬜ pending |
| Crit 5 / SAFE-05 | 0 | SIGKILL mid-run → re-run detects partial state, offers `[r]/[c]/[s]` (non-TTY: exit 2 + "last completed") | integration | background run + `kill -9` after snapshot; re-run non-interactive → assert exit 2 + "last completed: snapshot" | ❌ W0 | ⬜ pending |
| SAFE-04 | 0 | each step writes state record w/ sha256 before/after; valid JSON after each step | integration | `jq . .conjure-adopt-state` parses; `.mutated[].before` present | ❌ W0 | ⬜ pending |
| SAFE-07 | 0 | RESTRUCTURE-LOG.md gets entry per step as it happens | integration | assert log has SNAPSHOT, INVENTORY, SCAFFOLD, AUDIT in order | ❌ W0 | ⬜ pending |
| ADOPT-02 (lib gap) | 0 | dry-run manifest at mktemp temp, not hardcoded `/tmp/adopt-manifest-dryrun.json` | integration | assert printed manifest path under `$TMPDIR`/`mktemp -d` | ❌ W0 | ⬜ pending |
| D-08 / D-05 | 0 | `--apply-step` on synthetic manifest executes write+archive via mutate_*; marks `status: applied` | integration | hand-authored manifest; `--apply-step`; assert files changed + status applied + RESTRUCTURE log entry | ❌ W0 | ⬜ pending |
| D-08 / D-06 | 0 | `--update-manifest` appends step + rejects malformed JSON w/ exit 2 | integration | valid step appended; `{}` → rc==2 | ❌ W0 | ⬜ pending |
| Pitfall 3 | 0 | two consecutive live adopts do NOT nest backups-in-backups | integration | run twice (clear state between); assert no nested `.conjure-adopt-backups` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] Phase 22 test block in `tests/run.sh` — all five ROADMAP criteria + SAFE-04/07 + D-08 (mirror Phase 21 block; use `sandbox_setup`)
- [ ] Synthetic `restructure_steps[]` manifest fixture (one `write` + one `archive` op) for `--apply-step`/`--update-manifest` (D-08)
- [ ] git-initialized sandbox helper for dirty-tree test (criterion 3)
- [ ] SIGKILL test harness: background-launch + `kill -9` + re-run assertion (non-TTY exit-2 form)
- [ ] `shellcheck` directive coverage for `adopt.sh` (match inline `# shellcheck` style)

> No framework install needed — `tests/run.sh` + `tests/lib/sandbox.sh` exist. All gaps are new assertions/fixtures.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Interactive `[r]/[c]/[s]` recovery prompt via real TTY | SAFE-05 | TTY interaction not reliably automatable in CI; non-TTY exit-2 path IS automated | Run `conjure adopt`, `kill -9` mid-run, re-run in a terminal, confirm prompt appears and each choice behaves |
| macOS BSD `cp -a` snapshot self-copy edge (Pitfall A1) | SAFE-01 | macOS-specific `cp` behavior; CI may be Linux | On macOS, run two consecutive live adopts; confirm no nested backup dirs (also covered by Pitfall 3 automated test on Linux) |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 60s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
