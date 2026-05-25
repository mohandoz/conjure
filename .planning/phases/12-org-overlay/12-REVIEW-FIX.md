---
phase: 12-org-overlay
fixed: 2026-05-26
source_review: 12-REVIEW.md
findings_fixed: 9
findings_deferred: 4
status: fixed
---

# Phase 12: Code Review Fix Report

**Source:** `12-REVIEW.md` (3 critical, 6 warning, 4 info)
**Fixed:** 9 findings (all critical + warning)
**Deferred:** 4 info findings (non-blocking)
**Final test result:** PASS: 261 FAIL: 0

## Fixed

| ID | File | Fix |
|----|------|-----|
| CR-01 | `scripts/init-overlay.sh`, `scripts/refresh-overlay.sh` | Added `trap 'rm -rf "$CLONE_TMP"' EXIT` after `mktemp -d`; removed inline rm from error paths |
| CR-02 | `scripts/init-overlay.sh`, `scripts/refresh-overlay.sh`, `scripts/audit-setup.sh` | Added `--` before `$OVERLAY_URL` in all `git clone` and `git ls-remote` calls |
| CR-03 | `scripts/audit-setup.sh` | Captured `stat` result into `_mtime` with `|| echo 0` fallback before arithmetic |
| WR-01 | `scripts/init-overlay.sh`, `scripts/refresh-overlay.sh` | Moved `lib/mutate.sh` existence check before `source` so it can fire |
| WR-02 | `cli/conjure` | Added `tr '-' '_'` in `cmd_help` so hyphenated subcommands find their function |
| WR-03 | `cli/conjure` | Replaced `for f in $(find ...)` with `while IFS= read -r f; done < <(find ...)` |
| WR-04 | `scripts/audit-setup.sh` | Added empty-check on `OVERLAY_URL` after marker parse; warns if missing |
| WR-05 | `tests/run.sh` | Added EXIT traps for `MKTPL_DIR` and `SKILL_DIR` temp directories |
| WR-06 | `scripts/audit-setup.sh` | Consolidated duplicate EXIT traps into single `_audit_cleanup()` function |

## Deferred (Info)

| ID | Reason |
|----|--------|
| IN-01 | Resolved automatically by WR-01 fix — comment will now be accurate |
| IN-02 | Opaque clone error messages — acceptable tradeoff for now; address in v0.4.x |
| IN-03 | FM_DIR trap gaps — low risk (synthetic test content only); address in future test cleanup pass |
| IN-04 | Missing empty-URL OVLY test — acceptable gap; add in Phase 15 regression sweep |
