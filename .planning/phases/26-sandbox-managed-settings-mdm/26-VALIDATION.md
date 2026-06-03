---
phase: 26
slug: sandbox-managed-settings-mdm
status: draft
nyquist_compliant: true
wave_0_complete: false
created: 2026-06-03
---

# Phase 26 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Hand-rolled `tests/run.sh` fixture harness (project convention; no npm/bats at suite level) |
| **Config file** | none — fixtures live under `tests/fixtures/_emit-policy*/` |
| **Quick run command** | `bash tests/run.sh` (grep the POL-* block) |
| **Full suite command** | `bash tests/run.sh` |
| **Estimated runtime** | ~30–60 seconds |

---

## Sampling Rate

- **After every task commit:** Run `bash tests/run.sh`
- **After every plan wave:** Run `bash tests/run.sh` + `shellcheck -S error -e SC2164,SC2044,SC2034,SC2155 <changed .sh>`
- **Before `/gsd-verify-work`:** Full suite must be green
- **Max feedback latency:** 60 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 26-00-01 | 00 | 0 | POL-01..05 | — | Graceful-red fixtures + expected artifacts exist before feature code | fixture | `bash tests/run.sh` (POL block red) | ❌ W0 | ⬜ pending |
| 26-01-01 | 01 | 1 | POL-01 | T-26-01 | sandbox{} block merged into settings.json via jq+mutate_write; idempotent (re-run identical) | fixture | `bash tests/run.sh` (POL-01) | ❌ W0 | ⬜ pending |
| 26-01-02 | 01 | 1 | POL-02 | T-26-02 | every denyRead path mirrored 1:1 into permissions.deny as Read(<path>) (double-slash for absolute) | fixture | `bash tests/run.sh` (POL-02) | ❌ W0 | ⬜ pending |
| 26-02-01 | 02 | 2 | POL-03 | T-26-03 | managed-settings.json: disableBypassPermissionsMode STRING "disable", allowManagedPermissionRulesOnly, forceLoginOrgUUID placeholder, sandbox block | fixture | `bash tests/run.sh` (POL-03) | ❌ W0 | ⬜ pending |
| 26-02-02 | 02 | 2 | POL-04 | T-26-04 | MDM bundle: macOS com.anthropic.claudecode.plist + Windows Set-ClaudeCodePolicy.ps1; never system paths; deprecated ProgramData path absent | fixture | `bash tests/run.sh` (POL-04) | ❌ W0 | ⬜ pending |
| 26-03-01 | 03 | 3 | POL-05 | T-26-05 | audit flags missing sandbox / unmirrored denyRead / wrong-type disableBypass (fail exit 2); unreviewed template note (exit 0) | fixture | `bash tests/run.sh` (POL-05 + negative fixture) | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `tests/fixtures/_emit-policy/harness/` — input harness (CLAUDE.md with `<!-- compliance:hipaa -->` marker, .claude/settings.json, .conjure-version)
- [ ] `tests/fixtures/_emit-policy/expected-settings.json` — settings.json after sandbox merge (sandbox block + mirrored permissions.deny Read())
- [ ] `tests/fixtures/_emit-policy/expected-managed-settings.json` — managed-settings.json golden (string-typed disableBypassPermissionsMode)
- [ ] `tests/fixtures/_emit-policy/expected-plist.xml` + `expected-policy.ps1` — MDM artifact goldens
- [ ] `tests/fixtures/_emit-policy-broken/` — negative fixture: managed-settings with wrong type/key for audit detection
- [ ] Phase 26 graceful-red block appended to `tests/run.sh` (all POL-* cases fail until Wave 1+)

*Wave 0 establishes the Nyquist invariant: test infrastructure exists before feature code (mirrors Phase 25's `_emit-plugin` pattern).*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| `--validate` calling real `claude plugin`/config validators | POL-03/05 | Requires a real `claude` binary + macOS `plutil` not present in CI | On macOS with `claude` installed: `conjure emit-policy --regime hipaa --output /tmp/pol && plutil -lint /tmp/pol/com.anthropic.claudecode.plist` → OK |
| Live deployment + `claude config get sandbox.enabled` returns true | POL-03 | Requires deploying managed-settings to a system path (never auto-done) | Follow the printed verification assertion after a manual deploy |

---

## Validation Sign-Off

- [x] All tasks have automated verify (fixture/test) or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references (fixtures + expected artifacts)
- [x] No watch-mode flags
- [x] Feedback latency < 60s
- [x] `nyquist_compliant: true` set in frontmatter (after planner wires Wave 0)

**Approval:** pending (wave_0_complete: false — Wave 0 has not yet executed; nyquist_compliant reflects plan structure completeness, not execution state)
