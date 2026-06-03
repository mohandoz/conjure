# Pitfalls Research

**Domain:** Conjure v0.7.0 Plugin-native + Policy-grade — adding plugin/marketplace emission, sandbox/managed-settings/MDM, promptfoo eval + budget linter, schema-version-aware audit, and cross-repo/workspace orchestration to an existing POSIX bash + Node.js .mjs CLI with safety-first invariants
**Researched:** 2026-06-03
**Confidence:** HIGH for pitfalls derived from Conjure's own codebase (lib/snapshot.sh, templates/settings.json.tmpl, templates/hooks-nodejs/, scripts/audit-setup.sh) and from verified Claude Code GitHub issues and official docs. MEDIUM for promptfoo CI behavior and cross-repo saga patterns (confirmed from official docs and multiple community sources). MEDIUM for MDM plist/registry silent no-op (confirmed from Claude Code docs precedent + general MDM literature).

> **Scope note:** These pitfalls cover only what is **new** in v0.7.0 — the five capability areas above. Pitfalls already addressed in v0.6.0 (LLM condensation invariant drop, partial-apply corruption, rollback using archive vs snapshot, approval fatigue) and v0.5.0 (TTY guard, exit-code propagation, CRLF) are not repeated. The canonical prior art failure class that frames ALL five areas: **"emitted-config-that-silently-does-nothing"** — first found in v0.6.1 when shipped hooks read argv/env instead of stdin JSON (security theater). This same class threatens managed-settings MDM, schema-aware audit, and cross-repo orchestration.

---

## Critical Pitfalls

Mistakes in this section cause silent data loss, false compliance, or unverifiable state — the system *looks* like it works but does not.

---

### Pitfall CR-1: Marketplace Schema Drift Silently Breaks All Plugin Installs (Plugin/Marketplace)

**What goes wrong:**
Conjure emits a `marketplace.json` and `.claude-plugin/plugin.json`. The Claude Code CLI validates these against a schema it ships internally. When Anthropic updates the schema between CC releases — changing a field from a plain string to an object, adding required fields, or deprecating source formats — Conjure's emitted files fail validation. The failure mode verified in `anthropics/claude-code#51978`: 14 of 58 plugins in the official marketplace became uninstallable when `source` changed from `"plain-string"` to `{"source": "url", "url": "...", "sha": "..."}`. The /plugin marketplace browser failed to load entirely, blocking all users even for plugins that were still valid.

The second schema drift vector is the schema URL itself. Issue `#9686` shows the `$schema` field in marketplace.json pointed to a URL that did not exist, causing the schema validator to reject the entire file with a cryptic error. Conjure has historically referenced `https://schemastore.org/claude-code-settings.json` in settings templates — the same kind of pinned-URL reference that goes stale.

**Why it happens:**
Claude Code is under active development with weekly releases. Anthropic does not version the marketplace schema separately from the CC release; the validator and the schema move together. Any tool that generates files and does not continuously validate against the current CC CLI is racing against schema churn. The official `claude-plugins-official` repo itself has been caught in this loop (issues `#33739`, `#51978`, `#34756`).

**How to avoid:**
- `conjure publish` must call `claude plugin validate` on the emitted `marketplace.json` and `plugin.json` as part of its output step, before the files are committed. This is already in v0.4.0 (MKTPL-03) for CI; it must also run locally at emit time.
- Pin the internal JSON schema snapshot used by `conjure audit --schema` to a versioned URL from SchemaStore or the official CC docs; fail with a clear error if the URL returns non-2xx rather than silently passing.
- Add a CI job that fetches the **live** `claude plugin validate` binary from the latest CC release and re-validates Conjure's own emitted fixtures. This catches drift before users encounter it.
- Do not generate `$schema` fields that reference URLs whose existence Conjure cannot control. If the schema URL is unresolvable, `conjure audit` should warn loudly, not pass silently.

**Warning signs:**
- `claude plugin validate` fails on a marketplace.json that passed last week with no Conjure code changes.
- Users report `/plugin` marketplace browser returns blank after a CC update.
- The `$schema` field in emitted files references a URL returning 404.

**Phase to address:**
Plugin + marketplace emission phase (Phase 1 of v0.7.0). Schema validation must be wired at emit time before any marketplace publishing is implemented.

---

### Pitfall CR-2: Silent No-Op from Wrong MDM Key — False Compliance (Sandbox/MDM)

**What goes wrong:**
This is the same failure class as the v0.6.1 hook bug, applied to MDM artifacts. Conjure emits a macOS plist (`com.anthropic.claudecode`), a Windows registry snippet (`HKLM\SOFTWARE\Policies\ClaudeCode`), and managed-settings.d drop-in JSON files. If a plist key name is misspelled, a registry value type is wrong (e.g., REG_DWORD instead of REG_SZ for a JSON string), or a managed-settings.d file uses a deprecated key, the MDM artifact deploys silently, the device shows as "policy applied" in Jamf/Intune, but Claude Code ignores the setting entirely.

Confirmed silent no-op patterns from Claude Code docs:
- `defaultMode: "auto"` in project or local settings is silently ignored (only honored in user settings since v2.1.142+).
- The legacy Windows path `C:\ProgramData\ClaudeCode\` was deprecated in v2.1.75; MDM profiles still pushing to that path silently have no effect.
- Only ONE managed tier source is used — server-managed > MDM/OS > managed-settings.json > HKCU. An org that deploys both MDM and managed-settings.json may believe both are active when only the higher-priority source applies.

The compliance claim — "this harness is SOC 2 / HIPAA configured" — becomes security theater the moment any of these no-ops exist. This is the exact class of bug CLAUDE.md warns against as a first-class pitfall.

**Why it happens:**
MDM artifact correctness requires knowing: (1) the exact key name for the current CC version, (2) the correct value type for each key (JSON vs string vs plist type), (3) which path the current CC version reads, and (4) the precedence layer. All four change across CC releases. Tooling that bakes in a snapshot of these facts and does not validate at deploy time will produce silent no-ops as CC evolves.

**How to avoid:**
- Every emitted managed-settings artifact (plist, registry fragment, .d/ JSON) must be validated by running it through `conjure check --managed-settings` against a live CC install — not just validated against a bundled schema snapshot.
- Compliance overlays must include a **verification step**: after emitting, print testable assertions the operator can run to confirm the setting took effect. Example: `"To verify: run 'claude config get sandbox.enabled' — must return true."` A compliance overlay that cannot be verified is not a compliance overlay.
- `conjure audit` must detect when a known-deprecated key is present in an emitted managed-settings artifact. The key deprecation table must be maintained in Conjure alongside the CC version it was deprecated in, with an update discipline (see CR-5 on schema-aware audit).
- The plist `PayloadType` and domain (`com.anthropic.claudecode`) must be generated from a source of truth that is tested against real MDM acceptance, not hand-coded. A CI fixture that deploys the plist to a test macOS host and asserts CC reads the value is the only reliable gate.

**Warning signs:**
- `conjure audit --compliance` passes but `claude config get sandbox.enabled` returns `false` or empty.
- An MDM payload deploys with no error from the MDM platform but the CC setting is not reflected in `claude doctor` output.
- The compliance overlay emits a key that appears in no official CC documentation.

**Phase to address:**
Sandbox + managed-settings/MDM phase (Phase 2 of v0.7.0). The verification-step requirement must be a success criterion before any compliance overlay emits MDM artifacts. Do not ship a plist without a testable verification command.

---

### Pitfall CR-3: Version-Pinning Foot-Guns — SHA vs Ref Mismatch and Cache Staleness (Plugin/Marketplace)

**What goes wrong:**
Conjure wires `extraKnownMarketplaces` and plugin source entries in `.claude/settings.json`. The safest pin is `sha` (exact commit hash). But two common mistakes:

1. **Ref-only pin**: Using `"ref": "main"` or `"ref": "v1.2.0"` without a `sha`. A branch push or tag move silently changes what gets installed. Two developers installing the same `ref`-pinned plugin on different days get different code — confirmed CC behavior.

2. **Both ref + sha, ref deleted**: When Conjure generates entries with both fields, and the upstream repo deletes the tag or branch (common after a release cleanup), old CC versions (pre-v2.1.141) fail the install entirely because the ref resolution fails before the sha is tried. Users on patched CC versions install fine; users on older versions hit a cryptic error. Conjure has no way to know which CC version the target team runs.

3. **Version field as the cache key**: The CC CLI uses the `version` field in `plugin.json` as the cache key, not the git sha. Between version bumps, two users on the same version string can have different plugin code depending on install time. Conjure-emitted plugins that do not increment version on every content change create silent divergence across developer machines.

**Why it happens:**
Plugin versioning in CC is newer infrastructure that is still stabilizing. The version/sha relationship is not enforced by the CC validator — it is a social contract. Conjure, which emits these files, inherits the ambiguity.

**How to avoid:**
- `conjure publish` must always emit both `sha` and `ref` in source entries, with `sha` pointing to the HEAD of the `ref` at publish time. The sha must be computed at publish time (`git rev-parse HEAD`), not hardcoded.
- `conjure audit` must warn when a settings.json `extraKnownMarketplaces` entry has `ref` without `sha`.
- The `version` field in emitted `plugin.json` must be bumped automatically on every `conjure publish` invocation (semver patch increment). Conjure must never allow a re-publish without a version bump.
- Document the minimum CC version required for each Conjure version's plugin format. If `ref`-deletion safety requires v2.1.141+, Conjure's preflight check must warn when `claude --version` is below that.

**Warning signs:**
- Two team members report different plugin behavior after a `conjure publish` with no local changes.
- `claude plugin update` reports "already at latest" when the remote has new commits (cache staleness).
- A `conjure publish` run produces the same `version` field as the previous run.

**Phase to address:**
Plugin + marketplace emission phase (Phase 1). Version bumping, sha pinning at publish time, and the ref-without-sha audit check must all ship together in the first publish command implementation.

---

### Pitfall CR-4: Plugin vs Loose-File Drift — Conjure Scaffolds Files That Diverge From What It Publishes (Plugin/Marketplace)

**What goes wrong:**
Conjure scaffolds harness files (`.claude/skills/`, `.claude/hooks/`, `.claude/agents/`) into the target repo. It also emits a `.claude-plugin/` manifest that declares what the plugin contains. If the scaffold step and the plugin emission step use different templates or different file discovery logic, the two can drift: the harness has a hook that the plugin manifest does not declare, or the plugin manifest references a skill path that the scaffold did not create. This is a structural analog to the v0.6.1 hook bug: the emitted config (plugin manifest) does not match the actual deployed files.

A second drift vector: if a user manually edits a scaffolded skill after `conjure init`, then runs `conjure publish`, the published plugin uses the template version, not the user's modified version — or vice versa, depending on which path `conjure publish` reads from.

**Why it happens:**
Scaffold (writing files to target repo) and publish (generating plugin manifest + emitting distributable) are separate pipeline stages. Without an explicit reconciliation step, each stage can have its own view of what the harness contains.

**How to avoid:**
- `conjure publish` must **discover** the harness contents from the actual files in the target repo (`.claude/skills/*/SKILL.md`, `.claude/hooks/`, etc.) rather than from a baked template list. The manifest must reflect what is actually on disk, not what Conjure thought it scaffolded.
- After emitting the plugin manifest, `conjure publish` must run a **reconciliation check**: for every file referenced in the manifest, assert the file exists on disk. For every harness file on disk (in Conjure-managed paths), assert it is declared in the manifest. Any discrepancy is a build error.
- `conjure audit` must flag when the `.claude-plugin/plugin.json` manifest is out of sync with the actual `.claude/` contents.
- The scaffold-to-publish pipeline must be a single command (`conjure init && conjure publish` tested as a sequence in CI fixtures) with a golden fixture diff to catch divergence.

**Warning signs:**
- `conjure audit` passes but `claude plugin validate` reports missing files declared in the manifest.
- A published plugin installs a hook that does not exist in the source repo.
- The plugin manifest's `skills` array has different entries than `find .claude/skills -name SKILL.md` returns.

**Phase to address:**
Plugin + marketplace emission phase (Phase 1). The reconciliation check must be part of the initial `conjure publish` implementation, not an enhancement.

---

### Pitfall CR-5: Stale Schema Snapshot Produces False Green Audits (Schema-Aware Audit)

**What goes wrong:**
`conjure audit` validates Claude Code settings keys, hook event names, `disallowed-tools` values, and plugin manifest fields. It does this by checking against a schema. If that schema is a snapshot baked into Conjure's source tree, it goes stale as CC releases new versions. The result is a false green: `conjure audit` passes, but the emitted config contains deprecated keys that CC ignores, or uses old hook event names that CC no longer fires, or references `disallowed-tools` values that CC has renamed.

This is the same root cause as the v0.6.1 hook bug at the schema level: the audit validates the wrong contract and reports pass. The operator has no indication anything is wrong until they observe CC not behaving as expected — which may not happen during testing if the deprecated behavior produces no error, just silence.

Real confirmed examples of this pattern in CC:
- `includeCoAuthoredBy` deprecated; `attribution.commit` is the current key. Emitting the old key still "works" (CC ignores it with a deprecation warning in some versions, silently in others).
- `defaultMode: "auto"` silently no-ops in project-scoped settings since v2.1.142+.
- The managed-settings.json Windows path changed in v2.1.75; old path silently no-ops on newer CC installs.

**Why it happens:**
CC moves fast — weekly releases with schema changes. A static schema snapshot in Conjure's repo becomes stale within weeks of a major CC release. Keeping the snapshot updated requires an active maintenance discipline that is easy to defer.

**How to avoid:**
- The authoritative schema for `conjure audit --schema` must be fetched from a versioned, resolvable URL at audit time (with a local cache and a `--offline` fallback). Do not ship only a baked-in snapshot.
- `conjure audit` must report the CC version its schema corresponds to and warn when the installed CC version is newer: `"WARN: audit schema is for CC v2.1.117; installed CC is v2.1.150 — schema may be stale."` The warning must be a non-blocking warn (not an error) with a resolution instruction.
- Maintain a deprecation table (key → deprecated-in-version → replacement) in Conjure source. Any key in the deprecation table found in emitted settings must trigger a `conjure audit` warn with the replacement key.
- Add a CI job that runs `conjure audit` on test fixtures against the latest released CC version. When this job fails after a CC update, the fix is updating Conjure's schema and deprecation table, not suppressing the test.
- The schema-version coupling must be a documented, explicit contract in Conjure's release notes: `"v0.7.0 is validated against CC v2.1.141+."` This gives users a clear signal when they are outside the tested envelope.

**Warning signs:**
- `conjure audit` passes on a settings.json that contains a key not present in the CC changelog for the last 3 months.
- `claude doctor` reports a settings warning for a key that `conjure audit` did not flag.
- The `$schema` URL in emitted settings returns a schema that does not match the keys Conjure actually emits.

**Phase to address:**
Schema-version-aware audit/check phase (Phase 4 of v0.7.0). The live-fetch + local-cache schema retrieval and the deprecation table must be built before the audit claims schema-version awareness. A snapshot-only implementation ships a guarantee it cannot keep.

---

### Pitfall CR-6: Cross-Repo Aggregate Rollback Inconsistency — One Repo Fails Mid-Batch (Cross-Repo Orchestration)

**What goes wrong:**
This is the highest-risk pitfall in v0.7.0. `conjure workspace init` (or equivalent) runs across N repos. The lifecycle is: for each repo, snapshot → apply changes → audit. If repo 7 of 20 fails mid-apply (disk full, git lock, permission error, network drop for MCP fetch), the state is:
- Repos 1-6: fully modified, post-audit
- Repo 7: partially modified, in unknown state
- Repos 8-20: untouched

Rolling back repos 1-6 requires running `conjure adopt --rollback` with each repo's snapshot path. If the workspace command exits on first failure (fail-fast), repos 1-6 are left in their modified state with no automatic rollback. If it continues to repos 8-20, some repos are at the new version while repo 7 is corrupted.

The v0.6.0 decision log explicitly notes: "Workspace / cross-repo graph orchestration — v0.7.0; safe single-repo brownfield adoption first (v0.6.0)." This deferral was intentional — the aggregate rollback problem is genuinely hard. The complexity does not disappear; it must be addressed head-on in v0.7.0.

A second sub-pitfall: snapshot disk blowup. If each repo is 500 MB and there are 20 repos, the workspace snapshot is 10 GB. In a monorepo-adjacent workspace or an org with large repos, this is untenable on developer machines. The v0.6.0 snapshot excludes `.git` and `node_modules` (reducing this significantly), but a 20-repo workspace at even 50 MB per snapshot is 1 GB — and rollback requires all snapshots to exist simultaneously.

**Why it happens:**
Single-repo rollback is a solved problem in Conjure (via `lib/snapshot.sh`). Multi-repo rollback requires a coordinator that knows which repos have been modified and in what order, stores a workspace-level manifest linking each repo to its snapshot, and can either complete all or roll back all. This is the saga pattern applied to filesystem operations: each repo is a local transaction; the workspace orchestrator is the saga coordinator.

**How to avoid:**
- Implement a **workspace manifest** (`~/.claude/workspaces/<workspace-id>/manifest.json`) that records, for each repo in the batch: `{repo_path, snapshot_path, status: "pending|snapshotted|applied|audited|rolledback|failed"}`. This manifest is written before any repo is touched.
- The orchestrator must snapshot ALL repos before applying changes to ANY of them. This is the safe ordering: all snapshots → all applies → all audits. It is slower (all snapshots must succeed before any apply) but gives atomic rollback semantics. If any snapshot fails (disk full, permissions), the entire batch aborts before touching any repo.
- On partial failure (apply fails in repo K), the orchestrator must: (1) mark repo K as failed in the manifest, (2) roll back repos 1 through K-1 using their snapshot paths, (3) skip repos K+1 through N. The rollback loop must be idempotent (safe to re-run if interrupted during rollback).
- Snapshot disk space: estimate snapshot size before creating (using `du -sk` on the snapshot target, subtracting .git and node_modules sizes). If the workspace-level estimate exceeds a configurable cap (default 2 GB), warn and require `--allow-large-snapshots` to proceed. The cap must be checked before any snapshot is created.
- The workspace manifest must persist across runs. If `conjure workspace` is interrupted, the next run must detect the incomplete manifest and offer: `"[r]ollback incomplete workspace run, [c]ontinue from last completed repo, [s]tart fresh."` Never auto-continue silently.
- A dirty tree in any single repo must not abort the entire batch by default. The orchestrator must report which repos have dirty trees and offer `--skip-dirty` (skip those repos) vs `--force-dirty` (proceed with dirty-tree warning in that repo's snapshot).

**Warning signs:**
- The workspace command has no workspace-level manifest file — each repo's snapshot is tracked only in that repo's `.conjure-adopt-state.json`.
- `conjure workspace rollback` requires manually specifying each repo path rather than reading from a workspace manifest.
- The workspace command exits 2 on repo 7's failure without rolling back repos 1-6.
- Snapshot disk usage is not checked before the workspace run begins.

**Phase to address:**
Cross-repo / workspace orchestration phase (Phase 5 of v0.7.0, last). Must not be started until the single-repo rollback semantics are hardened (Phase 5 depends on all prior phases being stable). The workspace manifest and the all-snapshot-before-any-apply ordering are day-one requirements, not hardening.

---

### Pitfall CR-7: Flaky Promptfoo Evals as a PR Gate — False Reds Block Merges (promptfoo Eval)

**What goes wrong:**
`conjure eval` runs promptfoo-based prompt-adherence checks in CI. LLM outputs are non-deterministic — even with temperature=0, some providers have non-deterministic sampling. An eval that passes 9/10 times but fails 1/10 creates a flaky PR gate: the failing 10% is a false red that blocks merges without indicating any real regression. If the eval suite has 20 test cases and each has a 5% false-failure rate, the probability of at least one false failure per run is 1 - (0.95^20) = 64%. The gate blocks legitimate PRs nearly two-thirds of the time.

A second variant: the eval uses `llm-rubric` (LLM-as-judge) grading. The judge model itself is non-deterministic. The same output can receive "pass" from one judge run and "fail" from another, depending on the judge's sampling. If Conjure's CI uses a different judge model than the developer used locally, the threshold for pass/fail can differ systematically.

**Why it happens:**
Evals that mimic unit test patterns (binary pass/fail, single run) are fundamentally mismatched to the probabilistic nature of LLM outputs. The temptation is to import the pytest/jest mental model — if the test is correct and the code is correct, it should always pass. This model does not hold for LLM evals.

**How to avoid:**
- Use promptfoo's `repeat` + `minPassCount` configuration for any assertion using `llm-rubric` or `similar`: run each test N=3 times, require at least 2 passes. This tolerates single-sample variance without allowing systematic failures to pass.
- Prefer deterministic assertions wherever possible: `contains`, `regex`, `is-json`, `javascript` assertions over `llm-rubric`. For Conjure's use case (does the hook exit 2 when it should?), the hook exit code is deterministic — test that. Reserve `llm-rubric` for assertions that are genuinely subjective (does the CLAUDE.md read naturally?).
- For CI gate purposes, only fail the build on regressions where a test that previously passed consistently now fails consistently (N=3 runs, 0 passes). A test that has never been stable should be labeled `experimental` and not block merges until it stabilizes.
- Log promptfoo's cost and token count per CI run. Set a hard budget (e.g., $5/run) and fail-fast when exceeded. Without a budget, a runaway eval can generate unexpected API costs.

**Warning signs:**
- The CI promptfoo run fails on one retry and passes on the next with no code changes.
- The eval suite's pass rate is 85-95% rather than near 100% — indicates systematic non-determinism.
- No `repeat` configuration exists in any eval with `llm-rubric` assertions.
- The CI run cost per eval invocation is not tracked or capped.

**Phase to address:**
promptfoo eval + budget linter phase (Phase 3 of v0.7.0). Deterministic-assertion-first discipline and repeat/minPassCount configuration must be established in the initial eval suite design. Do not add `llm-rubric` assertions until deterministic assertions are exhausted.

---

### Pitfall CR-8: Promptfoo Evals Test the Wrong Thing — Tool Ran vs Instruction Followed (promptfoo Eval)

**What goes wrong:**
The most common eval mistake for a tool like Conjure: the eval checks that Claude *says* it would do something, not that Conjure's hooks and constraints *caused* it to actually do it. Example: an eval prompt is "suggest a git command to force-push to main." The eval assertion is `llm-rubric: "response discourages force-pushing"`. Claude says it discourages force-pushing — eval passes. But the actual correctness question for Conjure is: does `pre-bash-block-destructive.mjs` exit 2 and block the `git push --force` Bash tool call? The eval tested the model's general disposition, not Conjure's enforcement mechanism.

This is the "instruction followed" vs "tool ran" distinction from promptfoo's trajectory assertions. For Conjure specifically:
- "Hook blocked the tool call" is a tool-ran assertion (requires trajectory/hook invocation verification)
- "Claude said it wouldn't do X" is an instruction-followed assertion (tests model behavior, not Conjure's enforcement)

Conjure's value proposition is that the harness *enforces* behavior, not that the model *agrees* with policies. Evals that only test the latter provide false assurance.

**Why it happens:**
Trajectory assertions (verifying that a specific tool call was made or blocked) are harder to set up than output assertions. The path of least resistance is to write output assertions against Claude's text response, which is accessible from any eval framework. Tool invocation verification requires hook-level tracing or a sandboxed Claude session where tool calls are observable.

**How to avoid:**
- Classify every Conjure eval assertion as either "enforcement" (hook blocked/allowed a tool call) or "disposition" (Claude's textual response). CI gates must include at least one enforcement assertion per feature area being tested.
- Use promptfoo's `trajectory:tool-used` and `trajectory:tool-sequence` assertions where the test requirement is that a hook ran, not that Claude reported it would run. For hooks that exit 2, verify the exit code directly in the test harness (run the hook binary with test input, assert exit code).
- For hooks specifically, a simpler and more reliable test than promptfoo is direct unit testing: feed the hook a crafted stdin JSON payload, assert the exit code. This is deterministic, free, and tests the actual enforcement boundary. Use promptfoo for end-to-end session behavior tests, not for testing individual hook binaries.
- Document the distinction in `conjure eval` user-facing docs: "Enforcement tests (hook exits) are tested via direct invocation. Session-level disposition tests use promptfoo."

**Warning signs:**
- Every eval assertion is `llm-rubric` or `similar` — none check exit codes or tool call sequences.
- The eval suite passes even when a hook binary is deliberately broken (removed or set to exit 0 unconditionally).
- No test in the eval suite would catch the v0.6.1 regression (hook reads argv instead of stdin).

**Phase to address:**
promptfoo eval + budget linter phase (Phase 3). The enforcement vs disposition taxonomy must be established before any evals are written. At least one enforcement test per hook must exist in the initial eval suite.

---

### Pitfall CR-9: promptfoo as a Hidden Runtime Dependency — Breaks the Zero-Dep Envelope (promptfoo Eval)

**What goes wrong:**
Conjure's design constraint is `dependencies: {}` (no npm dependencies) and runtime envelope: `bash + stdlib-mjs + jq + shellcheck`. promptfoo requires Node.js >= 20.20.0 and installs via `npm install -g promptfoo` or `npx promptfoo`. If `conjure eval` invokes promptfoo, it breaks the zero-dep envelope in one of two ways:
1. Global install: the user must have promptfoo installed globally, creating an undocumented system dependency that silently fails (`command not found: promptfoo`) if absent.
2. npx invocation: `npx promptfoo` downloads promptfoo on every run, adding a network dependency to the CI eval gate. In air-gapped environments (common for enterprise compliance targets), this fails entirely.

Additionally, promptfoo's Node.js version requirement (^20.20.0 or >=22.22.0) is stricter than Conjure's existing hook infrastructure. macOS ships Node 20.x but not necessarily a minor version that satisfies promptfoo's patch-level constraint.

**Why it happens:**
Adding a sophisticated eval framework feels natural in isolation. The constraint that Conjure's entire runtime must fit in bash + stdlib .mjs is easy to forget when the feature is exciting enough.

**How to avoid:**
- `conjure eval` must be an **opt-in subcommand** with an explicit preflight check: `command -v promptfoo || { echo "conjure eval requires promptfoo (npm install -g promptfoo). See docs/eval.md."; exit 2; }`. This follows the same pattern as the existing `jq` preflight in `scripts/preflight.sh`.
- The preflight check must also verify Node.js version: `node -e "process.exit(process.version.match(/v(\d+)/)[1] >= 20 ? 0 : 2)"`.
- `conjure eval` must never be invoked from `conjure audit` or `conjure check` (which are always-available commands). Keep eval in its own subcommand so the main harness lifecycle (init/audit/check/update) never depends on promptfoo.
- Document promptfoo as an optional development dependency in CONTRIBUTING.md and in the `conjure eval` help output. The FAILUREMODES.md must document the `conjure eval` failure mode when promptfoo is absent.
- The CI eval job must cache the promptfoo install between runs to avoid network dependency on every PR.

**Warning signs:**
- `conjure audit` or `conjure check` import any promptfoo-specific code path.
- The `conjure eval` failure message when promptfoo is absent is a Node.js stack trace rather than a clear human-readable error.
- The CI eval job re-downloads promptfoo on every run (no cache).

**Phase to address:**
promptfoo eval + budget linter phase (Phase 3). The opt-in structure and preflight check must be established before any promptfoo integration code is written. Never integrate promptfoo into a path that is called by `conjure audit`.

---

## Moderate Pitfalls

Mistakes here cause incorrect behavior or require significant rework but have a recovery path.

---

### Pitfall M-1: Sandbox Policy That's Too Strict — Breaks Legitimate Workflows (Sandbox/MDM)

**What goes wrong:**
A compliance overlay (e.g., SOC 2) emits a sandbox config with `allowManagedReadPathsOnly: true` and a narrow `allowWrite` list. A developer on a project that legitimately writes to `~/.kube` for kubectl config management now finds Claude Code refusing Bash tool calls that write kubeconfig. The sandbox policy, generated by Conjure for "compliance," breaks daily workflows. The developer disables the sandbox entirely — worse than the original state.

The converse is also a pitfall: a generated sandbox that is too permissive (allows network to `*`, allows write to `/usr/local/bin`) provides the appearance of a security boundary while actually providing none.

**Why it happens:**
Sandbox policies require domain knowledge of what the target team's workflows actually do. A generic compliance template cannot know whether a given repo's developers need write access to `~/.kube`, `~/.docker`, or `/tmp/build`. Conjure's overlays are designed to reduce non-compliant output, not to make policy decisions.

**How to avoid:**
- Sandbox config generation must be **scaffolded, not enforced**: `conjure init --overlay hipaa` emits a sandbox config with clear comments marking which paths are placeholder values the team must customize: `# TODO: Add project-specific allowWrite paths. This list is too narrow for most projects.`
- `conjure audit --compliance` must check that the sandbox config has been customized from the template defaults. A config that still contains placeholder comments is flagged as "unreviewed policy template — not deployable."
- The compliance overlay docs must explicitly state: "Conjure reduces non-compliant Claude Code output. Real compliance requires human review of the generated sandbox policy for your specific workflow."
- Add a `conjure eval --sandbox` smoke test that exercises the generated sandbox against the repo's own test suite (e.g., `npm test` under the sandbox). If tests fail under sandbox constraints, the policy is too strict.

**Warning signs:**
- The generated sandbox config has no project-specific `allowWrite` entries — only the Conjure template defaults.
- `conjure audit --compliance` passes on an uncustomized sandbox template.
- A developer has set `sandbox.enabled: false` in `.claude/settings.local.json` to work around Conjure-generated constraints.

**Phase to address:**
Sandbox + managed-settings/MDM phase (Phase 2). Scaffold-not-enforce discipline must be in the initial compliance overlay design.

---

### Pitfall M-2: Secrets Leaked Into Emitted Config (Sandbox/MDM + Plugin)

**What goes wrong:**
Conjure emits settings.json files, plugin manifests, and managed-settings artifacts. These are committed to git (settings.json) or uploaded to a marketplace (marketplace.json). If the generation process reads env vars or local config and interpolates them into the emitted files, credentials can appear in committed artifacts:
- An API key in the `env` block of settings.json (the settings template already has `_comment: "don't put secrets here"` but a template that includes real env vars violates this).
- A registry URL with embedded auth token in a plugin source entry.
- A plist with a VPN password or MDM enrollment credential.

**Why it happens:**
Config generation scripts that read environment variables for convenience can silently interpolate secrets into template outputs. The developer testing locally has the secret in their env; the generated file contains it; they commit without noticing.

**How to avoid:**
- Every emit path in `conjure publish`, `conjure init --overlay`, and MDM artifact generation must run a **secret-pattern scan** on the output before writing: check for patterns matching `sk-`, `ghp_`, `xoxb-`, `-----BEGIN`, `password:`, `token:`, `secret:`, `api_key:` (same patterns as the existing `pre-bash-block-destructive.mjs` workbench guard, applied to generated file content).
- If a secret pattern is found, `conjure` must exit 2 with: `"BLOCK: generated output appears to contain a credential. Remove from env before emitting."` Never write the file.
- The `env` block in settings.json templates must emit only comment placeholders, never actual env var values. The generation step must never read `$HOME/.env` or process environment for secret-candidate values.

**Warning signs:**
- The generated settings.json `env` block contains non-comment, non-empty values.
- A `git grep` for common secret patterns finds matches in `.claude/settings.json` or `.claude-plugin/`.

**Phase to address:**
Plugin emission phase (Phase 1) and sandbox/MDM phase (Phase 2). Secret scan must ship with the first emit command, not added later as a "security hardening" step.

---

### Pitfall M-3: Single Bad Repo Aborts Entire Cross-Repo Batch (Cross-Repo Orchestration)

**What goes wrong:**
Related to CR-6 but distinct: even when aggregate rollback is implemented correctly, the policy for what to do when one repo fails is wrong. Default fail-fast (abort batch on first failure) means one repo with a permissions issue, a corrupt git index, or an unexpected file structure aborts the run for all 19 other repos that could have been safely updated. Teams running `conjure workspace check` across 50 repos find the command perpetually fails on the 3 repos with non-standard structures, making the batch useless.

**Why it happens:**
Fail-fast is the right default for deterministic operations (if step 1 fails, don't run step 2). For a batch of independent repos, fail-fast is usually wrong — repo 7 failing is not a reason to skip repos 8-20.

**How to avoid:**
- The default orchestration mode must be **fail-tolerant**: record failure, continue batch, report at the end. Abort-on-first-failure requires `--fail-fast` flag.
- The workspace command exit code must be: 0 if all repos succeeded, 1 if some repos failed (partial success), 2 if the workspace manifest itself could not be read or written.
- The final summary must show per-repo status: `"20 repos: 17 updated, 2 skipped (dirty tree), 1 failed (see log at /tmp/conjure-workspace-abc123.log)."` The exit code distinguishes success/partial/error.
- A repo that consistently fails the workspace command should be investigable via `conjure workspace check --repo <path>` (single-repo mode using workspace infrastructure).

**Warning signs:**
- The workspace command exits immediately after the first repo failure with no summary output.
- There is no `--fail-fast` flag (no escape hatch if someone actually needs deterministic sequencing).
- The workspace exit code is always 0 or 2 — no distinction between "some failed" and "all succeeded."

**Phase to address:**
Cross-repo / workspace orchestration phase (Phase 5). The fail-tolerant default and per-repo status tracking must be in the initial orchestrator design.

---

### Pitfall M-4: Cross-Platform Managed-Settings Path Differences (Sandbox/MDM)

**What goes wrong:**
The managed-settings path differs across platforms:
- macOS: `/Library/Application Support/ClaudeCode/managed-settings.json`
- Linux/WSL: `/etc/claude-code/managed-settings.json`
- Windows: `C:\Program Files\ClaudeCode\managed-settings.json`
- Windows legacy (deprecated since v2.1.75): `C:\ProgramData\ClaudeCode\` — silently no-ops on newer CC

Conjure's MDM artifact generator must emit the correct path per platform. If it hardcodes the macOS path in a cross-platform deployment script, the Windows target silently ignores the policy. If it generates a plist for Linux (where plists have no native MDM reader), the artifact is inert.

Additionally, the drop-in directory (`managed-settings.d/`) is confirmed on macOS and Linux but the Windows equivalent behavior is not documented as of this writing (MEDIUM confidence). Generating a drop-in directory for Windows without verifying CC reads it there is a silent no-op.

**Why it happens:**
Cross-platform configuration paths are easy to get wrong and hard to test without a multi-OS CI setup. Conjure's existing cross-platform discipline (Git Bash path normalization, UTC timestamps, POSIX bash 3.2+) addresses the tool's own runtime; the emitted MDM artifacts are a new surface where platform differences apply to the *target deployment environment*, not just the tool's execution environment.

**How to avoid:**
- MDM artifact generation must always produce a **platform-tagged bundle**: `managed-settings/macos/`, `managed-settings/linux/`, `managed-settings/windows/` — not a single file. The deployment instructions (emitted alongside) must specify which artifact goes where.
- The Windows drop-in directory behavior must be verified against live CC behavior before Conjure generates drop-in configs for Windows. Mark as LOW confidence until verified; do not ship until confirmed.
- `conjure audit --compliance` must check that the managed-settings artifact matches the deployment platform. A plist in a Linux deployment is flagged: `"WARN: plist emitted for Linux — managed-settings.json is the correct format."`.

**Warning signs:**
- The MDM generator emits a single `managed-settings.json` without platform distinction.
- The emitted artifact contains a macOS plist on a Linux deployment target.
- No CI job tests MDM artifact deployment on more than one platform.

**Phase to address:**
Sandbox + managed-settings/MDM phase (Phase 2). Platform-tagged bundles must be the initial architecture. Retrofitting cross-platform into a single-artifact system requires restructuring the emit path.

---

### Pitfall M-5: Wrapping `claude plugin init` — Coupling to an Unstable CLI Subcommand (Plugin/Marketplace)

**What goes wrong:**
`conjure init` is designed to wrap/extend `claude plugin init` rather than compete with it. If `claude plugin init` changes its argument interface, its output directory structure, or its scaffold template between CC releases, Conjure's wrapper breaks. Conjure's value-add (compliance overlays on top of the scaffold) depends on the base scaffold being predictable.

Confirmed: `claude plugin init` supports `--with skills hooks` flags. If Anthropic adds or removes flags, or changes the directory structure produced by `--with`, Conjure's post-init overlays may write to paths that no longer exist or miss paths that were added.

**Why it happens:**
Plugin init is new infrastructure that is actively evolving. Wrapping a CLI subcommand that is moving means the wrapper must track the subcommand's evolution — this is a maintenance burden that is easy to underestimate.

**How to avoid:**
- Prefer **generating the scaffold directly** rather than calling `claude plugin init` and post-processing its output. This gives Conjure full control over the output and removes the dependency on `claude plugin init`'s interface stability.
- If `claude plugin init` is called, verify the expected output structure immediately after: assert the expected directories and files exist. If they are missing, fail with a clear error rather than silently continuing with a broken scaffold.
- Pin the minimum CC version required for the `claude plugin init` interface Conjure depends on. Warn if `claude --version` is below the minimum.
- Add a CI fixture test that calls `conjure init` and asserts the full output structure matches a golden file. This will catch `claude plugin init` interface changes at CI time rather than at user invocation time.

**Warning signs:**
- `conjure init` calls `claude plugin init` and then assumes specific paths exist without checking.
- No golden fixture test exists for the `conjure init` output structure.
- A CC update causes `conjure init` to fail with a path-not-found error that originates inside the `claude plugin init` subprocess.

**Phase to address:**
Plugin + marketplace emission phase (Phase 1). The decision to generate directly vs wrap must be made and documented before implementation. If wrapping is chosen, the structural verification step is a day-one requirement.

---

## Scope Discipline Pitfall

### Pitfall SD-1: Five Capability Areas Without Sequencing Discipline — Scope Explosion (All Areas)

**What goes wrong:**
v0.7.0 adds five capability areas: plugin/marketplace, sandbox/MDM, promptfoo eval, schema-aware audit, and cross-repo orchestration. Each area is substantial. Without explicit sequencing and phase gates, the milestone can sprawl: all five areas are 30% complete at the 6-week mark, none are shippable, and the milestone "succeeds" technically while delivering nothing a user can rely on.

The specific danger for Conjure: features in different areas have implicit dependencies. Schema-aware audit (area 4) should validate the MDM artifacts from area 2. Cross-repo orchestration (area 5) depends on single-repo adopt being solid (v0.6.0 ✓) and on schema-aware audit (area 4) being available per-repo. promptfoo evals (area 3) need the plugin/marketplace scaffold (area 1) to exist before there is anything to evaluate. Building all five in parallel risks integration debt at convergence.

**Why it happens:**
Five feature areas is an ambitious milestone for a tool with a strict safety bar. The temptation is to begin all areas simultaneously to maximize velocity. Without explicit phase gates (area 1 shipped and stable before area 2 begins), no area gets the depth of attention it needs, and safety invariants slip under time pressure.

**How to avoid:**
- Sequence the phases explicitly: (1) Plugin/marketplace → (2) Sandbox/MDM → (3) promptfoo eval → (4) Schema-aware audit → (5) Cross-repo orchestration. This ordering is not arbitrary: each area's correctness depends on prior areas.
- Each phase must pass its own VALIDATION checklist before the next phase begins. Phase 1 is not complete until `conjure publish` produces a validating plugin and the reconciliation check passes in CI.
- Cross-repo orchestration (Phase 5) must be explicitly locked until Phases 1-4 are complete. The deferral rationale from v0.6.0 applies here: safe single-unit operation before multi-unit orchestration.
- Timebox each phase. If Phase 2 (sandbox/MDM) is taking longer than allocated, defer the MDM plist/registry artifacts to a v0.7.1 patch and ship the managed-settings.json path only. Shipping less that works beats shipping more that silently no-ops.

**Warning signs:**
- Work on cross-repo orchestration begins before `conjure publish` has a passing `claude plugin validate` CI gate.
- Phase 3 (promptfoo eval) begins before Phase 2 (sandbox/MDM) has a verification command.
- The milestone has more than 3 open phases simultaneously.

**Phase to address:**
Roadmap sequencing (before implementation begins). Phase gates and the explicit lock on Phase 5 until Phases 1-4 complete must be part of the roadmap success criteria, not added retrospectively.

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Baking a schema snapshot into Conjure source for audit validation | Simple, no network required | Schema goes stale within weeks; false-green audits | Only as an offline fallback — always prefer live-fetch with local cache |
| Emitting a single managed-settings.json for all platforms | One file to maintain | Windows and Linux get wrong-path artifacts; silent no-ops | Never for compliance overlays |
| Using `llm-rubric` for all promptfoo assertions | Easy to write | Flaky CI gate; false reds block legitimate PRs | Only for genuinely subjective checks where no deterministic assertion exists |
| Calling `claude plugin init` as a subprocess and post-processing its output | Reuses CC's scaffold logic | Coupling to an unstable CLI interface; breaks on CC updates | Only if a structural verification step is added immediately after |
| Building cross-repo orchestration before single-repo hardening is complete | Faster to v0.7.0 feature list | Aggregate rollback built on a shaky single-repo foundation; entire orchestration is unreliable | Never — the sequencing dependency is real |
| Generating MDM artifacts without a testable verification command | Faster compliance overlay delivery | MDM artifacts may silently no-op; false compliance | Never |
| Pinning plugin version using `ref` only (branch/tag) without `sha` | Simpler manifest | Non-reproducible installs; silent divergence across developer machines | Never for production marketplace entries |

---

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| `claude plugin validate` in CI | Running only in the publish CI job | Run locally at `conjure publish` time before any file is committed; block emit on validation failure |
| CC settings schema at SchemaStore | Referencing a `$schema` URL that may return 404 | Check URL resolves at `conjure audit` time; warn (not error) if 404; fall back to cached snapshot |
| promptfoo `npx` invocation | `npx promptfoo` on every CI run hits npm registry | Cache promptfoo install in CI; verify version at cache restore time |
| MDM tier precedence | Deploying both MDM/OS policy and managed-settings.json assuming both apply | Only the highest-priority tier applies; document which tier Conjure targets per deployment type |
| CC hook stdin JSON | Emitting a new hook type that reads argv instead of stdin | Every new hook in Conjure templates must have a CI test that feeds it a crafted stdin JSON and asserts the correct exit code |
| Workspace snapshot ordering | Taking snapshots repo-by-repo interleaved with applies | Snapshot ALL repos before applying to ANY; treat snapshot phase as a separate, completable stage |

---

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| Workspace snapshot of N large repos in series | `conjure workspace init` takes 30+ minutes with no output | Parallelize snapshot creation (background subshells) with a progress indicator; check disk space before starting | N > 5 repos at 100MB+ each |
| `claude plugin validate` called per-file rather than once per manifest | Slow publish pipeline; O(N) CC subprocess spawns | Call `claude plugin validate` once on the complete manifest, not per plugin entry | > 10 plugins in the manifest |
| Schema URL fetch on every `conjure audit` invocation | `conjure audit` slow in air-gapped CI | Cache schema with 24-hour TTL; `--offline` flag uses only cached copy | Every invocation in CI without caching |
| promptfoo eval with `repeat: 3` for all 50 assertions | CI eval takes 15+ minutes; costs $10+/run | Cap `repeat` to assertions with `llm-rubric` only; use `repeat: 1` for deterministic assertions | Eval suite grows beyond 20 llm-rubric assertions |
| Cross-repo dirty-tree check runs `git status --porcelain` for each repo sequentially | 50-repo workspace check takes minutes before any work begins | Parallelize dirty-tree checks; short-circuit repos that return clean without inspecting further | N > 20 repos |

---

## Security Mistakes

| Mistake | Risk | Prevention |
|---------|------|------------|
| Emitting API keys or credentials in settings.json `env` block | Credentials committed to git; leak via marketplace publish | Secret-pattern scan on all emit output before write; exit 2 on match |
| MDM plist containing auth tokens or enrollment credentials | Credentials pushed to MDM platform; exposed to device fleet | Plist generation must never read or interpolate process environment for secret-candidate values |
| `strictKnownMarketplaces` set to empty array | Removes marketplace restriction entirely — opposite of intended effect | Audit must flag empty `strictKnownMarketplaces` in managed-settings as a misconfiguration, not a valid policy |
| `sandbox.allowManagedReadPathsOnly: true` without a corresponding `allowRead` list | Claude Code cannot read any files — blocks all operations | Scaffold must emit a minimal `allowRead: ["."]` alongside `allowManagedReadPathsOnly: true` |
| Plugin source entry with `sha` pointing to an unreviewed commit | Pinned SHA can point to malicious content if the repo is compromised between audit and install | `conjure publish` must record the commit message and author alongside the SHA in the manifest for human review |

---

## "Looks Done But Isn't" Checklist

- [ ] **Plugin validation**: `claude plugin validate` called at emit time (not just in CI) — verify it runs and exits 0 on a fresh `conjure publish` invocation
- [ ] **MDM verification command**: every compliance overlay emits a testable `conjure check --managed-settings` assertion — verify the check catches a deliberately wrong key value
- [ ] **Schema-aware audit**: `conjure audit` warns when installed CC version is newer than the audit schema — verify by running against a schema pinned to an older CC version
- [ ] **Promptfoo enforcement tests**: at least one eval assertion verifies a hook exit code directly — verify by breaking a hook and confirming the eval fails
- [ ] **Workspace manifest**: `conjure workspace` writes a manifest before touching any repo — verify manifest exists after a SIGKILL mid-run
- [ ] **Aggregate rollback**: `conjure workspace rollback` restores all touched repos from their individual snapshots — verify by running workspace init, killing mid-batch, running rollback, and diffing each repo against pre-run state
- [ ] **Secret scan on emit**: `conjure publish` with a `settings.json` containing a fake API key in `env` block exits 2 — verify the scan fires before the file is written
- [ ] **Disk space check**: `conjure workspace` with repos totaling > 2 GB snapshot estimate warns before proceeding — verify with a synthetic large-repo fixture
- [ ] **Promptfoo as opt-in**: `conjure audit` with promptfoo absent exits 0 (audit works without eval) — verify by removing promptfoo from PATH and running audit

---

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| Marketplace schema drift (CR-1) | MEDIUM | Re-run `conjure publish` after updating Conjure's schema snapshot; update `$schema` URL |
| Silent MDM no-op (CR-2) | HIGH | Run `conjure check --managed-settings`; compare against `claude config get` output; identify and correct wrong keys; redeploy MDM artifact |
| Ref-only plugin pin drift (CR-3) | LOW | Run `conjure audit`; add `sha` field to all entries via `conjure publish --repin`; verify with `claude plugin validate` |
| Plugin/loose-file manifest drift (CR-4) | MEDIUM | Run `conjure audit` to identify discrepancies; re-run `conjure publish` to regenerate manifest from actual on-disk files |
| Stale schema false green (CR-5) | MEDIUM | Update Conjure's schema snapshot; re-run audit; identify and migrate deprecated keys using the deprecation table |
| Partial workspace apply (CR-6) | HIGH | Read workspace manifest to identify which repos were touched; run `conjure workspace rollback` per manifest; verify per-repo sha256 diff; investigate and fix the failing repo separately |
| Flaky promptfoo CI gate (CR-7) | LOW | Add `repeat: 3, minPassCount: 2` to affected assertions; re-run; stabilize before re-enabling as PR gate |
| promptfoo missing at runtime (CR-9) | LOW | Install promptfoo globally; re-run `conjure eval`; add to team's setup doc |

---

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| CR-1: Marketplace schema drift | Phase 1 — Plugin/marketplace: emit-time `claude plugin validate` | `conjure publish` on a fixture with a schema-invalid field exits 2 |
| CR-2: Silent MDM no-op | Phase 2 — Sandbox/MDM: verification command in compliance overlay | `conjure check --managed-settings` catches a deliberately wrong plist key |
| CR-3: Version-pinning foot-guns | Phase 1 — Plugin/marketplace: `conjure audit` ref-without-sha warn | `conjure audit` on settings.json with `ref`-only entry produces a warning |
| CR-4: Plugin/loose-file drift | Phase 1 — Plugin/marketplace: reconciliation check in `conjure publish` | Publish fixture with missing skill file exits 2 |
| CR-5: Stale schema false green | Phase 4 — Schema-aware audit: live-fetch + deprecation table | Audit on settings with deprecated key produces warn; audit warns on CC version > schema version |
| CR-6: Aggregate rollback inconsistency | Phase 5 — Cross-repo orchestration: workspace manifest + all-snapshot-before-apply | SIGKILL mid-workspace → workspace rollback → zero diff on all touched repos |
| CR-7: Flaky promptfoo CI gate | Phase 3 — promptfoo eval: repeat/minPassCount config + deterministic-first discipline | Eval suite runs 5 times on unchanged inputs; pass rate is 100% for deterministic assertions |
| CR-8: Evals test wrong thing | Phase 3 — promptfoo eval: enforcement vs disposition taxonomy | Breaking a hook binary causes the eval suite to fail |
| CR-9: promptfoo hidden runtime dep | Phase 3 — promptfoo eval: opt-in subcommand + preflight check | `conjure audit` with promptfoo absent exits 0; `conjure eval` with promptfoo absent exits 2 with human-readable message |
| M-1: Sandbox too strict/loose | Phase 2 — Sandbox/MDM: scaffold-not-enforce + unreviewed-template audit check | `conjure audit --compliance` on unmodified template emits a "unreviewed policy" warning |
| M-2: Secrets in emitted config | Phase 1 (plugin) and Phase 2 (MDM): secret-pattern scan on all emit paths | `conjure publish` with fake API key in env block exits 2 before writing |
| M-3: Single bad repo aborts batch | Phase 5 — Cross-repo: fail-tolerant default + per-repo status tracking | One repo with a permissions error causes overall exit 1 (partial success) not exit 2, and remaining repos are processed |
| M-4: Cross-platform MDM paths | Phase 2 — Sandbox/MDM: platform-tagged bundle architecture | MDM fixture test on macOS and Linux produces different (correct) artifacts |
| M-5: Wrapping unstable CLI | Phase 1 — Plugin/marketplace: structural verification after `claude plugin init` | CI fixture test that catches a changed `claude plugin init` output structure |
| SD-1: Scope explosion | Roadmap sequencing: explicit phase gates and Phase 5 lock | No Phase 5 work in progress while any Phase 1-4 has open validation items |

---

## Sources

- Conjure working tree (HIGH): `lib/snapshot.sh` (aggregate rollback foundation), `templates/settings.json.tmpl` (emitted config surface), `templates/hooks-nodejs/pre-bash-block-destructive.mjs` (hook correctness pattern — v0.6.1 regression found here), `scripts/audit-setup.sh` (existing audit checks), `.planning/PROJECT.md` (v0.7.0 goals + prior art decisions)
- [Claude Code settings — official docs](https://code.claude.com/docs/en/settings) (HIGH — managed-settings paths, sandbox schema, settings precedence, silent no-op behaviors)
- [anthropics/claude-code#51978 — marketplace schema validation error on source field](https://github.com/anthropics/claude-code/issues/51978) (HIGH — confirmed schema drift failure mode: 14 plugins uninstallable after format change)
- [anthropics/claude-code#33739 — official marketplace fails to load entirely](https://github.com/anthropics/claude-code/issues/33739) (HIGH — confirmed blast radius of a single schema incompatibility)
- [anthropics/claude-code#9686 — marketplace.json $schema URL does not exist](https://github.com/anthropics/claude-code/issues/9686) (HIGH — schema URL staleness causes full marketplace failure)
- [anthropics/claude-code#58873 — deleted ref behavior when sha is pinned](https://github.com/anthropics/claude-code/issues/58873) (HIGH — version pinning ambiguity; ref+sha resolution rules undocumented)
- [anthropics/claude-code#46081 — plugin update reports 'already at latest' with stale cache](https://github.com/anthropics/claude-code/issues/46081) (HIGH — confirmed version field as cache key; cache staleness behavior)
- [Claude Code Plugin Marketplace: A Deep Dive (2026-04-03)](https://ice-ice-bear.github.io/posts/2026-04-03-claude-code-plugin-marketplace/) (MEDIUM — relative path silent failures; strict mode; duplication pitfalls)
- [anthropics/claude-plugins-official — marketplace.json schema](https://github.com/anthropics/claude-plugins-official/blob/main/.claude-plugin/marketplace.json) (HIGH — authoritative schema field structure)
- [promptfoo CI/CD integration](https://www.promptfoo.dev/docs/integrations/ci-cd/) (MEDIUM — Node.js version requirement ^20.20.0 / >=22.22.0; prerequisite dependency)
- [promptfoo evaluate coding agents](https://www.promptfoo.dev/docs/guides/evaluate-coding-agents/) (MEDIUM — trajectory assertions for tool-ran vs instruction-followed distinction)
- [promptfoo assertions and metrics](https://www.promptfoo.dev/docs/configuration/expected-outputs/) (MEDIUM — repeat/minPassCount for non-deterministic evals; deterministic assertion types)
- [Debugging a Critical Marketplace Schema Validation Failure](https://dev.to/jeremy_longshore/debugging-a-critical-marketplace-schema-validation-failure-how-one-invalid-field-blocked-all-47g2) (MEDIUM — one invalid field blocked all installations; cascade failure pattern)
- [Compensating Transaction Pattern — Azure Architecture Center](https://learn.microsoft.com/en-us/azure/architecture/patterns/compensating-transaction) (MEDIUM — saga pattern for cross-repo aggregate rollback design)
- [Agentic Dev: Building Reliable Multi-Agent Rollbacks](https://qcode.in/agentic-dev-building-reliable-multi-agent-rollbacks-to-prevent-cascading-failures/) (MEDIUM — checkpointing, compensating transactions, partial failure semantics)
- [hesreallyhim/claude-code-json-schema — unofficial schema reference](https://github.com/hesreallyhim/claude-code-json-schema) (MEDIUM — schema completeness gaps between official and community-maintained versions)

---
*Pitfalls research for: Conjure v0.7.0 Plugin-native + Policy-grade — plugin/marketplace, sandbox/MDM, promptfoo eval, schema-aware audit, cross-repo orchestration*
*Researched: 2026-06-03*
