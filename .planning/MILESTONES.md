# Milestones

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
