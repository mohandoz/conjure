# Requirements — Conjure v0.4.0 Distribution + Ecosystem

**Milestone:** v0.4.0
**Status:** Active
**Last updated:** 2026-05-25

---

## v1 Requirements

### Marketplace Publish (DIST-01)

- [x] **MKTPL-01**: User can run `conjure publish` to update `.claude-plugin/marketplace.json` with the current release SHA and validate the manifest locally
- [x] **MKTPL-02**: CI validates that `version` fields in `marketplace.json` and `plugin.json` match the `VERSION` file on every PR
- [x] **MKTPL-03**: CI runs `claude plugin validate .` on every PR and fails on schema errors
- [x] **MKTPL-04**: User can submit the plugin to the community catalog (`anthropics/claude-plugins-community`) via guided `conjure publish --submit` output (process documentation + checklist; automation not required)

### 3-Way Merge — `cmd_update --apply` (TECH-01)

- [x] **MERGE-01**: User can run `conjure update --apply` and have changed template files merged into their project using `git merge-file --diff3` (replaces stub at `cli/conjure:174`)
- [x] **MERGE-02**: `conjure init` writes a `.claude/.conjure-templates-<version>/` base snapshot so the merge ancestor is always available for future `conjure update --apply` runs
- [x] **MERGE-03**: On merge conflict, `conjure update --apply` writes the conflicted content to a `.conjure-conflict-<filename>` sidecar and leaves the original file untouched
- [x] **MERGE-04**: Generated files (`.conjure-version`, `settings.json`) always accept upstream unconditionally; only user-owned files (`CLAUDE.md`, skills, agents) go through 3-way merge
- [x] **MERGE-05**: `conjure audit` detects `^<<<<<<<` conflict markers in any harness file and exits non-zero with a specific error message

### Skill Publishing (DIST-04)

- [x] **SKILL-01**: User can run `conjure publish-skill <name>` to validate a project skill against frontmatter schema, size cap (≤200 lines), and a static egress scan before submitting
- [x] **SKILL-02**: `conjure publish-skill` opens a pull request against the public kit via `gh pr create`; if `gh` is absent, prints the manual PR URL and checklist instead
- [x] **SKILL-03**: Published skill commit is SHA-pinned; branch-HEAD references are rejected with an error
- [x] **SKILL-04**: User can run `conjure publish-skill <name> --to <org/repo>` to contribute to a private kit or org overlay repo

### Org Overlay (DIST-05)

- [x] **OVLY-01**: User can run `conjure init --overlay <git-url>` to apply the base kit first and then overlay files from the given repo; all writes go through `lib/mutate.sh`
- [x] **OVLY-02**: After `conjure init --overlay`, a `.claude/.conjure-org-overlay` marker file records the overlay URL and the cloned commit SHA for audit traceability
- [x] **OVLY-03**: User can run `conjure refresh-overlay` to re-pull the org overlay and re-apply it; overlay-wins semantics on conflict
- [x] **OVLY-04**: `conjure audit` detects and reports overlay presence, the pinned SHA, and any drift from the currently checked-out overlay HEAD
- [x] **OVLY-05**: Overlay repo authentication uses the user's existing git credential store; no credentials are stored by Conjure

### Homebrew Formula (DIST-02)

- [x] **BREW-01**: User can install Conjure with `brew install mohandoz/conjure/conjure`; `conjure --version` exits 0
- [x] **BREW-02**: `CONJURE_HOME` resolves automatically to `$(brew --prefix)/share/conjure/` when installed via Homebrew (no manual env var required)
- [x] **BREW-03**: Homebrew formula is pinned to a tagged tarball URL + SHA256 (never a branch HEAD)
- [x] **BREW-04**: `mislav/bump-homebrew-formula-action@v3` fires on every GitHub release to auto-update the SHA256 in the `mohandoz/homebrew-conjure` tap repo

### Docker Image (DIST-03)

- [x] **DOCK-01**: User can run `docker run ghcr.io/mohandoz/conjure:v0.4.0 conjure audit .` with `-v $(pwd):/work` and get correct output with user-owned files
- [x] **DOCK-02**: Docker image runs as non-root (`USER conjure`, UID 1000); files written into a mounted volume remain owned by the calling user
- [x] **DOCK-03**: Image is published to `ghcr.io/mohandoz/conjure` via `GITHUB_TOKEN` with semantic version tags and `latest`
- [x] **DOCK-04**: Image is multi-arch (`linux/amd64` + `linux/arm64`) and baseline image size is ≤200 MB
- [x] **DOCK-05**: README documents `$(pwd)` / `${PWD}` / `%CD%` volume-mount forms for bash, PowerShell, and cmd

### Release Pipeline Wiring

- [x] **REL-01**: A single `release.yml` GitHub Actions workflow triggers on version tag push and fires: (a) Homebrew SHA bump via `bump-homebrew-formula-action`, (b) Docker multi-arch build + push to `ghcr.io`, (c) `marketplace.json` version consistency check
- [x] **REL-02**: Release workflow is gated on green CI (all tests + shellcheck + audit pass) before any distribution artifact is published

### Tech Debt Clearance

- [x] **TECH-02a**: `VALIDATION.md` created for Phase 01 (pre-flight cross-platform hooks) with executable verify commands
- [x] **TECH-02b**: `VALIDATION.md` created for Phase 02 (dry-run enforcement) with executable verify commands
- [x] **TECH-02c**: `VALIDATION.md` created for Phase 04 (regression suite + dry-run proof) with executable verify commands
- [x] **TECH-02d**: `VALIDATION.md` created for Phase 05 (README demo) with executable verify commands
- [x] **TECH-02e**: `VALIDATION.md` created for Phase 06 (cost estimator) with executable verify commands
- [x] **TECH-02f**: `VALIDATION.md` created for Phase 07 (skill-firing telemetry) with executable verify commands
- [x] **TECH-03**: `windows-latest` matrix entry added to CI; all existing tests pass with `shell: bash`; `.mjs` hooks tested with `shell: pwsh`

---

## Future Requirements (Deferred)

- `conjure:full` Docker tag with optional Go/Rust tools (gitleaks, ast-grep) — deferred to v0.4.x; baseline tag is the priority
- PowerShell `conjure.ps1` entrypoint for native Windows (no Git Bash) — deferred to v0.5.0; `wsl` target covers most Windows CI use cases
- Overlay version compatibility contract (`compatible-kit-version` in overlay manifest) — deferred to v0.4.x after first overlay is published in production
- `--dry-run` support for `conjure publish` and `conjure publish-skill` — deferred; not blocking adoption

---

## Out of Scope

- **Making a project actually compliant** — overlays reduce non-compliant output only; real compliance needs people + process + audit
- **Auto-update 3-way merge conflict resolution UI** — conflicts are surfaced as sidecar files; interactive resolution is a v0.5.0 concern
- **Skill marketplace moderation/scoring** — community submission is process work; automated curation is out of scope
- **Cross-repo graph orchestration** — v0.6.0; single-repo correctness first
- **IDE extensions, web dashboard** — backlog; not core to the one-command value

---

## Traceability

| REQ-ID | Phase | Plan | Status |
|--------|-------|------|--------|
| TECH-02a | Phase 08 | TBD | Pending |
| TECH-02b | Phase 08 | TBD | Pending |
| TECH-02c | Phase 08 | TBD | Pending |
| TECH-02d | Phase 08 | TBD | Pending |
| TECH-02e | Phase 08 | TBD | Pending |
| TECH-02f | Phase 08 | TBD | Pending |
| MERGE-01 | Phase 09 | TBD | Pending |
| MERGE-02 | Phase 09 | TBD | Pending |
| MERGE-03 | Phase 09 | TBD | Pending |
| MERGE-04 | Phase 09 | TBD | Pending |
| MERGE-05 | Phase 09 | TBD | Pending |
| MKTPL-01 | Phase 10 | TBD | Pending |
| MKTPL-02 | Phase 10 | TBD | Pending |
| MKTPL-03 | Phase 10 | TBD | Pending |
| MKTPL-04 | Phase 10 | TBD | Pending |
| SKILL-01 | Phase 11 | TBD | Pending |
| SKILL-02 | Phase 11 | TBD | Pending |
| SKILL-03 | Phase 11 | TBD | Pending |
| SKILL-04 | Phase 11 | TBD | Pending |
| OVLY-01 | Phase 12 | TBD | Pending |
| OVLY-02 | Phase 12 | TBD | Pending |
| OVLY-03 | Phase 12 | TBD | Pending |
| OVLY-04 | Phase 12 | TBD | Pending |
| OVLY-05 | Phase 12 | TBD | Pending |
| BREW-01 | Phase 13 | TBD | Pending |
| BREW-02 | Phase 13 | TBD | Pending |
| BREW-03 | Phase 13 | TBD | Pending |
| BREW-04 | Phase 13 | TBD | Pending |
| DOCK-01 | Phase 14 | Dockerfile + docker.yml smoke test | Complete (human-needed for live image test) |
| DOCK-02 | Phase 14 | Dockerfile USER conjure UID 1000 | Complete |
| DOCK-03 | Phase 15 | release.yml push: true to ghcr.io | Complete (human-needed for live tag push) |
| DOCK-04 | Phase 14 | docker.yml multi-arch + size assertion | Complete (human-needed for CI run) |
| DOCK-05 | Phase 14 | README.md Docker section | Complete |
| TECH-03 | Phase 14 | ci.yml windows-test job | Complete (human-needed for CI run) |
| REL-01 | Phase 15 | release.yml Homebrew+Docker+marketplace | Complete (human-needed for live tag push) |
| REL-02 | Phase 15 | release.yml ci-gate job | Complete (human-needed for live tag push) |

---

*Total requirements: 29 active (36 req-IDs when TECH-02a–f counted individually) | 4 future | 5 out of scope*
