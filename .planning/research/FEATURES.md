# Feature Research — v0.6.0 Safe Brownfield Adoption

**Domain:** CLI-driven brownfield project rehabilitation — inventory, classify, scaffold, condense, archive, rollback
**Researched:** 2026-05-28
**Milestone:** v0.6.0 — Safe Brownfield Adoption
**Confidence:** HIGH for safety primitives (existing codebase verified directly + comparable tool patterns); HIGH for UX
expectations from codemod/linter-with-autofix/migration-tool comparators; MEDIUM for LLM-skill UX patterns (design-space area)

---

## How Comparable Tools Handle This Problem

Before feature-by-feature analysis, comparator tools surface strong user expectations for any "safe adopt / rehabilitate" workflow.

### jscodeshift / Next.js Codemods (codemods with dry-run + skip reporting)
- `--dry` flag: applies transform but writes nothing; `-p` (`--print`) shows generated output to stdout
- Produces per-file SKIP / OK / ERROR report at end of run
- Idempotent by design: re-running on already-transformed code is a no-op (transform detects its post-condition is already met)
- "Phase 5: Validate at scale" is explicit in the recommended codemod workflow: dry-run first on the full corpus, review a sample, then re-run with `--fail-on-error`
- Guidance: insert TODO comments at edge cases rather than failing or silently skipping — surface ambiguity instead of suppressing it
- **Expectation this sets:** users want `--dry-run` to show every file that WOULD change and why, then an explicit apply step

### ESLint `--fix` / `--fix-dry-run` + Ruff safe/unsafe fixes
- ESLint `--fix-dry-run`: applies fixes in memory, reports the fixed content without writing files; requires a custom formatter to make output readable
- ESLint-interactive: groups violations by rule, shows count of fixable problems per rule, lets the user act on one rule at a time — granular, human-gated
- Ruff safe vs unsafe: safe fixes are applied by default; unsafe fixes (may change semantics) require `--unsafe-fixes` opt-in. Per-rule safety level is configurable
- **Expectation this sets:** mutation safety must be categorized — some changes are deterministic and safe to apply automatically; others require human review before application. The user must be able to see what category each proposed change falls into before approving

### OpenRewrite (large-scale Java refactoring)
- "Do no harm": if a recipe cannot determine a change is safe, it makes no change
- Dry-run via `dryRun` Maven goal: prints which visitors would make changes to which files, without altering source
- Every change is previewable as a structured diff before commit; rollback is supported
- Search-only recipes surface findings for human review rather than applying automatically
- **Expectation this sets:** for any change that requires judgment, tools should produce a "findings report" first, not apply changes silently. Human approval gates the transition from "report" to "apply"

### Terraform plan/apply (show-before-mutate)
- `terraform plan` is a required pre-step: shows every change with symbols (+/-/~) before any infrastructure is touched
- Plan output is saveable to a binary file; `apply` consumes that exact plan — what was reviewed is exactly what gets applied, no surprises
- Idempotent: if desired state matches current state, no changes are made
- **Expectation this sets:** "plan then apply" is the canonical UX for any tool that touches infrastructure. Users trained on Terraform expect to see a numbered list of changes before executing them

### Flyway / Liquibase (migration-state tracking)
- Maintain a `DATABASECHANGELOG` (or equivalent) table that records every applied migration with: id, description, checksum, execution timestamp
- On re-run, check the log to skip already-applied changesets — idempotency by state record
- Pre-conditions: `ON_FAIL: MARK_RAN` allows safe idempotent re-runs
- **Expectation this sets:** a persisted log of "what was done and when" is not optional. Users need it for audits, for debugging, and for safe re-runs. The log IS the rollback key

### chezmoi (dotfile manager — state-aware adoption)
- `chezmoi import` reads existing dotfiles and absorbs them into the managed state
- Additive by default: never deletes unmanaged files during initial adoption
- `chezmoi diff` (read-only) before `chezmoi apply` (write); never mutates without an explicit apply
- `chezmoi data` shows the current managed state inventory
- **Expectation this sets:** "import existing" flows must be non-destructive. The tool reads first, classifies, then proposes — never deletes without explicit user action

### "Import existing config" brownfield onboarding flows (VMware VCF, spec-driven-development, Terraform brownfield import)
- Core pattern: read current state → build inventory → compare to desired state → show delta → apply with approval
- Pilot conversion in a sandbox / dry-run before live apply is universal
- Archiving historical data outside the live system (rather than deleting it) is standard in all SAP/VMware brownfield migrations — "move only what you need, archive the rest"
- **Expectation this sets:** the inventory step is not optional and must be visible to the user before any mutations. Archive-not-delete is expected default behavior

---

## "Lose Nothing" — Concrete, Testable Behaviors

The user's explicit demand "lose nothing" maps to these observable, testable requirements:

1. **Full snapshot before any mutation.** Before `conjure adopt` writes a single byte, every path it will touch must be copied to a timestamped backup directory (e.g., `.conjure-adopt-backup-<ISO8601>/`). Testable: backup dir exists and contains exact copies of all mutated files, verifiable by sha256 comparison before vs. after adopt run.

2. **Archive-not-delete.** Files classified as "stale" or "superseded" are moved to `.conjure-archive-<timestamp>/`, never `rm`'d. Testable: no file that existed before `conjure adopt` is absent after the run; `find <repo> -name <stale_file>` returns the file in the archive location.

3. **`--dry-run` shows every planned mutation without writing anything.** `DRY_RUN=1` must produce the same plan output as a live run but zero filesystem side-effects. Testable: `DRY_RUN=1 conjure adopt` followed by `find <repo> -newer <timestamp_before>` finds only files the test itself created — no conjure writes.

4. **`--rollback` restores the snapshot exactly.** After a live run, `conjure adopt --rollback` must restore every mutated file to its pre-adopt state from the backup dir. Testable: sha256 of every mutated file after rollback equals sha256 recorded in the backup manifest before the run.

5. **`RESTRUCTURE-LOG.md` is written at every step, not only at the end.** Each individual mutation (scaffold layer, mutate CLAUDE.md, archive file) appends a log entry before the next mutation starts. Testable: if the process is killed mid-run, the log reflects the exact steps completed so far — no silent gaps.

6. **Idempotent re-run.** Running `conjure adopt` a second time on an already-adopted project must detect the existing state and produce "nothing to do" or "N steps already applied, 0 pending" — not re-apply work or corrupt already-correct state. Testable: sha256 of all managed files after second run equals sha256 after first run.

7. **`--force` required to proceed on dirty git tree.** If `git status` shows any uncommitted changes, `conjure adopt` refuses with a clear message pointing to the `--force` flag. Testable: `conjure adopt` in a repo with a staged change exits non-zero without writing anything; with `--force` it proceeds and writes a warning to the log.

8. **Never-delete is unconditional.** No flag or option causes `conjure adopt` to permanently delete any user file. `mutate_rm` must not be called by `adopt.sh` on user content — only on conjure-internal temporary files. Testable: audit `adopt.sh` for any call to `mutate_rm` on non-temporary paths; fuzz the doc corpus and verify all input files are present in either the repo or the archive after any run.

---

## Feature Landscape

### Table Stakes (Users Expect These)

Features users assume exist in any "safe adopt" tool. Missing these = product feels incomplete or untrustworthy.

| Feature | Why Expected | Complexity | Dependencies on Existing Conjure Features |
|---------|--------------|------------|------------------------------------------|
| `--dry-run` flag — shows full plan, writes nothing | Every migration tool in the comparator set ships this. Without it, users cannot safely explore what adopt will do. Terraform plan, jscodeshift `--dry`, ESLint `--fix-dry-run` — all three enforce this contract. | LOW — `lib/mutate.sh` already implements `DRY_RUN=1` for all write primitives; adopt.sh must source it and honor the flag throughout | `lib/mutate.sh` (fully shipped); all mutate_* calls already dry-run safe |
| Full timestamped snapshot backup before first mutation | Any tool that touches a project without a backup first will be blamed for data loss. The expectation is hardened by git-before-refactor conventions and chezmoi's import model. | MEDIUM — new `mutate_snapshot` primitive or inline cp loop; must handle large directories (argus has 2180 markdown files); needs a manifest file listing what was captured | `lib/mutate.sh` (must extend with snapshot primitive); existing `mutate_cp` for file-by-file copies |
| Markdown inventory: list every `.md` file with its path, line count, and classification | Users cannot approve or review changes to files they haven't seen listed. chezmoi's `data` command and Terraform's plan output both surface the full scope before any action. The argus fixture (2180 files) makes this non-trivial but mandatory. | MEDIUM — POSIX `find` + `wc -l` loop; classification buckets must be defined (harness core / skill-candidate / agent-candidate / reference-doc / planning-artifact / stale-candidate); write inventory to `.conjure-adopt-inventory.md` | None — pure read path, no existing feature dependency |
| Size-cap audit gate embedded in adopt flow | Users must see which files violate caps before and after restructure. Shipping adopt without the size-cap audit would mean users could adopt into a broken harness. | LOW — `scripts/audit-setup.sh` already implements size-cap checks; adopt calls it as a read-only pre-flight and again as post-flight verification | `scripts/audit-setup.sh` (fully shipped, used by `conjure audit`) |
| `RESTRUCTURE-LOG.md` — per-step persisted changelog | The user's explicit demand: "clear message of what changed at each step." Liquibase's DATABASECHANGELOG, Flyway's schema_history, and Terraform's state file all serve this function. Without persistence, users cannot recover from a partial run or understand what was done. | MEDIUM — new `log_step` helper; appends one line per step in ISO8601 + action + source + destination format; written via `mutate_write --append`; creates the file if absent; survives mid-run kill | `lib/mutate.sh` (mutate_write --append already implemented) |
| `--rollback` flag — restore from snapshot | Users who ran adopt and dislike the result need an escape. Terraform's rollback, chezmoi's revert, and every database migration tool's down-migration serve this expectation. Must be a single command, not a manual copy. | MEDIUM — reads backup manifest; iterates entries; copies backup/ → original path via `mutate_cp`; emits per-file restore log to RESTRUCTURE-LOG.md | `lib/mutate.sh` (mutate_cp); snapshot backup (new, required first) |
| Git-clean precondition — refuse dirty working tree | Every migration tool that does large-scale mutation (jscodeshift, chezmoi apply, OpenRewrite) recommends or enforces a clean git state before running. This is the cheapest safety net: if something goes wrong, `git checkout -- .` is the escape. | LOW — `git status --porcelain` output check; if non-empty, print error + `--force` hint and exit 2; same pattern as conjure hooks exit 2 convention | `git` (hard dep already); exit 2 convention already established in conjure |
| Scaffold missing harness layers | `conjure adopt` must wire up missing `.claude/` structure (skills/, agents/, hooks/) without overwriting what already exists. This is `conjure init`'s additive scaffold, reused as a sub-step of adopt. | LOW — call `scripts/init-project.sh` in additive mode (already skips existing files); adopt wraps this as one logged step | `scripts/init-project.sh` (fully shipped); additive-only behavior already correct |
| Never-delete: archive stale files to `.conjure-archive-<timestamp>/` | Users trust adopt only if they know nothing will be permanently erased. Archive-not-delete is the "lose nothing" contract made concrete. The SAP/VMware brownfield migration pattern universally separates "active" from "archived" rather than deleting. | LOW — `mutate_archive` primitive = `mutate_cp src archive/ && note_in_log "archived $src"`; never calls `mutate_rm` on user content | `lib/mutate.sh` (mutate_cp); new `mutate_archive` wrapper |
| `--force` flag — override git-clean precondition | CI/CD pipelines and users who understand the risk must be able to bypass the git-clean gate explicitly. The `--force` pattern is established by git itself and by jscodeshift's `--fail-on-error`. | LOW — parse `--force` flag; skip git status check when set; write a warning line to RESTRUCTURE-LOG.md noting that git-clean was bypassed | None |

### Differentiators (What Sets v0.6.0 Apart)

| Feature | Value Proposition | Complexity | Dependencies on Existing Conjure Features |
|---------|-------------------|------------|------------------------------------------|
| `restructure` skill — LLM judgment in-session, human-gated | The classification problem (what goes to skills vs. agents vs. reference docs vs. stale) requires reading and understanding content, not just measuring it. An LLM skill can propose decomposition of an oversized CLAUDE.md; a human approves each proposal; CLI primitives execute each approval. This hybrid (deterministic execution + LLM judgment + human gate) is unique in this space. | HIGH — skill SKILL.md must be written; it must read the adopt inventory, oversized CLAUDE.md, and doc sprawl; propose structured output; each proposal is human-gated; approved proposals are dispatched to CLI safe primitives. No existing pattern in conjure; the first skill that outputs structured commands for CLI execution | `scripts/audit-setup.sh` (size caps); inventory file (new); `conjure adopt` CLI primitives (new); existing skill frontmatter schema (fully shipped) |
| Inventory classification with actionable buckets | Classifying files into: `harness-core` / `skill-candidate` / `agent-candidate` / `reference-doc` / `planning-artifact` / `stale-candidate` gives users a structured view of their doc sprawl before they do anything. No comparator tool does this for markdown/doc sprawl specifically. | MEDIUM — classification heuristics per bucket (path pattern + line count + frontmatter presence + keyword match); written to `.conjure-adopt-inventory.md` in a table format; the `restructure` skill reads this file | None — new capability; uses POSIX tools only |
| `RESTRUCTURE-LOG.md` in human-readable structured format | Liquibase's changelog is a machine format. Conjure's log targets human readability (step number, timestamp, action verb, source path, destination path, outcome) while being grep-able. This makes it a usable audit trail for teams and a recovery guide when runs are interrupted. | LOW — define a log line format: `[YYYY-MM-DDTHH:MM:SSZ] STEP N: ACTION source → destination (OUTCOME)`; `log_step` function appends via `mutate_write --append` | `lib/mutate.sh` (mutate_write --append already works) |
| Idempotent re-run via state detection | Re-running adopt on an already-adopted project should not duplicate scaffold, re-archive files, or corrupt the log. State is detected by checking `.conjure-adopt-state` marker (written by adopt on first successful run) and comparing inventory hashes. This follows Flyway's "check the log before applying" pattern. | MEDIUM — write a `.conjure-adopt-state` file (JSON or simple key=value) recording which steps completed with their input sha256; on re-run, skip steps whose pre-condition sha256 still matches | None — new state file convention; consistent with `.conjure-version` and `.conjure-overlay` existing marker files |
| Machine-readable inventory output (`--json`) | Teams that integrate adopt into CI pipelines or dashboards need programmatic access to the inventory. `--json` emits the classification table as JSONL to stdout. Consistent with `conjure check --json` (v0.5.0 differentiator). | LOW — serialize inventory array as JSONL; one object per file with: path, lines, classification, action | `conjure check --json` precedent (v0.5.0); `jq` already a hard dep |
| Adoption report summarizing the before/after state | After `conjure adopt` completes, print a structured summary: files inventoried, layers scaffolded, files archived, CLAUDE.md before/after line count, size-cap compliance status. This closes the loop the way OpenRewrite's build-log summary and Terraform's apply output close theirs. | LOW — collect counts during execution; print summary at end; mirror it to the tail of RESTRUCTURE-LOG.md | All adopt sub-steps |

### Anti-Features (Explicit Non-Goals)

| Anti-Feature | Why Requested | Why Problematic | What to Do Instead |
|--------------|---------------|-----------------|-------------------|
| Fully autonomous adopt (no-human-approval restructure) | "Just fix it for me" — the appeal of zero-friction | Content judgment (what is stale, what should become a skill) cannot be made safely without human sign-off. A wrong autonomous decision on CLAUDE.md content changes the AI's behavior on every future session. Silent autonomous rewrites break user trust when they notice unexpected changes. PROJECT.md explicitly calls this a non-goal. | The `restructure` skill proposes; the human approves each step; CLI primitives execute. Never execute content judgment without a human gate. |
| Deleting any user file permanently | "Clean up the mess" — users want clutter gone | Permanent deletion during an adopt run would violate "lose nothing." Any file that looks stale might be the one the user needs next week. Recovery after accidental deletion during a tool run is a support nightmare. | Archive to `.conjure-archive-<timestamp>/`; the user can delete the archive manually when satisfied |
| Rewriting CLAUDE.md content autonomously | "Fix my oversized CLAUDE.md" — users see an obvious problem | Content rewriting changes the AI's behavior. Even a well-intentioned rewrite could remove important constraints or add unwanted ones. This is a judgment call, not a deterministic operation. | The `restructure` skill proposes extractions; the human approves each one; `conjure adopt` applies via `mutate_write` only on explicit approval |
| Cross-repo or workspace orchestration | "Adopt all my repos at once" | Scope explosion: cross-repo concerns belong to v0.7.0. Including cross-repo logic in v0.6.0 would delay shipping the single-repo story and introduce complex rollback semantics. | Single-repo only in v0.6.0. Cross-repo orchestration deferred explicitly in PROJECT.md to v0.7.0. |
| Interactive TUI (curses, fzf, dialog) for the inventory approval flow | "Show me a nice interface" | Breaks CI usage, adds runtime deps, excludes Windows Git Bash users. v0.5.0 `conjure resolve` intentionally avoided this. The `restructure` skill's interaction happens in Claude Code's session, not in the CLI. | CLI prints proposals; human responds with `y/n` or `s` (skip); editor is `$EDITOR` for edits. Same model as `conjure resolve`. |
| Automatic commit or push after adopt | "One-command commit" | Silent commits to a repo are a trust violation. Any mutation to the repo's history must be initiated by the user. | Print "commit when ready" in the post-adopt summary; never `git commit` or `git push` from within `conjure adopt` |
| Incorporating `conjure migrate` logic | "Detect if this came from Cursor/Aider and migrate it too" | `conjure migrate` already handles competitor-to-conjure migration. Combining it with brownfield adopt creates a single script that does too much. Users who need migration should run `conjure migrate` first, then `conjure adopt`. | Document the recommended two-step sequence in RESTRUCTURE-LOG.md preamble; keep `adopt` and `migrate` separate |
| Size-cap auto-fix (truncate oversized files) | "Just trim the file for me" | Truncating a file at a line count boundary almost certainly destroys content coherence. The correct response to an oversized CLAUDE.md is extraction, not truncation. | Audit reports the cap violation; `restructure` skill proposes what to extract; extraction is human-gated |

---

## Feature Dependencies

```
[git-clean precondition]
    └──required-by──> [conjure adopt (any live run)]
                          cannot safely mutate without a clean recovery path

[full snapshot backup]
    └──required-by──> [--rollback flag]
                          rollback needs the snapshot to restore from
    └──required-by──> ["lose nothing" guarantee]
                          testable only if backup manifest exists

[markdown inventory + classification]
    └──required-by──> [restructure skill]
                          skill reads inventory to propose extractions
    └──required-by──> [adoption report summary]
                          summary aggregates inventory counts
    └──required-by──> [idempotent re-run]
                          state comparison uses inventory hashes

[RESTRUCTURE-LOG.md]
    └──required-by──> [--rollback flag]
                          rollback reads log to identify steps to undo
    └──required-by──> [idempotent re-run]
                          state file records completed steps
    └──enables──>     [audit trail / team review]

[scaffold missing harness layers]
    └──requires──>    [scripts/init-project.sh (already shipped)]
                          adopt calls init-project in additive mode
    └──required-by──> [adoption report summary]
                          summary reports what was scaffolded

[size-cap audit gate]
    └──requires──>    [scripts/audit-setup.sh (already shipped)]
                          adopt calls audit as pre-flight + post-flight
    └──required-by──> [restructure skill]
                          skill knows which files violate caps from pre-flight

[lib/mutate.sh (already shipped)]
    └──required-by──> [all write operations in adopt.sh]
    └──extend-with──> [mutate_snapshot (new)]
    └──extend-with──> [mutate_archive (new)]
    └──extend-with──> [log_step (new, uses mutate_write --append)]

[restructure skill]
    └──requires──>    [inventory file (new)]
    └──requires──>    [conjure adopt CLI primitives (new)]
    └──requires──>    [human approval per step (design)]
    └──outputs──>     [structured commands dispatched to CLI]

[--dry-run]
    └──requires──>    [lib/mutate.sh DRY_RUN=1 (already shipped)]
    └──enables──>     [safe exploration before any commitment]

[conjure adopt (all steps)]
    └──requires──>    [git-clean precondition OR --force flag]
    └──requires──>    [full snapshot backup]
    └──produces──>    [RESTRUCTURE-LOG.md]
    └──produces──>    [.conjure-adopt-inventory.md]
    └──produces──>    [.conjure-adopt-state]
    └──may-produce──> [.conjure-archive-<timestamp>/]
```

### Dependency Notes

- **Snapshot backup requires lib/mutate.sh extension:** `mutate_snapshot` is a new primitive that wraps `mutate_cp` in a loop over all touched paths. It must write a manifest file (sha256 per file) for rollback verification. Without this manifest, rollback cannot verify fidelity.

- **RESTRUCTURE-LOG.md requires mutate_write --append:** This already works in `lib/mutate.sh`. The `log_step` function is a thin wrapper that formats the line and calls `mutate_write --append`. It must also work under `DRY_RUN=1` (printing `[dry-run] would log: <line>` instead of writing).

- **Idempotent re-run conflicts with stateless adoption:** The `.conjure-adopt-state` file is the resolution. On first run it does not exist; adopt runs fully. On subsequent runs it exists; adopt compares current sha256 values of managed paths against the state file's recorded hashes and skips steps whose pre-condition is already met.

- **`restructure` skill depends on the CLI adopt command existing:** The skill cannot run before `conjure adopt` is implemented, because it dispatches approved proposals to adopt's CLI primitives (e.g., `conjure adopt --archive <path>`, `conjure adopt --extract-skill <file>`). Build order: adopt CLI first, then skill.

- **`conjure migrate` and `conjure adopt` must not be called simultaneously:** Both modify `.claude/` and would produce conflicting state. Document as sequential: migrate first (converts tool-specific config), then adopt (rehabilitates the full project structure).

---

## MVP Definition

### Must Ship (v0.6.0 core)

The minimum viable `conjure adopt` that delivers on "lose nothing, report everything":

- [x] **Git-clean precondition + `--force` override** — why essential: the cheapest safety net; no other safety measure compensates for a dirty tree that can't be recovered via `git checkout`
- [x] **Full snapshot backup with sha256 manifest** — why essential: "lose nothing" is untestable without this; rollback requires it
- [x] **`--dry-run` plan output** — why essential: users will not run adopt live without first seeing the plan; every comparator tool ships this; absence makes adopt feel unsafe
- [x] **Markdown inventory + 6-bucket classification** — why essential: without an inventory, the restructure skill has nothing to read and users have no basis for approval decisions
- [x] **Scaffold missing harness layers (calls init-project.sh)** — why essential: adopt's primary deliverable is a correct four-layer harness; without scaffold, adopt is just an audit
- [x] **Size-cap audit gate (pre-flight + post-flight, calls audit-setup.sh)** — why essential: shipping adopt that produces a harness violating caps would be worse than not shipping
- [x] **Never-delete / archive-not-delete (`mutate_archive`)** — why essential: this is the user-visible "lose nothing" guarantee; must be present from day one
- [x] **`RESTRUCTURE-LOG.md` per-step structured changelog** — why essential: the user explicitly demanded "clear message of what changed at each step"; this is non-negotiable
- [x] **`--rollback` from snapshot** — why essential: without rollback, users cannot safely run adopt on a production project; it would be a one-way door
- [x] **`restructure` skill (SKILL.md)** — why essential: the oversized CLAUDE.md problem cannot be solved by deterministic rules alone; the skill is the judgment layer for the main user pain point

### Add After Validation (v0.6.x)

- [ ] **Idempotent re-run via `.conjure-adopt-state`** — trigger: first field reports of users re-running adopt and getting duplicate log entries or scaffold re-application; adds MEDIUM complexity; most users won't re-run immediately
- [ ] **`--json` inventory output** — trigger: first CI pipeline integration request; LOW complexity; can ship as a fast follow

### Defer to v0.7.0+

- [ ] **Cross-repo / workspace orchestration** — explicitly deferred in PROJECT.md; depends on v0.6.0 single-repo story being validated first
- [ ] **TUI conflict resolution for restructure approvals** — low priority; the `y/n` prompt model from `conjure resolve` is adequate; full TUI deferred as in v0.5.0
- [ ] **Autonomous (no-approval) restructure** — explicit non-goal per PROJECT.md; requires a fundamentally different trust model

---

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| `--dry-run` (inherits lib/mutate.sh) | HIGH | LOW | P1 |
| Git-clean precondition + `--force` | HIGH | LOW | P1 |
| RESTRUCTURE-LOG.md per-step log | HIGH | LOW | P1 |
| Never-delete / mutate_archive primitive | HIGH | LOW | P1 |
| Scaffold missing layers (calls init-project.sh) | HIGH | LOW | P1 |
| Size-cap audit gate pre/post (calls audit-setup.sh) | HIGH | LOW | P1 |
| Markdown inventory + 6-bucket classification | HIGH | MEDIUM | P1 |
| Full snapshot backup + sha256 manifest | HIGH | MEDIUM | P1 |
| `--rollback` from snapshot | HIGH | MEDIUM | P1 |
| `restructure` skill (SKILL.md) | HIGH | HIGH | P1 |
| Adoption summary report (before/after) | MEDIUM | LOW | P2 |
| Idempotent re-run via state file | MEDIUM | MEDIUM | P2 |
| `--json` inventory output | LOW-MEDIUM | LOW | P2 |
| Machine-readable RESTRUCTURE-LOG entries | LOW | LOW | P3 |

**Priority key:** P1 = ships in v0.6.0 core; P2 = ships in v0.6.x fast-follow or in v0.6.0 if time allows; P3 = nice-to-have

---

## Comparator Tool Analysis

| UX Behavior | jscodeshift / Next.js codemods | ESLint-interactive / Ruff | Terraform plan/apply | Flyway / Liquibase | chezmoi import | conjure adopt v0.6.0 |
|-------------|-------------------------------|--------------------------|---------------------|--------------------|----------------|---------------------|
| Dry-run before mutate | `--dry` + `-p` (print) | `--fix-dry-run` + formatter | `terraform plan` (required pre-step) | `dryRun` goal | `chezmoi diff` | `--dry-run` via lib/mutate.sh |
| Inventory / scope preview | Per-file SKIP/OK/ERROR report | Per-rule problem count | Full change list (+/-/~) | Schema history table | `chezmoi data` | `.conjure-adopt-inventory.md` |
| Safety categorization | Idempotent by post-condition check | safe vs. unsafe fixes | "plan then apply" gating | "already ran" state table | Additive by default | 6-bucket classification + size-cap pre-flight |
| Per-step changelog | No persistent log; stdout only | No persistent log | Terraform state file | DATABASECHANGELOG table | No persistent log | `RESTRUCTURE-LOG.md` append-per-step |
| Rollback | git history (implicit) | git history (implicit) | `terraform destroy` / state manipulation | Down-migrations | `chezmoi revert` | `--rollback` from sha256 snapshot manifest |
| Archive-not-delete | No (git history is the backup) | No | No | No (down-migration) | No | Yes — `mutate_archive` to dated dir |
| Idempotent re-run | Yes (post-condition check) | Yes (rule re-check) | Yes (state comparison) | Yes (DATABASECHANGELOG) | Yes (state hash) | Yes via `.conjure-adopt-state` (P2) |
| Human gate | `--fail-on-error` review step | Per-rule interactive prompt | PR review of plan | DBA review of changelog | `chezmoi apply` confirmation | `restructure` skill per-step approval |
| Dirty-tree guard | Recommends clean git state | No | No | No | Yes (warns on conflict) | `git status --porcelain` exit 2 |

---

## Sources

- jscodeshift dry-run and codemod workflow: [My Workflow for Codemods](https://www.skovy.dev/blog/codemod-workflow) — MEDIUM confidence (community article, patterns verified against jscodeshift docs)
- jscodeshift `--dry` flag: [jscodeshift npm](https://www.npmjs.com/package/jscodeshift) — HIGH confidence (package docs)
- Codemods as large-scale refactoring pattern: [Codemods: Automated API Refactoring](https://martinfowler.com/articles/codemods-api-refactoring.html) — HIGH confidence (Martin Fowler, verified)
- ESLint `--fix-dry-run` and `--fix-type`: [ESLint CLI Reference](https://eslint.org/docs/latest/use/command-line-interface) — HIGH confidence (official docs)
- ESLint-interactive per-rule interactive fixing: [eslint-interactive GitHub](https://github.com/mizdra/eslint-interactive) — HIGH confidence (README verified)
- Ruff safe vs. unsafe fixes: [The Ruff Linter](https://docs.astral.sh/ruff/linter/) and [Ruff unsafe fixes issue](https://github.com/astral-sh/ruff/issues/4181) — HIGH confidence (official docs + issue)
- OpenRewrite "do no harm" + dry-run: [Understanding OpenRewrite](https://www.moderne.ai/blog/understanding-openrewrite-beyond-the-myths) and [Recipe conventions](https://docs.openrewrite.org/authoring-recipes/recipe-conventions-and-best-practices) — HIGH confidence (official docs)
- Terraform plan/apply idempotency: [terraform plan reference](https://developer.hashicorp.com/terraform/cli/commands/plan) — HIGH confidence (official HashiCorp docs)
- Flyway/Liquibase state tracking: [Flyway vs Liquibase](https://www.bytebase.com/blog/flyway-vs-liquibase/) and [Idempotent Liquibase Changesets](https://imhoratiu.wordpress.com/2023/05/30/idempotent-liquibase-change-sets/) — MEDIUM confidence (verified against known behavior)
- Brownfield VITA framework: [Brownfield (software development) Wikipedia](https://en.wikipedia.org/wiki/Brownfield_(software_development)) — MEDIUM confidence (taxonomy useful, not prescriptive)
- chezmoi import + diff + apply workflow: inferred from previous v0.5.0 research (HIGH confidence, chezmoi docs verified in that session)
- Git clean precondition / requireForce: [git-clean documentation](https://git-scm.com/docs/git-clean) — HIGH confidence (official git docs)
- Conjure internal: `lib/mutate.sh`, `scripts/audit-setup.sh`, `scripts/init-project.sh`, `scripts/check.sh`, `scripts/resolve.sh`, `.planning/PROJECT.md` — HIGH confidence (read directly this session)

---
*Feature research for: Conjure v0.6.0 Safe Brownfield Adoption*
*Researched: 2026-05-28*
