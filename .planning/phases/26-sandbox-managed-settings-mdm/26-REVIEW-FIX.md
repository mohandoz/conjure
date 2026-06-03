---
phase: 26-sandbox-managed-settings-mdm
fixed_at: 2026-06-03T10:50:38Z
review_path: .planning/phases/26-sandbox-managed-settings-mdm/26-REVIEW.md
iteration: 2
findings_in_scope: 1
fixed: 1
skipped: 0
status: all_fixed
---

# Phase 26: Code Review Fix Report

**Fixed at:** 2026-06-03T10:50:38Z
**Source review:** .planning/phases/26-sandbox-managed-settings-mdm/26-REVIEW.md
**Iteration:** 2

**Summary:**
- Findings in scope: 1
- Fixed: 1
- Skipped: 0

## Fixed Issues

### WR-01 (new): WR-04 merge secret-abort leaks exit 1, not exit 2

**Files modified:** `scripts/emit-policy.sh`, `tests/run.sh`
**Commit:** 6ca9247
**Applied fix:**

The iteration-1 WR-04 fix added `secret_scan "$UPDATED" "settings.json" || return 1`
inside `merge_sandbox_block` (lib/policy-helpers.sh:144) and
`merge_deny_read_permissions` (lib/policy-helpers.sh:203). Those functions were
invoked in `scripts/emit-policy.sh` (lines 144/147) with no `|| exit 2`
translation, so under `set -euo pipefail` a credential in the operator's EXISTING
`.claude/settings.json` correctly aborted the write but propagated the function's
`return 1` as the script's exit code — violating CLAUDE.md's hard convention
("scripts/CLI/hooks exit 2, never exit 1") and emit-policy.sh's own documented
"2 = hard failure" contract.

Fix applied at the call sites (the idiom already used at emit-policy.sh lines
127/130/159/162 for every other hard-failure guard), leaving `lib/policy-helpers.sh`
untouched:

```bash
merge_sandbox_block "$TARGET/.claude/settings.json" "$SANDBOX_JSON" || exit 2
merge_deny_read_permissions "$TARGET/.claude/settings.json" "$COMBINED_DENY_READ" || exit 2
```

The trailing `||` also suppresses `set -e` for the statement, so the chosen
`exit 2` is what propagates.

**Test hardening:** The pre-existing `POL-secret-merged` test only asserted
exit `-ne 0`, which is precisely why the exit-1 regression slipped through. It was
strengthened to assert exit code is **exactly 2** and a second new assertion
(`POL-secret-merged-nowrite`) confirms the operator's `settings.json` is left
byte-for-byte unchanged (no write occurred). The fix was validated as load-bearing:
against the unfixed code the new assertion fails with `exited 1 ... expected 2`,
and passes once the `|| exit 2` translation is present.

**Verification:**
- Tier 1: re-read modified regions of both files; fix text present, surrounding code intact.
- Tier 2: `shellcheck -S error -e SC2164,SC2044,SC2034,SC2155` clean on
  `scripts/emit-policy.sh`, `lib/policy-helpers.sh`, `tests/run.sh`.
- Full suite: `bash tests/run.sh` → **508 PASS / 0 FAIL** (507 → 508; +1 from the
  new no-write assertion). Both new `POL-secret-merged` assertions pass.

---

_Fixed: 2026-06-03T10:50:38Z_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 2_
