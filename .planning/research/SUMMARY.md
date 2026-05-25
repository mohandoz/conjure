# Research Summary — Conjure v0.4.0 Distribution + Ecosystem

**Project:** Conjure
**Domain:** CLI tool distribution, ecosystem integration, and 3-way merge for a POSIX bash + Node.js init kit
**Researched:** 2026-05-25
**Confidence:** HIGH (official sources for all distribution channels; codebase read directly)

---

## Executive Summary

Conjure v0.4.0 adds seven capabilities across two tracks: distribution (Marketplace,
Homebrew, Docker, publish-skill, org overlays) and tech debt (3-way merge, Windows CI).
The distribution track opens install channels for macOS, Linux, CI environments, and
enterprise teams with private overlays. The tech debt track completes the `cmd_update
--apply` stub that has been inert since it was scaffolded, and confirms the cross-platform
claim with an actual Windows CI matrix entry. Together, the milestone makes Conjure
installable through every standard channel and keeps the "harness stays healthy" core
value intact.

The recommended approach is to sequence the work depth-first by dependency: 3-way merge
first (unblocks update correctness), then Marketplace publish (validates the release
artifact), then the two ecosystem commands (publish-skill, org overlays), then delivery
channels (Homebrew, Docker), and finally release-pipeline wiring. No new runtime
dependencies are introduced — the stack stays bash + Node stdlib + jq + git + shellcheck.
Docker uses a Debian-slim base (not Alpine) to avoid musl libc incompatibilities with
optional Go/Rust power tools. The Homebrew formula lives in a separate tap repo
(`mohandoz/homebrew-conjure`) to keep separation clean.

The dominant risk is supply-chain trust: Conjure distributes AI configuration that
Claude executes as instructions. Skills published through any channel can contain
prompt-injection payloads. A static egress scan (grep for `curl`/`wget`/network calls
in `run:` blocks) must be a CI gate across all distribution paths before any channel
opens. The second risk is the mutate.sh bypass: all four new mutation paths (overlay
apply, merge apply, publish-skill, publish-plugin) must route writes through
`lib/mutate.sh` or the `--dry-run` guarantee silently regresses.

---

## Stack Additions

| Tool / Format | Version | Purpose | Why |
|---------------|---------|---------|-----|
| `debian:bookworm-slim` | current | Docker base image | musl/Alpine breaks glibc-linked Go/Rust optional tools; Debian slim keeps image ~150 MB |
| `koalaman/shellcheck:stable` | stable tag | Multi-stage Docker shellcheck copy | Statically linked; `COPY --from=koalaman/shellcheck:stable` is the official pattern |
| `node:20-alpine` | 20 LTS | Docker Node layer (STACK.md sketch; bash added via apk) | Node 20 LTS; migrate to 22 before EOL 2026-04-30 |
| `.claude-plugin/marketplace.json` | Claude Code schema | Marketplace publish (DIST-01) | Already present at v0.2.0; needs `plugins[]` array + version bump to 0.4.0 |
| `mislav/bump-homebrew-formula-action` | v3 | Automate Homebrew SHA256 on release | Cross-repo write to tap; needs `HOMEBREW_TAP_TOKEN` with `repo` + `workflow` scopes |
| `git merge-file` | git >=2.x (already preflight dep) | 3-way merge for `cmd_update --apply` | Git builtin; `--diff3` conflict style; exit 0 = clean, >0 = N conflicts |
| `gh` (GitHub CLI) | system advisory dep | `conjure publish-skill` opens PR | Already in contributor workflow; print fallback if absent |

**No new runtime npm dependencies.** `dependencies: {}` stays empty. Base stack
(bash + Node stdlib + jq + shellcheck + git) is unchanged.

---

## Feature Table Stakes

### DIST-01 — Marketplace Publish
- Valid `marketplace.json` with `plugins[]` array, `github` source, SHA-pinned version
- `claude plugin validate` passes locally and in CI on every PR
- Version field (`marketplace.json` + `plugin.json`) kept in sync with `VERSION` — CI gate required
- Community marketplace submission to `anthropics/claude-plugins-community` (process work, can be async)

### DIST-02 — Homebrew Tap
- `brew install mohandoz/conjure/conjure` works end-to-end
- `CONJURE_HOME` resolves to `$(brew --prefix)/share/conjure/` automatically
- `test do` block: `conjure --version` exits 0 with greppable output
- Formula pinned to tagged tarball URL + SHA256 (never branch HEAD)
- `bump-homebrew-formula-action` fires on every release to auto-update SHA256 in tap repo

### DIST-03 — Docker Image
- `docker run ghcr.io/mohandoz/conjure:v0.4.0 conjure audit .` works with `-v $(pwd):/work`
- Non-root user (`USER conjure`, UID 1000); host files stay user-owned after volume-mount writes
- Published to `ghcr.io` via `GITHUB_TOKEN`; semantic version tags + `latest`
- Multi-arch: `linux/amd64` + `linux/arm64`; baseline image ≤200 MB
- README shows `$(pwd)` / `${PWD}` / `%CD%` forms for bash/PowerShell/cmd

### DIST-04 — `conjure publish-skill`
- Validates frontmatter schema + size cap (≤200 lines) before submitting — reuses existing audit logic
- Static egress scan: fail publish if skill contains `curl`/`wget`/network calls in `run:` blocks
- SHA-pins the published commit; PR-based contribution only (never auto-merge)
- Degrades gracefully without `gh` (print manual PR steps)

### DIST-05 — Org Overlay
- `conjure init --overlay <git-url>` applies base kit then org overlay via temp clone
- All writes through `lib/mutate.sh`; backup-before-mutate on conflicts
- `.claude/.conjure-org-overlay` marker records URL + clone SHA for audit traceability
- Overlay URL stored credential-free; authentication via user's existing git credential store
- `conjure refresh-overlay` re-pulls and re-applies; `conjure audit` detects and reports overlay presence

### TECH-01 — 3-Way Merge (`cmd_update --apply`)
- Replaces stub at `cli/conjure:174` with `lib/merge.sh` using `git merge-file --diff3`
- Base snapshot stored at `.claude/.conjure-templates-<version>/` written at `conjure init` time
- Conflicts written to sidecar (`.conjure-conflict-<file>`), never into the live file
- Generated files (`.conjure-version`, `settings.json`) always take upstream; user-owned files (`CLAUDE.md`, skills) get 3-way merge
- `conjure audit` must detect `^<<<<<<<` conflict markers and fail with specific error

### TECH-03 — Windows CI
- `windows-latest` matrix entry in CI: `shell: bash` for CLI path, `shell: pwsh` for `.mjs` hooks
- `.mjs` hooks use `path.join()` for all file paths (no string-concat `/` separators)
- `compatibility.platforms` stays `["darwin","linux","wsl"]` — no `"windows"` until a PowerShell entrypoint exists

---

## Phase Order Recommendation

Ordering logic: dependency-first, then complexity-first within independent groups.
TECH-02 (Nyquist) and TECH-01 (merge) precede distribution to keep the codebase
correct and covered before new surface area is added. DIST-01 unlocks DIST-02/03.
DIST-04/05 share the mutate.sh discipline. Release pipeline wiring is last.

| Phase | Feature | Rationale |
|-------|---------|-----------|
| **1** | TECH-02 Nyquist compliance backfill | Do first: write VALIDATION.md files in-context, not bulk post-hoc. Closes coverage gaps before new surface area arrives. Pitfall I-2 says deferring this produces shallow tests. |
| **2** | TECH-01 `lib/merge.sh` + `cmd_update --apply` | Deepest new logic; touches the existing stub; no distribution deps. Clears most-requested tech debt early. Base snapshot design must happen here. |
| **3** | DIST-01 Marketplace publish | Validates the release artifact. Correct `marketplace.json` + SHA is a prerequisite for Homebrew SHA pinning and Docker version tags. Low code complexity. |
| **4** | DIST-04 `conjure publish-skill` | Builds on DIST-01 plugin format; same script + CLI-function pattern; no external services. Validates ecosystem contribution flywheel. |
| **5** | DIST-05 Org overlay | Introduces git-clone-in-temp-dir (the one novel runtime behavior). Should follow simpler publish scripts so the pattern is established. Needs TECH-01 (update --apply) for overlay version coordination. |
| **6** | DIST-02 Homebrew tap | Depends on a clean tagged release artifact (Phase 3). Separate repo setup; straight-line formula work. Run `brew search conjure` before writing formula. |
| **7** | DIST-03 Docker image + TECH-03 Windows CI | Docker is delivery-only; image contains full v0.4.0 feature set. Windows CI matrix entry is low-effort and validates the Docker multi-arch claim simultaneously. |
| **8** | Release pipeline wiring (`release.yml` extension) | Connects Phases 3, 6, 7 into a single release trigger. Must come after all targets exist. |

**Can defer to v0.4.x:** TECH-02 Nyquist pass (if capacity forces a cut, but this
risks shallow tests); community marketplace submission (process work, async).

---

## Watch Out For

### 1. Supply-chain prompt injection (DS-1, S-2) — CRITICAL
Skills distributed through any channel are Claude instructions, not inert code. A
malicious `run:` block can exfiltrate credentials silently during normal AI-assisted
work. Research (Mitiga, JFrog 2026) shows 13%+ of public AI skill marketplaces contain
active vulnerabilities. **Prevention:** static egress CI scan (`grep` for
`curl`/`wget`/`fetch`/`$HOME/.ssh`/`process.env` in `run:` blocks) must be green before
any distribution channel opens. PR review required for all public-kit skill contributions.
Signed build provenance on every release.

### 2. `lib/mutate.sh` bypass breaks `--dry-run` (I-1) — CRITICAL
All four new mutation paths (overlay apply, merge apply, publish-skill, publish-plugin)
must route writes through `lib/mutate.sh`. Raw `cp`/`>`/`>>` calls silently skip the
`--dry-run` guard and backup guarantee. **Prevention:** extend the existing raw-write CI
guard (`grep -rn 'cp \|^>\|>> ' scripts/ cli/`) to cover all new v0.4.0 scripts on day
one before writing any distribution script.

### 3. Conflict markers written into live CLAUDE.md (T-1) — HIGH
`git merge-file` exits non-zero AND writes conflict markers into the output file. If the
calling script passes that merged file directly to the project, Claude Code loads
`<<<<<<< HEAD` as live instructions — undefined behavior. **Prevention:** on non-zero
`merge-file` exit, write to a `.conjure-conflict-<file>` sidecar and leave the original
untouched. `conjure audit` must grep for `^<<<<<<<` and fail with a specific error code.

### 4. `marketplace.json` version field left stale (M-1) — HIGH
The current manifests are at v0.2.0; the repo is at v0.3.0. If version fields stay
stale, Claude Code shows no update notification to existing plugin users — silent split.
**Prevention:** CI version-consistency check (grep `CONJURE_VERSION` vs `version` in
both manifests) gated on every release commit. Include both files in release checklist.

### 5. Docker image runs as root — host files owned by root (D-1) — HIGH
A root-running container writing into `-v $(pwd):/work` creates root-owned files the
user cannot delete or `git add`. **Prevention:** `USER conjure` (UID 1000) in Dockerfile;
document `--user $(id -u):$(id -g)` in README Docker usage; smoke-test file UID in CI.

---

## Open Questions

| Question | Impact | How to Resolve |
|----------|--------|----------------|
| **Docker base: STACK.md suggests `node:20-alpine` + bash; FEATURES.md recommends `debian:bookworm-slim`** | Alpine musl breaks optional Go/Rust tools (ast-grep, gitleaks); Debian slim avoids this | Decide before writing Dockerfile. Recommended: Debian-slim baseline; add `conjure:full` tag for optional tools later |
| **Merge base source for non-git installs (Homebrew, tarball)** | Without `.conjure-templates-<version>/` snapshot, TECH-01 degrades to 2-way diff | Decide: (a) always snapshot at init time (recommended, v0.4.0), or (b) document limitation for non-git installs |
| **`brew search conjure` collision check** | If taken in homebrew-core, formula must use `conjure-kit` or `conjure-claude` | Run `brew search conjure` before Phase 6 formula work |
| **Overlay version compatibility contract** | Org overlays may break on base-kit upgrade if schema drifts | Define `compatible-kit-version` in overlay manifest during DIST-05 before first overlay is published |
| **Community marketplace submission timing** | DIST-01 code work covers self-hosted use; Anthropic catalog submission is process-only | Can be async with Phase 3; decide whether it's in v0.4.0 scope or post-ship |

---

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | All additions verified against official docs; base stack unchanged |
| Features | HIGH (DIST-01/02/03, TECH-01/03) / MEDIUM (DIST-04/05) | Marketplace, Homebrew, Docker are well-established. publish-skill and org overlay have no Claude Code-native prior art. |
| Architecture | HIGH | Codebase read directly; chokepoints (mutate.sh, dispatch pattern) confirmed; build order verified against dependency graph |
| Pitfalls | HIGH (code + official sources) / MEDIUM (supply-chain patterns) | Supply-chain pitfalls sourced from security research (Mitiga, JFrog, Snyk), not Anthropic docs |

**Overall confidence:** HIGH for must-ship items (DIST-01/02/03, TECH-01/03). MEDIUM
for DIST-04/05 (emerging patterns with no Claude Code-native reference implementations).

---

## Sources

### Primary (HIGH)
- Claude Code official docs: plugin marketplaces, plugin schema, `claude plugin validate` — verified 2026-05-25
- Homebrew: Tap docs, Formula Cookbook, `bump-formula-pr` — official docs
- Docker: building best practices, `ghcr.io` publish workflow, multi-stage builds — official docs
- `git merge-file` documentation — git-scm.com official
- Conjure working tree: `cli/conjure`, `lib/mutate.sh`, `.claude-plugin/*.json`, `.github/workflows/`, `tests/run.sh` — read directly this session

### Secondary (MEDIUM)
- `mislav/bump-homebrew-formula-action` v3 — well-documented ecosystem tooling
- Mitiga / JFrog / Snyk / NVIDIA: AI skill supply-chain attack research 2026 — independent security research
- GitHub Actions Windows runner behavior — community discussion + confirmed runner docs
- Kustomize base+overlay as analog for DIST-05 — no Claude Code-native prior art; analog only

---
*Research completed: 2026-05-25*
*Ready for roadmap: yes*
