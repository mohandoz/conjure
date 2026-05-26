# Pitfalls Research

**Domain:** Conjure v0.5.0 Auto-Update + Healthcheck — adding drift detection, auto-PR, conflict resolution, PowerShell entrypoint, ci-gate guard, and SKILL-04 arg migration to existing POSIX bash CLI
**Researched:** 2026-05-26
**Confidence:** HIGH for pitfalls derived directly from this codebase and official docs. MEDIUM for GitHub API rate limiting and PowerShell integration patterns (verified from gh CLI docs and official PS docs). LOW for specific `conjure.ps1` execution-context edge cases (inferred from cross-platform patterns, no prior PS5/PS7 parity testing in this codebase yet).

> **Scope note:** These pitfalls cover the **six v0.5.0 features** — DRIFT-01/02 (drift detection), AUTPR-01/02 (auto-PR), RESOLVE-01/02 (conflict resolution), WIN-01/02 (PowerShell entrypoint), DEBT-01 (ci-gate empty-check guard), DEBT-02 (SKILL-04 positional arg migration). Pitfalls already present in the working tree are annotated with the relevant file. Generic advice omitted.

---

## Critical Pitfalls

Mistakes in this section cause silent failures, data loss, or security regressions that are hard to detect and expensive to fix.

---

### Pitfall CR-1: `conjure check` compares templates directly — reports false drift for user-owned customizations

**What goes wrong:**
The existing `cmd_update --check` (cli/conjure:185-196) diffs `$CONJURE_HOME/templates/skills/*/SKILL.md` against the project's `.claude/skills/*/SKILL.md`. This correctly detects upstream changes, but the same diff produces false positives for legitimate user edits: a user who added project-specific instructions to a skill will see it reported as drifted on every `conjure check`, even though there is no actionable update available. The drift report becomes noise. Users start ignoring it, which is the exact failure mode drift detection must avoid.

**Why it happens:**
The diff has no concept of "user-made change" vs "upstream-not-yet-applied change." The merge base (`.conjure-templates-${pinned}`) exists for 3-way merge but is not consulted during `conjure check`. The check compares two parties (current vs upstream) when it needs three (base vs current, base vs upstream).

**Consequences:**
- Chronic false-positive reports cause alert fatigue; real drift gets ignored
- Users learn to run `conjure update --check` and dismiss results without reading
- Downstream: `conjure update --pr` opens PRs for files that have only user edits, not upstream changes

**Prevention:**
- `conjure check` must use the same three-way comparison as `cmd_update --apply`: compare `base → current` (user delta) vs `base → upstream` (upstream delta). A file is "drifted" only when the upstream delta is non-empty AND the base exists. If the base snapshot is missing, report "unknown" rather than "drifted."
- Implement a `check_file_drift` function in `lib/merge.sh` (parallel to `merge_file_3way`) that returns: `clean` / `user-only` / `upstream-only` / `both-changed` / `no-base`.
- The drift report must distinguish "upstream has new content" from "file differs from template" — these are different user actions.

**Detection (warning sign):**
Running `conjure check` on a repo where the user has made intentional edits and seeing those files listed as drifted, even when pinned version equals installed version.

**Phase to address:** DRIFT-01 — must be a success criterion: "zero false positives on a repo where user edits exist and pinned version equals current."

---

### Pitfall CR-2: `conjure update --pr` opens duplicate PRs on every cron run — no idempotency guard

**What goes wrong:**
`conjure update --pr` (AUTPR-01) will call `gh pr create` to open a PR. The optional GH Action template (AUTPR-02) adds a cron trigger, e.g. weekly. If the cron fires and a PR already exists (not yet merged or closed), `gh pr create` will error: "a pull request for branch X into Y already exists." The script exits non-zero, the CI job fails, and the team receives a failing cron notification — every week until someone merges the PR.

**Why it happens:**
`gh pr create` is not idempotent. It errors if a PR already exists for the branch+base pair. The script must check before creating. (Confirmed via GitHub CLI discussion #5792: "Currently, running gh pr create on a branch that already has a PR will error out.")

**Consequences:**
- Weekly CI cron job fails with noise, not a real problem
- Team learns to ignore cron failures — then misses real drift
- If the script uses `|| true` to suppress the error, the cron silently does nothing when drift exists

**Prevention:**
- Before `gh pr create`, always run: `existing=$(gh pr list --head "$BRANCH" --base main --json number --jq length)`. If `existing > 0`, skip creation and print "PR already open — no action needed."
- The GH Action template must include this guard as the first step after diff computation.
- The branch used for the PR must be deterministic and project-scoped (e.g., `conjure/update-${CONJURE_VERSION}`) so the guard works reliably across cron runs.

**Detection (warning sign):**
`conjure update --pr` run twice on the same repo with no merge in between causes a non-zero exit on the second run.

**Phase to address:** AUTPR-01 — the idempotency guard is a required gate, not an enhancement.

---

### Pitfall CR-3: `conjure resolve` invoked in CI (non-TTY) hangs or exits with confusing error

**What goes wrong:**
`conjure resolve` (RESOLVE-01) walks through diff3 conflict sidecars interactively, presenting each conflict and awaiting user input. If a user accidentally includes `conjure resolve` in a CI step, or a hook triggers it, the command blocks waiting for stdin that never comes. The CI job hangs until timeout. If the script uses `read` without a TTY guard, it silently reads empty input and "resolves" all conflicts by accepting defaults — silently corrupting CLAUDE.md or skill files.

**Why it happens:**
Interactive prompts using `read` in bash do not fail gracefully when stdin is not a TTY. The silent default-acceptance path is especially dangerous: `read -r -t 0 answer` with a timeout accepts empty string as the default choice, which can be "keep theirs" or "keep mine" — both wrong without user confirmation.

**Consequences:**
- CI job hangs (timeout-based failure, hard to diagnose)
- Worse: if silent default is taken, merged file is silently accepted with a wrong resolution
- Resolved sidecar is deleted; the corruption is permanent unless the backup is restored

**Prevention:**
- First line of `conjure resolve` must be a TTY guard: `[ -t 0 ] || { echo "conjure resolve requires an interactive terminal (stdin is not a TTY)"; exit 2; }`.
- Never use a silent timeout default for conflict resolution choices. All `read` prompts must have no default — require an explicit `y`, `n`, `mine`, or `theirs` input.
- The `exit 2` code (not `exit 1`) is correct per Conjure's hook convention for "hard prerequisite failure." Document this in the command's help text.
- Add a test in `tests/run.sh` that pipes non-TTY stdin to `conjure resolve` and asserts exit 2.

**Detection (warning sign):**
`echo "" | bash cli/conjure resolve` exits 0 or hangs.

**Phase to address:** RESOLVE-01 — TTY guard is a day-one requirement, not a later hardening step.

---

### Pitfall CR-4: `conjure.ps1` uses `$LASTEXITCODE` inconsistently — exit code 1 propagated where exit 2 expected

**What goes wrong:**
Conjure's bash hooks exit 2 (hard failure) vs 0 (success), never exit 1 (reserved for linting-style non-fatal). In PowerShell, when an external process exits, `$LASTEXITCODE` captures the numeric code, but PowerShell's own error-handling (`$ErrorActionPreference = 'Stop'`) may convert a non-zero `$LASTEXITCODE` into a terminating error with its own exit code (1) rather than preserving the original code. The `conjure.ps1` wrapper, if it calls `bash cli/conjure ...` internally, must explicitly pass through `exit $LASTEXITCODE` — otherwise it normalizes all failures to exit 1 regardless of what bash returned.

**Why it happens:**
PowerShell has two exit-code channels: `$LASTEXITCODE` (external process exit code) and `$?` (cmdlet success boolean). A `.ps1` that ends with a cmdlet call after an external command exits 2 will see `$? = $true` (the cmdlet succeeded) and exit 0. This is a known PowerShell trap (PowerShell/PowerShell issue #13501).

**Consequences:**
- Claude Code hook infrastructure reads exit 2 to decide "abort this operation." If `conjure.ps1` normalizes to 0, hooks never abort — safety guarantees fail silently on Windows.
- CI test on `windows-latest` with `shell: pwsh` passes even when the underlying bash hook would have blocked the operation.

**Prevention:**
- `conjure.ps1` must end every execution path with `exit $LASTEXITCODE`, not with a PowerShell cmdlet that resets `$?`.
- The CI Windows job (WIN-02) must assert exit codes explicitly: run a command that should exit 2, assert `$LASTEXITCODE -eq 2`.
- Add to the PS1 shim: `$ErrorActionPreference = 'Continue'` — do not use `Stop`, which re-throws and loses the original exit code.

**Detection (warning sign):**
On `windows-latest` with `shell: pwsh`, running `conjure.ps1 init /nonexistent` returns 0 instead of non-zero.

**Phase to address:** WIN-01 — must be the first thing tested before any other PowerShell work.

---

### Pitfall CR-5: New scripts for `conjure check`, `conjure resolve`, `conjure update --pr` bypass `lib/mutate.sh` — dry-run guarantee broken

**What goes wrong:**
All existing writes funnel through `lib/mutate.sh` (validated in v0.3.0, CI-guarded). v0.5.0 adds new scripts: a drift-check script, a resolve script, and a PR-creation script. If any of these scripts write files directly (`printf > file`, `cp`, `mv`) without sourcing `lib/mutate.sh`, they silently bypass the dry-run guard. `conjure check --dry-run` or `conjure resolve --dry-run` would actually mutate files instead of simulating.

**Why it happens:**
New scripts written under time pressure tend to skip the source-lib boilerplate, especially for "read-only" commands like `conjure check`. But conflict resolution sidecar cleanup (RESOLVE-02: "marks sidecars resolved and cleans them up") involves file deletion — `rm` is a mutation. If the resolve script calls `rm` directly without going through a `mutate_rm` wrapper, the dry-run guarantee is broken for deletions.

**Consequences:**
- `conjure resolve --dry-run` silently deletes conflict sidecars
- `conjure check` creates a temporary diff report file that is never cleaned up
- The existing CI raw-write guard (`grep -rn 'cp \|^>\|>> ' scripts/`) catches `cp` and `>` but not `rm` — the regression slips CI

**Prevention:**
- Add `mutate_rm` to `lib/mutate.sh` before writing any resolve script that deletes sidecars.
- Extend the CI raw-write guard to catch bare `rm ` calls in new scripts: `grep -rn 'rm ' scripts/cli/ | grep -v '# .*mutate' | grep -v 'rm -f "$_merge_list'` — tune to catch real violations.
- Sidecar cleanup (RESOLVE-02) must call `mutate_rm` not bare `rm`.

**Detection (warning sign):**
`conjure resolve --dry-run` reports zero mutations skipped but sidecars are gone from disk.

**Phase to address:** RESOLVE-02 and AUTPR-01 — both involve file writes/deletes; mutate.sh sourcing must be verified before each script is accepted.

---

## Moderate Pitfalls

Mistakes here cause incorrect behavior, CI failures, or user confusion, but do not cause data loss.

---

### Pitfall M-1: DEBT-01 ci-gate empty-check guard passes when tag is pushed before CI has registered any checks

**What goes wrong:**
The current ci-gate job (release.yml:7-25) queries `/commits/$sha/check-runs` and fails if any check failed. DEBT-01 adds a guard: "fail if zero check-runs exist." But there is a race: when a tag is pushed, the release workflow triggers before the CI workflow has registered its check-runs for that commit. The ci-gate job queries the API, gets zero results (CI hasn't started yet), and the new guard correctly catches the empty set — but this would also be true for the first few seconds after any legitimate tag push.

**Why it happens:**
GitHub Actions check-runs are registered asynchronously after a push. There is no guarantee the CI check-run is registered before the release workflow's ci-gate job starts, especially on a fresh tag push where CI must first be queued.

**Consequences:**
- ci-gate fails on every legitimate tag push for the first N seconds
- Developer pushes a tag, release fails, must re-run manually — wastes time
- Alternatively, adding a sleep workaround is fragile and cargo-culted

**Prevention:**
- The empty-check guard must poll with retries, not check once: loop for up to 60 seconds, sleep 10s between checks, fail only if zero check-runs are returned after the retry window.
- Pattern: `for i in 1 2 3 4 5 6; do count=$(gh api ...); [ "$count" -gt 0 ] && break; sleep 10; done; [ "$count" -eq 0 ] && { echo "FAIL: no check-runs registered after 60s"; exit 1; }`.
- Alternatively, require the CI job (not the release) to be what triggers the release tag logic — this architectural inversion avoids the race entirely but requires a workflow redesign.

**Detection (warning sign):**
Push a tag, observe the ci-gate job fail within the first 15 seconds with "zero check-runs found."

**Phase to address:** DEBT-01 — the retry loop must be part of the initial implementation, not a follow-up fix.

---

### Pitfall M-2: DEBT-02 SKILL-04 positional arg breaks callers that pass `TARGET_REPO` env var

**What goes wrong:**
The current `publish-skill.sh` accepts `TARGET_REPO` as an environment variable (scripts/publish-skill.sh:22, cli/conjure:309-310). DEBT-02 replaces this with a positional arg. Any caller — documentation, team scripts, CI pipelines, local aliases — that uses `TARGET_REPO=org/repo conjure publish-skill my-skill` will silently fail after the migration: `TARGET_REPO` will be ignored, the positional arg will be missing, and the script will either error (if the guard exists) or default to `mohandoz/conjure` (if the env fallback is left in place with no warning).

**Why it happens:**
The `TARGET_REPO` env var was an acknowledged shortcut ("fragile" — PROJECT.md:123). The temptation during the migration is to remove the env var path immediately. But this is a breaking change for anyone with `TARGET_REPO` in their shell profile or scripts, and they get no warning.

**Consequences:**
- Silent misbehavior: skill is published to the wrong repo (`mohandoz/conjure`) with no error
- Or: hard failure with no explanation of why `TARGET_REPO` no longer works
- Team CI pipelines that set `TARGET_REPO` start failing silently

**Prevention:**
- Keep the `TARGET_REPO` env var for one release cycle with a deprecation warning: if `TARGET_REPO` is set and no positional `--to` arg is given, print "WARN: TARGET_REPO env var is deprecated; use --to <org/repo> instead" and still use its value.
- In the release after that, remove the env fallback and fail with a clear message.
- The deprecation warning must appear in the script, in `conjure help publish-skill`, and in the CHANGELOG.
- CI must test both the old path (env var with deprecation warning) and the new path (positional `--to`).

**Detection (warning sign):**
`TARGET_REPO=some/repo conjure publish-skill my-skill` after the migration publishes to `mohandoz/conjure` with no warning.

**Phase to address:** DEBT-02 — the deprecation bridge must be in place before the env var is removed.

---

### Pitfall M-3: `conjure update --pr` requires `gh` auth — fails silently when `GITHUB_TOKEN` is not configured

**What goes wrong:**
`gh pr create` requires either an interactive `gh auth login` session or a `GITHUB_TOKEN` / `GH_TOKEN` environment variable. In CI, the GitHub Actions `GITHUB_TOKEN` is automatically available. But locally, a developer running `conjure update --pr` on a machine where `gh` is installed but not authenticated gets a cryptic error: "To get started with GitHub CLI, please run: gh auth login." This is confusing because `conjure update --pr` looks like a Conjure command, not a GitHub CLI command — the user doesn't know why GitHub auth is required.

**Why it happens:**
The existing `publish-skill.sh` checks `command -v gh` but does not check auth status (scripts/publish-skill.sh:129). The same pattern will carry over to the auto-PR script if copied without improvement.

**Consequences:**
- Developer runs `conjure update --pr`, gets an opaque `gh auth` error
- They assume Conjure is broken, not that GitHub CLI needs setup

**Prevention:**
- Before calling `gh pr create`, check auth: `gh auth status >/dev/null 2>&1 || { echo "conjure update --pr requires GitHub CLI authentication. Run: gh auth login"; exit 2; }`.
- The `conjure preflight` command should check `gh auth status` and warn if not configured, so the failure happens during setup, not at PR-creation time.
- Document the `GH_TOKEN` env var approach for CI use explicitly in the command's `--help` output.

**Detection (warning sign):**
`GH_TOKEN="" conjure update --pr` produces a `gh` error message, not a Conjure-formatted error.

**Phase to address:** AUTPR-01 — auth check is a prerequisite before any PR creation logic is written.

---

### Pitfall M-4: `conjure.ps1` CRLF line endings corrupt the bash script it delegates to on Git Bash

**What goes wrong:**
If `conjure.ps1` is written or committed with Windows CRLF line endings (`\r\n`), and a Git Bash user (WIN-01 scenario) sources or runs it through bash, bash sees the carriage return as part of the command name: `bash: $'\r': command not found`. This happens even if the `.ps1` extension prevents bash from executing it directly — if any test or CI step sources the file or uses it as a reference, the CRLF causes cryptic failures.

Additionally, if `conjure.ps1` calls `bash` with a heredoc or inline script, CRLF in the heredoc corrupts the bash arguments.

**Why it happens:**
Git on Windows may auto-convert LF to CRLF on checkout if `core.autocrlf=true` is set (common on Windows developer machines). A `.ps1` file committed with LF endings becomes CRLF on checkout — this is expected for PowerShell but corrupts any bash paths.

**Consequences:**
- `conjure.ps1` runs fine in native PowerShell, fails intermittently when inspected or processed by bash tooling
- CI on `windows-latest` with `shell: bash` that reads `conjure.ps1` gets CRLF artifacts

**Prevention:**
- Add `.gitattributes` rule: `conjure.ps1 text eol=crlf` (correct for PowerShell). All bash scripts keep `text eol=lf`. This is deterministic regardless of client `core.autocrlf` setting.
- `conjure.ps1` must never be sourced or processed by bash scripts — it is a standalone Windows entrypoint. Add a comment at the top of the file: `# Windows-only entrypoint. Do not source from bash.`
- The CI Windows job that tests `conjure.ps1` must use `shell: pwsh`, not `shell: bash`.

**Detection (warning sign):**
`file conjure.ps1` on a macOS/Linux checkout shows `CRLF line terminators` rather than `LF`.

**Phase to address:** WIN-01 — `.gitattributes` must be set before the first commit of `conjure.ps1`.

---

### Pitfall M-5: `conjure check` diff output is not machine-readable — downstream scripts can't parse it

**What goes wrong:**
The current `cmd_update --check` (cli/conjure:194-197) prints human-readable text: `"~ skills/SKILL-03/SKILL.md (changed upstream)"`. If AUTPR-01 needs to consume the drift report to decide which files to include in the PR diff, it must parse this human text — a fragile coupling. A change to the check output format (e.g., adding color codes, adding a count line, changing the `~` prefix) silently breaks the auto-PR script.

**Prevention:**
- `conjure check` must support a `--json` or `--porcelain` output mode that emits machine-readable drift data (e.g., `{"file": "skills/SKILL-03/SKILL.md", "status": "upstream-changed"}`). The human-readable format remains the default.
- `conjure update --pr` uses `conjure check --porcelain` internally, not text parsing.
- Document the `--porcelain` format as stable; the human-readable format may change without notice.

**Phase to address:** DRIFT-02 (delta report output format) — design the machine-readable format before AUTPR-01 is implemented, because AUTPR-01 depends on it.

---

### Pitfall M-6: `conjure.ps1` path resolution fails when Conjure is installed via Homebrew (macOS/Linux PS7)

**What goes wrong:**
PowerShell 7 runs on macOS and Linux. A developer using PS7 on macOS who runs `conjure.ps1` may have Conjure installed via Homebrew, where `cli/conjure` is symlinked to `/opt/homebrew/bin/conjure` and `CONJURE_HOME` points to the Homebrew Cellar. The `conjure.ps1` shim, if it computes `CONJURE_HOME` relative to the `.ps1` file's location (`$PSScriptRoot/../`), will compute the wrong path when the script is in a different location than the Homebrew install.

**Prevention:**
- `conjure.ps1` must resolve `CONJURE_HOME` the same way `cli/conjure` does: by following the symlink to the real script location, then resolving `..` from there. Use `$PSCommandPath` (resolves symlinks in PS7.2+) not `$PSScriptRoot` (does not follow symlinks).
- Test path resolution explicitly: install via Homebrew symlink, run `conjure.ps1 version`, assert it finds the correct templates.

**Phase to address:** WIN-01.

---

### Pitfall M-7: GH Action cron template for auto-PR commits using the default `GITHUB_TOKEN` — no write permission

**What goes wrong:**
GitHub Actions' `GITHUB_TOKEN` has read-only permissions by default on public repos since 2023. A cron job that pushes a branch and creates a PR needs `contents: write` and `pull-requests: write` permissions. If the cron template (AUTPR-02) omits the `permissions:` block, the push and PR creation fail with "remote: Permission to ... denied to github-actions[bot]."

**Prevention:**
- The GH Action cron template must include:
  ```yaml
  permissions:
    contents: write
    pull-requests: write
  ```
- Document that a repo-scoped PAT with `contents` and `pull-requests` write scope is needed for private repos (the default GITHUB_TOKEN may have restrictions under org policies).

**Phase to address:** AUTPR-02.

---

## Minor Pitfalls

Small issues that cause confusion or minor friction but are easy to detect and fix.

---

### Pitfall MN-1: `conjure check` exits 0 when no drift found but also exits 0 when base snapshot is missing — caller can't distinguish

**What goes wrong:**
If `conjure check` exits 0 for both "up to date" and "cannot check (no base snapshot)," scripts that run `conjure check && echo "safe to proceed"` proceed incorrectly in the no-snapshot case.

**Prevention:**
- Use distinct exit codes: 0 = up to date, 1 = drift found, 2 = cannot check (missing snapshot or prerequisite). Document these in `conjure help check`.

**Phase to address:** DRIFT-01.

---

### Pitfall MN-2: Conflict sidecar filename collisions for skills with similar names

**What goes wrong:**
`write_merge_sidecar` (lib/merge.sh:64) replaces `/` with `_` in the relative path to form the sidecar name. Two skills named `code-review` and `code_review` would produce the same sidecar name `.conjure-conflict-skills_code-review_SKILL.md` (hyphen vs underscore collapse if the tr command normalizes both). This is unlikely but could silently overwrite one sidecar with another.

**Prevention:**
- Skill naming convention already requires `^[a-z][a-z0-9-]{1,40}$` (no underscores). Document this as the reason: underscores in skill names are rejected to prevent sidecar collisions.
- The `conjure resolve` script must verify sidecar uniqueness before starting the interactive session.

**Phase to address:** RESOLVE-01.

---

### Pitfall MN-3: `conjure update --pr` branch name contains the Conjure version — long version strings exceed GitHub's 255-char branch limit

**What goes wrong:**
A branch name like `conjure/update-0.5.0-20260526` is fine. But if the branch name includes the full diff summary or a list of changed files, it can exceed GitHub's 255-character branch name limit, causing `git push` to fail.

**Prevention:**
- Branch name must be deterministic and short: `conjure/update-v${CONJURE_VERSION}` only. No file names in the branch name.

**Phase to address:** AUTPR-01.

---

### Pitfall MN-4: `conjure resolve` deletes sidecars before user confirms the merged result is correct

**What goes wrong:**
RESOLVE-02 says "marks sidecars resolved and cleans them up after confirmation." If the confirmation prompt asks "Is this resolved? [y/N]" and the user types `y` before viewing the resulting file, the sidecar is deleted. The user then opens the resolved file and finds the merge was wrong — but the backup and the sidecar are gone.

**Prevention:**
- The resolve flow must: (1) show the merged result, (2) ask the user to open the file and verify, (3) only delete the sidecar after a second explicit confirmation. Never auto-delete on the first `y`.
- Print the backup path before starting resolution: "Your original files are backed up at `.claude.backup-TIMESTAMP`."

**Phase to address:** RESOLVE-02.

---

## Phase-to-Pitfall Mapping

| Phase | Feature | Critical Pitfalls | Moderate Pitfalls | Minor Pitfalls |
|-------|---------|-------------------|-------------------|----------------|
| DRIFT-01 | `conjure check` implementation | CR-1 (false drift positives) | M-5 (machine-readable output needed by AUTPR) | MN-1 (exit code ambiguity), MN-2 (sidecar collision) |
| DRIFT-02 | Drift report format | — | M-5 (design --porcelain before AUTPR-01) | MN-1 |
| AUTPR-01 | `conjure update --pr` | CR-2 (duplicate PR idempotency), CR-5 (mutate.sh bypass) | M-3 (gh auth preflight), M-7 (GH_TOKEN write permissions) | MN-3 (branch name length) |
| AUTPR-02 | GH Action cron template | — | M-7 (permissions block required) | — |
| RESOLVE-01 | `conjure resolve` interactive | CR-3 (TTY guard), CR-5 (mutate.sh / mutate_rm) | — | MN-2 (sidecar collisions), MN-4 (early sidecar delete) |
| RESOLVE-02 | Sidecar cleanup | CR-5 (mutate_rm required) | — | MN-4 (two-step confirmation) |
| WIN-01 | `conjure.ps1` entrypoint | CR-4 (exit code propagation) | M-4 (CRLF line endings), M-6 (Homebrew symlink path resolution) | — |
| WIN-02 | CI pwsh matrix job | CR-4 (exit code assertion in CI) | M-4 (shell: pwsh not shell: bash for PS tests) | — |
| DEBT-01 | ci-gate empty-check guard | — | M-1 (race condition, retry loop required) | — |
| DEBT-02 | SKILL-04 positional arg | — | M-2 (deprecation bridge for TARGET_REPO) | — |

---

## Pre-Existing Technical Debt that Creates Pitfall Surface in v0.5.0

| Debt | Where | Risk Surface | Must Address Before |
|------|-------|-------------|---------------------|
| `cmd_update --check` does 2-way diff, not 3-way | cli/conjure:185 | CR-1 false positives on every check | DRIFT-01 |
| `publish-skill.sh` uses `TARGET_REPO` env var | scripts/publish-skill.sh:22 | M-2 silent migration break | DEBT-02 |
| No `mutate_rm` in `lib/mutate.sh` | lib/mutate.sh | CR-5 dry-run bypass for sidecar deletions | RESOLVE-02 |
| ci-gate: no empty-check-runs guard | .github/workflows/release.yml:7 | M-1 race condition + new DEBT-01 requirement | DEBT-01 |
| `compatibility.platforms` in `marketplace.json` does not list `windows` | .claude-plugin/marketplace.json | WIN-01 must not add `windows` until PS1 is validated | WIN-01 post-validation |
| Windows CI uses only `shell: bash` (Git Bash) | .github/workflows/ci.yml:windows-test | WIN-02 — no native pwsh test coverage exists yet | WIN-02 |

---

## Sources

- Conjure working tree (HIGH — primary source): `cli/conjure:160-258` (`cmd_update`), `lib/merge.sh` (sidecar logic), `lib/mutate.sh` (mutation chokepoint), `scripts/publish-skill.sh:22` (`TARGET_REPO` env var), `.github/workflows/release.yml` (ci-gate), `.github/workflows/ci.yml` (windows-test job), `.planning/PROJECT.md` (DEBT-02 acknowledgment at line 123)
- [gh pr create duplicate PR discussion (cli/cli #5792)](https://github.com/cli/cli/discussions/5792) (MEDIUM — GitHub CLI community; `gh pr create` errors on existing PR, no idempotent create-or-update)
- [GitHub Actions rate limiting — cazzulino.com](https://www.cazzulino.com/github-actions-rate-limiting.html) (MEDIUM — community; 1000 req/hour for `GITHUB_TOKEN`, batch failures can exhaust limits)
- [GitHub API rate limiting workaround for Actions](https://gist.github.com/lcatlett/dba23f8dcda6892e048ec4887df85258) (MEDIUM — community; retry patterns for check-run queries)
- [PowerShell exit code bug (PowerShell/PowerShell #13501)](https://github.com/PowerShell/PowerShell/issues/13501) (MEDIUM — official GitHub issue; PowerShell CLI exits with 1 rather than the external process's code)
- [Native Commands in PowerShell — PowerShell Team blog](https://devblogs.microsoft.com/powershell/native-commands-in-powershell-a-new-approach/) (MEDIUM — official Microsoft blog; `$LASTEXITCODE` vs `$?` distinction, `$ErrorActionPreference` interaction)
- [Cross-platform PowerShell tips — powershell.org](https://powershell.org/2019/02/tips-for-writing-cross-platform-powershell-code/) (MEDIUM — community; path separator, `Join-Path`, CRLF/LF behavior)
- [GitHub Actions status checks — orgs/community discussion #167194](https://github.com/orgs/community/discussions/167194) (MEDIUM — GitHub community; check-run registration race condition on tag push)
- [TTY detection pitfalls — Medium](https://medium.com/@haroldfinch01/understanding-and-resolving-the-error-the-input-device-is-not-a-tty-75199ab2344d) (MEDIUM — community; `[ -t 0 ]` guard pattern, silent default acceptance risk)
- [Argo CD diffing pitfalls — engineering.01cloud.com](https://engineering.01cloud.com/2026/01/20/mastering-argo-cd-diffing-why-changes-go-unnoticed-and-how-to-fix-it/) (LOW — infra-tool analog; false positives from two-party vs three-party diff design, strategy for "user-only" vs "upstream-only" changes)
- [about_Pwsh — Microsoft Learn](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_pwsh?view=powershell-7.5) (HIGH — official Microsoft docs; `$PSCommandPath` symlink resolution, `$PSScriptRoot` behavior)

---

*Pitfalls research for: Conjure v0.5.0 Auto-Update + Healthcheck*
*Researched: 2026-05-26*
