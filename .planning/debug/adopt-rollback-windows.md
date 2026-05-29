---
slug: adopt-rollback-windows
status: fix_applied_pending_ci
trigger: "conjure adopt --rollback aborts on native Windows Git Bash (windows-test CI). snapshot_rollback fails so scaffolded .claude files survive, no [ROLLBACK] log entry, post-rollback diff non-empty. 5 remaining CI failures (adopt rollback x3 + argus rollback x2). macOS/Linux green at 439/0."
created: 2026-05-29
updated: 2026-05-29
---

# Debug: adopt --rollback aborts on native Windows Git Bash

## Symptoms

- **Expected:** `conjure adopt --rollback <target>` restores the snapshot, deletes scaffolded `created[]` files, verifies sha256 of mutated files, logs a `[ROLLBACK]` entry, exits 0. Post-rollback `diff -r` (excl. conjure dirs) is empty. Works on macOS + Linux (suite 439/0).
- **Actual (native Windows Git Bash, CI job `windows-test` only):** rollback aborts. `.claude/hooks` scaffolded files survive, RESTRUCTURE-LOG.md has no `[ROLLBACK]` entry, post-rollback diff non-empty.
- **5 failing assertions:** adopt rollback (scaffolded-present, no-[ROLLBACK]-log, diff-not-empty `Only in .../.claude: COMPOUND-CANDIDATES.md`) + argus rollback (no-[ROLLBACK]-log, diff-not-empty `Only in <target>: .claude`).
- **Timeline:** Introduced by v0.6.0 (Phase 21-24, snapshot/adopt are new). Surfaced only on Windows CI — the milestone audit + local verification were macOS-only.
- **Repro:** Windows Git Bash CI `windows-test` job (`bash --noprofile --norc -e -o pipefail`). NOT reproducible on macOS/Linux. Each CI cycle ~21 min (windows-test is the long pole).

## Already fixed (11 Windows failures → 5)

- `snapshot_create` (lib/snapshot.sh): `cp -a` → `tar --exclude=.git --exclude=node_modules` (commit a1ff4ca).
- `snapshot_rollback` (lib/snapshot.sh): `cp -a snapshot/. target/` → `( cd snap && tar -cf - . ) | ( cd target && tar -xpf - )` with cp fallbacks (commit 112cb70). **DID NOT fix the rollback abort — still failing.**
- Perf gate: platform-aware `PERF_CEILING` (30s Unix / 240s Windows) — Git Bash fork overhead (112cb70).
- Symlink-skip tests: gate on `[ -L ]` (Windows git checks out symlinks as files) (112cb70).
- `mutate_archive` D-13 abort test: portable file-as-archive-root injection (chmod-555 ignored by Windows) (112cb70).
- `brownfield-simple` → `_brownfield-simple` (excluded from generic golden loops) (ef5642f).

## Key code

- `scripts/adopt.sh` `rollback_path()` (~280-368):
  - step1 `snapshot_rollback "$snap" "$TARGET"` (line ~307) → `exit 2` on non-zero (line ~311). NO [ROLLBACK] log if this aborts.
  - step2 created-delete loop `mutate_rm "$TARGET/$p"` (327-331) + empty-dir prune.
  - step3 sha256-verify mutated[] (350-360) → `exit 2` on mismatch.
  - `log_step ROLLBACK` (363) → only reached if steps 1-3 pass.
- `lib/snapshot.sh` `snapshot_rollback()` (~77-95): now tar -xpf, cp -a/-Rp fallback.
- Tests: `tests/run.sh:2569+` (adopt rollback, P22_RB_*), argus rollback (P24 criterion 2). Both invoke `CONJURE_ADOPT_ROLLBACK=1 bash adopt.sh --rollback`.

## Current Focus

CONFIRMED via CI diag (run 26649103286, commit 74b655d): the abort is **step 3 sha256-verify, NOT step 1**. snapshot_rollback (tar) SUCCEEDS. Exact stderr: `✗ adopt.sh: --rollback: sha256 mismatch after restore: CLAUDE.md` → `restore incomplete` → exit 2 (line 360) → no [ROLLBACK] log, created-delete already ran (so most scaffolded files removed; COMPOUND-CANDIDATES.md remains because it is gitignored / not tracked in created[] — a SECONDARY issue).

hypothesis: `claude_before_sha` is captured at adopt.sh:672 — BEFORE the pre-scaffold audit (line 678 `audit-setup.sh "$TARGET"`) and BEFORE the snapshot (line 692 `snapshot_guarded`). Line 775 records `mutated[] += {path: CLAUDE.md, before: claude_before_sha, after: claude_after_sha}` unconditionally. Rollback step3 (adopt.sh:352) verifies `sha_of(restored CLAUDE.md) == claude_before_sha`. Restored CLAUDE.md = the SNAPSHOT's copy (taken at 692, AFTER the 678 audit). If anything rewrites CLAUDE.md between 672 and 692 on Windows (prime suspect: `scripts/audit-setup.sh` normalizing CRLF→LF or rewriting CLAUDE.md; git autocrlf=true on the Windows runner makes the checked-out CLAUDE.md CRLF), then snapshot CLAUDE.md (post-audit) != claude_before_sha (pre-audit) → step3 mismatch. macOS: audit is a no-op on bytes → before == snapshot == restored → passes.
test: (1) does `scripts/audit-setup.sh` ever WRITE/normalize `$TARGET/CLAUDE.md`? grep for writes to CLAUDE.md in audit-setup.sh. (2) Is `claude_before_sha` (672, pre-snapshot) consistent with the snapshot's CLAUDE.md bytes? (3) On Windows, is the mismatch CRLF (before=CRLF original, restored=LF or vice versa)?
expecting: CLAUDE.md bytes differ between the 672 capture and the snapshot (692) on Windows only.
candidate fixes (pick the correct, minimal one after confirming the test):
  - A. Capture `claude_before_sha` to match the snapshot source-of-truth: move the before-sha capture to AFTER snapshot_guarded (or compute it from the snapshot copy), so rollback's step3 before-hash == what the snapshot actually holds. (Aligns the rollback contract: "restore to snapshot state".)
  - B. Only record CLAUDE.md in mutated[] when it was ACTUALLY mutated by an apply-step op (skill), not unconditionally at report time — basic adopt does not mutate CLAUDE.md, so the spurious mutated[] entry should not exist. (line 775 guard: `[ "$claude_after_sha" != "$claude_before_sha" ]`.)
  - C. If audit-setup.sh is rewriting CLAUDE.md (CRLF) as a side-effect, stop it from mutating CLAUDE.md (audit must be read-only).
  Preference: B (don't fabricate a mutated[] entry for an unchanged file) + verify A's timing. C only if audit genuinely writes CLAUDE.md.
next_action: grep audit-setup.sh for CLAUDE.md writes; decide between B (gate the mutated[] record on actual change) and A (snapshot-aligned before-hash); apply the minimal fix; macOS suite must stay green; push one CI cycle to confirm windows-test green.
reasoning_checkpoint: cannot reproduce locally (Windows-only). The COMPOUND-CANDIDATES.md leftover is a separate created[]-tracking gap (gitignored scaffold file not removed on rollback) — fix alongside or note. One targeted fix per CI cycle (~21 min).

## Evidence

- timestamp 2026-05-29: macOS suite 439/0; Windows windows-test PASS 434 FAIL 5 (down from FAIL 11). Linux test job green.
- timestamp 2026-05-29: post-rollback `.claude/hooks` file count > 0 on Windows (assertion "scaffolded created[] files removed" fails) → step2 created-delete did NOT run → step1 snapshot_rollback aborted (rollback_path line 311) for the argus case (whole .claude survives). adopt case leaves only COMPOUND-CANDIDATES.md (ambiguous — may be a separate created[]-tracking gap or step3 abort).
- timestamp 2026-05-29: diagnostic commit 74b655d in-flight (run 26649103286) to capture the suppressed rollback stderr.

## Eliminated

- hypothesis: snapshot .git read-only objects cause the rollback cp failure — ELIMINATED: snapshot_create now excludes .git (a1ff4ca); rollback still fails without .git in the snapshot.
- hypothesis: cp -a ownership-preservation is the sole cause — PARTIALLY ELIMINATED: switched rollback to tar -xpf (112cb70), rollback still aborts.

## Resolution

- **root_cause:** `claude_before_sha` was captured from the LIVE tree at adopt.sh:672 — BEFORE `snapshot_guarded` (line ~692). The rollback contract restores the SNAPSHOT's bytes, so step-3 sha256-verify (adopt.sh ~352) compared the restored (snapshot) CLAUDE.md against a before-hash the snapshot could not reproduce. On the Windows runner (`core.autocrlf=true`, CRLF checkout) the tar/cp snapshot↔restore round-trip diverged from the pre-snapshot reading, so step-3 raised `sha256 mismatch after restore: CLAUDE.md` → `exit 2`, skipping the `[ROLLBACK]` log. (audit-setup.sh was ELIMINATED as a CLAUDE.md writer — it only reads line-count + greps for @imports; hypothesis C dead.) The `mutated[]` entry itself is benign once the before-hash is snapshot-aligned: basic adopt does not mutate CLAUDE.md (before==after), and the SAFE-04 test at tests/run.sh:2653 requires the entry to exist — so a pure "skip the record" fix would have broken the macOS suite.
  SECONDARY: `.claude/COMPOUND-CANDIDATES.md` is a conjure-managed, gitignored scaffold artifact created by init-project.sh:117. It is normally tracked in created[] (confirmed on macOS) and deleted in rollback step-2, but on the Windows runner the find/comm diff that populates created[] can miss it, leaving it behind and breaking the zero-diff post-rollback contract.
- **fix:** (A, primary) Move the `claude_before_sha` capture to AFTER `snapshot_guarded`, so the recorded before-hash == the exact bytes the snapshot holds and `snapshot_rollback` reproduces. Step-3 then matches on every platform; the SAFE-04 `mutated[0].before` entry is still recorded (basic adopt before==after). (B, secondary belt) In rollback step-2, after the created[] delete loop, add an idempotent `rm -f` safety net for conjure-owned gitignored scaffold artifacts (`.claude/COMPOUND-CANDIDATES.md`) that are never part of a user's pre-adopt tree (snapshot is taken pre-scaffold) — removes any created[]-tracking miss before the empty-dir prune.
- **verification:** (1) `grep` confirmed audit-setup.sh never writes CLAUDE.md. (2) macOS full suite `bash tests/run.sh` → **PASS 439 / FAIL 0** (SAFE-04 .mutated[0].before + all P22/P24 rollback assertions green). (3) `shellcheck -S error -e SC2164,SC2044,SC2034,SC2155 scripts/adopt.sh` → CLEAN. (4) Local adopt+rollback (fixture with pre-existing .claude): rollback rc=0, COMPOUND removed, `[ROLLBACK]` logged, zero-diff vs pre-adopt, `mutated[0].before` recorded. (5) PENDING: one `windows-test` CI cycle (~21 min) to confirm green — orchestrator owns the `git push` (hook-gated).
- **files_changed:** `scripts/adopt.sh` (capture move + rollback step-2 orphan safety net).

## Resolution status

Fix committed; awaiting the single windows-test CI confirmation cycle. Cannot reproduce Windows locally — reasoned from code, kept macOS suite green, shellcheck clean.
