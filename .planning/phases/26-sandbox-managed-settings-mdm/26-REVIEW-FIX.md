---
phase: 26-sandbox-managed-settings-mdm
fixed_at: 2026-06-03T00:00:00Z
review_path: .planning/phases/26-sandbox-managed-settings-mdm/26-REVIEW.md
iteration: 1
findings_in_scope: 6
fixed: 8
skipped: 2
status: all_fixed
---

# Phase 26: Code Review Fix Report

**Fixed at:** 2026-06-03
**Source review:** .planning/phases/26-sandbox-managed-settings-mdm/26-REVIEW.md
**Iteration:** 1

**Summary:**
- Findings in scope (critical_warning): 6 WARNINGs (0 blockers)
- Fixed: 6 WARNINGs + 2 INFO (IN-02, IN-03) = 8 total
- Skipped: 2 INFO (IN-01, IN-04) — out of scope / not trivially non-regressing

All 6 in-scope WARNING findings were fixed. Two trivial INFO items (IN-02, IN-03)
were additionally fixed since they were non-regressing. Test suite grew from
502 PASS / 0 FAIL to **507 PASS / 0 FAIL** (5 new tests added: POL-05b-abs,
POL-02-operator, POL-secret-merged, POL-04-macos-xmlmeta, POL-04-win-herestring).
`shellcheck -S error -e SC2164,SC2044,SC2034,SC2155` is clean on
`lib/policy-helpers.sh`, `scripts/emit-policy.sh`, `scripts/audit-setup.sh`.

## Fixed Issues

### WR-01: empty deny list converts to `[""]` not `[]`

**Files modified:** `lib/policy-helpers.sh`, `scripts/emit-policy.sh`
**Commit:** 7a0003f
**Applied fix:** Added `[.[] | select(length > 0)]` filter to both the
`read_entries_json` conversion in `merge_deny_read_permissions` and the
`DENY_ENTRIES_JSON` build in `emit-policy.sh`, mirroring the technique already used
at `emit-policy.sh:117`. Verified `printf '%s\n' "" | jq -R . | jq -sc '[.[] | select(length > 0)]'`
yields `[]`, not `[""]`. No stray empty `Read("")` rule is planted when the deny
list is empty.

### WR-02: POL-05b audit double-slash mismatch (false enforcement-gap error for absolute denyRead paths)

**Files modified:** `scripts/audit-setup.sh`, `tests/run.sh`
**Commit:** 24bfe66
**Applied fix:** Made the audit reuse `build_deny_read_entries` from
`lib/policy-helpers.sh` as the **single source of truth** for the
denyRead→`Read()` prefix convention, rather than re-implementing the prefix rules.
Sourced `policy-helpers.sh` in `audit-setup.sh` (safe — sourcing only defines
functions; `build_deny_read_entries` depends solely on jq, no mutate/snapshot
needed). In POL-05b the expected entry is now derived via
`build_deny_read_entries "$(jq -nc --arg p "$_dpath" '[$p]')"`, so an absolute path
`/abs` is correctly matched against the emitted `Read(//abs)` (double-slash).
**New test POL-05b-abs** proves an absolute denyRead path mirrored as `Read(//abs)`
passes audit (rc != 2, no "POL-02 enforcement gap" text). Existing POL-05b
(unmirrored path still fails) remains green.

### WR-03: operator-added sandbox denyRead paths never mirrored into permissions.deny

**Files modified:** `lib/policy-helpers.sh`, `tests/run.sh`
**Commit:** 539ebb4
**Applied fix:** In `merge_deny_read_permissions`, the conjure-generated
`deny_read_json` is now unioned with the existing `.sandbox.filesystem.denyRead`
already present in `settings.json` (read back from `$CURRENT`). Since emit calls
`merge_sandbox_block` FIRST (which writes operator-added paths into denyRead), by
the time `merge_deny_read_permissions` runs the file already contains
operator-added paths, so every denyRead path — conjure-emitted or operator-added —
is mirrored on every run. Closes the "false sense of security" gap.
**New test POL-02-operator**: emit, hand-add `~/.operator-secret` to
`sandbox.filesystem.denyRead`, re-emit, assert `Read(~/.operator-secret)` now
appears in `permissions.deny`. Idempotency (POL-01-idem) still holds.

### WR-04: merged pre-existing settings.json written back unscanned

**Files modified:** `lib/policy-helpers.sh`, `tests/run.sh`
**Commit:** 84561d3
**Applied fix:** Added `secret_scan "$UPDATED" "settings.json" || return 1` before
the `mutate_write` in BOTH `merge_sandbox_block` and `merge_deny_read_permissions`.
The merged result (operator's existing content + new block) is now scanned before
write; a credential already living in the operator's `settings.json` aborts emit
via the caller's `set -e`, restoring the "secret_scan before any write" invariant
for this write path.
**New test POL-secret-merged**: plant an AWS-key-shaped pattern (assembled at
runtime so no literal credential is committed) in the operator's pre-existing
settings.json, run emit, assert non-zero exit.

### WR-05: plist deny-entry / allowedDomains values not validated for XML metacharacters

**Files modified:** `lib/policy-helpers.sh`, `tests/run.sh`
**Commit:** f546b76
**Applied fix:** Extended the existing XML-metacharacter scan in `build_plist_xml`
(previously only on `deny_read_json` paths) to also scan `deny_entries_json`
(the `Read(...)` strings) and `sandbox_allowed_domains` before embedding them into
`<string>...</string>`. Any `&`, `<`, or `>` returns 2, consistent with the
existing path check — preventing silently-malformed plist XML on Linux (no plutil).
**New test POL-04-macos-xmlmeta** sources the helper and asserts `build_plist_xml`
returns 2 for both a deny entry containing `<` and an allowedDomains value
containing `&`.

### WR-06: ps1 here-string breakable by a denyRead path beginning with `'@`

**Files modified:** `lib/policy-helpers.sh`, `tests/run.sh`
**Commit:** f3022c5
**Applied fix:** In `build_ps1_script`, before embedding `$json_body` into the
PowerShell `@'...'@` here-string, validate that no line begins with `'@` (the
here-string terminator); return 2 if found. Defends against an
injection-into-generated-artifact vector. jq-pretty-printed valid input never
triggers this (nested values are indented), so normal emission is unaffected.
**New test POL-04-win-herestring** stubs `jq` within a subshell so `json_body`
starts with `'@`, proving the guard fires (rc 2). Normal POL-04-win emission
remains green.

### IN-02: build_managed_settings ignored its documented first argument

**Files modified:** `lib/policy-helpers.sh`
**Commit:** cc26593
**Applied fix:** Bound `$1` to `local regime="$1"` and added `: "$regime"` as a
documented no-op consume, keeping the documented `(regime, deny_entries_json,
sandbox_json)` contract in sync with the body. regime is intentionally NOT embedded
in the output (no `_conjure_regime` key by design — RESEARCH.md Q1); the binding
prevents a future arg-order change from silently shifting. Non-regressing (pure
read of a positional already passed by the sole caller).

### IN-03: VERIFY.txt step 5 instruction inverted relative to fresh output

**Files modified:** `scripts/emit-policy.sh`
**Commit:** cc26593
**Applied fix:** Reworded VERIFY.txt step 5 to clarify the `grep -c` "must return 0
AFTER you replace forceLoginOrgUUID with your org UUID — a freshly emitted file
intentionally returns 1." No test asserts on this wording, so non-regressing.

## Skipped Issues

### IN-01: REGIME_ALLOWED_DOMAINS is dead in all four regime files

**File:** `compliance/{hipaa,soc2,gdpr,pci}/policy.sh`, `scripts/emit-policy.sh`
**Reason:** skipped — not trivially non-regressing. The two options are (a) wire
`REGIME_ALLOWED_DOMAINS` into the network block (a behavioral/feature change that
could alter the deny-all-egress invariant) or (b) delete the variable from four
regime files (a judgment call about intended future use that warrants explicit
human sign-off). Out of scope for an automated, non-regressing fix.
**Original issue:** Every regime sets `REGIME_ALLOWED_DOMAINS=""` but
`emit-policy.sh` never reads it; `build_sandbox_block` hardcodes
`network.allowedDomains: []`. Dead code implying wiring that does not exist.

### IN-04: build_deny_read_entries `~/*` branch keeps tilde literally

**File:** `lib/policy-helpers.sh:89`
**Reason:** skipped — explicitly out of scope per the reviewer ("Out of scope to
fix here (external contract)"). Verifying Claude Code's `~` expansion in `Read()`
rules is an external-contract documentation task, not a code fix; normalizing `~/`
to `$HOME` at emit time would be a behavioral change requiring confirmation that
expansion is not guaranteed.
**Original issue:** Home-relative paths pass through as `Read(~/.aws)` with a
literal tilde; if Claude Code does not expand `~` in permission-rule strings the
protection silently fails. Needs a one-line confirmation in phase notes.

---

_Fixed: 2026-06-03_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
