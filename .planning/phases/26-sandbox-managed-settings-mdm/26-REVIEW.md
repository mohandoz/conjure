---
phase: 26-sandbox-managed-settings-mdm
reviewed: 2026-06-03T10:04:23Z
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
  warning: 6
  info: 4
  total: 10
status: issues_found
---

# Phase 26: Code Review Report

**Reviewed:** 2026-06-03T10:04:23Z
**Depth:** standard
**Files Reviewed:** 8
**Status:** issues_found

## Summary

Phase 26 emits security policy (sandbox block, managed-settings.json, macOS
plist, Windows ps1, VERIFY.txt) for four compliance regimes. I verified the
security invariants by running `emit-policy.sh` twice against a scratch target
and inspecting the output, then re-running after hand-editing the target's
settings.json.

**The core security invariants hold under the current data set:**

- **Idempotency CONFIRMED** — a second `emit-policy --regime hipaa` produced a
  byte-identical `settings.json` (diff empty). Operator-added entries in both
  `permissions.deny` and `sandbox.filesystem.denyRead` survived a re-emit. The
  `array_merge` (`(a//[])+(b//[])|unique`) pattern is correctly used — never `.*`
  for arrays.
- **`disableBypassPermissionsMode` CONFIRMED** emitted as string `"disable"`
  (verified `[type,.] == ["string","disable"]`); `validate_managed_settings_json`
  rejects boolean, and the audit has an unconditional `err()` on boolean.
- **denyRead mirroring CONFIRMED** — every combined denyRead path appears as
  `Read(<path>)` in `permissions.deny`.
- **No unknown top-level keys** — `keys` on managed-settings.json returned exactly
  `[allowManagedPermissionRulesOnly, forceLoginOrgUUID, permissions, sandbox]`.
  No `_conjure_regime`/`_conjure_unreviewed`. `forceLoginOrgUUID` is the sole
  sentinel.
- **Validate-and-secret-scan-before-write** ordering is correct; snapshot precedes
  mutate; `shellcheck -S error` is clean on all three shell scripts.

However, the implementation carries **several latent correctness defects** that
are currently masked only because the hardcoded baseline/regime path data happens
to avoid the triggering shapes. These are real bugs waiting for the first absolute
path or empty deny list, plus a security-relevant mirroring gap for
operator-added sandbox paths. No BLOCKERs given current data; six WARNINGs.

## Warnings

### WR-01: denyRead→permissions.deny mirror produces a single empty `Read` rule (`[""]`) when the deny list is empty

**File:** `lib/policy-helpers.sh:156` (and `scripts/emit-policy.sh:151`)
**Issue:** `merge_deny_read_permissions` converts newline-separated entries to JSON
via `printf '%s\n' "$read_entries" | jq -R . | jq -sc '.'`. When `read_entries` is
empty (no deny paths), this yields `[""]` — an array containing one empty string —
not `[]`. That empty `""` is then merged into `.permissions.deny`, planting a
stray, meaningless deny rule. The identical pattern at emit-policy.sh:151 builds
`DENY_ENTRIES_JSON` for managed-settings.json and the plist. Verified:
`printf '%s\n' "" | jq -R . | jq -sc '.'` → `[""]`.

This is currently masked because `BASELINE_DENY_READ` is hardcoded non-empty, so
the combined list is never empty. It becomes a live bug the moment the baseline is
parameterized or a `--no-baseline` style flag is added.
**Fix:** Filter empties during the conversion, mirroring the technique already used
at emit-policy.sh:117:
```bash
read_entries_json="$(printf '%s\n' "$read_entries" \
  | jq -R . | jq -sc '[.[] | select(length > 0)]')"
```
Apply the same `select(length > 0)` guard at emit-policy.sh:151.

### WR-02: POL-05b audit double-slash mismatch — false enforcement-gap error for absolute denyRead paths

**File:** `scripts/audit-setup.sh:257` vs `lib/policy-helpers.sh:90`
**Issue:** `build_deny_read_entries` transforms an absolute path `/abs` into
`Read(//abs)` (double slash, per the documented convention). But the POL-05b audit
greps the raw path: `grep -qF "Read($_dpath)"` → `Read(/abs)` (single slash). These
never match. Verified: `printf 'Read(//var/secrets)' | grep -qF 'Read(/var/secrets)'`
fails. The same mismatch exists for `./x` paths (emit stores `Read(/x)`, audit greps
`Read(./x)`).

Currently latent — no baseline or regime path begins with `/` or `./` (all are
`~/`, `**/`, or bare). The first absolute path added to any `compliance/*/policy.sh`
will make `conjure audit` emit a spurious `err()` and **exit 2**, falsely failing
CI even though the mirror is correct.
**Fix:** Apply the same prefix transform in the audit before grepping, or compare
against the canonical `Read()` form. Minimal fix:
```bash
case "$_dpath" in
  /*)  _expect="Read(/$_dpath)" ;;
  ./*) _expect="Read(${_dpath#.})" ;;
  *)   _expect="Read($_dpath)" ;;
esac
if ! printf '%s\n' "$_perm_deny" | grep -qF "$_expect"; then ...
```

### WR-03: Operator-added sandbox denyRead paths are never mirrored into permissions.deny (silent enforcement gap)

**File:** `scripts/emit-policy.sh:147`
**Issue:** `merge_deny_read_permissions` mirrors only the conjure-generated
`COMBINED_DENY_READ` set. It does **not** read back the existing (possibly
operator-extended) `.sandbox.filesystem.denyRead` from settings.json. Verified: an
operator-added `sandbox.filesystem.denyRead` entry survives re-emit (good) but is
**not** mirrored into `permissions.deny`, so `conjure audit` immediately flags it as
a "POL-02 enforcement gap" — and a re-emit never closes it. Per the phase threat
model, an unmirrored denyRead is "a false sense of security" because Read/Grep/Glob
bypass the OS sandbox. A natural operator action (hand-adding a denyRead path)
produces exactly that gap, and the tool offers no remediation path.
**Fix:** In `merge_deny_read_permissions`, union the entries derived from
`COMBINED_DENY_READ` with entries derived from the *existing*
`.sandbox.filesystem.denyRead` already present in `settings_file`, so every sandbox
denyRead path — conjure-emitted or operator-added — is mirrored on every run.

### WR-04: `merge_sandbox_block` writes operator's pre-existing settings.json back unscanned

**File:** `lib/policy-helpers.sh:107` / `scripts/emit-policy.sh:130`
**Issue:** `secret_scan` runs against the generated `SANDBOX_JSON` and `MANAGED_JSON`
(hardcoded content — low value), but `merge_sandbox_block`/`merge_deny_read_permissions`
read the operator's existing `settings.json` (`CURRENT="$(cat "$settings_file")"`)
and write the merged result via `mutate_write` **without** scanning the merged
output. If the operator's existing settings.json already contains a credential, the
emit pipeline re-writes it without ever invoking the credential gate, defeating the
"secret_scan before any write" invariant for that write path.
**Fix:** Run `secret_scan "$UPDATED" "settings.json"` before the `mutate_write` in
both `merge_sandbox_block` and `merge_deny_read_permissions`; return 1 on hit so the
caller's `set -e` aborts before the write.

### WR-05: plist deny-entry / allowedDomains values not validated for XML metacharacters

**File:** `lib/policy-helpers.sh:258-270, 282, 312`
**Issue:** `build_plist_xml` validates only the raw `deny_read_json` paths for
`& < >` (lines 258-270). The `deny_entries_json` (`Read(...)` strings) and
`network.allowedDomains` values are embedded into `<string>...</string>` (lines 282,
312) without the same check. Today the deny entries derive from the already-checked
denyRead paths and allowedDomains is always `[]`, so it is masked. But once
`allowedDomains` is wired up (see IN-01) or any independent deny entry is introduced,
an `&`/`<`/`>` in those values yields malformed plist XML. `plutil -lint` would catch
it on macOS (return 2), but on Linux (no plutil) the broken plist is written silently.
**Fix:** Extend the metacharacter scan to cover `deny_entries_json` and
`sandbox_allowed_domains` before embedding, returning 2 on any hit (consistent with
the existing path check).

### WR-06: ps1 here-string can be broken by a denyRead path containing `'@` at line start

**File:** `lib/policy-helpers.sh:454-459`
**Issue:** `build_ps1_script` embeds the pretty-printed managed JSON inside a
PowerShell literal here-string `@'...'@`. A here-string terminates at a line whose
first characters are `'@`. jq-pretty-printed JSON indents values, so a normal value
is safe, but the terminator detection in PowerShell is column-sensitive and a
crafted/odd deny path (e.g. one beginning with `'@`) embedded as an array element
could prematurely close the here-string and corrupt the emitted script — an
injection-into-generated-artifact vector. Controlled input today (paths are curated),
hence WARNING not BLOCKER.
**Fix:** Validate that no line of `$json_body` begins with `'@` before embedding, or
emit the JSON via a base64 blob decoded in the ps1, removing the here-string
terminator hazard entirely.

## Info

### IN-01: `REGIME_ALLOWED_DOMAINS` is dead in all four regime files

**File:** `compliance/{hipaa,soc2,gdpr,pci}/policy.sh:27/19/23/25`, `scripts/emit-policy.sh`
**Issue:** Every regime sets `REGIME_ALLOWED_DOMAINS=""`, but `emit-policy.sh` never
reads it; `build_sandbox_block` hardcodes `network.allowedDomains: []`. Confirmed via
grep: the variable is referenced nowhere outside `compliance/`. The deny-all-egress
behavior is correct, but the per-regime variable is dead code that implies a wiring
that does not exist — a future maintainer may set it expecting it to take effect.
**Fix:** Either wire `REGIME_ALLOWED_DOMAINS` into the sandbox/network block (with
the empty-list = deny-all semantics preserved) or delete the variable and document
that egress is unconditionally deny-all.

### IN-02: `build_managed_settings` ignores its documented first argument

**File:** `lib/policy-helpers.sh:220-223`
**Issue:** The header documents `build_managed_settings(regime, deny_entries_json,
sandbox_json)` and the caller passes `"$REGIME"` as `$1`, but the function body reads
only `$2`/`$3` — `regime` (`$1`) is unused. Harmless today, but a signature/body
mismatch invites a future off-by-one argument bug.
**Fix:** Drop the `regime` parameter from the signature/docs, or consume it (e.g.
embed a regime marker comment). Keep the documented contract and the body in sync.

### IN-03: VERIFY.txt step 5 instruction is inverted relative to fresh output

**File:** `scripts/emit-policy.sh:199-200`
**Issue:** VERIFY.txt instructs `grep -c REPLACE_WITH_ORG_UUID ... # must return 0`,
but a freshly emitted managed-settings.json **always** contains
`REPLACE_WITH_ORG_UUID` (it is the unreviewed sentinel). The check only passes after
the operator manually replaces it. The intent is correct (it is a pre-deploy gate),
but as written it reads like the emit is broken. Add one clause so operators are not
confused.
**Fix:** Reword: `# must return 0 AFTER you replace forceLoginOrgUUID with your org
UUID — a freshly emitted file intentionally returns 1`.

### IN-04: `build_deny_read_entries` `~/*` branch keeps tilde literally — verify Claude Code expands it

**File:** `lib/policy-helpers.sh:89`
**Issue:** Home-relative paths are passed through as `Read(~/.aws)` with a literal
tilde. This is consistent with the documented convention, but tilde expansion inside
a permission-rule string is a Claude-Code-side behavior; if it does not expand `~`,
`Read(~/.aws)` would not match the actual home path and the protection silently fails.
Out of scope to fix here (external contract), but worth a one-line confirmation in the
phase notes that Claude Code expands `~` in `Read()` rules.
**Fix:** Document the verified Claude Code tilde-expansion behavior, or normalize
`~/` to `$HOME` at emit time if expansion is not guaranteed.

---

_Reviewed: 2026-06-03T10:04:23Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
