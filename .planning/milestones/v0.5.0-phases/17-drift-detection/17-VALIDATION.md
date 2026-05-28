---
phase: 17
slug: drift-detection
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-05-26
---

# Phase 17 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Hand-rolled `tests/run.sh` (project standard) |
| **Config file** | none |
| **Quick run command** | `bash tests/run.sh` |
| **Full suite command** | `bash tests/run.sh` |
| **Estimated runtime** | ~15 seconds |

---

## Sampling Rate

- **After every task commit:** Run `bash tests/run.sh`
- **After every wave merge:** Run `bash tests/run.sh`
- **Phase gate:** Full suite green before `/gsd-verify-work`

---

## Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| DRIFT-01 | `conjure check` reports file-level delta (M/R/A categories) | integration | `bash tests/run.sh` (DRIFT section) | No — Wave 0 |
| DRIFT-01 | Exit 0 when no drift | integration | `bash tests/run.sh` | No — Wave 0 |
| DRIFT-01 | Exit 1 when drift detected | integration | `bash tests/run.sh` | No — Wave 0 |
| DRIFT-02 | `--porcelain` emits `M <path>` format | integration | `bash tests/run.sh` | No — Wave 0 |
| DRIFT-02 | `--porcelain` exits 0 when current | integration | `bash tests/run.sh` | No — Wave 0 |

---

## Wave 0 Gaps

- [ ] DRIFT test section in `tests/run.sh` — covers DRIFT-01 and DRIFT-02
- [ ] `scripts/check.sh` — worker script
- [ ] `cmd_check` in `cli/conjure` + dispatch entry + usage line

*(No new test infrastructure needed — existing `tests/run.sh` + `tests/lib/sandbox.sh` covers the pattern)*
