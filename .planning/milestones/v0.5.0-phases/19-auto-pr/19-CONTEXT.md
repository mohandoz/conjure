# Phase 19: Auto-PR — Context

**Date:** 2026-05-26
**Phase:** 19 of 20 — Auto-PR
**Goal:** Users can automate harness-update PRs on demand or via a scheduled GitHub Action without manual git operations

---

## Domain

`conjure update --pr` — pushes a harness-update branch and opens a GitHub PR with the drift diff as the PR body. Idempotent: if a PR already exists for the same branch, print the URL and exit 0.

Two deliverables:
1. **AUTPR-01**: `conjure update --pr` command
2. **AUTPR-02**: `.github/workflows/conjure-update.yml` cron template (written by `conjure init` or on demand)

---

## Decisions

### Branch name

- Pattern: `conjure/update-<short-hash>` where short-hash = first 7 chars of sha256 of current kit version string
- Deterministic: same kit version → same branch → idempotency check works
- Alternative considered: `conjure/update-v<version>` — rejected (version string can have special chars)

### Idempotency check (AUTPR-01)

- Run: `gh pr list --head <branch> --json url --jq '.[0].url'`
- If output is non-empty: print existing URL, exit 0
- If empty: proceed to create PR
- `gh` is a required dependency — exit 2 if not found

### PR body content

- Run `conjure check --porcelain` to get machine-readable drift lines
- Convert to a human-readable markdown diff table for the PR body
- Include header: "Harness update: drift detected by `conjure check`"

### git operations

- Checkout new branch: `git checkout -b <branch>`
- Apply drift: run `conjure update --apply` to perform the 3-way merge into the branch
- Commit: `git commit -am "conjure: update harness to v<CONJURE_VERSION>"`
- Push: `git push origin <branch>`
- PR: `gh pr create --title "conjure: update harness to v<CONJURE_VERSION>" --body "<body>"`

### Zero-drift guard

- If `conjure check` exits 0 (no drift): print "Harness is current — no PR needed" and exit 0

### cron template (AUTPR-02)

- Written to `.github/workflows/conjure-update.yml` in the target repo (or harness root)
- Template: weekly on Monday at 09:00 UTC; runs `conjure check` → `conjure update --pr` if drift
- Can be triggered by `conjure init` (add a flag or auto-include) OR by a new `conjure setup-cron` command
- **Decision**: standalone command `conjure update --cron` writes the template — simpler than modifying `conjure init` flow

### Implementation structure

- Extend `cmd_update` in `cli/conjure` to handle `--pr` and `--cron` flags
- Worker logic inline in `cmd_update` (no separate script — the git/gh operations are 20-30 lines)
- Sources: `scripts/check.sh` (via conjure check invocation)

---

## Canonical Refs

- `.planning/REQUIREMENTS.md` — AUTPR-01, AUTPR-02 definitions
- `cli/conjure` — `cmd_update` (extend with `--pr` and `--cron` flags)
- `scripts/check.sh` — `conjure check --porcelain` output format
- `tests/run.sh` — where AUTPR regression tests go
- `.planning/phases/17-drift-detection/17-CONTEXT.md` — porcelain format `<A|M|R> <path>`

---

## Code Context

### cmd_update current arg parsing
```bash
--check|--apply) action="$1" ;;
*)               target="$1" ;;
```
Add: `--pr) action="--pr" ;;` and `--cron) action="--cron" ;;`

### conjure check --porcelain invocation
```bash
CONJURE_PORCELAIN=1 CONJURE_HOME="$CONJURE_HOME" bash "$CONJURE_HOME/cli/conjure" check "$target"
```

### gh pr list idempotency check
```bash
existing=$(gh pr list --head "$branch" --state open --json url --jq '.[0].url' 2>/dev/null || true)
```

---

## Out of Scope

- Auto-merge on clean apply (REQUIREMENTS.md: "never — conflicts need human review")
- `conjure update --pr` auto-resolve before PR (future)
- Authentication setup for gh (user must have gh authenticated)

---

## Auto-Mode Note

Auto-answered in autonomous mode. Decisions follow from AUTPR-01/02 requirements and existing cmd_update patterns.
