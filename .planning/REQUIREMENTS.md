# Requirements: Conjure — v0.7.0 Plugin-native + Policy-grade

**Defined:** 2026-06-03
**Core Value:** A developer can turn any repo into a production-grade, eval-backed Claude Code harness with one trustworthy command — and keep it healthy over time.

> **Cross-cutting invariant (from PITFALLS.md — the v0.6.1 lesson):** every artifact
> Conjure *emits* (plugin/marketplace, sandbox/managed-settings, MDM, eval config,
> schema table) MUST ship with a testable verification command. An emitted config that
> silently does nothing is the milestone's primary failure class. Each `*-emit`/`publish`
> requirement is paired with an `audit`/`--validate` check that proves it is live.

## v1 Requirements

Build order (research consensus): **A plugin → B policy → C eval → D schema-audit → E workspace (last)**.
`conjure audit --json` (SCHM-05) ships early — it unblocks EVAL coverage + WS aggregation.

### Plugin + Marketplace Emission (PLUG)

- [ ] **PLUG-01**: `conjure publish-plugin` emits `.claude-plugin/plugin.json` from the scaffolded harness (correct `skills`/`agents`/`hooks`/`mcpServers` paths; `version` from `.conjure-version`)
- [ ] **PLUG-02**: `conjure publish-plugin --marketplace` generates `.claude-plugin/marketplace.json` (kebab-case `name`, `owner`, `plugins[]` with `source`); reserved-name guard
- [ ] **PLUG-03**: wires `extraKnownMarketplaces` (object form) + `enabledPlugins` into `.claude/settings.json` via idempotent `mutate_write` merge
- [ ] **PLUG-04**: `conjure publish-plugin --validate` runs `claude plugin validate` + JSON-schema check at emit time (no-silent-no-op gate); refuses on invalid manifest
- [ ] **PLUG-05**: version fallback — when `version` absent in `plugin.json`/marketplace entry, emit current git SHA as the version

### Policy: Sandbox + Managed-Settings / MDM (POL)

- [ ] **POL-01**: each compliance overlay emits a regime-specific `sandbox{}` block (`denyRead`/`denyWrite`/`network.allowedDomains`) merged into `.claude/settings.json` via `jq` + `mutate_write`
- [ ] **POL-02**: every `sandbox.filesystem.denyRead` path is mirrored into `permissions.deny` as `Read(<path>)` (closes the Read-tool enforcement gap #32226)
- [ ] **POL-03**: each overlay emits `managed-settings.json` with `disableBypassPermissionsMode:"disable"` (string, not boolean), `allowManagedPermissionRulesOnly`, `forceLoginOrgUUID` placeholder, and the sandbox block
- [ ] **POL-04**: MDM artifact generation — macOS plist (`com.anthropic.claudecode`) + Windows PowerShell/registry (`Set-ClaudeCodePolicy.ps1` → `HKLM\SOFTWARE\Policies\ClaudeCode`) written to a caller-specified output dir (never auto-placed at system paths)
- [ ] **POL-05**: `conjure audit` flags (a) overlay active but missing/`enabled:false` sandbox, (b) `denyRead` path with no mirrored `Read(...)` deny, (c) `disableBypassPermissionsMode` wrong type

### Eval: promptfoo + Context-Budget Linter (EVAL)

- [ ] **EVAL-01**: `conjure eval init` scaffolds `.conjure/eval/promptfooconfig.yaml` — one `skill-used` assertion per installed skill + `llm-rubric` per CLAUDE.md rule line
- [ ] **EVAL-02**: `conjure eval run` shells out to pinned `npx --yes promptfoo@<pinned>` (preflight: Node ≥20.20), passes through exit code; never bundled, never invoked from `audit`/`check`
- [ ] **EVAL-03**: `conjure eval --emit-workflow` generates a `pull_request` PR-gate workflow (`promptfoo/promptfoo-action`, `fail-on-threshold`, path-triggered on `.claude/**`,`CLAUDE.md`)
- [ ] **EVAL-04**: `conjure audit --budget` — static context linter (chars/4 on CLAUDE.md + always-loaded skills; flag over threshold; list top contributors; `--porcelain`)
- [ ] **EVAL-05**: `conjure audit` reports installed skills with no `skill-used` coverage in the eval config

### Schema-Version-Aware Audit / Check (SCHM)

- [ ] **SCHM-01**: `conjure audit` validates SKILL.md frontmatter against the current documented field set (incl. `disallowed-tools` as array/space-string); Conjure-maintained schema (not the stale VS Code one)
- [ ] **SCHM-02**: `conjure audit` flags `disableBypassPermissionsMode` set to boolean instead of string `"disable"`
- [ ] **SCHM-03**: `conjure check` flags unknown/renamed hook event names against a bundled event table (e.g. `SessionStop` → `SessionEnd`)
- [ ] **SCHM-04**: `conjure check --schema` reports the CC version each settings key was introduced in, vs the pinned `.conjure-version`, using a **bundled** `lib/cc-schema.json` (no runtime fetch — zero-egress)
- [ ] **SCHM-05**: `conjure audit --json` machine-readable output (consumed by EVAL coverage + WS aggregation)

### Cross-Repo / Workspace Orchestration (WS)

- [ ] **WS-01**: `.conjure-workspace.json` manifest (schema + validation + parent-dir discovery, same pattern as `.conjure-version`)
- [ ] **WS-02**: `conjure workspace init` discovers sibling repos containing `.claude/` (TTY prompt; non-TTY requires `--yes`); writes manifest via `mutate_write`
- [ ] **WS-03**: `conjure workspace check` runs `conjure check --porcelain` per repo → aggregated per-repo status table
- [ ] **WS-04**: `conjure workspace audit` runs `conjure audit --json` per repo → aggregated pass/fail + global summary
- [ ] **WS-05**: `conjure workspace update` runs `conjure update` per repo serially, reports per-repo merge/conflict status, `--continue-on-error` (default stop-on-first-error)
- [ ] **WS-06**: `conjure workspace adopt` across repos (optional tag filter), serial, **all snapshots taken before any apply** (saga); per-repo `.conjure-workspace-state.json` crash durability; stop-on-fail
- [ ] **WS-07**: `conjure workspace adopt --rollback` rolls back each repo independently from its pre-run snapshot; SIGKILL-mid-batch → rollback yields per-repo sha256 zero-diff (CI fixture test)

## v2 / Future Requirements

Acknowledged, deferred — not in this roadmap.

### Plugin (PLUG)
- **PLUG-F1**: `--pin-sha` resolves all marketplace sources to exact commit SHAs
- **PLUG-F2**: auto-wire `allowCrossMarketplaceDependenciesOn` when multi-source plugins detected

### Policy (POL)
- **POL-F1**: `managed-settings.d/` numbered drop-in fragments (composable layered policy)
- **POL-F2**: `_conjure_source` provenance annotations in emitted managed-settings
- **POL-F3**: `policyHelper` script generation for dynamic org policy

### Eval (EVAL)
- **EVAL-F1**: `conjure eval snapshot` local pass/fail baseline for before/after comparison
- **EVAL-F2**: per-skill trajectory assertion stubs from `allowed-tools` frontmatter

### Schema (SCHM)
- **SCHM-F1**: `conjure audit --strict` cross-validates `allowed-tools` vs hook `matcher` patterns
- **SCHM-F2**: schema-table self-update notice from `claude --version` in connected envs

### Workspace (WS)
- **WS-F1**: `conjure workspace report` — single-pane markdown/JSON health (version/drift/overlay/eval coverage)
- **WS-F2**: `conjure workspace emit-managed` — union managed-settings across mixed-compliance repos
- **WS-F3**: `conjure workspace import-mani` — convert a mani/ttal manifest to `.conjure-workspace.json`
- **WS-F4**: `--jobs N` parallel execution for read-only workspace commands (check/audit/report) only

## Out of Scope

Explicitly excluded (anti-features from research). Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| Merge/replace `conjure publish` + `publish-skill` into one command | Breaking change; conflates skill-PR flow with plugin-manifest generation. Add `publish-plugin` alongside. |
| Auto-install the plugin after generation | `claude plugin install` needs interactive trust/TTY; out of a non-CC context. Print the command. |
| `npm publish` as primary distribution | Adds release-pipeline scope. Support npm `source` in marketplace.json; don't run publish. |
| Auto-deploy MDM artifacts via Jamf/Intune APIs | Requires MDM credentials/tenant IDs Conjure must not handle. Generate artifacts + document deploy. |
| Claim overlays make a project "compliant" | Compliance needs people/process/BAA. Keep the "reduces non-compliant output" disclaimer. |
| Auto-detect credential paths by scanning the repo | False-positive + runtime cost. Ship standard per-regime deny patterns; document additions. |
| Bundle promptfoo as a dependency | Breaks `dependencies:{}`. Shell out to pinned `npx promptfoo`. |
| Run `conjure eval` on every `audit`/`check` | Real API cost ($0.50–$5/run) would blow CI budgets. Eval is an explicit opt-in subcommand. |
| Auto-fix schema violations (rewrite settings.json) | Mutation with semantic risk. Emit the correct key/value; user applies. |
| Refuse to audit on CC version mismatch | Would break CI for most teams. Warn, never hard-fail, on newer-than-known schema. |
| Runtime-fetch the CC schema table | Violates zero-egress-in-CI. Bundle `lib/cc-schema.json`; update via Conjure release. |
| Parallel execution of *mutating* workspace commands | Masks partial failures → inconsistent workspace. Serial for mutations; parallel read-only only (WS-F4). |
| Cross-repo atomic (all-or-nothing) rollback | Distributed-transaction complexity Conjure lacks state for. Per-repo snapshot rollback is the model. |
| Auto-clone missing repos from manifest git URLs | Credentials/SSH/network out of scope. `workspace init` discovers already-cloned repos. |
| Native integration with mani/ttal/other repo managers | None has dominant adoption. Accept `--workspace <path>`; offer a one-shot importer (WS-F3). |

## Traceability

Which phases cover which requirements. Populated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| (filled by roadmap) | — | Pending |

**Coverage:**
- v1 requirements: 27 total (PLUG 5, POL 5, EVAL 5, SCHM 5, WS 7)
- Mapped to phases: 0 (pending roadmap)
- Unmapped: 27 ⚠️

---
*Requirements defined: 2026-06-03*
*Last updated: 2026-06-03 after initial definition*
