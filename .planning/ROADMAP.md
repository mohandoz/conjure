# Roadmap: Conjure

## Completed Milestones

- **v0.3.0** — "Testing + Telemetry" — 7 phases, 22 plans, 20/20 requirements satisfied, 169 commits (2026-05-24 → 2026-05-25) — [Archive](.planning/milestones/v0.3.0-ROADMAP.md)

## Active Milestone

**v0.4.0 — Distribution + Ecosystem**

Make Conjure installable and shareable through every standard channel while clearing v0.3.0 tech debt that blocks production use.

## Phases

- [x] **Phase 08: Nyquist Compliance Backfill** - Write VALIDATION.md for phases 01, 02, 04, 05, 06, 07 (completed 2026-05-25)
- [x] **Phase 09: 3-Way Merge** - Implement `cmd_update --apply` via `lib/merge.sh` + base snapshot (completed 2026-05-25)
- [x] **Phase 10: Marketplace Publish** - Wire and validate the Claude Code Marketplace plugin manifest (completed 2026-05-25)
- [ ] **Phase 11: Skill Publishing** - Add `conjure publish-skill` command with egress scan + PR flow
- [ ] **Phase 12: Org Overlay** - Implement `conjure init --overlay` + `conjure refresh-overlay` system
- [ ] **Phase 13: Homebrew Tap** - Publish `mohandoz/homebrew-conjure` formula and auto-bump action
- [ ] **Phase 14: Docker + Windows CI** - Multi-arch Docker image and `windows-latest` CI matrix entry
- [ ] **Phase 15: Release Pipeline** - Single `release.yml` wires all distribution targets under one gate

## Phase Details

### Phase 08: Nyquist Compliance Backfill
**Goal**: Every completed phase has a VALIDATION.md with executable verify commands so test coverage is verifiable before new surface area is added
**Depends on**: Nothing (phase 07 already complete)
**Requirements**: TECH-02a, TECH-02b, TECH-02c, TECH-02d, TECH-02e, TECH-02f
**Success Criteria** (what must be TRUE):
  1. A contributor can run the verify commands in each VALIDATION.md and confirm the phase behavior without reading source code
  2. VALIDATION.md files exist for phases 01, 02, 04, 05, 06, and 07 in their respective phase directories
  3. CI passes with the new VALIDATION.md files present (no broken references, no size-cap violations)
**Plans**: 3 plans

Plans:
- [x] 08-01-PLAN.md — Create 01-VALIDATION.md (preflight + cross-platform hooks) and 02-VALIDATION.md (dry-run enforcement) (TECH-02a, TECH-02b)
- [x] 08-02-PLAN.md — Create 04-VALIDATION.md (regression suite + dry-run proof) and 05-VALIDATION.md (README demo) (TECH-02c, TECH-02d)
- [x] 08-03-PLAN.md — Create 06-VALIDATION.md (cost estimator) and 07-VALIDATION.md (skill-firing telemetry) (TECH-02e, TECH-02f)

### Phase 09: 3-Way Merge
**Goal**: `conjure update --apply` performs real 3-way file merges instead of silently ignoring user customizations, and conflicts are safely surfaced as sidecar files
**Depends on**: Phase 08
**Requirements**: MERGE-01, MERGE-02, MERGE-03, MERGE-04, MERGE-05
**Success Criteria** (what must be TRUE):
  1. User can run `conjure update --apply` and have changed template files merged into their project using `git merge-file --diff3` (no more stub)
  2. After `conjure init`, a `.claude/.conjure-templates-<version>/` snapshot exists so future merges have a valid ancestor
  3. When a merge produces conflicts, the original live file is untouched and a `.conjure-conflict-<filename>` sidecar holds the conflicted content
  4. Generated files (`.conjure-version`, `settings.json`) always accept upstream; user-owned files (`CLAUDE.md`, skills, agents) go through 3-way merge
  5. `conjure audit` detects `^<<<<<<<` conflict markers in any harness file and exits non-zero with a specific error message
**Plans**: 3 plans

Plans:
- [x] 09-01-PLAN.md — Create lib/merge.sh (merge_file_3way, write_merge_sidecar, merge_user_files) + add lib/ to CI shellcheck glob (MERGE-01, MERGE-03)
- [x] 09-02-PLAN.md — Modify cli/conjure: cmd_init snapshot write + cmd_update --apply real merge (MERGE-01, MERGE-02, MERGE-03, MERGE-04)
- [x] 09-03-PLAN.md — Add MERGE-05 audit conflict-marker check + MERGE-01/02/03/04 regression tests (MERGE-01, MERGE-02, MERGE-03, MERGE-04, MERGE-05)

### Phase 10: Marketplace Publish
**Goal**: The Conjure plugin manifest is valid, version-consistent, and a developer can run `conjure publish` to update and submit it to the community catalog
**Depends on**: Phase 09
**Requirements**: MKTPL-01, MKTPL-02, MKTPL-03, MKTPL-04
**Success Criteria** (what must be TRUE):
  1. User can run `conjure publish` and have `marketplace.json` updated with the current release SHA and validated locally
  2. CI fails on any PR where `version` in `marketplace.json` or `plugin.json` does not match the `VERSION` file
  3. CI runs `claude plugin validate .` on every PR and fails on schema errors
  4. User can run `conjure publish --submit` and receive a checklist + PR URL for submitting to `anthropics/claude-plugins-community`
**Plans**: 4 plans

Plans:
- [x] 10-01-PLAN.md — Restructure .claude-plugin/marketplace.json + plugin.json to pass `claude plugin validate` (MKTPL-01)
- [x] 10-02-PLAN.md — Create scripts/publish-plugin.sh + cmd_publish dispatch in cli/conjure (MKTPL-01, MKTPL-04)
- [x] 10-03-PLAN.md — Add version-consistency check + claude CLI install + plugin validate steps to ci.yml (MKTPL-02, MKTPL-03)
- [x] 10-04-PLAN.md — Inline MKTPL regression tests in tests/run.sh (MKTPL-01, MKTPL-02, MKTPL-04)

### Phase 11: Skill Publishing
**Goal**: A developer can contribute a project skill to the public kit (or a private org kit) through a single command that validates safety and opens a PR
**Depends on**: Phase 10
**Requirements**: SKILL-01, SKILL-02, SKILL-03, SKILL-04
**Success Criteria** (what must be TRUE):
  1. User can run `conjure publish-skill <name>` and have the skill validated against frontmatter schema, size cap, and a static egress scan before any submission step
  2. `conjure publish-skill` opens a PR via `gh pr create`; if `gh` is absent, it prints the manual PR URL and checklist instead
  3. Attempting to publish a skill at a branch HEAD (not a SHA-pinned commit) produces an error that stops submission
  4. User can run `conjure publish-skill <name> --to <org/repo>` to contribute to a private kit or org overlay repo
**Plans**: 2 plans

Plans:
- [ ] 11-01-PLAN.md — Create scripts/publish-skill.sh (four validation gates + PR instruction printing) (SKILL-01, SKILL-02, SKILL-03, SKILL-04)
- [ ] 11-02-PLAN.md — Wire cmd_publish_skill in cli/conjure + add SKILL-01..SKILL-04 regression tests in tests/run.sh (SKILL-01, SKILL-02, SKILL-03, SKILL-04)

### Phase 12: Org Overlay
**Goal**: An organization can define a private overlay repo that is applied on top of the base kit, with full audit traceability and credential-safe re-pull support
**Depends on**: Phase 09
**Requirements**: OVLY-01, OVLY-02, OVLY-03, OVLY-04, OVLY-05
**Success Criteria** (what must be TRUE):
  1. User can run `conjure init --overlay <git-url>` and have the base kit applied first, then the overlay files applied on top; all writes go through `lib/mutate.sh`
  2. After `conjure init --overlay`, a `.claude/.conjure-org-overlay` marker file exists recording the overlay URL and cloned commit SHA
  3. User can run `conjure refresh-overlay` to re-pull the org overlay and re-apply it with overlay-wins semantics on conflicts
  4. `conjure audit` reports overlay presence, the pinned SHA, and any drift from the currently checked-out overlay HEAD
  5. Overlay authentication uses the user's existing git credential store; no credentials are stored by Conjure
**Plans**: TBD

### Phase 13: Homebrew Tap
**Goal**: macOS and Linux developers can install Conjure with `brew install mohandoz/conjure/conjure` and receive automatic SHA updates on every release
**Depends on**: Phase 10
**Requirements**: BREW-01, BREW-02, BREW-03, BREW-04
**Success Criteria** (what must be TRUE):
  1. `brew install mohandoz/conjure/conjure` succeeds and `conjure --version` exits 0 with greppable version output
  2. `CONJURE_HOME` resolves automatically to `$(brew --prefix)/share/conjure/` when installed via Homebrew without any manual env var configuration
  3. The Homebrew formula references a tagged tarball URL + SHA256 (never a branch HEAD reference)
  4. Publishing a new GitHub release automatically triggers `mislav/bump-homebrew-formula-action@v3` to update SHA256 in the `mohandoz/homebrew-conjure` tap repo
**Plans**: TBD

### Phase 14: Docker + Windows CI
**Goal**: Conjure is runnable as a Docker container (multi-arch, non-root, ≤200 MB) and all existing tests pass on `windows-latest` CI
**Depends on**: Phase 10
**Requirements**: DOCK-01, DOCK-02, DOCK-03, DOCK-04, DOCK-05, TECH-03
**Success Criteria** (what must be TRUE):
  1. `docker run ghcr.io/mohandoz/conjure:v0.4.0 conjure audit .` works with `-v $(pwd):/work` and produces correct output
  2. Files written into a mounted volume from the container remain owned by the calling user (container runs as non-root `USER conjure`, UID 1000)
  3. Image is published to `ghcr.io/mohandoz/conjure` with semantic version tags and `latest` via `GITHUB_TOKEN`
  4. Image supports `linux/amd64` and `linux/arm64` architectures and baseline image size is ≤200 MB
  5. All existing CI tests pass with a `windows-latest` matrix entry using `shell: bash` for CLI paths and `shell: pwsh` for `.mjs` hooks
**UI hint**: no

### Phase 15: Release Pipeline
**Goal**: A single `release.yml` workflow gates all distribution artifacts behind green CI and fires Homebrew bump, Docker build, and marketplace version check on every version tag push
**Depends on**: Phase 13, Phase 14
**Requirements**: REL-01, REL-02
**Success Criteria** (what must be TRUE):
  1. Pushing a version tag triggers a single `release.yml` workflow that fires: Homebrew SHA bump via `bump-homebrew-formula-action`, Docker multi-arch build + push to `ghcr.io`, and `marketplace.json` version consistency check
  2. No distribution artifact (Homebrew SHA, Docker image, marketplace version) is published unless all tests, shellcheck, and audit pass green first
**Plans**: TBD

## Progress

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 08. Nyquist Compliance Backfill | v0.4.0 | 3/3 | Complete    | 2026-05-25 |
| 09. 3-Way Merge | v0.4.0 | 3/3 | Complete    | 2026-05-25 |
| 10. Marketplace Publish | v0.4.0 | 4/4 | Complete    | 2026-05-25 |
| 11. Skill Publishing | v0.4.0 | 0/2 | Not started | - |
| 12. Org Overlay | v0.4.0 | 0/TBD | Not started | - |
| 13. Homebrew Tap | v0.4.0 | 0/TBD | Not started | - |
| 14. Docker + Windows CI | v0.4.0 | 0/TBD | Not started | - |
| 15. Release Pipeline | v0.4.0 | 0/TBD | Not started | - |

## Backlog

### Future Milestones

- v0.5.0 — Auto-update drift detector, auto-PR bot (needs frozen schemas first)
- v0.6.0 — Workspace / cross-repo graph orchestration (single-repo correctness first)
