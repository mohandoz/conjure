# Feature Research — v0.4.0 Distribution + Ecosystem

**Domain:** CLI tool distribution + ecosystem integration for Conjure (POSIX bash + Node.js .mjs)
**Researched:** 2026-05-25
**Milestone:** v0.4.0 — Distribution + Ecosystem
**Confidence:** HIGH for Marketplace (official CC docs verified), HIGH for Homebrew (official docs + working examples), MEDIUM for Docker (standard patterns verified, Conjure-specific sizing estimated), MEDIUM for skill publishing (emerging standard), MEDIUM for org overlays (pattern clear, CC-specific docs not found), MEDIUM for 3-way merge (git-merge-file is standard, interactive UX is a design choice)

---

## Category 1: Marketplace Publish (DIST-01)

### Context

Conjure already has a `.claude-plugin/` directory with both `plugin.json` and `marketplace.json` (shipped in v0.2.0). The `marketplace.json` has the correct structure per current Claude Code docs. The gap is: the publish *workflow* is manual — no `conjure` command automates validating and submitting the marketplace entry.

The Claude Code marketplace works as follows (HIGH confidence — verified against official docs 2026-05-25):
- Conjure hosts its own `marketplace.json` in its GitHub repo under `.claude-plugin/marketplace.json`
- Users add it: `/plugin marketplace add mohandoz/conjure`
- Anthropic runs a `claude-community` marketplace; submissions go to `claude.ai/settings/plugins/submit` or `platform.claude.com/plugins/submit`
- `claude plugin validate` is the pre-submission validation command
- Approved plugins are pinned to a commit SHA in `anthropics/claude-plugins-community`

### Table Stakes

| Feature | Why Expected | Complexity | Dependencies |
|---------|--------------|------------|--------------|
| Valid `marketplace.json` with correct schema | CC requires it to pass `/plugin marketplace add`; schemastore.org already has the schema. Conjure's existing file has the right shape. | LOW — already exists, needs version bump to 0.3.0/0.4.0 and any field gaps closed | Existing `.claude-plugin/marketplace.json` (v0.2.0) |
| Valid `plugin.json` with current version | The plugin namespace, skills, agents, and hooks entries must match what actually ships | LOW — exists, needs to reference v0.3.0 skills and hooks templates | Existing `.claude-plugin/plugin.json` |
| `claude plugin validate` passes locally before CI | Standard gate: validate before submit. The CC CLI runs this check on every community submission anyway. | LOW — run `claude plugin validate` in CI as a step | CC ≥2.1.117 installed in CI |
| README install instruction: `/plugin marketplace add mohandoz/conjure` | Users need the single-command install. The marketplace install command is the on-ramp. | LOW — doc edit only | None |
| `conjure` version field stays in sync with git tags | CC pins plugins to commit SHA if no version field; explicit version means users only pull updates on intentional bumps. Conjure should own that bump. | LOW — add to release checklist | Semver tag in GitHub releases |

### Differentiators

| Feature | Value Proposition | Complexity | Dependencies |
|---------|-------------------|------------|--------------|
| `conjure publish-check` command | Runs `claude plugin validate` + checks marketplace.json fields + confirms SHA-pinning is explicit. "Pre-submit checklist in one command." Makes the publish workflow repeatable and reviewable in PRs. | MEDIUM — bash wrapper around `claude plugin validate` + jq field checks | `claude plugin validate` availability in CI |
| CI step that validates the plugin manifest on every PR | Keeps the manifest from drifting. The community submission pipeline runs the same check — pre-empting failures there with a local CI gate is a quality signal. | LOW — add one step to `.github/workflows/ci.yml` | `claude plugin validate` in CI runner |
| Community marketplace submission (anthropics/claude-plugins-community) | Puts Conjure on the default-discoverable list every CC user sees. | LOW (process-work, not code) — submit via `claude.ai/settings/plugins/submit`; `claude plugin validate` must pass first | Valid plugin.json + marketplace.json + DIST-01 CI step |

### Anti-Features

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| Using a reserved marketplace name (`claude-code-marketplace`, `anthropic-plugins`, etc.) | CC blocks these explicitly; would break `/plugin marketplace add` for all users | Use `conjure` as the marketplace name (already set in existing `marketplace.json`) |
| `strict: false` for the marketplace entry | Handing control to the marketplace operator means Conjure's own plugin.json is ignored — not the intent for a first-party publish | Keep `strict: true` (default); Conjure's plugin.json is the authority |
| Embedding raw file contents in marketplace.json | marketplace.json is a catalog, not a content store | All content stays in the plugin directories; marketplace.json references sources |
| Shipping marketplace.json that points to `npm` source | npm requires a published package; adds an unnecessary publish step for a bash CLI | Use `github` source pointing to `mohandoz/conjure` — simpler, no npm account required |

---

## Category 2: Homebrew Formula (DIST-02)

### Context

Homebrew tap = a GitHub repository named `homebrew-<tap>` containing `.rb` formula files. The Conjure formula needs no compilation — it installs a bash script and its templates via `bin.install` and supporting file copies. Pattern is verified and well-established (HIGH confidence).

For a bash script CLI, the formula is minimal:
```ruby
class Conjure < Formula
  desc "Production-grade Claude Code harness init kit"
  homepage "https://github.com/mohandoz/conjure"
  url "https://github.com/mohandoz/conjure/archive/refs/tags/v0.4.0.tar.gz"
  sha256 "..."
  license "MIT"

  def install
    bin.install "cli/conjure"
    # ship templates, profiles, compliance, etc. into a share dir
    share.install "templates", "profiles", "compliance", "scripts", "lib"
  end

  test do
    assert_match "conjure", shell_output("#{bin}/conjure --version 2>&1")
  end
end
```

The tap repository would be `mohandoz/homebrew-conjure` (or `mohandoz/homebrew-tap` if sharing across tools). Users install with `brew install mohandoz/conjure/conjure` or, after `brew tap mohandoz/conjure`, simply `brew install conjure`.

### Table Stakes

| Feature | Why Expected | Complexity | Dependencies |
|---------|--------------|------------|--------------|
| `brew install mohandoz/conjure/conjure` works end-to-end | The primary install experience for macOS devs. Expected for any serious CLI tool targeting devs in 2026. | MEDIUM — create `homebrew-conjure` GitHub repo with a valid `.rb` formula, test locally with `brew install --build-from-source`, ensure `CONJURE_HOME` resolves correctly at runtime | GitHub release with a versioned tarball (`v0.4.0.tar.gz`) and its SHA256 |
| Formula `test do` block that verifies `conjure --version` | Homebrew runs the test block after install; a failing test makes the formula invalid in CI. | LOW — one-liner using `shell_output` | `conjure --version` must output something greppable |
| GitHub release tag (`v0.4.0`) with a tarball | The formula's `url` points to a tarball; Homebrew requires a stable URL with a SHA256. | LOW — tag + GitHub auto-generates the tarball | Semver release on GitHub |
| `CONJURE_HOME` auto-resolves to the Homebrew prefix | The CLI uses `CONJURE_HOME` to locate templates/profiles/scripts. Homebrew installs to `$(brew --prefix)/share/conjure/` — must match. | MEDIUM — change `CONJURE_HOME` defaulting logic: detect if running from Homebrew prefix, fall back to `$(dirname "$0")/../share/conjure` | cli/conjure `CONJURE_HOME` resolution |
| Formula pinned to explicit version (not HEAD) | HEAD formulae are harder to trust; versioned formulae + SHA256 are reproducible. | LOW — don't use `brew install --HEAD`; always release a tag | Semver tags |
| GitHub Actions in the tap repo for formula testing | Homebrew supplies reusable actions (`Homebrew/actions/setup-homebrew`) to validate tap formulae in CI. | LOW — add `.github/workflows/tests.yml` to the tap repo | tap repo exists |

### Differentiators

| Feature | Value Proposition | Complexity | Dependencies |
|---------|-------------------|------------|--------------|
| Linux support via Homebrew on Linux (Linuxbrew) | Homebrew works on Linux; same tap formula installs on Ubuntu CI runners. Broadens the audience for the `brew install` line. | LOW — test with `brew install` on `ubuntu-latest` in GitHub Actions matrix; most bash CLIs work unchanged | Formula must not hardcode `/opt/homebrew` |
| `brew upgrade conjure` just works | Users get new versions by bumping the formula's `url`+`sha256`+`version`. Standard Homebrew update flow. | LOW — part of the release process: update formula on new tag | Semver release + formula update |
| `conjure` auto-detects Homebrew install and skips `CONJURE_HOME` prompt | DX improvement: no env-var setup needed for Homebrew users. Detection: `[ -n "${HOMEBREW_PREFIX}" ]` + existence of `$HOMEBREW_PREFIX/share/conjure`. | LOW | DIST-02 `CONJURE_HOME` fix |

### Anti-Features

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| Trying to get into Homebrew core (`homebrew/core`) | Core requires significant adoption criteria and a lengthy review; tap is faster and fully functional | Use a personal tap (`mohandoz/homebrew-conjure`) initially; submit to core when adoption warrants |
| Hardcoding `/usr/local` or `/opt/homebrew` in scripts | Breaks cross-arch (Intel vs Apple Silicon) and Linux installs | Use `$(brew --prefix)` or the `${HOMEBREW_PREFIX}` env var |
| Installing to `bin` only, leaving templates absent | Conjure is useless without its templates directory | Install to both `bin` and `share/conjure/` with proper `CONJURE_HOME` pointing at the share dir |
| Formula with no `test do` block | Homebrew CI rejects formulae without tests | Add `conjure --version` test at minimum |
| Maintaining the formula in the main conjure repo | Creates confusion between the tool repo and the tap repo | The tap is a separate repo: `mohandoz/homebrew-conjure` |

---

## Category 3: Docker Image (DIST-03)

### Context

Conjure's value proposition for Docker is: provide a single image that has all optional power tools pre-installed (`graphify`, `ast-grep`, `gitleaks`, `repomix`, `jq`, `shellcheck`, Node.js, bash) so teams can run `conjure init` or `conjure audit` in a clean CI environment without a preflight setup step.

The image does NOT need to ship Claude Code itself — Claude Code runs on the developer's machine. The container is a *tooling environment* for running Conjure commands, not a Claude runtime.

Base image options: Alpine (~5MB base, musl libc — some tools may need glibc), Debian slim (~80MB, glibc — broader compatibility), or Ubuntu (~120MB, fully compatible). For a bash CLI with optional native-binary tools (`ast-grep`, `gitleaks`), **Debian slim** is the right choice — Alpine musl breaks several Go/Rust binaries' dynamic linking; Debian slim keeps the image reasonably small (~150-200MB final) without the musl compatibility minefield. (MEDIUM confidence — Alpine vs Debian tradeoff well-established; specific tool compatibility is environment-dependent.)

### Table Stakes

| Feature | Why Expected | Complexity | Dependencies |
|---------|--------------|------------|--------------|
| `docker run ghcr.io/mohandoz/conjure:latest conjure audit .` works | The primary Docker UX. Mount the project with `-v $(pwd):/workspace -w /workspace`. Expected from any CLI tool with a Docker image. | MEDIUM — write Dockerfile, publish to `ghcr.io` via GitHub Actions on release tags | Dockerfile + `.github/workflows/docker-publish.yml` |
| Image published to `ghcr.io/mohandoz/conjure` (GitHub Container Registry) | ghcr.io is free for public repos, authenticated with `GITHUB_TOKEN` (no external secret needed), and has become the standard for OSS tool images. | LOW — standard GitHub Actions step using `docker/build-push-action` | GitHub Actions + GITHUB_TOKEN |
| Multi-arch image (linux/amd64 + linux/arm64) | CI runners are mixed-arch; Apple Silicon dev machines use arm64. A single-arch image silently runs under emulation or fails. | MEDIUM — use `docker buildx` with `--platform linux/amd64,linux/arm64` in the Actions workflow | `docker/setup-qemu-action` + `docker/setup-buildx-action` |
| Version-tagged images (`v0.4.0`) AND `latest` tag | Users need a reproducible tag for pinned CI environments. `latest` is convenient for "just try it." | LOW — `docker/metadata-action` extracts tags from the git tag automatically | GitHub release tags |
| `jq`, `bash`, `shellcheck`, Node.js ≥18 pre-installed | Conjure's hard runtime deps. Missing any of these makes the image non-functional. | LOW — standard Dockerfile `RUN apt-get install` | Dockerfile |
| Image SIZE documented in README | Users decide whether to pull based on size. A 2GB image for a bash CLI is a red flag. | LOW — add `docker pull` + `docker image inspect` to CI and print the size; note in README | CI step |

### Differentiators

| Feature | Value Proposition | Complexity | Dependencies |
|---------|-------------------|------------|--------------|
| Optional power tools included (`ast-grep`, `gitleaks`, `repomix`, `graphify`) | Users who want graph integration or secret scanning get them without any preflight. This is the main reason to have a Docker image at all — it eliminates the "install 5 tools before you start" friction. | MEDIUM — install each tool from GitHub releases or package managers in Dockerfile; pin versions; verify with `ast-grep --version` etc. | Must be pinned versions to prevent image drift |
| `CONJURE_HOME` pre-set correctly in the image | No env-var configuration needed in CI. The image ships a production-ready `CONJURE_HOME`. | LOW — `ENV CONJURE_HOME=/usr/local/share/conjure` in Dockerfile | Dockerfile ENV |
| GitHub Actions example snippet in README | Shows exactly how to use the image in a team's CI: `uses: docker://ghcr.io/mohandoz/conjure:latest`. | LOW — doc edit | Docker image published |
| Non-root user in image | Security best practice; Docker images running as root are flagged by security scanners. | LOW — `RUN useradd -m conjure && USER conjure` | Dockerfile |

### Anti-Features

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| Alpine as the base image | musl libc breaks several pre-built Go/Rust binaries (`ast-grep`, `gitleaks`) that ship glibc-linked binaries; debugging musl compatibility issues is a time sink | Debian slim: ~80MB base, full glibc compatibility, much smaller than Ubuntu full |
| Bundling Claude Code itself in the image | Claude Code authenticates against Anthropic's API; bundling it means managing credentials + a rapidly changing binary. Claude Code is the developer's tool, not the CI tooling. | Image provides only the tool environment; users install CC separately |
| `curl | sh` install steps inside Dockerfile | Violates the kit's own no-curl-pipe safety rule; also produces non-reproducible images | Download from pinned release URLs with SHA256 verification |
| Unbounded `latest` tag without version tags | `latest` mutates; pinned CI uses the version tag | Always publish both; document that pinned CI should use `v0.4.0` not `latest` |
| Huge image (>500MB) | Discourages adoption; signals poor hygiene; slow CI pulls | Use Debian slim + multi-stage build if any compilation is needed; target <200MB |
| Shipping the Docker image without a `--dry-run` test in CI | The image could silently fail if CONJURE_HOME is wrong | Add a CI step: `docker run ... conjure audit --dry-run /tmp/empty` exits 0 |

---

## Category 4: `conjure publish-skill` (DIST-04)

### Context

`conjure publish-skill <name>` takes a skill from the current project's `.claude/skills/<name>/` and contributes it back to the public Conjure kit (by opening a PR or packaging it as a plugin entry). The emerging standard for this is the Agent Skills open standard (Anthropic-originated, now cross-platform: CC, Copilot, Cursor, Codex, Gemini CLI). The pattern: validate locally → format as a standard skill directory → push to a fork → open a PR via `gh pr create`.

### Table Stakes

| Feature | Why Expected | Complexity | Dependencies |
|---------|--------------|------------|--------------|
| Validates skill frontmatter (name, description, size cap) before publishing | If the skill doesn't pass Conjure's own audit, it shouldn't be submitted to the kit. This gate is the minimum quality check. | LOW — reuse existing frontmatter validation from `scripts/audit-setup.sh` | Existing audit frontmatter validator |
| Checks skill size cap (≤200 lines per SKILL.md) | Enforces the kit's own constraint on contributed skills. Prevents bloat. | LOW — reuse size cap check | Existing size cap logic in `lib/` |
| Prints a checklist before submitting | "Does this skill: have a description? stay under 200 lines? avoid PII? use trigger-action format?" A printed checklist makes the contribution decision explicit. | LOW — print and ask for y/n confirmation | None |
| `--dry-run` support | Consistent with the rest of the CLI. Let users see what would happen without mutation. | LOW — honor `DRY_RUN` at the `lib/mutate.sh` level | lib/mutate.sh |

### Differentiators

| Feature | Value Proposition | Complexity | Dependencies |
|---------|-------------------|------------|--------------|
| Auto-opens a GitHub PR via `gh pr create` | Turns "copy files + write a PR" into one command. The `gh` CLI is already present on most dev machines. The PR body is auto-formatted with skill name, description, and test evidence. | MEDIUM — shell: fork check, branch creation, copy skill, `gh pr create` with template body | `gh` CLI available; user must have a fork |
| Packages the skill as a standalone `.claude-plugin`-compatible plugin entry | The contributed skill can also be installed directly via `/plugin install`. Contributes to both the Conjure kit AND the CC plugin ecosystem. | MEDIUM — generate a minimal `plugin.json` wrapping just the skill | DIST-01 plugin format knowledge |
| `conjure publish-skill --to <github-org/repo>` for org-private contribution | Teams with private forks can contribute to their internal overlay repo, not just the public kit. Composes with DIST-05 org overlays. | LOW — parameterize the target repo; default is `mohandoz/conjure` | DIST-05 org overlay concept |
| Cross-platform skill compatibility note (Agent Skills standard) | Skills that follow the Agent Skills open standard work across Claude Code, Copilot, Cursor, and Codex. A publish command that notes this broadens the skill's value. | LOW — doc note in the CLI output and in the PR template | No code change needed |

### Anti-Features

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| Auto-merging contributed skills without review | Even with validation, a contributed skill needs human review — it ships to every user of the kit. | Always PR-based; never auto-merge |
| Publishing skills containing project-specific paths, secrets, or PII | A common mistake when extracting project skills. | Add a PII/path check to the pre-publish validator: scan for email patterns, API key patterns, absolute paths |
| Requiring the user to have a fork before publishing | Creates friction. Many users won't have forked the repo. | Check if a fork exists; offer to create one via `gh repo fork mohandoz/conjure --clone=false` |
| Publishing a skill with `disable-model-invocation: true` without noting it | Skills with model invocation disabled are slash commands, not autonomous skills — fundamentally different use. | Detect this frontmatter field and note it in the PR description so reviewers know what they're getting |

---

## Category 5: Org Overlay System (DIST-05)

### Context

The org overlay pattern: a "base kit" (Conjure's public templates) plus a "private overlay repo" that extends or overrides specific files without forking the entire kit. Standard pattern in config management (Kustomize base+overlay, Drupal config overlay, CircleCI orb overrides). For Conjure, this means: `conjure init --overlay https://github.com/myorg/conjure-overlay` applies the base kit first, then applies the org's private overrides on top.

The overlay repo structure would mirror the base kit's structure under a `patches/` or `overlay/` directory, or simply ship a parallel `.claude/` tree that is merged on top of the base.

### Table Stakes

| Feature | Why Expected | Complexity | Dependencies |
|---------|--------------|------------|--------------|
| `conjure init --overlay <git-url>` applies base kit then overlays org-specific files | The entry point for org overlay use. Without it, teams have to fork Conjure and hand-maintain diverged copies — the common pain point this solves. | HIGH — requires git clone of overlay repo, a merge strategy (overlay wins on conflict), and lib/mutate.sh routing | lib/mutate.sh; git available in preflight |
| Overlay files win over base files (overlay takes precedence) | Standard convention: base provides defaults, overlay provides org-specific overrides. Matches Kustomize semantics that developers already understand. | MEDIUM — merge order: base first, overlay second, overlay wins on conflict | DIST-05 merge strategy |
| `conjure audit` checks for overlay presence and notes it in the report | Teams need to know which overlays are active. Audit transparency is a Conjure core value. | LOW — check for `.claude/.conjure-overlay` marker file and print in audit output | Existing audit-setup.sh |
| Overlay repo can be private | Orgs keep their HIPAA/PCI-specific rules private. The overlay git clone must work with SSH keys or GITHUB_TOKEN. | LOW — `git clone` already supports SSH and HTTPS with token auth; document the pattern | No code change; documentation only |
| `conjure refresh-overlay` re-pulls and re-applies the overlay | Keeps the org overlay fresh as the overlay repo evolves. Follows the same backup-before-mutate pattern. | MEDIUM — re-clone overlay, re-apply files, honor DRY_RUN | lib/mutate.sh; backup logic |

### Differentiators

| Feature | Value Proposition | Complexity | Dependencies |
|---------|-------------------|------------|--------------|
| `.claude/.conjure-overlay` marker file recording the overlay URL + pinned SHA | Makes the applied overlay auditable and reproducible. Teams can see exactly which overlay version is in use. Re-running `conjure refresh-overlay` from the marker is deterministic. | LOW — write the marker during `init --overlay`; read it in `refresh-overlay` and `audit` | lib/mutate.sh |
| Overlay can reference any git ref (`--overlay-ref v1.2.0`) | Teams pin to a tested overlay version, not just `main`. Follows the same philosophy as per-project `.conjure-version` pinning. | LOW — pass `--depth 1 --branch <ref>` to `git clone` | DIST-05 init flag |
| `conjure publish-skill --to <overlay-repo>` integration | Skills extracted from a project can be contributed to the org overlay, not just the public kit. Closes the contribution loop for private orgs. | LOW — DIST-04's `--to` flag; no new code | DIST-04 |
| Overlay-aware compliance overlays | An org's private overlay can extend a compliance overlay (e.g., HIPAA base from Conjure + org-specific addendum from the overlay repo). | MEDIUM — overlay files are deep-merged, not just top-level replaced; compliance files require append, not clobber semantics | Merge strategy must distinguish append vs replace |

### Anti-Features

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| Forking Conjure as the "overlay" strategy | Teams that fork must hand-maintain divergence. This is the problem the overlay system solves. | Document: fork = maintenance burden; overlay = stay on upstream + customize |
| Overlay silently clobbers user modifications | If the user has edited a base file post-init, a naive `refresh-overlay` destroys their work | Use the same backup-before-mutate + 3-way merge strategy as TECH-01 for overlay refreshes |
| Requiring the overlay repo to mirror Conjure's entire structure | If the overlay must replicate every directory, small orgs won't adopt it | Overlay only needs to include files it wants to change; missing files fall through to the base |
| Auto-pulling overlays on every `conjure audit` | Silent mutations during audit break the "audit is read-only" contract | Overlay re-application is only triggered by explicit `conjure refresh-overlay` or `init --overlay` |
| Global overlay config (affects all projects on the machine) | Global state = non-reproducible environments | Overlay config is per-project, stored in `.claude/.conjure-overlay` |

---

## Category 6: 3-Way Merge for `cmd_update --apply` (TECH-01)

### Context

`conjure update --check` already works (shows which template files have diverged). The `--apply` stub at `cli/conjure:174` prints "not yet implemented." The production implementation needs a 3-way merge: `git merge-file <current-project-file> <original-template-at-pinned-version> <new-template>`. This preserves user modifications to project files while applying upstream template changes — the canonical merge algorithm.

`git merge-file` is a standard POSIX-available command (comes with git, no extra install). It writes conflict markers (`<<<<<<<`, `=======`, `>>>>>>>`) for unresolvable conflicts, which the user then resolves manually. Exit code 0 = clean merge; exit code > 0 = conflicts present. (HIGH confidence — standard git command, well-documented.)

The key challenge: Conjure must have access to the template file at the *pinned version* (the "common ancestor"). This means storing a snapshot of the original templates at init/update time, or using git history.

### Table Stakes

| Feature | Why Expected | Complexity | Dependencies |
|---------|--------------|------------|--------------|
| `conjure update --apply` actually runs a merge instead of printing "not yet implemented" | This is an active stub (cli/conjure:174). Any user running `conjure update --apply` today gets a TODO message. It must be replaced with a real implementation. | HIGH — implement the full 3-way merge loop for each changed file | git available (preflight dep) |
| Preserves user modifications to project files | The fundamental promise of 3-way merge: if the user edited a SKILL.md and the template also changed, both edits should survive if they touch different lines. A simple file copy destroys user work. | HIGH — requires the "base" snapshot (original template at pinned version); git merge-file handles the actual merge math | Base snapshot availability (see below) |
| Backup-before-mutate before any merge write | Consistent with every other Conjure mutation. If the merge result is wrong, the user can restore from backup. | LOW — call `lib/mutate.sh` backup helper before writing the merged file | lib/mutate.sh |
| Conflict markers left in place for manual resolution | `git merge-file` outputs conflict markers on unresolvable conflicts (exit > 0). These should be left in the file for the user to resolve, not silently discarded or auto-resolved. | LOW — check `git merge-file` exit code; if > 0, print "conflicts in <file>, resolve manually" | git merge-file behavior |
| `--dry-run` shows which files would be merged without writing | Consistent with the rest of the CLI. Users should be able to preview the merge plan. | LOW — honor `DRY_RUN` | lib/mutate.sh |
| Base snapshot stored at `.claude/.conjure-templates-<version>/` | The 3-way merge requires the original template as the "common ancestor." The cleanest solution: when `conjure init` or a previous `conjure update --apply` runs, snapshot the applied templates into `.claude/.conjure-templates-<version>/`. | HIGH — this is the architectural decision that unblocks 3-way merge; without the base snapshot, the merge degrades to a 2-way diff (which loses user modifications) | Design choice: snapshot at init time |

### Differentiators

| Feature | Value Proposition | Complexity | Dependencies |
|---------|-------------------|------------|--------------|
| Per-file merge report: "clean / conflicted / skipped" | Users see exactly what happened to each file after `--apply`. Clean merges are applied silently; conflicts are listed with file paths. | LOW — collect git merge-file exit codes per file; print a summary table | TECH-01 implementation |
| `conjure update --apply --file <name>` to merge one file at a time | For large harnesses with many conflicts, users may want to merge one file at a time rather than all at once. | LOW — add a `--file` flag to the loop in cmd_update | TECH-01 implementation |
| Auto-resolve strategy for pure additions (new sections in template, file untouched by user) | If the user has not modified a file at all since init, no merge is needed — just copy the new template. This is the common case and should be handled without invoking merge-file. | LOW — `diff -q <project-file> <base-snapshot>` first; if identical, just copy new template | Snapshot comparison |

### Anti-Features

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| Using an interactive TUI merge tool (vimdiff, meld) | Not available in CI or Docker; breaks the "one command" principle; requires user to have a merge tool installed | `git merge-file` writes conflict markers in the file; user resolves with their editor of choice |
| Auto-resolving conflicts by always taking "ours" or "theirs" | Silently discards either user work or upstream improvements | Leave conflict markers for manual resolution; auto-resolve only when one side is unmodified |
| 2-way diff without a base snapshot | A simple diff between current project file and new template treats all user modifications as "conflicts" — every user edit is a conflict | 3-way merge requires a base; store the base snapshot at init time |
| Pulling base snapshots from git history | Requires the kit to be a git repo and the project to track the kit's history — fragile, non-portable | Store base snapshots as literal files in `.claude/.conjure-templates-<version>/` at init time |
| Running merge outside lib/mutate.sh | Any write that bypasses the chokepoint breaks DRY_RUN enforcement and the backup guarantee | Route the merged file write through `lib/mutate.sh` copy_into |

---

## Category 7: Nyquist Compliance Pass (TECH-02)

### Context

"Nyquist compliance" in the GSD framework refers to a test coverage standard: every logical branch/function in phases 01, 02, 04, 05, 06, 07 must have corresponding test coverage in `tests/run.sh`. The name draws from the Nyquist sampling theorem — sample at twice the rate to reconstruct the signal faithfully. In practice: at least one test per distinct code path. This is a code-quality debt clearance task, not a new feature.

### Table Stakes

| Feature | Why Expected | Complexity | Dependencies |
|---------|--------------|------------|--------------|
| All code paths in phases 01, 02, 04, 05, 06, 07 have at least one test assertion | The v0.3.0 milestone shipped 200 assertions but did not achieve full coverage of earlier phases. TECH-02 closes that gap. | HIGH — requires auditing each phase script for untested paths, then adding assertions | 200-assertion test suite from v0.3.0 |
| CI gate fails if a covered path loses its test | New tests for previously uncovered paths must be protected from accidental deletion | MEDIUM — no special infra needed if tests are in `tests/run.sh`; CI already runs it | Existing CI |

### Differentiators

| Feature | Value Proposition | Complexity | Dependencies |
|---------|-------------------|------------|--------------|
| Coverage map comment in `tests/run.sh` | A short comment block listing which CLI functions are tested enables future contributors to find gaps | LOW — doc edit | None |

### Anti-Features

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| 100% line coverage as the goal | Chasing line coverage metrics leads to testing implementation details, not behavior | Cover logical branches (happy path + each error path); stop at "can a regression hide from this suite?" |
| Adding a coverage tool (bashcov, kcov) | These have CI setup overhead and may not be worth it for a bash CLI at this scale | Hand-audit the scripts; write targeted regression assertions; the existing `pass`/`fail` helpers are sufficient |

---

## Category 8: Windows CI Confirmation (TECH-03)

### Context

Conjure's Node.js `.mjs` hooks are the Windows story (bash CLI requires git-bash/WSL on Windows). TECH-03 is about confirming that the CI matrix actually exercises the `.mjs` hook path on `windows-latest` GitHub Actions runners. On Windows runners, bash is Git Bash (bundled with Git for Windows) — NOT WSL. WSL requires additional setup on GitHub-hosted runners and is not natively available. (HIGH confidence — verified against GitHub Actions documentation and community discussions.)

### Table Stakes

| Feature | Why Expected | Complexity | Dependencies |
|---------|--------------|------------|--------------|
| GitHub Actions matrix includes `windows-latest` | The v0.3.0 STACK.md called for a Windows matrix entry; TECH-03 confirms it actually exists and passes. | LOW — add `windows-latest` to the OS matrix in `.github/workflows/ci.yml` | CI YAML |
| `.mjs` hook smoke test passes on `windows-latest` | A single `node hook.mjs < test-input.json` assertion on Windows confirms the hook's cross-platform claim. | LOW — add one test in `tests/run.sh` that invokes the hook via `node` on all platforms | `.mjs` hooks in templates/ |
| README documents Windows requirements (git-bash or WSL for bash CLI; native Node for hooks) | Users on Windows need to know what to install. | LOW — doc edit | None |

### Differentiators

None. TECH-03 is a validation task, not a feature. Get it green and document it; move on.

### Anti-Features

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| WSL in GitHub Actions CI | GitHub-hosted runners don't support WSL natively; requires the `ubuntu/wsl-actions-example` setup which adds ~3-5 min to CI | Test on `ubuntu-latest` for Linux; `windows-latest` with Git Bash for the Windows + git-bash scenario |
| Testing bash CLI on native Windows PowerShell | The bash CLI doesn't run under PowerShell without git-bash. Don't claim it does. | Document the git-bash/WSL requirement; test only the `.mjs` hooks on native Windows |

---

## Feature Dependencies (Cross-Category)

```
[GitHub release with semver tag]
    └──required-by──> [DIST-02 Homebrew formula url + sha256]
    └──required-by──> [DIST-03 Docker image version tag]
    └──required-by──> [DIST-01 plugin.json version bump]

[Valid plugin.json + marketplace.json (DIST-01)]
    └──required-by──> [DIST-04 publish-skill creates a plugin entry]
    └──enables──────> [Claude community marketplace submission]

[lib/mutate.sh + DRY_RUN (v0.3.0)]
    └──required-by──> [TECH-01 3-way merge writes through the chokepoint]
    └──required-by──> [DIST-05 overlay apply/refresh writes through the chokepoint]

[Base snapshot at .claude/.conjure-templates-<version>/]
    └──required-by──> [TECH-01 3-way merge "common ancestor"]
    └──written-by───> [conjure init] (store snapshot at init time)
    └──written-by───> [conjure update --apply] (update snapshot after apply)

[DIST-04 conjure publish-skill --to flag]
    └──composes-with──> [DIST-05 org overlay: contribute skill to private overlay repo]

[TECH-02 Nyquist coverage pass]
    └──validates───> [DIST-05 overlay logic]
    └──validates───> [TECH-01 merge logic]
    └──validates───> [DIST-04 publish-skill validation]

[TECH-03 Windows CI confirmation]
    └──confirms────> [DIST-03 Docker multi-arch image includes arm64]
    └──confirms────> [.mjs hooks work cross-platform]
```

---

## MVP Definition

The minimum v0.4.0 that satisfies "installable and shareable through every standard channel" while clearing tech debt:

### Must Ship (v0.4.0)

1. **DIST-01 table stakes** — valid marketplace.json + plugin.json at v0.4.0 version, `claude plugin validate` in CI. The plugin manifest already exists; this is a version bump + CI step + community submission.
2. **DIST-02 Homebrew tap** — `brew install mohandoz/conjure/conjure` works. A separate `homebrew-conjure` repo with a minimal formula. Requires `CONJURE_HOME` fix and a GitHub release tarball.
3. **DIST-03 Docker image** — `docker run ghcr.io/mohandoz/conjure:latest conjure audit .` works. Debian slim base, multi-arch, all tools pre-installed, published to ghcr.io on release.
4. **TECH-01 3-way merge** — `conjure update --apply` does a real merge instead of the stub. Requires base snapshot design + `git merge-file` loop. The highest-complexity item; unblocks "keep harness healthy" core value.
5. **TECH-03 Windows CI** — `windows-latest` matrix entry + `.mjs` hook smoke test. Low-effort, closes the cross-platform claim.

### Should Ship (v0.4.0, if capacity allows)

6. **DIST-04 `conjure publish-skill`** — validate + checklist + optional `gh pr create`. Medium complexity. Valuable for ecosystem flywheel.
7. **DIST-05 `conjure init --overlay`** — base + overlay merge on init, `.conjure-overlay` marker, `refresh-overlay`. High value for enterprise teams.

### Can Defer (v0.4.x or v0.5.0)

- TECH-02 Nyquist pass — quality debt; important but not user-facing. Can be a v0.4.x followup.
- `conjure publish-check` CI command — nice-to-have; CI already runs `claude plugin validate`.
- Community marketplace submission — process work; can happen asynchronously after DIST-01 ships.

---

## Sources

- [Claude Code — Create and distribute a plugin marketplace](https://code.claude.com/docs/en/plugin-marketplaces) — HIGH. Official docs, verified 2026-05-25. Full schema for marketplace.json, plugin sources, strict mode, community submission workflow.
- [Claude Code — Create plugins](https://code.claude.com/docs/en/plugins) — HIGH. Official docs. plugin.json schema, directory structure, `claude plugin validate`, `--plugin-dir`, community submission via `claude.ai/settings/plugins/submit`.
- [Homebrew — How to Create and Maintain a Tap](https://docs.brew.sh/How-to-Create-and-Maintain-a-Tap) — HIGH. Official docs. Tap creation, `brew tap-new`, formula structure, GitHub Actions integration.
- [Homebrew formula for bash script — orgs/Homebrew/discussions/5388](https://github.com/orgs/Homebrew/discussions/5388) — HIGH. Working example: `bin.install "scriptname"` for script-only tools. `test do` using `assert_match`.
- [GitHub Docs — Publishing Docker images](https://docs.github.com/actions/guides/publishing-docker-images) — HIGH. GITHUB_TOKEN auth for ghcr.io, `docker/build-push-action`, version tagging.
- [Alpine vs Distroless vs Scratch — Mathieu Benoit](https://medium.com/google-cloud/alpine-distroless-or-scratch-caac35250e0b) — MEDIUM. musl libc compatibility risks with Alpine for Go/Rust binaries.
- [Git — git-merge-file documentation](https://git-scm.com/docs/git-merge-file) — HIGH. 3-way merge algorithm, exit codes, conflict markers, `-L` labels, `-p` stdout output.
- [Kustomize base and overlay inheritance patterns](https://oneuptime.com/blog/post/2026-02-09-kustomize-base-overlay-inheritance/view) — MEDIUM. Base+overlay pattern, overlay wins on conflict, flat hierarchy recommendation.
- [GitHub — runkids/skillshare](https://github.com/runkids/skillshare) — MEDIUM. Cross-tool skill sharing pattern, one-command sync.
- [GitHub Actions on Windows — community discussion](https://github.com/orgs/community/discussions/25038) — HIGH. Bash on Windows runners is Git Bash (not WSL); WSL requires separate setup.
- Conjure internal: `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `cli/conjure:132-178` (cmd_update stub), `planning/ROADMAP.md`, `.planning/PROJECT.md` — HIGH (read directly this session).

---
*Feature research for: Conjure v0.4.0 Distribution + Ecosystem*
*Researched: 2026-05-25*
