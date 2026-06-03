---
phase: 27-schema-version-aware-audit
reviewed: 2026-06-03T00:00:00Z
depth: standard
files_reviewed: 4
files_reviewed_list:
  - lib/cc-schema.json
  - scripts/audit-setup.sh
  - scripts/check.sh
  - cli/conjure
findings:
  critical: 0
  warning: 5
  info: 3
  total: 8
status: issues_found
---

# Phase 27: Code Review Report

**Reviewed:** 2026-06-03
**Depth:** standard
**Files Reviewed:** 4
**Status:** issues_found

## Summary

Phase 27 adds schema-version-aware audit/check on top of a bundled `lib/cc-schema.json`
snapshot (30 hook events, 16 frontmatter fields). The five phase invariants (SCHM-01..05)
were exercised empirically against fixtures:

- **SCHM-01** (frontmatter type detection): VERIFIED correct. Inline object `{...}`, block
  mapping (empty key + indented `word:`), array `[...]`, and space-string forms are all
  classified correctly. Comments (`#`), mid-value braces, and hyphenated known fields
  (`disable-model-invocation`, `argument-hint`) do not produce false positives.
- **SCHM-02** (disableBypassPermissionsMode boolean): VERIFIED both `.disableBypassPermissionsMode`
  and `.permissions.disableBypassPermissionsMode` fail with exit 2. POL-05c behavior is preserved
  (the permissions.* path still fails). **One message-content bug** (boolean `false` prints blank
  value) — see WR-01.
- **SCHM-03** (renamed/unknown hook events): VERIFIED. SessionStop→SessionEnd flagged, unknown
  events flagged, findings routed to stderr (porcelain stdout stays clean), exit 2 correctly
  overrides drift exit 1. Events read from schema, not hardcoded.
- **SCHM-04** (per-key CC version report): version source is `claude --version` (not
  `.conjure-version`), claude-absent path WARNs and continues, cross-platform date math does not
  hang. **The invariant's "compares against introduced_version" is only a report, not a flag**
  — see WR-02.
- **SCHM-05** (`--json` single-object stdout): VERIFIED pure JSON to stdout, human text to stderr,
  exit/status mirroring (pass→0, warn→1, fail→2). Preflight stdout correctly redirected to stderr.

`shellcheck -S error -e SC2164,SC2044,SC2034,SC2155` passes clean on all three scripts. The
schema JSON is well-formed (30 events, 16 fields, no secrets). cc-schema.json `generated` date
drives the staleness advisory correctly.

The headline defects are two **trap-overwrite tempfile leaks** newly introduced this phase (the
new EXIT traps silently clobber pre-existing ones, leaking `$MANIFEST` and `$CHECKS_JSONL`), a
**stdout-corruption bug** when `--porcelain --schema` are combined, and the SCHM-02 blank-value
message. No false-negative was found that lets an invalid harness silently pass; no exit code
deviates from contract.

## Warnings

### WR-01: SCHM-02 message prints blank value for boolean `false`

**File:** `scripts/audit-setup.sh:335,337`
**Issue:** The value extraction uses `jq -r "${_dbpm_path} // empty"`. jq treats `false` as falsy,
so for `disableBypassPermissionsMode: false` the `//` operator yields the empty string. The check
still correctly fails (type detection at line 333 uses `| type` → `"boolean"`, so the security
control fires and exit 2 is returned), but the human/JSON message reads
`...(got:  at .permissions.disableBypassPermissionsMode)...` with no value. The phase invariant
(SCHM-02) explicitly requires "the correct string value in the message." Verified empirically:
`false` → blank, `true` → `true`.
**Fix:** Use a jq expression that does not collapse `false`:
```bash
_dbpm_val="$(jq -r "${_dbpm_path} | tostring" .claude/settings.json 2>/dev/null || echo '')"
```
(`tostring` on a boolean yields `"true"`/`"false"`; guard against `null` if the key is absent —
but this branch only runs when type=="boolean", so the key is present.)

### WR-02: New EXIT trap in check.sh clobbers MANIFEST cleanup trap (tempfile leak)

**File:** `scripts/check.sh:168` (overwrites `:29`)
**Issue:** Line 29 sets `trap 'rm -f "$MANIFEST"' EXIT`. The SCHM-03 block (new this phase) sets
`trap 'rm -f "${_SCHM03_TMP:-}"' EXIT` at line 168, which **replaces** the single EXIT trap slot.
`_SCHM03_TMP` is explicitly removed at line 202, but `$MANIFEST` now has no cleanup — it leaks to
`$TMPDIR` on every `check` run that has a settings.json (i.e. the common case). bash has only one
EXIT trap; a second `trap ... EXIT` overrides, it does not append.
**Fix:** Combine cleanup into a single trap, or use a cleanup function:
```bash
# near line 29
_check_cleanup() { rm -f "${MANIFEST:-}" "${_SCHM03_TMP:-}"; }
trap _check_cleanup EXIT
# remove the line 168 trap entirely; line 202 explicit rm can stay or go
```

### WR-03: New CHECKS_JSONL trap in audit-setup.sh clobbered by COST_TMP trap (tempfile leak)

**File:** `scripts/audit-setup.sh:455` (overwrites `:25`)
**Issue:** Line 25 (new this phase) sets `trap 'rm -f "${CHECKS_JSONL:-}"' EXIT`. The pre-existing
`--cost` block at line 455 sets `trap '_audit_cleanup' EXIT` where `_audit_cleanup` only removes
`$COST_TMP`. When `--cost` is supplied, the CHECKS_JSONL trap is overwritten and the tempfile
leaks on exit. CHECKS_JSONL still exists during JSON emission (line 543) because line 455 runs
before emission, so output is not corrupted — but the file is orphaned. This regression is the
mirror of WR-02 and only surfaces with `--cost`.
**Fix:** Make `_audit_cleanup` (or a single combined trap) remove both files:
```bash
_audit_cleanup() { rm -f "${COST_TMP:-}" "${CHECKS_JSONL:-}"; }
```
Set this once near the top instead of re-registering inside the `--cost` block.

### WR-04: `check --porcelain --schema` writes SCHM-04 report to stdout, corrupting machine output

**File:** `scripts/check.sh:227-238` (and the staleness `printf` at `:249`)
**Issue:** The SCHM-04 "Schema Version Report" is emitted with bare `printf` to stdout and is NOT
gated on `PORCELAIN`. Both flags are accepted simultaneously by `cmd_check` (cli/conjure:174-180).
Running `check --porcelain --schema` interleaves the human-readable report with the
`M/R/A <path>` porcelain lines on stdout, corrupting any machine consumer. Verified empirically:
the report block appears directly after `M .claude/settings.json` on stdout.
The internal `--pr` flow (cli/conjure:281) calls `check --porcelain` without `--schema`, so it is
not affected today, but the corruption is reachable by any user combining the two documented flags.
**Fix:** Route the SCHM-04 report to stderr (consistent with SCHM-03 findings), or suppress it under
porcelain:
```bash
if [ "$CONJURE_SCHEMA" = "1" ] && [ "$PORCELAIN" != "1" ] && ...; then
```
(SCHM-03 already writes to `>&2`; mirroring that for the SCHM-04 report keeps stdout machine-clean.)

### WR-05: SCHM-04 reports introduced_version but never compares/flags against detected CC version

**File:** `scripts/check.sh:205-254`
**Issue:** The phase invariant for SCHM-04 states it "compares detected `claude --version` against
each key's `introduced_version`." The implementation only *prints* `key → introduced: <version>`
side-by-side with the detected version; there is no comparison that flags a key whose
`introduced_version` is newer than the detected CC version (i.e. a key the user's installed CC does
not yet support). A harness using `skillOverrides` (introduced 2.1.129) on a CC 2.1.105 install
would not be surfaced. This is a false-negative against the stated invariant — informational keys
that the running CC cannot honor pass silently. (No data-loss/security impact, hence WARNING not
BLOCKER.)
**Fix:** If forward-compat flagging is intended, add a numeric version compare (sort -V or a
3-field awk comparator) and emit a WARN when `introduced_version` > detected `_CC_VER` and
`introduced_version != "all"`. If report-only was the actual intent, update the invariant/spec to
say "report" rather than "compare" so downstream reviewers are not misled.

## Info

### IN-01: Dead tempfile `_schm01_warn_jchecks` (created, written, never read)

**File:** `scripts/audit-setup.sh:123,128,137`
**Issue:** `_schm01_warn_jchecks` is created (123), written (128), and removed (137) but never read.
The `json_check` call at line 134 uses `$_msg` sourced from `_schm01_warn_errs` instead. As a side
effect, the JSON-mode message carries the human suffix `— SCHM-01` (from the errs file) rather than
the cleaner message staged in the unused jchecks file — a minor cosmetic inconsistency in the
emitted JSON.
**Fix:** Delete the `_schm01_warn_jchecks` mktemp, its write at line 128, and its name from the
line 137 `rm -f`. If the suffix-free message was intended for JSON, read from a parallel array
instead.

### IN-02: SCHM-04 `claude --version` parse depends on version being field 1

**File:** `scripts/check.sh:214`
**Issue:** `claude --version | awk '{print $1}'` works for the current output `2.1.161 (Claude Code)`
(verified → `2.1.161`). If a future CC prints `claude 2.1.x` (command name first), `$1` becomes
`claude`, fails the `^[0-9]+\.[0-9]+\.[0-9]+$` regex, and the code falls back to the schema baseline
with a WARN. This is safe (never fails the build) but silently disables real version detection.
**Fix:** Extract the first token matching a semver pattern rather than assuming position:
```bash
_CC_VER="$(claude --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
```

### IN-03: BSD `date -j -f "%Y-%m-%d"` uses current time-of-day, fuzzing the 90-day boundary

**File:** `scripts/audit-setup.sh:400-404` and `scripts/check.sh:243-247`
**Issue:** On macOS, `date -j -f "%Y-%m-%d" "$DATE" "+%s"` with no time component substitutes the
*current* time-of-day. Day arithmetic is therefore off by up to <1 day at the exact 90-day boundary,
so a schema generated exactly 90 days ago may flip between 89 and 90 days depending on run time. The
staleness gate is a strict `> 90` advisory WARN, so the impact is one-day cosmetic fuzz on a
non-blocking warning — not a correctness defect.
**Fix (optional):** Anchor to midnight: `date -j -f "%Y-%m-%d %H:%M:%S" "$DATE 00:00:00" "+%s"` for
the BSD branch, keeping the GNU `date -d` branch as-is.

---

_Reviewed: 2026-06-03_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
