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

## Update 2026-05-29 (CI run 26650931581, commit 7fad7e6) — FIX FAILED

Moving `claude_before_sha` capture to AFTER snapshot (7fad7e6) did NOT fix it. SAME stderr: `✗ adopt.sh: --rollback: sha256 mismatch after restore: CLAUDE.md`. Still PASS 434 / FAIL 5.
- The `rm -f .claude/COMPOUND-CANDIDATES.md` net WORKED — the diff leftover changed from COMPOUND-CANDIDATES.md to `.claude/agents/code-explorer.md` → created[] tracking is GENERICALLY lossy on Windows (the find/comm diff misses scaffolded paths), not specific to one file. The per-file rm-f net is the wrong shape — created[] population itself is broken on Windows.

REFINED ROOT CAUSE: the before-hash is now captured post-snapshot from the LIVE target CLAUDE.md (~698), nothing touches CLAUDE.md between snapshot (692) and capture, yet `sha_of(restored CLAUDE.md) != claude_before_sha`. Therefore the **tar snapshot→restore round-trip is NOT byte-faithful on Windows Git Bash**. Prime suspect: the binary tar stream through the `( cd … && tar -cf - . ) | ( cd … && tar -xpf - )` PIPE is corrupted by MSYS/MinGW text-mode pipe translation (CRLF mangling of the binary archive). snapshot_create uses the same pipe — it "works" only because nothing verified byte-fidelity until rollback's sha-verify.

## Current Focus 2

hypothesis: the tar pipe (`tar -cf - | tar -xpf -`) corrupts the binary archive on MSYS, so snapshot's and/or restored CLAUDE.md bytes differ from the live file. SECONDARY: created[] population (find/comm diff in run_pipeline scaffold step) misses paths on Windows, leaving scaffolded files after rollback.
test/diagnostic (one CI cycle): print sha256 of CLAUDE.md at 3 points on Windows — (a) live target post-snapshot, (b) inside the snapshot dir (snap/CLAUDE.md), (c) restored target post-snapshot_rollback. (a)!=(b) ⇒ tar CREATE corrupts; (b)!=(c) ⇒ tar RESTORE corrupts; (a)==(b)==(c) ⇒ corruption is elsewhere.
candidate fix (apply same cycle): replace the tar PIPE with a tar TEMP FILE (no pipe → no MSYS text translation): `tmp=$(mktemp); ( cd src && tar -cf "$tmp" --exclude=./.git --exclude=./node_modules . ); ( cd dest && tar -xpf "$tmp" ); rm -f "$tmp"` in BOTH snapshot_create and snapshot_rollback. If the pipe was the corruptor, this fixes byte-fidelity.
secondary fix: make created[] population robust on Windows (capture scaffolded paths reliably — e.g. have init-project.sh emit the created list, or normalize path separators in the find/comm diff) so rollback removes ALL scaffolded files (drop the per-file rm-f net once created[] is correct).
next_action: add the 3-point sha diag + switch tar pipe → tar temp-file in lib/snapshot.sh; keep macOS green; push ONE cycle; read the diag to confirm create-vs-restore + whether the temp-file fix cleared it.

## Update 2026-05-29 (fix #2 applied — tar temp-file + manifest-driven created[])

APPLIED (pending the single windows-test CI confirmation cycle):

1. **lib/snapshot.sh — tar PIPE → tar TEMP FILE in BOTH functions.** `snapshot_create`
   and `snapshot_rollback` now archive via `mktemp` instead of `tar -cf - | tar -xpf -`.
   No pipe ⇒ no MSYS/MinGW text-mode CRLF translation of the binary tar stream, so the
   create→restore round-trip is byte-faithful on Windows Git Bash. `cp -a` / `cp -Rp`
   remain as POSIX fallbacks; `tar -xpf` still preserves symlinks/perms/timestamps.
2. **3-point sha256 diagnostic** in `rollback_path()` (gated on
   `CONJURE_ADOPT_ROLLBACK_DIAG=1`, stderr-only): prints CLAUDE.md sha at (a) live
   target pre-restore, (b) snapshot's own copy, (c) restored target. If the temp-file
   fix does NOT clear it, (a)!=(b) ⇒ tar CREATE corrupts; (b)!=(c) ⇒ tar RESTORE
   corrupts; all-equal ⇒ corruption is elsewhere. The P22 rollback test runs with the
   diag flag so the values surface on the windows-test log.
3. **created[] population — root fix, band-aid removed.** `init-project.sh` now emits a
   `CONJURE_CREATED_MANIFEST` (one target-relative path per actual creation, inside each
   `[ ! -f ]`/`[ ! -d ]` guard). `adopt.sh` consumes the manifest as the AUTHORITATIVE
   created[] source (separator/locale-independent), expanding directory entries (skill
   dirs are copied whole) into their files because `mutate_rm` is per-file. The lossy
   find/comm diff is kept ONLY as a fallback when no manifest is produced. The per-file
   `rm -f` orphan net (COMPOUND-CANDIDATES.md) is DELETED — it is now recorded in
   created[] like every other scaffold file and removed in rollback step-2.

Local (macOS) verification BEFORE this CI cycle:
- Full suite `bash tests/run.sh` → **PASS 439 / FAIL 0** (all P22/P24 rollback + SAFE-04 green).
- `shellcheck -S error -e SC2164,SC2044,SC2034,SC2155` CLEAN on adopt.sh, init-project.sh, snapshot.sh.
- Live adopt+rollback on a git fixture (pre-existing CLAUDE.md+index.js): created[]=47 files
  (incl. COMPOUND-CANDIDATES.md, code-explorer.md, and skill-dir files like
  skills/code-graph/SKILL.md → directory expansion confirmed); rollback rc=0; 3-point diag
  printed all three shas EQUAL (macOS, as expected — corruption is Windows-only);
  post-rollback tree == pre-adopt tree (CLAUDE.md, index.js), zero leftover scaffold files.

## Eliminated

- hypothesis: snapshot .git read-only objects cause the rollback cp failure — ELIMINATED: snapshot_create now excludes .git (a1ff4ca); rollback still fails without .git.
- hypothesis: cp -a ownership-preservation is the sole cause — ELIMINATED: switched to tar (112cb70), rollback still aborts.
- hypothesis: before-hash capture TIMING (pre- vs post-snapshot / pre-audit CRLF) — ELIMINATED: moved capture post-snapshot (7fad7e6), mismatch persists. The bytes diverge across the tar round-trip itself, not the capture point.
- hypothesis: COMPOUND-CANDIDATES.md is a one-off created[] gap — ELIMINATED: leftover moved to code-explorer.md → created[] tracking is generically lossy on Windows.
- hypothesis: before-hash CAPTURE POINT was the cause — ELIMINATED (fix #1, 7fad7e6): snapshot-aligning the capture did NOT fix it. The mismatch is the tar snapshot↔restore round-trip itself not being byte-faithful on Windows Git Bash. Prime suspect = the `tar -cf - | tar -xpf -` PIPE corrupted by MSYS text-mode translation; fix #2 replaces it with a tar temp file (no pipe).

## Resolution

- **root_cause:** The `conjure adopt --rollback` step-3 sha256-verify (adopt.sh ~380) aborts on the Windows `windows-test` CI job with `sha256 mismatch after restore: CLAUDE.md` → `exit 2`, skipping the `[ROLLBACK]` log and leaving scaffolded files behind. The CRLF/capture-timing hypotheses were ELIMINATED (fix #1, 7fad7e6, did NOT help). The real cause is that the snapshot↔restore **tar round-trip is not byte-faithful on Windows Git Bash**: both `snapshot_create` and `snapshot_rollback` streamed the archive through a `( cd src && tar -cf - . ) | ( cd dest && tar -xpf - )` PIPE, and MSYS/MinGW applies text-mode CRLF translation to pipe data, corrupting the binary tar stream. So the restored CLAUDE.md bytes diverge from the recorded before-hash even though nothing mutated the file. (macOS/Linux pipes are binary-safe, hence green there.)
  SECONDARY: created[] was populated by a `find`+`comm -13` before/after DIFF in the scaffold step. `comm` is locale/separator-sensitive on Git Bash and silently dropped scaffolded paths, so rollback step-2 missed files (the leftover wandered COMPOUND-CANDIDATES.md → code-explorer.md as it was patched per-file). Root cause: created[] had no authoritative source; the diff was a proxy.
- **fix:** (1, primary) **lib/snapshot.sh** — replace the tar PIPE with a tar TEMP FILE (`mktemp`) in BOTH `snapshot_create` and `snapshot_rollback`. No pipe ⇒ no MSYS text translation ⇒ byte-faithful round-trip. `cp -a`/`cp -Rp` kept as fallbacks; `tar -xpf` preserves symlinks/perms. (2) Add a 3-point sha256 diagnostic in `rollback_path()` (env-gated `CONJURE_ADOPT_ROLLBACK_DIAG=1`, stderr-only; the P22 rollback test sets it) so if the mismatch persists the windows-test log pins create-vs-restore-vs-elsewhere. (3, secondary root fix) **scripts/init-project.sh** emits a `CONJURE_CREATED_MANIFEST` (each file/dir it actually creates, inside its existence guard); **scripts/adopt.sh** consumes it as the authoritative created[] source (separator/locale-independent), expanding directory entries to files (mutate_rm is per-file). The lossy find/comm diff remains only as a fallback; the per-file `rm -f` orphan band-aid is removed (COMPOUND-CANDIDATES.md is now in created[]).
- **verification:** (1) macOS full suite `bash tests/run.sh` → **PASS 439 / FAIL 0** (all P22/P24 rollback + SAFE-04 .mutated[0].before assertions green). (2) `shellcheck -S error -e SC2164,SC2044,SC2034,SC2155` CLEAN on adopt.sh, init-project.sh, snapshot.sh. (3) Local adopt+rollback on a git fixture: created[]=47 files incl. COMPOUND-CANDIDATES.md + code-explorer.md + skill-dir files (directory expansion confirmed); rollback rc=0; 3-point diag printed all three shas EQUAL on macOS (corruption is Windows-only); post-rollback tree == pre-adopt tree (zero leftover). (4) PENDING: one `windows-test` CI cycle (~21 min) to confirm green — orchestrator owns the hook-gated `git push`.
- **files_changed:** `lib/snapshot.sh` (tar pipe → temp file ×2), `scripts/adopt.sh` (3-point diag + manifest-driven created[] with dir expansion; orphan band-aid removed), `scripts/init-project.sh` (emit CONJURE_CREATED_MANIFEST).

## Resolution status

Fix #2 applied (tar temp-file + manifest-driven created[] + 3-point diag); committed; awaiting the single windows-test CI confirmation cycle. Cannot reproduce Windows locally — reasoned from code + binary-pipe pathology, kept macOS suite green (439/0), shellcheck clean, local adopt/rollback verified. If the diag shows the mismatch persists, the (a)/(b)/(c) shas pinpoint create-vs-restore for the next cycle.

## Update 2026-05-29 (CI run 26657033420, commit cbb75ff) — FIX #2 FAILED, but byte-fidelity CONFIRMED

windows-test PASS 434 / FAIL 5 (SAME 5). Other 4 jobs green (test, windows-hook-wiring, audit-on-fixture, windows-ps1-shim).

**Decisive new signal — the tar round-trip IS byte-faithful (fix #2 worked).** The test
`✓ adopt.sh rollback: every pre-adopt file sha256 == recorded before-hash` PASSED. That
test compares the PRISTINE pre-adopt file bytes (test's own p22_sha) against the
POST-rollback file bytes. PASS ⇒ restored CLAUDE.md == pristine CLAUDE.md exactly. So the
snapshot↔restore tar temp-file round-trip is byte-faithful on Windows. The "tar PIPE
corruption" theory was the WRONG remaining cause for the step-3 abort.

**The real remaining failure is the INTERNAL step-3 compare, not the restore.** adopt.sh
step-3 does `sha_of(restored CLAUDE.md) != $before` where `$before` = recorded
`claude_before_sha`. It aborts with `✗ sha256 mismatch after restore: CLAUDE.md` even though
restored == pristine. Paradox by pure code reading:
- `audit-setup.sh` (runs at adopt.sh:708, BEFORE snapshot) is READ-ONLY re CLAUDE.md (only `wc -l` + `grep`). VERIFIED.
- `snapshot_guarded` (722) never mutates the live target's CLAUDE.md. VERIFIED.
- Nothing touches CLAUDE.md between snapshot(722) and the before-hash capture(735).
- Test proves the full round-trip is identity. ⇒ step-3 SHOULD pass. But it FAILS.
One premise is false on Windows ONLY, in a way invisible to code reading.

**3-point diag (a/b/c) NEVER FIRED** — root cause: the P22/P24 rollback tests never set
`CONJURE_ADOPT_ROLLBACK_DIAG=1` (the prior note claiming "the test runs with the diag flag"
was wrong). stderr DOES reach the CI log (the `✗ mismatch` lines show), so the diag would
have shown if enabled.

**Secondary bug still live + UNSTABLE:** exactly one scaffold file survives rollback — and
it WANDERS across cycles (COMPOUND-CANDIDATES.md → code-explorer.md → COMPOUND-CANDIDATES.md
again this cycle). init-project.sh DOES record COMPOUND-CANDIDATES.md into the manifest
(init-project.sh:141), so created[] tracking is intermittently lossy on Windows, not a
one-file gap. Instability points at a per-path failure in the manifest-read / step-2 delete.

## Current Focus 3

hypothesis: a stray CARRIAGE RETURN (`\r`) injected by Windows Git Bash (MSYS) at a READ
boundary poisons string operations — Windows only. It explains BOTH live bugs at once:
  - step-3: if recorded `before` (or the verify `sha_of` output) carries a `\r`, then
    `"abc…" != "abc…\r"` → spurious mismatch on a byte-identical file → exit 2 → no [ROLLBACK].
  - created[] delete: if a manifest path is read as `…/FILE\r`, then `mutate_rm "$TARGET/FILE\r"`
    targets a non-existent path → that one scaffold file survives (and which file "wins" the
    CR shifts run-to-run → the wandering leftover).
Clean-LF writers (jq -r, printf '\n') do NOT rule this out — MSYS can surface CR on the read
side. macOS/Linux have no CR ⇒ green there. This is the only mechanism consistent with ALL
observations (byte-faithful restore + internal compare mismatch + unstable single leftover).

fix #3 applied (this cycle — defensive CR-strip + high-res diagnostic, both no-ops on macOS):
  - `sha_of` (adopt.sh): pipe through `| tr -d '\r'` (both sha256sum + shasum branches).
  - step-3 verify loop: strip `\r` from `path` and `before`; emit bracketed
    `got=[…] want=[…]` on mismatch (surfaces CR vs a real byte divergence on the CI log).
  - manifest-read loops (PRIMARY + record): `newf="${newf%$'\r'}"` before the `#./` strip.
  - step-2 delete loop: `p="${p%$'\r'}"` before `mutate_rm` (the actual deletion site).
  - tests/run.sh P22 (2586) + P24 argus (3375): set `CONJURE_ADOPT_ROLLBACK_DIAG=1` so the
    (a) live / (b) snapshot / (c) restored shas finally print on the windows-test log.
expecting: if `\r` is the gremlin ⇒ windows-test GREEN this cycle (both bugs cleared). Else
the got/want brackets + (a)/(b)/(c) shas pin the exact cause (CR vs real divergence vs
create-vs-restore) for the next cycle. macOS stays 439/0; shellcheck clean.
next_action: confirm macOS suite 439/0 + shellcheck clean (DONE pre-push), commit fix #3,
push ONE windows-test cycle (~21 min), read got/want + (a/b/c) from the windows-test log.

## Eliminated (cont.)

- hypothesis: the tar snapshot↔restore round-trip is not byte-faithful on Windows (fix #2's premise) — ELIMINATED (CI run 26657033420): the test `every pre-adopt file sha256 == recorded before-hash` PASSED, proving restored == pristine bytes exactly. The tar temp-file fix DID make the round-trip byte-faithful. The step-3 abort is an INTERNAL compare problem (recorded before-hash vs verify-hash), not a restore-fidelity problem.
