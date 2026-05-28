# Project Research Summary

**Project:** Conjure v0.6.0 — Safe Brownfield Adoption
**Domain:** Deterministic CLI-driven rehabilitation of messy existing repos into the conjure four-layer harness, with LLM judgment supplied by a human-gated skill
**Researched:** 2026-05-28
**Confidence:** HIGH

## Executive Summary

v0.6.0 adds the ability to take a grown-messy project — the canonical stress fixture ("argus") has 2180 markdown files, a 21 KB / 180-line CLAUDE.md against a 100-line cap, 35 GSD planning docs, and a `.claude/` with settings only — and fold it cleanly into the conjure four-layer harness without losing a single byte. The approach is split across two cooperating components: `conjure adopt` (deterministic bash CLI: snapshot, inventory, scaffold, audit, apply, log) and a `restructure` skill (in-session Claude, human-gated, judgment only). The CLI owns every filesystem mutation; the skill owns all judgment; the skill calls the CLI for every write; the CLI never calls the skill. This split is the design center of v0.6.0.

The stack introduces zero new dependencies. Every primitive — `find -print0 | xargs -0 wc -l` for inventory, `cp -a` for snapshot, `git status --porcelain=v1` for the clean gate, `wc -l <` redirect for cap detection, `jq -cn --slurpfile` for manifest construction — is already in the preflight stack. New lib files (`lib/log.sh`, `lib/snapshot.sh`, `lib/inventory.sh`) layer cleanly on the unchanged `lib/mutate.sh` chokepoint. The `adopt-manifest.json` is the integration contract between CLI and skill, with a summary-first structure so the skill can load the 2180-file index selectively rather than injecting all 175 KB of JSON into context at once.

The research surfaces seven critical pitfalls that directly drive implementation requirements, the most severe being: (1) LLM condensation silently dropping embedded constraints — caught by a pre-pass constraint extraction and a post-LLM invariant check before user approval; (2) partial-apply corruption from interrupts — caught by a step-completion manifest and signal traps from day one; (3) the snapshot vs git-state interaction — addressed by recording git HEAD sha in a `snapshot-meta.json` and warning explicitly when `--force` is used on a dirty tree; and (4) approval fatigue at 2000+ files — addressed by hierarchical grouped approvals, never 2180 individual prompts. These are not hardening concerns; they are day-one requirements.

## Key Findings

### Recommended Stack

The v0.6.0 stack is a strict zero-new-dependencies extension of v0.5.0. All inventory, snapshot, classification, manifest generation, and patch application primitives are assembled from tools already in the preflight gate. Three new `lib/` files are added (`lib/log.sh`, `lib/snapshot.sh`, `lib/inventory.sh`), one new `scripts/` worker (`scripts/adopt.sh`), one new constant file (`lib/caps.sh` — 5 lines extracting the hardcoded line caps from `audit-setup.sh`), and one new skill template (`templates/skills/restructure/SKILL.md`). `lib/mutate.sh` is unchanged; `scripts/audit-setup.sh` and `scripts/init-project.sh` are unchanged and called as subprocesses.

**Core techniques:**
- `find <root> -name '*.md' -print0 | xargs -0 wc -l` — batch inventory without per-file fork; 2180 files in under 2 seconds on NVMe; POSIX 3.2+
- `cp -a <target> <backup>` — full timestamped snapshot before any mutation; `-a` preserves timestamps + symlink structure (macOS 10.5+, all GNU); `cp -Rp` as documented POSIX fallback
- `git -C "" status --porcelain=v1` — clean gate; empty output = clean; unaffected by color/locale config; catches untracked files that `git diff --quiet` misses
- `wc -l < "$path"` (redirect form, no filename noise) — cap detection; compare to constants in `lib/caps.sh` (`CLAUDE_MD_CAP=100`, `SKILL_MD_CAP=200`, `AGENT_MD_CAP=80`)
- `jq -cn --arg ... --slurpfile` — manifest construction with no shell string interpolation (injection-safe); `--slurpfile` reads JSONL temp file as JSON array; `group_by + from_entries` for per-class summary
- `adopt-manifest.json` as CLI→skill contract; summary-first structure enables `!jq '\{summary, claude_md\}' .claude/adopt-manifest.json` selective injection in the skill rather than loading 175 KB into context
- Per-step patch files under `.claude/adopt-patches/<step-id>.json`; skill writes via `Write` tool; CLI reads via `jq -r ".operations[\]..."` loop and executes via `mutate_*` primitives
- `lib/log.sh` writes `RESTRUCTURE-LOG.md` via `mutate_write --append`; all writes honor `DRY_RUN`; log is human-readable markdown with grep-parseable `[TIMESTAMP] [PHASE] message` format
- `allowed-tools: [Read, Bash]` on the restructure skill — physically cannot call Write/Edit on project files; all mutations are forced through CLI, preserving the audit trail

**What NOT to add:**
- `ripgrep`, GNU `parallel`, or any tool not already in preflight — `find + xargs` is sufficient for 2180 files
- Full 2180-file `files[]` array injection into skill context — use summary + selective `jq` filters
- Inline JSON passed via CLI args for patch content — use patch files (quoting limits, non-reviewable)
- `mutate_rm` on user content files — only `archive` op (copy to `.conjure-archive/` then rm)
- `git status --short` — affected by user color config; `--porcelain=v1` is the contract-stable form

### Expected Features

The research frames v0.6.0 around 8 concrete, testable "lose nothing" behaviors, drawn from comparator tools (jscodeshift, ESLint `--fix-dry-run`, Terraform plan/apply, Flyway/Liquibase, chezmoi import):

**Must have (table stakes):**
- `--dry-run` shows every planned mutation without writing anything; `DRY_RUN=1` already honored by `lib/mutate.sh`; adopt must pass it throughout
- Full timestamped snapshot backup with sha256 manifest before first mutation — "lose nothing" is untestable without it; `--rollback` requires it
- Git-clean precondition (`git status --porcelain=v1`) with `exit 2` on dirty tree and `--force` override; required for safe recovery path
- Markdown inventory with 6-bucket classification (`harness-core`, `harness-skill`, `harness-agent`, `planning-doc`, `reference-doc`, `unknown`) emitted as `adopt-manifest.json`
- Scaffold missing harness layers via `scripts/init-project.sh` in additive mode (already idempotent)
- Size-cap audit gate pre-flight and post-flight via `scripts/audit-setup.sh` as subprocess
- Never-delete: `mutate_archive` moves stale files to `.conjure-archive-<ts>/`, never `rm`
- `RESTRUCTURE-LOG.md` append per step (not only at end); survives mid-run kill; each entry before the next step begins
- `--rollback` restores snapshot exactly; sha256 of every mutated file after rollback equals sha256 recorded before the run
- `restructure` skill (SKILL.md) — the oversized CLAUDE.md problem requires LLM judgment; skill proposes, human approves each step, CLI applies

**Should have (differentiators):**
- RESTRUCTURE-LOG.md in human-readable structured format with per-run sections and summary at top
- Idempotent re-run via `.conjure-adopt-state` step-completion manifest (detects already-applied steps)
- Adoption report summarizing before/after state (files inventoried, layers scaffolded, archived, CLAUDE.md line count delta)
- Hierarchical grouped approvals for large corpora — summary per class, not 2180 individual prompts
- Pre-write invariant check (constraint extraction pre-pass on CLAUDE.md + verify every constraint present in proposed LLM output before user approval gate)
- Archive decisions as a separate, last step with decision-vocabulary scan ("decided", "we chose", "rationale", "do not", "never") to flag files for individual review

**Defer to v0.6.x or v0.7.0+:**
- `--json` inventory output for CI pipelines — fast follow after validation
- Cross-repo / workspace orchestration — explicitly deferred to v0.7.0 per PROJECT.md
- Interactive TUI for approvals — `y/n` prompt model from `conjure resolve` is adequate
- Autonomous (no-approval) restructure — explicit non-goal; requires a fundamentally different trust model

**Anti-features (explicit non-goals):**
- Fully autonomous restructure with no human approval — judgment cannot be made safely without sign-off
- Permanently deleting any user file under any flag or option
- Rewriting CLAUDE.md content autonomously without human-approved extraction steps
- Auto-committing or pushing after adopt — trust violation; user must commit
- Interactive TUI — breaks CI, adds deps, excludes Windows Git Bash

### Architecture Approach

The architecture enforces a strict split-responsibility model: the CLI owns all filesystem mutations (every write routes through `lib/mutate.sh`); the skill owns all LLM judgment; the skill calls the CLI for every write; the CLI never calls the skill. Three new libs layer on unchanged `lib/mutate.sh` without modifying it. Two existing scripts (`init-project.sh`, `audit-setup.sh`) are reused as subprocesses. The `adopt-manifest.json` is the integration contract — written by the CLI inventory phase, read by the skill, updated by the skill via `conjure adopt --update-manifest`, executed step-by-step via `conjure adopt --apply-step <id>`. The restructure skill's `allowed-tools: [Read, Bash]` restriction physically enforces the constraint that it cannot write project files directly.

**Major components:**
1. `lib/log.sh` (NEW) — `log_init` / `log_step` / `log_fail`; all writes via `mutate_write --append`; produces `RESTRUCTURE-LOG.md`; must be built first (everything else depends on logging)
2. `lib/snapshot.sh` (NEW) — `snapshot_create` (`cp -a`, unconditional in live mode) / `snapshot_rollback` / `snapshot_list`; uses raw `cp -a`, not `mutate_cp`, because it precedes all `mutate_*` calls
3. `lib/inventory.sh` (NEW) — `inventory_scan` / `inventory_classify` / `inventory_emit_manifest`; read-only; writes `adopt-manifest.json` via `mutate_write`; must support selective injection for large corpora
4. `scripts/adopt.sh` (NEW) — orchestrates the full pipeline (5 steps); sources all three new libs; calls `init-project.sh` and `audit-setup.sh` as subprocesses; handles `--rollback`, `--apply-step`, `--update-manifest`, `--inventory`, `--status` sub-operations; dispatched by new `cmd_adopt` in `cli/conjure`
5. `templates/skills/restructure/SKILL.md` (NEW) — installed to `.claude/skills/restructure/SKILL.md` by `adopt.sh` Step 3; reads manifest, proposes restructure plan, requires human approval per step, calls `conjure adopt --apply-step` for each approved step; restricted to `[Read, Bash]`
6. `lib/caps.sh` (NEW, 5 lines) — `CLAUDE_MD_CAP=100`, `SKILL_MD_CAP=200`, `AGENT_MD_CAP=80`; sourced by both `audit-setup.sh` (call site change only) and `adopt.sh` to prevent cap drift
7. `adopt-manifest.json` schema — the CLI to skill contract; `schema_version`, `summary` (first), `files[]`, `size_cap_violations`, `restructure_steps[]`; written at inventory time; `restructure_steps[]` populated by skill before `--apply-step` is called

**Build order (dependency-ordered):**
Step 1 `lib/log.sh` → Step 2 `lib/snapshot.sh` → Step 3 `lib/inventory.sh` + manifest schema → Step 4 `scripts/adopt.sh` + `cmd_adopt` → Step 5 `templates/skills/restructure/SKILL.md` → Step 6 integration tests (`tests/fixtures/brownfield-argus/`)

**Key anti-patterns to avoid:**
- Restructure skill using `Write`/`Edit` tools directly — bypasses `mutate.sh`, breaks `DRY_RUN` and audit trail
- `snapshot_create` routed through `mutate_cp` — snapshot must be unconditional in live mode; suppressing it under `DRY_RUN` removes the safety net
- Manifest written via shell heredoc/printf — bypasses `mutate_write`, `DRY_RUN` not honored
- `adopt.sh` re-implementing scaffold logic from `init-project.sh` — duplicate maintenance; call `init-project.sh existing $target` instead

### Critical Pitfalls

Seven critical pitfalls drive requirements directly. They are not hardening — they are day-one constraints.

1. **LLM invariant/constraint drop during condensation (CR-1)** — Run a constraint-extraction pre-pass on CLAUDE.md before invoking the skill (grep for `must`, `never`, `always`, `forbidden`, `exit 2`, `@imports`, size-cap numbers into `INVARIANTS.txt`); require the model to confirm each invariant appears in the proposed output; run the invariant check against proposed content before user approval (not after write). This is the highest-severity pitfall: a dropped constraint like "hooks must exit 2, never exit 1" is invisible to size-cap audit and only surfaces as a production incident.

2. **Partial-apply corruption (CR-2)** — Write a step-completion manifest at the end of each successfully completed step (not at end of run); add `trap 'echo interrupted; exit 2' INT TERM` from day one; on restart after partial completion, detect the manifest and offer `[r]ollback / [c]ontinue / [s]tart fresh`. Snapshot is taken once at the start and reused on re-run — never re-snapshot an already-mutated tree.

3. **Snapshot/git-state interaction (CR-3)** — Capture git HEAD sha and `git stash list` in a `snapshot-meta.json` alongside the backup; warn prominently in RESTRUCTURE-LOG when `--force` is used on a dirty tree ("snapshot includes uncommitted changes; git rollback will NOT restore these — use `conjure adopt --rollback` only"); `--rollback` uses filesystem snapshot exclusively, never `git checkout --` or `git reset`.

4. **Archive is not rollback (CR-4)** — `--rollback` uses only the timestamped snapshot backup, not the archive folder (archive = "things adopted away from harness", not "pre-adopt state"). The step-completion manifest must record each file actually written (path + sha256 before + sha256 after) so rollback knows what to restore after an interrupted run, not just what was planned.

5. **Pre-write audit gate (CR-5)** — Run `conjure audit` against proposed LLM output before presenting to the user for approval. If the proposed output contains `@imports` (grep `^@`) or breaches the size cap, block the approval step with the audit output. The user must never be asked to approve invalid content — post-write audit is too late.

6. **Archive decisions require highest skepticism (CR-6)** — Archive steps must be sequenced last, individually confirmed, and gated by a decision-vocabulary scan ("decided", "we chose", "rationale", "do not", "never"). Files > 50 lines always require individual confirmation. Never batch more than 5 files in a single archive approval.

7. **Scaling to 2000+ files / approval fatigue (CR-7)** — Cap default inventory at 500 files (require `--full-inventory` for more); use streaming classification with a progress indicator; use hierarchical grouped approvals (per-class strategy, not per-file prompts); limit RESTRUCTURE-LOG entries for bulk operations to a summary line ("archived 31 of 35 GSD planning docs"). CI must assert `--dry-run` on a 500-file fixture completes in < 30 seconds.

## Implications for Roadmap

The research is unambiguous about build order: the dependency chain (log → snapshot → inventory → adopt.sh + manifest schema → skill) is deterministic. The pitfall-to-phase mapping from PITFALLS.md maps directly onto this sequence.

### Phase 1: Foundation Libs + Inventory

**Rationale:** `lib/log.sh` and `lib/snapshot.sh` have no inward dependencies (only `lib/mutate.sh`, already shipped). Everything else depends on them. The inventory + manifest schema must be finalized before the skill (reader) and `adopt.sh` (writer) are built. This phase also addresses CR-7 (scaling) by designing streaming classification and hierarchical grouping before any code is written.

**Delivers:** `lib/log.sh`, `lib/snapshot.sh`, `lib/inventory.sh`, `lib/caps.sh`, finalized `adopt-manifest.json` schema, streaming classification with 6-bucket heuristics, progress indicator pattern

**Addresses:** Git-clean precondition (LOW complexity, P1 feature), never-delete / `mutate_archive` primitive, cap constant extraction to `lib/caps.sh`

**Avoids:** CR-7 (design hierarchical approvals before implementation), M-2 (symlink + generated-file filters in the initial `find` pass), M-4 (UTC timestamps `date -u +%Y%m%dT%H%M%SZ`, absolute paths, `cp -a` vs `cp -r`)

**Research flag:** Standard patterns — no additional research needed. All primitives verified in STACK.md.

### Phase 2: `scripts/adopt.sh` + `cmd_adopt` + Rollback

**Rationale:** This is the CLI core. Once the three libs exist, `adopt.sh` can be written end-to-end: git-clean gate → snapshot → inventory → scaffold → audit → summary. The `--rollback` implementation requires the snapshot manifest (Phase 1) and the step-completion manifest (this phase). Signal traps and partial-apply recovery belong here — they are day-one requirements per CR-2, not hardening.

**Delivers:** Full `conjure adopt` pipeline (5 steps), `--dry-run` plan output, `--rollback` from snapshot, `--force` override, `--inventory` sub-operation, `cmd_adopt` dispatch in `cli/conjure`, step-completion manifest (`.conjure-adopt-state`), signal traps, `snapshot-meta.json` with git state (CR-3)

**Addresses:** All 8 "lose nothing" behaviors; `mutate_snapshot` as new `lib/mutate.sh` primitive; `--update-manifest` and `--apply-step` sub-operations (required by skill in Phase 3); `.gitignore` / `.claudeignore` additions for `.conjure-adopt-backups/`

**Avoids:** CR-2 (step manifest + signal traps from day one), CR-3 (snapshot-meta.json with git state), CR-4 (written-files log in manifest; rollback uses snapshot not archive), M-3 (sha256 no-op check in every `mutate_write` for adopt), M-4 (UTC timestamps, quote-safe paths), MN-2 (rollback guard when no snapshot exists)

**Research flag:** Standard patterns for most. The `--apply-step` / `--update-manifest` CLI→skill callback contract may need a planning-phase review of the step-id format and JSON schema validation depth (see Open Questions).

### Phase 3: `restructure` Skill + Pre-Write Audit Gate

**Rationale:** The skill can only be finalized after `--apply-step` and `--update-manifest` in Phase 2 are tested and locked. Writing the skill before the CLI callbacks exist produces documentation that cannot be verified. The pre-write audit gate (CR-5) and invariant check (CR-1) belong here because they operate on proposed LLM content before it reaches the user approval step.

**Delivers:** `templates/skills/restructure/SKILL.md` (installed by `adopt.sh` Step 3), constraint-extraction pre-pass (`INVARIANTS.txt` generation), pre-write `conjure audit` gate against proposed content, archive-as-last-step sequencing with decision-vocabulary scan (CR-6), RESTRUCTURE-LOG per-run structure with summary section (M-5), adoption report summary (before/after)

**Addresses:** `restructure` skill SKILL.md ≤200-line cap; `allowed-tools: [Read, Bash]` restriction; summary-first manifest injection pattern for 2180-file corpus; hierarchical grouped approvals

**Avoids:** CR-1 (invariant extraction + post-LLM verification gate blocks approval on missing constraint), CR-5 (`conjure audit` on proposed content before user sees it), CR-6 (archive as last step, decision-vocabulary scan, individual confirmation > 5 files), M-1 (approve-and-record with sha256 for non-reproducible LLM output), M-5 (per-run log structure + 1000-line rotation)

**Research flag:** Needs planning-phase review. The skill structured-output format and the step-id naming convention are design decisions not yet locked (see Open Questions). The skill body must stay ≤200 lines — tight given the instruction detail required. May need a planning spike to verify fit.

### Phase 4: Integration Tests + Argus Fixture

**Rationale:** The "looks done but isn't" checklist in PITFALLS.md is 9 items, all requiring fixture-based verification. Tests cannot be written until Phases 1-3 are complete. The argus stress fixture (2180 files) must be synthetic but representative — 500-file variant for CI performance assertion (< 30 seconds).

**Delivers:** `tests/fixtures/brownfield-argus/` fixture, tests covering: adopt `--dry-run` output, live run with manifest validation, `--rollback` zero-diff assertion, `--apply-step` execution + log entry, idempotent re-run (zero mutations), SIGKILL mid-run + recovery, 500-file performance assertion, symlink skip, `@import` guard (proposed content with `@import` must be blocked pre-write)

**Avoids:** All "looks done but isn't" checklist items; validates rollback fidelity (sha256 diff vs pre-adopt); validates approval fatigue mitigation (hierarchical output confirmed in dry-run)

**Research flag:** Standard patterns — bats-core integration tests following the v0.3.0 pattern. No additional research needed.

### Phase Ordering Rationale

The dependency chain is hard: `lib/log.sh` must exist before `lib/snapshot.sh` (snapshot calls `log_step`), which must exist before `scripts/adopt.sh` (adopt calls `snapshot_create`), which must exist before `templates/skills/restructure/SKILL.md` (skill calls `conjure adopt --apply-step`). No phase can be reordered without breaking a build-time dependency.

The pitfall-to-phase mapping confirms this order: CR-7 (scaling design) belongs in Phase 1 because classification heuristics cannot be retrofitted; CR-2 and CR-3 (partial-apply and snapshot/git) belong in Phase 2 because the manifest and traps are structural; CR-1 and CR-5 (LLM invariant and pre-write audit) belong in Phase 3 because they operate on skill output.

The only flexibility is Phase 4 (tests) — individual test stubs can be added incrementally alongside Phases 1-3, but the full integration suite must wait for Phase 3 to complete.

### Research Flags

Phases needing deeper research or design review during planning:
- **Phase 2 (adopt.sh):** Step-id format is unresolved (see Open Questions). The `--apply-step` / `--update-manifest` callback contract needs a planning-phase schema review before `adopt.sh` is coded, because the skill depends on this contract being stable.
- **Phase 3 (skill):** Skill structured-output format and manifest JSON vs key=value state file are open questions. The skill body must fit in ≤200 lines while covering: manifest loading, constraint checking, plan proposal, per-step approval loop, patch writing, and final audit. Tight. May need a planning-phase spike to verify fit.

Phases with standard patterns (skip additional research):
- **Phase 1 (libs):** All primitives are POSIX-verified in STACK.md. `lib/log.sh`, `lib/snapshot.sh`, `lib/inventory.sh` follow the same pattern as `lib/mutate.sh` and `lib/merge.sh`.
- **Phase 4 (tests):** bats-core fixture patterns are established from v0.3.0. The argus synthetic fixture is 500-file for CI; generation script is a simple loop.

## Open Questions

The research raised five open questions that are not resolvable from external sources — they require design decisions during planning. The roadmapper should create explicit decision points for each.

| Question | Why It Matters | Recommended Resolution Approach |
|----------|---------------|----------------------------------|
| **Step-id format** — human-readable slug (`extract-gsd-skill-01`) vs UUID vs monotonic integer | The skill writes step-ids; the CLI reads them; they appear in RESTRUCTURE-LOG.md and patch filenames. A collision or unparseable id corrupts the manifest. | Decide in Phase 2 planning before `adopt.sh` is coded. Recommendation: human-readable slug with a collision check (append `-N` suffix if exists). |
| **Manifest state format** — JSON (`adopt-manifest.json` + `restructure_steps[]`) vs separate key=value `.adopt-progress` file | A single JSON file is convenient for jq but requires read-modify-write atomicity. A key=value file is simpler but harder to extend. | Decide in Phase 2 planning. Recommendation: JSON manifest for the rich schema; key=value `.adopt-progress` for the simple step-completion state (avoids read-modify-write race on large manifests). |
| **Inventory scan time at 2180 files** — is `find + xargs wc -l` actually < 2s on NVMe, < 30s on network storage? | CR-7 requires a performance CI gate. If scan time exceeds 30s on the CI runner, the 500-file cap may not be sufficient. | Add a timing probe in Phase 1: run `find + xargs wc -l` against a 500-file synthetic fixture on the CI runner and measure; adjust cap or add a `--quick` mode that skips `wc -l` for files > N KB. |
| **Skill structured-output format** — does the skill write a patch JSON via `Write` tool and then the human runs `--apply-patch`, or does the skill call `--update-manifest --step-json` and then `--apply-step`? | STACK.md and ARCHITECTURE.md describe slightly different handshake variants (patch files vs manifest `restructure_steps[]`). The implementation must choose one. | The ARCHITECTURE.md approach (manifest `restructure_steps[]` + `--apply-step`) is preferred because it keeps all state in one file. STACK.md's patch-file approach is a valid alternative if manifest atomicity is a concern. Decide in Phase 3 planning. |
| **`--update-manifest` validation depth** — should the CLI schema-validate the step JSON passed by the skill, or trust it? | A malformed step JSON written to the manifest by the skill could corrupt subsequent `jq` reads. But full JSON Schema validation adds complexity. | Recommend: `jq` parse-check only (does it parse as valid JSON? does it have the required `id`, `op`, `status` fields?); reject with `exit 2` if not. Full schema validation deferred to v0.6.x. |

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | All v0.6.0 primitives verified against official docs (`find -print0 | xargs -0`, `git status --porcelain=v1`, `cp -a`, `wc -l <`, `jq -cn --slurpfile`, `!cmd` skill injection). Zero new deps confirmed. |
| Features | HIGH | 8 "lose nothing" behaviors are concrete and testable. Anti-features are explicit. Comparator tool analysis (jscodeshift, Terraform, chezmoi, Flyway) gives strong user expectation baseline. |
| Architecture | HIGH | Derived directly from live codebase (cli/conjure, lib/mutate.sh, lib/merge.sh, scripts/init-project.sh, scripts/audit-setup.sh all read this session). Component boundaries and dependency order are exact. |
| Pitfalls | HIGH for structural (CR-2, CR-3, CR-4, CR-7); MEDIUM for LLM-specific (CR-1, CR-5, CR-6) | LLM pitfalls are derived from published research on LLM summarization failure modes, not from empirical conjure runs. Treat as HIGH-priority requirements, not hypothetical risks. |

**Overall confidence:** HIGH

### Gaps to Address

- **Skill body fits in ≤200 lines:** The restructure skill must cover substantial ground (manifest loading, invariant checking, plan proposal, per-step approval, patch writing, audit). This has not been prototyped. If it does not fit, either the skill body must be split or the instruction style must be compressed significantly. Address in Phase 3 planning as a spike.

- **`cp -a` on older macOS:** `-a` is documented as supported since macOS 10.5+. The kit's CI matrix will validate. If a field report surfaces an older macOS, fall back to `cp -Rp` (already documented in STACK.md as the POSIX fallback). No action needed before Phase 2.

- **`--apply-step` atomicity under concurrent Claude Code sessions:** If two Claude Code sessions invoke the restructure skill simultaneously, both could attempt `--update-manifest` and produce a corrupted manifest. `jq`-based read-modify-write is not atomic on all filesystems. A temp-file-then-rename (`mv -f`) pattern would address it. Defer to Phase 2 planning.

## Sources

### Primary (HIGH confidence)
- Conjure `cli/conjure`, `lib/mutate.sh`, `lib/merge.sh`, `scripts/init-project.sh`, `scripts/audit-setup.sh`, `.planning/PROJECT.md` — read directly this session; all component boundaries and integration points derived from live source
- [git-status docs](https://git-scm.com/docs/git-status) — `--porcelain=v1` stable format, untracked file behavior
- [jq manual](https://jqlang.org/jq/manual/) — `-c`, `-n`, `--arg`, `--argjson`, `--slurpfile`, `group_by`, `from_entries`
- [wc POSIX spec](https://pubs.opengroup.org/onlinepubs/9699919799/utilities/wc.html) — `-l` redirect form; `-c` for byte count
- [cp POSIX spec](https://pubs.opengroup.org/onlinepubs/9699919799/utilities/cp.html) — `-a` (GNU/BSD extension, macOS 10.5+); `-Rp` as POSIX fallback
- [xargs man page](https://man7.org/linux/man-pages/man1/xargs.1.html) — `-0` null-delimiter; batched ARG_MAX behavior
- [Claude Code Skills docs](https://code.claude.com/docs/en/skills) — `!cmd` dynamic injection; `allowed-tools` space-separated string; `disable-model-invocation: true`

### Secondary (MEDIUM confidence)
- [Codemods: Automated API Refactoring (Martin Fowler)](https://martinfowler.com/articles/codemods-api-refactoring.html) — plan-then-apply UX contract
- [ESLint CLI Reference](https://eslint.org/docs/latest/use/command-line-interface) — `--fix-dry-run` UX pattern
- [terraform plan reference](https://developer.hashicorp.com/terraform/cli/commands/plan) — show-before-mutate as canonical UX
- [From Single to Multi: How LLMs Hallucinate in Multi-Document Summarization (arXiv)](https://arxiv.org/pdf/2410.13961) — up to 75% hallucination rate; "lost in the middle" effect
- [Semantic Override Hallucinations in LLM Reasoning (arXiv)](https://arxiv.org/html/2602.17520) — models revert to pretrained defaults despite explicit redefinition; constraint dropping
- [The Agent Approval Fatigue Problem](https://molten.bot/blog/agent-approval-fatigue/) — rubber-stamping when approval rate exceeds cognitive bandwidth
- [Backup Integrity Verification Framework](https://oneuptime.com/blog/post/2026-01-30-backup-verification-testing/view) — five-level verification model

---
*Research completed: 2026-05-28*
*Ready for roadmap: yes*
