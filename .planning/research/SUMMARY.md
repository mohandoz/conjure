# Project Research Summary

**Project:** Conjure v0.7.0 — Plugin-native + Policy-grade
**Domain:** POSIX bash + Node stdlib .mjs CLI harness scaffolder — plugin/marketplace emission, deployable policy/MDM, promptfoo eval gating, schema-version-aware audit, cross-repo workspace orchestration
**Researched:** 2026-06-03
**Confidence:** HIGH (official Claude Code docs, live codebase reads, confirmed GitHub issues; MEDIUM for promptfoo CI behavior and cross-repo saga patterns)

---

## Executive Summary

Conjure v0.7.0 adds five substantial capability areas on top of the stable v0.6.0 brownfield adoption base (467 passing tests): plugin/marketplace emission, sandbox and managed-settings/MDM policy generation, promptfoo-based eval gating with context-budget linting, schema-version-aware audit, and cross-repo workspace orchestration. The milestone's central challenge is not any single feature — it is scope discipline. Five areas built in parallel will produce five half-built features; four validated areas unlocking the fifth sequentially will produce something teams can actually depend on. Cross-repo orchestration is the capstone and must remain locked until areas 1-4 are each individually verified.

The recommended build sequence (Plugin → Sandbox/MDM → Eval → Schema-audit → Workspace) tracks a dependency graph that research across all four files confirms with high consistency. Plugin helpers must be extracted before emit-plugin ships; schema-aware audit must be available before workspace can aggregate per-repo audit outputs. The unifying architectural theme is unchanged from v0.6.0: every emitted artifact must have a testable verification command. The v0.6.1 hook-reads-argv regression — a shipped config that silently did nothing — is the template for the highest-risk failure class in v0.7.0. MDM artifacts that silently no-op because a key is misspelled, marketplace entries that fail `claude plugin validate` after a CC schema update, and hook events named `SessionStop` (invalid; correct name is `SessionEnd`) are all the same bug class wearing different costumes.

The zero-dependency runtime envelope (`dependencies: {}` stays empty) and POSIX bash 3.2+ constraints apply throughout. Net new runtime dependencies are zero: promptfoo is invoked via `npx promptfoo@0.121.14` at eval time only (never bundled); plist generation uses `python3`/`plutil` (macOS system tools); everything else is `jq` + bash arithmetic already in the envelope. The scope is genuinely large for a tool with a strict safety bar, but each area is independently shippable and has well-documented patterns from the official Claude Code docs verified in this research session.

---

## Key Findings

### Recommended Stack (v0.7.0 additions)

All five areas add zero new runtime dependencies. The full v0.7.0 stack table is documented in `.planning/research/STACK.md` (lines 1283-2028). Key additions:

**Core technologies:**
- `claude plugin validate .` (Claude Code built-in CLI) — plugin/marketplace CI validation at emit time, no external tool
- `lib/cc-schema.json` (bundled JSON, ~2KB) — schema-version-aware audit; MUST be bundled, NOT fetched at runtime (zero-egress CI constraint; schema fetching is an anti-pattern)
- `npx --yes promptfoo@0.121.14 eval` — eval gate; pinned, invoked at eval time only; `CONJURE_PROMPTFOO_VERSION` env var allows team override; Node >=20.20.0 required for `conjure eval` specifically
- `while read -r` workspace iteration (POSIX bash 3.2+) — cross-repo orchestration without any new dep
- `jq` (existing hard dep) — all JSON merges for sandbox block, managed-settings, marketplace wiring
- `python3 -c "import plistlib..."` OR `plutil` (macOS system tools) — macOS plist generation; advisory dep, no install required

**Critical schema facts (must-not-get-wrong):**
- `SessionStop` is NOT a valid hook event; correct name is `SessionEnd` — hooks using `SessionStop` silently fail
- `extraKnownMarketplaces` is an **object** (keys = marketplace names), NOT an array
- `strictKnownMarketplaces` goes in `managed-settings.json` ONLY — silently ignored if placed in `.claude/settings.json`
- `disableBypassPermissionsMode` must be string `"disable"`, NOT boolean `true`
- `sandbox.filesystem.denyRead` does NOT block Claude's `Read` tool — must be mirrored in `permissions.deny` as `Read(<path>)` rules
- Windows `C:\ProgramData\ClaudeCode\` path deprecated since v2.1.75 — do NOT emit; use `C:\Program Files\ClaudeCode\managed-settings.json` + registry key
- `promptfoo@0.121.14` requires Node `^20.20.0 || >=22.22.0` — add preflight check to `conjure eval` only; do not raise global Conjure Node requirement

### Expected Features

Full feature tables are in `.planning/research/FEATURES.md`. Synthesized priorities:

**Must have (P1 — foundational):**
- D: `conjure audit` validates all SKILL.md frontmatter keys (including new `disallowed-tools`) + hook event names against bundled table + `disableBypassPermissionsMode` type check + `--json` flag (needed by workspace aggregation)
- B: Sandbox block emission from compliance overlays into `.claude/settings.json` with mirrored `permissions.deny` for denyRead paths
- B: `managed-settings.json` generation per overlay (IT deployment artifact)
- A: `conjure publish-plugin` emits `plugin.json` + `marketplace.json` from actual on-disk harness contents + wires `extraKnownMarketplaces` into settings
- C: `conjure eval init` scaffolds `promptfooconfig.yaml` + `conjure eval run` executes via npx + `conjure audit --budget` static context linter

**Should have (P2):**
- E: `.conjure-workspace` manifest + `conjure workspace init` discovery
- E: `conjure workspace check` + `conjure workspace audit` (multi-repo health aggregation)
- B: MDM plist (macOS) + Windows .reg fragment generation
- A: `--pin-sha` for marketplace sources

**Defer to v0.7.x or v0.8.0:**
- E: `conjure workspace adopt` — multi-repo brownfield adoption (HIGH complexity + HIGH risk)
- E: Workspace emit-managed (union managed-settings across repos)
- B: `managed-settings.d/` fragment generation (composable drops for layered IT policies)

**Anti-features to exclude:**
- Auto-deploy MDM artifacts to Jamf/Intune via their APIs (credentials + org-specific tenant IDs out of scope)
- Bundle promptfoo as a Conjure dependency (violates `dependencies: {}`)
- Run `conjure eval` from `conjure audit` by default (eval makes real API calls; costs $0.50-$5/run)
- Parallel workspace execution with all-or-nothing rollback guarantee (invariant cannot be maintained with concurrent bash processes)

### Architecture Approach

The v0.6.0 architecture baseline is fixed and fully shipped. All v0.7.0 work is additive: 3 new dispatcher entries in `cli/conjure`, 3 new worker scripts, 3 new shared libs, 1 bundled data file, and template/compliance additions. The core invariant is preserved: every filesystem write routes through `lib/mutate.sh`. No new area may bypass this. `lib/snapshot.sh` is reused by workspace orchestration without modification — its per-repo snapshot primitives provide the rollback foundation for aggregate workspace rollback.

**New components (full details in `.planning/research/ARCHITECTURE.md`):**
1. `lib/plugin-helpers.sh` — jq transforms for plugin.json/marketplace.json; shared by emit-plugin.sh and refactored publish-plugin.sh
2. `lib/policy-helpers.sh` — emit sandbox{}, managed-settings.json, MDM artifacts; shared by all 4 compliance overlays
3. `lib/workspace.sh` — workspace load/state/rollback/report; sources snapshot.sh + log.sh
4. `lib/cc-schema.json` — bundled CC schema table (hook events, settings keys, version gates); read by audit-setup.sh via jq; NO runtime fetch
5. `scripts/emit-plugin.sh` — generates .claude-plugin/ from harness; wires extraKnownMarketplaces
6. `scripts/eval.sh` — runs promptfoo via npx --yes; --gate exits 2 on failure
7. `scripts/workspace.sh` — 4-step pipeline: preflight all repos, snapshot all repos, execute ops sequentially, aggregate rollback on any failure

**Modified components:** `cli/conjure` (3 new subcommands), `scripts/audit-setup.sh` (schema-version + budget-linter sections), `compliance/*/apply.sh` (all 4 overlays gain `--emit-policy` flag path), `scripts/publish-plugin.sh` (refactored to source lib/plugin-helpers.sh)

**Unchanged:** `lib/mutate.sh`, `lib/snapshot.sh`, `lib/log.sh`, `lib/inventory.sh`, `scripts/adopt.sh`, `scripts/check.sh`, `scripts/init-project.sh`

### Critical Pitfalls

Full analysis with prevention checklists in `.planning/research/PITFALLS.md`. Top pitfalls by severity:

1. **"Silent no-op emitted config" class (CR-2, CR-1, CR-5)** — THE unifying pitfall across all 5 areas. Same root cause as the v0.6.1 hook-reads-argv bug. MDM artifacts that deploy silently but are ignored (wrong key name, wrong type, deprecated Windows path), plugin manifests that fail `claude plugin validate` after a CC schema update, and audit that passes on deprecated settings keys are all variants of the same pattern. Prevention: every emitted artifact requires a testable verification command at emit time, not just in CI. Compliance overlays that cannot be verified are not compliance overlays.

2. **Cross-repo aggregate rollback inconsistency (CR-6)** — Highest-risk pitfall in v0.7.0. If repo 7 of 20 fails mid-apply, repos 1-6 are modified with no automatic rollback. The saga pattern is mandatory: snapshot ALL repos before applying to ANY; workspace manifest records each repo's snapshot path before the first op; `aggregate_rollback()` reads the manifest and calls `snapshot_rollback` per applied repo. Durable `.conjure-workspace-state.json` persists across SIGKILL.

3. **`SessionStop` / schema drift producing false green audits (CR-5, area D)** — `SessionStop` is not a valid hook event; correct name is `SessionEnd`. Existing harnesses using `SessionStop` silently never fire. `lib/cc-schema.json` must include the full validated event list. Schema is BUNDLED (matches zero-egress constraint) with a staleness advisory at >90 days — live-fetch at audit time is the anti-pattern resolved against in this summary.

4. **Flaky promptfoo CI gate (CR-7, CR-8)** — LLM outputs are non-deterministic. Evals that mimic unit-test pass/fail patterns will produce false reds. Prevention: deterministic assertions (`contains`, `javascript`, `is-json`) first; `llm-rubric` last and only for genuinely subjective checks; `repeat: 3, minPassCount: 2` for any `llm-rubric` assertion; eval must never be called from `conjure audit` path.

5. **Scope explosion without sequencing discipline (SD-1)** — 5 areas built simultaneously will be 5 half-built features. Phase 5 (workspace) must be explicitly locked until Phases 1-4 each pass their own validation checklist. workspace.sh calls all other conjure subcommands as subprocesses; they must be stable first.

---

## Implications for Roadmap

Based on the combined dependency graph confirmed across all 4 research files, the recommended build sequence is:

### Phase 1: Plugin + Marketplace Foundation (Area A)

**Rationale:** Plugin helpers must be extracted from `publish-plugin.sh` before `emit-plugin.sh` is written. Plugin emission is the simplest new command with the clearest spec from official docs. Establishes the emit-and-validate-at-emit-time pattern that all subsequent areas must follow. The smallest/safest area to ship first for early stabilization.

**Delivers:** `lib/plugin-helpers.sh` refactor; `scripts/emit-plugin.sh` + `cmd_emit_plugin`; `extraKnownMarketplaces` wiring into settings; `conjure publish` extended to validate marketplace.json reserved-name list; reconciliation check (manifest vs on-disk files).

**Must ship together:** `claude plugin validate .` called at emit time (not just CI); SHA pinning at publish time; ref-without-sha audit warning; secret-pattern scan on all emit output before write.

**Avoids pitfalls:** CR-1 (schema drift), CR-3 (version-pinning foot-guns), CR-4 (plugin/loose-file drift), M-2 (secrets in emitted config), M-5 (wrapping unstable CLI)

**Research flag:** Standard patterns — plugin schema is HIGH confidence from official docs. No research-phase needed.

---

### Phase 2: Sandbox + Managed-Settings / MDM (Area B)

**Rationale:** Policy emission depends only on `lib/mutate.sh` (shipped); no dependency on Phase 1 at the lib level. Building second lets compliance overlays adopt the emit-and-verify pattern established in Phase 1. MDM artifacts are the highest-stakes "looks done but isn't" surface.

**Delivers:** `lib/policy-helpers.sh`; all 4 compliance overlays gain `--emit-policy` flag path; `sandbox{}` block emitted into `.claude/settings.json` per overlay with mirrored `permissions.deny` for denyRead paths; `managed-settings.json` generation; platform-tagged MDM bundle (macos/, linux/, windows/); macOS plist via `plutil`/python3; Windows .reg fragment via bash string ops.

**Key schema facts to implement correctly:** `disableBypassPermissionsMode` must be string `"disable"` not boolean; `strictKnownMarketplaces` in managed-settings.json ONLY; denyRead must be mirrored in `permissions.deny` as `Read(<path>)` rules; deprecated Windows path `C:\ProgramData\ClaudeCode\` must NOT be emitted.

**Must ship together:** `conjure check --managed-settings` verification command; `conjure audit` flags missing `permissions.deny` mirror for denyRead paths; `conjure audit --compliance` flags uncustomized sandbox template.

**Avoids pitfalls:** CR-2 (silent MDM no-op), M-1 (sandbox too strict/loose), M-2 (secrets in emitted config), M-4 (cross-platform MDM paths)

**Research flag:** Windows drop-in directory (`managed-settings.d/`) behavior is MEDIUM confidence — verify against live CC before generating Windows drop-in configs during Phase 2 planning.

---

### Phase 3: promptfoo Eval + Context-Budget Linter (Area C)

**Rationale:** eval.sh has no hard dependency on Phases 1-2 (only needs `npx`). Placing eval before schema-audit means workspace (Phase 5) can include `conjure eval` as a supported workspace op. Budget linter extends `audit-setup.sh` — a natural prereq for schema-audit Phase 4 additions.

**Delivers:** `templates/evals/` directory (base + 4 compliance suites); `scripts/eval.sh` + `cmd_eval`; Node >=20.20.0 preflight check in `conjure eval` (not global); `conjure audit --budget` static context-budget linter; `conjure eval --init` scaffolds promptfooconfig.yaml; `conjure eval --emit-workflow` generates `.github/workflows/conjure-eval.yml`.

**Promptfoo invocation pattern:** `npx --yes "promptfoo@${CONJURE_PROMPTFOO_VERSION:-0.121.14}" eval -c <config> --no-cache --no-share`

**Must ship together:** Deterministic-assertion-first discipline (`contains`/`javascript` before `llm-rubric`); `repeat: 3, minPassCount: 2` for any llm-rubric assertion; eval absent from `conjure audit` code path; enforcement vs disposition taxonomy documented.

**Avoids pitfalls:** CR-7 (flaky CI gate), CR-8 (evals test wrong thing), CR-9 (promptfoo as hidden runtime dep)

**Research flag:** Phase 3 warrants a `--research-phase 3` pass to validate promptfoo's `claude-code-agent` provider behavior against Conjure's specific harness structure — novel integration not well documented outside promptfoo's own guides.

---

### Phase 4: Schema-Version-Aware Audit (Area D)

**Rationale:** Schema audit additions to `audit-setup.sh` are targeted and isolated. `lib/cc-schema.json` is a data file with no code dependencies. This phase also delivers `conjure audit --json` (needed by workspace Phase 5 for per-repo audit aggregation). Building D before E ensures workspace has a stable audit interface to call.

**Delivers:** `lib/cc-schema.json` (bundled; updated at Conjure release time; NO runtime fetch); schema-version section in `scripts/audit-setup.sh` (hook event name validation, settings key validation, version-gate checks, staleness warning at >90 days); `conjure audit --json` output flag; `disableBypassPermissionsMode` type check (string "disable" vs boolean); `disallowed-tools` frontmatter validation; SKILL.md frontmatter schema updated to include all 14 documented fields.

**Schema conflict resolved:** PITFALLS.md CR-5 advocates live-fetch schema with local cache. ARCHITECTURE.md and STACK.md both specify BUNDLED schema. This summary resolves in favor of BUNDLED — matches zero-egress CI constraint, zero-dep rule, and air-gapped enterprise compliance targets. Staleness is handled via >90-day advisory warning + `conjure update` prompt. Runtime fetch is an anti-pattern for this codebase.

**Must ship together:** `SessionEnd` (not `SessionStop`) in valid_hook_events; CC version detection falls back gracefully when `claude` not on PATH (warn, not fail); schema staleness advisory is a WARN not an ERR.

**Avoids pitfalls:** CR-5 (stale schema false green), CR-2 (managed-only key placement)

**Research flag:** Standard patterns — schema table content is HIGH confidence from official docs. No research-phase needed.

---

### Phase 5: Cross-Repo / Workspace Orchestration (Area E)

**Rationale:** MUST be last. workspace.sh calls `conjure init`, `conjure adopt`, `conjure audit`, `conjure check`, and `conjure eval` as subprocesses — all must be stable. Phase 5 is explicitly locked until Phases 1-4 each pass their own validation checklist. This is the same deferral rationale from v0.6.0 (safe single-repo operation before multi-repo orchestration) applied one level up.

**Delivers:** `.conjure-workspace` file format (one repo per line, comment-stripped); `lib/workspace.sh` (workspace_load, workspace_state_init, workspace_state_update, workspace_aggregate_rollback, workspace_report); `scripts/workspace.sh` 4-step pipeline; `cmd_workspace` in `cli/conjure`; `conjure workspace init` (discovers sibling repos with `.claude/`); `conjure workspace check` + `conjure workspace audit` (multi-repo health, fail-tolerant default); `conjure workspace rollback` reads `.conjure-workspace-state.json` and calls `snapshot_rollback` per applied repo.

**Critical design requirements (all day-one, not hardening):**
- Snapshot ALL repos in Step 2 before applying to ANY in Step 3 (all-snapshot-before-any-apply — the aggregate rollback invariant)
- `.conjure-workspace-state.json` written before each repo op and updated after (durable crash recovery; persists across SIGKILL)
- Default mode: fail-tolerant (continue on single-repo failure, collect all failures, report at end); abort-on-first-failure requires `--fail-fast`
- `parallel: false` only in v0.7.0 — parallel execution breaks the all-or-nothing rollback invariant; deferred as future opt-in with `rollback_policy: best-effort` only
- Disk space estimate before snapshot phase; warn at >2 GB and require `--allow-large-snapshots`

**Defer to v0.7.x or v0.8.0:** `conjure workspace adopt` (multi-repo brownfield); workspace emit-managed (union managed-settings); `conjure workspace update` (HIGH complexity + conflict sidecar aggregation)

**Avoids pitfalls:** CR-6 (aggregate rollback inconsistency), M-3 (single bad repo aborts batch), SD-1 (scope explosion)

**Research flag:** Phase 5 requires a `--research-phase 5` pass to validate the workspace manifest schema and state machine transitions before implementation begins. Aggregate rollback with durable state is novel territory for this codebase.

---

### Phase 6: Integration Tests for All Areas

**Rationale:** Per-area test fixtures must be added to `tests/run.sh` as graceful-red blocks. The integration fixtures are batched here because each tests the assembled result of its area.

**Delivers:** `tests/fixtures/_workspace-trio/` (3 small repos for workspace orchestration fixture); mock promptfoo stub (deterministic npx replacement for CI speed); golden fixture diffs for all new emit paths; `tests/run.sh` extended with blocks for Areas A-E.

**Addresses:** All pitfall "looks done but isn't" checklists from PITFALLS.md (9 checklist items spanning all areas)

---

### Phase Ordering Rationale

- **A and B** can proceed in parallel at the lib level (`lib/plugin-helpers.sh` and `lib/policy-helpers.sh` have no inter-dependency), but A must ship the emit-and-verify-at-emit-time pattern first as the discipline template.
- **C (eval)** has no hard code dependency on A or B; placed third because it extends `audit-setup.sh` which Phase D also extends, allowing a clean sequential modification.
- **D (schema-audit)** after C because `conjure audit --json` (Phase D's deliverable) is needed by workspace. Workspace planning needs this interface stable before Phase E implementation begins.
- **E (workspace) MUST be last** — calls every other subcommand as subprocess; aggregate rollback depends on per-repo snapshot primitives being hardened across all single-repo ops. No exceptions.
- Within any phase, researchers consistently agree: schema-audit (D) before eval (C) is slightly preferable if sequencing is strict, but C and D can be built concurrently with care to avoid `audit-setup.sh` conflicts.

### Research Flags

Phases needing deeper research during planning:
- **Phase 3 (eval):** promptfoo-action integration with Conjure's specific harness structure is novel; run `--research-phase 3` to validate provider config and assertion taxonomy
- **Phase 5 (workspace):** Aggregate rollback state machine design is new territory; run `--research-phase 5` to validate workspace manifest schema + state transitions

Phases with well-documented patterns (skip research-phase):
- **Phase 1 (plugin):** Plugin schema is HIGH confidence from official docs; `claude plugin validate` is built-in CLI
- **Phase 2 (sandbox/MDM):** All key names, paths, and platform variants verified from official CC docs (note Windows drop-in uncertainty — verify during planning, not a full research phase)
- **Phase 4 (schema-audit):** Schema table content is HIGH confidence; implementation extends existing audit-setup.sh patterns

---

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | All v0.7.0 stack additions verified against official Claude Code docs (June 2026); promptfoo version and Node.js requirement confirmed from official release notes; zero new runtime deps confirmed |
| Features | HIGH | Plugin/marketplace, sandbox/MDM, and hook schema from official docs (HIGH); promptfoo eval patterns from official promptfoo docs (HIGH); cross-repo patterns from GitHub issue analysis + community sources (MEDIUM raised toward HIGH by convergence) |
| Architecture | HIGH | Based on live codebase reads + official CC docs; all integration points derived from source code; component interaction map confirmed against existing script interfaces |
| Pitfalls | HIGH | Critical pitfalls derived from confirmed GitHub issues (#51978, #33739, #9686, #58873, #32226, #37683) and official docs; MEDIUM for promptfoo CI flakiness patterns (confirmed from multiple community sources) |

**Overall confidence:** HIGH

### Gaps to Address

- **Windows drop-in directory behavior:** `managed-settings.d/` is confirmed for macOS and Linux but MEDIUM confidence on Windows; verify against live CC before generating Windows drop-in configs (Phase 2 planning)
- **`extraKnownMarketplaces` in managed-settings scope — open Q:** Whether `extraKnownMarketplaces` is honored or silently ignored in `managed-settings.json` scope is not definitively documented; resolve at Phase 1 planning by testing against a live CC install or querying Anthropic docs
- **`allowed-tools` enforcement gap:** Open bug (#37683) — `allowed-tools` in SKILL.md frontmatter is parsed but not enforced at the tool-permission level; `conjure audit` should document this limitation in warning messages rather than treating it as a config error (carry through Phase 4)
- **promptfoo provider config for Conjure harnesses:** The `claude-code-agent` provider with `setting_sources` and `skills: all` against a real Conjure harness has not been end-to-end validated; primary Phase 3 research gap
- **Schema-aware audit bundled vs live-fetch:** Resolved in favor of BUNDLED in this summary (zero-egress + zero-dep constraint wins). Teams must update Conjure after CC releases to get fresh schema; the >90-day staleness advisory in `audit-setup.sh` is the mitigation.

---

## Sources

### Primary (HIGH confidence)
- [Claude Code plugin-marketplaces docs](https://code.claude.com/docs/en/plugin-marketplaces) — full marketplace.json schema, plugin.json schema, extraKnownMarketplaces shape, strictKnownMarketplaces, reserved names, source types; verified 2026-06-03
- [Claude Code settings docs](https://code.claude.com/docs/en/settings) — full sandbox{} schema, all managed-only keys with exact names/types, MDM deployment paths per platform, deprecated Windows path, all settings keys since v2.1.117; verified 2026-06-03
- [Claude Code hooks docs](https://code.claude.com/docs/en/hooks) — full 30+ event list, exit code semantics, MessageDisplay event, ConfigChange event, SessionEnd (not SessionStop); verified 2026-06-03
- [Claude Code week 22 changelog](https://code.claude.com/docs/en/whats-new/2026-w22) — v2.1.150-v2.1.157 features including disallowed-tools, MessageDisplay, defaultEnabled, workflowKeywordTriggerEnabled; verified 2026-06-03
- [promptfoo releases (GitHub)](https://github.com/promptfoo/promptfoo/releases) — v0.121.14 stable, Node ^20.20.0 requirement; verified 2026-06-03
- [anthropics/claude-code#51978](https://github.com/anthropics/claude-code/issues/51978) — marketplace schema drift: 14 plugins uninstallable after source field format change
- [anthropics/claude-code#32226](https://github.com/anthropics/claude-code/issues/32226) — sandbox denyRead does not block Read tool; confirmed from settings docs
- [anthropics/claude-code#37683](https://github.com/anthropics/claude-code/issues/37683) — allowed-tools not enforced at tool-permission level (open bug)
- Conjure live codebase: `cli/conjure`, `lib/mutate.sh`, `lib/snapshot.sh`, `lib/caps.sh`, `scripts/audit-setup.sh`, `scripts/publish-plugin.sh`, `compliance/hipaa/apply.sh`, `.claude-plugin/`
- [anthropics/claude-plugins-official marketplace.json](https://github.com/anthropics/claude-plugins-official/blob/main/.claude-plugin/marketplace.json) — authoritative real-world schema confirmation

### Secondary (MEDIUM confidence)
- [promptfoo Claude Agent SDK provider](https://www.promptfoo.dev/docs/providers/claude-agent-sdk/) — claude-code-agent provider config; verified 2026-06-03
- [promptfoo evaluate-coding-agents guide](https://www.promptfoo.dev/docs/guides/evaluate-coding-agents/) — assert types, --no-cache, --no-share patterns
- [promptfoo promptfoo-action GitHub Action](https://github.com/promptfoo/promptfoo-action) — PR gate integration
- [Multi-repo workspace structuring patterns](https://karun.me/blog/2026/03/26/structuring-claude-code-for-multi-repo-workspaces/) — community patterns for cross-repo orchestration
- [Compensating Transaction Pattern — Azure Architecture Center](https://learn.microsoft.com/en-us/azure/architecture/patterns/compensating-transaction) — saga pattern for aggregate workspace rollback design
- [anthropics/claude-code#33739](https://github.com/anthropics/claude-code/issues/33739) — official marketplace fails to load after single schema incompatibility (cascade failure)
- [anthropics/claude-code#9686](https://github.com/anthropics/claude-code/issues/9686) — $schema URL in marketplace.json does not exist causes full validator failure

### Tertiary (LOW confidence — needs validation during planning)
- Windows `managed-settings.d/` drop-in directory behavior — not definitively documented
- `extraKnownMarketplaces` behavior in managed-settings.json scope — open question, not confirmed from docs

---
*Research completed: 2026-06-03*
*Ready for roadmap: yes*
