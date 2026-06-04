# Feature Research — v0.8.0 Operability + DX

**Domain:** CLI harness scaffolding — diagnostics, telemetry insights, eval regression, init wizard polish, live UAT, documentation refresh
**Researched:** 2026-06-04
**Milestone:** v0.8.0 — Operability + DX
**Confidence:** HIGH for doctor/stats (prior art well documented, existing preflight.sh + telemetry JSONL already ship); HIGH for eval regression (promptfoo baseline pattern confirmed in official docs + community); MEDIUM for init wizard (prior art clear, project-specific auto-detect patterns need implementation judgement); MEDIUM for live UAT automation (gated-on-key pattern is standard, but Claude binary smoke specifics are novel); HIGH for README refresh (established structure patterns, project delta is well-known)

---

## Scope Note

All features below are ADDITIVE to what Conjure already ships. Existing commands
(`init`, `migrate`, `audit`, `update`, `check`, `resolve`, `adopt`, `publish`,
`publish-plugin`, `emit-policy`, `eval`, `workspace`) are NOT re-researched here.
Focus is exclusively on: `conjure doctor`, `conjure stats`, eval suite expansion,
init UX polish, live-system UAT, and README/docs refresh.

---

## Feature Area A: `conjure doctor` (Preflight Diagnostics)

### Prior Art Analysis

**npm doctor** checks: Node.js + git accessible, registry reachable, node_modules writable,
cache integrity, npm version current, permissions on global bin dirs. Emits a table with
pass/warn/fail per check. Exit 0 = all pass; exit 1 = anything failed. Notable flaw in
pre-v9 npm: exit 0 even on errors (since fixed). Machine-readable output not natively
supported; human table only.

**flutter doctor** checks: Flutter SDK, Dart SDK, Android toolchain, Xcode, IDE plugins,
connected devices. Uses `[✓]`, `[!]`, `[✗]` per category. Emits a summary line:
"Doctor found issues in N categories." `flutter doctor -v` adds verbose detail per check.
Exit 0 = all pass; exit 1 = any error. **Differentiator**: per-category grouping; fix
commands inline; `flutter doctor --android-licenses` runs the fix for one category.

**brew doctor** emits warnings for config drift (stale taps, mislinked kegs, unexpected
files). Does NOT group by category. Exit 0 = no issues; exit 1 = warnings present (this
caused community complaints — warnings that aren't actually errors still flip exit code).

**react-native doctor** goes further: "automatically fixes errors" for supported checks
(runs the fix and verifies). Groups by platform (Android, iOS, common). Each check shows
description + fix command or auto-fix option.

**Key lessons from prior art:**
1. Grouping by category (flutter model) is better than flat list (brew model) for
   large check sets
2. Per-check fix hints are table stakes — "what to run" on failure is mandatory
3. Exit codes must be clean: 0 = all required pass (optional warn OK), non-zero = blockers
4. `--verbose` / `-v` for extended detail on each check is expected
5. `--json` / `--porcelain` for machine-readable output is a differentiator (not all tools do it)
6. Auto-fix for some checks is a differentiator (react-native model) but requires TTY guard

**What Conjure already has:** `scripts/preflight.sh` — required/optional dep split,
OS-detected fix hints, exit 0/1. It checks: node, git (required); jq, rg, shellcheck,
graphify, ast-grep (optional). This is a foundation; `conjure doctor` needs to wrap and
extend it with harness-specific checks.

### Table Stakes

| Feature | Why Expected | Complexity | Dependencies |
|---------|--------------|------------|--------------|
| Binary presence table: claude, node, git, jq, shellcheck | Users expect a single command to show ALL environment gaps; preflight.sh already checks most but `claude` binary is new | LOW | `preflight.sh` (extend); `command -v` table |
| `.mjs` Node probe: `node -e "import('./templates/hooks-nodejs/session-start-context.mjs')"` dry run | Hooks fail silently if Node can't execute ES modules; a real probe catches version/ESM issues that `command -v node` misses | LOW | `scripts/preflight.sh` pattern; Node ESM support (v12+) |
| Per-check OS-detected install hint | User sees "brew install shellcheck" not "install shellcheck"; flutter/npm doctor both do this | LOW | `preflight.sh` `_fixup()` already exists; extend for claude binary |
| Harness structural checks: `.claude/`, `settings.json`, hooks present | `conjure doctor` is the first-run validator; user must know if the harness skeleton is incomplete | LOW | Parallel to `conjure audit` check list; simpler subset |
| `conjure doctor` as the recommended first-run command (docs + help text) | `brew doctor` became the standard "first thing to run" for Homebrew; Conjure needs the same mental model | LOW | CLI entrypoint + README |
| Exit 0 = all required pass (optional may warn), exit 2 = required missing | Consistent with Conjure convention (exit 2 for errors, never exit 1 from hooks) | LOW | Conjure exit convention (existing) |
| `--json` output for machine-readable result | CI pipelines that gate on doctor output need structured output; npm doctor gap (no JSON) is a known pain | LOW | Pattern from `conjure audit --json` (existing) |

### Differentiators

| Feature | Value Proposition | Complexity | Dependencies |
|---------|-------------------|------------|--------------|
| Claude Code version check: `claude --version` vs `.conjure-version` min requirement | Doctor detects "you have Claude Code v2.1.100 but this harness requires v2.1.117"; no prior tool does this for Claude Code harnesses | MEDIUM | `claude` soft dep; `.conjure-version` (existing); version comparison logic |
| Settings.json hook-event validation in doctor (subset of audit) | Doctor catches the most dangerous misconfiguration (hooks referencing nonexistent event names) without running a full audit | MEDIUM | Hook event name table from audit-setup.sh (existing v0.7.0) |
| `--fix` flag for auto-correctable issues: creates missing dirs, touches missing `.conjure-version` | React-native doctor auto-fix model; only for low-risk, reversible fixes; TTY-guarded | HIGH | TTY guard (existing pattern); `lib/mutate.sh`; backup-before-mutate |
| `conjure doctor --watch` re-runs checks on file change (development workflow) | Developers iterating on harness config want immediate feedback without re-running manually | HIGH | `fswatch` or polling loop; soft dep; probably P3 scope |

### Anti-Features

| Anti-Feature | Why Requested | Why Problematic | Alternative |
|--------------|---------------|-----------------|-------------|
| Merge `conjure doctor` into `conjure audit` | "One command" | `audit` is a deep harness health check (schema, caps, coverage); `doctor` is an environment preflight; conflating them confuses the mental model and increases audit runtime | Keep them separate; `doctor` runs in <1s (binary checks), `audit` runs in 2-5s (file inspection) |
| Auto-install missing binaries (run `brew install ...`) | "Zero friction" | Conjure must never run package manager commands without explicit user consent; brew/apt side effects are not reversible in a dry-run context | Print the command; never execute it |
| Network connectivity checks (ping registry.npmjs.com) | npm doctor does this | Adds network latency to a local tool; Conjure is a local harness kit, not a service-connected tool | Omit; document that eval requires network if ANTHROPIC_API_KEY is set |

---

## Feature Area B: `conjure stats` (Telemetry Insights)

### Prior Art Analysis

**Claude Code skill telemetry** is already documented in a GitHub issue
(#35319 — "Skill invocation tracking and usage analytics"): the community explicitly
requests `claude skills --stats` showing invocation counts per skill over the last 30 days.
Conjure already ships `skill-telemetry.mjs` (appends JSONL to `.claude/telemetry/skill-events.jsonl`)
and `conjure audit --retire-list` (cross-references installed skills vs telemetry counts, 30-day window).
`conjure stats` is the natural standalone surface for this data.

**Modern CLI analytics patterns** (Stripe CLI, Vercel CLI, Homebrew telemetry): local JSONL
append-only log; aggregate on read (never on write); human table + `--json`; no egress in
the stats command itself (log was captured locally by the hook).

**Key stats a team actually uses:**
- Fire counts per skill, per time window (7d, 30d, 90d, all)
- Dead skills (zero fires in window) — the retire candidate list
- Session counts (how many distinct sessions used any skill)
- Cost estimate (chars/4 × price table) for skills actually fired (not just loaded)
- Skill-typed vs skill-invoked split (was it invoked by Claude or typed by user?)

### Table Stakes

| Feature | Why Expected | Complexity | Dependencies |
|---------|--------------|------------|--------------|
| Fire count per skill (last 30d, configurable with `--window`) | The primary question: "which skills are actually being used?" `conjure audit --retire-list` already answers this but buries it in the audit output | LOW | `skill-events.jsonl` (existing); `jq` aggregation |
| Dead-skill detection: skills with zero fires in window | "What can I safely remove?" — retire candidates; `audit --retire-list` already does this; `stats` exposes it standalone | LOW | Audit retire-list logic (existing); cross-ref with installed skill dirs |
| Chars/4 cost estimate per skill based on actual fires | Cost visibility for skills actually used (not just loaded context); consistent with `audit --cost` but based on firing events not static file size | MEDIUM | Price table (existing in audit); chars-per-skill estimate from SKILL.md size; fire count from JSONL |
| `--json` output | Machine-readable for dashboards, CI reporting, org-wide aggregation | LOW | Pattern from `conjure audit --json` |
| `--window 7d|30d|90d|all` flag | Teams need different windows for weekly reviews vs quarterly planning | LOW | Date arithmetic (existing in audit retire-list logic) |
| Graceful no-telemetry message + enable instructions | If `CONJURE_TELEMETRY=1` was never set, stats must explain why there's no data and how to enable | LOW | Existing message in `audit --retire-list` |

### Differentiators

| Feature | Value Proposition | Complexity | Dependencies |
|---------|-------------------|------------|--------------|
| Skill-typed vs skill-invoked breakdown | Distinguishes user-initiated skill calls (typed `/skill-name`) from Claude-initiated invocations (Claude used `Skill` tool); different meaning for harness tuning | LOW | `event` field in JSONL (`skill_typed` vs `skill_invoke`); already captured by hook |
| Session-level summary: N distinct sessions, M days active | Shows whether the harness is used daily or episodically; context for interpreting fire counts | LOW | `session_id` field in JSONL (existing) |
| `conjure stats --top N` to show just the N most-fired skills | Quick scannable output for large harnesses (20+ skills) | LOW | Sort by count, head N |
| Trend: compare last-30d vs prior-30d, flag direction | "Is skill X usage growing or declining?" — useful for harness evolution decisions | MEDIUM | Two-window aggregation; delta calculation |
| `conjure stats export --csv` for spreadsheet analysis | Org-level reporting often lands in spreadsheets; `--json` gets you to CSV via jq but `--csv` is friendlier | LOW | `jq` formatting; simple text output |

### Anti-Features

| Anti-Feature | Why Requested | Why Problematic | Alternative |
|--------------|---------------|-----------------|-------------|
| Send stats to a central Conjure telemetry service | "Org dashboards" | Violates the local-only, no-egress contract; teams opted in to LOCAL telemetry only | Support `conjure stats export --json` for teams to pipe to their own dashboard |
| Real-time stats (tail -f style) | "Live view" | Adds complexity; skill fires are infrequent enough that a batch summary is more useful | `conjure stats` re-runs on demand; no persistent daemon needed |
| Correlate stats with actual task outcomes | "Was the skill helpful?" | Requires LLM evaluation of session outputs; out of scope for a local JSONL reader | Not in scope; this is an eval question, not a telemetry question |

---

## Feature Area C: Eval Suite Expansion

### Prior Art Analysis

**promptfoo baseline/regression pattern** (from official docs + community): the canonical
workflow is:
1. `npx promptfoo eval --output results-baseline.json` — capture pre-change baseline
2. Make prompt/skill changes
3. `npx promptfoo eval --output results-new.json`
4. `npx promptfoo eval --compare results-baseline.json` — shows regressions

Conjure's existing `conjure eval init|run` (v0.7.0) scaffolds a basic `promptfooconfig.yaml`
and runs it. The gap: (a) no per-profile suites (the same config tests all profiles), (b) no
stored baseline for regression comparison, (c) test cases only cover scaffold output, not
harness runtime behaviour.

**Per-profile eval pattern** (from promptfoo coding agent guide): use `vars:` in the
promptfooconfig with profile-specific test cases; or generate separate config files per
profile and run them with `--config`. The per-config approach is simpler for bash tooling.

**Live promptfoo run (gated on API key)**: standard CI pattern — check for `ANTHROPIC_API_KEY`
env var; if absent, skip with a clear message; never fail CI when key is not present.

### Table Stakes

| Feature | Why Expected | Complexity | Dependencies |
|---------|--------------|------------|--------------|
| Per-profile `promptfooconfig-<profile>.yaml` generation | Teams using specific profiles (ts-next, python-fastapi, etc.) need eval suites that test profile-specific skills and CLAUDE.md content, not just the generic harness | MEDIUM | `conjure eval init` (existing); profile dir reading (9 profiles); skill frontmatter parser (existing) |
| Regression baseline storage: `conjure eval snapshot` saves `baseline.json` | Before changing CLAUDE.md or skills, teams need a stored comparison point; this is the missing step before `conjure eval --compare` is useful | LOW | promptfoo `--output` flag (existing); `.conjure/eval/baselines/` dir; `mutate_write` |
| `conjure eval compare` wrapper: runs eval, compares to stored baseline, reports delta | Wraps `npx promptfoo eval --compare`; surfaces pass/fail regressions in human-readable form; exits non-zero if threshold breached | LOW | promptfoo compare command; stored baseline from snapshot |
| Live-run gate on `ANTHROPIC_API_KEY`: skip gracefully if absent | Standard CI pattern; never fail the job when no key is present; print skip message pointing to docs | LOW | Env var check; existing `conjure eval run` |
| Expand scaffold: test suite covers CLAUDE.md anti-patterns (exit 1 use, @import, size cap) | v0.7.0 eval tests are scaffold-only; the anti-pattern rules in CLAUDE.md are the most important things to eval | MEDIUM | `llm-rubric` assertions from audit knowledge; `conjure eval init` extension |

### Differentiators

| Feature | Value Proposition | Complexity | Dependencies |
|---------|-------------------|------------|--------------|
| `conjure eval coverage` report: which skills have no test case | Surfaces the eval coverage gap standalone; currently buried in `conjure audit`; teams should run this before baseline | LOW | Existing audit coverage logic; standalone subcommand |
| Trajectory assertions from skill `allowed-tools`: generate `javascript` stubs checking `metadata.toolCalls` | Skills that declare `allowed-tools: Read Bash` should have an eval asserting those tools fire in the right sequence | MEDIUM | Skill frontmatter parser (existing); promptfoo `toolCalls` metadata |
| Baseline per profile: `baselines/<profile>.json` + cross-profile regression summary | Profile-specific baselines let teams catch "python-fastapi profile broke" without re-running all profiles | MEDIUM | Per-profile eval files (from table stakes above); profile-keyed baseline storage |

### Anti-Features

| Anti-Feature | Why Requested | Why Problematic | Alternative |
|--------------|---------------|-----------------|-------------|
| Auto-run eval on every `conjure audit` | "Complete health check" | Eval makes real API calls; ~$0.50–5 per run; unexpected cost on routine audit breaks CI budgets | Keep eval as explicit subcommand; `audit --budget` covers static context linting |
| Bundling promptfoo as a Conjure dependency | "Zero setup" | Breaks `dependencies: {}` constraint; promptfoo is ~50MB npm package | `npx promptfoo` shell-out (downloads on first use); require Node (already a soft dep) |
| Write eval results into RESTRUCTURE-LOG.md | "Unified log" | Eval results are structured JSON; mixing into prose log loses structure | Write to `.conjure/eval/results/<timestamp>.json` |

---

## Feature Area D: Init UX Polish (Wizard + Profile Detection)

### Prior Art Analysis

**Interactive wizard patterns** (oclif + inquirer, algokit, pipecat CLI):
- Best wizards shift from template-selection to intent-selection: "What are you building?" → infer template, not "Pick template A, B, or C"
- AlgoKit v2 insight: "Streamlined, interactive process focused on user intent rather than specific technologies"
- Auto-detect from existing files (package.json → node profile; requirements.txt → python-fastapi; go.mod → go-gin; Cargo.toml → rust-axum; pom.xml → java-spring) is table stakes for init UX
- Non-interactive mode (`--yes` / `--no-input`) for CI automation
- Both interactive and non-interactive in same command, no separate codepath

**Current Conjure init UX gap**: `conjure init --profile=ts-next` requires the user to know profile names up front. There's no auto-detection and no interactive selection. A first-time user running `conjure init` with no flags gets no guidance on profile selection.

**Smarter defaults detection examples** (Claude token optimizer, react-native init):
- Scan for `package.json`, `go.mod`, `Cargo.toml`, `requirements.txt`, `pom.xml`, `build.gradle`, `*.sln`
- Detect monorepo markers (`nx.json`, `turbo.json`, `lerna.json`, `pnpm-workspace.yaml`)
- Suggest detected profile; let user override

### Table Stakes

| Feature | Why Expected | Complexity | Dependencies |
|---------|--------------|------------|--------------|
| Auto-detect profile from project files and suggest it | First-time users should not need to know that `--profile=python-fastapi` exists; the tool should say "I see requirements.txt — using python-fastapi profile, override? [y/N]" | MEDIUM | File probe: `package.json`, `go.mod`, `Cargo.toml`, `requirements.txt`, `pom.xml`; monorepo markers; profile name map |
| Interactive profile picker when auto-detect fails or is ambiguous | If detection fails, prompt with numbered list of profiles (not a raw flag); only when TTY present | MEDIUM | TTY detection (existing pattern in resolve.sh); `read` prompt loop; list profiles from `$CONJURE_HOME/profiles/` |
| `--yes` / `--no-input` flag: accept detected defaults without prompting (CI mode) | CI automation and scripted installs need non-interactive mode; `conjure init --yes` accepts auto-detected profile | LOW | Flag parsing; existing `DRY_RUN` pattern to model after |
| Print selected profile and why it was chosen | User should see "Using profile: python-fastapi (detected requirements.txt)" — no silent choices | LOW | Output line in init-project.sh before scaffold |
| Wizard asks about compliance overlay when no `--overlay` flag | Teams that need HIPAA/SOC2/GDPR/PCI overlays often forget to pass `--overlay`; a prompt "Apply a compliance overlay? [none/hipaa/soc2/gdpr/pci]" prevents missed setup | LOW | TTY check; `conjure emit-policy` integration; only prompt when TTY |

### Differentiators

| Feature | Value Proposition | Complexity | Dependencies |
|---------|-------------------|------------|--------------|
| Monorepo detection: suggest `monorepo` profile + explain what it adds | Monorepos are a common failure mode (wrong profile, missing workspace config); explicit detection and explanation reduces support burden | LOW | Monorepo marker detection (nx.json, turbo.json, pnpm-workspace.yaml, lerna.json) |
| Show diff of what will be created before writing (`--dry-run` + human-readable) | First-time users want to see what `conjure init` will do before it does it; `--dry-run` exists but output is technical | LOW | `DRY_RUN` path in `init-project.sh`; improved output formatting |
| `conjure init --interactive` explicit flag for always-prompting mode (even with auto-detect) | Power users want to review each choice even when detection is unambiguous | LOW | Alias for TTY-forced wizard mode |

### Anti-Features

| Anti-Feature | Why Requested | Why Problematic | Alternative |
|--------------|---------------|-----------------|-------------|
| Full TUI (ncurses) for profile selection | "Modern UX" | Added dependency, POSIX bash constraint, terminal compatibility issues; ncurses is explicitly out of scope per PROJECT.md | Simple numbered `read` prompt; works on all terminals |
| `conjure init` re-runs wizard on every invocation even if harness exists | "Always interactive" | Existing harnesses should use `conjure update` not re-init; re-running wizard risks overwriting user customisations | Guard: if `.claude/` already exists, default to `--mode=existing` and skip profile wizard |
| Remote profile fetching from a Conjure server | "Latest profiles always" | Adds network dep, egress, trust surface; `dependencies: {}` must stay empty | Ship profiles in the Conjure release; `conjure update` pulls new profile versions |

---

## Feature Area E: Live-System UAT Automation

### Prior Art Analysis

**Standard CI smoke test pattern**: check for secret env var; if absent, skip gracefully with message;
if present, run against live system; gate on exit code. GitHub Actions: `if: env.ANTHROPIC_API_KEY != ''`.

**Real `claude` binary smoke test**: the binary must be in PATH; `claude --version` is the cheapest
non-destructive probe; a minimal task (`claude -p "say hello"`) verifies the full stack without
creating harness artifacts.

**Deferred items from v0.7.0** (explicit in PROJECT.md STATE):
- `git -C "$VAR"` empty-var guard after mktemp failure (proven sandbox-escape vector)
- Kill-safe SCHM-STALE swap (atomic `jq > tmp + mv`)
- Real `claude` binary smoke test (gated on `CLAUDE_BIN_PATH` or PATH)
- Live promptfoo run (gated on `ANTHROPIC_API_KEY`)
- Manual MDM hardware UAT (cannot automate; macOS MDM requires physical device)

### Table Stakes

| Feature | Why Expected | Complexity | Dependencies |
|---------|--------------|------------|--------------|
| `git -C "$VAR"` empty-var guard in all test scaffolds | Documented sandbox-escape vector (tracked tech debt); proven to cause `git` to operate on the REAL repo when `$VAR` is empty after failed mktemp | LOW | `tests/run.sh`; hardening all `git -C "$TMPDIR"` callsites; guard: `[ -n "$TMPDIR" ] \|\| { echo "mktemp failed"; exit 2; }` |
| Kill-safe SCHM-STALE swap in audit-setup.sh | Atomic `jq > tmp + mv` prevents a partial write from leaving a corrupt temp schema file if audit is killed mid-run | LOW | `audit-setup.sh`; existing `jq … > tmp && mv tmp target` pattern from workspace saga |
| `claude` binary smoke test: `claude --version` in tests/run.sh, gated on `CLAUDE_BIN_PATH` env var | The harness must verify the binary it depends on actually works; gated so CI without the binary doesn't fail | LOW | `tests/run.sh` new test block; `command -v claude \|\| skip` guard |
| Live `conjure eval run` smoke in CI: gated on `ANTHROPIC_API_KEY` | Verify end-to-end eval pipeline works; skip gracefully when key absent | LOW | Existing `conjure eval run`; CI secret check |
| Document manual MDM steps (cannot automate): macOS managed-settings deploy, MDM hardware | Teams need explicit instructions for the steps that require a physical device or org MDM enrollment | LOW | FAILURE-MODES.md + HUMAN-UAT section; no code required |

### Differentiators

| Feature | Value Proposition | Complexity | Dependencies |
|---------|-------------------|------------|--------------|
| `CLAUDE_BIN_PATH` env var support in doctor + tests | Teams with non-standard Claude Code install paths (enterprise, custom homebrew prefix) need PATH override; standard pattern from other SDK tools | LOW | Doctor binary probe; test scaffold |
| `conjure doctor --live` mode: runs live probes (claude --version + promptfoo dry-run) in addition to static checks | Separates fast static checks from slow live probes; opt-in for environments where the binary is available | MEDIUM | Extend doctor with `--live` flag; call `claude --version`; run promptfoo with `--dry-run` if Node present |

### Anti-Features

| Anti-Feature | Why Requested | Why Problematic | Alternative |
|--------------|---------------|-----------------|-------------|
| Auto-deploy MDM artifacts to Jamf/Intune from CI | "Zero-friction MDM" | Requires MDM credentials; Conjure must never handle org credentials; deployment is IT ops | Generate artifacts; document deploy procedure; this is permanent out-of-scope |
| Run live eval tests on every PR without key guard | "Full coverage always" | API calls cost money; unguarded live tests break forks and public PRs that don't have the secret | Always gate on key presence; use `if: env.ANTHROPIC_API_KEY != ''` in workflow |

---

## Feature Area F: README + Docs Refresh

### Prior Art Analysis

**Best-in-class CLI tool READMEs** (gh CLI, cargo, npm CLI, Homebrew):
1. **One-sentence description** at the top — what it does, not what it is
2. **Badges** — CI status, version, license (signals maintenance status)
3. **Quick start** — 2-3 commands to get from zero to working; the moment of delight
4. **Short feature tour** — 3-5 bullets with concrete outcomes, not abstract capabilities
5. **Command reference** — table or sections per subcommand; inputs, outputs, flags
6. **Installation section** — every supported method (brew, docker, curl, git clone) with copy-paste commands
7. **Migration guide link** — for existing users upgrading; separate file, linked prominently
8. **Contributing / development** — for contributors
9. **License**

**What gh CLI README does well**: keeps the README short and links to `gh.io/manual` for deep reference. The README is discovery; the manual is reference.

**Current Conjure gap**: the README was written for v0.3-era feature set; commands like `conjure adopt`, `conjure emit-policy`, `conjure workspace`, `conjure eval` are either missing or have stale descriptions. The quick start sends users to a `PROMPT.md` that no longer reflects the primary workflow.

**MIGRATION-GUIDE.md + FAILURE-MODES.md sync**: these files were last updated at v0.4 era; they reference pre-`adopt` migration paths and pre-`emit-policy` compliance workflows.

### Table Stakes

| Feature | Why Expected | Complexity | Dependencies |
|---------|--------------|------------|--------------|
| README quick start reflects current workflow: `conjure doctor` → `conjure init` → `conjure audit` | The "happy path" must be the first thing a reader sees; current README doesn't mention doctor, adopt, or eval | LOW | Write; no code |
| Command reference table covering all v0.3–v0.7 commands | `conjure adopt`, `conjure emit-policy`, `conjure eval`, `conjure workspace`, `conjure publish-plugin` must all appear with their key flags | LOW | Write; no code |
| Installation section: Homebrew + Docker + git clone | Three install paths are shipped; README must show all three with copy-paste commands | LOW | Write; extract from existing INSTALL.md if it exists |
| MIGRATION-GUIDE.md sync: add v0.6.0 adopt path, v0.7.0 emit-policy, v0.8.0 doctor/stats | Users on v0.3–v0.7 upgrading need to know what's new and what changed; current guide stops at v0.5 | LOW | Write; append migration notes per version |
| FAILURE-MODES.md sync: add adopt failure modes, workspace saga failures, MDM manual steps | v0.6.0 adopt + v0.7.0 workspace introduced new failure modes not documented | LOW | Write; pull from v0.6/v0.7 milestone notes |
| "Feature tour" section: 5 concrete outcomes with one-liners | Readers need to understand what Conjure does in 60 seconds; current README buries capabilities in prose | LOW | Write; no code |

### Differentiators

| Feature | Value Proposition | Complexity | Dependencies |
|---------|-------------------|------------|--------------|
| Animated GIF or asciicast of `conjure init` → `conjure doctor` → `conjure audit` | Visual demo in README dramatically reduces "how does this actually work?" friction; prior art: asciinema, terminalizer | MEDIUM | `record-demo.sh` already exists in scripts/; extend for v0.8 command sequence |
| `conjure help <subcommand>` inline examples in each help block | `gh pr create --help` includes examples; Conjure's `--help` currently shows flags but no examples | LOW | Extend `usage()` blocks in `cli/conjure` per subcommand |
| Searchable online docs (GitHub Pages or docs site) | For a tool this complex (20+ subcommands), online searchable docs reduce support burden | HIGH | GitHub Pages + mkdocs/docusaurus; probably P3 scope for v0.8 |

### Anti-Features

| Anti-Feature | Why Requested | Why Problematic | Alternative |
|--------------|---------------|-----------------|-------------|
| Rewrite all docs in a documentation framework (Docusaurus, MkDocs) | "Professional docs" | High maintenance overhead; README-first approach is appropriate for current project size | Markdown files linked from README; GitHub renders them well; Docusaurus is a v1.0+ consideration |
| Auto-generate command reference from `--help` output | "Always in sync" | Conjure's `--help` output is not structured enough for auto-generation without significant refactoring | Hand-curate the command reference table; it's one section in README, manageable manually |
| Separate website for docs | "Discoverability" | Adds maintenance surface; GitHub README + linked Markdown files cover the use cases at current scale | Link to specific files (FAILURE-MODES.md, MIGRATION-GUIDE.md) from README; no website needed in v0.8 |

---

## Feature Dependencies

```
[A: conjure doctor]
    └──extends──>    preflight.sh (existing)
    └──requires──>   hook event name table (audit-setup.sh v0.7.0 existing)
    └──enhances──>   [D: init wizard] (doctor is recommended first-run step)
    └──requires──>   [F: README] surfaces doctor as entry point

[B: conjure stats]
    └──requires──>   skill-telemetry.mjs + skill-events.jsonl (existing)
    └──extends──>    conjure audit --retire-list logic (existing)
    └──standalone──> no hard deps on other v0.8 features

[C: eval suite expansion]
    └──extends──>    conjure eval init|run (v0.7.0 existing)
    └──requires──>   per-profile dirs (9 profiles, existing)
    └──enhances──>   [E: live UAT] (live eval smoke uses expanded suite)
    └──requires──>   node + promptfoo npx (existing soft deps)

[D: init wizard polish]
    └──extends──>    init-project.sh + cli/conjure cmd_init (existing)
    └──requires──>   TTY detection pattern (existing in resolve.sh)
    └──enhances──>   [A: doctor] (wizard can suggest running doctor first)
    └──standalone──> no hard deps on B, C, E

[E: live UAT automation]
    └──requires──>   git -C guard (test-harness hardening — tech debt fix)
    └──requires──>   conjure eval run (v0.7.0 existing)
    └──requires──>   audit-setup.sh SCHM-STALE fix (tech debt)
    └──standalone──> no hard deps on A, B, C, D for core fixes

[F: README + docs refresh]
    └──documents──>  A, B, C, D, E outputs
    └──standalone──> pure documentation, no code deps
    └──should ship last to capture v0.8 command additions
```

### Dependency Notes

- **A (doctor) extends preflight.sh** — the existing `scripts/preflight.sh` is the binary-check foundation; `conjure doctor` wraps it and adds harness-structural and Claude Code version checks.
- **E (live UAT) is partially tech-debt paydown** — the `git -C "$VAR"` guard and SCHM-STALE fix are hardening changes that must land early (they are sandbox-safety fixes, not new features).
- **B (stats) is nearly complete in audit** — `conjure audit --retire-list` already does the core of stats; `conjure stats` is a refactor/promotion of that logic into a standalone command with richer output.
- **F (README) depends on final shape of A and B** — write the README after doctor and stats commands are stabilised so the quick start is accurate.
- **C and D are independent** — eval suite expansion and init wizard can be built in parallel.

---

## MVP Definition for v0.8.0

### Ship First (safety + foundational — unblocks rest)

- [ ] **E: test-harness hardening** — `git -C "$VAR"` empty-var guard + SCHM-STALE atomic swap — safety fixes from v0.7.0 deferred debt; LOW complexity, HIGH priority
- [ ] **A: `conjure doctor` core** — binary table + .mjs probe + harness structural checks + OS fix hints + `--json` — LOW–MEDIUM complexity; extends existing preflight.sh

### Ship Second (new standalone value)

- [ ] **B: `conjure stats`** — fire/never-fire report + dead-skill detection + cost estimate + `--json` + `--window` — LOW–MEDIUM complexity; extends existing audit --retire-list
- [ ] **D: init wizard polish** — auto-detect profile + interactive picker + `--yes` flag + compliance overlay prompt — MEDIUM complexity; extends init-project.sh

### Ship Third (eval depth + live validation)

- [ ] **C: eval suite expansion** — per-profile configs + `conjure eval snapshot` + baseline comparison + live-run key guard — MEDIUM complexity; extends conjure eval
- [ ] **E: live UAT** — `claude` binary smoke (gated) + live eval run (gated on key) + MDM manual docs — LOW complexity for gated tests; document-only for MDM

### Ship Last (captures all above)

- [ ] **F: README + docs refresh** — quick start with doctor→init→audit flow; command reference covering v0.3–v0.7; MIGRATION-GUIDE + FAILURE-MODES sync — LOW complexity; HIGH user-facing value

---

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| E: git -C guard + SCHM-STALE fix | HIGH (safety) | LOW | P1 |
| A: doctor — binary + harness checks + fix hints | HIGH | LOW | P1 |
| A: doctor — `--json` output | HIGH | LOW | P1 |
| B: stats — fire count + dead-skill detection | HIGH | LOW | P1 |
| B: stats — cost estimate + `--json` + `--window` | MEDIUM | LOW | P1 |
| D: init — auto-detect profile | HIGH | MEDIUM | P1 |
| D: init — interactive picker (TTY) + `--yes` | HIGH | MEDIUM | P1 |
| C: eval — per-profile configs | HIGH | MEDIUM | P1 |
| C: eval — `conjure eval snapshot` baseline | HIGH | LOW | P1 |
| E: claude binary smoke (gated) | MEDIUM | LOW | P1 |
| E: live eval run (gated on key) | MEDIUM | LOW | P1 |
| F: README quick start + command reference | HIGH | LOW | P1 |
| F: MIGRATION-GUIDE + FAILURE-MODES sync | HIGH | LOW | P1 |
| A: doctor — Claude Code version check | MEDIUM | MEDIUM | P2 |
| A: doctor — settings hook-event validation | MEDIUM | MEDIUM | P2 |
| B: stats — skill-typed vs invoke breakdown | MEDIUM | LOW | P2 |
| B: stats — session summary | LOW | LOW | P2 |
| C: eval — trajectory assertions from allowed-tools | MEDIUM | MEDIUM | P2 |
| D: init — monorepo detection | MEDIUM | LOW | P2 |
| D: init — overlay wizard prompt | MEDIUM | LOW | P2 |
| F: `conjure help` examples per subcommand | MEDIUM | LOW | P2 |
| A: doctor — `--fix` auto-correct | LOW | HIGH | P3 |
| A: doctor — `--watch` mode | LOW | HIGH | P3 |
| B: stats — trend (last-30d vs prior-30d) | LOW | MEDIUM | P3 |
| F: animated GIF / asciicast demo | LOW | MEDIUM | P3 |
| F: searchable online docs site | LOW | HIGH | P3 |

**Priority key:** P1 = ship in v0.8.0; P2 = target v0.8.0, defer to v0.8.x if time-constrained; P3 = v0.9+ or backlog

---

## Competitor / Prior Art Reference

| Feature | brew doctor | flutter doctor | npm doctor | react-native doctor | conjure doctor (v0.8 target) |
|---------|-------------|----------------|------------|---------------------|------------------------------|
| Binary presence check | ✓ | ✓ | ✓ | ✓ | ✓ |
| OS-specific fix hints | Partial | ✓ | ✗ | ✓ | ✓ (extends preflight.sh) |
| Per-category grouping | ✗ | ✓ | ✗ | ✓ | ✓ (required/optional/harness) |
| Auto-fix for some checks | ✗ | ✗ | ✗ | ✓ | P3 only |
| `--json` machine output | ✗ | ✗ | ✗ | ✗ | ✓ (differentiator) |
| Version compatibility check | ✗ | Partial | ✓ (npm ver) | ✗ | ✓ (claude binary vs .conjure-version) |
| Clean exit codes (0=pass, non-zero=fail) | ✗ (warns flip exit 1) | ✓ | ✗ (bug: exit 0 on errors pre-v9) | ✓ | ✓ (follows Conjure exit 2 convention) |

---

## Sources

- npm doctor official docs: [npm-doctor | npm Docs](https://docs.npmjs.com/cli/v11/commands/npm-doctor/) — HIGH confidence
- npm doctor exit code bug: [npm doctor exit code 0 on ERR · Issue #1226 · npm/cli](https://github.com/npm/cli/issues/1226) — HIGH confidence
- flutter doctor overview: [Flutter Doctor: Diagnosing Setup Problems](https://mailharshkhatri.medium.com/flutter-doctor-diagnosing-setup-problems-768bcf783ae4) — MEDIUM confidence (community article, patterns confirmed via official Flutter docs)
- react-native doctor: [Meet Doctor, a new React Native command](https://reactnative.dev/blog/2019/11/18/react-native-doctor) — HIGH confidence (official blog)
- CLI best practices (output, exit codes, hints): [Command Line Interface Guidelines](https://clig.dev/) — HIGH confidence
- Skill invocation tracking community request: [Feature request: Skill invocation tracking · Issue #35319 · anthropics/claude-code](https://github.com/anthropics/claude-code/issues/35319) — HIGH confidence (GitHub issue)
- promptfoo baseline/regression workflow: [Prompt Regression Testing: A Practical 2026 Guide](https://futureagi.com/blog/prompt-regression-testing-2026/) — MEDIUM confidence (community article, patterns match official promptfoo docs)
- promptfoo evaluate coding agents: [Evaluate Coding Agents | Promptfoo](https://www.promptfoo.dev/docs/guides/evaluate-coding-agents/) — HIGH confidence (official docs)
- Auto-detect profile prior art (Claude token optimizer): [claude-token-optimizer](https://github.com/nadimtuhin/claude-token-optimizer) — MEDIUM confidence (community tool, pattern is well-established)
- AlgoKit init wizard v2 intent-first design: [2024-01-23 init wizard v2 architecture decision](https://developer.algorand.org/docs/get-details/algokit/architecture-decisions/2024-01-23_init-wizard-v2/) — MEDIUM confidence (single source, but design pattern is sound)
- README structure best practices: [How to Structure Your README File | freeCodeCamp](https://www.freecodecamp.org/news/how-to-structure-your-readme-file/) — MEDIUM confidence
- Awesome README examples: [matiassingers/awesome-readme](https://github.com/matiassingers/awesome-readme) — MEDIUM confidence (curated list, consensus patterns are reliable)
- Existing Conjure telemetry hook: `templates/hooks-nodejs/skill-telemetry.mjs` (codebase) — HIGH confidence (authoritative)
- Existing preflight: `scripts/preflight.sh` (codebase) — HIGH confidence (authoritative)
- v0.7.0 audit retire-list logic: `scripts/audit-setup.sh` lines 632–676 (codebase) — HIGH confidence (authoritative)

---

*Feature research for: Conjure v0.8.0 Operability + DX*
*Researched: 2026-06-04*
