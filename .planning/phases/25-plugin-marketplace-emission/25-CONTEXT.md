# Phase 25: Plugin + Marketplace Emission - Context

**Gathered:** 2026-06-03
**Status:** Ready for planning

<domain>
## Phase Boundary

Deliver `conjure publish-plugin` — a command that generates, validates, and
wires a Claude Code **plugin** + **marketplace** manifest from a
conjure-scaffolded harness, in one command, with **emit-time verification**.

Requirements in scope: PLUG-01..PLUG-05.

**Critical distinction:** The existing `conjure publish` (v0.4.0, MKTPL-01..04)
*self-publishes Conjure itself* — it stamps Conjure's own
`.claude-plugin/{plugin,marketplace}.json` with HEAD SHA + version for Conjure's
release pipeline (called by `release.yml`). Phase 25's **new** `conjure
publish-plugin` is different in kind: it **emits a plugin from a target repo's
scaffolded `.claude/` harness** so an end user can turn their harness into an
installable plugin. Do not conflate the two; do not break the existing
`conjure publish` self-publish path.

**Out of scope (other phases):** sandbox/managed-settings/MDM policy emission
(Phase 26, POL-*); `strictKnownMarketplaces` (managed-settings only, Phase 26);
schema-version-aware audit + `--json` (Phase 27, SCHM-*); workspace/cross-repo
invocation of publish-plugin (Phase 29).
</domain>

<decisions>
## Implementation Decisions

### Command identity & surface
- **D-01:** Keep `conjure publish` (self-publish) and `conjure publish-plugin`
  (target-repo emit) as **separate subcommands**. Extract shared
  `lib/plugin-helpers.sh`; refactor existing `scripts/publish-plugin.sh`
  self-publish worker to source it. (Matches research §"New components" item 1.)
- **D-02:** `conjure publish-plugin` operates on the **current working
  directory** by default (like `init`/`adopt`/`audit`) but accepts an explicit
  **`--path <dir>`** flag for scripting / future workspace (Phase 29) per-repo
  invocation.
- **D-03:** When regenerating `.claude-plugin/plugin.json` (init scaffolds a
  stub), **merge-preserve-manual**: regenerate computed fields
  (`skills`/`agents`/`hooks`/`mcpServers` paths, `version`) via jq through
  `mutate_write`, but preserve user-edited metadata (`description`, `keywords`,
  `author`, `license`). Backup-before-mutate. (Do NOT clobber hand-tuned fields.)
- **D-04:** On success, print files written **plus a copy-pasteable
  verification command** (e.g. `claude plugin validate .`, `claude plugin list`)
  the user can run to confirm the plugin actually loads — honoring the
  milestone's emit-and-verify-at-emit-time discipline.

### Marketplace source & version provenance
- **D-05:** `--marketplace` source default = **auto-detect github**: parse
  `git remote get-url origin` → owner/repo, emit `source: github` with `ref` +
  **pinned `sha` (HEAD)**. Fall back to local source if no remote.
- **D-06:** Version fallback chain (PLUG-05): `.conjure-version` →
  **current git SHA** → placeholder **`0.0.0` + printed warning** when the
  target is not a git repo. **Dirty tree → still pin HEAD sha but warn loudly**
  ("uncommitted changes — sha may not reflect emitted contents"). **Never blocks
  emit.** NOTE the asymmetry: the existing self-publish `publish-plugin.sh`
  exit-2s on a dirty tree (strict, it's Conjure's own release); the new
  target-repo emit warns instead of blocking.
- **D-07:** Reserved-name guard (PLUG-02) uses a **bundled static list** baked
  into `lib/plugin-helpers.sh` (e.g. `anthropic`, `claude`, `claude-code`,
  `official`). Reject reserved marketplace names with **exit 2**. Zero-egress /
  bundled-data ethos (consistent with milestone's bundled cc-schema decision);
  staleness handled by audit advisory. Authoritative reserved set: official
  plugin-marketplaces docs (see canonical refs).
- **D-08:** Secret-pattern scan (criterion 5) covers the **whole emitted
  manifest** (plugin.json + marketplace.json — `env`, `mcpServers`, and any
  string value), not just the `env` block. **Exit 2 before writing any file** on
  a hit. Reuse any existing secret-pattern / gitleaks asset in the repo if
  present.

### Validate gate
- **D-09:** **Two-tier validation.** The **bundled JSON-schema check runs on
  every** `publish-plugin` invocation and **refuses to write any file on an
  invalid manifest** (this IS the no-silent-no-op gate, PLUG-04).
  `claude plugin validate .` is the **opt-in extra layer behind `--validate`**.
- **D-10:** When **`--validate` is requested but the `claude` CLI is absent →
  exit 2 hard** with an install hint (do NOT silently downgrade — the user
  explicitly asked for live validation, so failing to validate must be loud).
  Use conjure's `command -v` preflight convention for the missing-dep hint.
- **D-11:** Bundled plugin/marketplace JSON-schemas live in
  **`.claude-plugin/SCHEMAS/`** alongside the existing
  `agent.schema.json` / `skill.schema.json`, validated with the same approach
  `conjure audit` already uses. (New files: `plugin.schema.json`,
  `marketplace.schema.json`.)
- **D-12:** Audit reconciliation check (criterion 5 — plugin.json out-of-sync
  with actual `.claude/` contents) is a **warning, exit 0** (advisory, like the
  criterion-4 `ref`-without-`sha` warning). Does not break the CI gate; nudges
  the user to re-run `publish-plugin`.

### Settings wiring (PLUG-03)
- **D-13:** Wire `extraKnownMarketplaces` into the project
  **`.claude/settings.json`** (shared/committed) **only when `--marketplace` is
  passed**. Bare `publish-plugin` emits manifests without touching settings.
- **D-14:** **Discoverable-only by default**: wiring `extraKnownMarketplaces`
  makes the plugin known but does NOT auto-activate it. **`--enable`** opts into
  adding the plugin to `enabledPlugins` (`{"<name>@<marketplace>": true}`).
  Emitting a plugin must not silently turn it on.
- **D-15:** `extraKnownMarketplaces` is an **object** (keys = marketplace names);
  merge is **keyed-object idempotent** via jq through `mutate_write` — re-running
  updates the same key in place (sha refresh), never appends a duplicate. Cover
  with a **golden-fixture re-run test** (emit twice → identical settings.json).
- **D-16:** github `extraKnownMarketplaces` / marketplace entries **pin `sha`
  with `ref` as fallback** (write both) so emissions stay audit-clean against the
  criterion-4 ref-without-sha warning. Reproducible installs by default.

### Claude's Discretion
- Exact reserved-name string set (seed with the official docs list).
- Exact secret-pattern regex set / entropy threshold (reuse repo's existing
  scanner if one exists).
- Output formatting details of the emit report (align with existing
  `publish-plugin.sh` / adopt-report style).
- Whether `plugin.json` `mcpServers`/`hooks` path emission reads from
  `.mcp.json` / `.claude/settings.json` hooks block — resolve in research
  against the live harness layout and official plugin.json schema.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Milestone planning (read first)
- `.planning/ROADMAP.md` §"Phase 25: Plugin + Marketplace Emission" — goal,
  5 success criteria, dependency note (builds on shipped `lib/mutate.sh` +
  existing `.claude-plugin/` stub).
- `.planning/REQUIREMENTS.md` — PLUG-01..PLUG-05 (lines ~19–23) + traceability.
- `.planning/PROJECT.md` §"Current Milestone" / §"Key Decisions" — milestone
  goal, v0.6.1 silent-no-op lesson, mutate.sh chokepoint invariant.

### v0.7.0 research (high-signal for this phase)
- `.planning/research/SUMMARY.md` — esp. §"New components" (item 1
  `lib/plugin-helpers.sh`, item 5 `scripts/emit-plugin.sh`), §"Phase 1: Plugin +
  Marketplace Foundation", schema facts (`extraKnownMarketplaces` is an object;
  `strictKnownMarketplaces` is managed-settings-only), pitfall CR-1/CR-3/CR-4/M-2/M-5.
- `.planning/research/PITFALLS.md` — silent-no-op class, schema drift cascade.
- `.planning/research/ARCHITECTURE.md` — component boundaries / build order.
- `.planning/research/STACK.md` — runtime envelope (jq, `claude plugin validate`
  as built-in, no new deps).

### Existing code (extend, don't duplicate)
- `scripts/publish-plugin.sh` — existing self-publish worker (150 lines) to be
  refactored to source `lib/plugin-helpers.sh`; **do not break its contract**
  (called by `release.yml`; dirty-tree → exit 2).
- `cli/conjure` — dispatcher; `cmd_publish` (~line 442), `cmd_publish_skill`,
  dispatch table (~line 502). Add `publish-plugin` entry here.
- `lib/mutate.sh` — ALL filesystem writes route through this (dry-run, backup).
- `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json` — reference
  schema shapes (conjure's own); `.claude-plugin/SCHEMAS/{agent,skill}.schema.json`
  — pattern for the new plugin/marketplace schemas.

### Official external docs
- Claude Code plugin-marketplaces docs —
  https://code.claude.com/docs/en/plugin-marketplaces — full marketplace.json /
  plugin.json schema, `extraKnownMarketplaces` object shape, reserved names,
  source types (verified 2026-06-03 per SUMMARY.md).
- anthropics/claude-plugins-official `.claude-plugin/marketplace.json` —
  authoritative real-world schema confirmation.
- GitHub issues #51978 / #33739 — marketplace schema-drift cascade failures
  (motivates the emit-time validate gate).

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `scripts/publish-plugin.sh`: existing jq-based plugin/marketplace manifest
  updater + dirty-tree/dep preflight + `mutate.sh` sourcing — the jq transforms
  are the seed for `lib/plugin-helpers.sh`.
- `lib/mutate.sh`: `mutate_write` (idempotent JSON merge target) + dry-run +
  backup-before-mutate — the wiring chokepoint for settings.json + manifests.
- `.claude-plugin/SCHEMAS/`: established schema-validation location + jq approach
  used by `conjure audit`; add `plugin.schema.json` + `marketplace.schema.json`.
- `lib/snapshot.sh` / `lib/caps.sh` / `lib/inventory.sh`: harness-content
  enumeration patterns for computing `skills`/`agents`/`hooks` paths.

### Established Patterns
- Split responsibility: CLI owns all filesystem mutations (mutate.sh chokepoint);
  every write routes through it — new emit path must not bypass.
- `command -v` preflight table for missing-dep hints (jq, git, claude).
- Hooks/CLI exit 2 (never exit 1) for hard prerequisite failures; non-TTY safe.
- Bundled-data over runtime-fetch (zero-egress-in-CI); staleness handled by
  audit advisory warnings.

### Integration Points
- `cli/conjure` dispatch table — new `publish-plugin)` case + `cmd_publish_plugin`.
- `scripts/audit-setup.sh` — add the reconciliation (manifest↔.claude/ drift)
  warning + `ref`-without-`sha` marketplace warning.
- `.claude/settings.json` — `extraKnownMarketplaces` (object) + `enabledPlugins`
  merge target.

</code_context>

<specifics>
## Specific Ideas

- The two-publish distinction is the single most important framing for this
  phase: `conjure publish` = ship Conjure; `conjure publish-plugin` = ship the
  user's harness. Naming is locked by REQUIREMENTS (PLUG-01); do not rename.
- Emit-and-verify discipline is non-negotiable: every emitted manifest carries a
  printed, runnable verification assertion (D-04) AND a write-blocking schema
  gate (D-09). A manifest that emits but silently fails to load is THE failure
  class this milestone exists to prevent (v0.6.1 hook-reads-argv lesson).
- Asymmetric dirty-tree handling (D-06) is deliberate, not an oversight —
  document it so the planner doesn't "fix" the target-repo warn path to match
  the strict self-publish path.

</specifics>

<deferred>
## Deferred Ideas

- `--pin-sha` as a standalone marketplace-source pinning subcommand — research
  open-question E; revisit if SHA-pinning UX needs its own surface (not needed:
  D-16 pins by default).
- Workspace / cross-repo `publish-plugin` (emit across many repos) — Phase 29.
- `strictKnownMarketplaces` enforcement — Phase 26 (managed-settings.json only;
  silently ignored in `.claude/settings.json`).
- Resolving whether `extraKnownMarketplaces` is honored in managed-settings
  scope — SUMMARY.md open-Q, belongs to Phase 26 planning.

None outside milestone scope — discussion stayed within phase boundary.

</deferred>

---

*Phase: 25-plugin-marketplace-emission*
*Context gathered: 2026-06-03*
