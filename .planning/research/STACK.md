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

## Stack Additions for v0.6.0: Safe Brownfield Adoption

**Domain:** v0.6.0 "Safe Brownfield Adoption" additions on top of the validated v0.5.0 stack.
**Researched:** 2026-05-28
**Confidence:** HIGH for all primitives (git status --porcelain, wc -l, find, cp -a, jq -c, skill !`cmd` injection — each verified against official docs or the current skills reference). MEDIUM for the manifest JSON schema (design decision, not an external standard).

### TL;DR Picks (v0.6.0)

| Feature | Pick | Confidence |
|---------|------|------------|
| ADOPT-01: Inventory 2000+ markdown files | `find <root> -name '*.md' -print0 \| xargs -0 wc -l` batched into a jq JSONL manifest via a single `mktemp` pass | HIGH |
| ADOPT-02: Full snapshot backup | `cp -a <target> <target>/.conjure-adopt-backup-<ts>/` before any mutation; `mutate_cp` already handles DRY_RUN | HIGH |
| ADOPT-03: Git-clean precondition | `git -C "$target" status --porcelain=v1` — empty output = clean; non-empty = dirty, refuse unless `--force` | HIGH |
| ADOPT-04: CLAUDE.md size/cap detection | `wc -l < "$target/CLAUDE.md"` (redirect, no filename noise); compare to hardcoded cap 100 | HIGH |
| ADOPT-05: CLI→skill manifest handshake | Single JSON file at `.claude/adopt-manifest.json`; jq `-c` for compact line-emit; skill reads via `!`cat .claude/adopt-manifest.json`` dynamic injection | HIGH |
| ADOPT-06: Skill-to-CLI edit application | Skill emits one-line `conjure adopt --apply-patch <step-id>` Bash commands; CLI reads a per-step JSON patch file from `.claude/adopt-patches/<step>.json`; mutate_write executes | HIGH |

### Detailed Findings by Question

#### (1) Inventorying and classifying 2000+ markdown files efficiently in bash/.mjs

**Pick: single `find` + `mktemp`-buffered while-read loop; emit one jq JSONL object per file; never exec per file.**

The stress fixture (argus, 2180 markdown files) fits comfortably in bash with one `find` pass and no parallelism needed. The bottleneck is syscall volume, not CPU — the right approach is to minimize process forks, not add GNU parallel.

**Concrete pattern (POSIX bash 3.2+, no associative arrays):**

```bash
# Emit one JSON line per .md file: path, line-count, byte-size, classify result
_inv="$(mktemp)"
find "$target" -name '*.md' -not -path '*/.git/*' -print0 \
  | xargs -0 wc -l 2>/dev/null \
  | grep -v '^ *[0-9]* total$' \
  | while IFS= read -r line; do
      bytes=$(printf '%s' "$line" | awk '{print $1}')
      path=$(printf '%s' "$line" | awk '{$1=""; print substr($0,2)}')
      class=$(classify_md_file "$path")   # see below
      jq -cn --arg p "$path" --arg c "$class" --argjson b "$bytes" \
        '{path:$p, lines:$b, class:$c}'
    done > "$_inv"
```

The `classify_md_file` function uses `case`/`grep` heuristics against the file path and (optional) first-line content to assign one of six classes:

| Class | Heuristic |
|-------|-----------|
| `harness-core` | Is `.claude/CLAUDE.md` exactly |
| `harness-skill` | Path matches `.claude/skills/*/SKILL.md` |
| `harness-agent` | Path matches `.claude/agents/*.md` |
| `planning-doc` | Path under `.planning/` |
| `reference-doc` | Path under `docs/`, `reference/`, `wiki/` (configurable) |
| `unknown` | Everything else |

**Performance reality for 2180 files:** `find + xargs wc -l` on 2180 small markdown files completes in under 2 seconds on an NVMe SSD. This does not require ripgrep, parallelism, or any external tool beyond what is already in the preflight stack. `wc -l` batches files via `xargs`, so it is one process per batch of ~5000 files (xargs default), not one process per file.

**Why not `wc -c` (byte count) only?** Line count is the audit signal (cap is measured in lines, not bytes). Both are cheap — collect both in the same pass.

**Why not `stat` for size?** `stat` format flags differ between BSD (macOS) and GNU (Linux). `wc -c` is fully POSIX. For the rare case where a `.md` file has no trailing newline, `wc -l` undercounts by 1 — this is acceptable for cap-detection purposes (the harness cap is 100 lines, not 99.9).

**Why not a `.mjs` inventory script?** `find` + `wc` is faster for file enumeration than Node's `fs.readdir` recursive walk (which requires async + Promise chaining). Reserve `.mjs` for hooks and the exact-count opt-in path. The inventory is a CLI-phase operation, not a hook.

**jq compact-output for JSONL:** `jq -c` (compact) emits one JSON object per line — the correct JSONL format. Each call to `jq -cn` (null input) constructs an object from `--arg` and `--argjson` flags. No shell variable interpolation into JSON strings (injection risk + quoting bugs). This is the correct pattern from the existing `lib/exact-count.mjs` and jq official cookbook.

#### (2) Deterministic full-snapshot backup + verifiable rollback

**Pick: `cp -a` timestamped snapshot of every touched directory before mutation; `mutate_cp` already wraps the DRY_RUN gate; rollback = `cp -a <backup> <original>`.**

The existing backup strategy for `migrate`/`update` is an ad-hoc `.claude.backup-<ts>` of the `.claude/` dir only. `conjure adopt` touches more: the CLAUDE.md root, any `docs/` pile, the `.planning/` dir. The snapshot must cover all touched paths.

**Concrete backup primitive (new `mutate_snapshot`):**

```bash
# mutate_snapshot <target_dir> <label>
# Creates: <target_dir>/../.conjure-adopt-<label>-<ts>/
# In dry-run: prints intent, does not copy.
# Returns snapshot path in CONJURE_LAST_SNAPSHOT.
mutate_snapshot() {
  local dir="$1"
  local label="${2:-adopt}"
  local ts
  ts="$(date +%Y%m%d%H%M%S)"
  local snap_parent
  snap_parent="$(dirname "$dir")"
  local snap_name=".conjure-${label}-backup-${ts}"
  local snap_path="${snap_parent}/${snap_name}"
  if [ "${DRY_RUN:-0}" = "1" ]; then
    echo "[dry-run] would snapshot $dir → $snap_path"
    CONJURE_DRY_MUTATION_COUNT=$((CONJURE_DRY_MUTATION_COUNT + 1))
    CONJURE_LAST_SNAPSHOT="$snap_path"
    return 0
  fi
  cp -a "$dir" "$snap_path"
  CONJURE_LAST_SNAPSHOT="$snap_path"
}
```

`cp -a` is POSIX (equivalent to `-dR --preserve=all` on GNU, `-Rp` on BSD) and preserves timestamps + permissions. It is the correct primitive for a faithful backup. No `tar`, no temp dir coordination needed.

**Rollback:** `--rollback` in `conjure adopt` reads the snapshot path from `RESTRUCTURE-LOG.md` (persisted at adopt time), then calls `mutate_cp "$snap_path" "$original_dir"`. The log format includes a `snapshot:` field for exactly this purpose.

**Why not `tar` for the snapshot?** `tar` requires a second command to extract, and the backup is a local directory (not a distributable archive). `cp -a` is faster for restore (no decompression), POSIX, and the backup dir is human-inspectable. For the argus stress fixture (~2180 files), `cp -a` on a typical project directory takes under 5 seconds.

**What triggers a snapshot?** Once, before any mutation, at the top of `cmd_adopt`. Never per-step — one snapshot, one rollback path. The RESTRUCTURE-LOG records each mutation step after the snapshot. This is the same "backup-before-mutate" contract as existing `migrate`/`update` flows.

**Integrity check for rollback:** After snapshot, compute `find <snap_path> -type f | wc -l` and record it in the log. Rollback first verifies the count matches before proceeding. This guards against a corrupt/partial snapshot (e.g., disk full during `cp -a`).

#### (3) Git-clean preconditioning via porcelain status

**Pick: `git -C "$target" status --porcelain=v1`; empty stdout = clean tree; non-empty = dirty; refuse unless `--force`.**

`git status --porcelain=v1` (or `--porcelain` without version, which implies v1) is the canonical script-safe format. It is:
- Stable across git versions (the explicit contract of `--porcelain`)
- Unaffected by user `color.status`, `status.relativePaths`, or locale settings
- One line per changed/untracked file; empty output = perfectly clean working tree

**Concrete guard function:**

```bash
# check_git_clean <target> [--force]
# Returns 0 if clean or --force passed; exits 2 if dirty and no --force.
check_git_clean() {
  local target="$1"
  local force="${2:-}"
  # Not a git repo at all: skip (conjure adopt works on non-git dirs with --force)
  if ! git -C "$target" rev-parse --git-dir >/dev/null 2>&1; then
    [ "$force" = "--force" ] && return 0
    echo "✗ $target is not a git repository. Use --force to adopt anyway." >&2
    exit 2
  fi
  local status_output
  status_output="$(git -C "$target" status --porcelain=v1 2>/dev/null)"
  if [ -n "$status_output" ]; then
    if [ "$force" = "--force" ]; then
      echo "⚠ dirty working tree (--force passed, proceeding):" >&2
      printf '%s\n' "$status_output" | head -10 >&2
      return 0
    fi
    echo "✗ Dirty working tree. Commit or stash changes before adopt." >&2
    echo "  Use --force to skip this check." >&2
    printf '%s\n' "$status_output" | head -5 >&2
    exit 2
  fi
  return 0
}
```

**Why `--porcelain=v1` and not `--porcelain=v2`?** v2 adds branch headers and more detail than needed. The guard only cares about "is there any output?" — v1 is sufficient and universally supported (git ≥1.8, which covers all supported platforms). v2 requires git ≥2.11.

**Why not `git diff --quiet && git diff --cached --quiet`?** That pattern misses untracked files. `--porcelain` reports tracked-modified, staged, AND untracked (`??`) in one call.

**Why `exit 2` not `exit 1`?** The kit convention is `exit 2` for "blocked / cannot proceed" (hook contract). `exit 1` is reserved for detected drift/failure in the `conjure check` flow. `adopt` is a command, not a hook, but following the kit's exit-code semantics is correct.

**Non-git repos:** Some brownfield projects are not git repos (a `design/` folder, a `wiki/` export). Allow `--force` to bypass the check and proceed anyway. Record the bypass in RESTRUCTURE-LOG.

#### (4) CLAUDE.md size / over-cap detection

**Pick: `wc -l < "$path"` (redirect, not filename argument) to get clean integer; compare to cap constant; also classify byte-weight using `wc -c` for the inventory manifest.**

```bash
# detect_claude_size <claude_md_path>
# Emits: lines, bytes, over_cap (0|1)
# Cap constants match conjure audit (CLAUDE.md ≤100 lines, SKILL.md ≤200, agent ≤80)
CLAUDE_MD_CAP=100
SKILL_MD_CAP=200
AGENT_MD_CAP=80

detect_claude_size() {
  local path="$1"
  local cap="${2:-$CLAUDE_MD_CAP}"
  [ -f "$path" ] || { echo "0 0 0"; return; }
  local lines bytes
  lines=$(wc -l < "$path")
  bytes=$(wc -c < "$path")
  local over=0
  [ "$lines" -gt "$cap" ] && over=1
  printf '%d %d %d\n' "$lines" "$bytes" "$over"
}
```

The redirect form `wc -l < "$path"` suppresses the filename suffix that `wc -l "$path"` emits. This gives a clean integer, parseable directly in bash without `awk '{print $1}'`. This is POSIX-portable (bash 3.2+ and all POSIX shells).

**Byte-weight as secondary signal:** A CLAUDE.md at exactly 100 lines but with 40KB of content per line is still a smell. Capture `wc -c` in the manifest for the `restructure` skill to surface to the user, even though the hard cap is line-count.

**Integration with existing `conjure audit`:** `scripts/audit-setup.sh` already checks line caps via a `wc -l` loop. The adopt flow reuses the same constants (`CLAUDE_MD_CAP`, `SKILL_MD_CAP`, `AGENT_MD_CAP`) from a shared `lib/caps.sh` constant file (new, small — 5 lines) rather than re-hardcoding them in `scripts/adopt.sh`. This prevents the caps from drifting between audit and adopt.

**Over-cap trigger for the `restructure` skill:** If `detect_claude_size` returns `over=1`, `conjure adopt` emits a manifest entry `{"path":"CLAUDE.md","lines":180,"bytes":21504,"cap":100,"over_cap":true}` that the `restructure` skill reads and acts on. The skill does not re-run `wc` — it trusts the manifest.

#### (5) CLI→skill manifest format: the data handshake

**Pick: `.claude/adopt-manifest.json` — a single JSON file; jq-generated; skill reads via `!`cat .claude/adopt-manifest.json`` dynamic injection.**

The manifest is the bridge between deterministic CLI phase (file scan, size measurement, classification) and LLM judgment phase (restructuring proposal). It must be:
1. Human-readable (editable if needed for debugging)
2. Machine-parseable by jq in subsequent CLI steps
3. Ingestible by the `restructure` skill without a subprocess round-trip

**Manifest schema (recommended):**

```json
{
  "schema_version": "1",
  "generated_at": "2026-05-28T10:00:00Z",
  "target": "/abs/path/to/project",
  "snapshot": "/abs/path/to/project/../.conjure-adopt-backup-20260528100000",
  "snapshot_file_count": 2180,
  "git_clean": true,
  "claude_md": {
    "path": "CLAUDE.md",
    "lines": 180,
    "bytes": 21504,
    "cap": 100,
    "over_cap": true
  },
  "files": [
    {
      "path": "relative/path/to/file.md",
      "lines": 45,
      "bytes": 3200,
      "class": "planning-doc"
    }
  ],
  "summary": {
    "total_files": 2180,
    "by_class": {
      "harness-core": 1,
      "harness-skill": 17,
      "harness-agent": 6,
      "planning-doc": 35,
      "reference-doc": 120,
      "unknown": 2001
    },
    "over_cap_files": ["CLAUDE.md"]
  }
}
```

**Why a single JSON file, not JSONL?** The `restructure` skill injects the entire manifest into context via `!`cat .claude/adopt-manifest.json``. A single JSON document is simpler for Claude to parse and reason about than a JSONL stream. The manifest for the argus fixture is ~2180 entries × ~80 bytes = ~175 KB of JSON text. This is large for context injection; see the truncation note below.

**Manifest truncation for large projects:** For projects with >500 markdown files, the `files[]` array becomes too large to inject into a skill context without hitting token limits. The skill should inject the `summary` and `claude_md` objects first, then load the full `files[]` array on demand via a follow-up `Read` tool call. The manifest generation must preserve `summary` at the top level for this reason.

**Practical approach for the argus stress fixture:** The `restructure` skill should inject only the summary section first:
```
!`jq '{summary, claude_md, git_clean, snapshot}' .claude/adopt-manifest.json`
```
Then request specific class subsets:
```
!`jq '[.files[] | select(.class == "planning-doc")]' .claude/adopt-manifest.json`
```

This avoids loading 2180 entries into context. The skill SKILL.md should demonstrate this pattern explicitly.

**jq generation pattern in `scripts/adopt.sh`:**

```bash
# Write manifest using jq -n to construct from shell variables safely
# (never use string interpolation to build JSON — quoting bugs + injection risk)
jq -cn \
  --arg schema "1" \
  --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg target "$target" \
  --arg snapshot "$CONJURE_LAST_SNAPSHOT" \
  --argjson snap_count "$snap_count" \
  --argjson git_clean "$git_clean_flag" \
  --slurpfile files "$_inv_jsonl_file" \
  '{
    schema_version: $schema,
    generated_at: $ts,
    target: $target,
    snapshot: $snapshot,
    snapshot_file_count: $snap_count,
    git_clean: $git_clean,
    files: $files[0],
    summary: ($files[0] | group_by(.class) | map({key: .[0].class, value: length}) | from_entries
             | {total_files: ($files[0] | length), by_class: .})
  }' > "$target/.claude/adopt-manifest.json"
```

`--slurpfile` reads the entire JSONL temp file into `$files[0]` as a JSON array. `group_by(.class)` builds the `by_class` summary. No shell string interpolation into the JSON — all values pass through `--arg` or `--argjson` flags. This is the same injection-safe pattern used in `lib/exact-count.mjs`.

**Why not a separate `manifest.sh` library?** The manifest generation is a one-shot operation in `scripts/adopt.sh`, not a reusable library function. Keep it inline in adopt.sh, behind a `generate_manifest()` function, rather than adding `lib/manifest.sh`. The `lib/` directory is for shared chokepoints (mutate, merge); adopt-specific logic belongs in `scripts/adopt.sh`.

#### (6) Skill applying edits back through CLI safe mutate primitives

**Pick: skill emits explicit shell commands; CLI runs them with `mutate_write`/`mutate_cp`; per-step patch files under `.claude/adopt-patches/<step-id>.json`; human approves each step before the CLI is invoked.**

The `restructure` skill is LLM judgment + human gating. It must not call `mutate_write` directly — the skill has no direct access to the bash function. The handshake is:

1. **Skill proposes** a structured patch as a JSON file at `.claude/adopt-patches/<step-id>.json`
2. **Human reviews** the proposal in the Claude Code session (the skill displays a diff-like summary)
3. **Human approves** by running `conjure adopt --apply-patch <step-id>` in the terminal
4. **CLI reads** the patch JSON and executes each operation via `mutate_write`/`mutate_mkdir`/`mutate_cp`
5. **CLI appends** the applied step to `RESTRUCTURE-LOG.md` and updates the manifest

**Patch file schema:**

```json
{
  "step_id": "extract-gsd-skill-01",
  "description": "Extract GSD workflow instructions from CLAUDE.md into .claude/skills/gsd/SKILL.md",
  "operations": [
    {
      "op": "write",
      "path": ".claude/skills/gsd/SKILL.md",
      "content": "---\nname: gsd\n...\n"
    },
    {
      "op": "write",
      "path": "CLAUDE.md",
      "content": "... truncated CLAUDE.md with GSD section replaced by @skill reference ..."
    }
  ],
  "proposed_at": "2026-05-28T10:05:00Z",
  "approved_at": null
}
```

**CLI patch application in `scripts/adopt.sh`:**

```bash
cmd_adopt_apply_patch() {
  local step_id="$1"
  local patch_file="$target/.claude/adopt-patches/${step_id}.json"
  [ -f "$patch_file" ] || { echo "✗ patch not found: $patch_file" >&2; exit 2; }

  # Read operations array from patch file
  local op_count
  op_count=$(jq '.operations | length' "$patch_file")
  local i=0
  while [ "$i" -lt "$op_count" ]; do
    local op path content
    op=$(jq -r ".operations[$i].op" "$patch_file")
    path=$(jq -r ".operations[$i].path" "$patch_file")
    case "$op" in
      write)
        content=$(jq -r ".operations[$i].content" "$patch_file")
        mutate_mkdir "$(dirname "$target/$path")"
        mutate_write "$target/$path" "$content"
        ;;
      mkdir)
        mutate_mkdir "$target/$path"
        ;;
      archive)
        local archive_dest=".conjure-archive/$(basename "$path")"
        mutate_mkdir "$target/.conjure-archive"
        mutate_cp "$target/$path" "$target/$archive_dest"
        mutate_rm "$target/$path"
        ;;
    esac
    i=$((i + 1))
  done

  # Stamp approved_at and append to RESTRUCTURE-LOG
  local now; now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  jq --arg t "$now" '.approved_at = $t' "$patch_file" \
    | mutate_write "$patch_file" "$(cat)"
  append_restructure_log "$step_id" "$op_count operations applied"
}
```

**Why patch files under `.claude/adopt-patches/`, not inline JSON passed via CLI args?** CLI args have shell quoting limits (~2MB ARG_MAX, but more importantly: quoting a multi-line SKILL.md body in a shell arg is fragile). The patch file is the safe boundary. The skill writes the file via its `Write` tool; the CLI reads it via `jq`. This also makes the patch human-reviewable before apply.

**Why not have the skill directly invoke `conjure adopt --apply` with all content on stdin?** Piping multi-kilobyte content through stdin requires the skill to use `Bash` tool, which the user must approve per-invocation. A file-based handshake lets the human review the patch file in the Claude Code session before issuing the CLI command. The separation between "skill proposes" and "human approves + CLI applies" is the safety contract.

**`archive` op vs `delete` op:** The kit's never-delete principle means the only destructive operation is `archive` (move to `.conjure-archive/`) — never a bare `rm`. The `mutate_rm` primitive exists but should not be used by the patch applier. `archive` uses `mutate_cp` + `mutate_rm` in sequence, matching the existing pattern in `cmd_migrate` for file archival.

**RESTRUCTURE-LOG.md format:** Append-only markdown table:

```markdown
| step | applied_at | operations | snapshot |
|------|-----------|------------|----------|
| extract-gsd-skill-01 | 2026-05-28T10:06Z | 2 | .conjure-adopt-backup-20260528100000 |
```

Written via `mutate_write "$log_path" "$row" --append`. The log is the audit trail that makes `--rollback` possible.

### New Files for v0.6.0

| File | Type | Purpose |
|------|------|---------|
| `scripts/adopt.sh` | bash worker | `cmd_adopt` implementation: git-clean check, snapshot, inventory, manifest emit, patch apply, log append |
| `lib/caps.sh` | bash constants | `CLAUDE_MD_CAP=100`, `SKILL_MD_CAP=200`, `AGENT_MD_CAP=80` — sourced by both `audit-setup.sh` and `adopt.sh` |
| `.claude/skills/restructure/SKILL.md` | Claude Code skill | Reads adopt-manifest.json, proposes restructuring, writes patch files via Write tool |
| `.claude/skills/restructure/README.md` | skill support file | Concise operational guide: what the skill does, how to invoke, how to apply patches |

### v0.6.0 Integration Points with Existing Code

| New Capability | Integrates With | Integration Approach |
|----------------|----------------|---------------------|
| `mutate_snapshot` | `lib/mutate.sh` | Add as a new primitive alongside `mutate_mkdir/cp/write/rm`. Same DRY_RUN gate + counter increment. Same shell-function pattern — no associative arrays, no local -n, POSIX 3.2+. |
| Size-cap constants | `scripts/audit-setup.sh` + `scripts/adopt.sh` | Extract hardcoded `100`/`200`/`80` constants from `audit-setup.sh` into new `lib/caps.sh`; both scripts `source "$CONJURE_HOME/lib/caps.sh"`. |
| `check_git_clean` | `scripts/adopt.sh` | Inline function in adopt.sh (not a lib/ shared primitive — only adopt needs it at this stage). Uses the same `exit 2` convention as the rest of the kit. |
| Inventory JSONL → manifest | `scripts/adopt.sh` → `.claude/adopt-manifest.json` | `generate_manifest()` function in adopt.sh; jq `-cn --slurpfile` pattern for safe JSON construction; manifest written via `mutate_write`. |
| Patch application | `scripts/adopt.sh` + `lib/mutate.sh` | `cmd_adopt_apply_patch()` in adopt.sh sources `lib/mutate.sh` and calls `mutate_write`/`mutate_mkdir`/`mutate_cp`/`mutate_rm`. Inherits `DRY_RUN` gate automatically. |
| `restructure` skill dynamic injection | `.claude/skills/restructure/SKILL.md` | Uses `!`jq '{summary, claude_md}' .claude/adopt-manifest.json`` for summary, then `Read` tool for full file array. Does NOT use `--slurp`-reading the full 175KB file into context at skill load. |
| RESTRUCTURE-LOG.md | `scripts/adopt.sh` | Written via `mutate_write ... --append` — same append primitive already used for JSONL telemetry. |

### v0.6.0 Stack Summary Table

| Tool / Pattern | Version / Source | Feature | New to stack? |
|----------------|-----------------|---------|---------------|
| `find <root> -name '*.md' -print0` | POSIX find | ADOPT-01 file inventory | No — already used in `lib/merge.sh`, `scripts/check.sh` |
| `xargs -0 wc -l` | POSIX xargs + wc | ADOPT-01 line-count in batches | Pattern is new; tools are existing |
| `jq -cn --arg ... --slurpfile ...` | jq (system, preflight dep) | ADOPT-01 manifest generation | Pattern is new; jq is existing dep |
| `cp -a <dir> <backup>` | POSIX cp | ADOPT-02 full snapshot | `cp -r` already used in mutate_cp; `-a` flag is the new nuance |
| `git -C "$t" status --porcelain=v1` | git (hard dep) | ADOPT-03 git-clean check | Pattern is new; git is existing dep |
| `wc -l < "$path"` (redirect form) | POSIX wc | ADOPT-04 line-count + cap check | Pattern is new; wc already exists everywhere |
| `lib/caps.sh` constants file | bash (new 5-line file) | ADOPT-04 cap constants shared between audit + adopt | New file; no new tool |
| `.claude/adopt-manifest.json` | JSON (jq-generated) | ADOPT-05 CLI→skill handshake | New format; jq is existing dep |
| `!`jq ... .claude/adopt-manifest.json`` | Claude Code skill `!`cmd`` injection | ADOPT-05 manifest consumption in skill | New usage of existing skill feature; verified in official docs |
| `.claude/adopt-patches/<step>.json` | JSON (skill-written) | ADOPT-06 skill→CLI patch handshake | New format; jq is existing dep |
| `jq -r ".operations[$i]..."` loop | jq (system dep) | ADOPT-06 patch application | Pattern is new; jq is existing dep |
| `mutate_write ... --append` | `lib/mutate.sh` (existing) | ADOPT-06 RESTRUCTURE-LOG append | No — `--append` flag already implemented in mutate_write |
| `mutate_snapshot` (new primitive) | `lib/mutate.sh` (extend) | ADOPT-02 snapshot primitive | New function in existing lib; no new tool |

**Net new dependencies: zero.** All v0.6.0 features use tools already in the preflight stack (`find`, `xargs`, `wc`, `cp`, `git`, `jq`). `dependencies: {}` stays empty.

### What NOT to Add (v0.6.0)

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| **`ripgrep` / `ag` for inventory** | Not in the preflight stack; `find -name '*.md'` is sufficient for enumeration; classification is path-based, not content search | `find -print0 \| xargs -0 wc -l` (POSIX, already preflight-checked) |
| **GNU `parallel` for inventory** | Not POSIX; not in preflight; 2180 files completes in <2s without parallelism; adds a dep for no measurable gain on this workload | Single `find` + `xargs -0` (xargs batches internally) |
| **`stat` for file metadata** | Format flags differ BSD vs GNU (`-f '%z'` vs `-c '%s'`); not worth the portability branch | `wc -c < "$path"` (POSIX, no format flag needed) |
| **Full 2180-file `files[]` array injection into skill context** | ~175 KB of JSON text ≈ ~44k tokens; blows the skill context budget; the skill doesn't need all 2180 paths to reason about CLAUDE.md restructuring | Inject `summary` + `claude_md` first via `!`jq '...'``; load specific classes on demand with `Read` tool |
| **Storing patch content as CLI arg or stdin pipe** | Shell quoting limits; fragile for multi-line SKILL.md content; impossible to human-review before apply | Patch file under `.claude/adopt-patches/<step>.json`; skill writes via Write tool; CLI reads via jq |
| **`mutate_rm` for archive operations** | Violates never-delete principle; `rm -f` is irreversible | `archive` op: `mutate_cp` to `.conjure-archive/` then `mutate_rm` — same semantics as `cmd_migrate` file archival |
| **Bare `cp` in `mutate_snapshot`** | `cp -r` does not preserve timestamps; `cp -a` does (both GNU/BSD support `-a`). Timestamps matter for rollback identity and for `find -newer` queries | `cp -a` in `mutate_snapshot` |
| **`git status --short` for the clean check** | `--short` output is affected by `--column` and color config; `--porcelain` is the contract-stable flag | `git status --porcelain=v1` |
| **Separate `lib/manifest.sh`** | Manifest generation is a one-shot adopt-only operation; adding a `lib/` file implies it's a reusable chokepoint (it isn't); keeps lib/ focused on `mutate` + `merge` | Inline `generate_manifest()` function in `scripts/adopt.sh` |
| **Auto-applying patches without human approval** | Explicitly out-of-scope (PROJECT.md: "fully autonomous restructure is a non-goal") | Human types `conjure adopt --apply-patch <id>` after reviewing in session |
| **`jq --rawfile` for patch content** | `--rawfile` reads a file as a raw string (no JSON parsing); incorrect for structured patch JSON | `--slurpfile` (reads as JSON array) or `jq -r` field extraction per-operation |

### v0.6.0 Bash Patterns Reference

Key patterns introduced in v0.6.0 — all POSIX bash 3.2+ compatible:

```bash
# Git clean check (porcelain=v1, empty = clean)
status_out="$(git -C "$target" status --porcelain=v1 2>/dev/null)"
[ -n "$status_out" ] && { echo "dirty tree"; exit 2; }

# File inventory: find + xargs wc-l, emit JSONL
find "$target" -name '*.md' -not -path '*/.git/*' -print0 \
  | xargs -0 wc -l 2>/dev/null \
  | grep -v '^ *[0-9]* total$' \
  | while IFS= read -r wc_line; do
      lcount=$(printf '%s' "$wc_line" | awk '{print $1}')
      fpath=$(printf '%s' "$wc_line" | awk '{$1=""; print substr($0,2)}')
      jq -cn --arg p "$fpath" --argjson l "$lcount" '{path:$p,lines:$l}'
    done >> "$_inv"

# Line-count only (cap check, clean integer output)
lines=$(wc -l < "$claude_md_path")
[ "$lines" -gt "$CLAUDE_MD_CAP" ] && echo "over cap: $lines/$CLAUDE_MD_CAP"

# Snapshot before mutation
mutate_snapshot "$target" "adopt"
# → sets CONJURE_LAST_SNAPSHOT

# Manifest: jq -cn with --slurpfile for JSONL array
jq -cn --slurpfile files "$_inv" \
  --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  '{generated_at: $ts, files: $files[0], summary: ...}' \
  > "$target/.claude/adopt-manifest.json"

# Patch apply loop (jq field extraction per index)
count=$(jq '.operations | length' "$patch")
i=0; while [ "$i" -lt "$count" ]; do
  op=$(jq -r ".operations[$i].op" "$patch")
  path=$(jq -r ".operations[$i].path" "$patch")
  # ... dispatch on $op
  i=$((i+1))
done

# RESTRUCTURE-LOG append
row="| $step_id | $(date -u +%Y-%m-%dT%H:%MZ) | $op_count | $CONJURE_LAST_SNAPSHOT |"
mutate_write "$log_path" "$row"$'\n' --append
```

### restructure Skill SKILL.md Sketch

```yaml
---
name: restructure
description: >
  Reads the conjure adopt manifest, proposes a safe restructuring plan for an oversized or
  messy CLAUDE.md, and writes patch files for human-gated CLI application.
  Use when conjure adopt has run and .claude/adopt-manifest.json exists.
disable-model-invocation: true
allowed-tools: Read Write Bash(conjure adopt --apply-patch *) Bash(conjure adopt --dry-run)
---

## Project inventory summary

!`jq '{summary, claude_md, git_clean, snapshot}' .claude/adopt-manifest.json`

## Instructions

You are restructuring a brownfield project's CLAUDE.md and doc sprawl into the
four-layer conjure harness. Work through these steps, getting human approval before
each apply:

1. Read the full CLAUDE.md at the path shown in `claude_md.path` above.
2. Identify what can extract to skills (procedures > 20 lines, repeated workflows),
   what should stay (project facts, constraints, stack decisions), and what is stale
   (instructions for tools no longer used).
3. For each extraction, propose the new SKILL.md content and the trimmed CLAUDE.md.
   Write the proposal as a patch file:
   `Write .claude/adopt-patches/<step-id>.json` with the schema from the adopt docs.
4. Show a human-readable summary of what the patch will do. Ask for approval.
5. After approval, the human runs: `conjure adopt --apply-patch <step-id>`
6. If you need to inspect planning docs: Read `.claude/adopt-manifest.json` and
   filter by class:
   `!`jq '[.files[] | select(.class == "planning-doc")]' .claude/adopt-manifest.json``
7. Never write directly to CLAUDE.md or skills/. All edits go through patch files.
```

### v0.6.0 Sources

- [Claude Code Skills docs](https://code.claude.com/docs/en/skills) — HIGH. Full frontmatter reference verified: `!`cmd`` dynamic injection runs before Claude sees content; `allowed-tools` space-separated string; `disable-model-invocation: true` prevents auto-trigger; `${CLAUDE_SKILL_DIR}` for bundled-file references. Skill SKILL.md ≤200 lines cap matches conjure's own skill cap. Verified 2026-05-28.
- [git-status docs](https://git-scm.com/docs/git-status) — HIGH. `--porcelain=v1` is stable-format guarantee; unaffected by user color/locale config; empty output = clean working tree; `??` prefix = untracked files. Verified 2026-05-28.
- [jq manual (jqlang/jq)](https://jqlang.org/jq/manual/) — HIGH. `-c` compact output (one JSON per line = JSONL); `-n` null input for construction; `--arg`/`--argjson`/`--slurpfile` are injection-safe arg passing; `group_by` + `from_entries` for summary aggregation; `inputs` builtin for entity-by-entity JSONL reading. Verified via Context7 /jqlang/jq. 2026-05-28.
- [xargs man page](https://man7.org/linux/man-pages/man1/xargs.1.html) — HIGH. `-0` null-delimiter option pairs with `find -print0`; xargs batches arguments to stay under ARG_MAX; no per-file fork overhead. POSIX-standard. Verified 2026-05-28.
- [wc POSIX spec](https://pubs.opengroup.org/onlinepubs/9699919799/utilities/wc.html) — HIGH. `-l` counts newlines; redirect form `wc -l < file` suppresses filename column; POSIX-portable across macOS/Linux/Git Bash. Verified 2026-05-28.
- [cp POSIX spec](https://pubs.opengroup.org/onlinepubs/9699919799/utilities/cp.html) — HIGH. `-a` (archive) is not POSIX strictly — it is a GNU/BSD extension equivalent to `-Rp`. GNU cp supports `-a`; BSD (macOS) cp supports `-a` since macOS 10.5+. All supported platforms have `-a`. `-Rp` is the POSIX fallback if ever needed on a minimal system. Verified 2026-05-28.
- [Conjure `lib/mutate.sh`](lib/mutate.sh) — HIGH (internal). `mutate_write --append` flag already implemented (line 60–64); `CONJURE_DRY_MUTATION_COUNT` pattern for new `mutate_snapshot` to follow. `DRY_RUN` gate confirmed. Verified 2026-05-28.
- [Conjure `lib/merge.sh`](lib/merge.sh) — HIGH (internal). `mktemp` + POSIX while-read loop pattern for find results (lines 107–123); confirmed bash 3.2+ no-associative-array constraint. Verified 2026-05-28.
- [Conjure `scripts/check.sh`](scripts/check.sh) — HIGH (internal). `sha256_file` cross-platform sha256 pattern (lines 18–24); POSIX find loop with `mktemp` buffer (lines 28–97); `--porcelain` output formatting pattern. Confirmed DRY_RUN-free (read-only); adopt.sh likewise separates read-only inventory from mutation phases. Verified 2026-05-28.
---
*Stack research for: Conjure v0.3.0 Testing + telemetry tooling*
*Updated: 2026-05-28 — v0.6.0 Safe Brownfield Adoption additions appended*
