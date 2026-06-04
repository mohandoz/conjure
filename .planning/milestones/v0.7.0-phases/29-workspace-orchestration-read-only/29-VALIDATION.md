---
phase: 29
slug: workspace-orchestration-read-only
status: draft
nyquist_compliant: true
wave_0_complete: false
created: 2026-06-03
---

# Phase 29 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Hand-rolled `tests/run.sh` fixture harness (project convention) |
| **Config file** | none — fixtures under `tests/fixtures/_workspace*/` |
| **Quick run command** | `bash tests/run.sh` (grep the WS-* block) |
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
| 29-00-01 | 00 | 0 | WS-01..04 | — | Workspace fixture (2-3 mini repos w/ .claude/, one bad-path manifest variant) + graceful-red WS block | fixture | `bash tests/run.sh` (WS red) | ❌ W0 | ⬜ pending |
| 29-01-01 | 01 | 1 | WS-01 | T-29-01 | lib/workspace.sh: manifest schema validation ({schema_version,repos:[{name,path,tags}]}, relative paths) + parent-dir discovery; invalid manifest → exit 2 | fixture | `bash tests/run.sh` (WS-01) | ❌ W0 | ⬜ pending |
| 29-01-02 | 01 | 1 | WS-02 | T-29-02 | `workspace init` discovers sibling repos w/ .claude/; TTY prompt /dev/tty; non-TTY needs --yes else exit 2; invalid path → exit 2 BEFORE write; written via mutate_write | fixture+PTY | `bash tests/run.sh` (WS-02) | ❌ W0 | ⬜ pending |
| 29-02-01 | 02 | 2 | WS-03 | T-29-03 | `workspace check` per-repo check --porcelain → table; fail-tolerant: perm-error repo → exit 1 partial, rest processed; bad path skipped w/ warning | fixture | `bash tests/run.sh` (WS-03) | ❌ W0 | ⬜ pending |
| 29-02-02 | 02 | 2 | WS-04 | T-29-04 | `workspace audit` per-repo audit --json → pass/fail table + global summary; exit 2 any-fail / 1 warn-only / 0 all-pass; --fail-fast aborts on first failure; bad path skipped w/ warning | fixture | `bash tests/run.sh` (WS-04) | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `tests/fixtures/_workspace/` — parent dir with 2-3 mini repos each containing `.claude/` (+ minimal settings.json so audit/check run) and a pre-built `.conjure-workspace.json`
- [ ] `tests/fixtures/_workspace-badpath/` — manifest with 3 repos, 1 invalid path (init-reject + check/audit-skip cases)
- [ ] One repo variant that fails audit (e.g. boolean disableBypassPermissionsMode) so the aggregate exit-2 path is testable
- [ ] Phase 29 graceful-red WS block appended to `tests/run.sh` (incl. a PTY/non-TTY `--yes` gate test via the existing expect/PTY pattern)

*Wave 0 establishes the Nyquist invariant: fixtures before aggregation logic.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| TTY interactive confirmation prompt UX | WS-02 | The non-TTY path is auto-tested; the interactive prompt look-and-feel needs a human terminal | In a real terminal: `conjure workspace init` in a dir with siblings → prompt lists discovered repos, confirm writes manifest |

---

## Validation Sign-Off

- [x] All tasks have automated verify (fixture/test) or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references (fixtures incl. bad-path + failing-audit variants)
- [x] No watch-mode flags
- [x] Feedback latency < 60s
- [x] `nyquist_compliant: true` set in frontmatter (Wave 0 wired)

**Approval:** pending (wave_0_complete: false)
