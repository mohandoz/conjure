# Phase 16: Prerequisites — Context

**Date:** 2026-05-26
**Phase:** 16 of 20 — Prerequisites
**Goal:** Lay two infrastructure foundations — `mutate_rm` primitive and `publish-skill` positional arg refactor

---

## Domain

Infrastructure phase. No user-visible features — unblocks Phase 17 (`conjure check`) and Phase 18 (`conjure resolve`).

Two independent items:
1. **INFRA-01**: `mutate_rm` in `lib/mutate.sh`
2. **DEBT-02**: `publish-skill` positional second argument for `org/repo`

---

## Decisions

### mutate_rm design (INFRA-01)

- **Pattern**: Exact same pattern as `mutate_cp` and `mutate_mkdir`.
- **Dry-run**: Print `[dry-run] would rm <path>`, increment `CONJURE_DRY_MUTATION_COUNT`.
- **Live mode**: `rm -f "$1"` (files) — no `-r` needed (callers control recursive logic).
- **Position in file**: After `mutate_write`, before `mutate_summary`.
- **Regression test**: Add `mutate_rm` to `tests/run.sh` alongside existing `mutate_cp`/`mutate_write` tests.

### publish-skill positional arg (DEBT-02)

- **Precedence**: Positional `$2` takes priority over `TARGET_REPO` env.
- **Deprecation**: If `TARGET_REPO` is set AND `$2` is absent, use it but emit: `WARN: TARGET_REPO env var is deprecated; use 'conjure publish-skill <name> <org/repo>' instead`
- **Default removal**: Remove the `TARGET_REPO="${TARGET_REPO:-mohandoz/conjure}"` default — require explicit arg or env.
- **Arg parsing**: Accept `$2` before flags — after reading `$1` (SKILL_NAME), check if `$2` looks like `org/repo` pattern and consume it as TARGET_REPO.
- **Help text**: Update usage line to `conjure publish-skill <name> <org/repo> [--dry-run]`
- **Error**: If neither positional nor env is set, print usage and exit 2.

---

## Canonical Refs

- `lib/mutate.sh` — existing mutate primitives; `mutate_rm` must match their pattern exactly
- `scripts/publish-skill.sh` — target of the DEBT-02 refactor
- `.planning/REQUIREMENTS.md` — INFRA-01, DEBT-02 definitions
- `tests/run.sh` — where regression tests live; `mutate_rm` test goes here

---

## Code Context

### lib/mutate.sh patterns
- All functions: check `${DRY_RUN:-0}`, print `[dry-run] would <op> <args>`, increment counter, `return 0`
- Live path: direct bash operation
- Counter var: `CONJURE_DRY_MUTATION_COUNT` (initialized at top of file)

### publish-skill.sh current arg parsing
- `$1` = SKILL_NAME (positional)
- `shift || true` after reading $1
- while loop handles `--to`, `--to=*`, `--dry-run`
- `TARGET_REPO` initialized with default before the while loop — this default must be removed

---

## Out of Scope

- `mutate_rm -r` / recursive deletion — not needed for Phase 18 (sidecar files only)
- `conjure publish-skill --to` flag removal — keep `--to` for backwards compatibility (just add positional as alternative)
- Any Phase 17/18/19/20 logic — strictly Phase 16 prerequisites only

---

## Auto-Mode Note

Gray areas were auto-answered in autonomous mode. Decisions follow directly from existing codebase patterns — no ambiguity warranting user input.
