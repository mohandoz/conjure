# Architecture Research

**Domain:** Open-source init kit for Claude Code — POSIX bash CLI + Node `.mjs` hooks (Conjure v0.4.0 "Distribution + Ecosystem")
**Researched:** 2026-05-25
**Confidence:** HIGH (existing codebase read directly; Claude Code Marketplace schema verified against official docs; Homebrew tap conventions verified against official docs)

> **Scope note (subsequent milestone):** This file documents how the seven v0.4.0
> capabilities (DIST-01 through DIST-05, TECH-01, plus the Homebrew/Docker delivery
> channels) slot into the *current* file layout. Existing layout is taken as
> fixed and shipped: `cli/conjure` (dispatcher) → `scripts/*.sh` → `lib/mutate.sh`
> (write chokepoint) → `profiles/` `compliance/` `migrations/` `templates/`;
> `tests/run.sh` is the single test entrypoint. Everything from v0.3.0 is already
> green (200 assertions).

---

## Existing Architecture (v0.3.0, fixed baseline)

```
cli/conjure          — dispatcher: parse flags, call scripts/*, source lib/*
  └── cmd_init        — init|migrate; --profile; --dry-run; calls scripts/init-project.sh
  └── cmd_audit       — calls scripts/audit-setup.sh; --cost; --retire-list
  └── cmd_update      — --check shows diff; --apply STUB (cli/conjure:171-178)
  └── cmd_migrate     — calls migrations/<source>/migrate.sh
  └── cmd_preflight   — calls scripts/preflight.sh
  └── cmd_refresh_graph / cmd_install_mcp

lib/mutate.sh         — write chokepoint (ALL filesystem mutations go here)
lib/cost.sh           — char→token→$ estimation (sourced by audit-setup.sh)
lib/prices.json       — per-model price table
lib/exact-count.mjs   — opt-in Anthropic SDK exact token counter

scripts/init-project.sh   — scaffold .claude/
scripts/audit-setup.sh    — health-check; --cost; --retire-list
scripts/preflight.sh      — dependency verification
scripts/refresh-graph.sh
scripts/install-mcp-stack.sh

profiles/<stack>/apply.sh          — CLAUDE.md fragment + preflight
compliance/<overlay>/apply.sh      — CLAUDE.md fragment + control files

.claude-plugin/
  ├── marketplace.json   — marketplace catalog (lists conjure as a plugin)
  ├── plugin.json        — plugin manifest
  └── SCHEMAS/           — skill.schema.json, agent.schema.json

tests/run.sh              — 200-assertion suite
tests/fixtures/<profile>/ — committed scaffolds per profile
```

Key constraint: **every filesystem write in the kit routes through `lib/mutate.sh`**
(mutate_mkdir / mutate_cp / mutate_write). New commands must follow this invariant.

---

## New Components

### 1. `scripts/publish-plugin.sh` (DIST-01)
**What:** Packages `.claude-plugin/` and prepares the marketplace submission.

The Claude Code Marketplace does not have a REST submission API — distribution is
done by updating `marketplace.json` in the conjure repo and pushing a git tag.
Specifically: the official Anthropic marketplace (`claude-plugins-official`) requires
a PR to add a plugin entry; community marketplaces are self-hosted repos. DIST-01
therefore means: (a) ensure `.claude-plugin/marketplace.json` is well-formed and
version-bumped, (b) emit the JSON snippet a maintainer pastes into a PR against
the Anthropic catalog, and (c) optionally push the conjure repo tag so the
`git-subdir` source pins to a real SHA.

Fields required in `.claude-plugin/marketplace.json` (verified against official docs):
```json
{
  "name": "conjure",
  "owner": { "name": "mohandoz" },
  "plugins": [{
    "name": "conjure",
    "source": { "source": "github", "repo": "mohandoz/conjure", "ref": "v0.4.0", "sha": "<40-char>" },
    "description": "...",
    "version": "0.4.0",
    "category": "developer-tools"
  }]
}
```

New file: `scripts/publish-plugin.sh`
- Reads `VERSION`
- Validates `.claude-plugin/marketplace.json` with `jq`
- Resolves the current HEAD SHA (`git rev-parse HEAD`)
- Writes/updates the `sha` field in marketplace.json via `mutate_write`
- Prints the JSON snippet for the Anthropic catalog PR
- Optionally checks `plugin.json` version matches `VERSION`

### 2. `cmd_publish` in `cli/conjure` (DIST-01)
**What:** New dispatch case in the CLI.
```
conjure publish [--dry-run]
```
Calls `scripts/publish-plugin.sh`. Follows the same `--dry-run` env pattern.
Minimal: ~10 lines in the dispatch table + function.

### 3. `scripts/publish-skill.sh` (DIST-04)
**What:** Packages a named skill from `.claude/skills/<name>/` and emits the plugin
entry JSON needed to contribute it to the conjure public kit (or a custom marketplace).

```
conjure publish-skill <name> [--dry-run]
```

Flow:
1. Locate `<target>/.claude/skills/<name>/SKILL.md` (default target = cwd)
2. Validate frontmatter against `.claude-plugin/SCHEMAS/skill.schema.json`
3. Emit a `plugin.json` stub for the skill as a standalone plugin
4. Print instructions for opening a PR against `mohandoz/conjure` to add it to `templates/skills/`

Does NOT require 3-way merge (TECH-01). Depends on schema validation only.

### 4. `scripts/apply-org-overlay.sh` (DIST-05)
**What:** Fetches and applies a private org overlay repo.

```
conjure init --org-overlay=<git-url-or-local-path> [target]
```

An org overlay is structurally identical to a compliance overlay: a directory with
`apply.sh` + optional `CLAUDE.md.fragment` + additional templates. The only new
capability is *fetching* it from a remote git URL before applying.

Flow:
1. Accept `--org-overlay=<git-url-or-local-path>` in `cmd_init`
2. If URL: `git clone --depth 1 <url> /tmp/conjure-org-overlay-$$` into a temp dir
3. Source and call the overlay's `apply.sh` (same interface as compliance overlays)
4. Clean up temp clone
5. Stamp `.claude/.conjure-org-overlay` with the URL + clone SHA for audit traceability

The overlay is a git repo users own. No conjure-side registry needed.

### 5. `lib/merge.sh` (TECH-01)
**What:** 3-way merge implementation for `cmd_update --apply`.

The existing stub at `cli/conjure:171-178` acknowledges the placeholder. The
implementation uses `git merge-file` (available wherever git is installed, which is
a preflight requirement), which takes three files: `current` (project's file),
`base` (the kit version that was installed when the project was initialized), and
`new` (current kit template). This is the canonical POSIX approach — no additional
tooling needed.

File: `lib/merge.sh`
Functions:
- `merge_skill(current, base, new, dest)` — calls `git merge-file -p current base new`; on conflict prints markers and returns non-zero
- `merge_with_backup(src, dest, base_ref)` — wraps `merge_skill` + backup-before-mutate via `lib/mutate.sh`

`cmd_update --apply` in `cli/conjure` is then completed:
1. For each differing skill: find `base` from `.conjure-version` stamp + git tag lookup, run `merge_with_backup`
2. Conflicts: print file paths, instruct user to resolve (no interactive editor — cross-platform constraint)
3. On clean merge: update `.conjure-version`

### 6. `Dockerfile` + `.github/workflows/docker.yml` (DIST-03)
**What:** Multi-stage Docker image with bash + jq + shellcheck + git + node pre-installed.
Not a CLI command — a delivery channel.

Location: `Dockerfile` at repo root, `docker.yml` CI job.

Base image: `debian:bookworm-slim` (not Alpine — bash 3.2 compat, jq in apt).
Published to: `ghcr.io/mohandoz/conjure:latest` + `ghcr.io/mohandoz/conjure:v<VERSION>`.

### 7. `homebrew-conjure` tap (DIST-02)
**What:** External Homebrew tap repository — not a file in this repo.

Location: separate GitHub repo `mohandoz/homebrew-conjure` (naming convention required
by Homebrew: `homebrew-<tapname>`). Contains `Formula/conjure.rb`.

The formula:
- `url` points to the GitHub release tarball `https://github.com/mohandoz/conjure/archive/refs/tags/v<VERSION>.tar.gz`
- `sha256` is the tarball hash (must be updated per release)
- `install` copies `cli/conjure` to `bin/conjure` and installs `scripts/`, `lib/`, `profiles/`, `compliance/`, `templates/`, `.claude-plugin/`
- `depends_on "jq"`, `depends_on "git"` — shellcheck is not in homebrew-core; note it as optional
- Sets `CONJURE_HOME` to the formula's prefix via a wrapper script

A GitHub Actions job in this repo (`.github/workflows/release.yml`) should be
extended to automatically open a PR against `mohandoz/homebrew-conjure` after each
release tag, updating the `sha256` and `url` fields.

---

## Modified Components

### `cli/conjure` — MODIFIED
**Changes:**
- Add `cmd_publish` function (~10 lines); dispatch `publish` case
- Add `cmd_publish_skill` function (~15 lines); dispatch `publish-skill` case
- Add `--org-overlay=<url>` flag parsing in `cmd_init`
- Complete `cmd_update --apply` by replacing the stub (lines 174-178) with a call to `lib/merge.sh:merge_with_backup`

**What does NOT change:** dispatch pattern, flag-parsing style, DRY_RUN threading, preflight call pattern. All new commands follow the existing `source lib/mutate.sh` + `bash scripts/<worker>.sh` pattern.

### `scripts/audit-setup.sh` — MODIFIED
**Changes:**
- Add a check for `.claude/.conjure-org-overlay` presence → report URL + SHA (traceability)
- Add version-pinning check: warn if `marketplace.json` version does not match `VERSION`

### `.github/workflows/release.yml` — MODIFIED
**Changes:**
- After creating the GitHub release: invoke `scripts/publish-plugin.sh` to generate the marketplace snippet and commit the updated SHA to `.claude-plugin/marketplace.json` via a bot commit
- Add a step to trigger a PR against `mohandoz/homebrew-conjure` (using `gh` CLI or a `repository_dispatch` event)
- Add a step to trigger the Docker build/push workflow

### `.github/workflows/ci.yml` — MODIFIED
**Changes:**
- Add `lib/merge.sh` to the shellcheck glob (currently `find cli scripts migrations profiles compliance templates/hooks tests -name '*.sh'` — add `lib`)
- Add a Docker build smoke test job (build only, no push, for PRs)

### `.claude-plugin/marketplace.json` — MODIFIED
**Changes:**
- Update `version` field to match `VERSION` on each release
- Add `sha` field pointing to release commit (done by `scripts/publish-plugin.sh`)

---

## Integration Points

### lib/mutate.sh chokepoint
Every new script that writes files MUST source `lib/mutate.sh` and use
`mutate_mkdir` / `mutate_cp` / `mutate_write`. This applies to:
- `scripts/publish-plugin.sh` (writes updated marketplace.json sha field)
- `scripts/apply-org-overlay.sh` (writes `.claude/.conjure-org-overlay` stamp)
- `lib/merge.sh` (writes merged files via `mutate_write`)

Scripts that only READ (publish-skill emitting JSON to stdout; the Homebrew formula)
do not need mutate.sh, but must not call `cp`/`mkdir`/`cat >` directly for
any writes they do make.

### Compliance overlay interface (org overlay reuse)
`scripts/apply-org-overlay.sh` is designed to call an overlay's own `apply.sh`
(same interface as `compliance/<overlay>/apply.sh`). This means org overlays are
not a new interface — they are standard compliance overlays hosted externally and
fetched at runtime. The only novel piece is the git-clone + temp-dir + stamp logic.

### Version stamp chain
```
VERSION file
  └─ read by cli/conjure → CONJURE_VERSION
       └─ stamped to <target>/.claude/.conjure-version on init
            └─ read by cmd_update --check / --apply (base for 3-way merge)
       └─ read by scripts/publish-plugin.sh → written to marketplace.json `version`
       └─ verified by .github/workflows/release.yml (tag must match VERSION)
```

### 3-way merge dependency chain
```
.conjure-version (base ref)
  └─ git tag exists for that version? → git show v<base>:templates/skills/<name>/SKILL.md
       └─ lib/merge.sh:merge_with_backup(current, base, new)
            └─ git merge-file -p current base new
```
This means `cmd_update --apply` requires: (a) git installed (already a preflight dep),
(b) the version tag for the project's pinned version exists in the conjure repo.
Implication: all release tags must be preserved (no force-delete). Add a note to CONTRIBUTING.md.

### Docker image vs CLI commands
The Docker image is purely a delivery channel. It contains the conjure CLI pre-installed
with all dependencies (bash, jq, git, shellcheck, node). No new CLI commands are
Docker-specific. The image's entrypoint is `conjure`; users run:
```
docker run --rm -v $(pwd):/repo mohandoz/conjure init
```

### Homebrew tap vs repo
The tap lives in a separate repository. The `cli/conjure` binary discovers
`CONJURE_HOME` via `$(cd "$(dirname "$0")/.." && pwd)` — this works because
Homebrew's `install` copies the whole tree into the formula prefix, and the
wrapper script sets `PATH` so that `conjure` resolves to the prefix copy.
No changes to `cli/conjure` are needed for Homebrew compatibility.

---

## Suggested Build Order

Dependencies are explicit: each item lists what it unblocks.

### Step 1 — TECH-01: `lib/merge.sh` + `cmd_update --apply`
**Why first:** The 3-way merge is the deepest new logic and the only piece that
touches an existing stub. Implementing it first lets all subsequent testing
(fixtures, publish round-trips) verify it in context. It has no dependencies on
any other DIST item. Once the stub is replaced with a working implementation,
the test suite can add merge regression fixtures.

Dependencies: git (already preflight), lib/mutate.sh (already shipped).
Unblocks: nothing else depends on it, but implementing it clears the tech debt
early before distribution work adds surface area.

### Step 2 — DIST-01: `scripts/publish-plugin.sh` + `cmd_publish`
**Why second:** Requires no new dependencies. Validates that `.claude-plugin/marketplace.json`
is correct before any external distribution happens. Short (one script + one CLI
function). The output is a JSON snippet + an updated marketplace.json SHA — a
low-risk, high-value capability that exercises the release pipeline.

Dependencies: `jq` (already preflight), `lib/mutate.sh` (shipped), `git rev-parse`.
Unblocks: DIST-02 and DIST-03 (both need a correct release artifact with a valid marketplace.json).

### Step 3 — DIST-04: `scripts/publish-skill.sh` + `cmd_publish_skill`
**Why third:** Builds on the same script + CLI-function pattern as DIST-01. Shares
the schema validation logic from `.claude-plugin/SCHEMAS/skill.schema.json`. No
external services, no git-clone, no merge logic needed. Can be done in parallel
with Step 2 if two people are working, but in a solo context it reuses the pattern
learned in Step 2.

Dependencies: `.claude-plugin/SCHEMAS/skill.schema.json` (already shipped), `jq`.
Unblocks: community contribution workflow (PR-based).

### Step 4 — DIST-05: `scripts/apply-org-overlay.sh` + `--org-overlay` flag
**Why fourth:** Introduces the only genuinely new runtime behavior (git-clone in a
temp dir). Should be built after the simpler publish scripts so the pattern is
established and the test fixtures have been used to build confidence. The temp-dir
+cleanup pattern needs careful `set -e` + trap handling — worth a focused pass.

Dependencies: `git clone` (already preflight), `lib/mutate.sh`, compliance overlay
`apply.sh` interface (stable).
Unblocks: org adoption stories; this is the feature that lets teams use private overlays.

### Step 5 — DIST-02: `mohandoz/homebrew-conjure` tap repo
**Why fifth:** Depends on a clean release artifact (Step 2 must have produced a
correct marketplace.json at a tagged version). The tap formula is straightforward
Ruby but lives in a separate repo — it requires a GitHub release to exist with the
correct tarball. Best done after the first successful `conjure publish` run so
the SHA is stable.

Dependencies: GitHub release (from release.yml), `VERSION` matching the tag.
Unblocks: `brew install conjure`.

### Step 6 — DIST-03: `Dockerfile` + `docker.yml` CI
**Why last among DIST items:** Docker is purely delivery; no CLI logic. Building it
last means the final image contains all v0.4.0 features. The Dockerfile is
straightforward (package installs + COPY); the CI job is small. Docker build
failures don't block any other work.

Dependencies: all scripts and CLI changes complete (Steps 1-5) so the image
contains the full v0.4.0 feature set.
Unblocks: `docker run mohandoz/conjure init`.

### Step 7 — Release pipeline wiring (`.github/workflows/release.yml` extension)
**Why last:** This step connects all of the above into a single release trigger.
Extend `release.yml` to: (a) run `scripts/publish-plugin.sh` and commit the SHA
update, (b) trigger the Homebrew tap PR, (c) trigger the Docker build/push. All
three targets must exist before this wiring is useful.

Dependencies: Steps 1-6 all complete; `gh` CLI available in CI (already present for
release creation).
Unblocks: automated release distribution.

---

### Build order summary table

| Step | Work item | New/Modified | Key dep | Unblocks |
|------|-----------|--------------|---------|----------|
| 1 | `lib/merge.sh` + `cmd_update --apply` | NEW + MODIFIED | git, lib/mutate.sh | tech debt cleared |
| 2 | `scripts/publish-plugin.sh` + `cmd_publish` | NEW + MODIFIED | jq, git rev-parse | Steps 5, 6, 7 |
| 3 | `scripts/publish-skill.sh` + `cmd_publish_skill` | NEW + MODIFIED | skill schema | community workflow |
| 4 | `scripts/apply-org-overlay.sh` + `--org-overlay` | NEW + MODIFIED | git clone, mutate.sh | org adoption |
| 5 | `mohandoz/homebrew-conjure` tap | NEW (separate repo) | GitHub release tag | brew install |
| 6 | `Dockerfile` + `docker.yml` | NEW | all CLI complete | docker run |
| 7 | `release.yml` pipeline extension | MODIFIED | Steps 2, 5, 6 | automated release |

---

## Architecture Diagram (v0.4.0 additions highlighted)

```
┌──────────────────────────────────────────────────────────────────────────────┐
│  ENTRYPOINTS                                                                   │
│  ┌──────────────────────────────────────────────────────────────┐             │
│  │  cli/conjure  (dispatcher)                                    │             │
│  │   init / migrate / audit / update / preflight  [existing]     │             │
│  │   publish         [NEW — DIST-01]                             │             │
│  │   publish-skill   [NEW — DIST-04]                             │             │
│  │   init --org-overlay=<url>  [NEW flag — DIST-05]             │             │
│  │   update --apply  [STUB → REAL — TECH-01]                    │             │
│  └──────────────────┬───────────────────────────────────────────┘             │
│                     │ subprocess (bash scripts/*.sh)                          │
├─────────────────────┼──────────────────────────────────────────────────────┤
│  WORKER SCRIPTS                                                               │
│  ┌──────────────────▼──────┐  ┌─────────────────┐  ┌──────────────────────┐  │
│  │ init-project.sh [exist] │  │ publish-plugin  │  │ publish-skill.sh     │  │
│  │ audit-setup.sh  [exist] │  │ .sh [NEW-D01]   │  │ [NEW-D04]            │  │
│  │ preflight.sh    [exist] │  └────────┬────────┘  └──────────┬───────────┘  │
│  └─────────────────────────┘           │ mutate_write          │ stdout JSON  │
│  ┌──────────────────────────┐           │                       │             │
│  │ apply-org-overlay.sh     │           │                       │             │
│  │ [NEW-D05]                │           │                       │             │
│  │  git clone (temp)        │           │                       │             │
│  │  → calls overlay/apply.sh│           │                       │             │
│  └──────────────────────────┘           │                       │             │
├────────────────────────────────────────┼───────────────────────┼─────────────┤
│  SHARED LIB (sourced, not dispatched)  │                       │             │
│  ┌──────────────────────────────┐  ┌───▼──────────────────┐    │             │
│  │ lib/mutate.sh  [existing]    │  │ lib/merge.sh [NEW-T01]│    │             │
│  │ (ALL writes route here)      │  │ merge_skill()         │    │             │
│  └──────────────────────────────┘  │ merge_with_backup()   │    │             │
│  ┌──────────────────────────────┐  └───────────────────────┘    │             │
│  │ lib/cost.sh    [existing]    │                                │             │
│  └──────────────────────────────┘                                │             │
├──────────────────────────────────────────────────────────────────┼─────────────┤
│  DISTRIBUTION CHANNELS (not CLI commands)                         │             │
│  ┌───────────────────────────┐  ┌────────────────┐  ┌────────────▼──────────┐  │
│  │ mohandoz/homebrew-conjure │  │  Dockerfile    │  │ .claude-plugin/       │  │
│  │ [NEW-D02 separate repo]   │  │ [NEW-D03]      │  │ marketplace.json      │  │
│  │  Formula/conjure.rb       │  │  ghcr.io image │  │ (SHA updated by D01)  │  │
│  └───────────────────────────┘  └────────────────┘  └───────────────────────┘  │
├─────────────────────────────────────────────────────────────────────────────────┤
│  CI / RELEASE PIPELINE                                                          │
│  ┌──────────────────────────────────────────────────────────────────────┐       │
│  │ .github/workflows/release.yml [MODIFIED]                             │       │
│  │   push tag → verify VERSION → extract changelog → create GH release  │       │
│  │   → run publish-plugin.sh (SHA commit)                               │       │
│  │   → PR to homebrew-conjure tap [NEW]                                 │       │
│  │   → trigger docker build/push [NEW]                                  │       │
│  └──────────────────────────────────────────────────────────────────────┘       │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

## Anti-Patterns to Avoid

### Anti-Pattern 1: Bypassing lib/mutate.sh in new publish scripts
**What:** Calling `jq --arg ... > file.json` directly in `publish-plugin.sh`.
**Why bad:** Breaks `--dry-run` contract; inconsistent behavior; future callers assume
all writes are DRY_RUN-aware.
**Do this instead:** Read with `jq`, build content string, pass to `mutate_write`.

### Anti-Pattern 2: Bundling git-clone side-effects into lib/ functions
**What:** Putting `git clone` inside a lib/ function so it "can be reused."
**Why bad:** lib/ functions are sourced and must be side-effect-free except for
the explicit mutate_* primitives. Network + subprocess in a sourced lib file is
unpredictable.
**Do this instead:** `git clone` stays in `scripts/apply-org-overlay.sh` (a worker
script). Only the stamp-write goes through lib/mutate.sh.

### Anti-Pattern 3: Interactive merge editor in cmd_update --apply
**What:** Spawning `$VISUAL` or `vimdiff` for merge conflict resolution.
**Why bad:** Breaks Docker/CI usage; not cross-platform (no `vi` on Windows CI).
**Do this instead:** On conflict, print the conflicting file paths with `<<<<<<<`
markers and exit non-zero with a message: "Conflicts in X file(s) — resolve manually,
then run: echo '<version>' > .claude/.conjure-version". No editor spawned.

### Anti-Pattern 4: Separate version tracking for marketplace.json
**What:** Having marketplace.json `version` field managed separately from `VERSION`.
**Why bad:** They drift; release automation breaks; audit's version consistency
check fails.
**Do this instead:** `scripts/publish-plugin.sh` always reads `VERSION` and writes
it to marketplace.json atomically via mutate_write. Single source of truth.

### Anti-Pattern 5: Org overlay stored inside the conjure kit repo
**What:** Adding org-specific overlays as committed directories under `compliance/`.
**Why bad:** Private compliance configs committed to a public OSS repo. Legal/trust
problem. Also defeats the purpose of org overlays.
**Do this instead:** Org overlays are always external repos, fetched at `init` time
via `--org-overlay=<url>`, never stored in conjure itself.

---

## Sources

- `cli/conjure` (full content read this session) — HIGH confidence
- `lib/mutate.sh` (full content read this session) — HIGH confidence
- `.claude-plugin/marketplace.json`, `.claude-plugin/plugin.json` (read this session) — HIGH confidence
- `.planning/PROJECT.md` v0.4.0 requirements (read this session) — HIGH confidence
- `.github/workflows/release.yml`, `ci.yml` (read this session) — HIGH confidence
- Claude Code official docs: "Create and distribute a plugin marketplace" at `code.claude.com/docs/en/plugin-marketplaces` — HIGH confidence (fetched this session; schema verified)
- `anthropics/claude-plugins-official` marketplace.json structure — HIGH confidence (fetched this session)
- Homebrew tap docs at `docs.brew.sh/Taps` and `docs.brew.sh/How-to-Create-and-Maintain-a-Tap` — HIGH confidence
- `git merge-file` documentation at `git-scm.com/docs/git-merge-file` — HIGH confidence

---
*Architecture research for: Conjure v0.4.0 Distribution + Ecosystem integration*
*Researched: 2026-05-25*
