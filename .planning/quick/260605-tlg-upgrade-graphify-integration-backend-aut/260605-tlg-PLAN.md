---
phase: quick-260605-tlg
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - scripts/refresh-graph.sh
  - templates/settings.json.tmpl
  - cli/conjure
autonomous: true
requirements: [TLG-01, TLG-02, TLG-03, TLG-04]

must_haves:
  truths:
    - "refresh-graph.sh auto-detects available API key and selects backend without user intervention"
    - "Running refresh-graph.sh with no API keys falls through to AST-only (graphify update) with a hint"
    - "Claude backend probe checks for python anthropic package before selecting; falls through if missing"
    - "--backend flag forces a specific backend; --ast-only forces no-LLM path"
    - "--setup flag idempotently adds git-exclude, global merge, claude install, hook install"
    - "SessionStart hook in settings.json.tmpl runs graphify check-update fast and never blocks"
    - "cli/conjure usage line reflects --setup, --backend, --ast-only flags"
  artifacts:
    - path: "scripts/refresh-graph.sh"
      provides: "Backend auto-detect + --setup integration steps"
      contains: "GEMINI_API_KEY"
    - path: "templates/settings.json.tmpl"
      provides: "SessionStart graphify freshness hook"
      contains: "graphify check-update"
  key_links:
    - from: "cli/conjure"
      to: "scripts/refresh-graph.sh"
      via: "cmd_refresh_graph passes $@ through unchanged"
      pattern: "bash.*refresh-graph\\.sh.*\"\\$@\""
---

<objective>
Upgrade Conjure's graphify integration: backend auto-detect in refresh-graph.sh (no-API-key default
falls through to AST-only), --setup flag for git-exclude/global-merge/claude-install/hook-install,
SessionStart hook in settings.json.tmpl for fast freshness check, and updated CLI usage lines.

Purpose: Users without an LLM API key currently get a hard failure on full graphify builds.
This makes the integration graceful — AST-only always works, semantic extraction is opportunistic.

Output: Updated scripts/refresh-graph.sh, templates/settings.json.tmpl, cli/conjure usage block.
</objective>

<execution_context>
@/Users/mohandoz/.claude/get-shit-done/workflows/execute-plan.md
@/Users/mohandoz/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@/Users/mohandoz/u01/innovate/conjure/.planning/STATE.md
@/Users/mohandoz/u01/innovate/conjure/CLAUDE.md
@/Users/mohandoz/u01/innovate/conjure/scripts/refresh-graph.sh
@/Users/mohandoz/u01/innovate/conjure/templates/settings.json.tmpl
@/Users/mohandoz/u01/innovate/conjure/cli/conjure
</context>

<tasks>

<task type="auto">
  <name>Task 1: Rewrite refresh-graph.sh with backend auto-detect and --setup flag</name>
  <files>scripts/refresh-graph.sh</files>
  <action>
Replace the entire script body (keep the shebang + set -euo pipefail preamble) with the following
logic. All code must pass `shellcheck -S error -e SC2164,SC2044,SC2034,SC2155`. POSIX bash 3.2+
only — no associative arrays, no mapfile, no local -n. exit 2, never exit 1.

Usage header (update comment block at top of file):
  # refresh-graph.sh — rebuild or update the graphify knowledge graph.
  # Usage: bash refresh-graph.sh [target-dir] [--full|--update] [--backend <name>] [--ast-only] [--setup]
  #   --update (default): incremental AST-only update (graphify update .).
  #   --full: full rebuild. Uses detected/forced backend if available, else AST-only.
  #   --backend <name>: force semantic backend (gemini|claude|openai|deepseek|kimi).
  #   --ast-only: skip LLM extraction even if keys are set.
  #   --setup: idempotent integration steps (git-exclude, global merge, claude+hook install).

Argument parsing (POSIX, no getopt):
  - Scan positional args sequentially. First non-flag arg that is not a known flag or its
    value becomes TARGET (default: $(pwd)). Flags: --full sets MODE=full; --update sets
    MODE=update (default); --ast-only sets FORCE_AST=1; --backend reads next arg as BACKEND_FORCE;
    --setup sets DO_SETUP=1.
  - After parsing, cd "$TARGET".

graphify presence check (same as current): if not in PATH → print install hint, exit 2.

Backend detection function `detect_backend` (no subshell needed; set vars in caller scope):
  Order: GEMINI_API_KEY→gemini, ANTHROPIC_API_KEY→claude, OPENAI_API_KEY→openai,
         DEEPSEEK_API_KEY→deepseek, MOONSHOT_API_KEY→kimi.
  For each: if the env var is non-empty, set DETECTED_BACKEND to that name and return.
  If FORCE_AST=1 is set, skip detection entirely (DETECTED_BACKEND stays empty).
  If BACKEND_FORCE is set (--backend flag), set DETECTED_BACKEND=$BACKEND_FORCE (overrides detection).
  Claude probe: if DETECTED_BACKEND=claude, run `python3 -c "import anthropic" 2>/dev/null`;
    if that fails (non-zero), print one-line warning:
      "⚠ anthropic Python package missing — run: pip install anthropic"
    then fall through detection again starting from OPENAI_API_KEY (i.e., re-run detect_backend
    with ANTHROPIC_API_KEY temporarily unset — simplest POSIX approach: use a local temp var to
    skip claude on the second pass). If still no backend found, DETECTED_BACKEND stays empty.

Build dispatch:
  Full build (MODE=full OR graphify-out/graph.json does not exist):
    if DETECTED_BACKEND is non-empty:
      echo "→ Full graphify build (backend: $DETECTED_BACKEND)..."
      graphify extract . --backend "$DETECTED_BACKEND"
    else:
      echo "→ Full graphify build (AST-only — no LLM backend detected)..."
      graphify update .
      echo "  Tip: export GEMINI_API_KEY / ANTHROPIC_API_KEY / OPENAI_API_KEY for semantic extraction."

  Incremental build (MODE=update AND graph.json already exists):
    echo "→ Incremental update..."
    graphify update .

  Note: the old `graphify . --mode deep --wiki --mcp` call is replaced entirely. The `extract`
  subcommand is what provides semantic extraction; AST-only always uses `graphify update .`.

--setup steps (run after build if DO_SETUP=1):
  Step 1 — git exclude: check if `graphify-out/` is already in `.git/info/exclude`
    (use grep -qF). If not present and .git/info/ directory exists: append `graphify-out/` to
    `.git/info/exclude` (plain echo append — this is a local git meta file, not a mutation
    through mutate.sh; the CLAUDE.md split-responsibility rule applies to target-repo CLAUDE.md
    mutations, not local git metadata). Print "✓ Added graphify-out/ to .git/info/exclude" or
    "  (already in .git/info/exclude)".
    If .git/info/ does not exist: print "⚠ Not a git repo; skipping git exclude step."

  Step 2 — global merge: if graphify-out/graph.json exists:
    REPO_TAG="$(basename "$(pwd)")"
    run: graphify global add graphify-out/graph.json --as "$REPO_TAG"
    print "✓ Merged into global graph as '$REPO_TAG'".
    On non-zero exit from graphify global add: print warn, continue (do not exit).
    If graph.json missing: print "⚠ graphify-out/graph.json not found; skipping global merge."

  Step 3 — claude install:
    run: graphify claude install
    On non-zero exit: print "⚠ graphify claude install failed or not supported; skipping."
    continue.

  Step 4 — hook install:
    run: graphify hook install
    On non-zero exit: print "⚠ graphify hook install failed or not supported; skipping."
    continue.

  For each of steps 2-4: wrap the graphify call in a subshell or use `|| true`-style guard so
  a failure does not abort the script (set -e is active; use explicit `|| { warn; }` pattern).

Final summary lines (keep as-is from current script):
  echo
  echo "✓ Graph at: graphify-out/graph.json"
  echo "✓ Wiki at:  graphify-out/wiki/"
  echo "✓ Report:   graphify-out/GRAPH_REPORT.md"
  </action>
  <verify>
    <automated>shellcheck -S error -e SC2164,SC2044,SC2034,SC2155 /Users/mohandoz/u01/innovate/conjure/scripts/refresh-graph.sh</automated>
  </verify>
  <done>
    shellcheck passes with zero errors. Script contains GEMINI_API_KEY detection, claude anthropic probe,
    --setup flag, graphify update . for AST-only path, and graphify extract . --backend for semantic path.
    Smoke test (no graphify installed): `bash scripts/refresh-graph.sh --ast-only /tmp` exits 2 with install hint.
  </done>
</task>

<task type="auto">
  <name>Task 2: Add SessionStart graphify hook to settings.json.tmpl and update CLI usage</name>
  <files>templates/settings.json.tmpl, cli/conjure</files>
  <action>
--- templates/settings.json.tmpl ---

The file already has a "SessionStart" hook entry containing session-start-context.mjs.
Add a second hook object to the SessionStart hooks array, appended after the existing entry:

  {
    "type": "command",
    "command": "command -v graphify >/dev/null 2>&1 && graphify check-update . 2>/dev/null || true"
  }

Result: SessionStart.hooks array has two entries — session-start-context.mjs first, then the
graphify check-update one-liner second.

Also add "Bash(graphify check-update:*)" to the permissions.allow array, alongside the existing
graphify query/path/explain entries (after "Bash(graphify explain:*)").

Validate JSON after editing: `jq empty templates/settings.json.tmpl` must succeed.

--- cli/conjure ---

Two locations to update:

1. Comment block at the top of the file (lines ~13-14): update the refresh-graph line to:
   #   refresh-graph [target] [--full|--update] [--backend <name>] [--ast-only] [--setup]

2. Usage() function (line ~48): update the conjure refresh-graph usage line to:
   conjure refresh-graph [target] [--full|--update] [--backend <name>] [--ast-only] [--setup]

Do not change any other part of cli/conjure. The cmd_refresh_graph function already passes $@
through to the script, so no functional change is needed there.
  </action>
  <verify>
    <automated>jq empty /Users/mohandoz/u01/innovate/conjure/templates/settings.json.tmpl && grep -c "graphify check-update" /Users/mohandoz/u01/innovate/conjure/templates/settings.json.tmpl && grep -c "\-\-setup" /Users/mohandoz/u01/innovate/conjure/cli/conjure</automated>
  </verify>
  <done>
    `jq empty` passes on the template. Template contains graphify check-update in SessionStart hooks
    and Bash(graphify check-update:*) in allow rules. cli/conjure usage block shows --setup, --backend,
    --ast-only in the refresh-graph line at both the top comment and the usage() function.
  </done>
</task>

</tasks>

<threat_model>
## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| env vars → backend selection | API key values from environment influence which external process is invoked |
| .git/info/exclude write | Script appends to a local git metadata file in the target repo |
| graphify subcommands | External CLI called with user-controlled --backend value |

## STRIDE Threat Register

| Threat ID | Category | Component | Disposition | Mitigation Plan |
|-----------|----------|-----------|-------------|-----------------|
| T-tlg-01 | Tampering | --backend flag value | mitigate | Backend value is passed as-is to `graphify extract . --backend`; graphify CLI validates the value — no shell injection surface since it is a quoted variable in a non-eval context |
| T-tlg-02 | Spoofing | DETECTED_BACKEND from env | accept | Env vars are user-controlled by design; no privilege escalation possible — graphify runs as same user |
| T-tlg-03 | Information Disclosure | API key probe order printed | accept | Script prints backend name (e.g., "gemini"), never the key value itself |
| T-tlg-04 | Denial of Service | graphify check-update in SessionStart | mitigate | Command wrapped in `|| true`; `2>/dev/null` suppresses errors; `command -v` guard means no-op when graphify absent — never blocks session start |
| T-tlg-SC | Tampering | npm/pip/cargo installs | accept | No new package installs in this task; anthropic probe is read-only `python3 -c "import anthropic"` |
</threat_model>

<verification>
1. shellcheck -S error -e SC2164,SC2044,SC2034,SC2155 scripts/refresh-graph.sh  → zero errors
2. jq empty templates/settings.json.tmpl  → exit 0
3. bash scripts/refresh-graph.sh --help 2>&1 || bash scripts/refresh-graph.sh --ast-only /tmp 2>&1  → exits 2 with install hint (graphify not installed in CI)
4. grep "graphify check-update" templates/settings.json.tmpl  → matches in both SessionStart.hooks and permissions.allow
5. grep "\-\-setup\|\-\-backend\|\-\-ast-only" cli/conjure  → matches in both comment block and usage() function
</verification>

<success_criteria>
- refresh-graph.sh: shellcheck-clean POSIX bash; detects API keys in priority order; falls back to
  `graphify update .` with hint when no key found; probes for anthropic package before selecting
  claude backend; --backend/--ast-only/--setup flags all functional; --setup steps are idempotent
  and individually failure-tolerant.
- templates/settings.json.tmpl: valid JSON; SessionStart hooks array has graphify check-update
  one-liner as second entry; permissions.allow includes Bash(graphify check-update:*).
- cli/conjure: both usage locations show --setup, --backend, --ast-only in refresh-graph signature.
</success_criteria>

<output>
Create .planning/quick/260605-tlg-upgrade-graphify-integration-backend-aut/260605-tlg-SUMMARY.md when done.
</output>
