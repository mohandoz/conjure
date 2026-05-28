---
phase: 22-conjure-adopt-cli-core-rollback
plan: 02
subsystem: api
tags: [bash, cli, adopt, snapshot, inventory, jq, atomic-state, signal-trap, dirty-tree, pitfall-3]

# Dependency graph
requires:
  - phase: 21-foundation-libs-inventory
    provides: "lib/snapshot.sh (snapshot_create/rollback), lib/inventory.sh (scan/emit_manifest), lib/log.sh (init/step/fail), lib/mutate.sh (chokepoint), lib/caps.sh; scripts/init-project.sh (idempotent scaffold), scripts/audit-setup.sh (0/1/2 exit contract)"
  - phase: 22-conjure-adopt-cli-core-rollback (plan 01)
    provides: "Phase 22 graceful-red test block in tests/run.sh (9 sections); _adopt-restructure-steps synthetic manifest fixture; the red→green executable contract"
provides:
  - "cmd_adopt thin dispatcher in cli/conjure (flag parse → CONJURE_ADOPT_* env → exec adopt.sh) + dispatch router entry + usage line"
  - "scripts/adopt.sh — the forward 5-step pipeline orchestrator (preconditions → snapshot → inventory → scaffold → audit → report) with crash-durable .conjure-adopt-state/, INT/TERM trap, dirty-tree gate, dry-run mktemp temp manifest, and the snapshot-outside-target self-copy guard"
  - "CONJURE_INVENTORY_MAX cap-lift mechanism in lib/inventory.sh wired to --full-inventory (default 500 unchanged)"
  - "Wave 2 mode-dispatch skeleton (rollback/apply-step/update-manifest/recovery stubs) so Plan 03 only fills function bodies"
affects: [22-03 (rollback/recovery/apply-step/update-manifest op-executor — shares scripts/adopt.sh), 23 (restructure skill drives --apply-step/--update-manifest), 24 (Argus zero-diff after rollback)]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Snapshot-outside-target self-copy guard: snapshot into a mktemp root OUTSIDE the target, then relocate the snapshot dir into the in-target .conjure-adopt-backups — the raw `cp -a target/.` never sees its own destination (Pitfall 3, no lib change)"
    - "Crash-durable step state: directory-form .conjure-adopt-state/ with state.json written atomically (jq>tmp.$$+mv same-dir) BEFORE each mutating step (SAFE-04 / SIGKILL-survivable)"
    - "Dry-run reads-for-real but writes zero under the target: emit the manifest to a mktemp -d dir with DRY_RUN=0 for that single read-only call (D-10/D-11, bypasses the lib's hardcoded /tmp redirect)"
    - "Call-time env cap override: CONJURE_INVENTORY_MAX read inside inventory_scan (not at source-time) so a later export from adopt.sh takes effect"

key-files:
  created:
    - scripts/adopt.sh
  modified:
    - cli/conjure
    - lib/inventory.sh
    - tests/run.sh

key-decisions:
  - "Directory-form .conjure-adopt-state/ (state.json + staging/) per D-07's literal staging path and RESEARCH Open Question 1"
  - "Self-copy guard implemented by snapshotting into a temp root outside the target then relocating (not move-aside-and-merge) — the in-target mkdir-before-cp is what causes macOS cp -a infinite recursion, so the destination must live outside the copied tree"
  - "log_init runs BEFORE the precondition gate so the --force dirty-tree WARN lands in RESTRUCTURE-LOG.md; state writes still happen only after the gate passes (a refused run leaves no state to false-trigger recovery)"
  - "adopt.sh resolves TARGET by skipping leading flag tokens (and --apply-step's value) so callers/tests may pass flags positionally even though the contract is carried by CONJURE_ADOPT_* env vars"

patterns-established:
  - "snapshot_guarded(): temp-root snapshot → relocate into in-target backup root → restore prior snapshots alongside (preserves D-04 history, prevents Pitfall 3 nesting)"
  - "state_record <jq-filter> [--arg...]: single atomic temp+mv state writer reused by state_init/state_set_step/state_set_snapshot/state_add_created/state_add_mutated"
  - "Mode dispatch at the bottom of adopt.sh: rollback / apply-step / update-manifest / resume / prior-partial-state → handler (Wave 2 stubs); else run_pipeline"

requirements-completed: [ADOPT-01, ADOPT-02, ADOPT-04, ADOPT-05, ADOPT-06, SAFE-01, SAFE-04, SAFE-06, SAFE-07]

# Metrics
duration: 35min
completed: 2026-05-29
---

# Phase 22 Plan 02: conjure adopt CLI core + forward pipeline Summary

**`conjure adopt` command surface + the forward 5-step pipeline (preconditions → snapshot → inventory → scaffold → audit → report) with crash-durable atomic state, an INT/TERM trap, a `git status --porcelain` dirty-tree gate, dry-run zero-writes via a mktemp temp manifest, and a snapshot-outside-target self-copy guard.**

## Performance

- **Duration:** ~35 min
- **Started:** 2026-05-28T20:45Z (approx)
- **Completed:** 2026-05-29
- **Tasks:** 2
- **Files modified:** 4 (1 created: scripts/adopt.sh; 3 modified: cli/conjure, lib/inventory.sh, tests/run.sh)

## Accomplishments

- Added `cmd_adopt` to `cli/conjure` as a thin wrapper mirroring `cmd_resolve`/`cmd_audit`: parses the eight flags + `--help` + positional target, runs `cmd_preflight`, then execs `scripts/adopt.sh` passing the full `CONJURE_ADOPT_*` env contract. Added the dispatch router entry and the `usage()` line. Zero business logic in the CLI.
- Built `scripts/adopt.sh` (436 lines) — the forward pipeline orchestrator: sources the five Phase 21 libs in dependency order, installs an INT/TERM trap, gates the dirty tree (`git status --porcelain`; exit 2 / `--force` WARN; non-git → skip with a note), writes the directory-form `.conjure-adopt-state/state.json` atomically (jq>tmp.$$+mv) before each mutating step, then runs snapshot → inventory → scaffold → audit → report. Zero `exit 1`; snapshot via raw `cp`, not `mutate_cp`.
- Solved Pitfall 1 (dry-run zero-writes): in `--dry-run` the manifest is emitted to a `mktemp -d` dir OUTSIDE the target with `DRY_RUN=0` for that single read-only call, so it never hits the lib's hardcoded `/tmp/adopt-manifest-dryrun.json` and leaves zero files under the target.
- Solved Pitfall 3 (snapshot self-copy): `snapshot_create` does `mkdir -p snap_dir` (in-target) then `cp -a target/.`, which on macOS recurses infinitely into its own destination. Fixed at the orchestrator by snapshotting into a temp root outside the target and relocating the snapshot dir into the in-target `.conjure-adopt-backups/` — no `lib/snapshot.sh` change.
- Wired `--full-inventory`: introduced `CONJURE_INVENTORY_MAX` (default 500 — Phase 21 behavior preserved), replaced the two hardcoded 500-file cap sites + the hint message, and had adopt.sh export a high cap when `CONJURE_ADOPT_FULL_INVENTORY=1`. Verified end-to-end (600 md files: default caps at 500, `--full-inventory` scans all 600).
- Wired the Wave 2 mode-dispatch skeleton (rollback / apply-step / update-manifest / resume / prior-partial-state → handler stubs) so Plan 03 only fills function bodies.

## Task Commits

Each task was committed atomically:

1. **Task 1: cmd_adopt dispatcher + scripts/adopt.sh (header, trap, dirty-tree gate, state schema, full pipeline)** — `ac428bc` (feat)
2. **Task 2: --full-inventory cap-lift wiring + self-copy regression assertion fix** — `a3ecb59` (feat)

**Plan metadata:** _(this docs commit)_

_Note: Task 1 and Task 2 both touch `scripts/adopt.sh`; the orchestrator (skeleton + run_pipeline) is one new file committed under Task 1, while Task 2 carries the additive lib cap-lift + the test-pattern correction._

## Files Created/Modified

- `scripts/adopt.sh` (created) — 5-step pipeline orchestrator + `.conjure-adopt-state/` schema/atomic writers + INT/TERM trap + dirty-tree gate + dry-run temp manifest + `snapshot_guarded` self-copy guard + Wave 2 mode-dispatch stubs.
- `cli/conjure` (modified) — `cmd_adopt` thin dispatcher, `adopt)` dispatch router entry, `conjure adopt ...` usage line.
- `lib/inventory.sh` (modified) — `CONJURE_INVENTORY_MAX` cap var (default 500), call-time `scan_max` in `inventory_scan`, both former-`500` sites + the hint message now reference it (additive; Phase 21 inventory tests unaffected).
- `tests/run.sh` (modified) — corrected the Wave 0 self-copy regression assertion (`-mindepth 2 -name .conjure-adopt-backups` instead of a backup-root-rooted `-path` glob that matched all snapshot content).

## Decisions Made

- **Directory-form `.conjure-adopt-state/`** (`state.json` + `staging/`) per D-07 + RESEARCH Open Question 1.
- **Self-copy guard = snapshot-outside-then-relocate**, not move-aside-and-merge. The root cause is the in-target `mkdir -p snap_dir` before the raw `cp -a target/.`; the only robust fix is to ensure the copy destination lives outside the copied tree, then relocate.
- **`log_init` before the precondition gate** so the `--force` WARN is logged; state writes remain post-gate so a refused dirty run leaves no state.
- **adopt.sh resolves TARGET by skipping flag tokens** (and `--apply-step`'s value), supporting positional flag passing in tests/callers while the env-var contract stays authoritative.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Wave 0 self-copy regression assertion could never pass**
- **Found during:** Task 2 (running the Phase 22 self-copy section)
- **Issue:** The Plan 01 (Wave 0) assertion `find "$BACKUP_ROOT" -path '*/.conjure-adopt-backups/*'` is rooted at the backup root, which is itself named `.conjure-adopt-backups`. Every descendant path therefore matches the glob, so the find returned all snapshot content (26 matches for a single clean snapshot) and the `[ -z ]` check could never be true — the assertion failed even when production code produced no nesting. The intent (per its own comment) was to detect a `.conjure-adopt-backups` directory nested INSIDE a snapshot.
- **Fix:** Switched the assertion to `find "$BACKUP_ROOT" -mindepth 2 -name '.conjure-adopt-backups' -type d`, which matches only a backup dir nested at depth ≥ 2 (true self-copy nesting). Verified production code yields zero such hits across two consecutive adopts (only one `.conjure-adopt-backups` dir exists).
- **Files modified:** `tests/run.sh`
- **Verification:** `self-copy: two adopts produce no nested .conjure-adopt-backups` now passes; `find … -name .conjure-adopt-backups -type d` confirms a single backup root.
- **Committed in:** `a3ecb59` (Task 2 commit)

**2. [Rule 1 - Bug] adopt.sh treated a leading `--force`/flag as the target path**
- **Found during:** Task 1 (dirty-tree `--force` section: exit 2 + a `--force/.conjure-adopt-state/...` path error)
- **Issue:** Tests invoke `bash adopt.sh --force "$target"`, so `$1="--force"` and `TARGET="--force"`. State writes then targeted `--force/.conjure-adopt-state/...` and `rm` choked on the leading `--`.
- **Fix:** Added a small arg-resolution loop at the top of adopt.sh that skips leading flag tokens (and `--apply-step`'s value) so the first bare positional is the target; the flag contract still rides on `CONJURE_ADOPT_*` env vars.
- **Files modified:** `scripts/adopt.sh`
- **Verification:** `--force` dirty-tree run now exits 0 and logs the WARN; all flag-positional test invocations resolve the correct target.
- **Committed in:** `ac428bc` (Task 1 commit)

**3. [Rule 1 - Bug] adopt.sh not executable (tripped the scripts-executable self-test)**
- **Found during:** Task 2 (full-suite run)
- **Issue:** The new `scripts/adopt.sh` was created without the executable bit; the suite's "scripts executable" check failed (`✗ NOT executable: scripts/adopt.sh`).
- **Fix:** `chmod +x scripts/adopt.sh` (matching `resolve.sh`/`init-project.sh`); committed with mode 100755.
- **Files modified:** `scripts/adopt.sh` (mode)
- **Verification:** Self-test green; `ls -l` shows `-rwxr-xr-x`.
- **Committed in:** `ac428bc` (Task 1 commit — file created with exec bit)

---

**Total deviations:** 3 auto-fixed (3 bugs)
**Impact on plan:** All three are correctness fixes required to make the planned behavior verifiable. The test-pattern fix corrects a Wave 0 assertion that could never pass; the other two are production-code bugs in the new orchestrator. No scope creep — no Wave 2 functionality was added.

## Issues Encountered

- Initial `selfcopy_guard_before`/`selfcopy_guard_after` (move-aside-then-merge) did NOT prevent Pitfall 3 because `snapshot_create` itself creates the in-target `snap_dir` before the `cp -a`, so the copy recursed into its own freshly-made destination (macOS `cp -a` "File name too long" → snapshot failed silently → missing SNAPSHOT log entry). Resolved by switching to the snapshot-outside-target-then-relocate strategy (`snapshot_guarded`).

## Known Stubs

The following are **intentional Wave 2 (Plan 03) stubs**, wired into the mode dispatch so Plan 03 only fills the function bodies. They are NOT silent placeholders — each prints a clear "not yet implemented (Wave 2 / Plan 03)" message and `exit 2`:

- `rollback_path()` — `--rollback` (SAFE-02 full restore + delete-created + sha256-verify, D-01). File: `scripts/adopt.sh`.
- `recovery_prompt()` / `--resume` — interactive `[r]/[c]/[s]` + resume-at-next-step (D-12/D-13/D-14). The non-TTY `exit 2` + "last completed:" + recovery-flags detection for a prior partial state IS implemented (the SIGKILL recovery section is green); the interactive prompt and the resume/rollback bodies are Plan 03.
- `apply_step()` — `--apply-step <id>` op executor (write/archive/extract, D-05/D-08). File: `scripts/adopt.sh`.
- `update_manifest()` — `--update-manifest` proposal writer (D-06/D-08). File: `scripts/adopt.sh`.

These stubs are why 7 Phase 22 assertions remain red (3 rollback, 3 apply-step, 1 update-manifest valid-append). This matches the plan's scope ("This plan STOPS before rollback/recovery/op-executor (Wave 2)") and verification target ("dry-run/live/dirty-tree/idempotency/state/log/self-copy go green").

## Verification

- `bash tests/run.sh`: **PASS 387 / FAIL 7** (baseline was PASS 359 / FAIL 9 graceful-red). The 7 remaining fails are exactly the Wave 2 features (rollback / apply-step / update-manifest); **zero** non-Phase-22 (Phase 21 / v0.5.0) regressions.
- Green Phase 22 sub-sections (this plan's target): dry-run zero-writes (ADOPT-02/D-11/Pitfall 1), live scaffold + idempotency + report 21→21 (ADOPT-01/04/05/06/SAFE-01), dirty-tree exit-2 / `--force` WARN (ADOPT-03/SAFE-06), state + log SNAPSHOT/INVENTORY/SCAFFOLD/AUDIT in order (SAFE-04/SAFE-07), git-init dirty-tree harness, SIGKILL non-TTY recovery exit 2 + last-completed + flags (SAFE-05), and the self-copy regression (Pitfall 3).
- `shellcheck -S error -e SC2164,SC2044,SC2034,SC2155 scripts/adopt.sh cli/conjure lib/inventory.sh` (the CI quality gate) → clean. `scripts/adopt.sh` is also clean at warning severity (only intentional SC2016 info-level jq single-quote filters remain, matching `lib/inventory.sh`).
- `grep -v '^#' scripts/adopt.sh | grep -c 'exit 1'` → 0.
- `--full-inventory` cap-lift verified end-to-end (600 md files: default 500, lifted to 600).

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- **Plan 03 (Wave 2)** can fill the four wired stubs (`rollback_path`, `recovery_prompt`/`--resume`, `apply_step`, `update_manifest`) against the existing red assertions and the `_adopt-restructure-steps` fixture. The `.conjure-adopt-state/state.json` schema it needs is already produced: `snapshot_path`, per-step `steps{}`, `created[]` (scaffolded harness paths, D-02), and `mutated[{path,before,after}]` (sha256) — exactly what D-01's rollback (snapshot_rollback → mutate_rm created[] → verify mutated[] sha256) consumes.
- **Note for Plan 03:** the rollback test's residual diff is `Only in .../.claude: COMPOUND-CANDIDATES.md` — the scaffold creates `.claude/COMPOUND-CANDIDATES.md`, which is in `created[]`, so the D-01 delete-created step will clear it on rollback. The `[ROLLBACK]` log entry + `created[]` deletion + sha256-verify are all that's needed to turn the three rollback assertions green.
- **Note for Plan 03:** `--apply-step` validation depth was resolved (op-allowlist {write,archive,extract} + required fields {id,op,status} + staging-path containment, `exit 2` on any failure — RESEARCH Open Question 3). The `--update-manifest` malformed-`{}` rejection already passes via the stub's `exit 2`; the valid-append path is Plan 03's to implement.
- **Note for Phase 23/24:** the `--apply-step`/`--update-manifest` staging contract (`.conjure-adopt-state/staging/<file>`, D-07) and the snapshot-outside-target guarantee (D-03 zero-diff excludes `.conjure-adopt-backups`/`.conjure-archive-*`/`RESTRUCTURE-LOG.md`/`adopt-manifest.json`/`.conjure-adopt-state`) hold from this plan.

## Self-Check: PASSED

- FOUND: `scripts/adopt.sh`
- FOUND: `.planning/phases/22-conjure-adopt-cli-core-rollback/22-02-SUMMARY.md`
- FOUND commits: `ac428bc`, `a3ecb59`
- TRACKED modifications: `cli/conjure`, `lib/inventory.sh`, `tests/run.sh`

---
*Phase: 22-conjure-adopt-cli-core-rollback*
*Completed: 2026-05-29*
