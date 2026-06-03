# Feature Research — v0.7.0 Plugin-native + Policy-grade

**Domain:** CLI harness scaffolding — plugin emission, deployable policy, eval-gating, schema-aware audit, cross-repo orchestration
**Researched:** 2026-06-03
**Milestone:** v0.7.0 — Plugin-native + Policy-grade
**Confidence:** HIGH for plugin/marketplace (official docs verified); HIGH for sandbox/managed-settings (official docs + MDM examples verified); MEDIUM for promptfoo eval harness (docs + integrations verified, but Claude Code harness-specific patterns are novel); MEDIUM for schema-aware audit (hooks schema from docs, disallowed-tools behaviour confirmed but enforcement gaps noted); MEDIUM for cross-repo orchestration (no native Claude Code workspace feature; patterns inferred from community practice and filed feature requests)

---

## Feature Area A: Plugin + Marketplace Emission

### What the native rail produces

A Claude Code plugin lives in a directory with `.claude-plugin/plugin.json` at its root. The manifest carries `name`, `description`, `version` (semver string), plus optional fields: `skills` (path or array), `agents`, `hooks`, `mcpServers`, `lspServers`. Plugin contents are copied into `~/.claude/plugins/cache/` on install — files outside the plugin directory cannot be referenced.

A **marketplace** wraps one or more plugins in `.claude-plugin/marketplace.json` at the repo root. Required fields: `name` (kebab-case, unique per user), `owner.name`, `plugins` (array). Plugin entries carry a `source` field (relative path `"./plugins/foo"`, `{"source":"github","repo":"org/repo","ref":"v1.0","sha":"..."}`, npm, or git URL). Version pinning: set `version` in `plugin.json` or in the marketplace entry; omit it to use git commit SHA as the version. Reserved marketplace names: `claude-code-marketplace`, `claude-plugins-official`, and a dozen Anthropic-controlled names.

Consumers add a marketplace once with `/plugin marketplace add <source>` or via `extraKnownMarketplaces` in project `settings.json`. They install individual plugins with `/plugin install <plugin>@<marketplace>`. They update with `/plugin marketplace update`. Pinning happens at the `sha` field in the marketplace entry.

**Settings integration:** `extraKnownMarketplaces` (project or managed) pre-registers marketplaces so users do not have to run `/plugin marketplace add` manually. `strictKnownMarketplaces` (managed only) restricts which marketplaces users can add. Pairing both in `managed-settings.json` gives IT full control: allow only approved sources, auto-register them.

**Important CI constraint:** `extraKnownMarketplaces` requires an interactive trust dialog; it does not work in headless/CI mode. Managed settings bypass this — they are trusted at the OS level.

### How conjure publish / publish-skill relate

- `conjure publish` (v0.4.0): validates and publishes a plugin (the `.claude-plugin/` in a repo)
- `conjure publish-skill` (v0.4.0): 4-gate validation + PR flow for a single skill
- v0.7.0 gap: neither command *generates* the harness as a plugin + marketplace entry, nor wires `extraKnownMarketplaces`/`strictKnownMarketplaces` into the project's settings

### Table Stakes

| Feature | Why Expected | Complexity | Conjure Dependencies |
|---------|--------------|------------|---------------------|
| `conjure publish-plugin` emits `.claude-plugin/plugin.json` from the scaffolded harness | Users expect the harness to be distributable as a first-class plugin; the native rail exists and is the install path | MEDIUM — must read existing harness structure, assemble `plugin.json` with correct `skills`/`agents`/`hooks`/`mcpServers` paths, version from `.conjure-version` | `cli/conjure`; `scripts/init-project.sh` (knows harness structure); existing `.claude-plugin/` stub (v0.2.0) |
| `conjure publish-plugin --marketplace` generates `.claude-plugin/marketplace.json` | If a team distributes the harness plugin from a git repo, the marketplace file is required for others to discover and install it | MEDIUM — generate marketplace entry with correct `source` (github or url), bump `version` field, write via `lib/mutate.sh` | `lib/mutate.sh`; existing `conjure publish` validation gates |
| Wire `extraKnownMarketplaces` + `enabledPlugins` into `.claude/settings.json` | Teams need members to get the marketplace pre-registered without a manual `/plugin marketplace add`; this is the install UX | LOW — append/merge the two keys into `.claude/settings.json` using `mutate_write`; idempotent (check before write) | `lib/mutate.sh`; `conjure audit` to verify settings file validity post-write |
| `conjure publish-plugin --validate` runs `claude plugin validate` + JSON schema check | Broken manifests cause silent install failures; validation before push is the expected QA gate (same model as `conjure publish` today) | LOW — shell out to `claude plugin validate`; check reserved-name list; validate `plugin.json` against schema | Existing `conjure publish` gate pattern; JSON schema tooling already present |
| Version bump in `plugin.json` / `marketplace.json` without `version` field → git SHA | Users who omit version get auto-versioning via git SHA; those who set version get semver pinning | LOW — detect presence of `version` field; if absent, emit `"version"` set to `$(git rev-parse HEAD)` | `git` (hard dep) |

### Differentiators

| Feature | Value Proposition | Complexity | Conjure Dependencies |
|---------|-------------------|------------|---------------------|
| Managed marketplace wiring: emit `strictKnownMarketplaces` block into `managed-settings.json` template | Security teams need to lock users to approved plugin sources; Conjure can generate the correct managed-settings snippet alongside the plugin manifest, not just the project settings | MEDIUM — generate a `managed-settings.json` fragment containing `strictKnownMarketplaces` and `extraKnownMarketplaces`; designed to be merged with the compliance overlay's managed-settings output | New; wraps sandbox/managed-settings feature area |
| `conjure publish-plugin --pin-sha` — locks all plugin sources to exact commit SHA | Reproducible harness installs across teams; prevents supply-chain drift when upstream plugins update | LOW — iterate `marketplace.json` plugins; for each `github`/`url` source missing `sha`, call `git ls-remote` to resolve current `ref` → SHA; write back | `lib/mutate.sh`; `git` |
| Cross-marketplace dependency declaration (`allowCrossMarketplaceDependenciesOn`) auto-wired | Harnesses that bundle plugins from multiple sources need this field or installs are blocked; Conjure can detect the pattern and emit the field | MEDIUM — detect when `marketplace.json` references plugins from sources not listed in `allowCrossMarketplaceDependenciesOn`; auto-populate | Marketplace schema knowledge |

### Anti-Features

| Anti-Feature | Why Requested | Why Problematic | What to Do Instead |
|--------------|---------------|-----------------|-------------------|
| Replace `conjure publish` / `conjure publish-skill` with a single new command | "Simplify the CLI" | Breaking change; both commands have validation gates and PR flows that are independently useful; merge would conflate skill publication (which targets a skill marketplace PR) with plugin manifest generation (which targets the repo) | Add `conjure publish-plugin` as a new subcommand; keep `publish` and `publish-skill` unchanged |
| Auto-install the plugin after generation | "Zero-friction" | `claude plugin install` requires an interactive session and user trust; running it from `conjure` (a non-Claude-Code context) is out of scope and would require TTY assumptions | Print the install command for the user to run; document it in the output |
| Publish to npm as the primary distribution channel | npm distribution is supported by the native rail | Adds `npm publish` to Conjure's scope; complicates the release pipeline; most teams use git-based distribution | Support npm source in `marketplace.json` generation, but do not run `npm publish`; that remains the user's responsibility |

---

## Feature Area B: Sandbox + Managed-Settings / MDM

### What the native rail provides

**Sandbox block** in `settings.json` (merges across all scopes — user + project + managed arrays concatenate):

```json
{
  "sandbox": {
    "enabled": true,
    "failIfUnavailable": true,
    "filesystem": {
      "allowWrite": ["/tmp/build", "./src", "~/.kube"],
      "denyWrite": ["/etc", "/usr/local/bin"],
      "denyRead": ["~/.aws/credentials", "~/.ssh"],
      "allowRead": ["."],
      "allowManagedReadPathsOnly": true
    },
    "network": {
      "allowedDomains": ["*.npmjs.org", "api.github.com"],
      "allowLocalBinding": true
    }
  }
}
```

**Critical enforcement gap:** `sandbox.denyRead` blocks bash subprocess reads but does NOT block Claude's `Read` tool. To protect reads at the tool level, mirror `denyRead` paths in `permissions.deny` as `Read(<path>)` rules.

**Managed-settings file locations:**

| Platform | Path |
|----------|------|
| macOS (file) | `/Library/Application Support/ClaudeCode/managed-settings.json` |
| macOS (MDM) | `com.anthropic.claudecode` plist domain (Jamf / Kandji) |
| Linux/WSL | `/etc/claude-code/managed-settings.json` |
| Windows (file) | `C:\Program Files\ClaudeCode\managed-settings.json` |
| Windows (MDM) | `HKLM\SOFTWARE\Policies\ClaudeCode` (REG_SZ JSON) |

Drop-in directory: `managed-settings.d/` (e.g., `10-telemetry.json`, `20-security.json`, `30-compliance.json`). Files merge alphabetically; scalars override, arrays concatenate and deduplicate.

**MDM artifacts shipped by Anthropic** (`claude-code/examples/mdm`):
- `macos/com.anthropic.claudecode.plist` — Jamf / Kandji Custom Settings payload
- `macos/com.anthropic.claudecode.mobileconfig` — full macOS Configuration Profile
- `windows/Set-ClaudeCodePolicy.ps1` — Intune Platform Script
- `windows/ClaudeCode.admx` + `en-US/ClaudeCode.adml` — Group Policy / Intune ADMX template

All Anthropic examples baseline on `disableBypassPermissionsMode`.

### Compliance regime → concrete policy keys

**HIPAA:**
```json
{
  "disableBypassPermissionsMode": "disable",
  "allowManagedPermissionRulesOnly": true,
  "forceLoginOrgUUID": "<org-uuid>",
  "sandbox": {
    "enabled": true,
    "failIfUnavailable": true,
    "filesystem": {
      "denyRead": ["~/.aws/credentials", "~/.ssh", "**/PHI/**", "**/patient_data/**", "**/*.hl7", "**/*.ccda"],
      "denyWrite": ["/etc", "/usr/local/bin"]
    },
    "network": {
      "allowedDomains": ["<approved-endpoints-only>"]
    }
  },
  "permissions": {
    "deny": ["Bash(curl http://*)", "Bash(wget http://*)", "Read(**/.env*)", "Read(**/secrets/**)", "Read(**/.ssh/**)"]
  }
}
```

**SOC 2:**
```json
{
  "disableBypassPermissionsMode": "disable",
  "allowManagedPermissionRulesOnly": true,
  "allowManagedHooksOnly": true,
  "forceRemoteSettingsRefresh": true,
  "sandbox": { "enabled": true, "failIfUnavailable": true },
  "permissions": {
    "deny": ["Bash(curl*)", "Bash(wget*)", "Read(**/.env*)", "Read(**/secrets/**)", "Read(**/.ssh/**)"]
  }
}
```

**GDPR:**
```json
{
  "disableBypassPermissionsMode": "disable",
  "allowManagedPermissionRulesOnly": true,
  "sandbox": {
    "filesystem": {
      "denyRead": ["**/pii/**", "**/personal/**", "**/user_profiles/**", "**/email*lists/**", "~/.aws/credentials"]
    }
  },
  "permissions": {
    "deny": ["Read(**/.env*)", "Read(**/secrets/**)", "WebFetch(http://**)"]
  }
}
```

**PCI DSS:**
```json
{
  "disableBypassPermissionsMode": "disable",
  "allowManagedPermissionRulesOnly": true,
  "sandbox": {
    "filesystem": {
      "denyRead": ["**/*card*", "**/payment*", "**/*token*", "**/*crypto*keys*", "~/.aws/credentials", "~/.ssh"]
    }
  },
  "permissions": {
    "deny": ["Bash(git push*)", "Bash(curl*)", "Read(**/.env*)", "Write(**/*vault**)"]
  }
}
```

### Table Stakes

| Feature | Why Expected | Complexity | Conjure Dependencies |
|---------|--------------|------------|---------------------|
| Compliance overlay generates `sandbox{}` block and writes it to `.claude/settings.json` | Security teams deploying HIPAA/SOC2/GDPR/PCI expect the overlay to produce enforceable runtime restrictions, not just documentation | MEDIUM — extend each overlay script to emit a `sandbox` JSON block; merge into existing `.claude/settings.json` via `jq` + `mutate_write`; include both `denyRead` and mirrored `permissions.deny` for the Read-tool gap | `compliance/` overlay scripts; `lib/mutate.sh`; `jq` (hard dep) |
| Generate `managed-settings.json` from overlay | IT/MDM teams need a ready-to-deploy file, not a settings.json that can be overridden by users | MEDIUM — each compliance overlay emits a `managed-settings.json` alongside the project `settings.json`; keys include `disableBypassPermissionsMode`, `allowManagedPermissionRulesOnly`, `allowManagedHooksOnly`, `forceLoginOrgUUID` (placeholder), sandbox block | `compliance/` overlays; `lib/mutate.sh` |
| macOS plist artifact from overlay | Jamf/Kandji deployments need the plist; teams cannot hand-craft it correctly | MEDIUM — generate `com.anthropic.claudecode.plist` from the managed-settings JSON using a shell-based JSON-to-plist converter (Python `plistlib` or `plutil`); write via `lib/mutate.sh` | `compliance/` overlays; Python 3 (soft dep for plist generation) |
| Windows registry / PowerShell artifact from overlay | Intune/Group Policy deployments need `Set-ClaudeCodePolicy.ps1` | MEDIUM — generate a parameterised PowerShell script that writes the managed-settings JSON to `HKLM\SOFTWARE\Policies\ClaudeCode`; adapt from Anthropic's example | `compliance/` overlays; `lib/mutate.sh` |
| `conjure audit` flags missing sandbox block and missing mirrored `permissions.deny` for denyRead paths | Teams that partially configure sandbox (denyRead without the mirrored Read deny) have a false sense of security | LOW — add two new audit checks: (1) if `sandbox.filesystem.denyRead` is set, verify each path also appears in `permissions.deny` as `Read(<path>)`, (2) if overlay is active, verify `sandbox.enabled: true` and `disableBypassPermissionsMode: "disable"` are present in managed-settings | `scripts/audit-setup.sh`; JSON schema validation |

### Differentiators

| Feature | Value Proposition | Complexity | Conjure Dependencies |
|---------|-------------------|------------|---------------------|
| `managed-settings.d/` drop-in generation: emit regime-specific fragments (e.g., `20-hipaa.json`, `30-marketplace.json`) | Orgs with layered IT policies (HIPAA + SOC2 base) need composable fragments, not a single monolithic file | MEDIUM — instead of generating one `managed-settings.json`, emit named fragments into `managed-settings.d/`; number them so merge order is predictable; document the merge semantics in the emitted README | `compliance/` overlays |
| `conjure refresh-overlay --emit-mdm` re-generates MDM artifacts when overlay policy changes | Overlays evolve; teams need re-generated MDM files on policy update, not manual edits | LOW — add `--emit-mdm` flag to `refresh-overlay` script; calls the plist + PS1 generators; dry-run safe | `scripts/refresh-overlay.sh` (existing); new plist/PS1 generators |
| Inline documentation comments in generated `managed-settings.json` | Security engineers reading deployed files need to know which Conjure overlay produced each key and why | LOW — emit a `"_conjure_source"` annotation object alongside each policy block (JSON doesn't support comments; use a parallel annotation key) | `lib/mutate.sh` |

### Anti-Features

| Anti-Feature | Why Requested | Why Problematic | What to Do Instead |
|--------------|---------------|-----------------|-------------------|
| Auto-deploy MDM artifacts to Jamf/Intune via their APIs | "One command" | Requires API credentials and org-specific Jamf/Intune tenant IDs; Conjure should not store or handle MDM credentials; deployment is an IT ops concern | Generate the artifacts; document the deployment steps; do not call MDM APIs |
| Claim overlays make a project "compliant" | Compliance is a natural aspiration | Compliance requires people, process, audit, and a signed BAA/DPA; the overlay only configures Claude Code's behaviour | Keep the existing disclaimer in overlay output: "reduces non-compliant output; real compliance needs people + process" |
| Auto-detect credential paths at scan time (crawl repo for .env files) | "Smart protection" | Scanning the full repo for credential-looking files adds scope, risk of false positives, and significantly increases runtime | Ship standard deny-read path patterns per regime; document how teams add project-specific paths |

---

## Feature Area C: conjure eval (promptfoo + context-budget linter)

### How promptfoo eval for a Claude Code harness works

promptfoo uses `anthropic:claude-agent-sdk` (alias `anthropic:claude-code`) as a provider. A `promptfooconfig.yaml` specifies `working_dir` (the repo under test), `permission_mode`, `setting_sources` (loads the project's `.claude/skills/`, `settings.json`), `skills: all` (or named list), and `max_turns`.

**Assertion types relevant to harness testing:**

| Assertion | What it proves | Syntax |
|-----------|---------------|--------|
| `skill-used` | A named skill was actually invoked (normalised from Claude's `Skill` tool call) | `type: skill-used, value: skill-name` |
| `not-skill-used` | A skill was NOT invoked (appropriate skills stay idle) | `type: not-skill-used, value: skill-name` |
| `javascript` with `context.providerResponse?.metadata?.toolCalls` | Exact tool-call sequence; can assert hooks fired (via PostToolUse) | custom JS |
| `llm-rubric` | Semantic quality — whether output follows CLAUDE.md rules (e.g., "response is in English", "no @import used") | `type: llm-rubric, value: "must not contain @import"` |
| `contains` / `icontains` | Literal string in output | standard |
| `is-json` | Output is valid JSON | standard |

**Hook firing cannot be directly asserted** via a promptfoo assertion today — hooks are shell processes in the sandbox. The practical approach is: configure PostToolUse hooks to write to a logfile in `/tmp/`, then use a `javascript` assertion that reads that file and checks for expected entries.

**CLAUDE.md adherence eval:** use `llm-rubric` with the specific rule text from CLAUDE.md as the rubric. Example: `"Claude must not call Bash(rm -rf *) — check that no such command appears in the tool calls"`. Combine with `javascript` assertions on `metadata.toolCalls` for deterministic checks.

**PR gate:** `promptfoo/promptfoo-action@v1` runs on `pull_request`; posts before/after comparison as a PR comment; fails if success rate drops below `fail-on-threshold` (e.g., 80). Requires `ANTHROPIC_API_KEY` secret and `permissions: pull-requests: write`.

```yaml
# .github/workflows/eval.yml (minimal)
on:
  pull_request:
    paths: ['.claude/**', 'CLAUDE.md', 'templates/**']
jobs:
  eval:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      pull-requests: write
    steps:
      - uses: actions/checkout@v4
      - uses: promptfoo/promptfoo-action@v1
        with:
          github-token: ${{ secrets.GITHUB_TOKEN }}
          anthropic-api-key: ${{ secrets.ANTHROPIC_API_KEY }}
          config: .conjure/eval/promptfooconfig.yaml
          fail-on-threshold: 80
```

### Context-budget linting

Claude Code tracks token usage per turn internally (visible via `/usage`). There is no first-party per-turn token count written to a file. The best proxy for a static linter:

- **CLAUDE.md line count** as a cap-compliance proxy (Conjure already enforces ≤100 lines; `conjure audit` already checks this)
- **Skills body line count** (≤200 lines; already enforced)
- **Chars/4 heuristic** for estimated token count — already in Conjure's cost estimator
- **Context load estimate** = CLAUDE.md chars/4 + sum(skills marked `disable-model-invocation: false` body chars/4) per session start

A new `conjure audit --budget` check would: (1) measure CLAUDE.md token estimate, (2) sum always-loaded skill tokens, (3) flag if session-start context exceeds a configurable threshold (default 8,000 tokens = ~32,000 chars), (4) list the top contributors. This is a static check, not a runtime hook.

### Table Stakes

| Feature | Why Expected | Complexity | Conjure Dependencies |
|---------|--------------|------------|---------------------|
| `conjure eval init` — scaffold `promptfooconfig.yaml` with harness-specific assertions | Teams need a working eval config, not a blank slate; the harness structure is known so Conjure can generate assertions for each skill | MEDIUM — read `.claude/skills/` inventory; emit one `skill-used` test per skill; emit one `llm-rubric` test per CLAUDE.md rule line; write to `.conjure/eval/promptfooconfig.yaml` via `mutate_write` | `scripts/audit-setup.sh` (reads harness); `lib/mutate.sh` |
| `conjure eval run` — executes `promptfoo eval` against the generated config | Teams need a single command, not "install promptfoo, figure out config path, run eval" | LOW — shell out to `npx promptfoo eval -c .conjure/eval/promptfooconfig.yaml`; require `node` (already a soft dep for hooks); pass through exit code for CI gate | `cli/conjure`; `node` (soft dep) |
| PR gate workflow template — `conjure eval --emit-workflow` generates `.github/workflows/conjure-eval.yml` | GitHub Actions gate is table-stakes for "eval-backed" to mean anything in a PR review | LOW — emit a parameterised workflow YAML; paths trigger on `.claude/**`, `CLAUDE.md`, `templates/**`; uses `promptfoo/promptfoo-action@v1`; requires `ANTHROPIC_API_KEY` secret | `lib/mutate.sh`; GitHub Actions knowledge |
| `conjure audit --budget` — static context-budget linter | Teams asked for "eval-backed"; context size is measurable statically and a leading indicator of poor harness hygiene | LOW — chars/4 heuristic on CLAUDE.md + always-loaded skills; flag if >8,000 tokens; list top contributors; output as part of `conjure audit` report | `scripts/audit-setup.sh`; `lib/caps.sh` (already measures lines; extend to chars) |
| `conjure audit` reports which skills have no eval coverage (no `skill-used` assertion in promptfooconfig.yaml) | Uncovered skills are a gap in the eval suite; surfacing the gap is the first step to closing it | LOW — parse `.conjure/eval/promptfooconfig.yaml`; extract `skill-used` assertion values; diff against `.claude/skills/` directory listing; report uncovered skills | `scripts/audit-setup.sh` |

### Differentiators

| Feature | Value Proposition | Complexity | Conjure Dependencies |
|---------|-------------------|------------|---------------------|
| `conjure eval snapshot` — records a baseline pass/fail before a harness change, for before/after comparison | promptfoo-action does before/after comparison automatically in CI, but teams want a local baseline record before pushing | LOW — run eval, write result JSON to `.conjure/eval/baseline.json`; subsequent `conjure eval run` compares against baseline; flag regressions in local output | `lib/mutate.sh`; promptfoo JSON output |
| Per-skill eval template with trajectory assertions for tool sequences | Skills that use `Bash` or `Read` in a specific sequence should assert that sequence; Conjure can generate trajectory stubs from skill `allowed-tools` frontmatter | MEDIUM — read `allowed-tools` from each skill's frontmatter; emit `javascript` assertion stubs that check `metadata.toolCalls` for those tools | Frontmatter parser (already present in audit) |
| Budget linter per-skill breakdown in `conjure audit --budget` output (porcelain + human) | CI can parse per-skill token estimates and flag the one skill that doubled in size | LOW — emit `--porcelain` JSON breakdown alongside human output; consistent with `conjure check --porcelain` pattern | `lib/caps.sh`; `conjure check` precedent |

### Anti-Features

| Anti-Feature | Why Requested | Why Problematic | What to Do Instead |
|--------------|---------------|-----------------|-------------------|
| Bundle promptfoo as a Conjure dependency | "Zero setup" | promptfoo is a large npm package; Conjure's constraint is `dependencies: {}`; bundling breaks the minimal-runtime-deps rule | Shell out to `npx promptfoo` (downloads on first use); document that `node` is required for `conjure eval` |
| Run eval on every `conjure audit` call by default | "Comprehensive audit" | Eval makes real API calls; cost is non-trivial ($0.50–$5 per run); unexpected costs on routine audit would break CI budgets | Keep `conjure eval` as an explicit subcommand; `conjure audit` runs the static budget linter only |
| Write eval results to RESTRUCTURE-LOG.md | "Unified log" | Eval results are structured JSON with per-test pass/fail; mixing them into a prose log loses structure | Write eval results to `.conjure/eval/results/` with timestamps; keep RESTRUCTURE-LOG.md for adopt/restructure operations |
| Assert that hooks "fired" via exit-code inspection | Hooks are shell processes; exit codes are not visible to promptfoo's assertion engine without extra infrastructure | Use the PostToolUse logfile pattern instead; or accept that hook firing is validated by unit tests in `tests/run.sh`, not by promptfoo evals |

---

## Feature Area D: Schema-version-aware Audit/Check

### What drift/validation checks exist today

`conjure audit` (v0.2.0+) checks: CLAUDE.md line count ≤100, SKILL.md line count ≤200, agent frontmatter JSON schema, anti-pattern detection (`@import` in CLAUDE.md), overlay drift. `conjure check` (v0.5.0) does 3-way sha256 drift detection on harness files.

### What the current schema actually contains

**SKILL.md frontmatter fields (all optional):** `name`, `description`, `when_to_use`, `argument-hint`, `arguments`, `disable-model-invocation`, `user-invocable`, `allowed-tools`, `disallowed-tools`, `model`, `effort`, `context` (fork), `agent`, `hooks`, `paths`, `shell`.

Critical enforcement note: `allowed-tools` is parsed by Claude Code but not enforced at the tool-permission level (open bug: issue #37683). `disallowed-tools` removes tools from Claude's pool during the skill's active turn; the restriction clears on the next user message.

**Hook schema:** 34 named events (as of 2026-06); handler types: `command`, `http`, `mcp_tool`, `prompt`, `agent`; `if` field uses permission-rule syntax. No explicit schema version field in the config JSON. Version-gated features: `terminalSequence` (v2.1.141+); `displayName` in marketplace (v2.1.143+); `defaultEnabled` in marketplace (v2.1.154+).

**Settings keys added in recent versions** that old harnesses may be missing or may have with wrong types: `disableBypassPermissionsMode` (string `"disable"`, not boolean), `allowManagedPermissionRulesOnly` (boolean), `allowManagedHooksOnly` (boolean), `sandbox.filesystem.allowManagedReadPathsOnly` (boolean).

**VS Code schema validator drift:** the VS Code extension's SKILL.md schema validator rejects valid fields (`allowed-tools`, `model`, `context`, `agent`, `hooks`) and includes undocumented fields — meaning any SKILL.md schema Conjure validates against must be Conjure-maintained, not deferred to the extension.

### Table Stakes

| Feature | Why Expected | Complexity | Conjure Dependencies |
|---------|--------------|------------|---------------------|
| `conjure audit` validates all SKILL.md frontmatter keys against current known-field list | Skill authors adding new keys (e.g., `disallowed-tools`) expect validation to pass; currently old schema may reject valid fields | LOW — update Conjure's JSON schema for SKILL.md frontmatter to include all 14 documented fields; re-run against `tests/fixtures/` to verify no regressions | `scripts/audit-setup.sh`; JSON schema files |
| `conjure audit` flags `disableBypassPermissionsMode` set to boolean `true` instead of string `"disable"` | Teams copying old examples set this incorrectly; boolean is silently ignored | LOW — add a type check in audit: if `disableBypassPermissionsMode` is present and is not the string `"disable"`, emit a warning with the correct value | `scripts/audit-setup.sh` |
| `conjure check` flags settings keys that reference removed or renamed hook events | Hook events were added in recent Claude Code versions; harnesses built on old event names (or using an event name that was a pre-release alias) may silently never fire | MEDIUM — maintain a Conjure-internal table of current hook event names (34 events); audit `settings.json` `hooks:` keys against this table; flag unknown event names | `scripts/audit-setup.sh`; hook-events table (new) |
| `conjure audit` validates `disallowed-tools` field in SKILL.md is an array or space-separated string (not a YAML mapping) | `disallowed-tools: Bash AskUserQuestion` is valid; `disallowed-tools: {Bash: true}` is not | LOW — add type-check rule for `disallowed-tools` in SKILL.md schema validation | `scripts/audit-setup.sh` |
| `conjure check --schema` reports which Claude Code version introduced each setting key found in the harness | Teams pinned to an older Claude Code version need to know if their settings include keys that did not exist in their pinned version | MEDIUM — maintain a version-gate table mapping setting key → minimum Claude Code version; emit a `check --schema` report comparing harness setting keys against the pinned `.conjure-version` | `scripts/check.sh`; `.conjure-version` (existing); version-gate table (new) |

### Differentiators

| Feature | Value Proposition | Complexity | Conjure Dependencies |
|---------|-------------------|------------|---------------------|
| `conjure audit --strict` cross-validates `allowed-tools` declarations against the hook `matcher` patterns | A skill that declares `allowed-tools: Read Bash` but has a hook that blocks `Bash` is self-contradicting; flagging this prevents confusing harness behaviour | MEDIUM — parse both `allowed-tools` from SKILL.md and `PreToolUse` hook matchers from `settings.json`; emit a warning if the allowed tool is also blocked by a hook | `scripts/audit-setup.sh`; frontmatter parser; hooks JSON parser |
| `conjure audit` flags `sandbox.denyRead` paths not mirrored in `permissions.deny` as `Read(...)` | The denyRead / Read-tool gap is a known gotcha; automated detection prevents false security | LOW — parse `sandbox.filesystem.denyRead` array; for each entry, check `permissions.deny` for a matching `Read(...)` rule; flag gaps | `scripts/audit-setup.sh` |
| Auto-update schema table from `claude --version` output when run in a connected environment | Schema drift between Conjure's table and the installed Claude Code version is detected at run time | MEDIUM — `conjure check --schema` optionally calls `claude --version`; if version is newer than the table's `schema_version_known_through` field, emit a notice to update Conjure | `scripts/check.sh`; `claude` (soft dep) |

### Anti-Features

| Anti-Feature | Why Requested | Why Problematic | What to Do Instead |
|--------------|---------------|-----------------|-------------------|
| Auto-fix schema violations (rewrite settings.json keys) | "One-command fix" | Automated rewriting of settings.json is a mutation with non-trivial semantic implications; the wrong key name is a symptom, not the problem | Emit clear error messages with the correct key name and value; let the user apply the fix |
| Pin to a specific Claude Code schema version and refuse to audit on mismatch | "Reproducible audits" | Claude Code versions in the wild vary widely; refusing to audit on version mismatch would break CI for most teams | Warn (not error) when the installed version is newer than the known schema; always proceed with the audit |

---

## Feature Area E: Cross-repo / Workspace Orchestration

### Current native Claude Code support

There is no native Claude Code workspace feature as of 2026-06. Issue #35362 (multi-repo workspace support) is closed without public resolution. Community patterns rely on: TOML/YAML repo manifests (mani, ttal), layered CLAUDE.md files (org → team → repo), `--add-dir` to grant read access to sibling repos, and manual task scripting.

`claude --workspace /path/a /path/b` syntax does not exist yet. The closest native primitive is `--add-dir`, which grants file access (not skill/config loading) from additional directories.

### What teams actually do

- A `workspace.toml` or `repos.yaml` lists project name, local path, git URL, and tags
- A root `CLAUDE.md` describes the workspace structure and cross-repo discovery
- Repo manager tools (mani, ttal) run tasks across repos via `mani run <task> --all-projects`
- Rollback is via `git` per repo; no cross-repo atomic rollback exists in any tool

### Conjure-native workspace model

Since no native rail exists, Conjure must define its own workspace manifest format. The most defensible approach is a JSON file (consistent with Conjure's existing JSON manifests) that lists repos with local paths:

```json
{
  "name": "acme-workspace",
  "repos": [
    { "name": "backend", "path": "../backend", "tags": ["node", "api"] },
    { "name": "frontend", "path": "../frontend", "tags": ["react"] },
    { "name": "infra", "path": "../infra", "tags": ["terraform"] }
  ]
}
```

Stored at `.conjure-workspace.json` in the workspace root. Commands accept `--workspace .conjure-workspace.json` or discover it by walking parent directories (same pattern as `conjure check` discovering `.conjure-version`).

### Table Stakes

| Feature | Why Expected | Complexity | Conjure Dependencies |
|---------|--------------|------------|---------------------|
| `.conjure-workspace.json` manifest — defines repos by local path and optional git URL | Teams with many repos need a declarative list; ad-hoc scripting is not repeatable; the manifest is the coordination primitive | LOW — define JSON schema; validate on load; no dependencies beyond `jq` | `lib/mutate.sh`; JSON schema tooling |
| `conjure workspace init` — creates the manifest by discovering sibling repos with a `.claude/` directory | First-run UX: users should not hand-write the manifest; discovery by convention is safer | MEDIUM — scan parent directory for dirs containing `.claude/`; prompt (TTY) or auto-add (non-TTY with `--yes`); write manifest via `mutate_write` | `lib/mutate.sh`; TTY detection (existing pattern) |
| `conjure workspace check` — runs `conjure check` across all repos in the manifest; emits a per-repo status table | The primary value: one command to see harness drift across 20 repos | MEDIUM — iterate manifest repos; shell out to `conjure check --porcelain` in each repo's path; aggregate results; emit a markdown table with repo name, drift status, and check exit code | `scripts/check.sh`; `lib/mutate.sh`; `--porcelain` output format |
| `conjure workspace audit` — runs `conjure audit` across all repos; aggregates cap violations and schema errors | Same motivation as workspace check; audit is the health check | MEDIUM — iterate repos; shell out to `conjure audit --json` in each; aggregate; emit per-repo pass/fail and a global summary | `scripts/audit-setup.sh`; `--json` output (new) |
| Per-repo rollback semantics: `conjure workspace adopt --rollback` rolls back each repo independently | Cross-repo atomic rollback is impossible without a distributed transaction; per-repo rollback is the safe degradation | LOW — for each repo in manifest, call `conjure adopt --rollback` if `.conjure-adopt-backup-*` exists; report per-repo outcome | `scripts/adopt.sh` (existing rollback); `lib/snapshot.sh` |
| `conjure workspace update` — runs `conjure update` across all repos; reports per-repo merge/conflict status | Harness updates across many repos is the primary workspace pain point today | HIGH — iterate repos; call `conjure update`; capture exit code and sidecar conflict list; report per-repo; stop on first error unless `--continue-on-error` | `scripts/update.sh`; conflict sidecar pattern (existing) |

### Differentiators

| Feature | Value Proposition | Complexity | Conjure Dependencies |
|---------|-------------------|------------|---------------------|
| `conjure workspace report` — markdown table of per-repo health (version, drift status, overlay, eval coverage) emitted to stdout or a file | Tech leads need a single-pane view; this is the multi-repo equivalent of `conjure audit` | MEDIUM — aggregate outputs from check, audit, and eval (if present); emit a markdown table; `--json` for CI dashboards | All workspace subcommands above |
| Workspace-scoped managed-settings merge — `conjure workspace emit-managed` generates a single `managed-settings.json` that covers all repos' compliance requirements | An org with mixed HIPAA + SOC2 repos needs a unified MDM policy; Conjure can union the denyRead paths and permission rules | HIGH — collect compliance overlay config from each repo's `.conjure-overlay`; union denyRead paths; union permission deny rules; emit a single managed-settings.json | Overlay system (existing); B-area managed-settings generator (new) |
| `conjure workspace adopt` — runs `conjure adopt` across repos matching a tag filter | Bootstrapping a new compliance requirement across 20 repos is a multi-day manual task; workspace adopt with `--tags terraform` makes it a one-command operation | HIGH — tag filtering from manifest; serial execution (not parallel — avoids masking errors); per-repo snapshot before any mutation; stop on first failure unless `--continue-on-error` | `scripts/adopt.sh`; `lib/snapshot.sh` |

### Anti-Features

| Anti-Feature | Why Requested | Why Problematic | What to Do Instead |
|--------------|---------------|-----------------|-------------------|
| Parallel execution of workspace commands | "Faster" | Parallel mutations across repos mask failures; if one repo fails mid-adopt, others may complete, leaving the workspace in an inconsistent state that is hard to diagnose | Serial execution by default; `--jobs N` only for read-only commands (check, audit, report) where failure isolation is trivial |
| Cross-repo atomic rollback (all-or-nothing) | "If one fails, undo all" | Distributed transactions require coordination state that Conjure does not have; the complexity is disproportionate to the gain; per-repo snapshot rollback is sufficient | Per-repo rollback; document the `conjure workspace adopt --rollback` procedure; teams can re-run per-repo rollback on failed repos |
| Auto-clone missing repos from the manifest git URL | "Workspace setup in one command" | Cloning repos involves credentials, SSH keys, and network; this is out of Conjure's scope | Document the `git clone` step; workspace init only discovers already-cloned repos |
| Native integration with mani, ttal, or other repo managers | "Use the standard tool" | No repo manager has enough adoption to be "standard"; adding a dep on any specific one fragments the user base | Accept `--workspace <path>` pointing to `.conjure-workspace.json`; provide a `conjure workspace import-mani` helper that converts a mani YAML to `.conjure-workspace.json` |

---

## Feature Dependencies

```
[B: managed-settings generator]
    └──required-by──> [A: managed marketplace wiring (strictKnownMarketplaces)]
    └──required-by──> [E: workspace emit-managed]
    └──requires──>    [compliance/ overlay scripts (existing)]

[A: plugin.json emission]
    └──requires──>    [existing .claude-plugin/ stub (v0.2.0)]
    └──requires──>    [conjure publish gate (existing)]
    └──enhances──>    [B: extraKnownMarketplaces wiring]

[C: conjure eval init]
    └──requires──>    [scripts/audit-setup.sh harness inventory (existing)]
    └──requires──>    [SKILL.md frontmatter parser (existing)]
    └──enhances──>    [D: audit coverage check (eval coverage gap)]

[D: schema-aware audit]
    └──requires──>    [scripts/audit-setup.sh (existing)]
    └──extends──>     [existing JSON schema for frontmatter (existing)]
    └──required-by──> [C: conjure audit --budget]
    └──required-by──> [B: audit flags missing sandbox mirror]

[E: workspace orchestration]
    └──requires──>    [scripts/check.sh --porcelain (existing)]
    └──requires──>    [scripts/audit-setup.sh --json (new flag)]
    └──requires──>    [scripts/adopt.sh --rollback (existing)]
    └──requires──>    [B: managed-settings generator (for workspace emit-managed)]
    └──requires──>    [.conjure-workspace.json manifest (new)]

[C: PR gate workflow]
    └──requires──>    [conjure eval init (generates promptfooconfig.yaml)]
    └──requires──>    [node (soft dep, already required by .mjs hooks)]
    └──enhances──>    [D: audit coverage check (surfaced in PR comment)]
```

### Dependency Notes

- **Build order within the milestone:** D (schema-aware audit) unblocks C (eval coverage check). B (managed-settings) and A (plugin emission) can proceed in parallel. E (workspace) requires D's `--json` audit flag and can start after D ships. C's PR gate requires C's eval init.

- **`conjure audit --json`** is a new flag needed by both C (coverage reporting) and E (workspace audit aggregation); ship it as part of D since audit-setup.sh is the natural owner.

- **`node` soft dep:** C's `conjure eval run` shells out to `npx promptfoo`; the `.mjs` hooks already require node, so this is not a new hard dep, but should be documented in the preflight check.

- **plist generation in B** requires Python 3 `plistlib` or `plutil` (macOS only). On Linux/Windows, emit the plist as a JSON + base64 blob with a note that macOS is required for the MDM deployment step. Python 3 is available on all target platforms.

---

## MVP Definition

### Ship First (foundational — unblocks everything)

- [x] **D: Schema-aware audit** — SKILL.md frontmatter validation + hook event table + `--json` flag — unblocks E; closes known schema debt; LOW–MEDIUM complexity
- [x] **B: sandbox block emission from overlays** — concrete denyRead/permissions.deny per regime — HIGH security value; MEDIUM complexity; standalone
- [x] **B: managed-settings.json generation** — IT deployment artifact; MEDIUM complexity; standalone

### Ship Second (core milestone value)

- [x] **A: `conjure publish-plugin`** — plugin.json + marketplace.json emission; MEDIUM complexity; depends on existing publish gate
- [x] **A: `extraKnownMarketplaces` wiring** — project settings integration; LOW complexity
- [x] **C: `conjure eval init` + `conjure eval run`** — scaffold eval + execute; MEDIUM complexity; requires D for coverage check
- [x] **C: PR gate workflow template** — `--emit-workflow`; LOW complexity
- [x] **C: `conjure audit --budget`** — static context linter; LOW complexity; extends D's audit

### Ship Third (workspace, highest complexity)

- [x] **E: `.conjure-workspace.json` + `conjure workspace init`** — manifest + discovery; LOW–MEDIUM complexity
- [x] **E: `conjure workspace check` + `conjure workspace audit`** — multi-repo health; MEDIUM complexity
- [x] **E: `conjure workspace update`** — multi-repo harness update; HIGH complexity

### Defer to v0.7.x or v0.8.0

- [ ] **E: `conjure workspace adopt`** — multi-repo brownfield adoption; HIGH complexity + HIGH risk
- [ ] **E: workspace emit-managed** — union managed-settings across repos; HIGH complexity; needs all overlay work to stabilise first
- [ ] **A: `--pin-sha` for all marketplace sources** — nice-to-have; LOW complexity but low urgency
- [ ] **B: MDM plist/PS1 artifact generation** — useful but can start without; MEDIUM complexity

---

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| D: SKILL.md frontmatter full schema | HIGH | LOW | P1 |
| D: hook event name validation | HIGH | MEDIUM | P1 |
| D: `disableBypassPermissionsMode` type check | HIGH | LOW | P1 |
| D: `conjure audit --json` flag | HIGH | LOW | P1 |
| B: sandbox block from overlays | HIGH | MEDIUM | P1 |
| B: managed-settings.json generation | HIGH | MEDIUM | P1 |
| A: `conjure publish-plugin` (plugin.json + marketplace.json) | HIGH | MEDIUM | P1 |
| A: `extraKnownMarketplaces` wiring | HIGH | LOW | P1 |
| C: `conjure eval init` | HIGH | MEDIUM | P1 |
| C: `conjure eval run` | HIGH | LOW | P1 |
| C: PR gate workflow template | HIGH | LOW | P1 |
| C: `conjure audit --budget` | MEDIUM | LOW | P1 |
| E: `.conjure-workspace.json` manifest | HIGH | LOW | P1 |
| E: `conjure workspace init` | HIGH | MEDIUM | P1 |
| E: `conjure workspace check` | HIGH | MEDIUM | P2 |
| E: `conjure workspace audit` | HIGH | MEDIUM | P2 |
| E: `conjure workspace update` | HIGH | HIGH | P2 |
| B: MDM plist artifact | MEDIUM | MEDIUM | P2 |
| B: Windows PS1 artifact | MEDIUM | MEDIUM | P2 |
| A: `--pin-sha` | MEDIUM | LOW | P2 |
| D: `allowed-tools` vs hook matcher cross-validation | MEDIUM | MEDIUM | P2 |
| B: managed-settings.d/ fragments | MEDIUM | MEDIUM | P2 |
| C: `conjure eval snapshot` baseline | MEDIUM | LOW | P3 |
| E: `conjure workspace adopt` | HIGH | HIGH | P3 |
| E: workspace emit-managed | MEDIUM | HIGH | P3 |

---

## Sources

- Claude Code plugin marketplace docs (official): [Create and distribute a plugin marketplace](https://code.claude.com/docs/en/plugin-marketplaces) — HIGH confidence
- Claude Code settings and sandbox schema (official): [Claude Code settings](https://code.claude.com/docs/en/settings) — HIGH confidence
- Anthropic MDM examples: [claude-code/examples/mdm](https://github.com/anthropics/claude-code/tree/main/examples/mdm) — HIGH confidence
- Claude Code hooks reference (official): [Hooks reference](https://code.claude.com/docs/en/hooks) — HIGH confidence
- SKILL.md frontmatter reference (official): [Extend Claude with skills](https://code.claude.com/docs/en/skills) — HIGH confidence
- promptfoo Claude Agent SDK provider (official): [Claude Agent SDK | Promptfoo](https://www.promptfoo.dev/docs/providers/claude-agent-sdk/) — HIGH confidence
- promptfoo skill testing (official): [Test Agent Skills | Promptfoo](https://www.promptfoo.dev/docs/guides/test-agent-skills/) — HIGH confidence
- promptfoo-action GitHub Action: [promptfoo/promptfoo-action](https://github.com/promptfoo/promptfoo-action) — HIGH confidence
- Claude Code cost and context management (official): [Manage costs effectively](https://code.claude.com/docs/en/costs) — HIGH confidence
- `allowed-tools` enforcement gap: [allowed-tools does not restrict tool access · Issue #37683](https://github.com/anthropics/claude-code/issues/37683) — HIGH confidence (open bug)
- VS Code skill schema drift: [YAML Frontmatter Validation Schema Outdated · Issue #23330](https://github.com/anthropics/claude-code/issues/23330) — HIGH confidence (open bug)
- `extraKnownMarketplaces` + trust dialog CI constraint: [Clarify extraKnownMarketplaces requires interactive trust dialog · Issue #13097](https://github.com/anthropics/claude-code/issues/13097) — HIGH confidence
- Multi-repo workspace feature request: [Feature request: Multi-repo workspace support · Issue #35362](https://github.com/anthropics/claude-code/issues/35362) — HIGH confidence (closed without native implementation)
- Multi-repo workspace structuring patterns: [Structuring Claude Code for Multi-Repo Workspaces](https://karun.me/blog/2026/03/26/structuring-claude-code-for-multi-repo-workspaces/) — MEDIUM confidence (community article)
- Enterprise governance compliance patterns: [Claude Code Governance](https://www.truefoundry.com/blog/claude-code-governance-building-an-enterprise-usage-policy-from-scratch) — MEDIUM confidence (community article, patterns consistent with official docs)
- `sandbox.denyRead` does not block Read tool: [sandbox denyRead seems ineffective · Issue #32226](https://github.com/anthropics/claude-code/issues/32226) — HIGH confidence (open bug, confirmed by settings doc audit)

---
*Feature research for: Conjure v0.7.0 Plugin-native + Policy-grade*
*Researched: 2026-06-03*
