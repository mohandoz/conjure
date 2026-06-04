---
phase: 26-sandbox-managed-settings-mdm
reviewed: 2026-06-03T10:45:00Z
depth: standard
files_reviewed: 8
files_reviewed_list:
  - lib/policy-helpers.sh
  - scripts/emit-policy.sh
  - scripts/audit-setup.sh
  - cli/conjure
  - compliance/hipaa/policy.sh
  - compliance/soc2/policy.sh
  - compliance/gdpr/policy.sh
  - compliance/pci/policy.sh
findings:
  critical: 0
  warning: 1
  info: 0
  total: 1
status: issues_found
---

# Phase 26: Code Review Report (Iteration 2)

**Reviewed:** 2026-06-03T10:45:00Z
**Depth:** standard
**Files Reviewed:** 8
**Status:** issues_found

## Summary

Re-review (iteration 2) of the 7 fix commits resolving the prior 6 WARNINGs.
Five of the six fixes are clean and the core security invariants all hold
(verified by running emit/audit end-to-end):

- **WR-01** (empty deny list → `[]`): verified — `build_deny_read_entries` on `[]` filtered to `[]`, no stray `[""]`.
- **WR-02** (POL-05b reuses `build_deny_read_entries`): verified — emit and audit now agree. Absolute path `/etc/foo` emits `Read(//etc/foo)` and audit derives the identical expected entry; relative `./rel` → `Read(/rel)`; home `~/.aws` → `Read(~/.aws)`; bare `**/.env` passes through. End-to-end audit on an emitted HIPAA settings.json reports **no** POL-02 enforcement gap.
- **WR-03** (operator-added denyRead mirrored): verified — a hand-added `/operator/secret` path is mirrored to `Read(//operator/secret)` on re-emit; emit-twice is byte-identical (idempotent); every `sandbox.filesystem.denyRead` entry has a matching `permissions.deny` Read().
- **WR-05** (plist XML-metachar escaping): verified — valid plist passes `plutil -lint`; a `&`/`<`/`>` in a deny path/entry/domain is rejected with exit 2.
- **WR-06** (ps1 here-string hardening): verified — emitted `.ps1` uses `$env:ProgramFiles` (zero `ProgramData` occurrences); the `'@`-terminator guard does not reject valid jq-pretty-printed JSON (string values are always double-quote-prefixed, so a body line can never begin with `'@`).

Core invariants re-confirmed: array merge uses `array_merge` (union+unique) on
every array key with only scalar `$old * $new` object merge — **no** recursive
`.*` on arrays; `disableBypassPermissionsMode` is STRING `"disable"`;
managed-settings.json has exactly the 4 allowed top-level keys
(`permissions`, `allowManagedPermissionRulesOnly`, `forceLoginOrgUUID`,
`sandbox`); artifacts go only to `--output`; validate-before-write holds;
POL advisory uses `note()`.

One genuinely **NEW** Warning was introduced by the **WR-04** fix: the
merge-path secret abort now leaks **exit 1** (not exit 2) on a credential found
in the operator's existing settings.json. The abort itself is correct and safe
(no write occurs, no data loss, no bypass) — only the exit code violates the
project's hard convention.

## Warnings

### WR-01 (new): WR-04 merge secret-abort leaks exit 1, not exit 2

**File:** `lib/policy-helpers.sh:144`, `lib/policy-helpers.sh:203` (originating `return 1`); `scripts/emit-policy.sh:144`, `scripts/emit-policy.sh:147` (unguarded call sites)

**Issue:**
The WR-04 fix added `secret_scan "$UPDATED" "settings.json" || return 1` inside
`merge_sandbox_block` (line 144) and `merge_deny_read_permissions` (line 203).
This is the first realistically-reachable non-zero return in those functions
(the only prior `return 1` was the effectively-unreachable jq-invalid-JSON
guard). In `scripts/emit-policy.sh` these functions are invoked with no
`|| exit 2` translation:

```bash
merge_sandbox_block "$TARGET/.claude/settings.json" "$SANDBOX_JSON"                # line 144
merge_deny_read_permissions "$TARGET/.claude/settings.json" "$COMBINED_DENY_READ"  # line 147
```

Under the script's `set -euo pipefail`, a function `return 1` aborts the script
with status **1**. Reproduced: planting `AKIA…` in an existing
`.claude/settings.json` and running `emit-policy --regime soc2` aborts the write
(settings.json correctly unchanged) but exits **1**, not **2**.

This violates the CLAUDE.md hard convention ("scripts/CLI/hooks `exit 2`, never
`exit 1`") for a hard-failure worker whose own header documents
"Exit codes: 0 = success; 2 = hard failure". It also contradicts the
`secret_scan` docstring contract (`lib/policy-helpers.sh:10`: "Caller must:
secret_scan … || exit 2"). The pre-existing audit summary gate
`[ "$WARN" -gt 0 ] && exit 1` is explicitly out of scope; this is a separate,
newly-reachable exit-1 path in a different script. A CI wrapper or caller that
distinguishes exit 2 (hard failure) from exit 1 will misclassify this abort.

**Fix:** Translate the merge functions' failure into exit 2 at the call sites
(matching every other hard-failure guard in this worker, e.g. lines 127, 130,
159, 162):

```bash
# scripts/emit-policy.sh, inside the MDM_ONLY != 1 block
merge_sandbox_block "$TARGET/.claude/settings.json" "$SANDBOX_JSON" || exit 2
merge_deny_read_permissions "$TARGET/.claude/settings.json" "$COMBINED_DENY_READ" || exit 2
```

The trailing `||` also disables `set -e` for that statement, so the chosen
exit 2 is what propagates.

---

_Reviewed: 2026-06-03T10:45:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
