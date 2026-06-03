---
phase: 27-schema-version-aware-audit
plan: "01"
subsystem: schema-audit
tags: [schema, skill-frontmatter, disableBypassPermissionsMode, posix-bash, schm-01, schm-02]
dependency_graph:
  requires:
    - lib/cc-schema.json (Wave 0 / 27-00)
    - tests/fixtures/_schema-audit-badfield/harness/ (Wave 0 / 27-00)
    - tests/fixtures/_schema-audit-disablebypass/harness/ (Wave 0 / 27-00)
  provides:
    - SCHM-01 frontmatter type validation in scripts/audit-setup.sh
    - SCHM-02 disableBypassPermissionsMode both-path check in scripts/audit-setup.sh
  affects:
    - scripts/audit-setup.sh (SCHM section + POL-05c replaced by SCHM-02)
tech_stack:
  added: []
  patterns:
    - awk two-line lookahead for YAML object-type detection (inline and block-style)
    - mktemp tempfile pattern for err()/warn() inside while-loop subshells (POSIX 3.2+)
    - printf|while IFS= read loop over multiple jq paths (no for/in — POSIX 3.2+)
    - jq runtime read of lib/cc-schema.json for known fields and expected types
key_files:
  created: []
  modified:
    - scripts/audit-setup.sh (SCHM-01 section inserted after skills loop; POL-05c replaced by SCHM-02)
decisions:
  - "SCHM-02 subsumed POL-05c: deliberate refactor — POL-05c only checked permissions. path; SCHM-02 checks BOTH paths (permissions. and top-level); exit 2 behavior preserved; Phase 26 regression test still green"
  - "awk two-line lookahead used for YAML object detection: detects inline {Bash: true} via /^{/ and block-style Bash: true (empty-value key + indented word: on next line) — both patterns required by T-27-01 threat mitigate"
  - "tempfile pattern for while-loop subshell err()/warn() propagation: same pattern as POL-05b in audit-setup.sh; POSIX-required since subshell FAIL/WARN counters don't propagate to main shell"
  - "jq read of cc-schema.json at runtime, not hardcoded field list: maintains schema-file-as-single-source-of-truth; SCHM-01 section skips gracefully if schema or jq absent"
metrics:
  duration: ~20 min
  completed: 2026-06-03
  tasks_completed: 2
  files_created: 0
  files_modified: 1
requirements:
  - SCHM-01
  - SCHM-02
---

# Phase 27 Plan 01: SCHM-01 SKILL.md Frontmatter Validation + SCHM-02 disableBypassPermissionsMode Both-Path Check

SKILL.md frontmatter type validation against lib/cc-schema.json (16 fields; object-typed array-or-space-string fields → fail exit 2) and boolean disableBypassPermissionsMode check at both permissions. and top-level paths → fail exit 2, replacing POL-05c.

## What Was Built

### Task 1 — SCHM-01 frontmatter type validation section (commit bcb46b6)

Inserted new SCHM-01 section in `scripts/audit-setup.sh` immediately after the existing skills loop and before the agents section. The section:

1. **Schema guard**: if `lib/cc-schema.json` is absent or `jq` is unavailable, emits `note "[schema] cc-schema.json not found — SCHM-01 skipped"` and skips the section (graceful degradation).

2. **Unknown field detection (warn)**: for each SKILL.md, extracts the frontmatter block via awk, reads known fields via `jq -r '.skill_frontmatter | keys[]'`, and for each top-level key not in the schema emits `warn "Skill '$name': unknown frontmatter field '$field' (not in CC schema — SCHM-01)"`. Uses tempfile pattern to propagate warn() calls from subshell.

3. **Object-type detection (fail)**: uses awk two-line lookahead:
   - Inline object: `fieldname: {` — detected via `/^\{/` on the value after splitting on `:`
   - Block-style mapping: top-level key with empty value followed by indented `  word:` line — detected via `prev_key` + `prev_val=""` + next line matching `^[[:space:]]+[a-zA-Z_-]+:`
   - For each `OBJECT_FIELD:fieldname`, jq looks up expected type; if `array-or-space-string` or `string`, emits `err "Skill '$name': field '$field' is an object (YAML mapping) — expected $expected (SCHM-01)"`. Uses tempfile pattern for err() propagation.

4. **Array/string forms NOT flagged**: YAML list (`- Bash`), inline list (`[Bash, Write]`), or space-separated string (`Bash Write`) are valid — the awk lookahead only fires on mapping-style syntax.

**Test results:**
- SCHM-01-badtype (block-style `disallowed-tools: { Bash: true, Write: true }`) → PASS (exit 2, output contains "disallowed-tools")
- SCHM-01-valid (array-typed allowed-tools) → PASS (no SCHM-01 fail)
- SCHM-01-unknown (unknown frontmatter field `totally_unknown_field`) → PASS (warns, exit 1 not 2)

### Task 2 — SCHM-02 both-path disableBypassPermissionsMode check, replaces POL-05c (commit 249758f)

Replaced the Phase 26 POL-05c block (single-path `permissions.disableBypassPermissionsMode` check) with SCHM-02 which covers both paths. The replacement is a deliberate refactor — not an accidental deletion.

SCHM-02 implementation:
- Gated on: `[ -f ".claude/settings.json" ] && command -v jq >/dev/null 2>&1`
- Uses `printf '%s\n' '.permissions.disableBypassPermissionsMode' '.disableBypassPermissionsMode' | while IFS= read -r _dbpm_path` (POSIX 3.2+ — no `for/in` over an array)
- For each path: `jq -r "${_dbpm_path} | type"` — if `boolean`, writes message to tempfile
- Reads tempfile back in main shell and calls `err()` for each line (FAIL counter increments correctly)
- Message format: `[schema] disableBypassPermissionsMode is boolean (got: $val at $path) — must be string "disable" (SCHM-02)`
- Cleanup: `rm -f "$_schm02_errs"` after reading

Verification:
- `grep -v '^#' scripts/audit-setup.sh | grep -c 'POL-05c'` == 0 (non-comment POL-05c references fully removed)
- Phase 26 regression: `CONJURE_HOME=$(pwd) bash scripts/audit-setup.sh tests/fixtures/_emit-policy-broken/harness` → exit 2, output contains "disableBypassPermissionsMode" and "disable"

**Test results:**
- SCHM-02-permissions (boolean at permissions. path) → PASS (exit 2)
- SCHM-02-toplevel (boolean at top-level path) → PASS (exit 2)
- POL-05c test (Phase 26 regression): PASS (SCHM-02 covers the same permissions. path)

### Overall suite

PASS: 516, FAIL: 5 (all remaining FAILs are graceful-red for Wave 2: SCHM-03-renamed, SCHM-03-unknown, SCHM-STALE, SCHM-05-json, SCHM-05-exit2 — out of scope for this plan).

## Deviations from Plan

None — plan executed exactly as written. The awk implementation follows Pattern 1 from RESEARCH verbatim. The POSIX printf|while pattern for SCHM-02 follows Pattern 6 as specified (not the research `for/in` form, per plan's explicit instruction).

## Known Stubs

None. All SCHM-01 and SCHM-02 checks are fully wired against real runtime schema data.

## Threat Flags

None. Changes are read-only jq + awk checks against user-supplied SKILL.md and settings.json; no new network endpoints, auth paths, or trust boundaries introduced.

## Self-Check: PASSED

- scripts/audit-setup.sh: FOUND
- Commits: bcb46b6 (SCHM-01), 249758f (SCHM-02)
- shellcheck -S error -e SC2164,SC2044,SC2034,SC2155: PASSED
- SCHM-01-badtype: PASS
- SCHM-01-valid: PASS
- SCHM-01-unknown: PASS
- SCHM-02-permissions: PASS
- SCHM-02-toplevel: PASS
- POL-05c Phase 26 regression: PASS (audit exits 2 on _emit-policy-broken fixture)
- grep -v '^#' scripts/audit-setup.sh | grep -c 'POL-05c' == 0: VERIFIED
