---
phase: 01-pre-flight-cross-platform-hooks
type: walking-skeleton
created: 2026-05-24
proves: "dep check + hook wiring work end-to-end"
---

# Walking Skeleton — Phase 1: Pre-flight & Cross-Platform Hooks

The walking skeleton for Conjure Phase 1 is the thinnest slice that proves
two things end-to-end without handwaving:

1. **Dep check works:** `conjure preflight` exits correctly on the real CLI
2. **Hook wiring is correct:** a test fixture's `.claude/settings.json` references
   `node` not `bash`, and that JSON is valid

This slice exercises the full stack: CLI dispatcher → bash script → OS detection
→ output; template → copied file → JSON validity.

---

## What "Done" Looks Like for the Skeleton

Two commands that prove the system works:

```
# Proves SAFE-04: dep check fires and exits correctly
cli/conjure preflight
# Expected: exits 0 on a machine with node + git present; prints ✓ for each

# Proves SAFE-03: generated harness has node hooks, not bash hooks
grep 'node .claude/hooks/' templates/settings.json.tmpl
# Expected: 5 matches (one per .mjs hook)

grep -c 'bash .claude/hooks/' templates/settings.json.tmpl
# Expected: 0
```

The test suite (`bash tests/run.sh`) makes these assertions automated and
regression-proof.

---

## Architectural Decisions (binding for all subsequent phases)

### Runtime: POSIX bash 3.2+ + Node.js stdlib .mjs

**Decision:** All CLI scripts use `#!/usr/bin/env bash` with `set -uo pipefail`.
No bash 4+ features (no mapfile, readarray, associative arrays) because macOS
ships bash 3.2. All hooks are `.mjs` files invoked via `node file.mjs`.

**Implication for future phases:** Any new script in `scripts/` follows this
pattern. Any new hook goes in `templates/hooks-nodejs/` as a `.mjs` file.

### Hook invocation: `node .claude/hooks/foo.mjs` everywhere (D-01, D-02)

**Decision:** Single `settings.json` template, no OS branching, no arg passing.
Node reads `process.env.CLAUDE_FILE_PATH` and `process.env.CLAUDE_COMMAND` directly.

**Implication for future phases:** Any new hook wired in `templates/settings.json.tmpl`
uses the format `"command": "node .claude/hooks/hookname.mjs"` — no arguments,
no OS conditions.

### Required vs optional deps: node + git block; jq + rg + shellcheck warn (D-04, D-05)

**Decision:** `scripts/preflight.sh` exits 1 on `node` or `git` missing; exits 0
with a warning for `jq`, `rg`, `shellcheck` missing. Power tools (graphify, ast-grep)
are mentioned separately.

**Implication for future phases:** If a future phase adds a new required dep,
it goes in the `node git` list in `scripts/preflight.sh`. Optional deps go in the
`jq rg shellcheck` list. Never add to the inline `cmd_preflight` — that function
is now a one-line stub.

### scripts/ as the scripts home (Phase 1 only uses scripts/)

**Decision:** `lib/` does not exist yet. Phase 2 creates `lib/mutate.sh`. Phase 1
uses only `scripts/`. Do not create `lib/` in Phase 1 work.

**Implication for future phases:** Phase 2 creates `lib/` as a new dir. All
mutation-gating logic lives there. Cross-references from Phase 3+ should import
from `lib/`, not `scripts/`.

### Backup-before-mutate on template edits

**Decision:** Any edit to a template file must backup first (`cp file file.bak`)
and delete the backup only after successful validation.

**Implication for future phases:** Apply to all template edits. This is enforced
by CLAUDE.md constraint and is not optional.

### Test framework: hand-rolled bash (tests/run.sh)

**Decision:** No shellspec, no bats-core at integration level. Extend `tests/run.sh`
with new sections following the `echo "▸ Section name"` + `pass()`/`fail()` pattern.
bats-core is allowed only at unit level.

**Implication for future phases:** Phase 3 fixture tests add sections to `tests/run.sh`.
Phase 4 golden-file assertions go in the same file. Do not add new test framework dependencies.

---

## Directory Layout (as of end of Phase 1)

```
cli/
  conjure                      # dispatch + cmd_preflight stub → scripts/preflight.sh
scripts/
  preflight.sh                 # NEW: standalone dep checker, POSIX bash 3.2+
  init-project.sh              # MOD: copies .mjs hooks from hooks-nodejs/
  audit-setup.sh               # MOD: checks .mjs existence, not .sh executable bit
  install-mcp-stack.sh         # unchanged
  refresh-graph.sh             # unchanged
templates/
  hooks-nodejs/                # unchanged — 5 .mjs hooks, now actually wired
    post-edit-format.mjs
    pre-bash-block-destructive.mjs
    pre-commit-quality-gate.mjs   # newly wired into settings.json.tmpl
    session-start-context.mjs
    stop-compound-engineering.mjs
  hooks/                       # unchanged — bash hooks stay as reference
    *.sh
  settings.json.tmpl           # MOD: bash commands → node commands (5 hooks)
tests/
  run.sh                       # MOD: preflight section + template lint section added
```

Directories NOT created in Phase 1 (established for future phases):
- `lib/` — Phase 2
- `tests/fixtures/` — Phase 3
