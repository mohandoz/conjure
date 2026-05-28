# Project Retrospective

*A living document updated after each milestone. Lessons feed forward into future planning.*

---

## Milestone: v0.4.0 — Distribution + Ecosystem

**Shipped:** 2026-05-26
**Phases:** 9 | **Plans:** 23 | **Commits:** 136

### What Was Built

- Nyquist VALIDATION.md backfill for 6 completed phases — standalone verify blocks, no source-code reading required
- Real 3-way merge (`conjure update --apply`) via `git merge-file --diff3` — conflict sidecars, base snapshot at init
- `conjure publish` + `conjure publish-skill` — Marketplace manifest management + egress-scanned PR flow
- Org overlay system — `conjure init --overlay`, `conjure refresh-overlay`, audit drift detection, credential-safe
- Homebrew formula + `mislav/bump-homebrew-formula-action@v3` wired in release pipeline
- Multi-arch Docker image (linux/amd64 + linux/arm64, debian:bookworm-slim, non-root, ≤200 MB)
- windows-test CI job (`windows-latest`, shell: bash)
- 4-job release.yml: ci-gate → release → docker + homebrew (independent parallel)

### What Worked

- **Phase 15.1 as tech debt cleanup** — inserting a post-phase hotfix to clear audit-identified debt before milestone close is clean; surfaced immediately, fixed immediately
- **Audit-first before completion** — v0.4.0-MILESTONE-AUDIT.md caught the Docker+Homebrew coupling before the milestone was marked done
- **Integration checker subagent** — spawning a dedicated integration checker found the ci-gate empty-check edge case that inline review had missed
- **`lib/mutate.sh` chokepoint discipline** — every write going through mutate made dry-run testing trivial and kept 261 tests passing through 9 phases

### What Was Inefficient

- **Phase SUMMARY.md frontmatter not standardized** — `gsd-sdk summary-extract` returned `null`/`"One-liner:"` for most plans because early phases don't use consistent frontmatter; required manual override in MILESTONES.md
- **VALIDATION.md Nyquist frontmatter inconsistency** — phases 09+ have `nyquist_compliant: false` frontmatter but Phase 09 has none; Nyquist classification required manual inspection
- **ci-gate logic warnings not caught during Phase 15 planning** — the empty-check bypass and filter name mismatch should have been caught in the discuss/plan phase, not during the post-close integration check

### Patterns Established

- Decimal phase numbering (15.1) for urgent hotfixes after milestone phases are complete — clear insertion semantics without renumbering
- 4-job release.yml pattern: gate job → core job → parallel distribution jobs (each fails independently)
- HOMEBREW_TAP_GITHUB_TOKEN preflight with graceful skip — missing secret warns, doesn't fail
- Post-milestone integration checker subagent with explicit requirement ID mapping

### Key Lessons

1. **Audit before close, not after** — the milestone audit caught real issues; run it while there's still time to fix without disrupting close ceremony
2. **`human_needed` is not a gap** — live-environment tests (brew install, docker run, GitHub tag push) are expected pre-release checklist items, not failures
3. **Phase 15.1 pattern is worth institutionalizing** — "audit finds debt → insert N.1 phase → fix → mark complete → close" is a clean loop that keeps milestone scope honest
4. **Frontmatter discipline matters for tooling** — inconsistent SUMMARY.md frontmatter breaks `gsd-sdk summary-extract`; standardize early

---

## Milestone: v0.5.0 — Auto-Update + Healthcheck

**Shipped:** 2026-05-28
**Phases:** 5 | **Plans:** 10 | **Commits:** 49

### What Was Built

- `conjure check` — sha256-based 3-way drift classifier (M/R/A) over a 35-entry kit manifest, `--porcelain` output, cross-platform sha256 fallback
- `conjure resolve` — interactive diff3 sidecar walker with fd-3 stdin isolation, non-TTY guard (exit 2), DRY_RUN-safe `mutate_rm` cleanup
- `conjure update --pr` + `--cron` — gh-guarded, zero-drift guard, deterministic branch naming, idempotent via `gh pr list`, weekly workflow template
- `conjure.ps1` — Windows shim (Git Bash → WSL → exit 2) with `$LASTEXITCODE` propagation + `windows-ps1-shim` pwsh CI job
- `mutate_rm` deletion primitive (INFRA-01), publish-skill positional arg (DEBT-02), release.yml ci-gate empty-check guard + retry (DEBT-01)

### What Worked

- **Autonomous milestone run** — discuss→plan→execute per phase ran end-to-end with minimal intervention; phases 16–20 completed in ~3 days
- **`lib/mutate.sh` chokepoint extended cleanly** — adding `mutate_rm` followed the established dry-run pattern; Phase 18 consumed it without friction
- **Deterministic branch naming** (sha256 of kit version) made `conjure update --pr` idempotency testable with stubbed `gh`

### What Was Inefficient

- **CI was declared done before it was actually green** — the milestone shipped, then the shellcheck shebang fix unmasked latent cross-platform test failures (70 on Windows, 3 on ubuntu) that had been hidden because shellcheck aborted the job before the suite ran. Required four post-close fix commits.
- **Windows test job was red for hours undetected** — no one watched the windows-test job; usrmerge (`/bin`→`/usr/bin`) and Git Bash PATH assumptions broke gh-isolation and tool resolution
- **SUMMARY.md frontmatter STILL inconsistent** — `summary-extract` again returned `"One-liner:"` / `"Date:"` garbage for most plans; MILESTONES.md accomplishments had to be hand-written (same lesson as v0.4.0, not yet fixed)

### Patterns Established

- **Test-isolation by symlink-mirror** — to hide one binary (gh) from `command -v` without losing siblings, mirror its dir(s) minus the target into a stub; robust under usrmerge and multi-dir installs
- **Dynamic tool-dir resolution in sandbox** — resolve git/jq/python3 parent dirs at runtime rather than hardcoding `/usr/bin`, so Git Bash (`/mingw64/bin`, `/cmd`) works
- **`cygpath -m` for native-tool cwd** — when a POSIX path is handed to a native-Windows binary (node), translate to a forward-slash Windows path (JSON-safe, same physical dir)

### Key Lessons

1. **A milestone isn't done until CI is observed green** — "tests pass locally" + "release job passed" ≠ "CI green"; a lint step short-circuiting can mask the whole test suite. Watch every job.
2. **Cross-platform PATH assumptions are landmines** — usrmerge, Git Bash layout, and native-vs-POSIX path handling each broke silently; test the actual runner, don't reason from Linux
3. **Standardize SUMMARY.md frontmatter already** — this is the second milestone where extraction tooling produced garbage; it's now a recurring tax

### Cost Observations

- Model mix: predominantly Opus 4.7 (1M context)
- Notable: the post-close debugging (diagnose 70+ failures from logs, reproduce locally, fix, verify) was the bulk of the late effort — would have been cheaper caught pre-close

---

## Cross-Milestone Trends

### Process Evolution

| Milestone | Phases | Plans | Key Change |
|-----------|--------|-------|------------|
| v0.3.0 | 7 | 22 | First GSD milestone; established plan→execute→verify loop |
| v0.4.0 | 9 | 23 | Added decimal phases; integration checker subagent; audit-before-close discipline |
| v0.5.0 | 5 | 10 | Autonomous milestone run; post-close CI hardening exposed cross-platform test gaps |

### Cumulative Quality

| Milestone | Test Assertions | Status |
|-----------|----------------|--------|
| v0.3.0 | 203 | All green |
| v0.4.0 | 261+ | All green |
| v0.5.0 | 302 | All green (after post-close cross-platform fixes) |
