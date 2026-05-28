---
phase: 22-conjure-adopt-cli-core-rollback
verified: 2026-05-28T21:59:37Z
status: passed
score: 5/5 must-have truths verified
overrides_applied: 0
manual_verification_performed: 2026-05-29
manual_verification_method: "Interactive [r]/[c]/[s] recovery prompt driven through a real PTY via `expect` (exercises the genuine /dev/tty read, not the CONJURE_FORCE_INTERACTIVE shortcut). 11/11 assertions passed across all three branches."
human_verification:
  - test: "Interactive TTY recovery prompt: run `conjure adopt` on a brownfield repo in a real terminal, SIGKILL it mid-run (kill -9 after the snapshot step), then re-run `conjure adopt` interactively and confirm the `[r]ollback / [c]ontinue / [s]tart-fresh` prompt appears and each choice behaves (r restores, c resumes without re-snapshotting, s discards state and starts fresh; empty/unknown input re-prompts with no default)."
    expected: "The prompt loop reads from /dev/tty: 'r' triggers rollback (zero-diff restore), 'c' resumes at the first incomplete step reusing the existing snapshot, 's' removes state and runs the pipeline anew. Empty or unknown input re-prompts (D-14, no default)."
    result: "VERIFIED 2026-05-29 via PTY (expect). [r]: partial-run/last-completed line shown, bad input re-prompts (D-14), SAFE-06 git warning surfaced, [ROLLBACK] logged, state dir dropped (D-04), CLAUDE.md restored byte-identical (SAFE-02). [c]: resumes reusing snapshot, no second backup created (CR-2/D-12). [s]: empty input re-prompts, then start-fresh completes the pipeline. 11/11 checks passed."
    why_human: "recovery_prompt() reads from /dev/tty (scripts/adopt.sh:372). Verified by driving a real pseudo-terminal with `expect` rather than the non-interactive harness."
known_limitation:
  - scope: "SAFE-05 rollback-recovery race (refuse-closed, no corruption)"
    detail: "A SIGKILL landing in the sub-second window between snapshot_guarded creating the on-disk backup and state_set_snapshot flushing snapshot_path leaves snapshot_path empty. In that state the [r]ollback choice FAILS CLOSED ('no snapshot recorded') rather than risk restoring a possibly-partial cross-filesystem mv'd snapshot; [s]tart-fresh still works. Safe behavior; a proper auto-recovery needs a snapshot-completion marker (touches the Phase 21 snapshot contract) — deferred as hardening (STATE.md deferred items / Phase 24)."
---

# Phase 22: `conjure adopt` CLI Core + Rollback — Verification Report

**Phase Goal:** Users can run `conjure adopt` on an existing repo to get a complete, audited, rollback-capable adoption pipeline with zero filesystem surprises
**Verified:** 2026-05-28T21:59:37Z
**Status:** human_needed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

The five ROADMAP success criteria are the contract. Each was verified by (1) reading the shipped code, (2) confirming the Phase 22 test-block assertions are real, and (3) running an INDEPENDENT fresh-sandbox behavioral spot-check (not relying on the test harness).

| #   | Truth (ROADMAP success criterion) | Status | Evidence |
| --- | --------------------------------- | ------ | -------- |
| 1 | `conjure adopt --dry-run` on a brownfield fixture prints the full 5-step plan and writes ZERO files to the target; manifest written to a temp path outside the target | ✓ VERIFIED | Spot-check: all 5 step labels (preconditions/snapshot/inventory/scaffold/audit) printed; `find` for adopt-manifest.json + .conjure-adopt-state under target = 0; manifest written to `/var/folders/.../tmp.XXX/adopt-manifest.json` (mktemp, NOT the lib's hardcoded `/tmp/adopt-manifest-dryrun.json`). Code: run_pipeline DRY_RUN branch (adopt.sh:698-707) emits via `DRY_RUN=0 inventory_emit_manifest` into a `mktemp -d`. Pitfall 1 / D-11 honored. |
| 2 | `conjure adopt` (clean tree) creates a snapshot, emits adopt-manifest.json, scaffolds only missing layers (existing untouched), runs audit-setup.sh, prints before/after CLAUDE.md line-count report | ✓ VERIFIED | Spot-check: `.conjure-adopt-backups/*/CLAUDE.md` snapshot present (SAFE-01); `adopt-manifest.json` under target (ADOPT-01); 6 new `.claude/hooks/*` scaffolded (ADOPT-04); pre-existing `.claude/skills/git/SKILL.md` sha256 byte-unchanged (ADOPT-04 never-overwrite); report prints `CLAUDE.md: 21 → 21 lines (cap 100)` (ADOPT-06) and `Audit: before rc=0 → after rc=0` (ADOPT-05). |
| 3 | dirty-tree exits 2 with a clear message; `--force` proceeds + logs WARN in RESTRUCTURE-LOG.md | ✓ VERIFIED | Spot-check on git-init'd sandbox with an untracked file: no-`--force` rc=2; `--force` rc=0; `grep 'WARN.*uncommitted'` matches in RESTRUCTURE-LOG.md. Code: precondition_git uses `git status --porcelain` (Pitfall 5, catches tracked+untracked), exit 2 / log_step WARN (adopt.sh:156-173). SAFE-06 honored. |
| 4 | `--rollback` restores every mutated file (sha256 matches before-run); `[ROLLBACK]` entry in RESTRUCTURE-LOG.md | ✓ VERIFIED | Spot-check: live adopt → `--rollback` yields `diff -r` zero-diff (excl. conjure dirs, D-03); `[ROLLBACK]` entry present; log trail reads `[SNAPSHOT] [INVENTORY] [SCAFFOLD] [AUDIT] [ROLLBACK]` (WR-03 fix confirmed — forward-run audit log preserved across the whole-tree restore). Code: rollback_path 3-step restore→delete-created→sha256-verify (adopt.sh:260-359). SAFE-02 / D-01 / D-04 honored. |
| 5 | SIGKILL mid-run + re-run detects partial `.conjure-adopt-state` and offers `[r]/[c]/[s]` (non-TTY: exit 2 + "last completed" message) | ✓ VERIFIED (automated half) / human_needed (TTY half) | Spot-check (seeded partial state, `< /dev/null`): rc=2; stderr contains `last completed:` + all three flags `--rollback`/`--resume`/`--start-fresh` (D-13). Test block also confirms a real background launch + bounded-poll + `kill -9` exercise (run.sh:2701-2747). Code: mode-dispatch non-TTY guard (adopt.sh:803-813) + recovery_prompt /dev/tty loop (adopt.sh:367-380). The interactive `[r]/[c]/[s]` prompt reads from /dev/tty and is deferred to manual verification (see human_verification). |

**Score:** 5/5 truths verified (the automated, programmatically-checkable portion of every criterion is green; only the interactive TTY prompt of criterion 5 needs a human).

### Required Artifacts

| Artifact | Expected | Status | Details |
| -------- | -------- | ------ | ------- |
| `scripts/adopt.sh` | 5-step pipeline + state schema + trap + dirty-tree gate + dry-run temp manifest + Pitfall-3 guard + rollback + recovery + apply-step/update-manifest (min_lines 150/250) | ✓ VERIFIED | 816 lines, substantive. All mode-dispatch branches filled (rollback_path, resume_pipeline, recovery_prompt, apply_step, update_manifest). shellcheck-clean under the CI gate. Zero non-comment `exit 1`. |
| `cli/conjure` (cmd_adopt) | thin dispatcher: 8 flags → CONJURE_ADOPT_* env → exec adopt.sh; dispatch router entry; usage line | ✓ VERIFIED | cmd_adopt at line 193 (thin wrapper, zero business logic), `adopt)` dispatch at line 498, usage line at 40. Mirrors cmd_resolve/cmd_audit. |
| `lib/inventory.sh` | `--full-inventory` cap-lift via `CONJURE_INVENTORY_MAX` (default 500, Phase 21 unchanged) | ✓ VERIFIED | `CONJURE_INVENTORY_MAX="${CONJURE_INVENTORY_MAX:-500}"` (line 16); `head -n "${scan_max}"` (line 205); hint message references the var (line 436). Phase 21 inventory tests stay green. |
| `lib/mutate.sh` (mutate_write_file) | byte-exact `cp` chokepoint, DRY_RUN-aware (CR-01 fix) | ✓ VERIFIED | mutate_write_file at line 76: byte-exact `cp`, DRY_RUN branch, counter increment. Replaces lossy `mutate_write "$(cat src)"`. |
| `tests/fixtures/_adopt-restructure-steps/adopt-manifest.json` | synthetic restructure_steps[] (1 write + 1 archive op), schema-valid | ✓ VERIFIED | `jq` confirms schema_version + summary + files + exactly 2 ops (write, archive). NOTE: shipped at `_adopt-restructure-steps` (underscore-prefixed); the PLAN frontmatter said `adopt-restructure-steps` — benign rename, the test block references the actual shipped path consistently. |
| `tests/run.sh` Phase 22 block | inline test block covering all 5 criteria + SAFE-04/07 + D-08 + Pitfall 3 | ✓ VERIFIED | 10 `▸ Phase 22` sub-section headers; 41 passing assertions, 0 failing. Uses existing `t`/`pass`/`fail` helpers and the Phase 21 sandbox pattern. |

### Key Link Verification

| From | To | Via | Status | Details |
| ---- | --- | --- | ------ | ------- |
| cli/conjure cmd_adopt | scripts/adopt.sh | env-var pass + `bash exec` | ✓ WIRED | `bash "$CONJURE_HOME/scripts/adopt.sh" "$target"` (cli/conjure:220) with full CONJURE_ADOPT_* contract. |
| scripts/adopt.sh | snapshot_create | raw cp -a snapshot (snapshot_guarded) | ✓ WIRED | `snapshot_create` called in snapshot_guarded (adopt.sh:190,202); not routed through mutate_cp. |
| scripts/adopt.sh | inventory_emit_manifest | dry-run mktemp temp path (D-11) | ✓ WIRED | adopt.sh:705,710. Dry-run path uses `DRY_RUN=0 inventory_emit_manifest` into mktemp. |
| scripts/adopt.sh | init-project.sh | idempotent scaffold subprocess (ADOPT-04) | ✓ WIRED | `bash "$CONJURE_HOME/scripts/init-project.sh" existing "$TARGET"` (adopt.sh:734). |
| scripts/adopt.sh | audit-setup.sh | audit subprocess, capture rc, no abort (ADOPT-05) | ✓ WIRED | Before+after rc captured (adopt.sh:669,775); never aborts. |
| rollback_path | snapshot_rollback | whole-tree restore → delete created[] → sha256-verify | ✓ WIRED | `snapshot_rollback "$snap" "$TARGET"` (adopt.sh:298) + created[] mutate_rm + mutated[] sha verify. |
| apply_step | lib/mutate.sh | op dispatch: write→mutate_write_file, archive→mutate_archive (RESTR-02 chokepoint) | ✓ WIRED | mutate_write_file (adopt.sh:555), mutate_archive (adopt.sh:582). Every target mutation routes through the chokepoint. |
| recovery prompt | /dev/tty | interactive read; non-TTY → exit 2 (D-13) | ✓ WIRED | recovery_prompt reads `< /dev/tty` (adopt.sh:372); non-TTY guard exits 2 with flags (adopt.sh:808-811). |

### Behavioral Spot-Checks

All run against fresh `mktemp -d` sandboxes, independent of the test harness.

| Behavior | Command (summary) | Result | Status |
| -------- | ----------------- | ------ | ------ |
| Dry-run zero writes + 5-step plan + temp manifest | `DRY_RUN=1 adopt.sh $sb` | 0 files under target; 5 labels; mktemp manifest path | ✓ PASS |
| Live: snapshot + manifest + 6 hooks + idempotent SKILL.md + report 21→21 + audit rc | `adopt.sh $sb` | all present, SKILL.md byte-unchanged | ✓ PASS |
| Dirty-tree exit 2 / --force rc 0 + WARN | git-init dirty sandbox | rc 2 then rc 0, WARN logged | ✓ PASS |
| Rollback zero-diff + [ROLLBACK] + full log trail | `adopt.sh` then `--rollback` | zero-diff; trail SNAPSHOT…AUDIT…ROLLBACK | ✓ PASS |
| Non-TTY partial-state recovery exit 2 + flags | seeded state, `< /dev/null` | rc 2; "last completed:" + 3 flags | ✓ PASS |
| WR-04 protected-dir denylist (write to .git/hooks) | apply-step with dest `.git/hooks/pre-commit` | rc 2; file NOT created | ✓ PASS |
| WR-05 op-allowlist on update-manifest (op:delete) | update-manifest with `op:delete` | rc 2; restructure_steps stays length 0 | ✓ PASS |
| Full test suite | `bash tests/run.sh` | PASS 401 / FAIL 0 | ✓ PASS |
| shellcheck CI gate | `shellcheck -S error -e SC2164,SC2044,SC2034,SC2155 <files>` | clean | ✓ PASS |

### Requirements Coverage

All 11 phase-22 requirement IDs are accounted for. The union of the three plans' `requirements:` frontmatter exactly equals the prompt's 11 IDs; every ID is mapped to Phase 22 with status Complete in REQUIREMENTS.md.

| Requirement | Source Plan | Description | Status | Evidence |
| ----------- | ----------- | ----------- | ------ | -------- |
| ADOPT-01 | 22-01, 22-02 | `conjure adopt` folds an existing repo into the four-layer harness | ✓ SATISFIED | Live run emits manifest + scaffolds layers (criterion 2) |
| ADOPT-02 | 22-01, 22-02 | `--dry-run` previews with zero filesystem side-effects | ✓ SATISFIED | Dry-run zero-writes spot-check (criterion 1) |
| ADOPT-04 | 22-01, 22-02 | scaffolds only missing layers, never overwrites | ✓ SATISFIED | SKILL.md byte-unchanged + 6 new hooks (criterion 2) |
| ADOPT-05 | 22-01, 22-02 | runs the audit and reports health before/after | ✓ SATISFIED | `Audit: before rc=0 → after rc=0` report line |
| ADOPT-06 | 22-01, 22-02 | adoption report with before/after CLAUDE.md line-count delta | ✓ SATISFIED | `CLAUDE.md: 21 → 21` + inventory/scaffold/archive counts |
| SAFE-01 | 22-01, 22-02 | full timestamped snapshot before first mutation | ✓ SATISFIED | `.conjure-adopt-backups/*/CLAUDE.md` snapshot |
| SAFE-02 | 22-01, 22-03 | `--rollback` restores; sha256 after == before | ✓ SATISFIED | Zero-diff rollback spot-check (criterion 4) |
| SAFE-04 | 22-01, 22-02 | step-completion manifest (path + sha256 before/after) | ✓ SATISFIED | state.json `.mutated[].before` present; atomic temp+mv writes |
| SAFE-05 | 22-01, 22-03 | traps INT/TERM → exit 2; offers rollback/continue/start-fresh on restart | ✓ SATISFIED (automated) / human_needed (TTY prompt) | trap INT/TERM (adopt.sh:60); non-TTY exit 2 + flags verified; TTY prompt deferred to manual |
| SAFE-06 | 22-01, 22-02, 22-03 | snapshot records git state; warns rollback is filesystem, not git | ✓ SATISFIED | snapshot_create captures git_head/stash; WARN at force + rollback time (D-15) |
| SAFE-07 | 22-01, 22-02, 22-03 | every step appends to RESTRUCTURE-LOG.md (survives mid-run kill) | ✓ SATISFIED | SNAPSHOT/INVENTORY/SCAFFOLD/AUDIT/ROLLBACK entries in order; preserved across rollback (WR-03) |

No orphaned requirements. ADOPT-03 (dirty-tree refusal) is traced to **Phase 21** in REQUIREMENTS.md and is NOT in this phase's declared scope, though its behavior is surfaced and exercised by the Phase 22 dirty-tree gate (criterion 3) — informational only, not a gap.

### Code Review Closure (22-REVIEW / 22-REVIEW-FIX)

A standard-depth review found 11 issues (2 critical, 5 warning, 4 info); 8 in-scope (CR-01, CR-02, WR-01..05, IN-03) were fixed. Every fix is confirmed present in the shipped code AND in git history:

| Finding | Fix verified in code | Commit (present) |
| ------- | -------------------- | ---------------- |
| CR-01 (write op strips trailing newline) | mutate_write_file byte-exact cp (mutate.sh:76); used at adopt.sh:555; test asserts `cmp -s` byte-match + recorded after-sha | fcc42a6 ✓ |
| CR-02 (extract archives new src, not old dest) | apply_archive_op takes src as $1; extract archives OLD dest first (adopt.sh:591-600); isolated extract test green | fcc42a6 ✓ |
| WR-01 (mutate before state record) | state_add_mutated/created recorded BEFORE mutate_write_file; state_set_last_mutated_after finalizes (adopt.sh:538-558) | fcc42a6 ✓ |
| WR-02 (resume re-runs dirty-tree gate) | gate skipped when CONJURE_ADOPT_REUSE_SNAPSHOT=1 (adopt.sh:640-644) | 7042f30 ✓ |
| WR-03 (rollback truncates audit log) | live log preserved aside + restored over stale snapshot copy (adopt.sh:288-309); spot-check trail SNAPSHOT…AUDIT…ROLLBACK | c24cadb ✓ |
| WR-04 (apply-step dest can clobber .git/backups) | protected-dir denylist case-match exit 2 (adopt.sh:532-537); spot-check `.git/hooks` write → rc 2, not created | fcc42a6 ✓ |
| WR-05 (update-manifest no op-allowlist) | inbound jq predicate asserts op ∈ {write,archive,extract} (adopt.sh:435-440); spot-check `op:delete` → rc 2 | 601642c ✓ |
| IN-03 (extract untested) + CR-01 test strengthening | isolated extract test + cmp -s byte-match assertions (run.sh:2808-2858, 2777-2795) | 2c8e7a9 ✓ |

Out-of-scope (not fixed, by directive): IN-01, IN-02, IN-04 — all pre-existing or optional hardening, documented in 22-REVIEW-FIX.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
| ---- | ---- | ------- | -------- | ------ |
| tests/run.sh | 1906, 2268 | `mktemp -t tmp.XXXXXX.md` | ℹ️ Info (false positive) | `XXX` is mktemp's required template-placeholder syntax in the Phase 21 block, not a debt marker. No action. |

No unreferenced TBD/FIXME/XXX debt markers in any Phase 22-modified file. No stubs, no empty implementations, no hardcoded-empty-data anti-patterns. Zero non-comment `exit 1` in adopt.sh (project convention honored).

### Human Verification Required

#### 1. Interactive TTY recovery prompt (`[r]/[c]/[s]`)

**Test:** Run `conjure adopt` on a brownfield repo in a real terminal, `kill -9` it mid-run (after the snapshot step lands), then re-run `conjure adopt` interactively. Confirm the `[r]ollback / [c]ontinue / [s]tart-fresh` prompt appears and each choice behaves: `r` restores (zero-diff), `c` resumes at the first incomplete step reusing the existing snapshot (no second backup dir), `s` discards state and starts fresh; empty/unknown input re-prompts with no default.
**Expected:** The `recovery_prompt()` loop reads from `/dev/tty`; each choice routes to rollback_path / resume_pipeline / start-fresh respectively; empty/unknown re-prompts (D-14).
**Why human:** The prompt reads from `/dev/tty` (adopt.sh:372), which cannot be driven by the non-interactive harness. The non-TTY exit-2 branch IS fully automated and green; only the interactive branch needs a human. This was explicitly deferred to manual verification by the planner (22-03-PLAN verification section + 22-VALIDATION manual table) — it is a planned deferral, not a gap.

### Gaps Summary

No gaps. All five ROADMAP success criteria are achieved in the shipped code and independently verified by fresh-sandbox behavioral spot-checks (not merely by SUMMARY claims or the test harness). The full suite is green (PASS 401 / FAIL 0), shellcheck-clean under the CI gate, all 11 requirement IDs satisfied, all 8 in-scope review findings fixed and confirmed present in both code and git history.

The status is `human_needed` (not `passed`) solely because the interactive TTY recovery prompt for criterion 5 requires a human at a real terminal — a deliberate, planner-documented deferral. Every programmatically-checkable behavior passes.

---

_Verified: 2026-05-28T21:59:37Z_
_Verifier: Claude (gsd-verifier)_
