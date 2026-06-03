---
phase: 27
slug: schema-version-aware-audit
status: draft
nyquist_compliant: true
wave_0_complete: false
created: 2026-06-03
---

# Phase 27 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Hand-rolled `tests/run.sh` fixture harness (project convention) |
| **Config file** | none — fixtures under `tests/fixtures/_schema-audit*/` |
| **Quick run command** | `bash tests/run.sh` (grep the SCHM-* block) |
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

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure/Correct Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 27-00-01 | 00 | 0 | SCHM-01..05 | — | Graceful-red fixtures (valid + invalid harnesses) + bundled lib/cc-schema.json exist before checks | fixture | `bash tests/run.sh` (SCHM red) | ❌ W0 | ⬜ pending |
| 27-01-01 | 01 | 1 | SCHM-01 | T-27-01 | audit validates 16 SKILL.md frontmatter fields; valid disallowed-tools (array OR space-string) accepted; bad type (`{Bash:true}`) → fail exit 2 | fixture | `bash tests/run.sh` (SCHM-01) | ❌ W0 | ⬜ pending |
| 27-01-02 | 01 | 1 | SCHM-02 | T-27-02 | audit flags disableBypassPermissionsMode boolean (top-level AND permissions.) → fail exit 2 with correct value in message; subsumes Phase 26 POL-05c | fixture | `bash tests/run.sh` (SCHM-02) | ❌ W0 | ⬜ pending |
| 27-02-01 | 02 | 2 | SCHM-03 | T-27-03 | check flags unknown/renamed hook event (SessionStop→SessionEnd) against lib/cc-schema.json events → fail exit 2 | fixture | `bash tests/run.sh` (SCHM-03) | ❌ W0 | ⬜ pending |
| 27-02-02 | 02 | 2 | SCHM-04 | T-27-04 | `check --schema` reports per-key CC-introduced version vs detected `claude --version`; claude absent → WARN not fail; >90d schema → WARN | fixture | `bash tests/run.sh` (SCHM-04) | ❌ W0 | ⬜ pending |
| 27-03-01 | 03 | 3 | SCHM-05 | T-27-05 | `audit --json` emits ONLY `{schema_version,status,checks[{id,severity,message}],summary}` to stdout; exit 2 on fail; jq-parseable; consumable by Phase 29 | fixture | `bash tests/run.sh` (SCHM-05) | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `lib/cc-schema.json` — bundled schema: 30 hook events, 16 SKILL.md frontmatter fields+types, settings_keys→introduced_version map, schema_version + generated date (authoritative content from RESEARCH.md)
- [ ] `tests/fixtures/_schema-audit/valid/` — a fully schema-valid harness (passes all SCHM checks)
- [ ] `tests/fixtures/_schema-audit-badfield/` — SKILL.md with `disallowed-tools: {Bash: true}` (invalid type)
- [ ] `tests/fixtures/_schema-audit-disablebypass/` — settings.json with boolean disableBypassPermissionsMode (both top-level + permissions. variants)
- [ ] `tests/fixtures/_schema-audit-hookevent/` — settings.json using a renamed/unknown hook event (SessionStop)
- [ ] `tests/fixtures/_schema-audit-stale/` — cc-schema.json copy with a >90-day generated date (staleness WARN)
- [ ] Phase 27 graceful-red SCHM block appended to `tests/run.sh`

*Wave 0 establishes the Nyquist invariant: bundled schema + fixtures before any check logic.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| `check --schema` against a real `claude --version` | SCHM-04 | CI has no `claude` binary; the absent-path (WARN) is auto-tested, the present-path is not | On a machine with `claude`: `conjure check --schema` → per-key versions reported, no fail |

---

## Validation Sign-Off

- [x] All tasks have automated verify (fixture/test) or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references (cc-schema.json + fixtures)
- [x] No watch-mode flags
- [x] Feedback latency < 60s
- [x] `nyquist_compliant: true` set in frontmatter (Wave 0 wired)

**Approval:** pending (wave_0_complete: false — Wave 0 not yet executed)
