# Pitfalls Research

**Domain:** Conjure v0.6.0 Safe Brownfield Adoption — adding `conjure adopt` + `restructure` skill to existing POSIX bash CLI; LLM-assisted content extraction with human approval gates
**Researched:** 2026-05-28
**Confidence:** HIGH for pitfalls derived directly from the codebase (cli/conjure, lib/mutate.sh, lib/merge.sh, migrations/from-claude/migrate.sh) and verified patterns. MEDIUM for LLM condensation failure modes (verified from published research). MEDIUM for cross-platform backup/path issues (verified from Git Bash/WSL path translation sources).

> **Scope note:** These pitfalls cover only what is **new** in v0.6.0 — the `conjure adopt` deterministic CLI and the `restructure` skill (LLM-assisted, human-gated). Pitfalls already addressed in v0.5.0 (TTY guard, mutate_rm, CRLF line endings, PS exit codes) are not repeated. The canonical stress fixture is "argus" — 2180 markdown files, 21 KB / 180-line CLAUDE.md (cap 100), 35-doc GSD `.planning/` sprawl, `.claude/` with settings only.

---

## Critical Pitfalls

Mistakes in this section cause silent data loss, unverifiable state, or produce a system that *looks* restructured but has dropped content the user cannot recover without understanding what was lost.

---

### Pitfall CR-1: LLM Condensation Silently Drops a Hidden Constraint or Operational Invariant

**What goes wrong:**
The `restructure` skill feeds Claude an oversized CLAUDE.md (180 lines, cap 100) and asks it to produce a ≤100-line core. Claude rewrites the file, preserving the "important" sections. A constraint like `hooks must exit 2, never exit 1` or `@imports are forbidden` or a project-specific invariant like `never call the external billing API in test mode` is embedded mid-paragraph without a heading. Claude treats it as context rather than a hard rule and omits or soft-paraphrases it. The condensed CLAUDE.md passes the size-cap audit. The dropped invariant is violated silently in a later session — the damage is not discovered until a production incident.

**Why it happens:**
LLMs trained on summarization tasks optimize for semantic coverage of prominent headings and explicit rules. Constraints embedded in prose (not bullet-pointed, not in a dedicated section) are the most vulnerable — they look like elaboration to the model. Published research confirms up to 75% of LLM summary content can be hallucinated or omit source material, and the "lost in the middle" effect means content in the middle of a long document is systematically under-represented in the output.

**How to avoid:**
- Before invoking the `restructure` skill, `conjure adopt` must run a **constraint extraction pre-pass**: grep the source CLAUDE.md for signal patterns — `must`, `never`, `always`, `forbidden`, `required`, `exit 2`, `@imports`, size-cap numbers, compliance keywords — and produce a machine-readable `INVARIANTS.txt` list.
- The `restructure` skill prompt must include the full `INVARIANTS.txt` list and require the model to confirm each invariant appears verbatim or by explicit reference in the proposed output before the user approves.
- After LLM condensation, `conjure adopt` runs a **post-condensation invariant check**: for each extracted constraint in `INVARIANTS.txt`, grep the proposed output; any missing constraint blocks the approval step with a clear warning: `"WARN: constraint not found in proposed output: 'hooks must exit 2'"`.
- The invariant check must run on the proposed content before it is written to disk, not after.

**Warning signs:**
- The condensed CLAUDE.md is shorter than expected with no visible content in RESTRUCTURE-LOG.md explaining where it went.
- `conjure audit` passes but a section that previously existed (visible in the timestamped backup) has no corresponding skill or archive entry.
- Post-adopt session produces a hook that uses `exit 1` or a file that contains `@imports`.

**Phase to address:**
Inventory + constraint-extraction phase (Phase 1 of `conjure adopt`). The invariant extraction and post-LLM verification gate must exist before any LLM-assisted condensation is attempted.

---

### Pitfall CR-2: Partial-Apply Corruption — Crash or Interrupt Mid-Restructure Leaves the Project in an Inconsistent State

**What goes wrong:**
`conjure adopt` processes a multi-step restructure: snapshot → inventory → scaffold missing layers → condense CLAUDE.md → extract skills → archive stale docs → write RESTRUCTURE-LOG.md. If the process is interrupted (Ctrl-C, OOM kill, SSH timeout, power loss) after step 3 but before step 6, the project is in a state where some harness layers exist but CLAUDE.md has not been condensed and no RESTRUCTURE-LOG entry covers the partial work. A second run of `conjure adopt` sees the partially-completed state and either errors (because scaffolds already exist) or re-runs steps 1-3 and overwrites the backup with a now-already-mutated tree — destroying the original state.

**Why it happens:**
The existing `lib/mutate.sh` is a write chokepoint but has no step-level transaction concept. Steps 1-N are independent shell invocations. There is no "completed steps" manifest. A re-run after partial completion has no way to know which steps finished.

**How to avoid:**
- `conjure adopt` must write a **step completion manifest** (`.claude/adopt-state.json` or `.claude/.adopt-progress`) at the end of each successfully completed step, recording: step name, timestamp, sha256 of any written files.
- On startup, `conjure adopt` reads the manifest and skips already-completed steps (idempotent re-run).
- The snapshot backup is taken **first**, before any step is executed, and its path is recorded in the manifest. A re-run after partial completion uses the existing snapshot, not a new one (which would snapshot the already-mutated tree).
- Signal traps (`trap 'echo interrupted; exit 2' INT TERM`) print the manifest path and a recovery instruction: `"Run conjure adopt --rollback to restore from <snapshot>"`.
- Critically: the snapshot and the manifest write are the **only** steps allowed to be non-idempotent. All subsequent steps must check "was this already done?" before writing.

**Warning signs:**
- `.claude/adopt-state.json` exists but `RESTRUCTURE-LOG.md` is absent or incomplete.
- `.claude/` contains newly-scaffolded skills but CLAUDE.md has not changed.
- A second run of `conjure adopt` reports "backup already exists" but then proceeds to overwrite files that were written by the first (partial) run.

**Phase to address:**
`conjure adopt` core implementation phase (Phase 2). The step manifest and signal trap are day-one requirements, not hardening. They must be in place before any live restructure logic is written.

---

### Pitfall CR-3: Snapshot Backup and Git Dirty-Tree Hazard — The Two Safety Nets Conflict

**What goes wrong:**
`conjure adopt` takes a timestamped filesystem snapshot backup (e.g., `.claude.backup-20260528T143000/`) before mutating anything. It also enforces a git-clean precondition: refuses to run if `git status --porcelain` shows unstaged changes, because a dirty tree means the snapshot and git history diverge — rollback via git loses what was in the working tree at adopt time, and rollback via snapshot restores files that git does not know about.

The conflict: a user with intentional uncommitted work (e.g., a half-finished skill they are about to adopt) runs `conjure adopt`. The git-clean check fires (`exit 2`). The user passes `--force`. `conjure adopt` runs, snapshots the dirty tree (including the uncommitted skill), and restructures. Now the snapshot contains the uncommitted content but git HEAD does not. If the user later runs `conjure adopt --rollback`, the restored files do not match the git index. `git status` shows the "rollback" as new unstaged changes — which is correct, but confusing. The user may then `git checkout -- .` to clean up and discard the snapshot-restored content.

A second hazard: if `conjure adopt` generates new files during restructure and the user has an unrelated `git add` in flight (e.g., in a separate terminal), the git index state at snapshot time differs from the index state at completion time. A `git stash`-based rollback (wrong approach) loses both.

**How to avoid:**
- The snapshot must capture both the git HEAD sha and the result of `git stash list` at snapshot time, storing them in a `snapshot-meta.json` alongside the copied files.
- RESTRUCTURE-LOG.md must print: `"WARNING: --force used on a dirty tree. Snapshot includes uncommitted changes. Git rollback will NOT restore these — use conjure adopt --rollback (snapshot-based) only."` This warning must appear both in the log and on stdout at adopt time.
- `--rollback` must use only the filesystem snapshot, never `git checkout --` or `git reset`. The rollback docs must state this explicitly.
- The git-clean precondition must distinguish "dirty but staged" (staged = user is mid-commit, higher risk) from "dirty with only untracked files" (lower risk). Recommend `--force` only for the untracked case; for staged changes, require stashing first and explain why.
- After rollback, print a diff count: `"Restored N files from snapshot taken at T. Run git status to review."` Do not auto-commit.

**Warning signs:**
- `conjure adopt --rollback` followed by `git status` shows a large number of modified/new files that do not match what the user expects the "original" state to be.
- The snapshot directory is smaller than expected (missing files that were in the dirty tree).
- RESTRUCTURE-LOG.md does not record whether `--force` was used.

**Phase to address:**
`conjure adopt` snapshot primitive and rollback implementation (Phase 2). The `snapshot-meta.json` with git state is a required part of every snapshot, not an enhancement.

---

### Pitfall CR-4: Incomplete or Unverifiable Rollback — Archive Instead of Delete Does Not Guarantee Recovery

**What goes wrong:**
The `never-delete` invariant means `conjure adopt` archives files to `.claude/archive/` instead of deleting them. This looks safe: the files are still there. But "archive instead of delete" is not a complete rollback story. A rollback must restore all mutated files to their original state, not just make the originals available. If a skill was condensed (original content replaced, not deleted), and the condensed version is in `.claude/skills/X/SKILL.md`, the archive contains the *original split sections* but the current SKILL.md contains the *LLM output* — the original SKILL.md content from before adoption is in the backup, not the archive.

A user doing `conjure adopt --rollback` who does not understand the distinction between the timestamped snapshot backup (complete pre-adopt state) and the archive folder (files archived *during* adopt) may use the archive to try to undo changes and find it is incomplete.

Additionally: rollback of a partial adoption (CR-2 scenario) must know which files were *actually written* during the interrupted run, not which files were *planned* to be written. Without a written-files log, `--rollback` either under-restores (misses files written before the interrupt) or over-restores (reverts files from a previous clean adopt that are not related to the interrupted one).

**How to avoid:**
- `conjure adopt --rollback` must use only the timestamped snapshot backup directory, not the archive. The archive is "things adopted away from the harness" — it is not the rollback mechanism.
- The step completion manifest (from CR-2) must record each file actually written (path + sha256 before + sha256 after). `--rollback` iterates this manifest and restores only the files that were mutated in the current adopt run.
- On startup, if a previous adopt run's manifest exists and is incomplete (interrupted), `conjure adopt` must ask: `"A previous adopt run was interrupted. Options: [r]ollback interrupted run, [c]ontinue from last completed step, [s]tart fresh (requires --force)."` Never auto-continue silently.
- Print the snapshot path at the start of every adopt run: `"Snapshot at: <path>. To undo everything: conjure adopt --rollback."` This must be the first line of stdout, before any mutations.
- Test rollback in CI: adopt a fixture repo, verify output, rollback, diff against original fixture — assert zero diff.

**Warning signs:**
- The archive directory contains files but the pre-adopt snapshot is missing or empty.
- `conjure adopt --rollback` reports "restored 0 files" after an interrupted run that visibly changed files.
- RESTRUCTURE-LOG.md has no "files written" section, only a "plan" section.

**Phase to address:**
Rollback implementation and RESTRUCTURE-LOG schema (Phase 2 + Phase 3). The written-files log in the step manifest is a prerequisite for any rollback guarantee claim.

---

### Pitfall CR-5: LLM Re-Introduces Forbidden @imports or Breaches Size Caps While "Fixing" Them

**What goes wrong:**
The `restructure` skill asks Claude to condense a 180-line CLAUDE.md to ≤100 lines. Claude may produce a compact file that uses `@imports` as a shortcut to reference skill content (since `@imports` is how Claude Code users naturally link files). The proposed output passes the 100-line check but contains lines like `@.claude/skills/git-workflow/SKILL.md` — which is explicitly forbidden in conjure because `@imports` trigger eager loading of all referenced files, defeating lazy skill loading and wasting tokens on every session start.

Similarly, Claude may produce a CLAUDE.md that is exactly 100 lines by using very dense, multi-constraint single lines — but then include a preamble or frontmatter that pushes the total to 103 lines. The size-cap audit catches this after the fact; the issue is that the LLM-proposed content was presented to the user for approval without the cap check running first, so the user approved invalid content.

**How to avoid:**
- `conjure adopt` must run the **full `conjure audit` suite against the proposed LLM output before presenting it to the user for approval**. If the proposed output fails any audit check, the approval step is blocked with the audit output: `"BLOCK: proposed CLAUDE.md contains @imports (line 34). Cannot proceed until LLM output is corrected."` The user is shown the failure and asked to re-prompt the skill or edit the proposed output manually.
- The `restructure` skill prompt must include the anti-@imports rule as a hard constraint in the system prompt: `"NEVER use @import syntax. Use prose references: 'For X, see .claude/skills/X/SKILL.md'."` This is a defense-in-depth measure; the audit gate is the actual enforcement.
- The line-count check must use the same counting method as `conjure audit` (wc -l, excluding trailing newline if relevant). Inconsistent counting (e.g., skill counts blank lines differently) caused false-negative cap checks in v0.3.0.
- Add a CI fixture test: a proposed CLAUDE.md with a single `@import` line must be rejected by the adopt pre-write audit gate.

**Warning signs:**
- Proposed CLAUDE.md from the `restructure` skill contains `^@` lines (grep-detectable).
- `conjure audit` fails on a just-adopted harness.
- The line count reported in RESTRUCTURE-LOG.md does not match `wc -l` on the actual file.

**Phase to address:**
`conjure adopt` pre-write audit gate (Phase 2 + Phase 3). The audit gate must run on proposed content before user approval, not after. This is the key distinction from the existing post-write audit in `conjure audit`.

---

### Pitfall CR-6: Trusting LLM-Proposed Deletions (Archive Decisions)

**What goes wrong:**
The `restructure` skill proposes which docs to archive (move to `.claude/archive/` as stale). For the argus fixture: 35 GSD `.planning/` docs, dashboard/ pile, latest_design/ pile. Claude may classify a `.planning/` phase plan as "stale completed work" and propose archiving it. But that plan contains a design decision that is still active — e.g., "we decided NOT to use associative arrays for bash 3.2 compat." The decision is not duplicated anywhere else. Once archived, it is de-prioritized and likely never consulted again. The invariant is effectively lost even though the file is not deleted.

The failure mode is "correct file present, wrong classification" — the file is in archive, not in a skill or in CLAUDE.md, so Claude Code does not surface it in sessions.

**How to avoid:**
- Archive decisions must be treated with the highest skepticism. The `restructure` skill must **never propose archive in the same step as proposing CLAUDE.md condensation**. Archive classification must be a separate, dedicated approval step with explicit justification for each file: `"Archive .planning/16-prerequisites/16-01-PLAN.md: reason: phase completed, no active decisions."` The user must approve each file individually or in explicit batches (not "archive all .planning/").
- `conjure adopt` must add a `--archive-review` step that shows: for each proposed-archive file, `diff /dev/null <file>` (full content), and requires `y`/`n`/`keep-as-skill` per file. For files > 50 lines, always require individual confirmation, never batch.
- The `restructure` skill must first scan for "decision vocabulary" in candidate-archive files: words like `"decided"`, `"we chose"`, `"do not"`, `"never"`, `"rationale"`, `"tradeoff"` — and flag those files as needing human review before archive classification.
- Archived files must be listed in RESTRUCTURE-LOG.md with the classification reason, so a future audit can verify the classification was correct.

**Warning signs:**
- The `restructure` skill proposes archiving files with names containing `DECISION`, `ADR`, `RATIONALE`, `PLAN`, or `CONTEXT` without individual justification.
- The archive batch count exceeds 5 files in a single approval step.
- Post-adopt `conjure audit` does not surface any of the previously-visible constraints from the archived files — they have effectively disappeared from Claude's context.

**Phase to address:**
`restructure` skill design and `conjure adopt` archive-review step (Phase 3). The archive step must be sequenced last and must be individually confirmed, not batched with other restructure operations.

---

### Pitfall CR-7: Scaling to 2000+ Files — Inventory Hangs, Memory Exhaustion, Manifest Bloat, Approval Fatigue

**What goes wrong:**
The argus fixture has 2180 markdown files. A naive `find . -name "*.md"` inventory loads all 2180 paths into a bash variable or a single manifest file. At 2180 entries × ~100 bytes/path = ~218 KB — manageable for the manifest. But classification (reading each file's content to determine type) requires reading 2180 files. If classification uses `wc -l` + `head -20` per file, that is 4360 subprocess calls. On a 2 GHz machine, this runs at ~100ms per file pair = 436 seconds (7 minutes) for a synchronous inventory. A user running `conjure adopt --dry-run` on argus watches a 7-minute blank terminal and assumes it has hung.

The second scaling failure is approval fatigue: if `conjure adopt` presents 2180 individual approval decisions, the user rubber-stamps everything (the exact failure mode the approval gates are designed to prevent). Meaningful approval requires batching into logical groups: "35 GSD .planning/ docs — propose archiving N, extracting M to skills" — with summary stats, not per-file prompts.

The third failure is manifest size: a RESTRUCTURE-LOG.md with 2180 entries is unreadable and not useful as an audit trail.

**How to avoid:**
- Inventory classification must be **bounded**: cap at 500 files in the first classification pass. If the project has more than 500 markdown files, `conjure adopt` must print a warning and require `--full-inventory` to proceed. For argus-scale projects, the default adoption scope is `.claude/` and root-level markdown files; `.planning/` and other doc piles are treated as a separate, opt-in scope.
- Classification must be streaming, not batch: process files one at a time with a progress indicator (line counter: `"Classifying file 412 of 500..."`). No subprocess per-file — use `wc -c` (single call per file via find -size) and `head` instead of multiple greps.
- Approval must be hierarchical: classify into groups (harness layer files / GSD planning docs / project docs / unknown), present group-level summary, approve group strategy, then per-file only for files flagged as requiring individual review (e.g., oversized, decision vocabulary, active `.planning/` phases).
- RESTRUCTURE-LOG.md must use a summary format for bulk classifications: `"Archived 31 of 35 GSD .planning/ docs (see adopt-state.json for full list)."` The full manifest lives in `adopt-state.json`, not in the human-readable log.
- CI must include a performance test: run `conjure adopt --dry-run` on a synthetic fixture with 500 markdown files and assert completion in < 30 seconds.

**Warning signs:**
- `conjure adopt --dry-run` on a mid-size project takes more than 60 seconds with no output.
- The generated RESTRUCTURE-LOG.md is larger than 100 KB.
- The user approves a batch of 50+ files without any summary context being shown.

**Phase to address:**
`conjure adopt` inventory and classification phase (Phase 1). Streaming classification and hierarchical approval grouping must be designed before implementation, not retrofitted after a performance complaint.

---

## Moderate Pitfalls

Mistakes here cause incorrect behavior or corrupted state but have a known recovery path.

---

### Pitfall M-1: Non-Deterministic / Non-Reproducible LLM Extraction — Same Input Produces Different Output on Re-Run

**What goes wrong:**
The `restructure` skill is an LLM prompt — temperature > 0, non-deterministic by design. Two users running `conjure adopt` on identical inputs produce different extracted skills and different condensed CLAUDE.md. A team member reviewing the PR sees a condensed CLAUDE.md that differs from what their colleague approved — not because the input changed, but because the LLM ran again. If `conjure adopt` allows the LLM step to be re-run (e.g., "not happy with this output — try again"), the audit trail in RESTRUCTURE-LOG.md shows the final approved output but not the intermediate attempts. The "reproducible" claim from conjure's value proposition breaks.

**How to avoid:**
- Once the user approves an LLM-proposed output, `conjure adopt` must write the **approved content** to disk immediately via `mutate_write`, and record the sha256 of the written content in `adopt-state.json`. Subsequent re-runs of `conjure adopt` must skip LLM steps for any file whose sha256 matches the manifest entry — they are already in their approved state.
- RESTRUCTURE-LOG.md must record: `"CLAUDE.md condensation approved by user at <timestamp>. sha256: <hash>."` This makes the step auditable regardless of what the LLM would produce if run again.
- The `restructure` skill must be explicitly documented as "LLM output, human-approved, non-deterministic." The determinism guarantee applies to *file operations* (conjure's existing value), not to LLM content proposals.
- If a user re-prompts the skill (discards proposed output and tries again), a new manifest entry must be written and the old one marked as discarded with a timestamp: `"Attempt 1 discarded by user at T. Attempt 2 approved at T2."` This preserves the audit trail of the decision process.

**Warning signs:**
- Two `conjure adopt` runs on the same repo produce different `adopt-state.json` sha256 entries for the same file.
- RESTRUCTURE-LOG.md has no approved-at timestamp or sha256 for LLM-generated content.
- Re-running `conjure adopt` after a completed adoption re-invokes the LLM step instead of skipping (idempotency failure).

**Phase to address:**
`restructure` skill design and `conjure adopt` step manifest (Phase 2 + Phase 3). The "approve-and-record" pattern is the bridge between non-deterministic LLM output and deterministic file operations.

---

### Pitfall M-2: Symlinks, Binaries, and Generated Files Corrupting the Inventory

**What goes wrong:**
A naive `find . -name "*.md"` inventory includes symlinks to markdown files. In the argus fixture, `.claude/settings.json` might be a symlink from a shared dotfiles repo. The inventory treats it as a regular file. `mutate_cp` does `cp "$src" "$dest"` — if `$src` is a symlink, `cp` without `-P` (preserve symlink) dereferences the link and copies the target content, breaking the symlink. On rollback, the restored "file" is a regular file, not a symlink — the dotfiles integration silently breaks.

A second case: generated markdown files (e.g., `docs/api-reference.md` auto-generated from OpenAPI spec). The `restructure` skill may propose condensing or archiving a generated file, not knowing it is regenerated on every build. After adoption, the next build regenerates the file in its original form, outside of the harness, silently overwriting the adoption result.

**How to avoid:**
- `conjure adopt` inventory must classify file types before processing: use `test -L "$f"` to detect symlinks; use heuristics for generated files (contains `# DO NOT EDIT`, `# Generated by`, `<!-- AUTO-GENERATED -->`, or lives in a path matching `dist/`, `build/`, `generated/`, `_site/`).
- Symlinks must be **skipped** in the inventory unless `--include-symlinks` is passed, with a RESTRUCTURE-LOG warning: `"Skipped symlink: .claude/settings.json — symlinks are not restructured."` The snapshot backup must preserve symlinks (use `cp -R` or `rsync -a`, which preserves symlink structure).
- Generated files must be placed in a separate inventory category ("generated — skip") and excluded from LLM condensation proposals. The `restructure` skill prompt must include this category explicitly.
- Binary files (detected by `file --mime-type` or `LC_ALL=C grep -P "\x00"`) must be skipped entirely — they have no business in a markdown inventory.

**Warning signs:**
- The inventory count includes `.png`, `.json`, or `.sh` files in the markdown inventory.
- Post-adoption `git status` shows symlink targets changed (dereferenced copy).
- A generated file appears in the `restructure` skill's proposed skill extraction list.

**Phase to address:**
`conjure adopt` inventory classification (Phase 1). The symlink and generated-file filters must be in the initial `find` pass, not added as post-processing.

---

### Pitfall M-3: Idempotency Failure — Re-Runs Double-Archive or Duplicate Skills

**What goes wrong:**
A user runs `conjure adopt`, the process completes, and they run it again (e.g., to check the state). Without idempotency guards, the second run re-inventories, sees the same files (including already-archived files in `.claude/archive/`), and proposes archiving them again — into `.claude/archive/archive/`. Or it re-scaffolds skills that were already created, appending duplicate content to existing SKILL.md files if `mutate_write` without a check-first guard is used.

The step completion manifest (from CR-2) prevents re-running completed steps. But idempotency must also work when the manifest is absent (fresh run after complete removal of `.claude/adopt-state.json`). In that case, `conjure adopt` must detect already-restructured state from the files themselves, not from the manifest.

**How to avoid:**
- Before writing any file, `conjure adopt` must check `[ -f "$dest" ]` and compare sha256 of existing content vs proposed content. If identical, skip with `"[adopt] already in target state: $dest (no-op)"`. If different, require explicit `--overwrite` flag or present a diff and await confirmation.
- The archive step must check whether a file is already in `.claude/archive/` before archiving: `[ -f ".claude/archive/$(basename $f)" ] && echo "already archived, skipping"`.
- The `--dry-run` output must be idempotency-aware: on re-run, `[dry-run] would write X (no-op: content identical)` vs `[dry-run] would overwrite X (content differs)`. This distinction is critical for users debugging adoption state.

**Warning signs:**
- Running `conjure adopt` twice produces a different `adopt-state.json` on the second run.
- `.claude/archive/` contains files with `(2)` or `_1` suffixes (second-run duplicates).
- RESTRUCTURE-LOG.md has two entries for the same file on different dates.

**Phase to address:**
`conjure adopt` step manifest and idempotent write logic (Phase 2). The sha256-based no-op check must be part of every `mutate_write` call in adopt, not opt-in.

---

### Pitfall M-4: Cross-Platform Backup Path Issues — Windows Git Bash / bash 3.2 Incompatibilities

**What goes wrong:**
The snapshot backup path uses a timestamp: `.claude.backup-$(date +%Y%m%dT%H%M%S)`. On macOS, `date +%Y%m%dT%H%M%S` produces `20260528T143000`. On Windows Git Bash, `date` is available but timezone handling differs. On systems where `TZ` is not set, the timestamp may be local time rather than UTC, causing backup directories from different machines to have non-comparable names (looks like duplicate backups).

A second issue: the snapshot is created with `cp -r source/ dest/`. On macOS and Linux, `cp -r` on a directory ending with `/` copies the *contents* into the destination. On some Linux variants, `cp -r source/ dest/` (when dest does not exist) vs `cp -r source dest` behaves differently. The snapshot may silently omit the top-level directory or create an unexpected structure, breaking the rollback restore path.

A third issue: the existing `lib/mutate.sh::mutate_cp` does `cp -r "$1" "$2"` for directories. On bash 3.2 (macOS default), `set -u` is active. If the backup path contains spaces (user home directory with spaces — common on macOS), unquoted `$2` in mutate_cp causes a word-split error.

**How to avoid:**
- Always use `date -u +%Y%m%dT%H%M%SZ` (explicit UTC suffix) for backup timestamps. The `Z` suffix makes the timezone unambiguous in log messages and directory names.
- The snapshot creation must normalize the path: always use `cp -rp "$source" "$dest_parent/"` (never trailing slash on source with `cp -r`) and verify `[ -d "$dest_parent/$source_basename" ]` after the copy to assert the structure is correct.
- All paths in `adopt-state.json` must be stored as absolute paths. Any use of relative paths in the manifest must be resolved against a stored `ADOPT_ROOT` before use.
- `mutate_cp` is already quote-safe via `"$1"` and `"$2"`. Verify that all `conjure adopt` call sites use `mutate_cp` (not bare `cp`) for the snapshot step.
- On Windows Git Bash, `cygpath` is available but must not be required — all paths should use Unix-style `/` separators (Git Bash normalizes these). Never store `C:\...` paths in the manifest.

**Warning signs:**
- Backup directory timestamp does not end in `Z` (non-UTC timestamp in log).
- `ls .claude.backup-*/` shows an unexpected directory structure (e.g., extra level of nesting or missing top-level `.claude/`).
- `conjure adopt --rollback` on Windows Git Bash reports "path not found" for a backup path that exists.

**Phase to address:**
`conjure adopt` snapshot primitive (Phase 2). UTC timestamps, path normalization, and quote-safe path handling must be in the initial snapshot implementation.

---

### Pitfall M-5: RESTRUCTURE-LOG.md Grows Without Bound — Audit Trail Becomes Unauditable

**What goes wrong:**
RESTRUCTURE-LOG.md is append-only (each adopt run appends). For a project that runs `conjure adopt` multiple times (initial adoption, then re-adoption after adding docs), the log grows indefinitely. After 10 adoption runs, the log is a wall of entries with no structure indicating which run is "current." A reviewer trying to understand the current state of the repo must read the entire log. The audit trail, designed to provide clarity, becomes a source of confusion.

**How to avoid:**
- RESTRUCTURE-LOG.md must have a **per-run header** with a unique run ID, timestamp, and git sha: `## Adopt run: run-20260528T143000Z (commit abc1234)`. Each run's entries are grouped under its header.
- The log must have a **summary section at the top** (overwritten on each run): `Last adopt run: run-20260528T143000Z | Files modified: 12 | Archived: 5 | Skills created: 3`. This summary is the quick-read answer; the full log is the audit trail.
- Cap the log at 1000 lines. When the cap is reached, `conjure adopt` must rotate the log: move current content to `RESTRUCTURE-LOG-archive-<date>.md` and start a fresh log. This prevents unbounded growth.
- The `adopt-state.json` manifest (machine-readable) is the authoritative record; RESTRUCTURE-LOG.md is the human-readable summary. Do not duplicate all manifest data into the log.

**Warning signs:**
- RESTRUCTURE-LOG.md is larger than 50 KB.
- The log contains entries from more than 3 different dates with no section headers separating them.
- There is no "last adopt run" summary at the top of the log.

**Phase to address:**
RESTRUCTURE-LOG.md schema design (Phase 3). The per-run structure must be defined before any adopt runs write to the log, because retrofitting structure onto an existing flat log requires a migration.

---

## Minor Pitfalls

Small issues that cause friction or subtle errors but are recoverable.

---

### Pitfall MN-1: `conjure adopt` Does Not Distinguish Already-Correct Harness from Needing Adoption

**What goes wrong:**
Running `conjure adopt` on a project that already has a correct four-layer harness (CLAUDE.md ≤100 lines, all skills valid, hooks in place) should exit 0 with `"Nothing to adopt."` Instead, a naive implementation re-runs the full inventory, scaffolds "missing" layers that are actually present with slightly different names, and presents the user with a no-op restructure for approval.

**How to avoid:**
- Add a preflight check to `conjure adopt`: run `conjure audit` first. If audit passes cleanly, print `"conjure adopt: audit passes — harness is already in good shape. Use --force to adopt anyway."` and exit 0.
- If audit fails, report which checks failed to set expectations: `"conjure adopt will address: CLAUDE.md over cap (180 lines), missing skill frontmatter in 3 skills."` This scoping message sets user expectations before the inventory step runs.

**Phase to address:**
`conjure adopt` entry-point phase (Phase 1 preflight).

---

### Pitfall MN-2: `conjure adopt --rollback` Without a Preceding Adopt Run Destroys Files

**What goes wrong:**
A user running `conjure adopt --rollback` without a prior snapshot backup (e.g., they deleted the backup directory manually, or this is the first run) would, in a naive implementation, attempt to restore from a non-existent backup and either error cryptically or, if the rollback code uses `cp -r snapshot/ .` without checking that `snapshot/` exists, create an empty `.claude/` by overwriting with nothing.

**How to avoid:**
- `--rollback` must check for snapshot existence first: `[ -d "$SNAPSHOT_PATH" ] || { echo "No snapshot found at $SNAPSHOT_PATH — nothing to roll back."; exit 2; }`. Always exit 2 (hard failure, per conjure hook convention) on missing prerequisites.
- Print the snapshot path in the rollback dry-run: `[dry-run] would restore from: <path>`.

**Phase to address:**
`conjure adopt --rollback` implementation (Phase 2).

---

### Pitfall MN-3: Size-Cap Line Count Includes or Excludes Trailing Newline Inconsistently

**What goes wrong:**
`wc -l` counts newline characters. A file with 100 lines of content and a trailing newline reports 100. A file with 100 lines and no trailing newline reports 99. `printf '%s'` (used in `mutate_write`) does not add a trailing newline. A CLAUDE.md written by `mutate_write` from LLM content that includes a trailing newline is 101 lines per `wc -l` but looks like 100 in an editor. The size-cap audit may pass or fail depending on whether the LLM output includes a trailing newline — inconsistent behavior for the same logical content.

**How to avoid:**
- `conjure audit` and `conjure adopt`'s pre-write cap check must use the same counting function. Define `count_lines()` once in `lib/mutate.sh` or a shared lib: `printf '%s' "$content" | wc -l`. This counts logical lines, not newline characters.
- `mutate_write` must always add a trailing newline (use `printf '%s\n'` not `printf '%s'`) for text files. This makes `wc -l` deterministic.
- The pre-write cap check must count the proposed content string with the same function, before writing, to ensure the written result will pass the post-write audit.

**Phase to address:**
`conjure adopt` pre-write audit gate (Phase 2 + cap-check hardening).

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Single approval step for all archive decisions | Faster UX for small projects | Catastrophic on 2000+ file projects (approval fatigue, silent loss) | Never for > 10 files per batch |
| Storing LLM-proposed content in RESTRUCTURE-LOG.md only (not in adopt-state.json with sha256) | Simpler implementation | Non-reproducible; cannot verify rollback completeness | Never |
| Skipping invariant extraction pre-pass and relying on LLM to preserve all constraints | Faster Phase 1 | Silent invariant loss (CR-1); discovered only after production incident | Never |
| Using git checkout / git reset as rollback mechanism instead of filesystem snapshot | No extra files on disk | Loses dirty-tree content; breaks if working tree has unstaged changes at adopt time | Never |
| Flat RESTRUCTURE-LOG.md without per-run structure | Simpler log writes | Unauditable after 3+ adopt runs | Never for production use |
| `find . -name "*.md"` without symlink/binary/generated filters | Simpler inventory | Breaks on symlink-heavy repos; proposes archiving generated files | Only in --dry-run preview mode |

---

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| `lib/mutate.sh` in adopt scripts | Writing files directly with `printf >` or `cp` outside mutate.sh (bypasses dry-run) | Every filesystem write in adopt scripts must use `mutate_mkdir`, `mutate_cp`, `mutate_write`, `mutate_rm` — no exceptions |
| `conjure audit` as the cap gate | Running audit only after writing to disk (user already approved invalid content) | Run the audit suite against the proposed content string before presenting for user approval |
| `git status --porcelain` dirty-tree check | Using `git diff --quiet HEAD` (misses untracked files) | Use `git status --porcelain` which shows both tracked-modified and untracked files |
| Snapshot backup with `cp -r` | Copying symlinks as regular files (dereferences target) | Use `cp -Rp` (preserve mode + symlink structure) or `rsync -a` for snapshot creation |
| Step manifest `adopt-state.json` | Writing the manifest only at the end of all steps (loses progress on interrupt) | Write manifest entry at the END of each successfully completed step, not at the end of the full run |

---

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| One subprocess per file for classification | `conjure adopt --dry-run` takes > 5 minutes on medium repos | Batch `find` with `-exec` or use `wc -c` (size check) as first-pass filter before content reads | > 200 files |
| Loading full file content into bash variables for classification | Bash runs out of memory on large files; `$()` subshell for a 1 MB file kills performance | Use `head -5` for frontmatter check; `wc -c` for size; never load full content into a shell variable | Files > 100 KB |
| Grepping full repo tree for constraint patterns | INVARIANTS.txt extraction on 2180 markdown files takes 30+ seconds | Scope constraint extraction to CLAUDE.md + root-level markdown only; exclude `.planning/` and generated dirs | > 500 files |
| Sequential `adopt-state.json` writes (one write per file manifest entry) | Thousands of small writes on slow filesystems (NFS, network mounts) | Accumulate manifest entries in memory; flush to JSON once per step, not per file | > 100 files on network storage |

---

## "Looks Done But Isn't" Checklist

- [ ] **Rollback**: `conjure adopt --rollback` actually tested on a fixture repo — asserts zero diff vs pre-adopt state, not just "reports success"
- [ ] **Invariant preservation**: Every constraint extracted in `INVARIANTS.txt` verified present in the approved CLAUDE.md output — not just line count check
- [ ] **@import guard**: `conjure audit` run against proposed LLM output before user approval presentation — not only after write
- [ ] **Symlink handling**: Inventory run on a fixture with at least one symlink — confirms symlink is skipped and RESTRUCTURE-LOG shows skip reason
- [ ] **Partial-apply recovery**: `conjure adopt` killed mid-run with SIGKILL — second run detects incomplete manifest and offers rollback/continue/fresh options
- [ ] **Idempotency**: `conjure adopt` run twice on an already-adopted repo — second run produces zero mutations and exits 0
- [ ] **Archive-decision logging**: Every archived file has a classification reason in `adopt-state.json` — not just a file path
- [ ] **Windows Git Bash**: Snapshot backup path uses UTC timestamp (`Z` suffix) and absolute paths — tested on Git Bash fixture
- [ ] **Line-count consistency**: `wc -l` count used in pre-write cap check matches `conjure audit` count method — tested with file with and without trailing newline

---

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| Silent invariant drop (CR-1) | HIGH | Diff backup CLAUDE.md vs current; manually restore dropped constraints; re-run `conjure audit` |
| Partial-apply corruption (CR-2) | MEDIUM | Run `conjure adopt --rollback` using snapshot; verify diff; commit clean state |
| LLM re-introduces @imports (CR-5) | LOW | `grep -n '^@' .claude/CLAUDE.md`; remove @imports; replace with prose references; re-run audit |
| Symlink dereference in backup (M-2) | MEDIUM | Restore symlink from dotfiles/original source; `ln -s <target> <path>`; verify |
| Double-archive on re-run (M-3) | LOW | Remove `.claude/archive/archive/`; move mis-archived files back; re-run with idempotency fix |
| Non-UTC backup timestamp confusion (M-4) | LOW | Rename backup directory to add `Z` suffix; update `adopt-state.json` snapshot path |
| LLM deletion of active-decision docs (CR-6) | HIGH | Identify archived files via `RESTRUCTURE-LOG.md`; move back from `.claude/archive/`; re-add decision content to appropriate skill or CLAUDE.md |

---

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| CR-1: Invariant drop in LLM condensation | Phase 1 (inventory + constraint extraction) + Phase 3 (pre-write audit gate) | `conjure adopt --dry-run` on fixture with known constraints; assert all appear in proposed output |
| CR-2: Partial-apply corruption | Phase 2 (step manifest + signal traps) | Send SIGKILL mid-adopt on fixture; assert second run offers rollback/continue |
| CR-3: Snapshot + dirty-tree conflict | Phase 2 (snapshot primitive with `snapshot-meta.json`) | Run adopt with `--force` on dirty tree; assert RESTRUCTURE-LOG contains dirty-tree warning |
| CR-4: Incomplete rollback | Phase 2 (written-files log in manifest) + Phase 3 (rollback test in CI) | Adopt fixture, rollback, diff vs original — assert zero diff |
| CR-5: @imports or cap breach in LLM output | Phase 2 (pre-write audit gate) + Phase 3 (CI fixture with @import) | Inject @import into mock LLM output; assert adopt blocks before user approval |
| CR-6: Trusting LLM archive decisions | Phase 3 (`restructure` skill design — archive as separate step) | Fixture with file containing "we decided never to"; assert it is flagged for individual review |
| CR-7: Scaling / approval fatigue | Phase 1 (streaming classification) + Phase 1 (hierarchical grouping) | Run `--dry-run` on 500-file fixture; assert < 30 seconds and hierarchical approval output |
| M-1: Non-reproducible LLM extraction | Phase 2 (approve-and-record with sha256) + Phase 2 (idempotent re-run) | Run adopt twice; assert second run skips LLM steps for already-approved content |
| M-2: Symlinks / binaries in inventory | Phase 1 (inventory classification filters) | Fixture with symlink; assert inventory skips symlink and RESTRUCTURE-LOG records skip |
| M-3: Idempotency failure | Phase 2 (sha256 no-op check in mutate_write for adopt) | Run adopt twice; assert zero mutations on second run |
| M-4: Cross-platform backup paths | Phase 2 (UTC timestamp, absolute paths, quote-safe cp) | Run on Git Bash fixture; assert backup path uses `Z` suffix and restores correctly |
| M-5: RESTRUCTURE-LOG unbounded growth | Phase 3 (per-run structure + 1000-line rotation) | Run adopt 5 times on fixture; assert log has structured per-run sections and summary at top |

---

## Sources

- Conjure working tree (HIGH): `lib/mutate.sh` (mutation chokepoint), `lib/merge.sh` (3-way merge/sidecar pattern), `migrations/from-claude/migrate.sh` (existing brownfield detection logic), `cli/conjure` (dispatcher), `.planning/PROJECT.md` (v0.6.0 goals + constraints)
- [Consolidation vs. Summarization vs. Distillation in LLM Context Compression](https://medium.com/@RLavigne42/consolidation-vs-summarization-vs-distillation-in-llm-context-compression-c96fa5956057) (MEDIUM — LLM condensation tradeoffs; summarization deliberately discards peripheral details)
- [From Single to Multi: How LLMs Hallucinate in Multi-Document Summarization](https://arxiv.org/pdf/2410.13961) (MEDIUM — up to 75% hallucination rate in summaries; "lost in the middle" effect)
- [How to write idempotent Bash scripts](https://arslan.io/2019/07/03/how-to-write-idempotent-bash-scripts/) (MEDIUM — check-before-write patterns for bash idempotency)
- [Approval Fatigue — Encyclopedia of Agentic Coding Patterns](https://aipatternbook.com/approval-fatigue) (MEDIUM — batch approvals via steering loop; individual approval for high-risk actions)
- [The Agent Approval Fatigue Problem](https://molten.bot/blog/agent-approval-fatigue/) (MEDIUM — rubber-stamping when approval rate exceeds human cognitive bandwidth)
- [Backup Integrity Verification Framework](https://oneuptime.com/blog/post/2026-01-30-backup-verification-testing/view) (MEDIUM — five levels: existence, integrity, partial restore, full restore, application verification)
- [Best Rollback Readiness Checks](https://us.fitgap.com/stack-guides/rollback-readiness-checks-that-prevent-missing-prerequisites-during-incidents/) (MEDIUM — codify prerequisites, enforce as deploy gates, test restore paths)
- [cygpath path translation reference](https://cygwin.com/cygwin-ug-net/cygpath.html) (MEDIUM — Windows/Unix path format differences; `/c/` vs `/mnt/c/` across Git Bash and WSL)
- [Symbolic Links in Bash Programming](https://uomresearchit.github.io/shell-programming-course/08-symlinks/index.html) (MEDIUM — `find -L` dereferences symlinks; `-xtype l` finds broken symlinks; risk of data loss when symlink targets move)
- [Semantic Override Hallucinations in LLM Reasoning](https://arxiv.org/html/2602.17520) (MEDIUM — models revert to pretrained defaults despite explicit redefinition; constraint dropping in algebraic manipulation)

---
*Pitfalls research for: Conjure v0.6.0 Safe Brownfield Adoption — LLM-assisted restructure with deterministic file operations*
*Researched: 2026-05-28*
