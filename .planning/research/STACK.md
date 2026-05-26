# Stack Research

**Domain:** v0.3.0 "Testing + telemetry" tooling for the Conjure Claude Code harness kit (POSIX bash CLI + Node.js `.mjs` hooks)
**Researched:** 2026-05-24
**Confidence:** HIGH (hooks API, pricing, tokenizer status verified against official sources; shell-framework tradeoff is well-established)

## TL;DR Picks (one line each)

| Decision | Pick | Confidence |
|----------|------|------------|
| (a) Fixture regression testing | **Extend hand-rolled `tests/run.sh`**, optionally **vendor `bats-core` v1.13.0 as a git submodule** for new unit-level specs. Do NOT add shellspec or npm test deps. | HIGH |
| (b) Skill-firing telemetry | **Append-only JSONL log written by a `PreToolUse` (tool_name=`Skill`) hook**, also capture `InstructionsLoaded`. Pure bash + `.mjs`, no external service. | HIGH |
| (c) Cost estimator | **chars/4 heuristic** over harness file bytes × a small per-model price table baked into `conjure`. Do NOT bundle a tokenizer or call the API by default. | HIGH |
| (d) Cross-platform preflight | **`command -v` table in bash + a mirrored `.mjs` probe**, OS-detected install hints (brew/apt/winget/npm). Already partially exists in `cmd_preflight`. | HIGH |

---

## Recommended Stack

### Core Technologies

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| **Hand-rolled `tests/run.sh`** | (current, extend) | Fixture-driven regression suite, audit assertions per profile | Already ships, 112 tests green, zero install. The fixture suite is fundamentally "run `audit-setup.sh` against `tests/fixtures/<profile>/` and assert exit code + grep output" — this is a loop, not a framework need. Keeps the kit dependency-free, which is a core constraint. |
| **bats-core** | **v1.13.0** (2025-11-07) | OPTIONAL: structured unit-level specs for individual CLI functions / dry-run assertions | TAP-compliant, pure bash, runs on bash 3.2+, installable as a **git submodule with zero runtime deps**. Only adopt if hand-rolled assertions get unwieldy; introduce alongside, not as a replacement. |
| **bats-support + bats-assert** | **v2.2.4** | OPTIONAL: `assert_output`, `assert_success`, `assert_equal` helpers for bats | The ergonomic layer that makes bats worth it. Not on npm — must be submodules. Only pull in if bats is adopted. |
| **shellcheck** | **v0.11.0** (2025-08) | Lint all `.sh` (already in CI) | Keep pinned. v0.11 adds SC2327–2335; relevant to the new fixture/telemetry scripts. CI already runs it (relaxed to error-only per recent commit). |
| **Node.js (built-in only)** | **>=18 LTS** | `.mjs` hooks for Windows + cost-estimator math + dry-run helpers | Already a declared platform. Use `node:fs`, `node:process`, `node:os`, `node:child_process` from stdlib only. No npm `dependencies` block. |
| **jq** | system (preflight-checked) | JSONL telemetry parsing in `conjure audit`, fixture JSON validation | Already a preflight dependency and used in `tests/run.sh`. Reuse for reading the telemetry log; don't add a JSON lib. |

### Supporting Libraries

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| **`@anthropic-ai/sdk`** | latest (~0.6x line) | `client.messages.countTokens()` for an *opt-in* `--cost --exact` mode only | ONLY behind an explicit flag, lazy `npx`-invoked, never a hard dep. Free API, rate-limited. Default path must stay offline. Most users won't have credentials configured; design must degrade to the heuristic silently. |
| **(none for tokenizing)** | — | — | Deliberately empty. See "What NOT to Use." The chars/4 heuristic needs no library. |

### Development Tools

| Tool | Purpose | Notes |
|------|---------|-------|
| `git submodule` | Vendor bats-core if adopted | `git submodule add https://github.com/bats-core/bats-core tests/bats`. Pin to v1.13.0 tag. CI must `git submodule update --init`. |
| GitHub Actions (existing `ci.yml`) | Run fixture suite on push | Add a matrix entry per OS (`ubuntu-latest`, `macos-latest`, and `windows-latest` for the `.mjs` hook path) to actually exercise cross-platform claims. |
| `tput`/ANSI (existing pattern) | Test output formatting | Already used in `run.sh`; keep. |

## Installation

```bash
# Nothing new required for the DEFAULT path — bash + node + jq + shellcheck already assumed.

# OPTIONAL, only if adopting bats for unit-level specs:
git submodule add https://github.com/bats-core/bats-core.git tests/bats
git submodule add https://github.com/bats-core/bats-support.git tests/test_helper/bats-support
git submodule add https://github.com/bats-core/bats-assert.git tests/test_helper/bats-assert
git -C tests/bats checkout v1.13.0

# OPTIONAL, only for `conjure audit --cost --exact` (never bundled):
#   invoked at runtime, never installed into the kit:
npx --yes @anthropic-ai/sdk  # (illustrative; real call is a tiny .mjs using the SDK)
```

The kit's own `package.json` (if any) MUST keep `dependencies: {}` empty. Anything heavier is a `devDependency` at most, or an `npx` runtime call.

## Detailed Findings by Question

### (a) Fixture-based regression testing of POSIX shell CLIs

**Pick: extend the hand-rolled harness; vendor bats-core only if specs get complex.**

The v0.3.0 fixture work is mostly: for each of the 9 profiles, scaffold an example project under `tests/fixtures/<profile>/`, run `conjure audit`, and assert it exits clean with expected files. That is a `for` loop calling the existing `audit-setup.sh` — the current `pass`/`fail`/`t` helpers in `run.sh` already model this perfectly. Adding a framework here buys little and costs a dependency.

When a framework *does* earn its place: testing individual CLI functions in isolation (e.g., "`cmd_init --dry-run` writes zero files", arg-parsing edge cases, telemetry-log format). For those, **bats-core v1.13.0** is the standard:
- Pure bash, runs on bash 3.2+ (matches the POSIX/cross-platform constraint).
- TAP output (CI-friendly, plays with the existing GitHub Actions).
- Installs cleanly as **git submodules** with no npm/runtime footprint.
- `bats-assert`/`bats-support` (v2.2.4) give readable assertions.

**Why bats over shellspec:** shellspec's last release is **0.28.1 from January 2021** — effectively unmaintained for 5 years. bats-core shipped v1.13.0 in **November 2025** with an active org and three maintained helper libs. For a "trust-first" kit, picking the actively-maintained tool matters. shellspec's BDD DSL and broader-shell support are nice but irrelevant here: the kit is bash-targeted, and the maintenance gap is disqualifying.

**Dry-run enforcement as a test target:** the cleanest assertion is *filesystem-snapshot-based* — record `find <target> -type f | sort` before and after `conjure init --dry-run`, assert identical. This is a hand-rolled assertion regardless of framework. The CLI already threads `dryrun` through `cmd_init`/`cmd_migrate`; the gap is that `init-project.sh` and `profiles/*/apply.sh` must honor it. Tests should assert the *snapshot invariant*, not internal flags.

### (b) Lightweight local telemetry from Claude Code hooks (no external service)

**Pick: append-only JSONL written by hooks, parsed by `jq` in `conjure audit`.**

Critical 2026 finding — the Claude Code hooks API now exposes exactly what's needed, so telemetry needs no transcript scraping or external service:

- **`PreToolUse` / `PostToolUse` with `tool_name: "Skill"`** — when Claude invokes a skill (even autonomously, not just via `/slash`), the hook receives `tool_input.skill_name`. This is the primary skill-firing signal.
- **`InstructionsLoaded`** — fires when CLAUDE.md/skills/rules load, with `file_path`, `memory_type`, and `load_reason`. Captures eager-load events for the retire-list signal.
- **`SessionStart`** (`source`, `model`) and **`SessionEnd`/`Stop`** — bracket sessions for per-session aggregation. Common fields `session_id` + `cwd` are on every event.

Implementation: a small hook (bash + mirrored `.mjs`) reads the JSON on stdin, extracts `session_id` + `skill_name` + timestamp, and appends one line to `.claude/telemetry/skills.jsonl`. JSONL is the right format — append-only, crash-safe, `jq`-readable, no DB. `conjure audit --skills` (or a quarterly script) tallies `skill_name` frequency to produce the retire-list ("skills that never fired in N sessions").

Hard rules for the hook (from the existing kit constraints + hooks contract):
- Telemetry hooks MUST `exit 0` and emit nothing on stdout that isn't intended JSON (stdout at exit 0 is parsed by Claude Code). Safest: write the file, then `exit 0` with empty stdout, or set `"suppressOutput": true`.
- MUST be non-blocking and fast (<100ms); never `exit 2` (that blocks the tool — telemetry must never block).
- MUST be append-only and tolerate a missing/locked file (concurrent sessions). Use `>>` with `mkdir -p`.
- Log path under the project's `.claude/` (gitignore it via the existing `.gitignore.tmpl`), never a global or network location. Local-only is a privacy + trust requirement for an OSS kit.

Do NOT: ship an analytics SDK, phone home, use a sqlite dep, or parse the `transcript_path` JSONL (fragile, large, and unnecessary now that `Skill` tool events exist).

### (c) Estimating Claude session token cost from static file sizes

**Pick: chars/4 heuristic × baked-in per-model price table. No tokenizer dependency.**

Verified blocker against bundling a tokenizer: the official **`@anthropic-ai/tokenizer`** npm package is **explicitly inaccurate for Claude 3 and later models** (per Anthropic's own README/npm page) — and the kit targets Claude Code >=2.1.117 running Claude 4.x. There is **no accurate offline Claude 4 tokenizer** published; the only billing-grade source is the online `messages.countTokens()` API. tiktoken/`gpt-tokenizer` are OpenAI encodings and only approximate Claude.

Given the kit's zero-heavy-dep + offline + cross-platform constraints, the right call is the same heuristic the kit *already documents* in `reference/SIZING.md`: **~4 chars/token**. The cost estimator's job is a *budget warning*, not an invoice — heuristic precision (±10–15%) is more than enough to flag "your harness eagerly loads 30k tokens every session."

Design for `conjure audit --cost`:
1. Sum bytes of eager-loaded harness surface: root `CLAUDE.md` + every skill's `name:`+`description:` frontmatter (only the body loads on match, so count bodies separately as "potential") + agent definitions + `.claude/settings.json` + MCP tool-metadata estimate.
2. `tokens ≈ chars / 4`. Add the documented session baseline (~20k) and MCP metadata (~500–3000/server) from SIZING.md.
3. Multiply by a small price table baked into `conjure` (current rates, May 2026, per 1M tokens):

   | Model | Input | Output |
   |-------|-------|--------|
   | Haiku 4.5 | $1.00 | $5.00 |
   | Sonnet 4.6 | $3.00 | $15.00 |
   | Opus 4.7 | $5.00 | $25.00 |

   Cost is dominated by *input* (the harness is input context), so report input-cost-per-session prominently. Note the 90% prompt-cache discount and 50% batch discount as caveats, not defaults.
4. Offer `--cost --exact` as an opt-in escape hatch that lazily calls `countTokens()` via the SDK *if* credentials exist, else silently falls back to the heuristic with a one-line note.

Keep the price table in one obvious constant block with a "rates as of 2026-05; verify at platform.claude.com/docs/about-claude/pricing" comment, so it's a trivial one-line update — pricing drifts and must not require a code rewrite.

### (d) Cross-platform dependency pre-flight (bash + Windows `.mjs`)

**Pick: `command -v` probe table in bash, mirrored `.mjs` probe, OS-detected install hints.**

The pattern is already half-built in `cli/conjure` `cmd_preflight()` (checks git/jq/rg, suggests `brew install`). v0.3.0 hardens it:

- **Detection:** `command -v <tool>` is the portable POSIX primitive (works in bash, dash, git-bash). In `.mjs`, mirror with `child_process` running `command -v` on POSIX and `where` on Windows, or check `process.platform`. Avoid `which` (not always present; non-POSIX exit semantics).
- **OS-aware install hints:** the current code hardcodes `brew install`. Make it OS-detected: `brew` (macOS), `apt`/`dnf` (Linux), `winget`/`scoop`/`choco` (Windows), `npm i -g` for node tools. Detect via `uname -s` (bash) / `process.platform` (node).
- **One-command fix-it:** print a single copy-pasteable line per platform, e.g. `brew install jq ripgrep` — never auto-run installs (the kit forbids `curl|sh` foot-guns; same principle applies to silent package installs). Print, let the human run it.
- **Required vs optional tiers** (already modeled): hard-require `git`, `jq`; recommend `rg`; optional power tools (`graphify`, `ast-grep`, `gitleaks`, `repomix`) stay advisory and never block.
- **Windows reality:** the `.mjs` hooks are the Windows story. Document that the bash CLI itself expects git-bash/WSL on Windows; the `.mjs` hooks are what run under native PowerShell/cmd. Preflight should detect the bash-vs-native context and point Windows users at the `.mjs` hook variants.

---

## Stack Additions for v0.4.0: Distribution + Ecosystem

**Domain:** v0.4.0 "Distribution + Ecosystem" additions on top of the validated v0.3.0 stack.
**Researched:** 2026-05-25
**Confidence:** HIGH for Marketplace schema (official docs verified) and git-merge-file (git builtins). MEDIUM for Docker (multi-stage pattern is standard; base image pinning is implementation detail). MEDIUM for Homebrew tap (well-documented but SHA256 automation is ecosystem tooling).

### Stack Additions (new capabilities only — base stack unchanged)

| Tool / Format | Version / Source | Purpose | Why |
|---------------|-----------------|---------|-----|
| **`.claude-plugin/marketplace.json`** | Claude Code Marketplace schema (schemastore.org/claude-code-marketplace.json) | DIST-01: Publish Conjure to Claude Code Marketplace | Already partially authored (`.claude-plugin/marketplace.json` exists at v0.2.0). Needs version bump to 0.4.0, `plugins[]` array listing Conjure as a plugin with `source: {source:"github", repo:"mohandoz/conjure"}`, and compliance with reserved-names list. No new runtime dep — pure JSON. |
| **Homebrew tap repo** (`homebrew-conjure`) | Homebrew tap conventions | DIST-02: `brew install mohandoz/conjure/conjure` | A separate GitHub repo named `homebrew-conjure` with a Ruby formula `conjure.rb`. Formula uses `bin.install "cli/conjure" => "conjure"` and declares `depends_on "jq"`. No new code in the main repo beyond a CI step that calls `mislav/bump-homebrew-formula-action@v3` to auto-update SHA256 on GitHub Release. |
| **`mislav/bump-homebrew-formula-action`** | v3 (current) | Automate formula SHA256 + URL on release | GitHub Action: triggers on release publish, computes SHA256 of the tarball, commits to `homebrew-conjure`. Needs a `HOMEBREW_TAP_TOKEN` secret with `repo` + `workflow` scopes for the tap repo. Zero runtime dep on main repo. |
| **Docker base: `node:20-alpine`** | `node:20-alpine` (Node 20 LTS, Alpine 3.x) | DIST-03: Runtime base — node + npm available, minimal size | Alpine gives ~25% smaller image than Debian slim. Node 20 LTS is supported through 2026-04-30 (Node 22 LTS is the longer option — see below). bash is NOT in node:alpine by default; must `apk add bash`. |
| **Docker ADD: `koalaman/shellcheck:stable`** | `stable` tag (currently v0.10.x / v0.11.x) | DIST-03: Copy statically-linked shellcheck binary via multi-stage | Official approach: `COPY --from=koalaman/shellcheck:stable /bin/shellcheck /bin/shellcheck`. Statically linked — no musl/glibc conflict on Alpine. No separate package install needed. |
| **Docker ADD: `jq` (Alpine package)** | `jq` from Alpine apk | DIST-03: JSON processing in container | `apk add --no-cache jq` — jq is in Alpine's main repository, no extra repos needed. Alpine's jq is statically linked. |
| **`git merge-file` (git builtin)** | git >=2.x (already a preflight dep) | TECH-01: `cmd_update --apply` 3-way merge | git is already a hard dependency. `git merge-file --diff3 <current> <base> <other>` performs a 3-way merge in-place on `<current>`. Exit code 0 = clean, 1–127 = N conflicts, negative = error. `-p` / `--stdout` for preview-only. The `--diff3` flag adds a third "base" section in conflict markers for easier manual resolution. No new dep — it's a git subcommand, not a separate binary. |
| **`conjure-skills` public repo** | GitHub repo (new, `mohandoz/conjure-skills`) | DIST-04: `conjure publish-skill` destination | Git-based skill registry pattern: a public GitHub repo with `skills/<name>/SKILL.md` layout, a `registry.json` index, and PR-based contribution. `conjure publish-skill <name>` validates frontmatter locally then opens a GitHub PR via `gh pr create`. Requires `gh` (GitHub CLI) as a soft dep (advisory, not blocking). |
| **`gh` (GitHub CLI)** | system (advisory dep, not blocking) | DIST-04: `conjure publish-skill` opens PR to skill registry | Already used in contributor workflow. `conjure publish-skill` shells out to `gh pr create` after local validation. If `gh` is absent, print instructions instead (same "print, don't auto-run" principle). No new install in the kit. |

### Overlay System (DIST-05) — No New Stack Deps

The org overlay system (base kit + private overlay repo per org) requires no new stack additions:

- **Mechanism:** `conjure init --overlay <git-url>` clones the overlay repo to a temp dir, applies it on top of the base scaffold. Uses existing `lib/mutate.sh` chokepoint for safety.
- **Overlay repo format:** a convention-based git repo with `skills/`, `profiles/`, `compliance/` overrides. A `conjure-overlay.json` manifest declares which layers to merge.
- **Merge strategy:** file-wins — overlay files replace base files by path. No runtime dep beyond `git clone`. Private repos use existing git credential helpers (same pattern as the Marketplace private-repo support).
- **No new stack:** git clone + existing mutate.sh + jq for manifest parsing. All already in the preflight stack.

### Integration Points

| New Capability | Integrates With | Integration Approach |
|----------------|----------------|---------------------|
| DIST-01 Marketplace | `.claude-plugin/marketplace.json` (already exists) | Update version to 0.4.0, add `plugins[]` array, validate with `claude plugin validate .` in CI |
| DIST-02 Homebrew tap | GitHub Releases (existing release workflow) | Add `bump-homebrew-formula-action` step to release CI; no code change in main repo |
| DIST-03 Docker | `cli/conjure` + `scripts/` + `lib/` (existing) | Multi-stage Dockerfile: `FROM koalaman/shellcheck:stable AS sc` → `FROM node:20-alpine`, `apk add bash jq git`, `COPY --from=sc /bin/shellcheck /bin/shellcheck`, copy repo, `ENTRYPOINT ["/usr/local/bin/conjure"]` |
| DIST-04 publish-skill | `conjure audit` (validates schema), `gh` CLI (opens PR) | New `cmd_publish_skill()` in `cli/conjure`: validate frontmatter → `gh pr create` against `mohandoz/conjure-skills`. Degrades gracefully without `gh`. |
| DIST-05 org overlay | `cmd_init` + `lib/mutate.sh` | Add `--overlay <git-url>` flag to `cmd_init`; post-init step clones overlay and applies file-wins merge. |
| TECH-01 3-way merge | `cmd_update --apply` (stub at line 174) | Replace stub with: backup-before-mutate → `git merge-file --diff3 <proj> <base> <upstream>` per changed file → report conflicts. If conflicts: open `$VISUAL` for resolution (or print file list). |

### What NOT to Add (v0.4.0)

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| **npm publish** for the CLI | `conjure` is a bash script, not a Node package. `npm install -g conjure` would be a mismatch. Homebrew + git-clone are the right install paths. | Homebrew tap (DIST-02) + `git clone` quickstart |
| **Docker Hub auto-publishing** (automated push on every commit) | Premature; creates maintenance burden before the Docker image has proven users. | Pin to release-triggered publish only, gated behind a manual `workflow_dispatch` initially. |
| **`node:22-alpine`** as base | Node 22 LTS EOL is 2027-04-30; Node 20 LTS EOL is 2026-04-30 — both viable, but 22 is slightly less ecosystem-tested in CI images as of mid-2026. Either works; pick 22 if Node 20 approaches EOL before the image is live. | `node:20-alpine` with a note to migrate to 22 when 20 hits EOL |
| **Homebrew core submission** | homebrew-core requires significant maintainability bar (CI, tests, version history). Third-party tap is the right path for a young tool. Core can come later. | `homebrew-conjure` tap |
| **Public npm registry for the skill kit** | Adds a publish surface with package name squatting risk; npm users aren't the target market; Marketplace + git clone cover the same ground. | Marketplace (DIST-01) + `conjure-skills` GitHub repo (DIST-04) |
| **Bundled PR bot / auto-update daemon** | Out of scope per PROJECT.md (deferred to v0.5.0). Auto-update requires stable schemas. | `conjure update --apply` with manual confirm (TECH-01) |
| **Registry API or database for skill publish** | Overkill. PR-based contribution to a public GitHub repo is auditable, spam-throttled (gh account age), and requires zero backend. | GitHub PR workflow via `gh pr create` |
| **`shellcheck` as a runtime npm package** | No such package with parity. Statically-linked binary from `koalaman/shellcheck:stable` is the correct source. | Docker multi-stage COPY |
| **`diff3` standalone binary** | `diff3` is present on most Linux/macOS but is NOT the same as `git merge-file`. `git merge-file` is the correct primitive: it handles the three-way merge semantics, writes in-place, and provides exit codes. | `git merge-file --diff3` |

### Dockerfile Sketch (DIST-03)

```dockerfile
# Stage 1: shellcheck binary (statically linked)
FROM koalaman/shellcheck:stable AS shellcheck-bin

# Stage 2: runtime image
FROM node:20-alpine

RUN apk add --no-cache bash git jq

COPY --from=shellcheck-bin /bin/shellcheck /usr/local/bin/shellcheck

WORKDIR /opt/conjure
COPY . .
RUN ln -s /opt/conjure/cli/conjure /usr/local/bin/conjure

ENV CONJURE_HOME=/opt/conjure
ENTRYPOINT ["conjure"]
CMD ["--help"]
```

Key decisions:
- `apk add bash git jq` — bash not included in node:alpine; git needed for overlay fetch and merge-file; jq already a hard dep.
- COPY from shellcheck:stable (not :latest) — stable tag follows releases, not git HEAD.
- `CONJURE_HOME` env var — already used by `cli/conjure` to locate scripts/; must be set for the container.
- Non-root user omitted from sketch for clarity; production image should `adduser -D conjure && USER conjure`.

### Homebrew Formula Sketch (DIST-02)

```ruby
class Conjure < Formula
  desc "Production-grade Claude Code harness kit"
  homepage "https://github.com/mohandoz/conjure"
  url "https://github.com/mohandoz/conjure/archive/refs/tags/v0.4.0.tar.gz"
  sha256 "PLACEHOLDER_UPDATED_BY_CI"
  license "MIT"

  depends_on "jq"

  def install
    bin.install "cli/conjure" => "conjure"
    # install supporting scripts
    libexec.install "scripts", "lib", "profiles", "compliance",
                    "templates", "reference", ".claude-plugin"
    # patch CONJURE_HOME to point at libexec
    inreplace bin/"conjure", /CONJURE_HOME=.*/, "CONJURE_HOME=\"#{libexec}\""
  end

  test do
    assert_match "conjure", shell_output("#{bin}/conjure --help")
  end
end
```

Key decisions:
- `inreplace` patches the `CONJURE_HOME` hardcoded path — Homebrew installs to a cellar path, not the git checkout location.
- `depends_on "jq"` — only hard dep; shellcheck and node are suggested, not required, so advisory-only (use `recommended` or document in README).
- CI automation: `mislav/bump-homebrew-formula-action@v3` on release event, cross-repo write to `homebrew-conjure` with `HOMEBREW_TAP_TOKEN`.

### Marketplace.json Update (DIST-01)

The existing `.claude-plugin/marketplace.json` covers the marketplace-level fields but lacks a `plugins[]` array — the format blends marketplace and plugin manifest. Per the official docs (verified), a marketplace must have:

```json
{
  "name": "conjure",
  "owner": { "name": "mohandoz" },
  "plugins": [
    {
      "name": "conjure",
      "source": { "source": "github", "repo": "mohandoz/conjure" },
      "description": "...",
      "version": "0.4.0"
    }
  ]
}
```

Current `marketplace.json` is missing `plugins[]`. Adding it is a pure JSON edit — no code change. The `plugin.json` already has the correct component declarations (`commands`, `skills`, `agents`).

Validation command (built into Claude Code CLI, no new dep):
```bash
claude plugin validate .
```

### git-merge-file Integration (TECH-01)

The stub at `cli/conjure:174` needs:

```bash
# For each changed file (current pattern already identifies them):
local backup="${proj}.conjure-backup-$(date +%Y%m%d%H%M%S)"
cp "$proj" "$backup"
# 3-way merge: current=project file, base=version at .conjure-version tag, other=HEAD template
git merge-file --diff3 \
  -L "your version" \
  -L "conjure $pinned (base)" \
  -L "conjure $CONJURE_VERSION (upstream)" \
  "$proj" "$base_file" "$upstream_file"
merge_exit=$?
if [ "$merge_exit" -eq 0 ]; then
  echo "  ✓ $rel — merged cleanly"
elif [ "$merge_exit" -gt 0 ]; then
  echo "  ! $rel — $merge_exit conflict(s). Edit manually, then remove conflict markers."
else
  echo "  ✗ $rel — merge error; backup at $backup"
  cp "$backup" "$proj"
fi
```

`$base_file` requires either (a) a git tag per conjure release (`git show v${pinned}:templates/...`) or (b) a cached baseline in `~/.conjure/cache/`. Option (a) requires only `git` (already a dep). Option (b) requires a download step but is more reliable for users who installed via Homebrew. Recommend option (a) for v0.4.0 (simpler), with a note to revisit if non-git installs (Homebrew) become significant.

---

## Stack Additions for v0.5.0: Auto-Update + Healthcheck

**Domain:** v0.5.0 "Auto-Update + Healthcheck" additions on top of the validated v0.4.0 stack.
**Researched:** 2026-05-26
**Confidence:** HIGH for gh CLI usage (official docs + Context7 verified), GitHub check-runs API (official REST docs verified), PowerShell pwsh syntax (official Microsoft docs verified). MEDIUM for the conjure.ps1 design pattern (no authoritative precedent for bash-CLI-to-ps1-shim; derived from pwsh -File semantics and existing patterns).

### TL;DR Picks (v0.5.0)

| Feature | Pick | Confidence |
|---------|------|------------|
| DRIFT-01/02: `conjure check` drift detection | `diff -q` loop over installed vs template files (same primitive as existing `cmd_update --check`) — extract into `cmd_check` | HIGH |
| AUTPR-01: `conjure update --pr` | `git checkout -b` + `git push -u origin HEAD` + `gh pr create --title --body --base main` — explicit push before create (no `--push` flag exists) | HIGH |
| AUTPR-02: GH Action cron template | Ship `.github/workflows/conjure-update.yml.tmpl` as a template file; `conjure init` optionally writes it | HIGH |
| RESOLVE-01/02: `conjure resolve` | Walk `.conjure-conflict-*` sidecars; open each in `$VISUAL` or `$EDITOR`; delete sidecar on confirm | HIGH |
| WIN-01: `conjure.ps1` entrypoint | PowerShell 7 (pwsh) script using `$PSScriptRoot` for path resolution + `& git` + passthrough args; shebang `#!/usr/bin/env pwsh` | HIGH |
| WIN-02: pwsh CI matrix job | `runs-on: windows-latest`, `shell: pwsh` — add alongside existing `shell: bash` Windows jobs | HIGH |
| DEBT-01: ci-gate empty-check guard | `gh api .../check-runs --jq '.total_count'` → fail if 0 | HIGH |
| DEBT-02: publish-skill positional arg | Promote positional arg (already parsed at `$1`) to primary; demote `TARGET_REPO` env to fallback | HIGH |

### Detailed Findings

#### DRIFT-01/02: `conjure check` — Drift Detection

**No new tools needed.** The primitive is `diff -q "$template_file" "$installed_file"`, which is POSIX and already used in `cmd_update --check` (line 188 of `cli/conjure`). The delta for `conjure check` is:

1. Scope: `conjure check` should compare ALL harness file types (skills, agents, hooks, settings.json, CLAUDE.md), not just skills as the current `cmd_update --check` does.
2. Output format: structured delta report — added/modified/removed — rather than just a count.
3. Actionable next step: print the relevant follow-up command per delta type.

Implementation: a new `cmd_check()` function in `cli/conjure` + `scripts/check-harness.sh` worker. The worker iterates the same file lists as `lib/merge.sh` (`merge_user_files`) but calls `diff -q` and classifies as added/modified/removed. No new binary — `diff` is POSIX, already present everywhere git-bash and macOS ship.

The existing `cmd_update --check` (which only checks skills and only reports a count) should remain for backwards compat but can delegate to `cmd_check` internally.

#### AUTPR-01: `conjure update --pr` — GitHub PR Workflow

**Tool: `gh` (already a soft dep). Pattern: `git push` then `gh pr create`.**

Key verified facts about `gh pr create` (Context7 + official manual):
- There is **no `--push` flag**. If the local branch has not been pushed, the CLI prompts interactively. For a non-interactive script, you must `git push -u origin HEAD` before calling `gh pr create`.
- `--title`, `--body`, `--base`, `--head` are all available and bypass interactive prompts.
- `--repo [HOST/]OWNER/REPO` targets a different repo (not needed here — the PR is in the user's own repo).
- Duplicate PR prevention: check `gh pr list --head "$branch" --json number --jq length` before creating; if > 0, print existing PR URL instead.

Correct implementation pattern for `cmd_update_pr()`:

```bash
# 1. Run update --apply first (or verify no conflicts remain)
# 2. Create a timestamped branch
local branch="conjure/update-${CONJURE_VERSION}-$(date +%Y%m%d)"
git -C "$target" checkout -b "$branch"
# 3. Commit the merge result
git -C "$target" add .claude/
git -C "$target" commit -m "chore: update conjure harness to v${CONJURE_VERSION}"
# 4. Push (required before gh pr create in non-interactive mode)
git -C "$target" push -u origin HEAD
# 5. Create PR
gh pr create \
  --title "chore: update conjure harness to v${CONJURE_VERSION}" \
  --body "Auto-generated by \`conjure update --pr\`." \
  --base main
```

Degrade gracefully when `gh` is absent: print the git push + manual PR URL with all fields pre-filled. Follow the existing publish-skill.sh pattern (lines 129–144).

#### AUTPR-02: GH Action Cron Template

**No new runtime dep — pure YAML template shipped alongside the kit.**

Ship `templates/github/conjure-update.yml.tmpl` as a cron workflow template. Conjure can optionally write it to `.github/workflows/conjure-update.yml` during `conjure init` (opt-in, not default — follows same pattern as settings.json.tmpl).

Template content sketch:

```yaml
name: Conjure Harness Update
on:
  schedule:
    - cron: '0 9 * * 1'  # Weekly Monday 9am UTC
  workflow_dispatch:

jobs:
  update:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Update conjure harness
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          bash <(curl -fsSL https://raw.githubusercontent.com/mohandoz/conjure/main/cli/conjure) \
            update --pr
```

Note: the cron template raises a foot-gun concern (`curl | bash`). The safer pattern for the template is to pin to a specific version tag and use `git clone` locally. Flag this in the template with a comment. Implementation detail, not a stack question — but worth noting here so the roadmap phase includes a safety review.

#### RESOLVE-01/02: `conjure resolve` — Interactive Conflict Resolution

**No new tools needed.** The sidecar format is already defined by `lib/merge.sh:write_merge_sidecar`. The sidecar filename pattern is `.conjure-conflict-<encoded>` where `<encoded>` is the relative path with `/` replaced by `_`.

`cmd_resolve()` implementation:
1. `find "$target/.claude" -name '.conjure-conflict-*'` to collect sidecars.
2. For each sidecar, print the diff3 content (the sidecar IS the merged file with conflict markers).
3. Open in `${VISUAL:-${EDITOR:-vi}}` — same convention as git and other POSIX tools.
4. After editor returns, ask "Mark as resolved? [y/N]". On `y`: copy sidecar back to the canonical path (sidecar name decodes back to the original path), delete the sidecar.
5. When all sidecars resolved: prompt user to stamp the new version (`echo 'v...' > .claude/.conjure-version`).

The `read -r` prompt pattern is already used in the kit. No new dep. The decoding is a `tr '_' '/'` on the encoded name segment.

The editor-open step must tolerate CI/non-interactive environments (no TTY). Guard with `[ -t 0 ]` check; in non-interactive mode, print the sidecar path and tell the user to edit manually.

#### WIN-01: `conjure.ps1` — Native PowerShell Entrypoint

**Tool: PowerShell 7 (pwsh). Pattern: `$PSScriptRoot` path resolution + passthrough via `& git`.**

Key verified facts (official Microsoft docs, pwsh 7.5/7.6):
- `#!/usr/bin/env pwsh` shebang works on Linux/macOS for PowerShell 7. On Windows, the shebang is ignored; the file is invoked with `pwsh -File conjure.ps1`.
- `pwsh -File <script>` is the correct invocation. As of PowerShell 7.2, `-File` only accepts `.ps1` on Windows (a `.ps1` extension is correct for this use case).
- `$PSScriptRoot` resolves to the directory containing the script — equivalent to `$(dirname "$0")` in bash. This is the reliable path anchor for `CONJURE_HOME`.
- `$IsWindows`, `$IsLinux`, `$IsMacOS` are built-in booleans for OS detection (PowerShell 6+).
- `-NonInteractive` and `-NoProfile` flags are relevant for CI contexts where `conjure.ps1` might be invoked from a script.

`conjure.ps1` design:

```powershell
#!/usr/bin/env pwsh
# conjure.ps1 — Native PowerShell entrypoint for conjure.
# Works on Windows (native pwsh, no Git Bash required), macOS, Linux.
# Invocation: pwsh -File conjure.ps1 <args>
#             or: ./conjure.ps1 <args>  (when pwsh is in PATH)

$conjureHome = $PSScriptRoot
$conjureBash = Join-Path $conjureHome "cli" "conjure"

if ($IsWindows) {
    # On native Windows, delegate to Git Bash if available, otherwise
    # invoke Node.js for hook-capable operations only.
    $gitBash = (Get-Command "bash.exe" -ErrorAction SilentlyContinue)?.Source
    if ($gitBash) {
        & $gitBash $conjureBash @args
        exit $LASTEXITCODE
    }
    Write-Error "Git Bash not found. Install Git for Windows or use WSL."
    Write-Host "  winget install Git.Git"
    exit 1
} else {
    # macOS/Linux: delegate to the bash entrypoint directly
    & bash $conjureBash @args
    exit $LASTEXITCODE
}
```

Key decisions:
- `@args` is PowerShell's splatting of all positional arguments — equivalent to `"$@"` in bash. This passes all flags and arguments through correctly.
- `$LASTEXITCODE` propagates the exit code from the bash subprocess. Without it, the PowerShell process exits 0 regardless.
- `?.Source` is PowerShell 7 null-conditional member access. On PowerShell 5.1 (Windows PowerShell), this would need `if ($gitBash) { $gitBash.Source }` — but `conjure.ps1` targets pwsh 7+ explicitly.
- The Windows path is explicit about the limitation: on native Windows without Git Bash, the bash CLI cannot run. The ps1 entrypoint makes this clear with an actionable message + install hint.
- Do NOT try to implement conjure logic in PowerShell. The ps1 is purely a launcher shim. All logic stays in the bash entrypoint.

**Why not a full PowerShell port:** The bash CLI is ~330 lines and embeds POSIX primitives (process substitution, `set -uo pipefail`, `find` loops). A faithful port would require maintaining two implementations in sync forever. The shim pattern keeps a single source of truth.

**CI validation (WIN-02):** Add a job `windows-ps1` to `ci.yml`:

```yaml
windows-ps1:
  runs-on: windows-latest
  steps:
    - uses: actions/checkout@v4
    - name: Smoke test conjure.ps1
      shell: pwsh
      run: |
        $result = & ./conjure.ps1 version
        if ($LASTEXITCODE -ne 0) { exit 1 }
        Write-Host "conjure.ps1 version output: $result"
```

This validates the ps1 shim works in a real pwsh environment. The existing `windows-test` and `windows-hook-wiring` jobs run with `shell: bash` and remain unchanged.

#### DEBT-01: ci-gate Empty-Check Guard

**Tool: `gh api` (already used in `release.yml`). Pattern: `total_count` check.**

The existing `ci-gate` job in `release.yml` filters check-runs by conclusion (failure/timed_out/cancelled/action_required) but does NOT guard against the case where `total_count` is 0 (no checks ran at all — a race condition where the tag push precedes CI). The fix is a single additional guard:

```bash
total=$(gh api \
  "/repos/${{ github.repository }}/commits/${{ github.sha }}/check-runs" \
  --jq '.total_count')
if [ "$total" -eq 0 ]; then
  echo "FAIL: zero check-runs found for ${{ github.sha }} — CI may not have run yet"
  exit 1
fi
```

This uses the `total_count` field that the GitHub REST API always returns (verified against official docs — the response is always `{total_count: N, check_runs: [...]}` with `total_count: 0` when empty). No new tool — `gh api` is already authenticated in the workflow via `GH_TOKEN: ${{ github.token }}`.

The guard should exclude the "Release" check itself from the count (same filter as the existing failed-checks query): filter to `select(.name != "Release")` before counting. Otherwise a release re-run would see itself in the count.

Revised pattern:

```bash
total=$(gh api \
  "/repos/${{ github.repository }}/commits/${{ github.sha }}/check-runs" \
  --jq '[.check_runs[] | select(.name != "Release")] | length')
if [ "$total" -eq 0 ]; then
  echo "FAIL: no non-Release check-runs found — CI has not run for this commit"
  exit 1
fi
```

Using `[...] | length` via jq rather than `.total_count` because `total_count` is the count of ALL check runs before the `select` filter, so it could be non-zero (e.g., 1 from the Release job itself) while the meaningful CI jobs are absent.

#### DEBT-02: `conjure publish-skill` Positional Arg

**No new tools.** The positional arg (`$1` in `scripts/publish-skill.sh`) is already parsed and stored in `SKILL_NAME`. The `TARGET_REPO` env/flag (`--to`) already works. The refactor is purely within `cli/conjure`'s `cmd_publish_skill()` dispatch: make `<target-repo>` a positional arg when provided as the second positional, and treat `TARGET_REPO` env as a fallback (not primary).

Current interface:
```
conjure publish-skill <name> [--to <org/repo>] [--dry-run]
TARGET_REPO=org/repo conjure publish-skill <name>
```

Target interface (DEBT-02):
```
conjure publish-skill <name> [<org/repo>] [--dry-run]
conjure publish-skill <name> --to <org/repo> [--dry-run]  # still works
TARGET_REPO=org/repo conjure publish-skill <name>           # still works (lowest priority)
```

Implementation: in `scripts/publish-skill.sh`, after parsing `SKILL_NAME=$1`, check if `$2` matches the `owner/repo` regex and is not a flag — if so, use it as `TARGET_REPO`. The existing `--to` flag overrides. This is a 5-line change in the argument parser.

### v0.5.0 Stack Summary Table

| Tool / Pattern | Version / Source | Feature | New to stack? |
|----------------|-----------------|---------|---------------|
| `diff -q` (POSIX) | system | DRIFT-01/02 drift detection | No — already used |
| `gh pr create` + `git push -u origin HEAD` | system gh CLI (soft dep, already advisory) | AUTPR-01 PR creation | Pattern is new; tool is existing soft dep |
| YAML template (`conjure-update.yml.tmpl`) | shipped file | AUTPR-02 cron automation | New template file, no new tool |
| `${VISUAL:-${EDITOR:-vi}}` | POSIX env convention | RESOLVE-01/02 conflict editor | No — standard POSIX pattern |
| `find .claude -name '.conjure-conflict-*'` | POSIX find | RESOLVE-01 sidecar discovery | No — same find pattern as merge.sh |
| `conjure.ps1` shim | pwsh 7+ (PowerShell 7) | WIN-01 native Windows entrypoint | New file; pwsh is new optional dep |
| `shell: pwsh` in GH Actions | GitHub Actions built-in | WIN-02 CI matrix | New job config, no new tool |
| `gh api` + `--jq '[...] | length'` | system gh CLI (already in release.yml) | DEBT-01 empty-check guard | Pattern extension; tool exists |
| Second positional arg parsing | bash | DEBT-02 publish-skill refactor | No — pure bash refactor |

**Net new dependencies: zero.** All v0.5.0 features are implemented with tools already in the preflight stack (`diff`, `find`, `git`, `gh`, `jq`) plus `pwsh` as a new optional soft dep for Windows users who want native PowerShell. `dependencies: {}` stays empty.

### v0.5.0 Integration Points

| Feature | Integrates With | Integration Approach |
|---------|----------------|---------------------|
| DRIFT-01/02 `conjure check` | Existing `cmd_update --check` logic | Extract file-comparison loop to `scripts/check-harness.sh`; `cmd_check()` calls it; `cmd_update --check` delegates to same worker |
| AUTPR-01 `conjure update --pr` | `cmd_update --apply` + `gh` CLI | New `--pr` flag in `cmd_update` arg parser; `git checkout -b` → apply → `git push` → `gh pr create`; degrade to manual instructions if `gh` absent |
| AUTPR-02 cron template | `conjure init` + `templates/github/` | New template dir; `cmd_init` optionally writes it when `--with-cron-update` flag passed |
| RESOLVE-01/02 `conjure resolve` | `lib/merge.sh` sidecar naming convention | New `cmd_resolve()` + `scripts/resolve-conflicts.sh`; depends on sidecar format from `write_merge_sidecar()` which must not change |
| WIN-01 `conjure.ps1` | `cli/conjure` (bash entrypoint) | New file `cli/conjure.ps1`; `CONJURE_HOME` set via `$PSScriptRoot`; shellcheck must skip `.ps1` files |
| WIN-02 pwsh CI job | `.github/workflows/ci.yml` | New `windows-ps1` job with `shell: pwsh`; add `cli/conjure.ps1` to shellcheck exclusion list |
| DEBT-01 empty-check guard | `.github/workflows/release.yml` ci-gate step | Prepend `total` count check before the conclusion-filter check |
| DEBT-02 positional arg | `scripts/publish-skill.sh` arg parser | Minimal change: detect `$2` as positional `TARGET_REPO` when it matches owner/repo pattern |

### What NOT to Add (v0.5.0)

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| **`--push` flag in `gh pr create`** | Does not exist. Requesting it causes an error. | Explicit `git push -u origin HEAD` before `gh pr create` |
| **Full PowerShell port of `cli/conjure`** | Doubles maintenance burden; two CLI implementations diverge. The bash CLI is 330 lines and POSIX-idiomatic — a ps1 port would be ~600 lines and different. | `conjure.ps1` shim that delegates to bash via Git Bash on Windows |
| **PowerShell 5.1 (Windows PowerShell) support** | `?.` null-conditional and `$IsWindows` require PS 6+; PS 5.1 is maintenance-mode since 2022; pwsh 7 ships with all Windows 11 installs via winget. | Require pwsh 7+ explicitly; document `winget install Microsoft.PowerShell` |
| **`peter-evans/create-pull-request` Action** | External action with broad permissions; overkill for a simple `git push + gh pr create` in the cron template. Adds a dependency on a third-party action. | `gh pr create` with `GH_TOKEN` (already in the workflow context) |
| **Interactive `select` menu for `conjure resolve`** | `select` is bash 4+ (macOS ships bash 3.2). A `while read -r` prompt loop works on bash 3.2+. | `while read -r` + explicit `y/n` prompt |
| **Auto-committing the merge result in `conjure update --apply`** | Existing behavior: user reviews and commits. Changing this would break the "human confirms before git history changes" trust contract. | Print instructions; user commits manually. `--pr` creates the commit as part of its flow. |
| **`gh` as a hard dep for any v0.5.0 feature** | `gh` is advisory. Windows users without `gh` must still get useful output. | Degrade to manual URL + instructions; same pattern as `publish-skill.sh` lines 137–144 |
| **`xdg-open` / `open` / `start` for editor launch** | OS-specific; not portable. VS Code users would expect a different opener than terminal users. | `${VISUAL:-${EDITOR:-vi}}` — the universal POSIX editor-open convention |
| **`total_count` field directly for DEBT-01 guard** | `total_count` counts ALL runs including the Release job itself. Using it means the Release job's own check-run satisfies the guard, defeating the purpose. | `[.check_runs[] | select(.name != "Release")] | length` via jq |

### v0.5.0 Bash Patterns Reference

Key patterns used across v0.5.0 features — all POSIX bash 3.2+ compatible:

```bash
# Drift detection: classify delta type
if [ -f "$installed" ] && ! diff -q "$template" "$installed" >/dev/null 2>&1; then
  echo "  ~ $rel (modified)"
elif [ ! -f "$installed" ]; then
  echo "  + $rel (new upstream file)"
fi

# PR branch creation (conjure update --pr)
branch="conjure/update-${CONJURE_VERSION}-$(date +%Y%m%d)"
git -C "$target" checkout -b "$branch"

# Push before pr create (non-interactive prerequisite)
git -C "$target" push -u origin HEAD

# PR dedup guard
existing=$(gh pr list --head "$branch" --json number --jq length 2>/dev/null || echo 0)
[ "$existing" -gt 0 ] && { echo "PR already exists"; gh pr list --head "$branch"; return 0; }

# Sidecar discovery (conjure resolve)
find "$target/.claude" -maxdepth 3 -name '.conjure-conflict-*' > "$_sidecar_list"

# Editor open with POSIX fallback
${VISUAL:-${EDITOR:-vi}} "$sidecar"

# CI guard: count non-Release check-runs
total=$(gh api "/repos/${REPO}/commits/${SHA}/check-runs" \
  --jq '[.check_runs[] | select(.name != "Release")] | length')
[ "$total" -eq 0 ] && { echo "FAIL: no CI checks found"; exit 1; }
```

---

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|-------------------------|
| Hand-rolled `run.sh` fixtures | bats-core v1.13.0 | When per-function unit specs (dry-run invariants, arg parsing) outgrow inline `pass`/`fail` helpers. Adopt as a submodule alongside, never replacing the integration loop. |
| bats-core | shellspec 0.28.1 | Essentially never — last release Jan 2021, unmaintained. Only if you needed deep ksh/zsh/dash matrix testing, which this kit does not. |
| chars/4 heuristic | `messages.countTokens()` API (`--exact` opt-in) | When a user wants billing-grade numbers and has API creds. Lazy, flagged, never default (rate-limited, needs network + auth). |
| JSONL + jq telemetry | sqlite / analytics SDK | Never for this kit — violates zero-heavy-dep + local-only + cross-platform constraints. |
| `command -v` probe | `troubleshoot`/`preflight-check` tools | Never — those are Kubernetes/heavyweight; wildly out of scope for a shell kit. |
| Homebrew tap (`homebrew-conjure`) | Homebrew core | Core requires higher maintainability bar; tap is the right start for a young tool. Revisit if adoption grows. |
| `git merge-file --diff3` | `diff3` standalone, `patch`, or Node diffing lib | `git merge-file` is more robust (three-way semantics, in-place write, exit codes); `diff3` is POSIX but lacks the three-way merge contract; patch is one-directional; Node lib is a dep violation. |
| `node:20-alpine` Docker base | `debian:bookworm-slim` | Debian slim if you need glibc-linked binaries or more system packages; alpine is 25% smaller and all tools (bash, jq, shellcheck) are available. |
| PR-based skill contribution via `gh` | REST API calls, npm publish | `gh pr create` is zero-dep (soft dep, print fallback), audit-trailed, and spam-throttled by GitHub account age. |
| `conjure.ps1` shim delegating to bash | Full PowerShell port of `cli/conjure` | Never for this kit — doubles maintenance burden, diverges over time, and the bash CLI is the authoritative implementation. |
| `${VISUAL:-${EDITOR:-vi}}` for resolve editor | `xdg-open`, `open`, `code` | If you want a specific editor integration — but that's a user preference, not a kit choice. The POSIX env convention respects user config. |
| `[.check_runs[] | select(...)] | length` | `.total_count` | Use `.total_count` only if you want ALL checks including the Release job itself. For the ci-gate guard, you need to exclude the Release job. |

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| **`@anthropic-ai/tokenizer`** | Officially inaccurate for Claude 3+ (kit targets Claude 4.x); adds an npm dep for a wrong answer | chars/4 heuristic (already in SIZING.md) |
| **tiktoken / `gpt-tokenizer`** | OpenAI encodings; only approximate Claude, and pull a WASM/native dep | chars/4 heuristic |
| **shellspec** | Unmaintained since 0.28.1 (Jan 2021); trust-first kit shouldn't depend on abandoned tooling | bats-core v1.13.0 (Nov 2025) |
| **An analytics/telemetry SDK or any phone-home** | Privacy + trust killer for an OSS kit; adds a dep + network | Local append-only JSONL parsed by jq |
| **sqlite for the telemetry store** | Heavy native dep; cross-platform binary headaches; overkill for append+count | JSONL file |
| **Parsing `transcript_path` JSONL for skill detection** | Fragile, large, format-volatile; unnecessary now that `PreToolUse` exposes `tool_name=Skill`/`skill_name` | `PreToolUse` + `InstructionsLoaded` hook events |
| **`which` for detection** | Not guaranteed present; inconsistent exit codes across platforms | `command -v` (bash) / platform-aware probe (`.mjs`) |
| **Auto-running installers in preflight** | Violates the kit's "no `curl\|sh` foot-guns" safety rule | Print one copy-pasteable install command; human runs it |
| **npm `dependencies` in the kit** | Breaks "no hard dependency on heavy runtimes"; forces an install step | stdlib-only `.mjs`; `npx --yes` for rare opt-in paths |
| **npm publish for the CLI tool** | Mismatch: conjure is bash, not a Node module. Creates install confusion. | Homebrew tap + git-clone quickstart |
| **`diff3` standalone for 3-way merge** | Not a three-way merge implementation — `diff3` shows differences, `git merge-file` does the merge. Using `diff3` for merging requires manual scripting to apply hunks. | `git merge-file --diff3` (git builtin, already a hard dep) |
| **Docker Hub auto-push on every commit** | Maintenance burden before Docker image has users; premature. | Release-triggered publish only |
| **Registry API/database for skill publishing** | Backend to maintain, no users yet. | PR-based GitHub workflow via `gh pr create` |
| **`gh --push` flag** | Does not exist in gh CLI (verified). Using it causes an error. | `git push -u origin HEAD` before `gh pr create` |
| **`peter-evans/create-pull-request` Action** | Third-party action with broad permissions; unnecessary since `gh` is already available in Actions context. | `gh pr create` with `GH_TOKEN` |
| **PowerShell 5.1 / Windows PowerShell** | Maintenance-mode since 2022; missing `$IsWindows`, `?.` null-conditional. conjure.ps1 targets pwsh 7+. | `winget install Microsoft.PowerShell` |
| **`select` menu in `conjure resolve`** | bash 4+ only; macOS ships bash 3.2. | `while read -r` + y/n prompt |

## Stack Patterns by Variant

**If fixture assertions stay simple (audit exit code + file presence):**
- Use hand-rolled `run.sh` loop only. No submodule.
- Because: adding bats for `grep`+exit-code checks is pure overhead.

**If you add fine-grained unit specs (dry-run invariants, telemetry-format, arg parsing):**
- Vendor bats-core + bats-assert as pinned submodules; keep `run.sh` as the integration driver that also invokes `bats tests/unit/`.
- Because: readable assertions + TAP output earn their keep at the unit level.

**If a user needs billing-grade cost numbers:**
- `conjure audit --cost --exact` → lazy SDK `countTokens()` if creds present.
- Because: heuristic is for budgeting; exact mode is for the rare precision case, never the default.

**If running on native Windows (no WSL/git-bash):**
- Use `conjure.ps1` (v0.5.0); it delegates to Git Bash if present, or explains how to install it.
- Because: native PowerShell cannot run the bash CLI directly; ps1 shim + Git Bash is the supported path.

**For DIST-03 Docker — base image choice:**
- Use `node:20-alpine` + `apk add bash git jq` + multi-stage shellcheck copy.
- Because: keeps image small, uses official images, no custom base to maintain.

**For DIST-04 publish-skill without `gh`:**
- `cmd_publish_skill` validates frontmatter locally, then either runs `gh pr create` or prints a step-by-step manual PR URL.
- Because: same "print, don't auto-run" principle as preflight install hints.

**For `conjure update --pr` without `gh`:**
- Print: `git push -u origin HEAD` + manual PR URL with pre-filled title/body.
- Because: consistent degradation pattern across all `gh`-dependent commands.

**For `conjure resolve` in non-interactive (CI) context:**
- Guard with `[ -t 0 ]`; if no TTY, print sidecar paths and skip editor. Exit 0 with instructions.
- Because: CI pipelines don't have a terminal; blocking on `read` would hang the job.

## Version Compatibility

| Package A | Compatible With | Notes |
|-----------|-----------------|-------|
| bats-core v1.13.0 | bash 3.2+ | macOS ships bash 3.2; v1.13.0 supports it. Submodule, no npm. |
| bats-assert v2.2.4 | bats-core v1.x | Requires bats-support; both as submodules (not on npm). |
| shellcheck v0.11.0 | POSIX + bash 5.3 directives | New SC2327–2335 checks; expect a few new lints on fresh telemetry scripts. |
| Node `.mjs` hooks | Node >=18 LTS, stdlib only | No transitive deps to break. |
| Price table | rates as of 2026-05 | Drifts ~quarterly; keep in one constant block with a verify-at-URL comment. |
| Claude Code hooks API | Claude Code >=2.1.117 (kit min) | `Skill` tool event + `InstructionsLoaded` confirmed present in current hooks reference. |
| `node:20-alpine` | Docker Engine >=20.10 | Node 20 LTS; EOL 2026-04-30; migrate to node:22-alpine before EOL. |
| `koalaman/shellcheck:stable` | Alpine 3.x multi-stage | Statically linked; works on any Linux base, no musl/glibc concern. |
| `git merge-file` | git >=2.x (already a hard dep) | Present on all platforms including git-bash on Windows. |
| Homebrew tap formula | Homebrew 4.x | Ruby formula; `depends_on "jq"` satisfied by homebrew-core. |
| `mislav/bump-homebrew-formula-action` | v3 | Needs COMMITTER_TOKEN with `repo` + `workflow` scopes for tap repo. |
| `conjure.ps1` | pwsh 7.0+ (PowerShell Core) | Uses `$IsWindows`, `?.` null-conditional, `@args` splatting — all require pwsh 6+; target 7+ for stability. Incompatible with Windows PowerShell 5.1. |
| `gh pr create` | gh >=2.x | No `--push` flag in any version. Always push first with `git push -u origin HEAD`. |
| GitHub check-runs API | GitHub REST API v3 | `GET /repos/{owner}/{repo}/commits/{ref}/check-runs` returns `{total_count, check_runs[]}`. Use jq `length` filter after `select` to count filtered runs. |

## Sources

### v0.3.0 Sources (unchanged)
- [Claude Code Hooks reference](https://code.claude.com/docs/en/hooks) — HIGH. Confirmed full event list, `PreToolUse`/`PostToolUse` `tool_name: "Skill"` + `tool_input.skill_name`, `InstructionsLoaded` event, common fields (`session_id`, `cwd`, `transcript_path`), exit-code semantics (0 parses stdout, 2 blocks), JSON output options (`suppressOutput`).
- [bats-core GitHub releases (API)](https://github.com/bats-core/bats-core) — HIGH. v1.13.0 published 2025-11-07; bats-assert v2.2.4 latest tag.
- [ShellSpec releases (API)](https://github.com/shellspec/shellspec) — HIGH. Latest 0.28.1 published 2021-01-11 (unmaintained → disqualified).
- [bats-core installation docs](https://bats-core.readthedocs.io/en/stable/installation.html) — HIGH. Git-submodule install path; helper libs not on npm.
- [shellcheck releases (API)](https://github.com/koalaman/shellcheck) — HIGH. v0.11.0 (2025-08-03), new SC2327–2335 checks.
- [@anthropic-ai/tokenizer (npm)](https://www.npmjs.com/package/@anthropic-ai/tokenizer) — HIGH. Explicitly "no longer accurate as of Claude 3 models" → do not bundle.
- [Claude API Token counting docs](https://platform.claude.com/docs/en/build-with-claude/token-counting) — HIGH. `countTokens()` is the only billing-grade source; free but rate-limited; ~4 chars/token rule of thumb.
- [Claude API Pricing](https://platform.claude.com/docs/en/about-claude/pricing) — HIGH. Haiku 4.5 $1/$5, Sonnet 4.6 $3/$15, Opus 4.7 $5/$25 per 1M; output 5× input; 90% cache / 50% batch discounts.
- [Conjure `reference/SIZING.md`](reference/SIZING.md) — HIGH (internal). Existing chars/4 token estimates + session baseline (~20k) + MCP metadata (500–3000/server) — reuse directly in the estimator.
- [Conjure `cli/conjure` `cmd_preflight()`](cli/conjure) — HIGH (internal). Existing `command -v` probe + tiered required/optional tools to extend.

### v0.4.0 Sources (new)
- [Claude Code Marketplace docs](https://code.claude.com/docs/en/plugin-marketplaces) — HIGH. Full `marketplace.json` schema verified: required fields (`name`, `owner`, `plugins[]`), plugin entry fields (`source`, `version`, `strict`, `category`, `tags`), all source types (`github`, `url`, `git-subdir`, `npm`, relative path), reserved names list, `claude plugin validate` CLI command, `CLAUDE_CODE_PLUGIN_SEED_DIR` for container pre-population. Verified 2026-05-25.
- [Conjure `.claude-plugin/marketplace.json`](.claude-plugin/marketplace.json) — HIGH (internal). Existing file present; missing `plugins[]` array; needs update not rewrite.
- [Homebrew Taps docs](https://docs.brew.sh/Taps) — HIGH. Repo must be named `homebrew-<name>`; one-argument `brew tap user/repo` works only with that naming convention; formulas auto-update on `brew update`.
- [Homebrew Formula Cookbook](https://docs.brew.sh/Formula-Cookbook) — HIGH. `bin.install "script" => "name"`, `inreplace` for path patching, `depends_on`, `test do` block requirements.
- [mislav/bump-homebrew-formula-action](https://github.com/mislav/bump-homebrew-formula-action) — MEDIUM. v3 current; auto-updates URL + SHA256 in tap repo on release; needs `COMMITTER_TOKEN` with `repo` + `workflow` scopes.
- [koalaman/shellcheck Docker Hub](https://hub.docker.com/r/koalaman/shellcheck-alpine) — HIGH. `stable` tag = latest release; multi-stage `COPY --from=koalaman/shellcheck:stable /bin/shellcheck /bin/shellcheck` is the documented pattern.
- [nodejs/docker-node](https://github.com/nodejs/docker-node) — HIGH. `node:20-alpine` does NOT include bash; requires `apk add bash`. Alpine ~25% smaller than Debian slim.
- [git-merge-file docs](https://git-scm.com/docs/git-merge-file) — HIGH. Full option set verified: `--diff3` for three-section conflict markers, `-p`/`--stdout` for preview, exit 0 = clean, 1–127 = N conflicts, negative = error. `-L` for custom labels.
- [anthropics/skills GitHub](https://github.com/anthropics/skills) — MEDIUM. Anthropic's own public skill repo; confirms PR-based contribution pattern is the ecosystem norm.
- [vercel-labs/skills](https://github.com/vercel-labs/skills) — MEDIUM. `npx skills` CLI pattern; confirms GitHub repo + PR workflow is standard for skill registries, not a custom API.

### v0.5.0 Sources (new)
- [gh pr create manual](https://cli.github.com/manual/gh_pr_create) — HIGH. Full flag list verified: `--title`, `--body`, `--base`, `--head`, `--repo`, `--draft`, `--fill`. Confirmed: no `--push` flag exists. Branch must be pushed before `gh pr create` in non-interactive mode. Verified 2026-05-26.
- [Context7 /cli/cli — pr create docs](https://context7.com/cli/cli) — HIGH. Confirmed `gh pr create --base main --head feature-branch` pattern; `--fill` for auto-populate; duplicate PR check via `gh pr list --head "$branch" --json number --jq length`. Verified 2026-05-26.
- [gh cli/cli issue #8152](https://github.com/cli/cli/issues/8152) — HIGH. Confirms `--push` flag does not exist and is an open feature request as of 2023; not shipped since. Workaround: `git push -u origin HEAD && gh pr create`. Verified 2026-05-26.
- [GitHub REST API: check-runs for commit](https://docs.github.com/en/rest/checks/runs) — HIGH. `GET /repos/{owner}/{repo}/commits/{ref}/check-runs` returns `{total_count: N, check_runs: [...]}`. `total_count: 0` when no runs. Filter with jq `select` before counting for accurate non-Release check count. Verified 2026-05-26.
- [Microsoft Learn: about_Pwsh (pwsh 7.5)](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_pwsh?view=powershell-7.5) — HIGH. Full parameter list verified: `-File`, `-Command`, `-NonInteractive`, `-NoProfile`, `-WorkingDirectory`. `$PSScriptRoot` resolves to script directory. `$IsWindows`/`$IsLinux`/`$IsMacOS` are built-in PS 6+. `?.` null-conditional is PS 7+. `@args` splatting passes all arguments through. `-File` accepts `.ps1` on Windows (7.2+). Shebang `#!/usr/bin/env pwsh` works on Linux/macOS. Verified 2026-05-26.
- [Conjure `cli/conjure`](cli/conjure) — HIGH (internal). `cmd_update --check` at lines 183–197 uses `diff -q`; `cmd_update --apply` at lines 200–257 calls `lib/merge.sh`. Sidecar pattern in `lib/merge.sh:write_merge_sidecar`. Confirmed patterns reusable for `cmd_check` and `cmd_resolve`. Verified 2026-05-26.
- [Conjure `scripts/publish-skill.sh`](scripts/publish-skill.sh) — HIGH (internal). Lines 129–144: degrade pattern when `gh` absent — print manual PR URL. This is the template for all `gh`-dependent degrade paths in v0.5.0. Verified 2026-05-26.
- [Conjure `.github/workflows/release.yml`](.github/workflows/release.yml) — HIGH (internal). ci-gate job at lines 9–28: existing `gh api .../check-runs` query pattern with `--jq` filter. DEBT-01 adds a `total` count guard before the conclusions check. Verified 2026-05-26.

---
*Stack research for: Conjure v0.3.0 Testing + telemetry tooling*
*Updated: 2026-05-26 — v0.5.0 Auto-Update + Healthcheck additions appended*
