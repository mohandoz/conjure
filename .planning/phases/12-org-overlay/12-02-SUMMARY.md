---
phase: 12-org-overlay
plan: 02
subsystem: cli
tags: [bash, cli, audit, overlay, shellcheck]

requires:
  - phase: 12-org-overlay
    plan: 01
    provides: scripts/init-overlay.sh + scripts/refresh-overlay.sh worker scripts

provides:
  - cli/conjure cmd_init with --overlay=<git-url> flag wiring to scripts/init-overlay.sh
  - cli/conjure cmd_refresh_overlay function + refresh-overlay) dispatch case
  - scripts/audit-setup.sh overlay presence + drift check section (OVLY-04)

affects:
  - 12-03 (test suite will invoke conjure init --overlay and verify audit output)

tech-stack:
  added: []
  patterns:
    - CLI flag extension: add to local declaration + case arm + body guard block
    - Dispatch table entry mirrors existing refresh-graph) pattern verbatim
    - Audit section reads flat key=value marker file via grep/cut (no jq)
    - git ls-remote with || true for graceful network failure (D-06)

key-files:
  created: []
  modified:
    - cli/conjure
    - scripts/audit-setup.sh

key-decisions:
  - "Used || true on git ls-remote line (not exit-code check) to prevent set -uo pipefail abort on network failure (Pitfall 3 / D-06)"
  - "Overlay section inserted between conflict-marker block and # Summary comment — maintains existing file structure"
  - "cut -d= -f2- (not -f2) for URL field to preserve = characters in URLs; cut -d= -f2 for SHA (no = in SHA)"

requirements-completed:
  - OVLY-01
  - OVLY-03
  - OVLY-04
  - OVLY-05

duration: 2min
completed: 2026-05-26
---

# Phase 12 Plan 02: CLI and Audit Wiring Summary

**Six-edit CLI wiring and audit extension: --overlay flag in cmd_init, cmd_refresh_overlay dispatcher, drift-detecting overlay audit section — all shellcheck-clean**

## Performance

- **Duration:** ~2 min
- **Started:** 2026-05-25T22:05:35Z
- **Completed:** 2026-05-25T22:07:35Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments

- `cli/conjure`: Added `overlay=""` local var, `--overlay=*` case arm, org overlay invocation block calling `scripts/init-overlay.sh` after profile overlay, `cmd_refresh_overlay()` function, `refresh-overlay)` dispatch case, updated `usage()` string for both additions
- `scripts/audit-setup.sh`: Inserted overlay presence + drift check section between conflict-marker block and `# Summary` — reads `.conjure-org-overlay` marker, calls `git ls-remote` with `|| true` for graceful degradation, reports ok/warn using existing helper functions

## Task Commits

Each task was committed atomically:

1. **Task 1: Extend cli/conjure** - `a2cba3f` (feat)
2. **Task 2: Add overlay audit section** - `732edd5` (feat)

## Files Created/Modified

- `cli/conjure` — 6 edits: local decl, arg parser, init-overlay.sh call, cmd_refresh_overlay function, dispatch case, usage string
- `scripts/audit-setup.sh` — 1 insertion: 20-line overlay section after conflict-marker block

## Decisions Made

- `|| true` on `git ls-remote` line in `audit-setup.sh` prevents `set -uo pipefail` from aborting audit when network is unreachable (Pitfall 3 / D-06 requirement); empty `UPSTREAM_SHA` output triggers the "drift check skipped" warning path
- `cut -d= -f2-` for URL (preserves `=` in URLs like `https://...`); `cut -d= -f2` for SHA (no `=` in SHAs) — matches PATTERNS.md read pattern
- Overlay section position: after line 145 (`fi` closing conflict-marker block), before `# Summary` comment — maintains file's existing section order

## Deviations from Plan

None - plan executed exactly as written. All 6 cli/conjure edits applied per PATTERNS.md Location 1-5 specifications. Audit section inserted verbatim per PATTERNS.md D-05/D-06 code block.

## Known Stubs

None.

## Threat Flags

| Flag | File | Description |
|------|------|-------------|
| threat_flag: network-egress | scripts/audit-setup.sh | git ls-remote outbound call to overlay repo URL stored in .conjure-org-overlay marker |

Note: This threat surface is fully covered by T-12-06 (DoS via hang — accepted, git default timeout acceptable) and T-12-07 (URL tampering — accepted, attacker needs write access) in the plan's STRIDE register.

## Self-Check

Files exist:
- cli/conjure: YES (modified in place)
- scripts/audit-setup.sh: YES (modified in place)

Commits exist:
- a2cba3f: YES
- 732edd5: YES

## Self-Check: PASSED
