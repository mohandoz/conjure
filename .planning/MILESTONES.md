# Milestones

## v0.6.0 Safe Brownfield Adoption (Shipped: 2026-05-29)

**Phases completed:** 4 phases, 12 plans, 25 tasks

**Key accomplishments:**

- Graceful-red `▸ Phase 22` test block (9 sections) in tests/run.sh plus a synthetic 2-op restructure_steps[] manifest fixture — the executable red→green contract that gates every later Phase 22 verification before scripts/adopt.sh exists.
- `conjure adopt` command surface + the forward 5-step pipeline (preconditions → snapshot → inventory → scaffold → audit → report) with crash-durable atomic state, an INT/TERM trap, a `git status --porcelain` dirty-tree gate, dry-run zero-writes via a mktemp temp manifest, and a snapshot-outside-target self-copy guard.
- Filled the four Wave 2 mode-dispatch stubs in `scripts/adopt.sh`: the D-01 3-step rollback (snapshot restore → delete created[] → sha256-verify) that yields Phase 24 zero-diff, the [r]/[c]/[s] partial-run recovery prompt + `--resume` snapshot-reuse, and the `--apply-step`/`--update-manifest` op-executor (the Phase 23 skill seam) with op-allowlist + staging-path + traversal validation.
- Graceful-red `▸ Phase 23 — restructure gate helpers` block in tests/run.sh plus 8 canonical-token gate fixtures, locking the Nyquist contract so every Wave 1/2 deliverable verifies against a red→green signal that already exists.
- Four deterministic bash gate helpers (verify-invariants = GATE A, audit-staged = GATE B, extract-invariants pre-pass, decision-scan archive guard) that block invalid LLM restructure proposals — dropped invariants, @imports, cap breaches, undocumented-decision archives — before any human approval, flipping all 12 Wave 0 gate-helper assertions green (406→418 PASS).
- The thin `[Read, Bash]` restructure SKILL.md (110 lines), the per-class `/dev/tty` approve/skip/edit approval driver (non-TTY → exit 2, one RESTRUCTURE summary line per bucket), and the one-token init-project.sh scaffold edit — flipping the last 4 Wave 0 graceful-reds green (scaffold/criterion-1, archive-last, non-TTY approval, bulk summary) and closing Phase 23 at 427 PASS / 0 FAIL.
- A `_brownfield-argus` generator that materializes 509 `.md` + a real `ln -s` symlink + a 127-line oversized CLAUDE.md + an `@import` seed into any target dir, plus a 1-line additive `report()` deviation so an idempotent adopt re-run emits the literal ROADMAP phrase "nothing to scaffold" — full suite stays PASS 429/0.
- The `▸ Phase 24` block in `tests/run.sh` — five criterion sections (C1–C5) that

drive the shipped `conjure adopt` + restructure-gate pipeline against the 500-file
`_brownfield-argus` fixture and assert all five v0.6.0 ROADMAP success criteria
end-to-end: <30s dry-run + zero writes, rollback zero-diff (per-file sha256 +
`diff -r`), idempotent re-run ("nothing to scaffold"), SIGKILL-after-snapshot
recovery (non-TTY exit 2 + auto-rollback zero-diff via a 3-attempt anti-flake
relaunch loop), and symlink-skip + @import pre-write block — taking the full suite
from PASS 429 to PASS 447, FAIL 0, shellcheck-clean.

---

## v0.5.0 Auto-Update + Healthcheck (Shipped: 2026-05-28)

**Phases completed:** 5 phases, 10 plans
**Timeline:** 2026-05-26 → 2026-05-28 | 49 commits
**Requirements:** 11/11 satisfied

**Delivered:** Closed the harness lifecycle loop — installed harnesses can now detect drift, resolve conflicts interactively, and open update PRs, with a native Windows entrypoint and a hardened release gate.

**Key accomplishments:**

- Drift Detection (DRIFT-01/02): `conjure check` — sha256-based 3-way drift classifier (modified/removed/added) over a 35-entry kit manifest, `--porcelain` output for CI, cross-platform sha256 fallback (bash 3.2 compatible)
- Conflict Resolution (RESOLVE-01/02): `conjure resolve` — interactive diff3 sidecar walker with fd-3 stdin isolation, non-TTY guard exiting 2, and DRY_RUN-safe `mutate_rm` cleanup
- Auto-PR (AUTPR-01/02): `conjure update --pr` and `--cron` — gh prerequisite guard, zero-drift guard, deterministic branch naming, idempotency via `gh pr list`, and a weekly cron workflow template
- Windows entrypoint (WIN-01/02): `conjure.ps1` shim (Git Bash → WSL → exit 2) with `$LASTEXITCODE` propagation, plus a `windows-ps1-shim` pwsh CI job asserting exit-code passthrough
- Prerequisites + tech debt (INFRA-01, DEBT-01/02): dry-run-safe `mutate_rm` primitive, `publish-skill` positional `$2` (TARGET_REPO deprecated), and a `release.yml` ci-gate empty-check guard with API-propagation retry loop

**Post-close hardening:** cross-platform test suite repaired after the milestone shipped — gh-isolation under usrmerge, Git Bash sandbox PATH (git/jq/python3), telemetry cwd via `cygpath -m`, and pwsh exit propagation; all 5 CI jobs green. Homebrew formula bumped to the v0.5.0 tag with a real sha256.

---

## v0.4.0 Distribution + Ecosystem (Shipped: 2026-05-26)

**Phases completed:** 9 phases, 23 plans
**Timeline:** 2026-05-25 → 2026-05-26 | 136 commits | 197 files changed

**Key accomplishments:**

- Nyquist backfill: 6 VALIDATION.md files for phases 01, 02, 04, 05, 06, 07 with executable verify blocks (TECH-02a–f)
- 3-Way Merge: `conjure update --apply` uses real `git merge-file --diff3`; conflict sidecars + base snapshot at init (MERGE-01–05)
- Marketplace Publish: `conjure publish` + CI version-consistency + `claude plugin validate` in CI (MKTPL-01–04)
- Skill Publishing: `conjure publish-skill` with 4-gate validation (schema, size, egress, SHA-pin) + PR flow (SKILL-01–04)
- Org Overlay: `conjure init --overlay` + `conjure refresh-overlay` + audit drift reporting; credential-safe (OVLY-01–05)
- Homebrew Tap: formula + `mislav/bump-homebrew-formula-action@v3` wired in release pipeline (BREW-01–04)
- Docker + Windows CI: multi-arch Dockerfile (debian:bookworm-slim, non-root) + docker.yml + windows-test CI job (DOCK-01–05, TECH-03)
- Release Pipeline: 4-job release.yml — ci-gate → release → docker + homebrew (parallel, independent) (REL-01–02)

**Known deferred items at close:** 9 (see .planning/STATE.md Deferred Items)

---
