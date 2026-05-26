# Feature Research — v0.5.0 Auto-Update + Healthcheck

**Domain:** CLI harness auto-update, drift detection, and cross-platform entrypoint for Conjure (POSIX bash + Node.js .mjs)
**Researched:** 2026-05-26
**Milestone:** v0.5.0 — Auto-Update + Healthcheck
**Confidence:** HIGH for drift-detection and auto-PR patterns (chezmoi, mise, renovate verified); HIGH for PowerShell shim (official PS docs + cross-platform community); MEDIUM for interactive conflict resolution UX (design choice area); HIGH for SKILL-04 positional arg refactor (existing code verified directly)

---

## How Similar Tools Handle These Problems

Before feature-by-feature analysis, the comparator tools reveal strong user expectations:

**chezmoi (dotfiles manager):** Splits the concern into `chezmoi diff` (read-only drift report) and `chezmoi apply` (mutate). Users check before they commit. No surprises. The `chezmoi update` command combines pull + apply into one for the trusting user. The diff output shows file-level additions and removals with unified diff format. Conflict handling is delegated to git during rebase.

**mise (version manager):** `mise outdated` shows a table: Plugin / Requested / Current / Latest. Clean, actionable, exits 0. Next step is unambiguous: `mise upgrade`. Exit code and output are designed for scripting. The `--json` flag exists for programmatic consumption.

**Renovate (dependency update bot):** Creates one PR per dependency group, keeps it open, force-pushes to the same branch when newer versions arrive (does not spam). Has a Dependency Dashboard issue that lists all pending updates. PR body contains a structured diff with the version delta and links. If a PR is closed without merging, the dashboard marks it "ignored" — user must re-enable explicitly.

**Dependabot:** Simpler model: creates individual PRs per dep, reopens if needed, can flood repos with many PRs. Users prefer Renovate's grouping and dedup behavior for this reason.

**Key pattern from all four:** Read-only check → visible diff → explicit apply. Never mutate silently. Never flood with PRs. One source of truth for pending state.

---

## Feature 1: `conjure check` — Drift Detection (DRIFT-01, DRIFT-02)

### Context

`conjure update --check` already exists and compares installed files against current upstream templates. The new `conjure check` command is a distinct, higher-level operation: compare the *installed harness* against what Conjure would install at the *current upstream version*. This answers "is my harness stale?" not "are my files different from the template?"

The distinction matters: `update --check` compares file contents. `conjure check` should also detect structural drift: missing files, extra files, version mismatch, schema version mismatch. It is the health dashboard for the harness.

### Table Stakes

| Feature | Why Expected | Complexity | Dependencies |
|---------|--------------|------------|--------------|
| File-level delta: added / modified / removed relative to upstream | Users need to know which files need attention. Without this, "harness is stale" is not actionable. Mise's outdated table is the model: show what's different, not just "something changed." | LOW — extend existing `update --check` loop to also detect files present upstream but absent locally, and files present locally but not in upstream | Existing `cmd_update --check` in `cli/conjure` |
| Version mismatch surfaced first | The `.conjure-version` pin vs current `CONJURE_VERSION` is the cheapest check. If they match, skip the diff entirely (fast exit). | LOW — already done in `cmd_update`; `conjure check` reuses this gate | `.claude/.conjure-version` |
| Exit code 0 = healthy, 1 = drift detected | Scripts and CI need a machine-readable signal. `mise outdated` exits 0 (informational), but for Conjure `check` in CI the useful signal is: drift exists. | LOW — count deltas; exit 1 if any found, 0 if none | Standard POSIX exit code semantics |
| Human-readable summary line: "N files differ. Run conjure update --apply to merge." | The next step must be printed explicitly. No dead-end output. chezmoi always follows diff with the apply command. | LOW — add a summary line | None |
| `--json` flag for machine-readable output | CI scripts and integrations (e.g., the GH Action cron) need to parse drift results. `mise outdated --json` proves this is expected. | LOW — serialize delta list as JSONL/JSON to stdout | `jq` already a hard dep for reading output |

### Differentiators

| Feature | Value Proposition | Complexity | Dependencies |
|---------|-------------------|------------|--------------|
| Schema version check: detect when `.claude/settings.json` hook schema has changed upstream | Settings schema changes are a silent breakage vector (hooks stop firing). A check that detects schema version drift before it causes problems is uniquely valuable for Conjure. | MEDIUM — compare `schemaVersion` field in installed `.claude/settings.json` vs upstream template | Upstream template must carry a schemaVersion field |
| Overlay drift detection: flag when installed overlay has drifted from the overlay repo HEAD | Orgs that use `conjure refresh-overlay` need to know when their overlay is stale too. | MEDIUM — read `.claude/.conjure-overlay` marker; `git ls-remote` to check current overlay HEAD vs pinned SHA | `conjure refresh-overlay` marker file; git |
| `conjure check --ci` mode: structured output for dashboard PR body | The cron-triggered GH Action (AUTPR-02) needs check output formatted as a PR body section. `--ci` emits markdown-formatted table. | LOW — alternate output format when flag is present | None |

### Anti-Features

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| Mutating anything during `conjure check` | Violates the "check is read-only" contract. Users trust check to be safe to run at any time, including in CI audits. | Keep check pure read; all mutation goes through `update --apply` |
| Checking only version string, not file contents | Version match does not guarantee file content match (especially after manual edits). Must diff actual files. | Always do the file-level diff pass even when versions match; just optimize the order |
| Printing a wall of diff hunks | Overwhelming output teaches users to ignore it. mise's columnar table is the right model: file path, status, one line each. | Print one line per file: `~ SKILL.md (upstream changed)`, `+ hooks/new-hook.mjs (missing locally)` |
| Autorunning update when drift is found | Silent mutation is the opposite of what trust-first means. | Always stop at the report; require explicit `conjure update --apply` |

### Expected UX

```
$ conjure check
Project:        v0.4.0  →  Current kit: v0.5.0

  ~ skills/GSD-EXECUTE/SKILL.md   (upstream updated)
  + skills/GSD-NEW-SKILL/SKILL.md (missing locally — added in v0.5.0)
  ~ .claude/settings.json         (schema version changed)

3 file(s) differ. Run 'conjure update --apply' to merge.
```

Exit code 1. In CI: same output, exit 1 fails the check job cleanly.

---

## Feature 2: `conjure update --pr` — Auto-PR (AUTPR-01, AUTPR-02)

### Context

This turns the drift detection + merge into a GitHub PR, enabling async review of harness updates before they land. The workflow: detect drift → create a branch → apply the 3-way merge on that branch → open a PR via `gh pr create`. The optional GH Action cron template makes this fully automated.

Renovate is the model: one open PR per harness update, force-updated if a newer kit ships before the first PR is merged. Never open a second PR if one is already open.

### Table Stakes

| Feature | Why Expected | Complexity | Dependencies |
|---------|--------------|------------|--------------|
| Creates a branch `conjure/update-v<N>`, applies merge, opens PR via `gh pr create` | The core action. Without it, the feature doesn't exist. `gh` is already a soft dep (used in `publish-skill`). | MEDIUM — branch creation + `git commit` + `gh pr create`; all git primitives already in use | `gh` CLI (soft dep; print instructions if absent); `git` (hard dep) |
| Deduplication: if a `conjure/update-*` PR is already open, skip (or force-update the branch) | Renovate's most important behavior. Opening a second PR when one is already open creates confusion and merge conflicts. | MEDIUM — `gh pr list --head conjure/update-*` to check before creating; if found, `git push --force-with-lease` to update branch | `gh` CLI |
| PR body includes: version delta, file list, link to CHANGELOG | Users reviewing the PR need context. Without the file list and version delta in the body, the PR is opaque. Renovate always puts the update context in the PR body. | LOW — format PR body as markdown in the `gh pr create --body "..."` call | `conjure check --ci` output |
| `--base <branch>` flag to target a non-default branch | Teams that maintain `develop` or `release` branches as the merge target need this. | LOW — pass through to `gh pr create --base` | None |
| `--dry-run` shows the PR body + branch name without pushing | Consistent with all other Conjure mutations. | LOW — honor `DRY_RUN`; print what would be pushed/opened | `lib/mutate.sh` |
| Meaningful PR title: "chore(conjure): update harness v0.4.0 → v0.5.0" | PR titles visible in dashboards must be immediately identifiable. Renovate-style titles are the norm. | LOW — template the title with version numbers | `CONJURE_VERSION` and pinned version |

### Differentiators

| Feature | Value Proposition | Complexity | Dependencies |
|---------|-------------------|------------|--------------|
| GH Action cron template (AUTPR-02): ships as `templates/github/conjure-auto-update.yml` | Teams get automated harness maintenance by copying one file. The template uses the weekly Monday 9AM cron pattern established by Renovate. | LOW — write the template; no runtime code change | `conjure update --pr` working (AUTPR-01) |
| PR labels: `conjure`, `maintenance` auto-applied | PR categorization and automation (e.g., auto-merge if CI passes + label matches) requires labels. | LOW — `gh pr create --label conjure,maintenance` | Labels must exist in the target repo; document how to create them |
| Conflict annotation in PR body: if merge had conflicts, list the sidecar files and explain resolution | PR reviewer needs to know that `conjure resolve` is the next step before merging. | LOW — collect `CONJURE_MERGE_CONFLICT_COUNT`; add a "Conflicts requiring resolution" section to PR body if > 0 | `lib/merge.sh` sidecar tracking |
| `--reviewer <handle>` passthrough to `gh pr create` | Teams have designated harness maintainers. Auto-requesting their review reduces triage overhead. | LOW — pass through to `gh pr create --reviewer` | None |

### Anti-Features

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| Opening a PR per changed file | N files = N PRs. This is the Dependabot flood pattern that users hate. Renovate fixed this by grouping. Conjure should group the entire harness update in one PR. | One PR covers all changed files in the update |
| Auto-merging the PR | Even if CI passes and no conflicts exist, auto-merging removes the human review gate. The harness is the foundation for all Claude Code behavior — it must be reviewed. | Print "merge when ready" in the PR body; never auto-merge from within conjure |
| Pushing to the default branch directly | Any push to main/master without a PR bypasses review. The PR model exists for a reason. | Always create a branch; always open a PR; never push to default branch |
| Requiring a `conjure publish` flow for the PR | Auto-PR is a local-repo operation, not a marketplace operation. These concerns must not be conflated. | `update --pr` only touches the target project repo; `publish` is for the kit itself |
| Hard failing when `gh` is absent | Not all users have `gh` installed. The same "print, don't auto-run" principle from publish-skill applies. | Print the equivalent manual steps (branch, commit, PR URL pattern) when `gh` is absent |

### Expected UX

```
$ conjure update --pr
▸ Checking for existing update PR…
  No open conjure/update-* PR found.
▸ Applying 3-way merge: v0.4.0 → v0.5.0
  ✓ skills/GSD-EXECUTE/SKILL.md merged cleanly
  ✓ skills/GSD-NEW-SKILL/SKILL.md added
  ! .claude/settings.json — 1 conflict → .conjure-conflict-_claude_settings.json
▸ Committing to branch conjure/update-v0.5.0
▸ Opening PR…
  https://github.com/org/repo/pull/42

  PR body includes: version delta, file list, conflict resolution instructions.
```

---

## Feature 3: `conjure resolve` — Guided Interactive Conflict Resolution (RESOLVE-01, RESOLVE-02)

### Context

When `conjure update --apply` or `--pr` produces conflicts, it leaves `.conjure-conflict-*` sidecar files next to the originals. Currently, the user must find these files manually, understand the diff3 markers, resolve them, delete the sidecars, and manually stamp the version. `conjure resolve` wraps this into a guided walk.

The model is `git mergetool`: it iterates conflict files one by one, opens the user's editor (or a simple CLI prompt for each), and tracks completion. Unlike `git mergetool`, Conjure's conflicts are in named sidecar files, not the live files — so the workflow is: view sidecar → decide → write resolution → confirm → move to next.

### Table Stakes

| Feature | Why Expected | Complexity | Dependencies |
|---------|--------------|------------|--------------|
| Lists all `.conjure-conflict-*` sidecars in the project | The user must know what needs resolving. A summary list before starting is the minimum. chezmoi always shows what will be touched before touching it. | LOW — `find .claude -name '.conjure-conflict-*'` | Existing sidecar naming convention from `lib/merge.sh` |
| Opens each sidecar in `$VISUAL` or `$EDITOR` (or falls back to `cat`) | The actual resolution happens in the user's editor. Conjure should not attempt to build a TUI — that would exclude CI and non-interactive shells. The git mergetool model (open editor, wait, continue) is the right approach. | LOW — `${VISUAL:-${EDITOR:-cat}} "$sidecar"` per file; wait for editor to exit | Standard POSIX env var chain |
| After each edit, confirm with y/n: "Resolved? [y/n]" | Prevents accidental advancement to the next file before resolution is complete. | LOW — read from stdin; default to 'n' (safe default) | None |
| On confirmation, copy sidecar content to the live file and delete the sidecar | The resolution is committed: overwrite the original file with the resolved sidecar, then clean up. All writes through `lib/mutate.sh`. | LOW — `mutate_cp sidecar live_file && rm sidecar` | `lib/mutate.sh` |
| After all sidecars resolved, prompt to stamp the new version | The version stamp is the final gate. If the user walks away mid-session, the stamp is not written — they can resume. | LOW — check `CONJURE_MERGE_CONFLICT_COUNT` equivalent; if zero sidecars remain, offer to write `.conjure-version` | `.claude/.conjure-version` |
| `--dry-run` lists sidecars without opening editor or writing | Consistent with rest of CLI. | LOW — honor `DRY_RUN` | `lib/mutate.sh` |

### Differentiators

| Feature | Value Proposition | Complexity | Dependencies |
|---------|-------------------|------------|--------------|
| Prints the conflict context summary before opening editor: original file path, version delta, number of conflict hunks | Users need context to make an informed resolution choice. Printing "3 conflict hunks between your version and v0.5.0 upstream in SKILL.md" is more actionable than just opening a file cold. | LOW — grep `<<<<<<<` count in sidecar before opening | None |
| `--file <name>` to resolve a single sidecar (not the full walk) | Users who want to resolve one file at a time (e.g., after consulting a colleague about a specific conflict) need this escape hatch. | LOW — filter sidecar list by name prefix | None |
| Skip option per file: press 's' to defer this sidecar | Not every conflict must be resolved in one session. Skip lets the user defer a hard decision without losing the work done on easier files. | LOW — add 's' to the y/n prompt; leave the sidecar in place | None |
| Summary at end: "3 resolved, 1 skipped. Run 'conjure resolve' again to finish." | Closes the loop. Users know the session's outcome. | LOW — track resolved/skipped counts; print summary | None |

### Anti-Features

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| Building a TUI (curses, dialog, fzf) | Breaks non-interactive CI; adds a runtime dep; excludes users without those tools. The editor is already the standard conflict resolution UX. | `$VISUAL/$EDITOR` with blocking wait; fall back to `cat` for viewing in CI |
| Auto-resolving conflicts (always-ours or always-theirs) | Silently discards either user work or upstream improvements. This is the worst possible default for a harness that governs AI behavior. | Never auto-resolve; always require explicit human confirmation |
| Resolving conflicts in-place on the live file (no sidecar model) | The existing sidecar model is the right design: the live file is untouched until resolution is confirmed. Changing this would require a migration of the existing conflict contract. | Keep the sidecar model; `conjure resolve` works with it, not against it |
| Requiring a specific merge tool installed (vimdiff, meld, etc.) | Not available in all environments. The `$EDITOR` chain is universal. | `${VISUAL:-${EDITOR:-cat}}`; document mergetool as an option in help text |
| Deleting sidecars before user confirms resolution | Data loss. If the editor crashes or the user hits ctrl-C, the resolved content must not be lost before it's been confirmed. | Write to a temp file first; only delete sidecar on explicit 'y' confirmation |

### Expected UX

```
$ conjure resolve
Found 2 conflict sidecar(s):
  1. .claude/.conjure-conflict-_claude_CLAUDE.md
  2. .claude/skills/GSD-EXECUTE/.conjure-conflict-skills_GSD-EXECUTE_SKILL.md

[1/2] CLAUDE.md — 2 conflict hunk(s) between your version and v0.5.0
Opening in $EDITOR...
[editor closes]
Resolved? [y/n/s(kip)]: y
  ✓ CLAUDE.md resolved and updated.

[2/2] skills/GSD-EXECUTE/SKILL.md — 1 conflict hunk(s) between your version and v0.5.0
Opening in $EDITOR...
Resolved? [y/n/s(kip)]: s
  ↷ Skipped. Sidecar left in place.

Summary: 1 resolved, 1 skipped.
Run 'conjure resolve' again to finish the remaining sidecar.
```

---

## Feature 4: `conjure.ps1` — Native PowerShell Entrypoint (WIN-01, WIN-02)

### Context

Conjure's current Windows story is: use Git Bash or WSL for the bash CLI; use Node.js `.mjs` hooks for native Windows hooks. The gap is that Windows developers who open a PowerShell (or pwsh) terminal cannot run `conjure` — they must know to switch to Git Bash. `conjure.ps1` is a thin PowerShell shim that detects whether Git Bash is available, and if so, delegates to the bash entrypoint; if not, prints a clear error and install hint.

The shim model is established: it is how tools like `npm.cmd`, `yarn.cmd`, and language version managers (asdf on Windows, mise Windows wrapper) handle the "bash tool on Windows" problem. The shim does not reimplement the tool in PowerShell — it bridges to bash.

### Table Stakes

| Feature | Why Expected | Complexity | Dependencies |
|---------|--------------|------------|--------------|
| `conjure.ps1` locates the bash entrypoint and delegates via Git Bash | The minimum viable shim: `& "C:\Program Files\Git\bin\bash.exe" "$PSScriptRoot\cli\conjure" @args`. All arguments pass through unchanged. | LOW — standard PS shim pattern; 10-20 lines | `cli/conjure` must be on a path accessible from Git Bash |
| Falls back to WSL `bash` if Git Bash is not found at the standard path | WSL2 is installed on many modern Windows machines. Using it as a fallback broadens coverage without requiring Git Bash. | LOW — `wsl bash "$PSScriptRoot/cli/conjure" @args` if git-bash.exe absent | WSL2 installed |
| Prints a clear error and install hint when neither Git Bash nor WSL is found | No cryptic failure. The "print, don't auto-run" principle: tell the user what to install. | LOW — `Write-Error` + link to Git for Windows download | None |
| Passthrough of all arguments and exit codes | The shim must be transparent. `conjure check --json` piped into `jq` must work from PowerShell. Exit codes must propagate correctly from bash to PowerShell (`$LASTEXITCODE`). | LOW — `@args` passthrough + `exit $LASTEXITCODE` | None |
| CI job: `windows-latest` with `shell: pwsh` that calls `conjure.ps1` | WIN-02 proves the shim works in CI. The existing Windows CI job uses `shell: bash` (Git Bash). Adding a `pwsh` job proves native PowerShell. | LOW — add a matrix entry to `.github/workflows/ci.yml` | `conjure.ps1` shipped; GITHUB_TOKEN |

### Differentiators

| Feature | Value Proposition | Complexity | Dependencies |
|---------|-------------------|------------|--------------|
| `conjure.ps1` auto-detects git-bash.exe via registry (`HKLM:\SOFTWARE\GitForWindows`) if not at standard path | Git for Windows can be installed at non-default paths (e.g., Scoop installs it under `~\scoop\apps\git`). Registry-based detection is more robust. | MEDIUM — PowerShell registry access is simple (`Get-ItemProperty`); adds ~5 lines | None (registry access is a PS built-in) |
| `conjure.ps1` hints at `winget install Git.Git` when Git Bash is absent | Winget is the Windows package manager standard; it is pre-installed on Windows 11. The hint is the same "print, don't run" pattern, now Windows-idiomatic. | LOW — add `winget install Git.Git` to the error message | None |
| Document the `conjure.ps1` flow in README Windows section | Without documentation, Windows users won't know the shim exists. | LOW — doc edit | `conjure.ps1` shipped |

### Anti-Features

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| Reimplementing the bash CLI in PowerShell | Massive maintenance burden; two surfaces to keep in sync; inevitable divergence. The shim model exists precisely to avoid this. | Thin shim that delegates to bash; `.mjs` for the parts that must be native on Windows (hooks) |
| Silently shadowing failures from bash in the shim | If `cli/conjure` exits 1, `conjure.ps1` must exit 1. PowerShell has `$LASTEXITCODE` for this. | Always `exit $LASTEXITCODE` after invoking bash |
| Using PowerShell 5.1 (Windows PowerShell) as the only target | PS 5.1 is pre-installed but shows its age; PS 7 (pwsh) is the cross-platform version and is what `shell: pwsh` uses in GitHub Actions. | Target PS 7 (`pwsh`) for CI; document PS 5.1 as "untested but likely works" |
| Invoking `wsl` without checking if it is enabled | WSL2 may be installed but the distro not configured, causing a long timeout. | Check `wsl --list --quiet` exit code before using WSL as a fallback; timeout quickly if it fails |

### Expected UX

```powershell
PS C:\myrepo> conjure.ps1 check
Project:        v0.4.0  →  Current kit: v0.5.0

  ~ skills/GSD-EXECUTE/SKILL.md   (upstream updated)

1 file(s) differ. Run 'conjure update --apply' to merge.
```

From a CI perspective (`shell: pwsh`), `$LASTEXITCODE` is 1 and the job fails cleanly.

---

## Feature 5: ci-gate Empty-Check Guard (DEBT-01)

### Context

The ci-gate job in `release.yml` runs CI checks before allowing a release. The current gap: if a tagged commit has zero GitHub check-runs (e.g., a tag pushed directly without a preceding CI run), ci-gate passes vacuously — it sees no failures because there are no checks. This is a safety hole: a broken release could ship if tagged without a preceding CI run.

### Table Stakes

| Feature | Why Expected | Complexity | Dependencies |
|---------|--------------|------------|--------------|
| ci-gate fails if it finds zero check-runs for the tagged commit SHA | A gate that passes vacuously is not a gate. This is a correctness fix, not a new feature. | LOW — add `gh api repos/{owner}/{repo}/commits/{sha}/check-runs --jq '.total_count'`; fail if 0 | `gh` CLI in CI runner; `GH_TOKEN` |
| Outputs the check-run count to logs for auditability | Future debuggers need to see why the gate passed or failed. | LOW — `echo "Check runs found: $count"` | None |

### Differentiators

None. This is a correctness fix. Ship it and move on.

### Anti-Features

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| Waiting for check-runs to appear (polling loop) | Releases should not block indefinitely on CI. The gate must read state, not drive state. | Fail immediately if zero checks found; the release workflow must be triggered only after CI runs complete |
| Checking only "success" status without checking count | An empty result returns no failures — same vacuous-pass problem. | Check `total_count > 0` first, then check for failures |

### Expected UX (CI log)

```
Check runs for abc1234: 12 found
All 12 check-runs passed. Gate open.
```

Or on failure:
```
Check runs for abc1234: 0 found
✗ Tagged commit has no check-runs — this tag was not preceded by a CI run.
```

---

## Feature 6: SKILL-04 Positional Arg Refactor (DEBT-02)

### Context

`conjure publish-skill` currently accepts `--to <org/repo>` as a flag but also reads `TARGET_REPO` from the environment. The env var path was noted in PROJECT.md as "fragile" tech debt. The correct UX is: `conjure publish-skill <name> [<org/repo>]` where `<org/repo>` is a positional arg with a default of `mohandoz/conjure`. The `--to` flag can remain as an alias for backward compatibility.

This is a refactor, not a new capability. The current `scripts/publish-skill.sh` already has `SKILL_NAME` as a positional and the `--to` flag implemented. The gap is: `TARGET_REPO` env var as the primary interface is fragile because env vars leak across processes and make scripts non-deterministic.

### Table Stakes

| Feature | Why Expected | Complexity | Dependencies |
|---------|--------------|------------|--------------|
| `conjure publish-skill <name> <org/repo>` works as a positional | Standard CLI convention. Positional args are explicit and non-leaky. | LOW — move positional parsing to position 2 in the arg loop | `scripts/publish-skill.sh` |
| `--to <org/repo>` remains as a named alias | Backward compatibility for any scripts that already use `--to`. | LOW — already implemented; keep it | None |
| `TARGET_REPO` env var still accepted as fallback (lowest priority) | Existing CI scripts may use it. Deprecate with a warning, not removal. | LOW — add deprecation warning when `TARGET_REPO` is set but positional is used | None |
| Update help text to reflect positional usage | `conjure publish-skill --help` must show the positional arg. | LOW — doc edit in `scripts/publish-skill.sh` | None |
| Update `cmd_publish_skill` in `cli/conjure` to pass the positional | The CLI dispatcher must thread the positional arg through to the script. | LOW — check `cli/conjure`'s `cmd_publish_skill` dispatch for arg forwarding | `cli/conjure` |

### Differentiators

None. This is a cleanup task. Clean, correct, consistent.

### Anti-Features

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| Removing `TARGET_REPO` env support immediately | Breaking change for any CI that sets it. Deprecate first; remove in v0.6.0. | Print a warning when `TARGET_REPO` is used; document removal in CHANGELOG |
| Making the target repo a required positional (no default) | Adds friction for the common case (publishing to the official conjure repo). | Default to `mohandoz/conjure` when no positional and no `--to` provided |

### Expected UX (before vs after)

```bash
# Before (fragile env var):
TARGET_REPO=myorg/conjure conjure publish-skill my-skill

# After (explicit positional):
conjure publish-skill my-skill myorg/conjure

# After (flag alias — backward compat):
conjure publish-skill my-skill --to myorg/conjure
```

---

## Feature Dependencies (Cross-Feature)

```
[conjure check (DRIFT-01, DRIFT-02)]
    └──enables──> [conjure update --pr (AUTPR-01)]   # --pr uses check output for PR body
    └──reuses───> [cmd_update --check logic in cli/conjure]

[conjure update --apply (v0.4.0 TECH-01 — already shipped)]
    └──required-by──> [conjure update --pr (AUTPR-01)]  # --pr applies the merge before pushing
    └──required-by──> [conjure resolve (RESOLVE-01)]    # resolve walks the conflict sidecars

[lib/merge.sh write_merge_sidecar (v0.4.0 — already shipped)]
    └──required-by──> [conjure resolve (RESOLVE-01)]    # resolve reads .conjure-conflict-* files

[lib/mutate.sh (v0.3.0 — already shipped)]
    └──required-by──> [conjure resolve writes through mutate_cp]
    └──required-by──> [conjure check --dry-run honors DRY_RUN]

[conjure update --pr (AUTPR-01)]
    └──enables──> [GH Action cron template (AUTPR-02)]  # template just calls conjure update --pr

[gh CLI (soft dep — already used in publish-skill)]
    └──required-by──> [conjure update --pr]
    └──required-by──> [ci-gate empty-check guard (DEBT-01)]

[cli/conjure cmd_publish_skill dispatch]
    └──required-by──> [SKILL-04 positional arg refactor (DEBT-02)]
    └──exists-at──>   [cli/conjure — verified in session]

[conjure.ps1 shim (WIN-01)]
    └──enables──> [CI pwsh matrix job (WIN-02)]
    └──delegates-to──> [cli/conjure bash entrypoint via git-bash.exe]
```

---

## MVP Definition

### Must Ship (v0.5.0)

1. **conjure check (DRIFT-01, DRIFT-02)** — table stakes; the entry point for the entire auto-update story. Without it, `update --pr` has no diff signal to put in the PR body. Low complexity; high user value.
2. **conjure resolve (RESOLVE-01, RESOLVE-02)** — direct completion of v0.4.0's 3-way merge. Conflicts exist; no guided resolution exists. This closes the loop on what was shipped.
3. **conjure update --pr (AUTPR-01)** — the automated maintenance story. Medium complexity but depends only on already-shipped primitives (update --apply, gh CLI, lib/merge.sh sidecars).
4. **conjure.ps1 (WIN-01)** — low complexity; unblocks a meaningful segment of users; the CI proof (WIN-02) can ship simultaneously.
5. **ci-gate empty-check guard (DEBT-01)** — correctness fix; negligible complexity; must ship before any release is cut.
6. **SKILL-04 positional arg refactor (DEBT-02)** — low complexity; fixes a fragile interface before it propagates to more callers.

### Can Defer to v0.5.x

- **GH Action cron template (AUTPR-02)** — add-on to AUTPR-01; useful but not blocking. Template file is a documentation artifact with zero runtime code. Can ship in the same release or as a fast follow.
- **Schema version drift detection in `conjure check`** — differentiator; requires the settings.json template to carry a schemaVersion field (small change); can be added when that field stabilizes.
- **PowerShell registry-based git-bash detection** — standard path coverage handles 90% of users; registry fallback is a polish item.

### Defer to v0.6.0

- Workspace / cross-repo graph orchestration (already out of scope in PROJECT.md)
- IDE extensions or web dashboard for drift visibility
- `conjure resolve` TUI (curses/dialog) — the `$EDITOR` model is correct for now

---

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| conjure check | HIGH | LOW | P1 |
| conjure resolve | HIGH | LOW | P1 |
| ci-gate empty-check guard | HIGH (correctness) | LOW | P1 |
| conjure update --pr | HIGH | MEDIUM | P1 |
| conjure.ps1 shim + CI job | MEDIUM | LOW | P1 |
| SKILL-04 positional arg refactor | MEDIUM | LOW | P1 |
| GH Action cron template | MEDIUM | LOW | P2 |
| Schema version check in conjure check | MEDIUM | MEDIUM | P2 |
| conjure check --json | LOW-MEDIUM | LOW | P2 |
| Registry-based git-bash detection | LOW | MEDIUM | P3 |

---

## Competitor Feature Analysis

| Feature | chezmoi | mise | Renovate | Conjure v0.5.0 |
|---------|---------|------|----------|----------------|
| Drift detection | `chezmoi diff` (file-level, unified diff) | `mise outdated` (columnar table, --json) | Built into PR creation | `conjure check` (file-level, columnar + exit code) |
| Update command | `chezmoi update` (pull + apply) | `mise upgrade` | Automated PR | `conjure update --apply` (already shipped) |
| Auto-PR | No | No | Yes — one per dep group | `conjure update --pr` |
| Cron automation | Via `chezmoi update` in cron | No | Yes — native GH App | GH Action template (AUTPR-02) |
| Conflict handling | Delegated to git rebase | N/A | Skips conflicting files, flags in PR | `conjure resolve` (sidecar walk) |
| Windows native | PS 7 script included | Native binary | Native (Node.js) | `conjure.ps1` shim (Git Bash delegation) |
| Machine-readable output | `--json` everywhere | `--json` everywhere | Webhook/API | `conjure check --json` (differentiator) |
| PR deduplication | N/A | N/A | Yes (force-update existing branch) | Check for existing `conjure/update-*` PR before creating |

---

## Sources

- [chezmoi — Daily operations](https://www.chezmoi.io/user-guide/daily-operations/) — HIGH. `chezmoi diff` / `chezmoi apply` split; `chezmoi update` combined pull+apply; blocking wait-for-editor pattern.
- [mise — mise outdated](https://mise.jdx.dev/cli/outdated.html) — HIGH. Columnar output: Plugin / Requested / Current / Latest; `--json` flag; `mise upgrade` as next step.
- [Renovate Docs — Pull requests](https://docs.renovatebot.com/key-concepts/pull-requests/) — HIGH. One-PR-per-dep-group; force-update existing branch; PR body structure; dedup via `gh pr list`.
- [Renovate Docs — Dependency Dashboard](https://docs.renovatebot.com/key-concepts/dashboard/) — HIGH. Dashboard issue tracks all pending updates; ignored PRs require explicit re-enable.
- [Using GitHub CLI in workflows](https://docs.github.com/en/actions/writing-workflows/choosing-what-your-workflow-does/using-github-cli-in-workflows) — HIGH. `gh pr create` in Actions; `GH_TOKEN` required; `permissions: pull-requests: write`.
- [Flux GH Actions auto-PR](https://fluxcd.io/flux/use-cases/gh-actions-auto-pr/) — MEDIUM. Cron-triggered auto-PR pattern; branch naming conventions; dedup by checking existing open PRs.
- [git-mergetool documentation](https://git-scm.com/docs/git-mergetool) — HIGH. One-file-at-a-time conflict walk; `$VISUAL/$EDITOR` delegation; skip with `--no-commit`; the model for `conjure resolve`.
- [PowerShell cross-platform guide](https://medium.com/@josephsims1/powershell-beyond-windows-a-cross-platform-guide-2f6d6de473dd) — MEDIUM. `$PSScriptRoot` for script self-location; `@args` passthrough; `$LASTEXITCODE` propagation.
- [Build a cross-platform shell script CLI runner](https://wadehuang36.medium.com/build-a-cross-platform-shell-script-cli-runner-d6075b8fb682) — MEDIUM. Shim pattern: detect platform, delegate to bash.exe on Windows.
- Conjure internal: `cli/conjure` (cmd_update, cmd_publish_skill), `lib/merge.sh` (write_merge_sidecar, merge_file_3way), `scripts/publish-skill.sh`, `.planning/PROJECT.md` — HIGH (read directly this session).

---
*Feature research for: Conjure v0.5.0 Auto-Update + Healthcheck*
*Researched: 2026-05-26*
