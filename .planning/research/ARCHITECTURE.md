# Architecture Research

**Domain:** Open-source init kit for Claude Code — POSIX bash CLI + Node `.mjs` hooks (Conjure v0.7.0 "Plugin-native + Policy-grade")
**Researched:** 2026-06-03
**Confidence:** HIGH (live codebase read; official Claude Code docs fetched this session; all integration points derived from source)

> **Scope note (subsequent milestone):** This file extends the v0.6.0 ARCHITECTURE.md in place.
> The v0.6.0 architecture is taken as fixed and fully shipped (467 passing tests). Everything below
> is additive or a targeted modification to existing components. The core invariant holds:
> **every filesystem write routes through `lib/mutate.sh`**. All new components must honor this
> without exception. Hooks/scripts exit 2, never exit 1.

---

## Existing Architecture Baseline (v0.6.0, fixed)

```
cli/conjure               — dispatcher: parse flags, set env vars, delegate to scripts/
  ├── cmd_init            — init|migrate; --profile; --overlay; --dry-run
  ├── cmd_migrate         — calls migrations/<source>/migrate.sh
  ├── cmd_audit           — calls scripts/audit-setup.sh; --cost; --retire-list
  ├── cmd_update          — --check / --apply / --pr / --cron
  ├── cmd_check           — calls scripts/check.sh; --porcelain; exit 0/1
  ├── cmd_resolve         — calls scripts/resolve.sh; --dry-run
  ├── cmd_adopt           — calls scripts/adopt.sh; full brownfield pipeline
  ├── cmd_refresh_graph   — calls scripts/refresh-graph.sh
  ├── cmd_refresh_overlay — calls scripts/refresh-overlay.sh
  ├── cmd_install_mcp     — calls scripts/install-mcp-stack.sh
  ├── cmd_preflight       — calls scripts/preflight.sh
  ├── cmd_publish         — calls scripts/publish-plugin.sh
  └── cmd_publish_skill   — calls scripts/publish-skill.sh

lib/mutate.sh             — write chokepoint (ALL filesystem mutations go here)
lib/snapshot.sh           — snapshot_create / snapshot_rollback / snapshot_list
lib/inventory.sh          — inventory_scan / inventory_classify / inventory_emit_manifest
lib/log.sh                — log_init / log_step / log_fail → RESTRUCTURE-LOG.md
lib/merge.sh              — 3-way merge; writes conflict sidecars
lib/caps.sh               — CLAUDE_MD_CAP / SKILL_MD_CAP / AGENT_MD_CAP constants
lib/exact-count.mjs       — opt-in exact token counter (Node.js)
lib/prices.json           — per-model price table

scripts/adopt.sh          — 5-step brownfield adoption pipeline
scripts/audit-setup.sh    — health-check; size caps; schema validation
scripts/check.sh          — drift detection; read-only; exit 0/1
scripts/resolve.sh        — guided interactive sidecar walker
scripts/init-project.sh   — scaffold .claude/ (idempotent)
scripts/publish-plugin.sh — marketplace.json update + submission snippet
scripts/publish-skill.sh  — 4-gate skill validation + PR flow
scripts/preflight.sh      — dependency verification

templates/                — kit templates (CLAUDE.md.tmpl, skills/, agents/, hooks-nodejs/)
profiles/                 — 9 stack profiles (apply.sh per profile)
compliance/               — 4 compliance overlays (hipaa/ soc2/ gdpr/ pci/ — apply.sh + fragments)
.claude-plugin/           — plugin manifest (marketplace.json, plugin.json, SCHEMAS/)
tests/run.sh              — hand-rolled regression suite (467 assertions)
```

---

## v0.7.0 Design Overview: Five Capability Areas

The five areas integrate as follows and must share the invariants above:

1. **Plugin + marketplace emission** — `conjure emit-plugin` generates a well-formed plugin dir
   from the scaffolded harness; updates marketplace.json for the harness-as-plugin distribution
   channel; wires `extraKnownMarketplaces` into `.claude/settings.json`.

2. **Sandbox + managed-settings/MDM** — compliance overlays gain a second emit target: in addition
   to their current `apply.sh` (mutate CLAUDE.md + hooks), they emit a `sandbox{}` block into
   settings.json and a `managed-settings.json` artifact + optional MDM fragments (plist, registry).

3. **promptfoo eval + budget linter** — `conjure eval` runs promptfoo via `npx promptfoo` (no
   install dep); test specs live in `templates/evals/`; eval gates a CI job. Budget linter added
   to `conjure audit` as a new flag.

4. **Schema-version-aware audit** — audit reads a bundled schema table (`lib/cc-schema.json`)
   keyed by CC version ranges; validates known hook event names, settings keys, and disallowed
   patterns against the installed CC version.

5. **Cross-repo / workspace orchestration** — `conjure workspace` reads a `conjure-workspace.json`
   manifest; iterates repos; reuses `lib/snapshot.sh` per-repo; introduces `lib/workspace.sh`
   with aggregate rollback semantics.

---

## New and Modified Components

### Area 1: Plugin + Marketplace Emission

#### `cmd_emit_plugin` in `cli/conjure` (NEW dispatcher entry)

```
conjure emit-plugin [--plugin-dir <path>] [--marketplace-url <url>] [--dry-run] [target]
```

Thin wrapper: parse flags → env vars → `bash scripts/emit-plugin.sh`.

#### `scripts/emit-plugin.sh` (NEW worker)

**What it does:**
- Reads the scaffolded harness at `$target/.claude/` (skills/, agents/, hooks/, settings.json)
- Generates a self-contained plugin directory at `$target/.claude-plugin/` (if absent) or
  updates the existing one (it already exists in Conjure itself — the same pattern applies
  to harnesses emitted for other repos)
- Writes/updates `plugin.json` with skills paths, agents paths, hooks config
- Updates `marketplace.json` with current HEAD SHA and version (reuses publish-plugin.sh logic)
- Injects `extraKnownMarketplaces` into `.claude/settings.json` (via `mutate_write`)
- Optionally writes `strictKnownMarketplaces` into `.claude/settings.json` when `--strict` passed

**Reuse decision:** Do NOT duplicate `scripts/publish-plugin.sh`. Instead:
- `publish-plugin.sh` remains the Conjure-self publish path (updates Conjure's own marketplace.json)
- `emit-plugin.sh` is the target-repo path: generates/updates the target repo's `.claude-plugin/`
  from its scaffolded harness
- Both share a `lib/plugin-helpers.sh` that houses the jq transforms for marketplace.json + plugin.json

#### `lib/plugin-helpers.sh` (NEW shared lib)

Functions extracted from `publish-plugin.sh` and reused by `emit-plugin.sh`:
- `plugin_update_marketplace <marketplace_json> <version> <sha>` — jq transform
- `plugin_update_plugin_json <plugin_json> <version>` — jq transform
- `plugin_inject_extra_marketplace <settings_json> <marketplace_url>` — injects `extraKnownMarketplaces`
- `plugin_inject_strict_marketplace <settings_json> <marketplaces_json>` — injects `strictKnownMarketplaces`

All writes via `mutate_write`. Dry-run honored.

**Template reuse rationale:** The existing `templates/skills/`, `templates/agents/`, `templates/hooks-nodejs/`
are already referenced by `plugin.json` via relative paths (`"skills": "./templates/skills"` etc.).
`emit-plugin.sh` reads those existing paths from the target's `.claude/` and writes them into the
generated `plugin.json` without duplicating template content. The plugin dir is a view over the
harness, not a copy.

#### `marketplace.json` settings wiring

Official CC settings keys (confirmed from docs):
- `extraKnownMarketplaces`: array of marketplace source objects — registers marketplaces for the project
- `strictKnownMarketplaces`: array — restricts what users can add (MDM/managed-settings only for enforcement)

`emit-plugin.sh` writes `extraKnownMarketplaces` into `.claude/settings.json` via `mutate_write`
so that team members who clone the repo automatically have the harness marketplace registered.

---

### Area 2: Sandbox + Managed-Settings / MDM

#### Modified: `compliance/<overlay>/apply.sh` (all 4 overlays — MODIFIED)

Current overlays write:
- CLAUDE.md fragment (appended)
- A hook script
- A CONTROLS.md doc

**v0.7.0 addition:** Each overlay's `apply.sh` gains a `--emit-policy` flag path that writes:
- A `sandbox{}` block into `.claude/settings.json` (per-overlay allowWrite/denyRead/network values)
- A `managed-settings.json` artifact in a configurable output dir
- MDM fragments (optional, behind `--mdm` flag)

This is an additive flag, not a redesign. The existing `apply.sh` behavior (without `--emit-policy`)
is unchanged.

#### `lib/policy-helpers.sh` (NEW shared lib)

Shared functions for all 4 compliance overlays:
- `policy_emit_sandbox <settings_json> <sandbox_json_fragment>` — merges sandbox{} into settings.json via jq + mutate_write
- `policy_emit_managed_settings <output_dir> <policy_json>` — writes managed-settings.json via mutate_write
- `policy_emit_plist <output_dir> <policy_json>` — writes macOS plist (managed-settings MDM artifact)
- `policy_emit_registry_hive <output_dir> <policy_json>` — writes Windows .reg fragment
- `policy_emit_drop_in <output_dir> <filename> <fragment_json>` — writes managed-settings.d/ fragment

All writes via `mutate_write`. Dry-run honored.

#### Sandbox block structure (from official CC docs, HIGH confidence)

```json
{
  "sandbox": {
    "enabled": true,
    "filesystem": {
      "allowWrite": ["/tmp/build"],
      "denyWrite": ["/etc", "/usr/local/bin"],
      "denyRead": ["~/.aws/credentials"]
    },
    "network": {
      "allowedDomains": ["*.internal.example.com"]
    }
  }
}
```

Each overlay defines its own sandbox fragment in `compliance/<overlay>/sandbox.json.tmpl`
(new template file, processed by `policy_emit_sandbox`).

#### Managed-settings platform paths (from official CC docs, HIGH confidence)

| Platform | Path |
|----------|------|
| macOS | `/Library/Application Support/ClaudeCode/managed-settings.json` |
| Linux/WSL | `/etc/claude-code/managed-settings.json` |
| Windows | `C:\Program Files\ClaudeCode\managed-settings.json` |
| Drop-in dir | same location + `managed-settings.d/` (alphabetically merged) |

`conjure audit --policy-check` verifies that the target's `.claude/settings.json` sandbox block
matches the overlay's expected policy fragment (drift detection for compliance policy).

#### New template files per overlay

Each of the 4 overlays gains:
```
compliance/<overlay>/
  apply.sh              — MODIFIED: add --emit-policy flag path
  sandbox.json.tmpl     — NEW: sandbox block for this overlay
  managed-settings.json.tmpl — NEW: managed-settings artifact template
  plist.tmpl            — NEW: macOS MDM plist (--mdm flag)
```

---

### Area 3: promptfoo Eval + Budget Linter

#### `cmd_eval` in `cli/conjure` (NEW dispatcher entry)

```
conjure eval [--suite <name>] [--gate] [--dry-run] [target]
```

Thin wrapper → `bash scripts/eval.sh`.

#### `scripts/eval.sh` (NEW worker)

**What it does:**
- Checks for `npx` (already expected — Node.js is a runtime dep for hooks)
- Runs `npx --yes promptfoo@latest eval -c <spec>` where `<spec>` is one of:
  - A named suite from `templates/evals/<suite>/promptfooconfig.yaml`
  - The target repo's `.claude/evals/promptfooconfig.yaml` (installed by `conjure init`)
- `--gate` flag: exit 2 if any assertions fail (for CI use)
- Results written to `.claude/evals/results/` (gitignored by convention)
- All writes via `mutate_write` (results output dir creation)

**No new runtime dep.** `npx --yes promptfoo` is invoked on demand; promptfoo is not added to
`dependencies`. This matches the existing `npx --yes ctx7@latest` pattern used in documentation
lookups and keeps `dependencies: {}` empty.

#### `templates/evals/` (NEW directory)

```
templates/evals/
  promptfoo/             — core eval suite (installed to .claude/evals/ by conjure init)
    promptfooconfig.yaml — base config: providers, prompts, assertions
    tests/               — YAML test case files
      skill-adherence.yaml     — tests skills fire correctly for trigger phrases
      hook-blocking.yaml       — tests destructive-bash hook blocks known patterns
      size-cap-adherence.yaml  — tests CLAUDE.md stays within cap after edits
  hipaa/                 — compliance eval suite
    promptfooconfig.yaml
    tests/phi-no-leak.yaml
  soc2/
    promptfooconfig.yaml
    tests/audit-log.yaml
```

`conjure init` installs `templates/evals/promptfoo/` into `$target/.claude/evals/`.
`conjure eval --suite hipaa` runs the HIPAA-specific suite.

#### Budget linter added to `scripts/audit-setup.sh` (MODIFIED)

New flag: `conjure audit --budget-check [--budget-tokens N]`

When `CONJURE_BUDGET_CHECK=1`:
- Counts estimated tokens for CLAUDE.md + all skills (existing chars/4 heuristic)
- Compares against per-turn budget threshold (default 20K tokens, configurable)
- Warns if any skill exceeds 5K tokens (high single-skill load)
- Outputs budget report section in audit output

No new lib; adds ~40 lines to `audit-setup.sh` in the existing audit loop, reusing the
`$TOTAL_CHARS` and chars/4 estimation already present.

#### CI job structure

Eval is designed as a CI job, not a pre-commit hook (too slow for per-commit). The
`conjure update --cron` template (already written to `.github/workflows/conjure-update.yml`)
gets a sibling `conjure eval --gate` step added to the generated workflow template.

```yaml
# Fragment added to templates/workflows/conjure-eval.yml.tmpl
jobs:
  conjure-eval:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Run eval suite
        run: CONJURE_HOME=conjure-src conjure-src/cli/conjure eval --gate
```

---

### Area 4: Schema-Version-Aware Audit

#### `lib/cc-schema.json` (NEW bundled schema table)

A JSON file maintained in the kit (not fetched at runtime) mapping CC version ranges to:
- Known hook events
- Known settings keys
- Known `disallowed-tools` values
- Minimum-version-required features

```json
{
  "schema_version": "1",
  "updated": "2026-06-03",
  "known_hook_events": [
    "PreToolUse", "PostToolUse", "Stop", "SessionStart",
    "UserPromptExpansion", "ConfigChange", "Notification",
    "SubagentStop", "PreCompact"
  ],
  "known_settings_keys": [
    "permissions", "hooks", "env", "sandbox", "mcpServers",
    "includeCoAuthoredBy", "cleanupPeriodDays", "disabledMcpjsonServers",
    "deniedMcpServers", "policyHelper", "allowManagedHooksOnly",
    "extraKnownMarketplaces", "strictKnownMarketplaces",
    "skillOverrides", "enabledPlugins"
  ],
  "version_gates": {
    "policyHelper": "2.1.136",
    "skillOverrides": "2.1.129",
    "displayName": "2.1.143",
    "defaultEnabled": "2.1.154"
  },
  "minimum_conjure_cc_version": "2.1.117"
}
```

**Why bundled, not fetched:** Runtime network fetches violate the zero-egress-in-CI constraint
and the no-curl-sh safety rule. The schema table is small (~2KB), human-auditable, and versioned
with the kit. It is updated at Conjure release time when new CC schema changes are detected.

**Update path:** `conjure update` includes a check against a published schema manifest
(same mechanism as kit updates) and emits a warning if `cc-schema.json` is older than 30 days.
This is advisory only; the audit still runs.

#### Modified: `scripts/audit-setup.sh` (MODIFIED)

New section: schema-version-aware validation. Added when `CONJURE_SCHEMA_CHECK=1`
(or default-on after a flag stabilization period):

```bash
# Schema-aware audit (sourced from lib/cc-schema.json via jq)
# 1. Detect installed CC version: claude --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+'
# 2. Load cc-schema.json known_hook_events, known_settings_keys
# 3. For each hook event in settings.json: warn if not in known_hook_events
# 4. For each top-level settings key: warn if not in known_settings_keys
# 5. For version-gated features: compare CC version vs version_gates[key]
# 6. Check for disallowed-tools / disabledMcpjsonServers drift
```

CC version detection:
```bash
CC_VERSION="$(claude --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo 'unknown')"
```

If `claude` not on PATH (CI without CC installed), schema check is skipped with a warning,
not a failure. This matches the existing `jq` skip pattern.

#### `lib/cc-schema.json` update cadence

`scripts/audit-setup.sh` compares the `updated` field in `lib/cc-schema.json` against
`date +%Y-%m-%d` (90-day threshold). If stale, emits advisory: "cc-schema.json is >90 days
old — run `conjure update` to refresh." This is a WARN (exit 1), not an ERR (exit 2).

---

### Area 5: Cross-Repo / Workspace Orchestration

This is the most complex area. The architecture must address:
- Per-repo snapshot using existing `lib/snapshot.sh` primitives
- Aggregate rollback semantics: partial failure in repo N must roll back repos 0..N-1
- State durability: a SIGKILL mid-workspace-run must allow `--resume` recovery
- Reporting: per-repo status + aggregate summary

#### `conjure-workspace.json` (NEW per-workspace manifest)

Not stored in any single repo — lives in a workspace root directory alongside all repo dirs:

```json
{
  "schema_version": "1",
  "name": "my-org-workspace",
  "conjure_version": "0.7.0",
  "repos": [
    {
      "name": "api",
      "path": "./api",
      "profile": "node",
      "overlay": null,
      "conjure_ops": ["init", "adopt", "audit"]
    },
    {
      "name": "web",
      "path": "./web",
      "profile": "react",
      "overlay": "soc2",
      "conjure_ops": ["init", "audit"]
    }
  ],
  "rollback_policy": "all-or-nothing",
  "parallel": false
}
```

`rollback_policy` values:
- `all-or-nothing`: if any repo fails, roll back all previously-applied repos (the hard default)
- `best-effort`: continue on failure, report failed repos, no rollback (for audit-only runs)

`parallel: false` is the default and only supported value in v0.7.0. True parallel would require
snapshot/rollback coordination across concurrent bash processes which introduces race conditions
on shared `lib/mutate.sh` state. Parallel is `best-effort` mode only and deferred.

#### `cmd_workspace` in `cli/conjure` (NEW dispatcher entry)

```
conjure workspace [--file <conjure-workspace.json>] [--dry-run] [--rollback] [--resume] [--porcelain]
```

Thin wrapper → `bash scripts/workspace.sh`.

#### `scripts/workspace.sh` (NEW worker)

**Pipeline:**

```
Step 0: Load + validate workspace manifest (jq schema check)
  write .conjure-workspace-state.json (durable crash state)

Step 1: Pre-flight all repos
  for each repo in manifest:
    verify path exists
    cmd_preflight for repo
  abort if any preflight fails (before any mutations)

Step 2: Snapshot all repos
  for each repo in manifest:
    source lib/snapshot.sh
    snapshot_create $repo_path $workspace_root/.conjure-workspace-backups/$repo_name/
    record CONJURE_SNAPSHOT_PATH in .conjure-workspace-state.json
    (failures here abort entire workspace run — no partial state)

Step 3: Execute ops per repo (sequential)
  for each repo in manifest:
    for each op in repo.conjure_ops:
      execute: CONJURE_HOME=$CONJURE_HOME DRY_RUN=$DRY_RUN \
               bash $CONJURE_HOME/cli/conjure $op [flags] $repo_path
      record result in .conjure-workspace-state.json
      if op exits 2: trigger aggregate_rollback; exit 2

Step 4: Aggregate report
  print per-repo status table
  print overall result: PASS / PARTIAL / FAIL
  write workspace-report.json
```

**Aggregate rollback (the deferred hard part):**

```
aggregate_rollback() is called when Step 3 fails on repo N:
  for each repo that has status=applied in .conjure-workspace-state.json (repos 0..N-1):
    snapshot_rollback $recorded_snapshot_path $repo_path
    record status=rolled-back in .conjure-workspace-state.json
  repo N itself: snapshot_rollback if snapshot was taken; else skip (no mutations)
  print: "Workspace rolled back. All repos restored to pre-workspace state."
  exit 2
```

Key design: `snapshot_create` for each repo happens in Step 2 (before ANY op execution),
so a failure in repo 3 can always roll back repos 0, 1, 2 from their pre-Step-2 snapshots.
This is the same snapshot-before-mutate invariant as `scripts/adopt.sh` Step 1, applied
at workspace scale.

**Durable state file (crash recovery):**

`.conjure-workspace-state.json` is written before each repo operation and updated after:

```json
{
  "schema_version": "1",
  "workspace": "my-org-workspace",
  "started_at": "2026-06-03T10:00:00Z",
  "phase": "ops",
  "repos": [
    {
      "name": "api",
      "snapshot_path": "/abs/.conjure-workspace-backups/api/conjure-adopt-20260603T100001Z",
      "status": "applied",
      "ops_applied": ["init", "adopt"],
      "op_failed": null
    },
    {
      "name": "web",
      "snapshot_path": "/abs/.conjure-workspace-backups/web/conjure-adopt-20260603T100030Z",
      "status": "running",
      "ops_applied": ["init"],
      "op_failed": null
    }
  ]
}
```

`--resume` reads this file and skips repos with `status: applied`; re-runs from the first
`status: running` or `status: failed` entry. `--rollback` reads all `snapshot_path` values
and calls `snapshot_rollback` for each repo with `status: applied`.

#### `lib/workspace.sh` (NEW shared lib)

Functions sourced by `scripts/workspace.sh`:
- `workspace_load <manifest_path>` — parse + validate conjure-workspace.json via jq
- `workspace_state_init <workspace_root>` — write initial .conjure-workspace-state.json
- `workspace_state_update <repo_name> <phase> <status>` — atomic append via mutate_write
- `workspace_aggregate_rollback <state_file>` — iterate applied repos, call snapshot_rollback
- `workspace_report <state_file>` — print per-repo table + aggregate result

`lib/workspace.sh` sources `lib/snapshot.sh` (for snapshot_rollback) and `lib/log.sh`
(for workspace-level log entries). All writes via `mutate_write`.

#### Backup location for workspace snapshots

`$workspace_root/.conjure-workspace-backups/<repo-name>/conjure-adopt-<ts>/`

Separate from the per-repo `.conjure-adopt-backups/` to avoid confusion when a repo is also
managed individually. `.conjure-workspace-backups/` is added to the workspace root's `.gitignore`.

---

## Component Interaction Map (v0.7.0 complete)

```
┌────────────────────────────────────────────────────────────────────────────────────────┐
│  ENTRYPOINTS                                                                            │
│  ┌─────────────────────────────────────────────────────────────────────────────────┐   │
│  │  cli/conjure  (bash dispatcher)                         [existing + MODIFIED]    │   │
│  │   ... all v0.6.0 subcommands unchanged ...                                     │   │
│  │   emit-plugin [--plugin-dir] [--strict] [--dry-run]     [NEW — v0.7.0]        │   │
│  │   eval [--suite] [--gate] [--dry-run]                   [NEW — v0.7.0]        │   │
│  │   workspace [--file] [--dry-run] [--rollback] [--resume][NEW — v0.7.0]        │   │
│  └─────────────────────────────────────────────────────────────────────────────────┘   │
├────────────────────────────────────────────────────────────────────────────────────────┤
│  WORKER SCRIPTS (subprocess via bash scripts/*.sh)                                      │
│  ┌──────────────────────────────────┐  ┌──────────────────────────────────────────┐   │
│  │  v0.6.0 workers (unchanged)       │  │  emit-plugin.sh            [NEW]         │   │
│  │  adopt.sh                        │  │   reads .claude/ → writes .claude-plugin/ │   │
│  │  audit-setup.sh ── MODIFIED ──┐  │  │   lib/plugin-helpers.sh sourced           │   │
│  │  check.sh                     │  │  │   mutate_write for all outputs            │   │
│  │  resolve.sh                   │  │  ├──────────────────────────────────────────┤   │
│  │  publish-plugin.sh ─extract→  │  │  │  eval.sh                   [NEW]         │   │
│  │  publish-skill.sh              │  │  │   npx promptfoo eval -c <spec>           │   │
│  │  init-project.sh               │  │  │   --gate flag: exit 2 on fail            │   │
│  │  preflight.sh                  │  │  │   writes results/ via mutate_write       │   │
│  └──────────────────────────────────┘  ├──────────────────────────────────────────┤   │
│                                         │  workspace.sh              [NEW]         │   │
│    audit-setup.sh adds:                 │   Step 0: load manifest + init state     │   │
│    - schema-version check               │   Step 1: preflight all repos            │   │
│    - budget-linter section              │   Step 2: snapshot all repos             │   │
│                                         │   Step 3: execute ops sequentially       │   │
│    compliance/*/apply.sh adds:          │   Step 4: aggregate report               │   │
│    - --emit-policy flag path            │   aggregate_rollback() on any failure    │   │
│    - sandbox.json.tmpl processing       │   lib/workspace.sh sourced              │   │
│    - managed-settings.json emit         │   lib/snapshot.sh sourced (reused)      │   │
│    - MDM plist/registry (--mdm)         └──────────────────────────────────────────┘   │
├────────────────────────────────────────────────────────────────────────────────────────┤
│  SHARED LIB (sourced, not dispatched)                                                   │
│  ┌──────────────────────────────────────────────────────────────────────────────────┐  │
│  │ lib/mutate.sh   [existing — UNCHANGED]                                           │  │
│  │  THE write chokepoint — ALL mutations route here — invariant preserved           │  │
│  └──────────────────────────────────────────────────────────────────────────────────┘  │
│  ┌──────────────────────────────────────────────────────────────────────────────────┐  │
│  │ lib/snapshot.sh  [existing — UNCHANGED; REUSED by workspace.sh]                  │  │
│  │  snapshot_create / snapshot_rollback / snapshot_list                            │  │
│  └──────────────────────────────────────────────────────────────────────────────────┘  │
│  ┌──────────────────────────────────────────────────────────────────────────────────┐  │
│  │ lib/plugin-helpers.sh  [NEW — v0.7.0]                                            │  │
│  │  plugin_update_marketplace / plugin_update_plugin_json                          │  │
│  │  plugin_inject_extra_marketplace / plugin_inject_strict_marketplace             │  │
│  │  sourced by: emit-plugin.sh + publish-plugin.sh (refactored)                    │  │
│  └──────────────────────────────────────────────────────────────────────────────────┘  │
│  ┌──────────────────────────────────────────────────────────────────────────────────┐  │
│  │ lib/policy-helpers.sh  [NEW — v0.7.0]                                            │  │
│  │  policy_emit_sandbox / policy_emit_managed_settings                             │  │
│  │  policy_emit_plist / policy_emit_registry_hive / policy_emit_drop_in           │  │
│  │  sourced by: all 4 compliance/*/apply.sh                                        │  │
│  └──────────────────────────────────────────────────────────────────────────────────┘  │
│  ┌──────────────────────────────────────────────────────────────────────────────────┐  │
│  │ lib/workspace.sh  [NEW — v0.7.0]                                                 │  │
│  │  workspace_load / workspace_state_init / workspace_state_update                │  │
│  │  workspace_aggregate_rollback / workspace_report                               │  │
│  │  sources: lib/snapshot.sh + lib/log.sh                                         │  │
│  └──────────────────────────────────────────────────────────────────────────────────┘  │
│  ┌──────────────────────────────────────────────────────────────────────────────────┐  │
│  │ lib/cc-schema.json  [NEW — v0.7.0]                                               │  │
│  │  bundled schema table: known_hook_events / known_settings_keys / version_gates  │  │
│  │  read by: scripts/audit-setup.sh (schema-version-aware check section)           │  │
│  └──────────────────────────────────────────────────────────────────────────────────┘  │
│  ┌──────────────────────────────────────────────────────────────────────────────────┐  │
│  │ lib/inventory.sh / lib/log.sh / lib/merge.sh / lib/caps.sh [existing — unchanged]│  │
│  └──────────────────────────────────────────────────────────────────────────────────┘  │
├────────────────────────────────────────────────────────────────────────────────────────┤
│  TEMPLATES + COMPLIANCE (new files)                                                     │
│  ┌──────────────────────────────────────────────────────────────────────────────────┐  │
│  │ templates/evals/          [NEW — v0.7.0]                                         │  │
│  │   promptfoo/promptfooconfig.yaml + tests/                                        │  │
│  │   hipaa/ soc2/ gdpr/ pci/ (compliance eval suites)                              │  │
│  └──────────────────────────────────────────────────────────────────────────────────┘  │
│  ┌──────────────────────────────────────────────────────────────────────────────────┐  │
│  │ compliance/<overlay>/sandbox.json.tmpl     [NEW per overlay — v0.7.0]            │  │
│  │ compliance/<overlay>/managed-settings.json.tmpl  [NEW per overlay — v0.7.0]     │  │
│  │ compliance/<overlay>/plist.tmpl            [NEW per overlay, optional]           │  │
│  └──────────────────────────────────────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────────────────────────────────┘
```

---

## New vs Modified Files — Explicit List

### NEW FILES

| File | Type | Purpose |
|------|------|---------|
| `lib/plugin-helpers.sh` | library | jq transforms for plugin.json / marketplace.json; shared by emit-plugin.sh + publish-plugin.sh |
| `lib/policy-helpers.sh` | library | emit sandbox{} block, managed-settings.json, MDM artifacts; shared by all 4 compliance overlays |
| `lib/workspace.sh` | library | workspace load/state/rollback/report; sources snapshot.sh + log.sh |
| `lib/cc-schema.json` | data | bundled CC schema table: hook events, settings keys, version gates |
| `scripts/emit-plugin.sh` | worker | generates .claude-plugin/ from harness scaffold; wires extraKnownMarketplaces |
| `scripts/eval.sh` | worker | runs promptfoo via npx; --gate exits 2 on failure; writes results/ |
| `scripts/workspace.sh` | worker | workspace orchestration: preflight → snapshot → ops → aggregate rollback |
| `templates/evals/` | templates | promptfoo eval suites installed by conjure init; 1 base + 4 compliance |
| `compliance/*/sandbox.json.tmpl` | data | sandbox block template per overlay (4 files) |
| `compliance/*/managed-settings.json.tmpl` | data | managed-settings template per overlay (4 files) |
| `compliance/*/plist.tmpl` | data | macOS MDM plist template per overlay (4 files, optional) |

### MODIFIED FILES

| File | Change | Why |
|------|--------|-----|
| `cli/conjure` | add `cmd_emit_plugin`, `cmd_eval`, `cmd_workspace` + dispatch entries + usage() | 3 new subcommands |
| `scripts/audit-setup.sh` | add schema-version check section + budget-linter section | areas 3 + 4 |
| `scripts/publish-plugin.sh` | refactor jq transforms into lib/plugin-helpers.sh; source that lib | deduplicate with emit-plugin.sh |
| `compliance/hipaa/apply.sh` | add --emit-policy flag path; source lib/policy-helpers.sh | area 2 |
| `compliance/soc2/apply.sh` | same | area 2 |
| `compliance/gdpr/apply.sh` | same | area 2 |
| `compliance/pci/apply.sh` | same | area 2 |

### UNCHANGED FILES (confirmed)

| File | Reason |
|------|--------|
| `lib/mutate.sh` | API complete; invariant preserved by all new components |
| `lib/snapshot.sh` | reused by workspace.sh without modification |
| `lib/log.sh` | reused by workspace.sh without modification |
| `lib/inventory.sh` | not involved in v0.7.0 features |
| `lib/merge.sh` | not involved |
| `lib/caps.sh` | not modified; budget linter in audit-setup.sh uses CLAUDE_MD_CAP directly |
| `scripts/adopt.sh` | not modified; called by workspace.sh as a subprocess |
| `scripts/check.sh` | not modified; available as workspace op |
| `scripts/init-project.sh` | not modified; called by workspace.sh as subprocess |

---

## Data Flow: End-to-End for Each Area

### Plugin Emission Flow

```
USER: conjure emit-plugin [--strict] [target]
  │
  ▼
cli/conjure cmd_emit_plugin → scripts/emit-plugin.sh $target
  │
  ├─ read $target/.claude/skills/ → enumerate skills paths
  ├─ read $target/.claude/agents/ → enumerate agent paths
  ├─ read $target/.claude/hooks/  → enumerate hook files
  ├─ read $target/.claude/settings.json → current hooks block
  │
  ├─ source lib/plugin-helpers.sh
  ├─ plugin_update_plugin_json → writes $target/.claude-plugin/plugin.json
  ├─ plugin_update_marketplace  → writes $target/.claude-plugin/marketplace.json
  ├─ plugin_inject_extra_marketplace → writes extraKnownMarketplaces into settings.json
  │   (all via mutate_write)
  │
  └─ mutate_summary; exit 0
```

### Managed-Settings / Policy Emission Flow

```
USER: conjure init --overlay=hipaa [target]  OR  conjure refresh-overlay [target]
  │
  ▼
compliance/hipaa/apply.sh --emit-policy $target
  │
  ├─ source lib/policy-helpers.sh
  ├─ source lib/mutate.sh
  │
  ├─ (existing) append CLAUDE.md.fragment → CLAUDE.md
  ├─ (existing) copy pre-commit-phi-scan.sh → .claude/hooks/
  ├─ (existing) copy CONTROLS.md → docs/compliance/
  │
  ├─ (NEW) policy_emit_sandbox $target/.claude/settings.json compliance/hipaa/sandbox.json.tmpl
  │     jq merge sandbox{} into settings.json → mutate_write
  │
  ├─ (NEW --mdm) policy_emit_managed_settings $output_dir compliance/hipaa/managed-settings.json.tmpl
  │     jq render → mutate_write managed-settings.json
  │
  └─ (NEW --mdm) policy_emit_plist $output_dir compliance/hipaa/plist.tmpl
        render → mutate_write managed-settings.d/10-hipaa.json + plist artifact
```

### Workspace Orchestration Flow (the hard path)

```
USER: conjure workspace --file ./conjure-workspace.json [--dry-run]
  │
  ▼
scripts/workspace.sh
  │
  ├─ Step 0: workspace_load → validate manifest (jq schema)
  │    workspace_state_init → write .conjure-workspace-state.json
  │
  ├─ Step 1: preflight_all
  │    for each repo:
  │      bash $CONJURE_HOME/cli/conjure preflight $repo_path
  │      record result → state update
  │    any failure → exit 2 (no mutations yet)
  │
  ├─ Step 2: snapshot_all
  │    for each repo:
  │      snapshot_create $repo_path $workspace_root/.conjure-workspace-backups/$name/
  │      workspace_state_update $name snapshot $snapshot_path
  │    any failure → exit 2 (partial snapshots logged; warn user to check)
  │
  ├─ Step 3: execute_ops (sequential)
  │    for each repo (in manifest order):
  │      for each op in repo.conjure_ops:
  │        DRY_RUN=$DRY_RUN bash $CONJURE_HOME/cli/conjure $op $repo_path
  │        rc=$?
  │        workspace_state_update $name op_applied $op
  │        if rc == 2:
  │          workspace_aggregate_rollback .conjure-workspace-state.json
  │          exit 2
  │
  └─ Step 4: workspace_report → print table + write workspace-report.json
       exit 0

aggregate_rollback() called on Step 3 failure:
  for each repo with status=applied in state file (newest-first for safety):
    snapshot_rollback $recorded_snapshot_path $repo_path
    workspace_state_update $name status rolled-back
  print: "All applied repos rolled back."
  exit 2
```

### Schema-Aware Audit Flow

```
USER: conjure audit [target]
  │
  ▼
scripts/audit-setup.sh $target
  │
  ├─ (existing audit checks: size caps, frontmatter, hooks JSON, etc.)
  │
  └─ (NEW) schema-version-aware section:
       CC_VERSION=$(claude --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
       if [ -z "$CC_VERSION" ]: warn "CC not found — schema check skipped"
       else:
         SCHEMA=$(jq . $CONJURE_HOME/lib/cc-schema.json)
         known_events=$(echo $SCHEMA | jq -r '.known_hook_events[]')
         for event in $(jq -r '.hooks | keys[]' .claude/settings.json):
           if not in known_events: warn "Unknown hook event: $event (CC $CC_VERSION)"
         for key in $(jq -r 'keys[]' .claude/settings.json):
           if not in known_settings_keys: warn "Unknown settings key: $key"
         for feature, min_ver in version_gates:
           if feature present in settings.json AND CC_VERSION < min_ver:
             warn "Feature $feature requires CC $min_ver (installed: $CC_VERSION)"
         check schema freshness: if updated > 90 days ago: warn "cc-schema.json stale"
```

---

## Dependency-Ordered Build Sequence

Dependencies between the 5 areas determine build order. The key constraint: workspace
orchestration calls `conjure init`, `conjure adopt`, `conjure audit`, `conjure check`
as subprocesses — so those commands must be stable before workspace.sh is written.
Plugin helpers must be extracted before emit-plugin.sh is written.

### Step 1 — `lib/plugin-helpers.sh` + refactor `publish-plugin.sh`

**Why first:** Shared jq transforms needed by both `emit-plugin.sh` (new) and
`publish-plugin.sh` (existing, refactored). Extracting the lib first gives a stable
interface before emit-plugin.sh is written. This is a small, low-risk refactor.

Requires: `lib/mutate.sh` (shipped)
Unblocks: Step 2 (emit-plugin.sh)

---

### Step 2 — `scripts/emit-plugin.sh` + `cmd_emit_plugin` in `cli/conjure`

**Why second:** Plugin emission is the foundation for the marketplace registration that
workspace orchestration may rely on (repos emitting their own plugins). Plugin emission
is also the simplest new command — good to ship and stabilize early.

Requires: Step 1 (lib/plugin-helpers.sh)
Unblocks: Step 7 (workspace can call emit-plugin as an op)

---

### Step 3 — `lib/cc-schema.json` + schema-version section in `audit-setup.sh`

**Why third:** Audit changes are targeted and isolated (additive section in
audit-setup.sh). Schema table is a data file with no code dependencies. Building this
before policy-helpers keeps the compliance area modular.

Requires: `scripts/audit-setup.sh` (shipped); `jq` (preflight dep)
Unblocks: Step 5 (compliance policy may include schema-version check)

---

### Step 4 — `lib/policy-helpers.sh` + compliance overlay extensions

**Why fourth:** Policy helpers depend only on `lib/mutate.sh` (shipped). The 4 overlay
`apply.sh` modifications are parallel within this step (no inter-overlay dependencies).
Build hipaa first (most complex: PHI rules) to validate the pattern, then soc2/gdpr/pci.

Requires: `lib/mutate.sh` (shipped), compliance templates (sandbox.json.tmpl etc.)
Unblocks: Step 7 (workspace can call --emit-policy as a workspace op)

---

### Step 5 — `templates/evals/` + `scripts/eval.sh` + `cmd_eval` + budget linter

**Why fifth:** eval.sh has no dependencies on the new libs — only on `npx`. The budget
linter in audit-setup.sh is additive. These are independent of workspace and plugin.
Placing eval here (before workspace) allows workspace to include `eval` as a supported op.

Requires: `scripts/audit-setup.sh` (for budget linter section); `npx` (runtime)
Unblocks: Step 6 (workspace can run eval as an op); CI integration

---

### Step 6 — `lib/workspace.sh` + `scripts/workspace.sh` + `cmd_workspace` in `cli/conjure`

**Why last among new features:** workspace.sh calls every other conjure command as a
subprocess. All per-repo conjure ops must be stable before the workspace layer can be
written. The aggregate rollback design (the hardest part) requires `lib/snapshot.sh`
(shipped v0.6.0 — confirmed stable with 467 passing tests) and the durable state file.

Requires: Steps 1–5 stable; `lib/snapshot.sh` (shipped); `lib/log.sh` (shipped)
Unblocks: end-to-end workspace user story

---

### Step 7 — Integration tests for all 5 areas

Per-area test fixtures added to `tests/run.sh` (graceful-red blocks before each feature).
Workspace fixture: `tests/fixtures/_workspace-trio/` (3 small repos to orchestrate).
Eval fixture: mock promptfoo invocation (stub npx script for CI speed).

Requires: Steps 1–6
Unblocks: CI coverage of all v0.7.0 capabilities

---

### Build order summary table

| Step | Work item | New / Modified files | Key dependency | Unblocks |
|------|-----------|----------------------|----------------|----------|
| 1 | lib/plugin-helpers.sh + publish-plugin.sh refactor | `lib/plugin-helpers.sh` (N), `scripts/publish-plugin.sh` (M) | lib/mutate.sh (shipped) | Step 2 |
| 2 | emit-plugin.sh + cmd_emit_plugin | `scripts/emit-plugin.sh` (N), `cli/conjure` (M) | Step 1 | Step 6 workspace ops |
| 3 | lib/cc-schema.json + audit schema-version section | `lib/cc-schema.json` (N), `scripts/audit-setup.sh` (M) | audit-setup.sh (shipped) | Step 5 audit budget |
| 4 | lib/policy-helpers.sh + 4 overlay extensions + templates | `lib/policy-helpers.sh` (N), `compliance/*/apply.sh` (M×4), `compliance/*/sandbox.json.tmpl` (N×4), `compliance/*/managed-settings.json.tmpl` (N×4) | lib/mutate.sh (shipped) | Step 6 workspace ops |
| 5 | templates/evals/ + eval.sh + cmd_eval + budget linter | `templates/evals/` (N), `scripts/eval.sh` (N), `cli/conjure` (M), `scripts/audit-setup.sh` (M) | audit-setup.sh (shipped), npx | Step 6 workspace ops |
| 6 | lib/workspace.sh + workspace.sh + cmd_workspace | `lib/workspace.sh` (N), `scripts/workspace.sh` (N), `cli/conjure` (M) | Steps 1–5; lib/snapshot.sh (shipped) | Full workspace UX |
| 7 | Integration tests for all areas | `tests/run.sh` (M), `tests/fixtures/_workspace-trio/` (N), eval stubs (N) | Steps 1–6 | CI coverage |

N = New file, M = Modified file

---

## Anti-Patterns to Avoid

### Anti-Pattern 1: Duplicating template content into the plugin dir

**What people do:** `cp -r templates/skills/ .claude-plugin/skills/` — copies skill templates
into the plugin directory, creating a second source of truth.
**Why it's wrong:** When skill templates are updated in Conjure, the plugin dir copy diverges.
The `conjure update` 3-way merge only handles the target repo's `.claude/skills/`, not
the plugin copy. Size drift becomes unmaintainable.
**Do this instead:** `plugin.json` references skill paths as relative paths pointing to
the existing `.claude/skills/` in the harness. The plugin dir is a view, not a copy.
`emit-plugin.sh` writes path references only.

---

### Anti-Pattern 2: Fetching the CC schema at runtime

**What people do:** `curl https://json.schemastore.org/claude-code-settings.json` in
`audit-setup.sh` to get the current schema.
**Why it's wrong:** Violates the no-egress-in-CI constraint; fails in air-gapped envs;
introduces non-determinism (schema can change between runs); `curl | parse` is a
foot-gun pattern.
**Do this instead:** Bundle `lib/cc-schema.json` in the kit. Update it at Conjure release
time when schema changes are detected. Emit a staleness warning (>90 days) to prompt
users to run `conjure update`.

---

### Anti-Pattern 3: Parallel workspace execution without aggregate rollback support

**What people do:** Run workspace ops in parallel (background subshells per repo) for speed.
**Why it's wrong:** Parallel execution means multiple repos are "in-flight" simultaneously.
If repo 4 fails while repos 2, 3 are still running, you cannot cleanly roll back all of
them — some may be partially applied. The aggregate rollback design (snapshot-all-then-execute)
only works sequentially: repo N's snapshot is taken before repo N's ops begin.
**Do this instead:** Default to `parallel: false`. Support `parallel: true` only with
`rollback_policy: best-effort` (no rollback, just report failures). Never offer
all-or-nothing rollback with parallel execution — the invariant cannot be maintained.

---

### Anti-Pattern 4: Emitting managed-settings to the repo's .claude/settings.json and calling it MDM

**What people do:** Write the sandbox{} block and managed-settings.json into `.claude/settings.json`
and tell teams "this is your MDM policy."
**Why it's wrong:** `.claude/settings.json` is a project-level file overridable by users.
MDM requires system-level paths (`/Library/Application Support/ClaudeCode/managed-settings.json`)
to be enforceable. Writing to project-level only creates a false sense of enforcement.
**Do this instead:** `--emit-policy` writes sandbox{} to `.claude/settings.json` (project
enforcement). `--mdm` writes to a separate output dir for admin deployment. The audit warns
when `sandbox{}` is absent from project settings even though an overlay was applied.

---

### Anti-Pattern 5: Workspace state file only in memory (no crash durability)

**What people do:** Track per-repo snapshot paths in shell variables during workspace execution.
**Why it's wrong:** If the process is killed mid-run (SIGKILL, OOM, network loss on remote),
the snapshot paths are lost. On `--resume`, no rollback is possible for applied repos.
**Do this instead:** Write `.conjure-workspace-state.json` before each repo operation and
update it after. Every snapshot path is persisted to disk. `--rollback` reads this file
and can restore any repo that has a recorded snapshot path, even after a crash.

---

## Integration Points

### lib/snapshot.sh → workspace.sh (direct reuse, zero modification)

`workspace.sh` sources `lib/snapshot.sh` and calls `snapshot_create` / `snapshot_rollback`
with workspace-scoped backup root. The snapshot functions are parameterized (backup_root
is a caller argument), so they work identically for workspace backups as for adopt backups.
No changes to `lib/snapshot.sh` required.

### scripts/publish-plugin.sh → lib/plugin-helpers.sh (refactor, not replacement)

`publish-plugin.sh` is refactored to source `lib/plugin-helpers.sh` for the jq transforms.
All existing behavior is preserved; the refactor only extracts 2-3 jq expressions into
named functions. This is a mechanical refactor with no behavior change, testable by
running the existing `publish-plugin.sh` tests before and after.

### compliance/apply.sh → lib/policy-helpers.sh (additive sourcing)

Each overlay's `apply.sh` gains `source "$CONJURE_HOME/lib/policy-helpers.sh"` and a
`--emit-policy` code path. The existing code path (without `--emit-policy`) runs exactly
as before. No behavior change for existing users.

### workspace.sh → cli/conjure (subprocess call-back)

`workspace.sh` calls other conjure subcommands as subprocesses:
```bash
bash "$CONJURE_HOME/cli/conjure" $op [flags] "$repo_path"
```
This is the same pattern as `adopt.sh` calling `audit-setup.sh`. The CLI is the
stable interface; workspace never sources scripts directly (to avoid environment
variable leakage between repos).

### eval.sh → npx promptfoo (runtime, no install dep)

`eval.sh` uses `npx --yes promptfoo@latest eval`. The `--yes` flag installs promptfoo
on first use (npx cache), requiring no pre-install step. This is consistent with the
existing `npx --yes ctx7@latest` pattern in the development tooling.

---

## Sources

- `cli/conjure` (full content read this session) — HIGH confidence
- `lib/mutate.sh` (full content read this session) — HIGH confidence
- `lib/snapshot.sh` (full content read this session) — HIGH confidence
- `lib/caps.sh` (full content read this session) — HIGH confidence
- `scripts/audit-setup.sh` (full content read this session) — HIGH confidence
- `scripts/publish-plugin.sh` (full content read this session) — HIGH confidence
- `compliance/hipaa/apply.sh` (read this session) — HIGH confidence
- `.claude-plugin/marketplace.json` + `plugin.json` (read this session) — HIGH confidence
- `.planning/PROJECT.md` v0.7.0 milestone context (read this session) — HIGH confidence
- `.planning/research/ARCHITECTURE.md` v0.6.0 (read this session; carried forward) — HIGH confidence
- Official CC docs: settings (sandbox, managed-settings, hook events, schema keys) — HIGH confidence ([source](https://code.claude.com/docs/en/settings))
- Official CC docs: plugin marketplaces (marketplace.json schema, extraKnownMarketplaces, strictKnownMarketplaces) — HIGH confidence ([source](https://code.claude.com/docs/en/plugin-marketplaces))
- Official CC docs: hooks guide (hook events list including ConfigChange, Notification) — HIGH confidence ([source](https://code.claude.com/docs/en/hooks-guide))
- promptfoo CI/CD integration docs (npx eval, GitHub Action, YAML spec format) — MEDIUM confidence ([source](https://www.promptfoo.dev/docs/integrations/ci-cd/))
- CC settings gist (April 2026, v2.1.104 reference) — MEDIUM confidence ([source](https://gist.github.com/mculp/c082bd1e5a439410158974de90c89db7))

---
*Architecture research for: Conjure v0.7.0 Plugin-native + Policy-grade integration*
*Researched: 2026-06-03*
