# Project Research Summary

**Project:** Conjure v0.5.0 — Auto-Update + Healthcheck
**Domain:** POSIX bash CLI harness kit for Claude Code — drift detection, auto-PR, conflict resolution, Windows entrypoint
**Researched:** 2026-05-26
**Confidence:** HIGH

## Executive Summary

Conjure v0.5.0 closes the lifecycle loop opened in v0.4.0: `conjure init` scaffolds, `conjure update --apply` merges upstream changes, but users have no lightweight way to discover they are stale, no automation to surface drift as a PR, and no guided tool for resolving the merge conflicts that `--apply` leaves as sidecars. This milestone adds the six capabilities that complete that loop: `conjure check` (read-only drift report), `conjure update --pr` (drift-to-PR automation), `conjure resolve` (guided sidecar walk), `conjure.ps1` (native Windows shim), and two correctness fixes (ci-gate empty-check guard, `publish-skill` positional arg).

The implementation requires zero new runtime dependencies. Every new feature is built from tools already in the preflight stack: `diff -q` for drift comparison, `gh pr create` + `git push` for PR automation, `find` + POSIX `read` for conflict walking, PowerShell 7 (`pwsh`) as an optional soft dependency for Windows users who want a native entrypoint, and `gh api` for the ci-gate guard. The existing `lib/mutate.sh` chokepoint, `lib/merge.sh` sidecar contract, and `cli/conjure` dispatcher pattern all extend cleanly without structural changes.

The dominant risk is not implementation complexity — all six features are straightforward — but correctness gaps: two-way diffs that produce false-positive drift reports (CR-1), non-idempotent PR creation that spams cron jobs (CR-2), interactive prompts that silently fail in non-TTY environments (CR-3), and PowerShell exit code normalization that breaks hook abort semantics (CR-4). Every one of these is a day-one requirement, not a hardening step. Address them in the build order described below before any feature is considered complete.

## Key Findings

### Recommended Stack

No new tools enter the stack. The entire v0.5.0 surface is implemented with `diff`, `find`, `git`, `gh`, `jq`, `awk`, and `pwsh` — all either hard preflight dependencies or already-advisory soft dependencies. The `dependencies: {}` block in `package.json` stays empty.

The one new optional soft dependency is PowerShell 7 (`pwsh`), required only for Windows users who want `conjure.ps1` as a native entrypoint. The shim is ~30 lines: path detection (Git Bash candidates, then WSL fallback), argument passthrough via `@args`, and exit code propagation via `exit $LASTEXITCODE`. It is explicitly a launcher, not a port.

**Core technologies (v0.5.0 additions to existing stack):**
- `diff -q` (POSIX) — drift detection in `check-drift.sh` — already present everywhere; no new install
- `gh pr create` + `git push -u origin HEAD` — PR automation — `gh` is an existing soft dep; the pattern is new
- `find .claude -name '.conjure-conflict-*'` — sidecar discovery in `resolve-conflicts.sh` — existing POSIX `find`
- `conjure.ps1` (pwsh 7) — Windows dispatch shim — new optional soft dep; `winget install Microsoft.PowerShell` on Windows
- `gh api` + jq `select(.name != "Release") | length` — ci-gate empty-check guard — `gh` already in `release.yml`

**Patterns confirmed by research to avoid:**
- No `--push` flag exists in `gh pr create` — always `git push -u origin HEAD` first
- Do not use `total_count` from the check-runs API directly — it includes the Release job; filter with jq `select` first
- Do not target PowerShell 5.1 — `$IsWindows` and `?.` null-conditional require PS 6+; target pwsh 7+
- Do not use `$PSScriptRoot` for symlink-resolved paths — use `$PSCommandPath` (PS 7.2+) instead

### Expected Features

**Must have (v0.5.0 table stakes):**
- `conjure check` with 3-way drift classification (user-only / upstream-only / both-changed / no-base) and exit codes 0/1/2 — without this, `update --pr` has no signal and drift detection produces false positives
- `conjure check --porcelain` machine-readable output — required by `update-pr.sh` to build the PR body without text-parsing
- `conjure update --pr` with idempotency guard (`gh pr list --head ... | length` before create) — the PR dedup check is a required gate, not an enhancement
- `conjure resolve` with TTY guard (`[ -t 0 ] || exit 2`) and no silent default on `read` prompts — non-interactive invocation must fail loudly, not silently corrupt files
- `conjure.ps1` with `exit $LASTEXITCODE` on every code path and `$ErrorActionPreference = 'Continue'` — exit code propagation is a correctness requirement for hook abort semantics
- ci-gate empty-check guard with retry loop (poll up to 60s, sleep 10s between attempts) — a single-shot check races the check-run registration delay on tag push
- `mutate_rm` added to `lib/mutate.sh` before `resolve-conflicts.sh` is written — sidecar cleanup must honor `DRY_RUN`

**Should have (differentiators):**
- `conjure check --ci` mode emitting markdown-formatted output for PR bodies
- PR body includes version delta, file list, and conflict annotation when sidecars exist
- `conjure resolve --file <name>` to resolve a single sidecar without a full walk
- Skip option (`s`) in the conflict walk so users can defer hard decisions mid-session
- `.gitattributes` entry `conjure.ps1 text eol=crlf` committed with the file to prevent CRLF/LF corruption

**Defer to v0.5.x or later:**
- GH Action cron template (AUTPR-02) — pure YAML template; can ship as a fast-follow
- Schema version drift detection in `conjure check` — requires settings.json template to carry a schemaVersion field
- `conjure resolve` TUI (curses/dialog) — `$VISUAL/$EDITOR` model is correct for now
- IDE extensions or web dashboard for drift visibility

### Architecture Approach

The v0.4.0 dispatcher-workers-lib architecture extends cleanly. Three new worker scripts, three new/extended commands in `cli/conjure`, one new entrypoint (`cli/conjure.ps1`), and one new function in `lib/mutate.sh` (`mutate_rm`). The lib/mutate.sh chokepoint invariant — all filesystem mutations route through it — is extended to cover deletions.

**Major components (new and modified):**
1. `scripts/check-drift.sh` (new) — pure read-only drift comparison against snapshot dir; never sources `lib/mutate.sh`; exits 0/1/2; supports `--porcelain`
2. `scripts/update-pr.sh` (new) — sources `lib/merge.sh` (reuses `merge_user_files`); idempotency guard; `git push -u origin HEAD` then `gh pr create`; optionally writes cron template via `mutate_write`
3. `scripts/resolve-conflicts.sh` (new) — interactive sidecar walk with TTY guard; `awk`-based diff3 block extraction; `mutate_write` for resolved files; `mutate_rm` for sidecar cleanup
4. `cli/conjure.ps1` (new) — pwsh 7 launcher shim; Git Bash path candidates, WSL fallback; `@args` passthrough; `exit $LASTEXITCODE` on every path
5. `lib/mutate.sh` (modified) — add `mutate_rm`; same dry-run pattern as existing three mutate_* functions
6. `cli/conjure` (modified) — add `cmd_check`, extend `cmd_update` for `--pr`, add `cmd_resolve`, pass positional `$2` from `cmd_publish_skill` to script
7. `.github/workflows/release.yml` (modified) — DEBT-01: prepend retry-loop empty-check guard before conclusion-filter in ci-gate
8. `.github/workflows/ci.yml` (modified) — WIN-02: add `windows-pwsh` job with `shell: pwsh`

### Critical Pitfalls

1. **False-positive drift from 2-way comparison (CR-1)** — `conjure check` must compare base→current against base→upstream, not current against upstream. A file with only user edits must not be reported as drifted. Implement `check_file_drift` in `lib/merge.sh` before writing `check-drift.sh`. Success criterion: zero false positives on a repo with user edits where the pinned version equals current.

2. **Non-idempotent PR creation (CR-2)** — `gh pr create` errors when a PR for the branch already exists. Check `gh pr list --head "$BRANCH" --json number --jq length` before creating; if `> 0`, print the existing PR URL and exit 0. This guard is part of the feature specification, not an edge case.

3. **TTY guard missing from `conjure resolve` (CR-3)** — interactive prompts hang or silently accept defaults in CI. First line of `scripts/resolve-conflicts.sh`: `[ -t 0 ] || { echo "conjure resolve requires an interactive terminal"; exit 2; }`. Add regression test: pipe non-TTY stdin, assert exit 2.

4. **PowerShell exit code normalization (CR-4)** — PowerShell may reset `$LASTEXITCODE` after a cmdlet call. Every code path in `conjure.ps1` must end with `exit $LASTEXITCODE`. Use `$ErrorActionPreference = 'Continue'`, never `Stop`. The WIN-02 CI job must explicitly assert that exit code 2 propagates through the shim.

5. **`mutate_rm` missing — dry-run guarantee broken (CR-5)** — bare `rm` in `resolve-conflicts.sh` would bypass `DRY_RUN`. Add `mutate_rm` to `lib/mutate.sh` before any resolve script is written. The existing CI raw-write guard catches `cp` and `>` but not `rm` — extend it.

## Implications for Roadmap

The dependency graph determines build order. All seven steps are additive or targeted modifications; no existing behavior is removed.

### Phase 1: DEBT-02 — `publish-skill` Positional Arg Refactor

**Rationale:** Pure refactor, zero new logic, 10 minutes. Removes the fragile `TARGET_REPO` env var path before new surface area is added. Clears acknowledged tech debt (PROJECT.md line 123) first.
**Delivers:** `conjure publish-skill <name> <org/repo>` as a positional; `--to` retained as alias; `TARGET_REPO` retained with deprecation warning.
**Addresses:** DEBT-02
**Avoids:** M-2 (silent migration break without deprecation bridge)

### Phase 2: `mutate_rm` in `lib/mutate.sh`

**Rationale:** `scripts/resolve-conflicts.sh` (Phase 4) cannot be written without this. 10-line addition to the most tested file in the kit. Add regression tests immediately.
**Delivers:** `mutate_rm <path>` — dry-run aware file deletion; increments `CONJURE_DRY_MUTATION_COUNT`; follows exact pattern of existing mutate_* functions.
**Addresses:** CR-5 (dry-run bypass for sidecar deletions)
**Avoids:** CR-5 (bare `rm` in resolve scripts bypassing DRY_RUN)

### Phase 3: DRIFT-01/02 — `conjure check` + `scripts/check-drift.sh`

**Rationale:** Pure read path. Must precede Phase 5 (auto-PR) because AUTPR-01 consumes `--porcelain` output for the PR body. The 3-way drift classification design must be finalized here; it is the foundation that prevents false-positive fatigue across the entire milestone.
**Delivers:** `conjure check [target]` — 3-way drift classification, exit codes 0/1/2, human and `--porcelain` output modes; `scripts/check-drift.sh` as a pure read-only worker.
**Addresses:** DRIFT-01, DRIFT-02
**Avoids:** CR-1 (3-way vs 2-way comparison), M-5 (AUTPR-01 text parsing), MN-1 (exit code ambiguity)

### Phase 4: RESOLVE-01/02 — `conjure resolve` + `scripts/resolve-conflicts.sh`

**Rationale:** Requires `mutate_rm` (Phase 2). Completes the conflict-resolution story deferred from v0.4.0. Must ship before `update --pr` so users can resolve conflicts the auto-PR flow creates.
**Delivers:** `conjure resolve [target]` — TTY guard, sidecar discovery, awk-based diff3 block extraction, k/t/e/s prompt, `mutate_write` + `mutate_rm` on confirmation, session summary.
**Addresses:** RESOLVE-01, RESOLVE-02
**Avoids:** CR-3 (TTY guard), CR-5 (mutate_rm required), MN-4 (two-step confirmation before sidecar delete)

### Phase 5: AUTPR-01/02 — `conjure update --pr` + `scripts/update-pr.sh`

**Rationale:** Depends on `lib/merge.sh` (v0.4.0 shipped), Phase 3 (`--porcelain` output), and Phase 4 (`conjure resolve`). Full update cycle testable end-to-end. Cron template (AUTPR-02) is one `mutate_write` call added in the same step.
**Delivers:** `conjure update --pr` — idempotency guard, branch + merge + push + PR create, structured PR body, optional cron template; graceful degrade when `gh` absent.
**Addresses:** AUTPR-01, AUTPR-02
**Avoids:** CR-2 (idempotency guard), M-3 (gh auth preflight), M-7 (permissions block in cron template), MN-3 (short deterministic branch name)

### Phase 6: WIN-01 — `cli/conjure.ps1` PowerShell Shim

**Rationale:** No bash logic to implement; purely a Windows path detection and delegation file. Independent of Phases 1-5; placed sixth for serial execution. Its validation (Phase 7) requires it to exist.
**Delivers:** `cli/conjure.ps1` — Git Bash path candidates, WSL fallback, `@args` passthrough, `exit $LASTEXITCODE` on every path, `.gitattributes` `eol=crlf` entry.
**Addresses:** WIN-01
**Avoids:** CR-4 (exit code propagation), M-4 (CRLF line endings), M-6 (symlink resolution via `$PSCommandPath`)

### Phase 7: WIN-02 + DEBT-01 — CI Jobs

**Rationale:** Both are `.github/workflows/` YAML edits with no code dependencies on each other. WIN-02 requires `conjure.ps1` (Phase 6). DEBT-01 requires no new code.
**Delivers:** `windows-pwsh` job in `ci.yml` (shell: pwsh, exit code propagation assertion); retry-loop empty-check guard in `release.yml` ci-gate (60s timeout, 10s sleep, jq `select(.name != "Release") | length`).
**Addresses:** WIN-02, DEBT-01
**Avoids:** CR-4 (CI asserts exit code 2 propagates), M-1 (retry loop prevents false failure on check-run registration race)

### Phase Ordering Rationale

- Phases 1 and 2 are prerequisite cleanup costing under an hour combined; they prevent two correctness bug classes from propagating into new code
- Phase 3 (drift check) must precede Phase 5 (auto-PR) because AUTPR-01 consumes `--porcelain` output; out-of-order development means rewriting the PR body logic
- Phase 4 (resolve) must precede Phase 5 (auto-PR) so the complete user story is testable: apply → conflicts → resolve → clean PR
- Phases 6 and 7 are independent of the bash feature work and can be developed in parallel with Phases 3-5 if bandwidth allows
- The `mutate_rm` addition in Phase 2 addresses CR-5 structurally before any new mutation script is written — risk reduction at the library level, not the feature level

### Research Flags

Phases needing deeper research during planning:
- **Phase 3 (conjure check):** The `check_file_drift` function design (3-way drift classification without running `git merge-file`) is the most design-intensive piece of the milestone. The awk/diff mechanics are unspecified in the research files. Plan phase should prototype this function and verify the snapshot directory structure from `cmd_init` matches what `check-drift.sh` will expect.
- **Phase 5 (update --pr):** The interaction between `lib/merge.sh merge_user_files` and the new branch/commit/push flow needs a concrete integration test before the phase is marked complete. This flow has not previously been exercised end-to-end.

Phases with standard patterns (skip research-phase):
- **Phase 1 (DEBT-02):** Pure arg parser refactor in an already-read file.
- **Phase 2 (`mutate_rm`):** 10-line addition following an established pattern.
- **Phase 6 (conjure.ps1):** PowerShell shim pattern thoroughly documented in STACK.md with verified code.
- **Phase 7 (CI jobs):** YAML edits with patterns confirmed from existing `release.yml` and STACK.md.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | All v0.5.0 tools verified against official docs: `gh pr create` flag set, pwsh 7.5 semantics, GitHub check-runs API response shape. Zero new tools enter the stack. |
| Features | HIGH | Six features are well-scoped with clear table stakes. chezmoi/mise/Renovate comparator analysis confirms expected UX patterns. Feature dependencies explicitly mapped. |
| Architecture | HIGH | Existing codebase read directly (not inferred). All integration points verified: `lib/merge.sh` sidecar naming, `lib/mutate.sh` function signatures, `cli/conjure` dispatch table, `release.yml` ci-gate job structure. |
| Pitfalls | HIGH (CR-1 to CR-5, M-1 to M-4); LOW (M-6 PS symlink) | Critical pitfalls derived from direct codebase reading and official docs. PowerShell Homebrew symlink resolution (M-6) is inferred from PS docs, not tested against an actual Homebrew install. |

**Overall confidence:** HIGH

### Gaps to Address

- **`check_file_drift` function design:** PITFALLS.md CR-1 recommends this function but leaves the awk/diff mechanics unspecified. Plan phase for Phase 3 should include a concrete prototype and a test with a known user-edited file before implementation begins.
- **`conjure.ps1` Homebrew symlink resolution (M-6):** `$PSCommandPath` (PS 7.2+) resolves symlinks; this has not been tested against an actual Homebrew installation. Can be documented as a known v0.5.0 limitation and fixed in v0.5.1 if the macOS/Linux PS7 user base is small.
- **Conflict annotation count in PR body:** FEATURES.md identifies sidecar-count annotation in the PR body as a differentiator for `update --pr`, but the mechanism for exporting that count from `lib/merge.sh` during the `update-pr.sh` execution is not yet specified. Resolve during Phase 5 planning.

## Sources

### Primary (HIGH confidence)

- `cli/conjure` (full content, read 2026-05-26) — dispatcher, `cmd_update --check` lines 183-197, `cmd_publish_skill` dispatch, `TARGET_REPO` env var usage
- `lib/merge.sh` (full content, read 2026-05-26) — `merge_file_3way`, `write_merge_sidecar`, sidecar naming, diff3 label format
- `lib/mutate.sh` (full content, read 2026-05-26) — `mutate_mkdir`, `mutate_cp`, `mutate_write` patterns; `mutate_rm` confirmed absent
- `scripts/publish-skill.sh` (full content, read 2026-05-26) — `TARGET_REPO` env at line 22; `gh` degrade pattern at lines 129-144
- `.github/workflows/release.yml` (full content, read 2026-05-26) — ci-gate job structure, existing `gh api` check-runs query
- `.github/workflows/ci.yml` (full content, read 2026-05-26) — windows-test job; no `shell: pwsh` job present
- [gh pr create manual](https://cli.github.com/manual/gh_pr_create) — confirmed no `--push` flag; `--title`, `--body`, `--base` available
- [GitHub REST API check-runs](https://docs.github.com/en/rest/checks/runs) — `{total_count, check_runs[]}` response shape; `total_count: 0` when empty
- [Microsoft Learn: about_Pwsh 7.5](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_pwsh?view=powershell-7.5) — `$PSScriptRoot`, `$PSCommandPath`, `$IsWindows`, `?.` null-conditional, `@args`, `$LASTEXITCODE`

### Secondary (MEDIUM confidence)

- [chezmoi daily operations](https://www.chezmoi.io/user-guide/daily-operations/) — read-only check → visible diff → explicit apply UX model
- [mise outdated docs](https://mise.jdx.dev/cli/outdated.html) — columnar output, `--json` flag, actionable next-step model
- [Renovate pull requests docs](https://docs.renovatebot.com/key-concepts/pull-requests/) — one-PR-per-group, force-update existing branch, dedup pattern
- [gh cli/cli discussion #5792](https://github.com/cli/cli/discussions/5792) — confirmed `gh pr create` errors on existing PR
- [PowerShell/PowerShell issue #13501](https://github.com/PowerShell/PowerShell/issues/13501) — `$LASTEXITCODE` vs `$?` trap; `$ErrorActionPreference` interaction
- [GitHub Actions orgs/community #167194](https://github.com/orgs/community/discussions/167194) — check-run registration race on tag push; retry loop required
- [git-mergetool documentation](https://git-scm.com/docs/git-mergetool) — one-file-at-a-time conflict walk; `$VISUAL/$EDITOR` delegation model

### Tertiary (LOW confidence)

- [Argo CD diffing pitfalls](https://engineering.01cloud.com/2026/01/20/mastering-argo-cd-diffing-why-changes-go-unnoticed-and-how-to-fix-it/) — false positives from two-party vs three-party diff design (analogous pattern only)
- TTY detection pitfall pattern — `[ -t 0 ]` guard; silent default acceptance risk

---
*Research completed: 2026-05-26*
*Ready for roadmap: yes*
