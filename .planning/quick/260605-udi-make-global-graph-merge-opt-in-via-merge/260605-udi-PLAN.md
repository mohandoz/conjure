---
phase: quick-260605-udi
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - scripts/refresh-graph.sh
  - cli/conjure
autonomous: true
requirements: [UDI-MERGE-GLOBAL-OPT-IN]
must_haves:
  truths:
    - "--setup never calls graphify global add or graphify merge-graphs"
    - "--merge in a workspace dir (has .conjure-workspace.json) merges member graphs via graphify merge-graphs"
    - "--merge in a manifest-less workspace (cwd not git, >=2 child .git dirs) merges discovered member graphs"
    - "--merge inside a single git repo prints an informational message and exits 0"
    - "--merge warns and skips when fewer than 2 member graphs exist"
    - "--merge warns and skips individual missing member graphs"
    - "graphify global add is absent from the entire script"
    - "shellcheck passes on the modified script"
  artifacts:
    - path: scripts/refresh-graph.sh
      provides: "--merge flag with three-mode workspace detection; --setup without any merge step"
    - path: cli/conjure
      provides: "usage lines updated to --merge (merge member-repo graphs at workspace level)"
  key_links:
    - from: "cli/conjure (usage comment + usage() function)"
      to: "scripts/refresh-graph.sh"
      via: "cmd_refresh_graph passes $@ through to the script"
      pattern: "\\-\\-merge"
---

<objective>
Replace `--merge-global` (machine-wide graphify global add) with `--merge`
(workspace-level graphify merge-graphs), and remove `graphify global add` from
`--setup` entirely.

Purpose: Per-project graphs are the default scope. Merging is a workspace-level
operation targeting a `merged-graph.json` alongside the member repos — never a
machine-global side-effect of `--setup`.

Output:
- scripts/refresh-graph.sh — Step 2 (global merge) deleted from --setup; new
  --merge branch implementing three workspace-detection modes; `graphify global
  add` gone from the entire file; comment header updated.
- cli/conjure — usage lines updated to document `--merge` (not --merge-global).
</objective>

<execution_context>
@$HOME/.claude/get-shit-done/workflows/execute-plan.md
@$HOME/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/quick/260605-udi-make-global-graph-merge-opt-in-via-merge/260605-udi-PLAN.md
</context>

<tasks>

<task type="auto">
  <name>Task 1: Remove global-merge from --setup; add --merge flag (workspace-level) to refresh-graph.sh</name>
  <files>scripts/refresh-graph.sh</files>
  <action>
Edit scripts/refresh-graph.sh with the following precise changes. POSIX bash
3.2+ throughout — no associative arrays, no mapfile, no local -n. Build graph
arg lists via positional params (`set --`). exit 2 on hard failures, never exit 1.

1. Update the comment header (lines 3-8):
   - Change Usage line to:
     `# Usage: bash refresh-graph.sh [target-dir] [--full|--update] [--backend <name>] [--ast-only] [--setup] [--merge]`
   - Change --setup description to:
     `#   --setup: idempotent integration steps (git-exclude, claude+hook install).`
   - Add after --setup description:
     `#   --merge: merge member-repo graphs at workspace level (workspace or manifest-less workspace; info-only in single-repo).`

2. In the variable declarations block, add `DO_MERGE=0` alongside `DO_SETUP=0`.
   Remove any `DO_MERGE_GLOBAL` variable if present.

3. In the POSIX arg-parsing case statement:
   - Add `--merge) DO_MERGE=1 ;;`
   - Remove any `--merge-global` case if present.

4. In the --setup block, remove Step 2 (global merge) — the lines beginning
   with the comment `# Step 2 — global merge` through the closing `fi` of that
   block (currently lines 119-127 in the original script). Keep Step 1
   (git-exclude), Step 3 (claude install), Step 4 (hook install), and renumber
   the survivors so comments read Step 1, Step 2, Step 3 respectively.

5. After the closing `fi` of the --setup block add the new --merge block. The
   logic must implement three detection modes in order:

   Mode A — Workspace with manifest (.conjure-workspace.json exists in cwd):
   - Read member repo paths from .conjure-workspace.json using:
     `jq -r '.repos[].path' .conjure-workspace.json`
   - Iterate member paths; for each, check if `<path>/graphify-out/graph.json`
     exists. If it does, accumulate it as a positional param (`set -- "$@" "<path>/graphify-out/graph.json"`).
     If missing, print a warning and skip.
   - If fewer than 2 graphs accumulated (`$# -lt 2`), warn "fewer than 2 member
     graphs found; skipping merge" and skip (do not call merge-graphs).
   - Otherwise call:
     `graphify merge-graphs "$@" --out graphify-out/merged-graph.json`
     and print success.

   Mode B — Manifest-less workspace (cwd is NOT a git repo AND >=2 immediate
   child dirs contain .git):
   - Guard: `git rev-parse --git-dir >/dev/null 2>&1` exits non-zero → not a git repo.
   - Discover children: iterate immediate subdirectories of cwd; for each where
     `<child>/.git` exists as a directory, check if `<child>/graphify-out/graph.json`
     exists. Accumulate graph paths via positional params the same way as Mode A.
   - Same >=2 guard and merge-graphs call as Mode A.

   Mode C — Single git repo (cwd is a git repo):
   - Guard: `git rev-parse --git-dir >/dev/null 2>&1` succeeds → single repo.
   - Print: "single repo — per-repo graph at graphify-out/graph.json; nothing to merge"
   - Exit 0 path (continue; no merge call).

   Detection order in the script:
   1. If .conjure-workspace.json exists → Mode A.
   2. Else if git rev-parse fails → Mode B (manifest-less workspace fallback).
   3. Else → Mode C (single repo).

   IMPORTANT: `graphify global add` must NOT appear anywhere in the file —
   neither in the new --merge block nor anywhere else.

   Use only POSIX constructs. Subdirectory iteration for Mode B must use a
   `for` loop with glob expansion (`for _d in ./*/ ; do ...`), not find with
   -exec or mapfile. Guard each glob with `[ -d "$_d" ]`.
  </action>
  <verify>
    <automated>shellcheck -S error -e SC2164,SC2044,SC2034,SC2155 scripts/refresh-graph.sh</automated>
  </verify>
  <done>
- shellcheck exits 0 with zero errors.
- `grep "global add" scripts/refresh-graph.sh` returns no output (zero occurrences).
- `grep "DO_MERGE=" scripts/refresh-graph.sh` shows declaration and references.
- `grep -c "Step 2" scripts/refresh-graph.sh` equals 1 and that occurrence is
  the claude-install step (formerly Step 3).
- `grep "merge-graphs" scripts/refresh-graph.sh` shows the merge-graphs call
  inside the DO_MERGE block.
  </done>
</task>

<task type="auto">
  <name>Task 2: Update refresh-graph usage lines in cli/conjure</name>
  <files>cli/conjure</files>
  <action>
In cli/conjure, update every location that documents refresh-graph flags:

1. Top-of-file comment block (around line 13):
   Replace any occurrence of `--merge-global` with `--merge` in the
   refresh-graph usage line, or if the flag is absent, append `[--merge]` to
   the existing flag list for refresh-graph. The final line should read:
   `#   refresh-graph [target] [--full|--update] [--backend <name>] [--ast-only] [--setup] [--merge]`

2. usage() function (around line 48):
   Same replacement/append. Final line:
   `conjure refresh-graph [target] [--full|--update] [--backend <name>] [--ast-only] [--setup] [--merge]`

3. If any other occurrence of `--merge-global` exists in the file, replace it
   with `--merge`.

No other changes to cli/conjure.
  </action>
  <verify>
    <automated>grep "merge-global" /Users/mohandoz/u01/innovate/conjure/cli/conjure | wc -l | tr -d ' ' | grep -q "^0$" && echo "PASS: no merge-global occurrences" || echo "FAIL: merge-global still present"</automated>
  </verify>
  <done>
- Zero occurrences of `--merge-global` in cli/conjure.
- `grep -c "\-\-merge" cli/conjure` is at least 2 (top comment + usage function).
  </done>
</task>

<task type="auto">
  <name>Task 3: Smoke-test the three --merge modes and --setup cleanliness</name>
  <files></files>
  <action>
Create a self-contained smoke test in a temp directory and run it. Use `bash`
directly (not bats). The test stubs `graphify` and `jq` as minimal shell
functions in a subshell so no real graphify install is required.

Four scenarios to verify:

(a) --setup must NOT call global add or merge-graphs:
    Run refresh-graph.sh --setup (with HOME/PATH stubbed so graphify, git, and
    jq resolve to stubs that record calls). Assert the call log contains no
    "global add" and no "merge-graphs".

(b) --merge in a dir with .conjure-workspace.json + two member graph.json files:
    Create a fake workspace root with .conjure-workspace.json listing two
    member paths. Create graphify-out/graph.json in each member. Run
    refresh-graph.sh --merge. Assert the call log shows
    `merge-graphs <path1>/graphify-out/graph.json <path2>/graphify-out/graph.json --out graphify-out/merged-graph.json`.

(c) --merge inside a git repo (Mode C):
    Initialize a throwaway git repo in the temp dir, change into it, run
    refresh-graph.sh --merge. Assert stdout contains "single repo" and no
    merge-graphs call occurs.

(d) --merge with fewer than 2 graphs (Mode A, only 1 member graph exists):
    Set up a workspace JSON with two members but create graph.json for only
    one. Assert stdout contains "fewer than 2" warning and no merge-graphs call.

Exit the smoke test script with 0 if all assertions pass, 2 if any fail.
Print PASS/FAIL per scenario.

Write the smoke test to $TMPDIR/refresh-graph-smoke.sh and run it with bash.
Do not leave test artifacts in the working tree.
  </action>
  <verify>
    <automated>bash "$TMPDIR/refresh-graph-smoke.sh"; echo "exit: $?"</automated>
  </verify>
  <done>
All four scenario lines print PASS and the smoke script exits 0.
  </done>
</task>

</tasks>

<threat_model>
## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| shell flag --merge → graphify merge-graphs | User triggers workspace-level graph merge; member paths come from .conjure-workspace.json or cwd glob |
| .conjure-workspace.json content → jq parse | File is user-controlled; parsed only for .repos[].path strings used as filesystem paths |

## STRIDE Threat Register

| Threat ID | Category | Component | Disposition | Mitigation Plan |
|-----------|----------|-----------|-------------|-----------------|
| T-udi-01 | Tampering | member path from .conjure-workspace.json | accept | paths used only as read-only file existence checks and graphify CLI args; no eval or shell expansion beyond quoting |
| T-udi-02 | Tampering | manifest-less child dir glob (./*/) | accept | glob anchored to cwd; each entry guarded with -d check; no user-supplied pattern |
| T-udi-03 | Denial of Service | graphify merge-graphs failure | mitigate | warn-and-skip already used for all setup steps; same pattern applied here |
| T-udi-SC | Tampering | npm/pip/cargo installs | accept | no new package installs in this change |
</threat_model>

<verification>
After all tasks complete:

1. shellcheck -S error -e SC2164,SC2044,SC2034,SC2155 scripts/refresh-graph.sh — must exit 0
2. No global add anywhere:
   grep "global add" scripts/refresh-graph.sh — must return empty
3. --setup block is clean:
   grep -A 40 'DO_SETUP.*=.*1' scripts/refresh-graph.sh | grep -c "merge-graphs" — must equal 0
4. --merge block calls merge-graphs:
   grep -A 50 'DO_MERGE.*=.*1' scripts/refresh-graph.sh | grep -q "merge-graphs" && echo PASS
5. cli/conjure has no merge-global:
   grep "merge-global" cli/conjure — must return empty
6. cli/conjure documents --merge:
   grep -c "\-\-merge" cli/conjure — must be >= 2
7. Smoke tests all pass (Task 3)
</verification>

<success_criteria>
- --setup runs: git-exclude + graphify claude install + graphify hook install (no global add, no merge-graphs)
- --merge in a workspace root: graphify merge-graphs over member graphs -> graphify-out/merged-graph.json
- --merge in a manifest-less workspace: same, discovered from child dirs with .git
- --merge in a single git repo: info message, exit 0, no merge call
- --merge with <2 graphs: warns and skips cleanly
- graphify global add absent from the entire script
- shellcheck exits 0 on scripts/refresh-graph.sh
- cli/conjure usage reflects --merge in both documentation locations
</success_criteria>

<output>
Create `.planning/quick/260605-udi-make-global-graph-merge-opt-in-via-merge/260605-udi-01-SUMMARY.md` when done.
</output>
