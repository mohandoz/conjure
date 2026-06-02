---
phase: 260603-302
plan: 01
type: verification
status: passed
verified: 2026-06-02
method: behavioral spot-check + full suite + shellcheck (orchestrator-run, independent of executor)
---

# Verification — v0.6.1 Hardening Patch

All six fixes verified behaviorally against the live code, not just by passing tests.

## Gate results

- `bash tests/run.sh` → **PASS 467 / FAIL 0** (baseline 439, +28 new assertions)
- `shellcheck -S error -e SC2164,SC2044,SC2034,SC2155 cli/conjure scripts/init-overlay.sh scripts/refresh-overlay.sh scripts/audit-setup.sh` → **clean**
- 10 atomic commits (5 graceful-red test + 5 fix), `9bf1407`..`076aca5`

## must_haves — behavioral confirmation

| Truth | Check | Result |
|-------|-------|--------|
| pre-bash hook reads stdin JSON `tool_input.command` (was no-op) | piped `rm -rf /` payload → blocks | exit 2 ✓ |
| rm-rf regex catches flag-order variants (FIX-06) | piped `rm -fr ~` payload | exit 2 ✓ |
| safe command allowed | piped `git status` | exit 0 ✓ |
| gitleaks exit 1 (finding) blocks | stub gitleaks exit 1 + git commit payload | hook exit 2 ✓ |
| gitleaks exit 2 (tool error) does NOT false-block | stub gitleaks exit 2 | hook exit 0 ✓ |
| cron template has no pipe-to-shell | grep generated YAML | no `curl…\|bash` ✓ |
| cron uses SHA-pinned checkout | grep `actions/checkout@<40-hex>` | present ✓ |
| cron runs conjure from checkout tree (CONJURE_HOME) | grep `CONJURE_HOME=conjure-src` | present ✓ |
| inventory.sh DRY_RUN uses mktemp | grep | hardcoded `/tmp` gone, mktemp present ✓ |
| dispatcher / overlay scripts / cmd_publish exit 2 | tests/run.sh FIX-05 section | green ✓ |

## Preserved intentional exit-1 sites
- `scripts/audit-setup.sh:297` — warnings-only exit 1 (documented public API) — unchanged ✓
- `cli/conjure` cmd_update D-06 conflict `return 1` — unchanged ✓

## Disposition
PASSED — ready to tag v0.6.1. Core "production-grade harness" integrity restored:
the three shipped hooks that were silent no-ops now actually enforce.
