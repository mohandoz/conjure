---
phase: 28-promptfoo-eval-context-budget-linter
reviewed: 2026-06-03T17:12:52Z
depth: standard
files_reviewed: 3
files_reviewed_list:
  - scripts/eval.sh
  - scripts/audit-setup.sh
  - cli/conjure
findings:
  critical: 0
  warning: 0
  info: 2
  total: 2
status: clean
---

# Phase 28: Code Review Report (Iteration 2 — Re-review)

**Reviewed:** 2026-06-03
**Depth:** standard
**Files Reviewed:** 3
**Status:** clean

## Summary

Re-review after the fixer resolved 1 BLOCKER (CR-01) + 4 WARNINGs (WR-01..04)
across commits `6576ced`, `babad68`, `2bcba41`, `1ec9ed4`, `4d4627f`. Each fix
was verified empirically (stubbed inputs, live script runs, JSON parse checks)
and the codebase scanned for NEW regressions introduced by the fix commits.

**All five fixes verified correct. No new Critical or Warning defects found.**
Two Info-level observations are recorded below; neither blocks shipping. Per the
re-review charter (Info-only = clean), frontmatter status is `clean`.

### Empirical verification results

- **CR-01 (YAML escaping)** — `_yaml_escape_single` now does `sed "s/'/''/g"`.
  Verified: `Don't log PHI` → `Don''t log PHI`; only-apostrophe `'` → `''`;
  double quotes / colons / leading-dash pass through unescaped (correct for
  single-quoted YAML scalars); the old shell-style `'\''` idiom is fully gone
  (grep for `\'` returns nothing). Suite test `CR-01-yaml-apostrophe` passes.
- **WR-01 (EVAL-05 config path)** — `_eval_cfg=".conjure/eval/promptfooconfig.yaml"`
  is now cwd-relative post-`cd "$TARGET"`. Verified live: coverage report fires
  (`✓ eval coverage…`) for BOTH absolute (`/tmp/audittest`) and relative
  (`audittest` from `/tmp`) target args. Suite test `WR-01-eval05-relative-target`
  passes. No more path-doubling.
- **WR-02 (Node envelope)** — scrutinized hardest. Stubbed-parse matrix:
  20.19→REJECT, 20.20→ACCEPT, 20.99→ACCEPT, 21.0→REJECT, 22.0→REJECT,
  22.21→REJECT, 22.22→ACCEPT, 23.x→ACCEPT. All correct. `v`-prefix stripping
  via `tr -d 'v'` handles `v20.20.0`. Suite test `WR-02-node-envelope` passes.
  (One theoretical parse edge noted in Info IN-01 — not reachable from real
  `node --version` output.)
- **WR-03 (awk skill-used extraction)** — Verified live: interleaved
  `description:` between `type: skill-used` and `value:` no longer
  false-negatives (`beta.skill` extracted); commented-out assertion blocks
  excluded (no `ghost-skill` leak); hyphens and dots in names preserved
  (`gamma-skill.v2`). Suite test `WR-03-skill-extract-robust` passes.
- **WR-04 (porcelain `_comment`)** — Verified live: `audit --budget --porcelain`
  output still parses with `jq .`; `.over` and `._comment` both readable; the
  added `_comment` field documents the exit-code-vs-over-field contract without
  corrupting JSON. Suite test `WR-04-porcelain-contract` passes.

### Core invariants re-confirmed

- **Decoupling** — `audit-setup.sh`/`check.sh` are promptfoo-free: the only
  `promptfoo` token in audit is the config *filename* read by the EVAL-05
  coverage diff (no `npx`/promptfoo invocation). `check.sh` has zero references.
  Live: `audit` on a promptfoo-absent target exits 0/1 (never errors on its
  absence); suite test `EVAL-02-audit-decoupled` passes.
- **Single EXIT trap** — exactly one `trap _audit_cleanup EXIT` (line 33); the
  `--cost` block no longer re-registers, so `CHECKS_JSONL` is not leaked.
- **Exit codes** — audit honors its documented 0/1/2 gate; `eval.sh` dispatch
  returns 2 on unknown subcommand and all error paths.
- **POSIX bash 3.2+** — no associative arrays / `mapfile` / `local -n` added.
- **shellcheck `-S error -e SC2164,SC2044,SC2034,SC2155`** — clean across all
  three files.
- **Full suite** — 541 PASS / 0 FAIL (matches prior baseline; +regression tests
  for all 5 fixes now present and green).

## Info

### IN-01: Node parser accepts a bare-major version string (unreachable edge)

**File:** `scripts/eval.sh:43-47`
**Issue:** For a version string with no `.` (e.g. a bare `"22"`), the minor
extraction `_node_rest="${_node_ver#*.}"` returns the *full* string `22` when no
dot is present, so `_node_minor` becomes `22` and `22` would be (wrongly)
accepted as if it were `22.22`. This is not reachable in practice — `node
--version` always emits `vMAJOR.MINOR.PATCH`, and the `v`-strip leaves at least
`MAJOR.MINOR`. Recorded only for completeness; not a behavioral defect for real
inputs.
**Fix (optional hardening):** guard with a default when no dot is present, e.g.
`case "$_node_ver" in *.*) ;; *) _node_minor=0 ;; esac`.

### IN-02: EVAL-05 coverage diff couples audit to the eval config filename

**File:** `scripts/audit-setup.sh:533`
**Issue:** Audit references the literal path
`.conjure/eval/promptfooconfig.yaml`. This is a deliberate, documented coupling
(audit reads the file to diff skill-used assertions vs installed skills) and is
NOT a promptfoo-runtime dependency, so the decoupling invariant holds. Noted
because the filename is now duplicated between `eval.sh` (writer) and
`audit-setup.sh` (reader); a shared constant would remove drift risk if the path
ever changes.
**Fix (optional):** hoist the relative config path into `lib/caps.sh` (or a
small shared constant) consumed by both writer and reader.

---

_Reviewed: 2026-06-03_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
