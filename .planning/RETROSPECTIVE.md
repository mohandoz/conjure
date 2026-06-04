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

## Milestone: v0.6.0 — Safe Brownfield Adoption

**Shipped:** 2026-05-29
**Phases:** 4 (21–24) | **Plans:** 12 | **Tasks:** 25

### What Was Built
`conjure adopt` — a deterministic 5-step pipeline (preconditions → snapshot → inventory → scaffold → audit) that folds an existing repo into the four-layer harness, fully rollback-capable with crash-durable `.conjure-adopt-state` and partial-run recovery. A human-gated `[Read, Bash]` `restructure` skill condenses an oversized CLAUDE.md through pre-write safety gates (invariant-verify + `conjure audit`) that block invalid proposals before approval, applying every mutation through the audited `conjure adopt` chokepoint. Verified E2E against a 500-file `_brownfield-argus` fixture (suite 449/0).

### What Worked
- **Test-first Wave 0 per phase** — a graceful-red test block landed before production code each phase, giving a concrete red→green signal (21→22→23→24). The suite grew 359 → 449 with zero silent regressions.
- **Split-responsibility architecture** (CLI mutates, skill judges, `[Read, Bash]` chokepoint) made the security story crisp and the code review tractable.
- **Driving the real `/dev/tty` paths via `expect`** — the interactive recovery prompt (Phase 22) and approval loop (Phase 23) were genuinely verified by PTS, not hand-waved as "manual."
- **The milestone integration audit earned its keep** — a live E2E smoke test caught a real headline-flow blocker (adopt refused a clean git repo) that 449 green unit/integration assertions all missed because every pipeline test used a non-git fixture.

### What Was Inefficient
- **Plan-checker repeatedly blocked on the same Dimension-11 format gate** (RESEARCH "## Open Questions" missing the `(RESOLVED)` suffix) across phases 22/23/24 — the substance was always resolved in VALIDATION.md; only the heading marker was stale. A planner-side convention would have saved three revision passes.
- **The clean-git-repo blocker should have been a planned test** — the test gap (no pipeline test against a real git repo) was the root cause it escaped until the audit's live smoke test.
- **The planner corrupted `.planning/ROADMAP.md` twice** (stray Perl/Write edits, em-dash mojibake) and self-recovered both times — fragile editing of a UTF-8 doc.

### Patterns Established
- `_`-prefixed fixture dirs are excluded from the generic `tests/fixtures/[^_]*/` audit/golden loops — now a hard rule (tripped in 22, locked in 23/24).
- Pre-write gates over post-write fixes: validate proposed content (invariants + `@import`/cap audit) BEFORE the human approval prompt.
- Snapshot excludes `.git`/`node_modules`; rollback verifies sha256 zero-diff excluding conjure's own dirs (D-03).

### Key Lessons
- A green test suite proves the paths you tested, not the path your users take — the headline flow (`conjure adopt` on a real git repo) was the one path no test exercised.
- When a fix touches a safety primitive (the snapshot copy), verify the invariant it underpins directly (live rollback zero-diff + `git fsck`), not just the unit suite.

### Cost Observations
- Model mix: predominantly Opus 4.7 (1M context); subagents (researcher/planner/checker/executor/reviewer/fixer/verifier) on Sonnet.
- Notable: two code-review→fix cycles (Phase 22: 2 Critical; Phase 23: 1 Critical) and the audit-time blocker fix were the highest-value spend — each caught a real correctness/safety bug the suite missed.

---

## Milestone: v0.7.0 — Plugin-native + Policy-grade

**Shipped:** 2026-06-04
**Phases:** 6 (25–30) | **Plans:** 24 | **Requirements:** 27/27

### What Was Built
Conjure now rides Claude Code's native rails end-to-end: `conjure publish-plugin` (plugin.json + marketplace.json with merge-preserve, validation gates, secret-scan), `conjure emit-policy` (per-regime sandbox + 1:1 `Read()` deny mirror + managed-settings.json + macOS/Windows MDM bundle), schema-version-aware audit/check on a bundled `lib/cc-schema.json` with `audit --json` machine output, `conjure eval` (promptfoo via the claude-agent-sdk provider, pinned, with PR-gate emission and an `audit --budget` context linter), and `conjure workspace` (read-only manifest aggregation plus a mutating saga: snapshot-all-before-any-apply, SIGKILL-durable atomic state, per-repo sha256 zero-diff rollback). Suite 562→579/0 at close.

### What Worked
- **Wave-0-test-infrastructure-first held for all 6 phases** — every feature wave turned a planned graceful-red block green; zero silent regressions across 96 new assertions.
- **The review→fix→re-review loop converged to clean every phase** and caught genuinely dangerous bugs the suite missed: exit-1 convention breaks + missing backup-before-mutate (25), YAML injection via apostrophes in CLAUDE.md rules (28), a path-traversal boundary anchored one level too high accepting `../sibling` escapes (29), pkill regex over-match + the orphaned-subprocess SIGKILL root cause (30).
- **Plan-checker as a pre-execution gate paid off heavily** — it caught the snapshot_create API misuse, the env-var-vs-argv flag override (CONJURE_JSON/PORCELAIN), the idempotent-vs-archive design contradiction, and a cross-wave cli/conjure write race before any executor ran.
- **Research with live doc fetches corrected training-data assumptions**: 30 hook events not 34, 16 SKILL.md fields not 14, claude-agent-sdk as the only viable promptfoo provider, fail-on-threshold integer semantics, repeat/minPassCount placement.
- **Prior-phase lessons compounded**: the warn()-flips-exit-code rule (25), single-EXIT-trap rule (27), and execution-time boundary re-checks (29) were each enforced in every subsequent phase's plans.

### What Was Inefficient
- **Worktree-isolation merge friction in Phase 25** (FF failures from tracking-commit divergence, a stray SUMMARY recreation, an mktemp template collision) — switched to sequential non-worktree execution for phases 26-30; far smoother for single-plan waves.
- **Transient API socket errors killed two subagents mid-run** (28-01 executor, 29 planner) — both recovered cleanly by spot-check + fresh dispatch, but cost ~30 min.
- **The environment degraded at the OS level mid-Phase-30** (mktemp + `.env.example` reads denied): failed mktemp left test dir vars empty and `git -C ""` escaped sandboxes, committing junk to the real repo twice. Recovery required reflog surgery (soft reset after an auto-checkpoint commit luckily captured the repaired tree).

### Patterns Established
- Audit severity contract: `note()` for advisory (exit 0), `err()` for real bugs (exit 2) — `warn()` reserved for the legacy WARN→exit-1 gate only.
- Emit workers: validate-before-write, snapshot-before-mutate, exit 2, idempotent jq merges with explicit `(a//[])+(b//[])|unique` for arrays.
- Machine outputs (`--json`, `--porcelain`): stdout purity via a `human()` stderr router; flags passed as argv to subprocesses, never env-only.
- Security boundaries checked at validate-time AND execution-time, including rollback-restore time.

### Key Lessons
- A SIGKILL test that kills the orchestrator does not kill its children — orphaned subprocesses kept mutating repos during rollback; eviction must be explicit (anchored pkill / PID tracking).
- Test sandboxes built on `mktemp` + `git -C "$VAR"` have a catastrophic failure mode when mktemp fails: the empty var silently retargets the REAL repo. Guard every `-C` var (tracked as tech debt).
- In-place swaps of production files during tests (SCHM-STALE) need trap-based restore — an interrupted run shipped the fixture into production.

### Cost Observations
- Model mix: Opus 4.8 (1M) orchestrator; all subagents (researcher/pattern-mapper/planner/checker/executor/reviewer/fixer/verifier/debugger/integration-checker) on Sonnet.
- ~50 subagent dispatches across the milestone; ~181 commits in ~36 hours.
- Notable: the highest-value spend was adversarial verification — plan-checker blockers (5 phases), review-fix convergence loops (4 phases to clean), and the 2.8M-token SIGKILL-flake debug session that found a real production bug.

---

## Cross-Milestone Trends

### Process Evolution

| Milestone | Phases | Plans | Key Change |
|-----------|--------|-------|------------|
| v0.3.0 | 7 | 22 | First GSD milestone; established plan→execute→verify loop |
| v0.4.0 | 9 | 23 | Added decimal phases; integration checker subagent; audit-before-close discipline |
| v0.5.0 | 5 | 10 | Autonomous milestone run; post-close CI hardening exposed cross-platform test gaps |
| v0.6.0 | 4 | 12 | Pre-write safety gates; split-responsibility CLI/skill architecture; live E2E smoke in milestone audit |
| v0.7.0 | 6 | 24 | Full autonomous run (discuss→plan→execute per phase); plan-checker revision loops; review→fix convergence to clean every phase |

### Cumulative Quality

| Milestone | Test Assertions | Status |
|-----------|----------------|--------|
| v0.3.0 | 203 | All green |
| v0.4.0 | 261+ | All green |
| v0.5.0 | 302 | All green (after post-close cross-platform fixes) |
| v0.6.0 | 449 | All green |
| v0.7.0 | 579 | All green at close |
