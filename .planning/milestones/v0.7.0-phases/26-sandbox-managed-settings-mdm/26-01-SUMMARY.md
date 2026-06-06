---
phase: 26-sandbox-managed-settings-mdm
plan: "01"
subsystem: policy-emission
tags: [wave-1, sandbox, permissions-deny, idempotent-merge, pol-01, pol-02, posix-bash]
dependency_graph:
  requires:
    - "26-00"
  provides:
    - lib/policy-helpers.sh (sandbox jq builders + validators + idempotent merge)
    - scripts/emit-policy.sh (policy emit worker — sandbox + permissions.deny)
    - compliance/hipaa/policy.sh (HIPAA PHI delta paths)
    - compliance/soc2/policy.sh (SOC 2 audit-log delta paths)
    - compliance/gdpr/policy.sh (GDPR PII delta paths)
    - compliance/pci/policy.sh (PCI DSS cardholder delta paths)
    - cli/conjure cmd_emit_policy + emit-policy) dispatch
  affects:
    - tests/run.sh (POL-01, POL-01-idem, POL-02, POL-dryrun now PASS; FAIL 12→8)
tech_stack:
  added: []
  patterns:
    - array_merge jq def for idempotent sandbox block merge (RESEARCH.md Pattern 1)
    - double-slash absolute path rule in build_deny_read_entries (RESEARCH.md Pattern 2)
    - validate-before-write discipline (exit 2 if jq type check fails)
    - snapshot-before-mutate via snapshot_create before first mutate_write
    - TARGET derivation from parent(OUTPUT_DIR) when --output given without --path
key_files:
  created:
    - lib/policy-helpers.sh
    - scripts/emit-policy.sh
    - compliance/hipaa/policy.sh
    - compliance/soc2/policy.sh
    - compliance/gdpr/policy.sh
    - compliance/pci/policy.sh
  modified:
    - cli/conjure (cmd_emit_policy + usage line + dispatch entry)
decisions:
  - "TARGET derived from dirname(OUTPUT_DIR) when --output passed without --path — required for POL-01 test harness compatibility"
  - "merge_deny_read_permissions added as 6th function to policy-helpers.sh to cleanly separate the permissions.deny merge from the sandbox merge"
  - "All 4 compliance/*/policy.sh files marked chmod +x to satisfy the project-wide executability test loop (find scripts compliance -name *.sh)"
  - "Shared baseline deny paths defined inline in emit-policy.sh (not a separate file) per PLAN action spec"
metrics:
  duration: "~24 min"
  tasks_completed: 2
  files_created: 6
  files_modified: 1
  completed: "2026-06-03T09:37:53Z"
---

# Phase 26 Plan 01: Wave 1 — Core Library + Emit Worker + CLI Dispatch Summary

Wave 1 delivers the foundational policy emission infrastructure: shared jq builders and validators in `lib/policy-helpers.sh`, per-regime deny-path data in 4 `compliance/*/policy.sh` files, the `scripts/emit-policy.sh` emit worker, and CLI dispatch in `cli/conjure`. Tests POL-01, POL-01-idem, POL-02, and POL-dryrun are now GREEN.

## What Was Built

**Task 1: lib/policy-helpers.sh and compliance regime data files**

`lib/policy-helpers.sh` implements 6 functions:

- `secret_scan(content, label)`: credential pattern scan (sk-ant-, sk-, AKIA, api_key/secret_key/private_key/access_token/auth_token field patterns) using POSIX ERE via `grep -qiE`.
- `validate_sandbox_json(content)`: 3-field jq type-check accumulator (enabled boolean, filesystem.denyRead array, network.allowedDomains array); returns 1 if any check fails.
- `build_sandbox_block(deny_read_json, deny_write_json)`: constructs sandbox{} JSON with `enabled:true, failIfUnavailable:true, allowUnsandboxedCommands:false` from regime arrays.
- `build_deny_read_entries(deny_read_json)`: converts denyRead JSON array to `Read(<path>)` lines using the double-slash rule for absolute paths (RESEARCH.md Pattern 2).
- `merge_sandbox_block(settings_file, sandbox_json)`: deep-merges sandbox block into settings.json using `def array_merge(a; b): (a // []) + (b // []) | unique;` for all 6 array fields; calls `mutate_write`.
- `merge_deny_read_permissions(settings_file, deny_read_json)`: builds Read() entries then merges into `.permissions.deny` using the same `array_merge` def; calls `mutate_write`.

The 4 compliance/*/policy.sh files carry per-regime delta paths only (newline-separated strings) for sourcing by emit-policy.sh. All files are POSIX 3.2+ compatible and shellcheck-clean.

**Task 2: scripts/emit-policy.sh and CLI dispatch**

`scripts/emit-policy.sh` follows the emit-plugin.sh structure exactly:
- shebang + `set -euo pipefail` + CONJURE_HOME derivation
- Sources lib/log.sh, lib/snapshot.sh, lib/mutate.sh, lib/policy-helpers.sh
- Env defaults + arg parsing (--regime, --output, --path, --managed-only, --mdm-only, --dry-run)
- Regime enum validation before any `source compliance/$REGIME/policy.sh` call (T-26-03)
- TARGET derivation: explicit via `--path` > `$CONJURE_POLICY_TARGET` env > `dirname(OUTPUT_DIR)` > `$(pwd)`
- Baseline + regime delta paths combined, deduped with `sort -u`, converted to JSON arrays
- `validate_sandbox_json` + `secret_scan` before any `mutate_write` (validate-before-write discipline)
- `snapshot_create` before first mutate (backup-before-mutate invariant)
- `merge_sandbox_block` + `merge_deny_read_permissions` for settings.json (idempotent)
- Output dir creation, VERIFY.txt emission, Wave 2 stubs (managed-settings.json and MDM artifacts silently skipped)
- `mutate_summary` + `exit 0` on success

`cli/conjure` additions:
- `cmd_emit_policy`: thin-wrapper function parsing same flags, passing env vars to `emit-policy.sh`
- `emit-policy)` dispatch entry before `version|-v|--version`
- Usage line added to `usage()` function

## Verification Results

```
bash tests/run.sh 2>&1 | grep "POL-01\|POL-02\|POL-dryrun"
  ✓ emit-policy merges sandbox block into settings.json (POL-01)
  ✓ emit-policy is idempotent: re-run produces identical settings.json (POL-01-idem)
  ✓ emit-policy mirrors denyRead paths into permissions.deny (POL-02)
  ✓ emit-policy --dry-run prints mutations but writes no files (POL-dryrun)

PASS: 494    FAIL: 8
```

- 9 new PASSes (4 executability checks + 5 POL tests: POL-01, POL-01-idem, POL-02, POL-dryrun, plus pre-existing now passing tests)
- 8 remaining FAILs are exactly Wave 2/3 stubs: POL-03, POL-03-type, POL-04-macos, POL-04-win, POL-05a, POL-05b, POL-05c, POL-05-advisory
- Pre-existing 485 tests still pass (no regression)
- shellcheck clean: lib/policy-helpers.sh, scripts/emit-policy.sh, all 4 compliance/*/policy.sh

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Missing executable bits on new .sh files**
- **Found during:** First test run after Task 2 — 5 "NOT executable" failures
- **Issue:** The project's smoke test loop (`find scripts cli migrations profiles compliance templates/hooks -name '*.sh'`) checks that every `.sh` file is executable. New `scripts/emit-policy.sh` and all 4 `compliance/*/policy.sh` files lacked the executable bit.
- **Fix:** `chmod +x` on all 5 new .sh files to match project convention.
- **Files modified:** scripts/emit-policy.sh, compliance/{hipaa,soc2,gdpr,pci}/policy.sh
- **Commit:** 9c62923 (included with Task 2 commit)

**2. [Rule 2 - Missing] TARGET derivation from OUTPUT_DIR parent**
- **Found during:** Analysis of POL-01 test before implementation
- **Issue:** The POL-01 test invokes emit-policy.sh with `--output $P26_POL01_DIR/conjure-policy` but no `--path` flag, then checks `$P26_POL01_DIR/.claude/settings.json`. With a plain `TARGET=$(pwd)` default, emit-policy would write to $CONJURE_HOME instead of the fixture dir.
- **Fix:** Added TARGET derivation: when `--output` is given and TARGET is not set explicitly, derive `TARGET=$(dirname "$OUTPUT_DIR")`. This is the only semantically consistent behavior (output dir is always `$TARGET/conjure-policy`).
- **Files modified:** scripts/emit-policy.sh

**3. [Rule 2 - Missing] merge_deny_read_permissions as separate helper function**
- **Found during:** Implementation of merge_sandbox_block
- **Issue:** The PLAN action note says "merge_sandbox_block can accept a third argument ... or [handle merge in a] separate jq step". The separate function approach is cleaner and shellcheck-passes more easily.
- **Fix:** Added `merge_deny_read_permissions(settings_file, deny_read_json)` as a 6th function in policy-helpers.sh to cleanly separate sandbox merge from permissions.deny merge.
- **Files modified:** lib/policy-helpers.sh

## Known Stubs

- `scripts/emit-policy.sh` lines that print `(managed-settings.json: implemented in Wave 2)` to stderr — Wave 2 (Plan 02) implements the full managed-settings.json and MDM artifact emission. These stubs exit 0 and are silent in dry-run mode.

## Threat Flags

None — no new network endpoints, auth paths, or schema changes at trust boundaries beyond those documented in the plan's threat model. All mitigations from the threat register (T-26-01 through T-26-05) are implemented:
- T-26-01: array_merge def in merge_sandbox_block and merge_deny_read_permissions
- T-26-02: double-slash rule in build_deny_read_entries
- T-26-03: regime enum validation before source call
- T-26-04: secret_scan on SANDBOX_JSON before mutate_write
- T-26-05: default output dir is ./conjure-policy/; no system path logic

## Commits

| Hash | Description |
|------|-------------|
| fe5868b | feat(26-01): add policy-helpers.sh and compliance regime data files |
| 9c62923 | feat(26-01): add emit-policy.sh worker and CLI dispatch |

## Self-Check: PASSED
