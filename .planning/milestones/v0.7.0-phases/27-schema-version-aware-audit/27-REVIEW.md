---
phase: 27-schema-version-aware-audit
reviewed: 2026-06-03T00:00:00Z
depth: standard
iteration: 2
files_reviewed: 3
files_reviewed_list:
  - scripts/audit-setup.sh
  - scripts/check.sh
  - cli/conjure
findings:
  critical: 0
  warning: 0
  info: 3
  total: 3
status: clean
---

# Phase 27: Code Review Report (Re-review, iteration 2)

**Reviewed:** 2026-06-03
**Depth:** standard
**Files Reviewed:** 3
**Status:** clean

## Summary

Re-review after the fixer resolved all 5 WARNINGs from iteration 1 across three commits
(55b37a3, 8a3e508 — plus the iteration-1 baseline). Each fix was re-derived from source and
verified empirically. **No new Critical or Warning issues were introduced by the fix commits.**

Test + lint gates run by the reviewer:

- `bash tests/run.sh` → **523 PASS / 0 FAIL**, including the two new regression tests
  `check --porcelain --schema keeps stdout machine-clean (WR-04)` and
  `check --schema WARNs on key newer than detected CC version, never fails (WR-05)`.
- `shellcheck -S error -e SC2164,SC2044,SC2034,SC2155 scripts/check.sh scripts/audit-setup.sh cli/conjure`
  → **exit 0, clean**.

### Fix verification (each confirmed, no regression)

- **WR-02 / WR-03 (EXIT-trap clobber → tempfile leak):** Both scripts now register exactly one
  combined cleanup function on EXIT — `_check_cleanup` (check.sh:33, rm -f MANIFEST + _SCHM03_TMP
  + _SCHM04_NEWER) and `_audit_cleanup` (audit-setup.sh:29, rm -f CHECKS_JSONL + COST_TMP). No
  later `trap ... EXIT` re-registration exists (grep confirms a single `trap` per script). Measured
  `$TMPDIR` file delta before/after a run: **leak=0 in every mode** — check.sh normal / --schema /
  --porcelain --schema; audit normal / --cost / --json / --json --cost. The combined traps also
  drop nothing the old per-block traps used to clean (the explicit inline `rm -f` at check.sh:209
  and :279 remain as belt-and-suspenders). `set -u` safety verified: with settings.json absent
  (SCHM-03/04 blocks skipped, those vars never set) and with --cost omitted (COST_TMP unset), the
  `${VAR:-}` defaults prevent any "unbound variable" abort — confirmed no unbound errors on EXIT.

- **WR-04 (porcelain + schema stdout corruption):** `_schm04_out()` (check.sh:222) routes every
  SCHM-04 report line to stderr when `PORCELAIN=1`, stdout otherwise. Empirically, `check
  --porcelain --schema` stdout contains ONLY `M/R/A <path>` lines (grep for any non-`^[MRA] ` line
  returns nothing). All human report text (header rule, per-key table, WARN lines) lands on stderr.

- **WR-01 (boolean message blank value):** SCHM-02 now extracts the value via `jq ... | tostring`
  (audit-setup.sh:346). For `disableBypassPermissionsMode: false` the message reads
  `(got: false at .disableBypassPermissionsMode)` and for `true` reads `(got: true ...)`; both
  paths still `err` → exit 2. Dual-path coverage (top-level + `permissions.*`) preserved.

- **WR-05 (NEW LOGIC — newer-than-CC key WARN):** Scrutinized hardest. All sub-claims hold:
  - **(a) direction correct:** with a fake `claude` reporting v2.1.130, only `workflowKeywordTriggerEnabled`
    (introduced 2.1.157, newer) warned; `skillOverrides` (2.1.129), `disableRemoteControl` (2.1.128),
    and `maxSkillDescriptionChars` (2.1.105) — all older — did NOT warn.
  - **(b) "all"/"unknown"/null excluded:** `model` (introduced "all") and an unrecognized
    `unknownKey` (resolves to "unknown") are filtered by the `grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'`
    semver gate before comparison — no false warn.
  - **(c) claude absent:** with `claude` off PATH, `_CC_PRESENT=0` and the comparison block is
    skipped entirely — zero newer-key warns (only the existing "claude not found" baseline WARN).
  - **(d) numeric (not lexical) semver:** the `sort -V` comparator returns 2.1.10 as greater than
    2.1.9 (correct), where a lexical `sort` would invert it. Directly verified both orderings.
  - **(e) no exit-code escalation:** a harness with a newer key + detected claude exits 1 (drift),
    never 2. The WARN is advisory-only and does not touch `SCHEMA_FAIL`, honoring the SCHM-04
    non-goal. The collect-to-tempfile-then-emit pattern (`_SCHM04_NEWER`) correctly hoists the
    findings out of the jq-pipe subshell into the main shell.

### Core invariants re-confirmed

- `--json` stdout is pure, jq-parseable JSON; human text on stderr; status/exit mirror
  (pass→0, warn→1, fail→2).
- SCHM-02 dual-path both fail exit 2; SCHM-03 exit 2 overrides drift exit 1 (renamed-event
  fixture → exit 2); SCHM-01 type detection canonical case passes (`SCHM-01-badtype` test green).
- Zero egress in the phase-27 changed logic (the only `git ls-remote` is pre-existing overlay
  drift, untouched this phase); POSIX bash 3.2+ (no `declare -A`/`mapfile`/`local -n` — the sole
  grep hit is a comment); shellcheck clean.

## Narrative Findings (AI reviewer)

No Critical or Warning findings. The three Info items below carried over from iteration 1 are
**unrelated to the fix commits** (none was in scope for the 5 WARNINGs) and remain advisory. IN-01
was addressed by the fixer (dead `_schm01_warn_jchecks` tempfile removed); it is noted closed.

### Info

#### IN-01: (CLOSED) Dead tempfile `_schm01_warn_jchecks` removed

**File:** `scripts/audit-setup.sh:128-144`
**Status:** Resolved in commit 8a3e508. The unused `_schm01_warn_jchecks` mktemp/write/rm were
deleted; the SCHM-01 unknown-field JSON record now sources its message from `_schm01_warn_errs`
(suffix-inclusive). Verified no tempfile leak and `--json` stdout stays valid JSON. No regression.

#### IN-02: SCHM-04 `claude --version` parse assumes version is field 1

**File:** `scripts/check.sh:229`
**Issue:** `claude --version | awk '{print $1}'` works for current output `2.1.161 (Claude Code)`.
If a future CC printed `claude 2.1.x` (command name first), `$1` would be `claude`, fail the
`^[0-9]+\.[0-9]+\.[0-9]+$` regex, and fall back to the schema baseline with a WARN — safe
(never fails) but silently disables real detection. Unchanged from iteration 1; not a fix-commit
regression.
**Fix (optional):** `_CC_VER="$(claude --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"`

#### IN-03: BSD `date -j -f "%Y-%m-%d"` uses current time-of-day at the 90-day boundary

**File:** `scripts/check.sh:284` and `scripts/audit-setup.sh:411`
**Issue:** On macOS, `date -j -f "%Y-%m-%d"` with no time component substitutes the current
time-of-day, so a schema generated exactly 90 days ago may flip between 89/90 days by run time.
Strict `> 90` advisory WARN → ≤1-day cosmetic fuzz on a non-blocking warning. Unchanged from
iteration 1.
**Fix (optional):** Anchor to midnight in the BSD branch:
`date -j -f "%Y-%m-%d %H:%M:%S" "$DATE 00:00:00" "+%s"`.

---

_Reviewed: 2026-06-03_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard · iteration 2_
