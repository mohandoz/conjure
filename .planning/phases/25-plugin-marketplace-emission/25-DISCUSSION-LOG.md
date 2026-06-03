# Phase 25: Plugin + Marketplace Emission - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-03
**Phase:** 25-plugin-marketplace-emission
**Areas discussed:** Command identity, Marketplace source, Validate gate, Settings wiring

---

## Command identity

| Option | Description | Selected |
|--------|-------------|----------|
| Separate, shared lib | Distinct subcommands; extract lib/plugin-helpers.sh, refactor publish-plugin.sh to source it | ✓ |
| Fold into publish | One `conjure publish` detects context | |
| Deprecate publish | Rename self-publish, make publish-plugin primary | |

**User's choice:** Separate, shared lib (D-01)

| Option | Description | Selected |
|--------|-------------|----------|
| CWD target repo | Operate on CWD like init/adopt/audit | |
| --path flag | Default CWD + explicit `--path <dir>` for scripting/workspace | ✓ |
| You decide | Planner picks | |

**User's choice:** --path flag (D-02)

| Option | Description | Selected |
|--------|-------------|----------|
| Merge, preserve manual | Regenerate computed fields, preserve user-edited metadata via jq merge | ✓ |
| Full regen + backup | Overwrite entirely, snapshot first | |
| You decide | Planner picks | |

**User's choice:** Merge, preserve manual (D-03)

| Option | Description | Selected |
|--------|-------------|----------|
| Emit + verify command | Print files + copy-paste verification assertion | ✓ |
| Files-written summary | Just list files + exit 0 | |
| You decide | Planner picks | |

**User's choice:** Emit + verify command (D-04)

---

## Marketplace source

| Option | Description | Selected |
|--------|-------------|----------|
| Auto-detect github | Parse origin remote → github source + pinned sha; local fallback | ✓ |
| Local path default | `source: ./` default, `--github` opt-in | |
| Prompt/flag explicit | Require `--source`, exit 2 if unset | |

**User's choice:** Auto-detect github (D-05)

| Option | Description | Selected |
|--------|-------------|----------|
| 0.0.0 + dirty warn | No git → 0.0.0 + warn; dirty → pin sha + warn; never blocks | ✓ |
| Exit 2 no-git | Hard refuse without git; dirty → exit 2 unless --allow-dirty | |
| You decide | Planner picks | |

**User's choice:** 0.0.0 + dirty warn (D-06)
**Notes:** Deliberate asymmetry — existing self-publish publish-plugin.sh exit-2s on dirty; target-repo emit warns instead.

| Option | Description | Selected |
|--------|-------------|----------|
| Bundled static list | Hardcoded reserved set in lib/plugin-helpers.sh | ✓ |
| Prefix-pattern match | Reject anthropic*/claude*/*-official patterns | |
| You decide | Planner picks | |

**User's choice:** Bundled static list (D-07)

| Option | Description | Selected |
|--------|-------------|----------|
| Whole manifest | Scan entire plugin.json + marketplace.json | ✓ |
| env + mcpServers only | Scan only config-bearing blocks | |
| You decide | Planner picks | |

**User's choice:** Whole manifest (D-08)

---

## Validate gate

| Option | Description | Selected |
|--------|-------------|----------|
| Schema always, CLI opt-in | Bundled schema check every run (refuse write on invalid); claude plugin validate via --validate | ✓ |
| Both default-on | Schema + claude validate by default, --no-validate to skip | |
| Both opt-in | Only validate with --validate | |

**User's choice:** Schema always, CLI opt-in (D-09)

| Option | Description | Selected |
|--------|-------------|----------|
| Exit 2 hard | --validate + claude absent → exit 2 with hint | ✓ |
| Warn + schema-only | Fall back to schema check, exit 0 | |
| You decide | Planner picks | |

**User's choice:** Exit 2 hard (D-10)

| Option | Description | Selected |
|--------|-------------|----------|
| Bundled in .claude-plugin/SCHEMAS | Alongside existing agent/skill schemas | ✓ |
| New schema dir | Dedicated schemas/cc/ dir | |
| You decide | Planner picks | |

**User's choice:** Bundled in .claude-plugin/SCHEMAS (D-11)

| Option | Description | Selected |
|--------|-------------|----------|
| Warning (exit 0) | Manifest↔disk drift = advisory, audit passes | ✓ |
| Failure (exit 1) | Drift breaks the gate | |
| You decide | Planner picks | |

**User's choice:** Warning (exit 0) (D-12)

---

## Settings wiring

| Option | Description | Selected |
|--------|-------------|----------|
| settings.json, --marketplace gated | Wire into project settings.json only with --marketplace | ✓ |
| settings.local.json, gated | Wire into gitignored per-dev settings | |
| settings.json, always | Auto-wire every run | |

**User's choice:** settings.json, --marketplace gated (D-13)

| Option | Description | Selected |
|--------|-------------|----------|
| Add marketplace, leave disabled | Discoverable only, no enabledPlugins | |
| Auto-enable own plugin | Add to enabledPlugins, live immediately | |
| --enable flag | Default discoverable-only; --enable opts in | ✓ |

**User's choice:** --enable flag (D-14)

| Option | Description | Selected |
|--------|-------------|----------|
| Keyed object merge, idempotent | Merge by marketplace name key, golden-fixture re-run test | ✓ |
| Overwrite key each run | Rewrite named entry wholesale | |
| You decide | Planner picks | |

**User's choice:** Keyed object merge, idempotent (D-15)

| Option | Description | Selected |
|--------|-------------|----------|
| Pin sha, ref as fallback | Write both ref + pinned sha | ✓ |
| Floating ref only | ref: main, no sha (audit warns) | |
| You decide | Planner picks | |

**User's choice:** Pin sha, ref as fallback (D-16)

---

## Claude's Discretion

- Exact reserved-name string set (seed from official plugin-marketplaces docs).
- Exact secret-pattern regex set / entropy threshold (reuse existing repo scanner if present).
- Emit-report output formatting (align with publish-plugin.sh / adopt-report style).
- `plugin.json` `mcpServers`/`hooks` path emission source — resolve in research against live harness layout + official schema.

## Deferred Ideas

- `--pin-sha` standalone pinning subcommand (research open-Q E) — not needed; D-16 pins by default.
- Workspace / cross-repo publish-plugin — Phase 29.
- `strictKnownMarketplaces` enforcement — Phase 26 (managed-settings only).
- Whether `extraKnownMarketplaces` is honored in managed-settings scope — Phase 26 planning open-Q.
