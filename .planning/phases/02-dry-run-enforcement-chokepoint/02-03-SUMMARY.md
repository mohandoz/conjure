---
phase: 02
plan: 03
subsystem: profiles
tags: [dry-run, mutation-chokepoint, profiles, bash]
dependency_graph:
  requires: [02-01]
  provides: [all-9-profiles-migrated]
  affects: [profiles/ts-next, profiles/data-science, profiles/go-gin, profiles/java-spring, profiles/monorepo, profiles/node-nest, profiles/polyglot, profiles/python-fastapi, profiles/rust-axum]
tech_stack:
  added: []
  patterns: [mutate_write-option-b, variable-capture-heredoc, inline-chmod-guard]
key_files:
  created: []
  modified:
    - profiles/ts-next/apply.sh
    - profiles/data-science/apply.sh
    - profiles/go-gin/apply.sh
    - profiles/node-nest/apply.sh
    - profiles/polyglot/apply.sh
    - profiles/python-fastapi/apply.sh
    - profiles/rust-axum/apply.sh
    - profiles/java-spring/apply.sh
    - profiles/monorepo/apply.sh
decisions:
  - "Option B (inline command substitution) used for all mutate_write fragment appends — concise, counter-safe"
  - "monorepo dynamic heredoc replaced with MONOREPO_CONTENT variable + mutate_write — avoids subshell counter loss (Pitfall 3)"
  - "java-spring chmod guard uses inline [ DRY_RUN != 1 ] || chmod — D-02 excludes mutate_chmod"
metrics:
  duration: "~20 minutes"
  completed: "2026-05-24T20:15:00Z"
  tasks_completed: 2
  tasks_total: 2
  files_modified: 9
---

# Phase 2 Plan 3: Retrofit All 9 profiles/*/apply.sh Summary

**One-liner:** All 9 profile apply.sh scripts migrated from `$DRY` positional-arg guards to `lib/mutate.sh` chokepoint with `DRY_RUN` env var — uniform dry-run enforcement across all profiles.

## What Was Built

Migrated all 9 `profiles/*/apply.sh` scripts to route every filesystem write through the `lib/mutate.sh` mutation chokepoint created in plan 02-01. The migration removed the `DRY="${2:-0}"` positional argument from all 9 profiles and replaced per-call `[ "$DRY" = 0 ] && ...` guards with `mutate_write`, `mutate_cp`, and inline `DRY_RUN` guards. Each profile now calls `mutate_summary` at its tail.

**Task 1 — 7 simple profiles (ts-next, data-science, go-gin, node-nest, polyglot, python-fastapi, rust-axum):**
- Identical 3-step migration: remove `DRY="${2:-0}"`, add `source "$CONJURE_HOME/lib/mutate.sh"` after `PROFILE_DIR=`, replace write guard with `mutate_write` Option B, add `mutate_summary` before final echo.
- All 7 had the same `[ "$DRY" = 0 ] && cat "$PROFILE_DIR/CLAUDE.md.fragment" >> "$TARGET/CLAUDE.md"` pattern inside a `grep -q` idempotency guard. All replaced uniformly.

**Task 2 — java-spring and monorepo:**
- **java-spring:** Same 3-step header migration plus: `mutate_cp` for the hook file copy, inline `[ "${DRY_RUN:-0}" = "1" ] || chmod +x` guard (D-02 excludes mutate_chmod from the minimal function set).
- **monorepo:** Same header migration plus: dynamic heredoc replaced with `MONOREPO_CONTENT` variable-capture pattern — assigns the template content (with backtick escapes for `\`<cmd>\``) to a variable, then calls `mutate_write "$pkg/CLAUDE.md" "$MONOREPO_CONTENT"`. This avoids subshell counter loss (Pitfall 3 from RESEARCH.md). Root CLAUDE.md append migrated to `mutate_write` Option B.

## Verification

```
bash tests/run.sh  →  PASS: 121    FAIL: 0  (no regressions)
for f in profiles/*/apply.sh; do bash -n "$f"; done  →  all OK
grep -rn 'DRY="${2' profiles/  →  no output (all positional args removed)
grep -rl 'source.*lib/mutate.sh' profiles/  →  9 files
grep -rn '\[ "\$DRY" = 0 \]' profiles/  →  no output (all old guards removed)
DRY_RUN=1 bash profiles/ts-next/apply.sh /tmp/test  →  [dry-run] lines present, no filesystem mutations
```

## Commits

| Task | Commit | Files |
|------|--------|-------|
| Task 1: 7 simple profiles | 5d5f1a8 | profiles/{ts-next,data-science,go-gin,node-nest,polyglot,python-fastapi,rust-axum}/apply.sh |
| Task 2: java-spring + monorepo | 1008264 | profiles/java-spring/apply.sh, profiles/monorepo/apply.sh |

## Deviations from Plan

None — plan executed exactly as written.

The acceptance criteria grep for the chmod guard (`\[ "\${DRY_RUN:-0}" = "1" \] || chmod`) returns 0 due to unescaped brackets being treated as regex character classes. The line is present and correct; verified with `grep -cF`.

## Known Stubs

None — all 9 profiles now route writes through `lib/mutate.sh`. No placeholder values or stub patterns introduced.

## Threat Flags

None — no new network endpoints, auth paths, file access patterns, or schema changes introduced. The only new surface is the `source "$CONJURE_HOME/lib/mutate.sh"` line in each profile, which is the chokepoint this phase is building.

## Self-Check: PASSED

- All 9 profile files found on disk
- Commits 5d5f1a8 (Task 1) and 1008264 (Task 2) verified in git log
- SUMMARY.md present at .planning/phases/02-dry-run-enforcement-chokepoint/02-03-SUMMARY.md
