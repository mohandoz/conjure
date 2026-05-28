# Phase 22: `conjure adopt` CLI Core + Rollback - Research

**Researched:** 2026-05-28
**Domain:** POSIX bash CLI orchestration — wiring already-built Phase 21 primitives (`lib/snapshot.sh`, `lib/inventory.sh`, `lib/log.sh`, `lib/mutate.sh`, `lib/caps.sh`) into a complete, audited, rollback-capable `conjure adopt` pipeline with crash-safe step state, signal traps, and dry-run zero-writes.
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

> Source: `.planning/phases/22-conjure-adopt-cli-core-rollback/22-CONTEXT.md` (D-01..D-15 + Claude's Discretion). All copied verbatim. These are LOCKED — the planner MUST honor them and must NOT explore alternatives to locked decisions.

### Locked Decisions

**Rollback scope & cleanliness (SAFE-02, Phase 24 zero-diff)**
- **D-01:** `--rollback` = **full restore + delete-created**. Three steps: (1) `snapshot_rollback` does whole-tree `cp -a snapshot/. target/` (restores every mutated file AND un-archives originals, since both live in the snapshot); (2) for each path in `.conjure-adopt-state` `created[]`, `mutate_rm` it (removes scaffolded harness files the snapshot can't undo); (3) verify `sha256(p) == before` for every `p` in `mutated[]`. Then `log_step ROLLBACK`. This is the only strategy that yields Phase 24's sha256-identical before/after. Surgical (manifest-only restore) and full-restore-only were **rejected** — the former risks unrecorded mutations escaping, the latter leaves scaffolded files behind.
- **D-02:** `created[]` tracks **scaffolded harness paths only** (new skills/agents/hooks/docs). It does **NOT** include conjure's own backup infrastructure (`.conjure-adopt-backups/`, `.conjure-archive-<ts>/`, `.conjure-adopt-state`, `RESTRUCTURE-LOG.md`) — those are never deleted by the delete-created step.
- **D-03:** Phase 24's "zero diff after rollback" comparison **MUST exclude conjure's own dirs** (`.conjure-adopt-backups/`, `.conjure-archive-*`, `RESTRUCTURE-LOG.md`) — they didn't exist pre-adopt, so they are out of the before/after diff scope. (Flag this to the Phase 24 test author.)
- **D-04:** After a successful rollback, **keep the snapshot dir, archive dir, and `RESTRUCTURE-LOG.md`** (now carrying a `[ROLLBACK]` entry) for audit/forensics; **delete only `.conjure-adopt-state`** (the run is over — a stale state file would trigger a false recovery prompt on the next run). User can manually purge backups later. "Remove everything" rejected (destroys the audit trail + the only backup right after a restore).

**`--apply-step` / `--update-manifest` contract (the Phase 23 skill seam)**
- **D-05:** **Manifest-driven restructure-op executor.** `--apply-step <id>` reads operation `#id` from `adopt-manifest.json` `restructure_steps[]`, executes it via the appropriate `mutate_*` primitive, `log_step RESTRUCTURE`, and marks the step `status: applied`. **Skill proposes (writes manifest), CLI applies (reads manifest)** — this preserves the RESTR-02 chokepoint (the skill never calls Write/Edit on project files; every mutation routes through `lib/mutate.sh`). Pipeline-step-rerun semantics were **rejected** for `--apply-step`.
- **D-06:** `--update-manifest` is how the skill writes **proposed ops + their status** back into `adopt-manifest.json` `restructure_steps[]`. Inbound half of the contract; `--apply-step` is the outbound half.
- **D-07:** **Staging-path content references.** Generated content (condensed CLAUDE.md, new SKILL.md bodies) is written by the skill to `.conjure-adopt-state/staging/<file>`; the manifest op references it as `{ op: "write", dest: "CLAUDE.md", src: ".conjure-adopt-state/staging/CLAUDE.md", status: "proposed" }`. Keeps the manifest lean and lets `--apply-step` + `conjure audit` inspect proposed content as a **real file before writing**. Inline content in the manifest **rejected**.
- **D-08:** **Phase 22 scope for the executor:** ship `--apply-step` + `--update-manifest` with the supported op types (at least `archive`, `write`; `extract` = write-new + archive-old composed from the two) and test them against a **synthetic/hand-authored manifest fixture**. Phase 23 wires the actual skill that *generates* real ops.

**Adoption report + dry-run output (ADOPT-06, ADOPT-02, criterion 1)**
- **D-09:** **Report format = labeled plain-text sections + a compact before/after delta block** (echo lines, no new deps), consistent with existing `cmd_audit`/`cmd_check` output style. Required metrics (fixed by ADOPT-06): files inventoried, layers scaffolded, files archived, CLAUDE.md line-count delta, snapshot path, audit before→after. Aligned-table format rejected.
- **D-10:** **Dry-run runs read-only steps for real.** `--dry-run` executes preconditions (git-clean check) + `inventory_scan` (read-only) for real, writes `adopt-manifest.json` so the plan is concrete (real counts: N inventoried, M missing layers, K cap violations); mutating steps (snapshot, scaffold, archive, audit-writes) print `[dry-run] would …`. Static-plan rejected.
- **D-11:** **Dry-run manifest temp path is OUTSIDE the target repo.** Write it to a `mktemp -d` system temp dir (e.g. `$TMPDIR`), NOT under `.conjure-adopt-state/` or anywhere inside the target — ADOPT-02 ("zero filesystem side-effects") and Phase 24 criterion 1 ("writes **zero files to the fixture directory**") forbid any write under the target root. Print the temp path so the user can inspect the plan. *(Corrects the in-repo `.conjure-adopt-state/dry-run/` path shown in the discussion preview.)*

**Partial-run recovery (SAFE-04, SAFE-05)**
- **D-12:** **`[c]ontinue` = resume at next incomplete step.** Read `.conjure-adopt-state` step-completion records, skip steps already marked done (sha256-matched), resume at the first incomplete step, and **reuse the existing snapshot dir** (no second backup). Restart-from-step-1 rejected.
- **D-13:** **No-TTY behavior = `exit 2` + explicit recovery flags.** Mirror `scripts/resolve.sh`: read the `[r]ollback/[c]ontinue/[s]tart-fresh` prompt from `/dev/tty`; if there is no TTY, print the detected partial state (including `last completed: <step>`) + instructions and `exit 2` — **never auto-mutate**. CI/automation drives recovery non-interactively via explicit flags: `--rollback`, `--resume` (= continue, D-12), `--start-fresh`. Auto-rollback/auto-continue in non-TTY both rejected.
- **D-14:** Interactive recovery prompt has **no default choice** — empty input re-prompts (resolve.sh pattern). Recovery is destructive-adjacent; force a conscious selection.

**SAFE-06 (git-state warning)**
- **D-15:** `snapshot_create` already captures `git_head` + `git_stash_list` into `.snapshot-meta.json` (Phase 21). Phase 22's remaining SAFE-06 work is the **user-facing warning** that `--rollback` restores from the **filesystem snapshot, not git** — surfaced in the report and/or at rollback time.

### Claude's Discretion
- `.conjure-adopt-state` exact JSON schema (step records with path + sha256 before/after per SAFE-04; `created[]`, `mutated[]`, `staging/` layout) — design during planning, mirroring `adopt-manifest.schema.json` draft-07 style and `.snapshot-meta.json` shape.
- **Scaffold reuse mechanism** (ADOPT-04): call `scripts/init-project.sh` as a subprocess vs. inline its skip-if-exists logic — Phase 21 notes `init-project.sh` is "called as subprocesses by the later adopt.sh". Default to subprocess unless planning finds a blocker. "Missing layer" granularity (file-level vs layer-level) is implementation detail; reuse init's existing idempotent never-overwrite behavior.
- Signal-trap mechanics (`trap '…' INT TERM`, ensuring partial state is flushed before exit 2), per-step `log_step` message wording, and the exact step-ordering of state-record writes (record completion *before* advancing).
- `--force` interaction with recovery: `--force` governs the dirty-tree precondition (ADOPT-03); it is independent of the recovery prompt. Confirm no surprising overlap during planning.

### Deferred Ideas (OUT OF SCOPE)
- `--json` report/inventory output for CI — tracked as **ADOPT-07 (v2)**.
- `--quick` inventory mode — tracked as **ADOPT-08 (v2)**.
- The `restructure` skill that *generates* `restructure_steps[]` ops, the constraint-extraction pre-pass, and the pre-write audit gate — **Phase 23** (Phase 22 only builds the executor + staging contract they ride on).
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| ADOPT-01 | Run `conjure adopt` on existing repo → fold into four-layer harness in one command | §Architecture Patterns — 5-step pipeline orchestrator (`scripts/adopt.sh`); §Code Examples — pipeline skeleton, `cmd_adopt` dispatch |
| ADOPT-02 | `conjure adopt --dry-run` previews every planned change with zero filesystem side-effects | §Pitfall 1 (dry-run zero-writes); §Code Examples — dry-run manifest mktemp temp-path (D-11); inventory_emit_manifest already redirects under DRY_RUN — but to `/tmp` hardcoded, NOT mktemp (see Pitfall 1) |
| ADOPT-04 | Scaffold only *missing* layers via idempotent init scaffold — never overwrite | §Don't Hand-Roll (call `init-project.sh existing`); §Code Examples — subprocess scaffold; init-project.sh confirmed idempotent (all writes `[ ! -f ]`/`[ ! -d ]` guarded) |
| ADOPT-05 | Run size-cap + schema audit, report harness health before AND after | §Architecture Patterns — audit-before/after capture; audit-setup.sh exit 0/1/2 contract; §Code Examples — capturing exit code without aborting |
| ADOPT-06 | Adoption report: files inventoried, layers scaffolded, files archived, CLAUDE.md line-count delta | §Code Examples — report block (D-09 labeled plain-text); metrics sourced from manifest summary + state file |
| SAFE-01 | Full timestamped snapshot of every touched path before first mutation | `snapshot_create` (built, Phase 21) — `cp -a` whole-tree, UTC ts; §Pitfall 3 (snapshot self-copy risk) |
| SAFE-02 | `conjure adopt --rollback` fully restores; sha256 after == sha256 before | §Architecture Patterns — 3-step rollback (D-01); §Code Examples — rollback + sha256 verify loop; cross-platform sha256 helper |
| SAFE-04 | Each step recorded in step-completion manifest (path + sha256 before/after) | §Code Examples — `.conjure-adopt-state` schema + atomic write (temp+mv); §Pitfall 2 (crash-durable state) |
| SAFE-05 | Trap interrupts (INT/TERM → exit 2); on restart offer rollback/continue/start-fresh | §Code Examples — signal trap + recovery prompt (mirrors resolve.sh `/dev/tty`); §Pitfall 4 (SIGKILL untrappable → durability) |
| SAFE-06 | Snapshot records git state; warn that `--rollback` is filesystem-not-git | snapshot-meta capture done (Phase 21); D-15 user-facing warning is the remaining work |
| SAFE-07 | Every step appends to human-readable `RESTRUCTURE-LOG.md` as it happens (survives mid-run kill) | `log_init`/`log_step` (built, Phase 21); set `RESTRUCTURE_LOG_PATH` so snapshot/inventory auto-log; append-per-step (not batched) |
</phase_requirements>

## Summary

Phase 22 is **orchestration, not invention**. Every hard primitive already exists and is tested from Phase 21: `snapshot_create`/`snapshot_rollback`/`snapshot_list` (whole-tree `cp -a` + `.snapshot-meta.json` git capture), `inventory_scan`/`inventory_emit_manifest` (6-bucket classifier + `adopt-manifest.json`), `log_init`/`log_step`/`log_fail` (append-only `RESTRUCTURE-LOG.md`), the `mutate_*` chokepoint (`mkdir/cp/write/rm/archive`, all `DRY_RUN`-aware), and `caps.sh` constants. The phase wires them into `scripts/adopt.sh` (a 5-step pipeline: preconditions → snapshot → inventory → scaffold → audit) plus `cmd_adopt` in `cli/conjure`, and adds three genuinely new pieces of logic: the `.conjure-adopt-state` crash-safe step manifest, signal-trap recovery, and the `--apply-step`/`--update-manifest` op executor.

The work is squarely in the existing stack — POSIX bash 3.2.57 (the live interpreter on macOS), `jq` 1.8.1, `git` 2.54, `find`/`cp -a`/`wc`/`mktemp`, and `sha256sum`/`shasum` (both present). Zero new dependencies; `dependencies: {}` stays empty. The dominant risk is not "can we build it" but "does it satisfy the four hard safety invariants exactly": (1) dry-run writes literally zero bytes under the target root, (2) rollback yields sha256-identical before/after (the Phase 24 zero-diff gate), (3) state is durable on disk *before* each step so a `kill -9` mid-step leaves a recoverable manifest, and (4) the dirty-tree gate exits 2 (never 1) and respects `--force`.

**Three concrete pitfalls demand planning attention before any code is written:** (a) `snapshot_create` copies `target/.` — if `.conjure-adopt-backups/` lives inside the target, the snapshot recursively copies prior backups (BSD/macOS `cp` behavior on self-nested dest is unspecified); the planner must decide an exclusion/ordering strategy. (b) The existing `inventory_emit_manifest` dry-run path hardcodes `/tmp/adopt-manifest-dryrun.json`, which violates D-11 (must be `mktemp -d` outside target) AND is a fixed path that collides across concurrent runs — adopt.sh must override the output path, not rely on the lib's built-in `/tmp` redirect. (c) `kill -9` cannot be trapped, so SAFE-05 recovery hinges on state durability, not the trap — the state record must be flushed (atomic temp+mv) *before* the mutating step it guards, not after.

**Primary recommendation:** Build `scripts/adopt.sh` as a thin orchestrator that sources the five libs, sets `RESTRUCTURE_LOG_PATH` once so snapshot/inventory auto-log, gates dirty-tree with `git status --porcelain` (exit 2 / `--force`), writes the `.conjure-adopt-state` record atomically before each mutating step, traps INT/TERM to flush-and-exit-2, and mirrors `resolve.sh`'s `/dev/tty` + fd-3 prompt model for recovery. Keep `cmd_adopt` a thin env-var-passing wrapper exactly like `cmd_resolve`/`cmd_audit`.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Flag parsing + dispatch | CLI dispatcher (`cli/conjure` `cmd_adopt`) | — | Matches existing `cmd_resolve`/`cmd_audit` pattern: parse flags, set env vars, exec `scripts/adopt.sh` |
| Pipeline orchestration (5 steps) | Worker (`scripts/adopt.sh`) | — | All multi-step command logic lives in `scripts/*.sh`; cli/conjure stays thin |
| Snapshot create/rollback/list | Lib (`lib/snapshot.sh`) | Worker calls it | Built Phase 21; raw `cp -a` safety primitive, not routed through mutate |
| Inventory + manifest emit | Lib (`lib/inventory.sh`) | Worker calls it | Built Phase 21; read-only scan + `mutate_write` manifest |
| All filesystem mutations | Lib (`lib/mutate.sh`) | — | Locked chokepoint; `--apply-step` ops and scaffold writes route here |
| Step-state persistence (`.conjure-adopt-state`) | Worker (`scripts/adopt.sh`) | `jq` for read/write, `mv` for atomicity | NEW this phase; not a reusable lib primitive (adopt-specific recovery) |
| Signal trap + recovery prompt | Worker (`scripts/adopt.sh`) | `/dev/tty` (mirror resolve.sh) | NEW; TTY model is established in resolve.sh |
| Scaffold missing layers | Subprocess (`scripts/init-project.sh existing`) | Worker invokes | ADOPT-04 reuse — idempotent, never-overwrite already proven |
| Size-cap audit before/after | Subprocess (`scripts/audit-setup.sh`) | Worker captures exit code | ADOPT-05 reuse; exit 0/1/2 contract |
| `--apply-step`/`--update-manifest` op executor | Worker (`scripts/adopt.sh`) | `jq` read manifest, `mutate_*` execute | NEW; the Phase 23 skill seam (D-05/D-06/D-08) |

## Standard Stack

> This phase adds **no new dependencies**. Everything below is already in the runtime envelope (bash + stdlib + `jq` + git) and verified present on the live machine this session.

### Core
| Tool | Version (verified) | Purpose | Why Standard |
|------|--------------------|---------|--------------|
| bash | 3.2.57 (macOS live) | Pipeline + state logic | Project floor is bash 3.2+; this IS the interpreter — no associative arrays, no `mapfile`, no `local -n` |
| jq | 1.8.1 | Read/write `.conjure-adopt-state` + `adopt-manifest.json` `restructure_steps[]` | Already a preflight hard dep; `-cn --arg/--argjson/--slurpfile` is injection-safe (no shell string interp into JSON) |
| git | 2.54.0 | Dirty-tree precondition (`git status --porcelain`) | Already used; `--porcelain` is the contract-stable, color/locale-immune form |
| coreutils (`cp -a`, `mv`, `wc`, `find`, `mktemp`) | system | Snapshot copy, atomic state write, line counts, scans, temp dirs | All POSIX; `cp -a` already used by snapshot lib with `cp -Rp` fallback |
| sha256sum / shasum | both present (`/sbin/sha256sum`, `/usr/bin/shasum`) | SAFE-02/SAFE-04 sha256 before/after | Cross-platform: prefer `sha256sum`, fall back to `shasum -a 256` (exact pattern already in `mutate_archive`) |

### Supporting (already-built Phase 21 primitives — orchestrate, do not reimplement)
| Function | File | Signature | Notes for adopt.sh |
|----------|------|-----------|--------------------|
| `snapshot_create` | `lib/snapshot.sh` | `snapshot_create <target> <backup_root>` → sets `CONJURE_SNAPSHOT_PATH` | Raw `cp -a target/.` — NOT `mutate_cp`. DRY_RUN=1 prints would-be path, sets var, no copy. Auto-logs `SNAPSHOT` if `RESTRUCTURE_LOG_PATH` set. Writes `.snapshot-meta.json` (git_head, git_stash_list). |
| `snapshot_rollback` | `lib/snapshot.sh` | `snapshot_rollback <snapshot_path> <target>` | Whole-tree `cp -a snapshot/. target/`. Validates path exists (returns 1 if not). Auto-logs `ROLLBACK`. **Does NOT delete created[] — that's adopt.sh's job (D-01 step 2).** |
| `snapshot_list` | `lib/snapshot.sh` | `snapshot_list <backup_root>` | `ls -1t` newest-first. **Note: takes backup_root, not target** (differs from research draft). |
| `inventory_scan` | `lib/inventory.sh` | `inventory_scan <target>` | Sets `CONJURE_INVENTORY_ITEMS`, `_TOTAL_FOUND`, `_SCAN_CAPPED`. Read-only. Skips symlinks/binary/`.git`/`node_modules`/`.conjure-adopt-backups`/`.conjure-archive-*`. 500-file cap (D-08). |
| `inventory_emit_manifest` | `lib/inventory.sh` | `inventory_emit_manifest <target> <output_path>` | Writes manifest via `mutate_write`. **DRY_RUN=1 hardcodes `/tmp/adopt-manifest-dryrun.json`** (see Pitfall 1 — adopt.sh must pass an mktemp path AND set DRY_RUN=0 for the manifest write, or override the redirect). Auto-logs `INVENTORY`. |
| `log_init` | `lib/log.sh` | `log_init <target_dir>` → sets `RESTRUCTURE_LOG_PATH` | Writes header via `mutate_write` (replace). Honors DRY_RUN. |
| `log_step` | `lib/log.sh` | `log_step <PHASE> <message>` | Appends `[ts] [PHASE] msg\n` via `mutate_write --append`. SAFE-07: append-per-step. |
| `log_fail` | `lib/log.sh` | `log_fail <message>` | Logs FAIL, **`exit 2`** (project convention). |
| `mutate_mkdir/cp/write/rm` | `lib/mutate.sh` | per-fn | All DRY_RUN-aware, increment `CONJURE_DRY_MUTATION_COUNT`. `mutate_write <dest> <content> [--append]`. |
| `mutate_archive` | `lib/mutate.sh` | `mutate_archive <src_abs> <archive_root>` | copy→sha256-verify→rm→ledger (D-13). Requires absolute src, no `..`. The `archive` op for `--apply-step`. |
| `mutate_summary` | `lib/mutate.sh` | — | Call at end; prints `[dry-run] N mutations skipped`. |
| caps | `lib/caps.sh` | `CLAUDE_MD_CAP=100` `SKILL_MD_CAP=200` `AGENT_MD_CAP=80` | For report line-count delta + audit step. |

### Subprocesses (ADOPT-04 / ADOPT-05 reuse — call, don't duplicate)
| Script | Invocation | Contract |
|--------|-----------|----------|
| `scripts/init-project.sh` | `bash "$CONJURE_HOME/scripts/init-project.sh" existing "$target"` | Idempotent: every write guarded `[ ! -f ]`/`[ ! -d ]`. Uses `set -euo pipefail`, exits 1 on bad *usage* only. Passes through `DRY_RUN`/`CONJURE_HOME` env. |
| `scripts/audit-setup.sh` | `bash "$CONJURE_HOME/scripts/audit-setup.sh" "$target"` | Exit 0=pass, 1=warnings, 2=errors. Sources `lib/caps.sh`. **Capture rc; do NOT abort adopt on non-zero** (audit surfaces violations, doesn't gate). |

### Alternatives Considered
| Instead of | Could Use | Tradeoff / Verdict |
|------------|-----------|--------------------|
| `jq` read-modify-write of `.conjure-adopt-state` | Separate `key=value` `.adopt-progress` file (SUMMARY.md open question) | CONTEXT.md Claude's Discretion says design the JSON schema mirroring `adopt-manifest.schema.json` draft-07 style — so **JSON it is**. `jq` is already a hard dep. Use temp+`mv` for atomicity (resolves the read-modify-write race flagged in SUMMARY.md gaps). |
| `trap` to flush state | Rely solely on trap | `kill -9` (SAFE-05 / Phase 24 criterion 4) is **untrappable**. Trap handles INT/TERM only; durability (write-before-step) is what saves SIGKILL. Use **both**. |
| Lib's built-in DRY_RUN→`/tmp` manifest redirect | adopt.sh passes explicit `mktemp -d` path | D-11 requires temp OUTSIDE target and the lib's `/tmp/adopt-manifest-dryrun.json` is a fixed (collision-prone) path. adopt.sh must control the path. |

**Installation:** None. No `npm install` / `pip install`. Confirm via existing `cmd_preflight` (already invoked by sibling `cmd_*` functions).

## Package Legitimacy Audit

> This phase installs **zero external packages**. No registry dependency is added; `dependencies: {}` stays empty per CLAUDE.md. slopcheck / registry verification is **N/A**.

| Package | Registry | Disposition |
|---------|----------|-------------|
| (none) | — | No external packages — pure shell orchestration of in-repo libs |

**Packages removed due to slopcheck [SLOP] verdict:** none (no packages).
**Packages flagged as suspicious [SUS]:** none.

## Architecture Patterns

### System Architecture Diagram

```
 user: conjure adopt [--dry-run|--force|--rollback|--resume|--start-fresh|
                       --apply-step <id>|--update-manifest|--full-inventory] [target]
   │
   ▼
 cli/conjure :: cmd_adopt            (thin wrapper — parse flags → env vars → exec)
   │  DRY_RUN, CONJURE_ADOPT_FORCE, CONJURE_ADOPT_ROLLBACK, CONJURE_ADOPT_RESUME,
   │  CONJURE_ADOPT_START_FRESH, CONJURE_ADOPT_APPLY_STEP, CONJURE_ADOPT_UPDATE_MANIFEST,
   │  CONJURE_ADOPT_FULL_INVENTORY, CONJURE_HOME
   ▼
 scripts/adopt.sh "$target"
   │  source lib/mutate.sh, lib/caps.sh, lib/log.sh, lib/snapshot.sh, lib/inventory.sh
   │  trap '<flush-state>; exit 2' INT TERM            ◀── SAFE-05 (INT/TERM)
   │
   ├─ MODE DISPATCH (mutually exclusive sub-ops):
   │     --rollback        → rollback_path()     ─────────────┐
   │     --apply-step <id> → apply_step()        ───────┐     │
   │     --update-manifest → update_manifest()   ──┐    │     │
   │     (recovery: prior .conjure-adopt-state)  ──┼────┼─────┼── recovery_prompt() (D-12/13/14)
   │     (default)         → run_pipeline()        │    │     │
   │                                               ▼    ▼     ▼
   │  ┌────────────────────────────────────────────────────────────────┐
   │  │ run_pipeline() — the 5 steps (each: write state BEFORE, then act)│
   │  │                                                                  │
   │  │  Step 0  preconditions:  git status --porcelain                  │
   │  │            dirty && !force → exit 2 (ADOPT-03)                    │
   │  │            dirty && force  → log_step WARN (SAFE-06/CR-3)         │
   │  │            brownfield check: CLAUDE.md or .claude/ exists         │
   │  │  Step 0.5 log_init → RESTRUCTURE_LOG_PATH set (SAFE-07)           │
   │  │  Step 1  snapshot_create → CONJURE_SNAPSHOT_PATH (SAFE-01)        │
   │  │            [dry-run] prints would-be path, no copy                │
   │  │  Step 2  inventory_scan + inventory_emit_manifest (ADOPT-01)      │
   │  │            [dry-run] real scan, manifest → mktemp temp (D-11)     │
   │  │  Step 3  init-project.sh existing (subprocess) → scaffold         │
   │  │            record each created path in state created[] (D-02)     │
   │  │            [dry-run] mutate_* print "would …"                     │
   │  │  Step 4  audit-setup.sh (subprocess) → capture rc; no abort       │
   │  │  Step 5  adoption report (D-09) + mutate_summary                  │
   │  └────────────────────────────────────────────────────────────────┘
   │
   ├─ writes/reads:
   │     RESTRUCTURE-LOG.md         (lib/log.sh, append-per-step — durable)
   │     adopt-manifest.json        (lib/inventory.sh; dry-run → temp)
   │     .conjure-adopt-state       (NEW: step records + created[] + mutated[] + staging/)
   │     .conjure-adopt-backups/    (snapshot dirs; .snapshot-meta.json git capture)
   │     .conjure-archive-<ts>/     (mutate_archive dest + .archive-ledger)
   │
   └─ rollback_path() (D-01):
         snapshot_rollback snapshot/. target/   (restore mutated + un-archive)
           → for p in created[]: mutate_rm p     (delete scaffolded)
             → for p in mutated[]: assert sha256(p)==before  (SAFE-02 verify)
               → log_step ROLLBACK
                 → rm .conjure-adopt-state (D-04: keep snapshot/archive/log)
```

### Recommended File Structure (this phase)
```
scripts/
└── adopt.sh              # NEW — 5-step pipeline + rollback + recovery + op executor
cli/
└── conjure              # MODIFIED — add cmd_adopt, dispatch entry, usage() line
tests/
├── run.sh               # MODIFIED — Phase 22 test block (mirror Phase 21 block style)
└── fixtures/
    ├── brownfield-simple/   # REUSE — existing clean fixture (21-line CLAUDE.md)
    └── <synthetic manifest fixture>  # NEW — hand-authored restructure_steps[] for --apply-step (D-08)
```
> Per-repo artifacts (`.conjure-adopt-state`, `.conjure-adopt-backups/`, `RESTRUCTURE-LOG.md`, `adopt-manifest.json`) are written into the **target**, not the kit. Never commit them in fixtures.

### Pattern 1: Thin CLI wrapper (mirror `cmd_resolve`/`cmd_audit`)
**What:** `cmd_adopt` parses flags, sets env vars, execs `scripts/adopt.sh`. No business logic in `cli/conjure`.
**When:** Always — the codebase invariant is that `cli/conjure` dispatches and `scripts/*.sh` does the work.
**Example:**
```bash
# Source: cli/conjure cmd_resolve (lines 176-190) — the canonical thin-wrapper template
cmd_resolve() {
  local target dryrun
  target="$(pwd)"; dryrun=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --dry-run)   dryrun=1 ;;
      --help|-h)   echo "Usage: conjure resolve [--dry-run] [target]"; return 0 ;;
      *)           target="$1" ;;
    esac
    shift
  done
  CONJURE_HOME="$CONJURE_HOME" DRY_RUN="$dryrun" \
    bash "$CONJURE_HOME/scripts/resolve.sh" "$target"
}
```

### Pattern 2: Set `RESTRUCTURE_LOG_PATH` once → libs auto-log
**What:** `snapshot_create` and `inventory_emit_manifest` both call `log_step` *only if* `RESTRUCTURE_LOG_PATH` is set. `log_init` sets it. So call `log_init "$target"` early and the snapshot/inventory steps log themselves (SAFE-07).
**When:** Step 0.5, right after the precondition gate passes, before snapshot.
**Anti-pattern:** Calling `snapshot_create` before `log_init` → snapshot won't log; or setting `RESTRUCTURE_LOG_PATH` to a different path than `log_init` used → split logs.

### Pattern 3: Write step-state BEFORE the mutating step (crash durability)
**What:** For each mutating step, write the `.conjure-adopt-state` "starting step X" record (atomic temp+mv) *before* executing the mutation, and the "completed step X + sha256" record *after*. A `kill -9` between leaves a state file that says "step X started, not completed" → recovery knows where to resume/rollback.
**When:** Steps 1, 3 (mutating). Steps 0, 2-dry, 4 are read-only-ish.
**Why:** SIGKILL is untrappable (Pitfall 4) — durability, not the trap, is what makes SAFE-05 / Phase 24 criterion 4 work.

### Pattern 4: Recovery prompt mirrors `resolve.sh` TTY model
**What:** On startup, if `.conjure-adopt-state` exists and is incomplete (and no explicit `--rollback`/`--resume`/`--start-fresh` flag given), prompt `[r]ollback / [c]ontinue / [s]tart-fresh` reading from `/dev/tty`; if no TTY, print state + flags and `exit 2`.
**When:** Before `run_pipeline()`, after mode dispatch.
**Example (the exact non-TTY guard + fd-3 loop to mirror):**
```bash
# Source: scripts/resolve.sh (lines 34-53) — non-TTY exit-2 guard + interactive loop
if ! { [ -t 0 ] || [ "${CONJURE_FORCE_INTERACTIVE:-0}" = "1" ]; }; then
  echo "conjure adopt: partial run detected (last completed: $last_step)" >&2
  echo "  non-interactive — choose: --rollback | --resume | --start-fresh" >&2
  exit 2                                  # D-13: never auto-mutate
fi
while true; do
  read -r -p "  [r]ollback / [c]ontinue / [s]tart-fresh: " choice < /dev/tty
  case "$choice" in
    r|rollback)    rollback_path; break ;;
    c|continue)    DRY_RUN=0 resume_pipeline; break ;;
    s|start-fresh) rm -f .conjure-adopt-state; run_pipeline; break ;;
    *)             echo "  enter r, c, or s" ;;   # D-14: no default; empty re-prompts
  esac
done
```
> Note: resolve.sh uses `read -r -p` from stdin with an fd-3 trick for the *file list*. For adopt's single prompt, reading directly from `/dev/tty` (as above) is cleaner and matches D-13's `/dev/tty` requirement. `CONJURE_FORCE_INTERACTIVE=1` is the test escape hatch (already established).

### Pattern 5: `--apply-step` / `--update-manifest` op executor (D-05/D-06/D-08)
**What:** `--update-manifest` reads a step JSON (from `--step-json` or stdin), `jq`-validates it has `id`/`op`/`status`, appends to `restructure_steps[]`, writes back atomically. `--apply-step <id>` reads op `#id`, dispatches by `op` type to the right `mutate_*`, logs `RESTRUCTURE`, marks `status: applied`.
**Op types (Phase 22 scope, D-08):**
- `write` — `mutate_write "$dest" "$(cat "$src")"` where `src` is `.conjure-adopt-state/staging/<file>` (D-07 staging-path ref). Record dest in `created[]` or `mutated[]`.
- `archive` — `mutate_archive "$abs_src" "$archive_root"` (already copy→verify→rm→ledger).
- `extract` = `write` (new) + `archive` (old) composed.
**Validation depth (SUMMARY.md open question):** `jq` parse-check + required-fields check only (`id`, `op`, `status`); reject with `exit 2` if malformed. Full JSON Schema validation deferred to v0.6.x (per SUMMARY.md recommendation).

### Anti-Patterns to Avoid
- **Routing `snapshot_create` through `mutate_cp`** — snapshot is the safety primitive; DRY_RUN would suppress the backup. The lib already uses raw `cp -a`; adopt.sh must not "fix" this.
- **Writing the manifest with `printf >`/heredoc** — bypasses `mutate_write`/DRY_RUN. Use `inventory_emit_manifest`.
- **Aborting adopt on audit non-zero** — Step 4 captures rc and logs it; adopt continues (audit surfaces violations for the restructure skill, doesn't gate).
- **`exit 1` anywhere** — project convention is `exit 2` for hard failures (`log_fail` already does this). Dirty-tree refusal, non-TTY recovery, missing-snapshot rollback all `exit 2`.
- **Re-snapshotting on `--resume`** — D-12: reuse the existing snapshot dir; a second snapshot would back up the already-mutated tree (CR-2).
- **Treating archive as rollback** — CR-4/D-01: rollback restores from the *snapshot*, then deletes `created[]`. The archive dir is "moved-away" files, restored only because they live in the snapshot too.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Full timestamped backup | A new `cp -R` loop | `snapshot_create` (built) | Already does UTC ts, `cp -a` + `cp -Rp` fallback, git-state capture, auto-log |
| Restore on rollback | Manual `cp` restore | `snapshot_rollback` (built) | Whole-tree `cp -a`, path validation, auto-log; D-01 adds only the created[]-delete + sha256-verify on top |
| Markdown inventory + classification | New scanner | `inventory_scan`/`inventory_emit_manifest` (built) | 6-bucket classifier, symlink/binary skip, 500-cap, jq manifest, schema-valid |
| Append-only audit log | `echo >> LOG.md` | `log_init`/`log_step` (built) | Structured `[ts] [PHASE] msg`, DRY_RUN-aware, append-per-step (SAFE-07 durability) |
| Move-with-verify (archive) | `mv` + hope | `mutate_archive` (built) | copy→sha256-verify→rm→ledger; refuses relative/`..` src |
| Scaffold missing layers | Re-derive init logic | `init-project.sh existing` subprocess | Idempotent (`[ ! -f ]`/`[ ! -d ]` guards), already tested across 9 profiles |
| Size-cap audit | New cap checks | `audit-setup.sh` subprocess | Sources caps.sh, exit 0/1/2 contract, golden-file tested |
| sha256 (cross-platform) | One tool only | `sha256sum` → `shasum -a 256` fallback | Exact pattern already in `mutate_archive` (lines 113-123) |
| Atomic JSON state write | `jq ... > file` (truncates on crash) | `jq ... > tmp && mv tmp file` | `mv` on same filesystem is atomic; truncation-mid-write corrupts state (SUMMARY.md flagged this) |

**Key insight:** ~90% of Phase 22's "work" is already-built libs. The genuinely new code is small: the `.conjure-adopt-state` schema + atomic read/write helpers, the signal trap + recovery prompt, the dirty-tree gate, the report block, and the op executor. Keep `scripts/adopt.sh` an orchestrator — every time you reach for raw `cp`/`mv`/`printf >` on a *target* file, ask "is there a `mutate_*` or lib function for this?" (answer is almost always yes).

## Runtime State Inventory

> Phase 22 is greenfield code creation (new `scripts/adopt.sh`), not a rename/refactor of existing strings. This section is included because adopt.sh *creates and manages runtime state files in the target* — the planner must understand the state surface even though there is no migration.

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | `.conjure-adopt-state` (NEW this phase — step records, created[], mutated[], staging/); `adopt-manifest.json` (Phase 21 schema, restructure_steps[] becomes read+write); `.snapshot-meta.json` (Phase 21, inside each snapshot dir); `.archive-ledger` (Phase 21, inside archive dir) | Design `.conjure-adopt-state` schema (Claude's Discretion). The other three are read-only references for adopt.sh. |
| Live service config | None — conjure is a local CLI; no external services, daemons, or remote config | None — verified: no network calls, no service registration anywhere in the pipeline |
| OS-registered state | None — no Task Scheduler / launchd / pm2 / systemd. Signal trap is in-process only. | None |
| Secrets/env vars | adopt.sh reads `DRY_RUN`, `CONJURE_HOME`, `CONJURE_ADOPT_*` (new, set by cmd_adopt), `CONJURE_FORCE_INTERACTIVE` (test escape hatch), `RESTRUCTURE_LOG_PATH`/`CONJURE_SNAPSHOT_PATH`/`CONJURE_INVENTORY_*` (lib module-level vars). `EDITOR` only if recovery offers edit (it doesn't — D-14). No secrets. | Document the `CONJURE_ADOPT_*` env-var contract between cmd_adopt and adopt.sh (mirror cmd_audit's `CONJURE_COST`/`CONJURE_EXACT` style). |
| Build artifacts | None — no compiled artifacts; shell scripts run in place | None |

**The canonical question — what runtime state persists after the run?** `.conjure-adopt-backups/` (snapshots, kept per D-04), `.conjure-archive-<ts>/` (kept per D-04), `RESTRUCTURE-LOG.md` (kept, gets `[ROLLBACK]` entry per D-04), `adopt-manifest.json` (kept). `.conjure-adopt-state` is **deleted on successful rollback or successful completion** (D-04) so a stale file never triggers a false recovery prompt.

## Common Pitfalls

### Pitfall 1: Dry-run leaks a write under the target root (ADOPT-02 / Phase 24 criterion 1 FAIL)
**What goes wrong:** ADOPT-02 and Phase 24 criterion 1 require **zero files written to the target directory** in dry-run. But `inventory_emit_manifest` under `DRY_RUN=1` hardcodes the output to `/tmp/adopt-manifest-dryrun.json` (lib/inventory.sh lines 408-411) — a *fixed* path that (a) is `/tmp`, not `mktemp -d` (D-11 says use `mktemp -d`/`$TMPDIR`), and (b) collides if two dry-runs run concurrently. Worse, if adopt.sh sets the output path to something under `.conjure-adopt-state/` (the discussion-preview path D-11 explicitly corrects), the manifest lands inside the target and breaks the zero-writes guarantee.
**Why it happens:** The lib has its own dry-run redirect; adopt.sh layering its own path on top creates two competing behaviors.
**How to avoid:** In dry-run, adopt.sh creates `tmp_manifest_dir=$(mktemp -d)` (outside target) and writes the *real* manifest there. Either (a) call `inventory_emit_manifest "$target" "$tmp_manifest_dir/adopt-manifest.json"` with `DRY_RUN=0` *for that one call* (manifest is a read-only artifact, not a target mutation — D-10 says read-only steps run for real), or (b) override the lib's redirect path. Approach (a) matches D-10 ("dry-run runs read-only steps for real") best. Then `echo` the temp path so the user can inspect. **Verification:** after a dry-run, assert `git status --porcelain "$target"` is empty AND `find "$target" -newer <marker>` shows zero new files.
**Warning signs:** A dry-run leaves `adopt-manifest.json` or `.conjure-adopt-state` in the target; Phase 24 criterion 1 fails the zero-writes assertion.

### Pitfall 2: `.conjure-adopt-state` corrupted by a crash mid-write
**What goes wrong:** `jq '...' state.json > state.json` truncates the file before jq finishes — a crash mid-write leaves a zero-byte or partial JSON, and the next run can't parse it (recovery prompt breaks).
**Why it happens:** Redirection (`>`) truncates immediately; read-modify-write on the same path is non-atomic.
**How to avoid:** Always `jq '...' state.json > state.tmp.$$ && mv state.tmp.$$ state.json`. `mv` on the same filesystem is atomic (rename(2)). This is the SUMMARY.md "temp-file-then-rename" recommendation made concrete. For the very first write, `jq -n '...' > tmp && mv tmp state.json`.
**Warning signs:** `jq: error: Could not parse` on `.conjure-adopt-state`; recovery prompt crashes instead of offering options.

### Pitfall 3: Snapshot recursively copies prior backups (snapshot self-copy)
**What goes wrong:** `snapshot_create` does `cp -a "${target}/." "${snap_dir}/"`. If `backup_root` is *inside* `target` (e.g. `target/.conjure-adopt-backups/`), then `target/.` includes `.conjure-adopt-backups/` — the new snapshot copies all *prior* snapshots into itself. On GNU `cp` this is detected and skipped; on **BSD/macOS `cp` the behavior on a dest nested inside src is unspecified** and can error or balloon the copy. Even when it "works," each adopt run's snapshot grows by the size of all previous snapshots.
**Why it happens:** The lib copies `target/.` wholesale and is unaware of where its own `backup_root` sits.
**How to avoid:** The planner must decide one of: (a) pass a `backup_root` *outside* the target (but D-02/D-03/D-04 treat `.conjure-adopt-backups/` as living in the target — so this conflicts), or (b) exclude `.conjure-adopt-backups/`/`.conjure-archive-*` from the snapshot copy (requires a lib change or a pre-snapshot move), or (c) accept the first run is clean (no prior backups exist) and ensure adopt.sh removes/excludes nested backups before re-snapshot. **Recommendation:** Since D-12 says `--resume` reuses the existing snapshot (no second backup), the common path snapshots **once** when no prior backup exists — so the self-copy only bites on a fresh adopt after a prior completed adopt left backups. Plan a guard: snapshot into `backup_root` and have inventory/snapshot already exclude `.conjure-adopt-backups` (inventory does; snapshot does NOT). **Flag for planning:** decide whether to add an exclusion to `snapshot_create` (lib change — out of "don't reimplement" spirit but may be necessary) or to snapshot before any backup dir exists and refuse re-snapshot when one does. Either way, **add a test**: two consecutive live adopts must not nest backups-in-backups.
**Warning signs:** `.conjure-adopt-backups/conjure-adopt-<ts2>/.conjure-adopt-backups/conjure-adopt-<ts1>/...` nesting; snapshot dir size grows non-linearly across runs; macOS `cp` error "cannot copy a directory into itself."

### Pitfall 4: SIGKILL recovery hinges on durability, not the trap
**What goes wrong:** SAFE-05 / Phase 24 criterion 4 test `kill -9` mid-run. `kill -9` (SIGKILL) **cannot be trapped** — `trap '...' INT TERM` does nothing for it. If the design relies on the trap to flush state, SIGKILL leaves no recoverable manifest and the "offer rollback/continue/start-fresh" prompt never appears on re-run.
**Why it happens:** Conflating "graceful interrupt handling" (INT/TERM) with "crash recovery" (SIGKILL, power loss, OOM).
**How to avoid:** Two mechanisms, not one. (1) `trap '<flush partial state note>; exit 2' INT TERM` for graceful interrupts (SAFE-05 explicit INT/TERM clause). (2) **Write state durably BEFORE each mutating step** (Pattern 3) so that even an untrappable kill leaves `.conjure-adopt-state` saying "step N started." The recovery prompt keys off the *persisted* state, not the trap. **Test SIGKILL by:** launch adopt in background, `kill -9` after the snapshot step (Phase 24 criterion 4 says "after snapshot, before scaffold"), re-run, assert the recovery prompt fires.
**Warning signs:** SIGKILL test re-run runs the pipeline fresh (no prompt) → state wasn't durable; or the trap "works" in tests using SIGTERM but the real `kill -9` test fails.

### Pitfall 5: Dirty-tree gate uses the wrong git check
**What goes wrong:** Using `git diff --quiet` (misses untracked files) or `git status --short` (affected by user color config) for ADOPT-03. A repo with only untracked files passes `git diff --quiet` but is genuinely dirty for adopt's purposes (the snapshot would include untracked files git doesn't know about — CR-3).
**Why it happens:** Multiple git "is it clean" idioms exist with different semantics.
**How to avoid:** Use `git -C "$target" status --porcelain` — empty output = clean (exit code irrelevant). This catches tracked-modified AND untracked. Non-empty + no `--force` → `log_fail`-style message + `exit 2`. Non-empty + `--force` → proceed AND `log_step WARN "uncommitted changes included in snapshot; --rollback restores from snapshot, not git"` (SAFE-06 / CR-3 / Phase 24 criterion 3). Handle non-git target gracefully (porcelain errors → treat as "not a git repo," allow with a note, since snapshot still works).
**Warning signs:** Phase 24 criterion 3 (`--force` warning in log) fails; a dirty tree with only untracked files is allowed without `--force`.

### Pitfall 6: Line-count delta off-by-one (trailing newline)
**What goes wrong:** ADOPT-06 report shows "CLAUDE.md line-count delta." `wc -l` counts newlines; `mutate_write` uses `printf '%s'` (no trailing newline added). A before/after comparison using inconsistent counting reports a misleading delta. (Phase 22 doesn't condense CLAUDE.md itself — that's Phase 23 — but the *report* must show before/after consistently, and the `--apply-step write` op writes content.)
**How to avoid:** Use `wc -l < "$file"` (redirect form, no filename noise) consistently for both before and after, exactly as `audit-setup.sh` does (line 29). Capture the "before" count from the snapshot copy or pre-mutation, the "after" from the live file.
**Warning signs:** Report shows a delta of ±1 that doesn't match an editor's line count.

## Code Examples

> All examples are derived from the live codebase patterns read this session (`cli/conjure`, `scripts/resolve.sh`, `scripts/audit-setup.sh`, `lib/*.sh`). They are scaffolds for the planner, not finished code.

### `cmd_adopt` dispatch wrapper (cli/conjure)
```bash
# Mirror of cmd_audit/cmd_resolve (cli/conjure lines 144-190). Thin: parse → env → exec.
cmd_adopt() {
  local target dryrun force rollback resume start_fresh apply_step update_manifest full_inv
  target="$(pwd)"; dryrun=0; force=0; rollback=0; resume=0; start_fresh=0
  apply_step=""; update_manifest=0; full_inv=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --dry-run)         dryrun=1 ;;
      --force)           force=1 ;;
      --rollback)        rollback=1 ;;
      --resume)          resume=1 ;;
      --start-fresh)     start_fresh=1 ;;
      --apply-step)      shift; apply_step="${1:-}" ;;
      --update-manifest) update_manifest=1 ;;
      --full-inventory)  full_inv=1 ;;
      --help|-h)         echo "Usage: conjure adopt [--dry-run] [--force] [--rollback] [--resume] [--start-fresh] [--apply-step <id>] [--update-manifest] [--full-inventory] [target]"; return 0 ;;
      *)                 target="$1" ;;
    esac
    shift
  done
  cmd_preflight || return 1
  CONJURE_HOME="$CONJURE_HOME" DRY_RUN="$dryrun" \
    CONJURE_ADOPT_FORCE="$force" CONJURE_ADOPT_ROLLBACK="$rollback" \
    CONJURE_ADOPT_RESUME="$resume" CONJURE_ADOPT_START_FRESH="$start_fresh" \
    CONJURE_ADOPT_APPLY_STEP="$apply_step" CONJURE_ADOPT_UPDATE_MANIFEST="$update_manifest" \
    CONJURE_ADOPT_FULL_INVENTORY="$full_inv" \
    bash "$CONJURE_HOME/scripts/adopt.sh" "$target"
}
# Dispatch (add near cli/conjure line 466):  adopt)  shift; cmd_adopt "$@" ;;
# usage() (add near line 39):  conjure adopt [--dry-run] [--force] [--rollback] [--resume] ...
```

### Pipeline skeleton (scripts/adopt.sh) — header + lib sourcing + trap
```bash
#!/usr/bin/env bash
# scripts/adopt.sh — conjure adopt pipeline orchestrator.
# Exit codes: 0 = success, 2 = hard failure / non-TTY recovery / dirty-tree refusal.
set -uo pipefail
CONJURE_HOME="${CONJURE_HOME:-$(cd "$(dirname "$0")/.." && pwd)}"
TARGET="${1:-$(pwd)}"
# shellcheck source=/dev/null
source "$CONJURE_HOME/lib/mutate.sh"    || { echo "adopt.sh: cannot source lib/mutate.sh" >&2; exit 2; }
source "$CONJURE_HOME/lib/caps.sh"      || { echo "adopt.sh: cannot source lib/caps.sh" >&2; exit 2; }
source "$CONJURE_HOME/lib/log.sh"       || { echo "adopt.sh: cannot source lib/log.sh" >&2; exit 2; }
source "$CONJURE_HOME/lib/snapshot.sh"  || { echo "adopt.sh: cannot source lib/snapshot.sh" >&2; exit 2; }
source "$CONJURE_HOME/lib/inventory.sh" || { echo "adopt.sh: cannot source lib/inventory.sh" >&2; exit 2; }

STATE_PATH="$TARGET/.conjure-adopt-state"   # NOTE: directory per D-07 staging/ — or file+sibling staging dir; planner decides
# SAFE-05: graceful INT/TERM (SIGKILL handled by write-before-step durability, NOT this trap)
trap 'echo "interrupted — partial state at $STATE_PATH; recover with --rollback|--resume|--start-fresh" >&2; exit 2' INT TERM
```

### Dirty-tree precondition (Step 0, ADOPT-03 + SAFE-06)
```bash
precondition_git() {
  local dirty; dirty="$(git -C "$TARGET" status --porcelain 2>/dev/null)"
  if [ -n "$dirty" ]; then
    if [ "${CONJURE_ADOPT_FORCE:-0}" != "1" ]; then
      echo "✗ working tree is dirty — commit/stash first, or pass --force" >&2
      exit 2                                  # never exit 1
    fi
    log_step WARN "--force on dirty tree; uncommitted changes are in the snapshot. --rollback restores from snapshot, NOT git."
    echo "⚠ --force: uncommitted changes included in snapshot (rollback is snapshot-based, not git)"
  fi
}
```

### Atomic state write (SAFE-04, Pitfall 2)
```bash
# state_set_step <step_name> <status>  — atomic temp+mv
state_record() {  # args: jq filter applied to current state
  local filter="$1"; local tmp="${STATE_PATH}.tmp.$$"
  if [ -f "$STATE_PATH" ]; then
    jq "$filter" "$STATE_PATH" > "$tmp" && mv "$tmp" "$STATE_PATH"
  else
    jq -n "$filter" > "$tmp" && mv "$tmp" "$STATE_PATH"   # first write
  fi
}
# sha256 cross-platform (exact pattern from mutate.sh lines 113-123)
sha_of() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
  else shasum -a 256 "$1" | cut -d' ' -f1; fi
}
```

### Rollback (D-01: restore → delete created[] → verify sha256 → cleanup)
```bash
rollback_path() {
  local snap; snap="$(jq -r '.snapshot_path' "$STATE_PATH")"
  [ -d "$snap" ] || { echo "✗ no snapshot at $snap — nothing to roll back" >&2; exit 2; }  # MN-2
  RESTRUCTURE_LOG_PATH="$TARGET/RESTRUCTURE-LOG.md"
  snapshot_rollback "$snap" "$TARGET"                 # step 1: whole-tree restore + un-archive
  # step 2: delete scaffolded files the snapshot can't undo (D-02 excludes conjure's own dirs)
  jq -r '.created[]?' "$STATE_PATH" | while IFS= read -r p; do
    [ -n "$p" ] && mutate_rm "$TARGET/$p"
  done
  # step 3: verify every mutated file matches its recorded before-hash (SAFE-02)
  local mismatch=0
  while IFS=$'\t' read -r p before; do
    [ -z "$p" ] && continue
    [ "$(sha_of "$TARGET/$p")" = "$before" ] || { echo "✗ sha mismatch after rollback: $p" >&2; mismatch=1; }
  done < <(jq -r '.mutated[]? | "\(.path)\t\(.before)"' "$STATE_PATH")
  [ "$mismatch" -eq 0 ] || exit 2
  log_step ROLLBACK "restored from $snap; deleted $(jq '.created|length' "$STATE_PATH") created paths"
  rm -f "$STATE_PATH"                                 # D-04: keep snapshot/archive/log, drop state
}
```

### `.conjure-adopt-state` schema sketch (Claude's Discretion — mirrors snapshot-meta + manifest)
```json
{
  "schema_version": "1",
  "started_at": "2026-05-28T14:23:00Z",
  "target": "/abs/path",
  "snapshot_path": "/abs/path/.conjure-adopt-backups/conjure-adopt-20260528T142300Z",
  "current_step": "scaffold",
  "steps": {
    "preconditions": "completed",
    "snapshot":      "completed",
    "inventory":     "completed",
    "scaffold":      "started",
    "audit":         "pending"
  },
  "created": [".claude/hooks/stop.mjs", ".claude/skills/restructure/SKILL.md"],
  "mutated": [{"path": "CLAUDE.md", "before": "<sha256>", "after": "<sha256>"}]
}
```
> `staging/` (D-07) is a sibling directory `.conjure-adopt-state/staging/` if STATE_PATH is a dir, or `.conjure-adopt-staging/` if STATE_PATH is a file. Planner decides the layout; the schema above assumes the file form. Note `current_step` + per-step `started`/`completed` is what makes SIGKILL recovery work (Pitfall 4).

### Adoption report (ADOPT-06 / D-09 — labeled plain-text, no new deps)
```bash
report() {  # reads adopt-manifest.json + state; echo lines like cmd_audit
  echo
  echo "Adoption report"
  echo "  Inventory:   $(jq -r '.summary.total_files' "$MANIFEST") files ($(jq -r '.summary.unknown' "$MANIFEST") unknown)"
  echo "  Scaffolded:  $(jq '.created|length' "$STATE_PATH") layer files"
  echo "  Archived:    ${ARCHIVED_COUNT:-0} files"
  echo "  CLAUDE.md:   ${BEFORE_LINES} → ${AFTER_LINES} lines (cap ${CLAUDE_MD_CAP})"
  echo "  Snapshot:    $CONJURE_SNAPSHOT_PATH"
  echo "  Audit:       before rc=${AUDIT_BEFORE_RC} → after rc=${AUDIT_AFTER_RC}"
  echo "  Next:        open Claude Code → run the restructure skill"
}
```

## State of the Art

| Old Approach (research drafts, pre-Phase-21) | Current Approach (live code) | Impact |
|----------------------------------------------|------------------------------|--------|
| 11-tag classifier (`candidate-skill`, `stale-candidate`, …) in ARCHITECTURE.md §2 | 6 deterministic buckets only (`core/skill/agent/planning-doc/reference-doc/unknown`) per Phase 21 D-01/D-02 | Plan against the 6-bucket manifest; the richer tags are LLM judgment (Phase 23) |
| `snapshot_list <target>` | `snapshot_list <backup_root>` (lib/snapshot.sh line 93) | Pass backup_root, not target |
| Manifest dry-run → `mutate_write` to `/tmp` (Anti-Pattern 3 in ARCHITECTURE.md) | Lib hardcodes `/tmp/adopt-manifest-dryrun.json`; D-11 supersedes with `mktemp -d` outside target | adopt.sh must control the dry-run manifest path (Pitfall 1) |
| `restructure_steps[]` op types: `move-to-skill`, `update-claude-md`, `scaffold-skill` (ARCHITECTURE.md) | D-08 scope: `archive`, `write`, `extract`(=write+archive) | Plan only these three op types for Phase 22 |
| Step manifest at `.claude/adopt-state.json` (research) | `.conjure-adopt-state` at target root (CONTEXT.md) | Use the CONTEXT.md path/name |

**Deprecated/outdated:**
- ARCHITECTURE.md §3's manifest JSON (with `git_age_days`, `links_to`, `at_imports_detected`) — superseded by the real `adopt-manifest.schema.json` (no `git_age_days` per D-05, no `links_to`, `linked_from` only per D-06). Plan against `adopt-manifest.schema.json`, not the research draft.
- ARCHITECTURE.md's `--inventory` / `--status` sub-flags — not in CONTEXT.md's flag set. Phase 22 flags are exactly: `--dry-run`, `--force`, `--rollback`, `--apply-step`, `--update-manifest`, `--resume`, `--start-fresh`, `--full-inventory`.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | BSD/macOS `cp -a src/. dest/` where dest is nested inside src has unspecified/error behavior (vs GNU cp's skip) | Pitfall 3 | If macOS cp silently handles it, the self-copy is "only" a size bloat, not a hard failure — still worth a test, lower urgency |
| A2 | `mv` on the same filesystem is atomic for `.conjure-adopt-state` writes | Pitfall 2, Code Examples | If state and tmp land on different filesystems (unlikely — same dir), `mv` falls back to copy+unlink (non-atomic). Keeping tmp in the same dir (`${STATE_PATH}.tmp.$$`) guarantees same-fs. |
| A3 | Reading the recovery prompt from `/dev/tty` (vs resolve.sh's fd-3 stdin trick) is acceptable and matches D-13 | Pattern 4 | D-13 explicitly says read from `/dev/tty`, so this is low-risk; resolve.sh's fd-3 trick is for reading a *file list* while prompting, which adopt's single prompt doesn't need |
| A4 | The dry-run manifest can be written with DRY_RUN=0 for that one `inventory_emit_manifest` call (manifest is a read-only artifact per D-10, not a target mutation) | Pitfall 1, ADOPT-02 | If interpreted strictly as "no writes anywhere in dry-run," even the temp manifest write is suspect — but D-10/D-11 explicitly bless writing the manifest to a temp path. Low risk. |
| A5 | Phase 22 needs no lib changes — it pure-orchestrates. Possible exception: snapshot self-copy (Pitfall 3) may require excluding `.conjure-adopt-backups` in `snapshot_create` | Summary, Pitfall 3 | If a lib change to snapshot.sh is needed, it's a small additive exclusion, but it touches a "done" Phase 21 file — planner should scope it explicitly and add a regression test |

**Note:** No external package or API claims are made in this research (zero new deps), so the assumptions above are all about local code/OS behavior, verifiable by the Phase 22 tests themselves.

## Open Questions (RESOLVED)

> All three resolved during Phase 22 planning; each resolution is encoded in the plans (commit `c9a2565`). Recorded here for artifact-sync.

1. **`.conjure-adopt-state`: single file or directory?**
   - What we know: D-07 needs a `staging/` subdir for proposed content; SAFE-04 needs step records + sha256; D-01 needs `created[]`/`mutated[]`.
   - **RESOLVED — directory form `.conjure-adopt-state/`** with `state.json` + `staging/`. Keeps state + staging colocated and matches D-07's literal path `.conjure-adopt-state/staging/<file>`. See plan 22-02 Task 1 (`state_record`/schema).

2. **Snapshot self-copy mitigation (Pitfall 3) — lib change or ordering guard?**
   - What we know: `snapshot_create` copies `target/.` including `.conjure-adopt-backups/`; D-12 reuses the snapshot on resume (so usually snapshot-once).
   - **RESOLVED — ordering guard (b)+(c), no lib change.** Pipeline only snapshots when no `.conjure-adopt-state` exists; on a second full adopt (prior run completed, state deleted, backups remain), exclude/move-aside `.conjure-adopt-backups` before the raw `cp`. Backed by a two-consecutive-adopts regression test. See plan 22-01 Task 3(d) (test) + 22-02 Task 2 (guard).

3. **`--apply-step` validation depth (SUMMARY.md open question, partially resolved by D-08).**
   - What we know: D-08 + SUMMARY.md recommend `jq` parse + required-fields (`id`/`op`/`status`) check, full JSON Schema deferred.
   - **RESOLVED — op-allowlist + path containment.** Validate `op ∈ {write, archive, extract}`, required fields `{id, op, status}`, `src` (for write) resolves under the staging dir, reject `..`/relative escape (`mutate_archive` also rejects `..`). `exit 2` on any failure (never execute a malformed op). See plan 22-03 Task 2 (`apply_step` validation).

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| bash 3.2+ | entire pipeline | ✓ | 3.2.57 (live) | — (this is the floor) |
| jq | state + manifest read/write | ✓ | 1.8.1 | — (hard dep, preflight-checked) |
| git | dirty-tree gate, snapshot-meta | ✓ | 2.54.0 | non-git target → skip gate with note (snapshot still works) |
| sha256sum | SAFE-02/04 hashing | ✓ | Darwin 1.0 (`/sbin`) | shasum -a 256 |
| shasum | sha256 fallback | ✓ | present (`/usr/bin`) | — |
| cp -a | snapshot copy | ✓ | system | cp -Rp (lib already falls back) |
| mktemp -d | dry-run temp manifest (D-11) | ✓ | `/usr/bin/mktemp` | — |
| mv | atomic state write | ✓ | system | — |
| init-project.sh | scaffold (ADOPT-04) | ✓ | in repo | — |
| audit-setup.sh | audit (ADOPT-05) | ✓ | in repo | — |

**Missing dependencies with no fallback:** none — every dependency is present and verified this session.
**Missing dependencies with fallback:** git on a non-git target (skip the dirty-tree gate, note it, proceed — snapshot is filesystem-based and works regardless).

## Validation Architecture

> nyquist_validation is enabled (config.json `workflow.nyquist_validation: true`). This section enumerates the observable signals that prove each Phase 22 success criterion, so the orchestrator can build VALIDATION.md.

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Hand-rolled `tests/run.sh` (project standard — `bats-core` only at unit level per STACK.md; **no new test deps**). Mirror the Phase 21 inline block style (`tests/run.sh` lines ~1691+). |
| Config file | none — `tests/run.sh` is self-contained; sandbox via `tests/lib/sandbox.sh` |
| Quick run command | `bash tests/run.sh 2>&1 \| grep -A40 "Phase 22"` (run the suite, focus the Phase 22 block) |
| Full suite command | `bash tests/run.sh` (302+ assertions; exits non-zero on any failure) |

### Phase Requirements → Test Map (the five ROADMAP success criteria + req coverage)
| Criterion / Req | Behavior (observable signal) | Test Type | Automated Command | File Exists? |
|-----------------|------------------------------|-----------|-------------------|--------------|
| Criterion 1 / ADOPT-02 | `adopt --dry-run` on brownfield-simple prints 5-step plan AND writes **zero files to target** AND manifest lands at a temp path | integration | sandbox copy fixture; run `DRY_RUN=1 ... adopt.sh`; assert `git status --porcelain "$sb"` empty AND `find "$sb" -name adopt-manifest.json` empty AND temp manifest exists | ❌ Wave 0 (new Phase 22 block) |
| Criterion 1 / ADOPT-02 | dry-run output contains `preconditions`, `snapshot`, `inventory`, `scaffold`, `audit` + `[dry-run] would …` lines | integration | grep dry-run stdout for each step label | ❌ Wave 0 |
| Criterion 2 / ADOPT-01,04,05,06 | live `adopt` on clean fixture: snapshot created, manifest emitted, missing layers scaffolded (existing untouched), audit ran, report shows before/after CLAUDE.md lines | integration | run live in sandbox; assert `.conjure-adopt-backups/*/CLAUDE.md` exists, `adopt-manifest.json` present, new `.claude/hooks/*` present, pre-existing `.claude/skills/git/SKILL.md` byte-unchanged, report line matches `CLAUDE.md: 21 → 21` | ❌ Wave 0 |
| Criterion 2 / ADOPT-04 | idempotent scaffold: a pre-existing file is NOT overwritten | integration | sha256 a pre-existing skill before/after; assert equal | ❌ Wave 0 |
| Criterion 3 / ADOPT-03,SAFE-06 | dirty-tree fixture → `exit 2` with clear message; same with `--force` → proceeds + logs WARN in RESTRUCTURE-LOG.md | integration | `git init` sandbox, touch untracked file; run without force → assert rc==2; run with `--force` → assert rc==0 AND `grep -q 'WARN.*uncommitted' RESTRUCTURE-LOG.md` | ❌ Wave 0 |
| Criterion 4 / SAFE-02 | live run then `--rollback` → every mutated file's sha256 == recorded before; `[ROLLBACK]` in log | integration | run live, capture pre-adopt sha256 of all files; rollback; assert per-file sha256 equal AND `grep -q '\[ROLLBACK\]' RESTRUCTURE-LOG.md` AND `created[]` files gone | ❌ Wave 0 |
| Criterion 4 / SAFE-02 | **zero-diff**: pre-adopt tree vs post-rollback tree (excluding conjure dirs per D-03) | integration | `diff -r` with excludes for `.conjure-adopt-backups`/`.conjure-archive-*`/`RESTRUCTURE-LOG.md`/`adopt-manifest.json` → assert empty | ❌ Wave 0 (also Phase 24, but a Phase 22 smoke version is valuable) |
| Criterion 5 / SAFE-05 | SIGKILL mid-run → re-run detects partial `.conjure-adopt-state` and offers `[r]/[c]/[s]` | integration | run adopt in background, `kill -9` after snapshot; re-run with `CONJURE_FORCE_INTERACTIVE=1` feeding `r\n` via `/dev/tty` substitute OR run non-interactively and assert `exit 2` + "last completed: snapshot" message (D-13) | ❌ Wave 0 |
| SAFE-04 | each step writes a state record with sha256 before/after; state is valid JSON after each step | integration | after a run, `jq . .conjure-adopt-state` parses; `.mutated[].before` present | ❌ Wave 0 |
| SAFE-07 | RESTRUCTURE-LOG.md gets an entry per step AS it happens (durability) | integration | assert log has SNAPSHOT, INVENTORY, SCAFFOLD, AUDIT lines in order | ❌ Wave 0 |
| ADOPT-02 (lib gap) | dry-run manifest is at mktemp temp, NOT `/tmp/adopt-manifest-dryrun.json` fixed path | integration | assert manifest path printed is under `$TMPDIR`/`mktemp -d`, not the hardcoded `/tmp` file | ❌ Wave 0 (validates Pitfall 1 fix) |
| D-08 / D-05 | `--apply-step` on a synthetic manifest fixture executes `write` and `archive` ops via mutate_*; marks `status: applied` | integration | hand-author manifest with one `write` + one `archive` step; run `--apply-step`; assert files changed AND `jq '.restructure_steps[].status'` == applied AND log has RESTRUCTURE entry | ❌ Wave 0 (new fixture) |
| D-08 / D-06 | `--update-manifest` appends a step + rejects malformed JSON with exit 2 | integration | feed valid step → assert appended; feed `{}` (no id/op) → assert rc==2 | ❌ Wave 0 |
| Pitfall 3 | two consecutive live adopts do NOT nest backups-in-backups | integration | run adopt twice (delete state between); assert no `.conjure-adopt-backups/*/.conjure-adopt-backups` nesting | ❌ Wave 0 (regression for self-copy) |

### Sampling Rate
- **Per task commit:** `bash tests/run.sh 2>&1 | grep -E "Phase 22|✗"` (Phase 22 block + any failures)
- **Per wave merge:** `bash tests/run.sh` (full suite green — must not regress Phase 21 or v0.5.0 blocks)
- **Phase gate:** Full suite green + `shellcheck scripts/adopt.sh cli/conjure` clean before `/gsd-verify-work`

### Wave 0 Gaps
- [ ] Phase 22 test block in `tests/run.sh` — covers all five ROADMAP criteria + SAFE-04/07 + D-08 (mirror Phase 21 block at lines ~1691+; use `sandbox_setup` for isolation)
- [ ] Synthetic `restructure_steps[]` manifest fixture (hand-authored, one `write` + one `archive` op) for `--apply-step`/`--update-manifest` tests (D-08)
- [ ] A git-initialized sandbox helper path for the dirty-tree test (criterion 3) — `git init` + untracked file inside `sandbox_setup`'d dir
- [ ] SIGKILL test harness: background-launch + `kill -9` + re-run assertion (mirror nothing existing — new pattern; non-TTY exit-2 assertion is the simplest reliable form)
- [ ] `shellcheck` directive coverage for `adopt.sh` (the codebase uses inline `# shellcheck disable=` and `# shellcheck source=/dev/null` — match that style)

> No framework install needed — `tests/run.sh` + `tests/lib/sandbox.sh` already exist. All gaps are *new assertions/fixtures*, not new infrastructure.

## Sources

### Primary (HIGH confidence — read directly this session)
- `lib/snapshot.sh`, `lib/inventory.sh`, `lib/log.sh`, `lib/mutate.sh`, `lib/caps.sh` — the built Phase 21 primitives; all signatures/behaviors above are from the live code
- `cli/conjure` (cmd_resolve, cmd_audit, cmd_update, dispatch case, usage) — the dispatch/wrapper pattern to mirror
- `scripts/resolve.sh` — the `/dev/tty` + non-TTY exit-2 + fd-3 prompt model (D-13/D-14)
- `scripts/init-project.sh` — idempotent scaffold subprocess (ADOPT-04); confirmed all writes guarded
- `scripts/audit-setup.sh` — exit 0/1/2 contract, `wc -l <` line counting, `^@` import check (ADOPT-05)
- `adopt-manifest.schema.json` — the real draft-07 manifest schema (6-bucket enum, restructure_steps[])
- `tests/run.sh` (Phase 21 block + sandbox usage), `tests/lib/sandbox.sh`, `tests/fixtures/brownfield-simple/` — test conventions + the fixture this phase runs against
- Live environment probes — bash 3.2.57, jq 1.8.1, git 2.54.0, sha256sum + shasum present, mktemp present
- `.planning/phases/22-conjure-adopt-cli-core-rollback/22-CONTEXT.md` — D-01..D-15 (authoritative spec)
- `.planning/REQUIREMENTS.md`, `.planning/ROADMAP.md` (Phase 22 goal + 5 criteria), `.planning/STATE.md`
- `.planning/phases/21-foundation-libs-inventory/21-CONTEXT.md`, `21-VALIDATION.md`

### Secondary (MEDIUM confidence — v0.6.0 research synthesized pre-Phase-21)
- `.planning/research/SUMMARY.md` — build order, CR-1..7, Open Questions (step-id, manifest atomicity, validation depth)
- `.planning/research/ARCHITECTURE.md` — component boundaries; **note: its 11-tag classifier + manifest draft + sub-flags are superseded by Phase 21 D-01/D-09 and CONTEXT.md** (see State of the Art)
- `.planning/research/PITFALLS.md` — CR-2 (partial-apply), CR-3 (snapshot/git), CR-4 (archive≠rollback), M-3 (idempotency), M-4 (UTC/quote-safe/cp), MN-2 (rollback guard)

### Tertiary (LOW confidence)
- None — this phase required no external/web research (known POSIX-bash domain, all primitives in-repo).

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — every tool verified present on the live machine; zero new deps; all primitives read from source
- Architecture: HIGH — derived directly from live `cli/conjure` patterns + the built Phase 21 libs + locked CONTEXT.md decisions
- Pitfalls: HIGH for structural (dry-run zero-writes, atomic state, SIGKILL durability, dirty-tree gate); MEDIUM for the snapshot self-copy edge (A1 — exact macOS `cp` behavior on nested dest not re-verified this session, flagged for a test)

**Research date:** 2026-05-28
**Valid until:** ~2026-06-27 (30 days — stable in-repo domain; the only volatility is if Phase 21 libs change, which would invalidate the signatures above)
