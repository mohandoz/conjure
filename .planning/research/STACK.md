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
- Use the `.mjs` hook + `.mjs` preflight variants; bash CLI assumes git-bash/WSL.
- Because: native Windows can't run the bash hooks; `.mjs` is the portability layer.

**For DIST-03 Docker — base image choice:**
- Use `node:20-alpine` + `apk add bash git jq` + multi-stage shellcheck copy.
- Because: keeps image small, uses official images, no custom base to maintain.

**For DIST-04 publish-skill without `gh`:**
- `cmd_publish_skill` validates frontmatter locally, then either runs `gh pr create` or prints a step-by-step manual PR URL.
- Because: same "print, don't auto-run" principle as preflight install hints.

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

---
*Stack research for: Conjure v0.3.0 Testing + telemetry tooling*
*Updated: 2026-05-25 — v0.4.0 Distribution + Ecosystem additions appended*
