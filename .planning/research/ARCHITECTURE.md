# Architecture Research

**Domain:** Open-source init kit for Claude Code — POSIX bash CLI + Node `.mjs` hooks (Conjure v0.8.0 "Operability + DX")
**Researched:** 2026-06-04
**Confidence:** HIGH (live codebase read; all integration points derived from source; no speculative claims)

> **Scope note (subsequent milestone):** This file extends the v0.7.0 ARCHITECTURE.md in place.
> The v0.7.0 architecture is taken as fixed and fully shipped (579 passing tests). Everything below
> is additive or a targeted modification to existing components. The core invariant holds:
> **every filesystem write routes through `lib/mutate.sh`**. All new components must honor this
> without exception. Hooks/scripts exit 2, never exit 1.

---

## Existing Architecture Baseline (v0.7.0, fixed)

```
cli/conjure               — dispatcher (623 lines): parse flags, set env vars, delegate to scripts/
  ├── cmd_init            — init|migrate; --profile; --overlay; --dry-run
  ├── cmd_migrate         — calls migrations/<source>/migrate.sh
  ├── cmd_audit           — calls scripts/audit-setup.sh; --cost; --retire-list; --budget; --json
  ├── cmd_update          — --check / --apply / --pr / --cron
  ├── cmd_check           — calls scripts/check.sh; --porcelain; --schema; exit 0/1
  ├── cmd_resolve         — calls scripts/resolve.sh; --dry-run
  ├── cmd_adopt           — calls scripts/adopt.sh; full brownfield pipeline
  ├── cmd_refresh_graph   — calls scripts/refresh-graph.sh
  ├── cmd_refresh_overlay — calls scripts/refresh-overlay.sh
  ├── cmd_install_mcp     — calls scripts/install-mcp-stack.sh
  ├── cmd_preflight       — calls scripts/preflight.sh
  ├── cmd_publish         — calls scripts/publish-plugin.sh (old path)
  ├── cmd_publish_skill   — calls scripts/publish-skill.sh
  ├── cmd_publish_plugin  — calls scripts/publish-plugin.sh
  ├── cmd_emit_policy     — calls scripts/emit-policy.sh
  ├── cmd_eval            — calls scripts/eval.sh; init|run|--emit-workflow
  └── cmd_workspace       — calls scripts/workspace.sh; init|check|audit|update|adopt

lib/mutate.sh             — write chokepoint (ALL filesystem mutations go here)
lib/snapshot.sh           — snapshot_create / snapshot_rollback / snapshot_list
lib/inventory.sh          — inventory_scan / inventory_classify / inventory_emit_manifest
lib/log.sh                — log_init / log_step / log_fail → RESTRUCTURE-LOG.md
lib/merge.sh              — 3-way merge; writes conflict sidecars
lib/caps.sh               — CLAUDE_MD_CAP / SKILL_MD_CAP / AGENT_MD_CAP constants
lib/workspace.sh          — workspace manifest helpers; state machine; rollback
lib/plugin-helpers.sh     — jq transforms for plugin.json / marketplace.json
lib/policy-helpers.sh     — emit sandbox{} block / managed-settings / MDM artifacts
lib/cc-schema.json        — bundled CC schema table: hook events, settings keys, version gates
lib/exact-count.mjs       — opt-in exact token counter (Node.js)
lib/prices.json           — per-model price table

scripts/adopt.sh          — 5-step brownfield adoption pipeline (906 lines)
scripts/audit-setup.sh    — health-check; size caps; schema validation; budget; retire-list (695 lines)
scripts/check.sh          — drift detection; read-only; exit 0/1
scripts/resolve.sh        — guided interactive sidecar walker
scripts/init-project.sh   — scaffold .claude/ (idempotent)
scripts/eval.sh           — promptfoo init/run/emit-workflow (384 lines)
scripts/workspace.sh      — workspace orchestration: preflight → snapshot → ops → rollback (1237 lines)
scripts/emit-policy.sh    — per-regime sandbox + managed-settings + MDM artifacts
scripts/emit-plugin.sh    — generates .claude-plugin/ from harness scaffold
scripts/publish-plugin.sh — marketplace.json update + submission snippet
scripts/publish-skill.sh  — 4-gate skill validation + PR flow
scripts/preflight.sh      — dependency verification + OS-detected install hints (130 lines)

templates/                — kit templates (CLAUDE.md.tmpl, skills/, agents/, hooks-nodejs/)
  hooks-nodejs/
    skill-telemetry.mjs   — PreToolUse(Skill)+UserPromptExpansion → appends JSONL (opt-in)
profiles/                 — 9 stack profiles (apply.sh per profile: ts-next, node-nest, go-gin, etc.)
compliance/               — 4 compliance overlays (hipaa/ soc2/ gdpr/ pci/ — apply.sh)
.claude-plugin/           — plugin manifest (marketplace.json, plugin.json, SCHEMAS/)
tests/run.sh              — hand-rolled regression suite (579 assertions, ~6712 lines)
tests/fixtures/           — underscore-prefixed fixtures excluded from generic audit loops
```

**Telemetry data location (critical for stats):**
- Hook: `templates/hooks-nodejs/skill-telemetry.mjs`
- Write target: `$TARGET/.claude/telemetry/skill-events.jsonl` (appended per skill invocation)
- Schema: `{ts, session_id, event: "skill_invoke"|"skill_typed", skill, project_cwd}`
- Gate: `CONJURE_TELEMETRY=1` in `settings.json` env block (opt-in, silent no-op otherwise)
- Already consumed by: `scripts/audit-setup.sh` `--retire-list` section (lines 632–676), which
  reads the JSONL, counts fires per skill over 30 days, and cross-references installed skills.

---

## v0.8.0 Design Overview: Six Capability Areas

1. **`conjure doctor`** — standalone preflight diagnostics: full `command -v` table + `.mjs` probe + OS install hints
2. **`conjure stats`** — read skill-firing JSONL, fire/never-fire report, dead-skill detection, chars/4 cost estimates
3. **Eval suite expansion** — per-profile adherence suites, regression baselines beyond scaffold
4. **Init UX polish** — smart profile detection heuristics, smarter `--profile` auto-suggestion
5. **Live-UAT automation + test-harness hardening** — automate smoke tests, guard `git -C "$VAR"` for empty-var escape, document manual steps
6. **README + docs refresh** — no new code components; pure content work targeting existing CLI surface

---

## New and Modified Components

### Area 1: `conjure doctor`

#### What the existing `preflight.sh` already does (v0.7.0)

`scripts/preflight.sh` (130 lines) already has:
- `_detect_os()` — macos / linux / wsl / windows-gitbash via `uname -s`
- `_fixup()` — per-OS, per-dep install hints (brew / apt / winget)
- Required deps: `node`, `git`
- Optional deps: `jq`, `rg`, `shellcheck`
- Power tools: `graphify`, `ast-grep` (advisory only)

`cmd_preflight` in `cli/conjure` calls `scripts/preflight.sh` directly. It is already wired to
`conjure init` as a pre-check (line 84: `cmd_preflight || return 1`).

#### Gap between `preflight` and the `doctor` spec

`conjure doctor` per the v0.8.0 spec adds:
1. **`.mjs` probe** — verify `.claude/hooks/*.mjs` can be executed by `node`; `preflight.sh` only checks `command -v node`, not whether the hook files themselves run
2. **Richer output format** — structured summary table (not just pass/fail lines) with version numbers
3. **Separate subcommand entry** — `conjure doctor` vs `conjure preflight` (preflight is still the
   silent pre-check used by other commands; `doctor` is the verbose, user-facing diagnostic)

#### Integration decision: new `scripts/doctor.sh` worker + `cmd_doctor` entry

Do NOT modify `preflight.sh`. It is a silent, re-entrant checker used by `init`, `audit`, and the
workspace pipeline. Doctor is a separate UX concern: verbose, interactive, never called as a
sub-check. Adding verbose behavior to `preflight.sh` would break callers that redirect its output.

**New file:** `scripts/doctor.sh` — sources `scripts/preflight.sh` logic via shell functions
(or re-implements the `command -v` table with versions added). Key additions:

```
scripts/doctor.sh
  1. OS detection (reuse _detect_os logic — either source or inline)
  2. Dep table with versions:
     node $(node --version), git $(git --version | head -1), jq $(jq --version)
     shellcheck $(shellcheck --version | head -2), rg $(rg --version | head -1)
  3. .mjs probe:
     for each .claude/hooks/*.mjs in target:
       node --input-type=module < /dev/null → verify node can run ESM
       (a more precise probe: node -e "import('$hook').catch(()=>{})" is a syntax check)
  4. Claude Code version:
     CC_VERSION=$(claude --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
     compare against minimum_conjure_cc_version from lib/cc-schema.json
  5. cc-schema.json freshness (reuse staleness logic from audit-setup.sh SCHM-STALE)
  6. Exit 0 (all required found) / exit 2 (required missing)
```

**New dispatcher entry in `cli/conjure`:**
```bash
cmd_doctor() {
  local target="$(pwd)"
  # parse --target or positional arg
  CONJURE_HOME="$CONJURE_HOME" bash "$CONJURE_HOME/scripts/doctor.sh" "$target"
}
```

Case entry: `doctor) shift; cmd_doctor "$@" ;;`

**`usage()` line to add:**
`  conjure doctor [target]            — full dependency + hook diagnostic`

**Unchanged:** `scripts/preflight.sh` — kept as the silent sub-check.

---

### Area 2: `conjure stats`

#### Telemetry data flow (confirmed from source)

```
$TARGET/.claude/telemetry/skill-events.jsonl
  ← written by: templates/hooks-nodejs/skill-telemetry.mjs
     (PreToolUse/Skill + UserPromptExpansion events, opt-in via CONJURE_TELEMETRY=1)
  ← schema: {ts: ISO8601, session_id: string, event: "skill_invoke"|"skill_typed",
             skill: string, project_cwd: string}

$TARGET/.claude/skills/
  ← installed skill directories, each containing SKILL.md
  ← enumerated by: find $TARGET/.claude/skills -name SKILL.md

Already consumed by: scripts/audit-setup.sh --retire-list (lines 632–676)
  - reads JSONL, counts fires per skill in last 30 days
  - cross-references installed skill dirs
  - prints fire count + "[active]" / "[retire?]" status
```

#### Gap: `--retire-list` is embedded in `audit-setup.sh` under the `CONJURE_RETIRE` flag

The `--retire-list` section (lines 632–676 of `audit-setup.sh`) is the direct precursor to
`conjure stats`. It reads the JSONL and does a 30-day fire count. It does NOT produce:
- Total invocations across all time
- Cost estimates from telemetry (chars/4 per skill)
- Session counts (how many sessions touched each skill)
- Dead-skill detection (installed but never fired in the log's full history)
- JSON output mode

#### Integration decision: new `scripts/stats.sh` worker + `cmd_stats` entry

Do NOT expand `audit-setup.sh` further. It is already 695 lines and has a distinct audit
concern (health check). Stats is a separate read-only reporting concern.

`scripts/stats.sh` reads the JSONL and installed skills; produces a stand-alone report.
It sources `lib/caps.sh` for the chars/4 heuristic constants.

```
scripts/stats.sh
  1. Read $TARGET/.claude/telemetry/skill-events.jsonl
     - if absent: advise CONJURE_TELEMETRY=1 and exit 0
  2. Build per-skill aggregate from full JSONL history:
     - total fires (skill_invoke + skill_typed combined)
     - distinct session_id count per skill
     - last_fired timestamp per skill
     - chars/4 cost: for each installed SKILL.md, compute chars, extrapolate to
       (chars/4) * fires * price_per_token (reuse lib/prices.json)
  3. Cross-reference installed skills (find .claude/skills -name SKILL.md):
     - skills in JSONL but not installed → ghost fires (stale skill removed after data)
     - skills installed but not in JSONL → never-fired (dead-skill candidates)
  4. 30-day fire filter (same cutoff as --retire-list): surface "dormant" vs "never-fired"
  5. Output:
     human mode: ASCII table (skill, fires, sessions, last_fired, cost_est, status)
     --json flag: {skills: [...], summary: {total_fires, total_cost_est, dead_count}}
  6. Exit 0 always (read-only; no mutations; no failure conditions)
```

**`lib/stats-helpers.sh` (NEW) or inline in `scripts/stats.sh`?**

The JSONL-parsing logic (per-skill aggregation via `jq`) is ~40-60 lines. At that size, keep it
inline in `scripts/stats.sh` rather than creating a new lib. If a future feature (e.g., workspace
stats aggregation) needs to reuse it, extract to `lib/stats-helpers.sh` at that point.

**New dispatcher entry in `cli/conjure`:**
```bash
cmd_stats() {
  local target="$(pwd)" do_json=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --json) do_json=1 ;;
      *) target="$1" ;;
    esac
    shift
  done
  CONJURE_HOME="$CONJURE_HOME" CONJURE_JSON="$do_json" \
    bash "$CONJURE_HOME/scripts/stats.sh" "$target"
}
```

Case entry: `stats) shift; cmd_stats "$@" ;;`

**`usage()` line to add:**
`  conjure stats [--json] [target]    — skill-firing telemetry report`

**CRITICAL: `scripts/stats.sh` does NOT call `lib/mutate.sh`.** It is purely read-only.
No mutations — no source of mutate.sh needed. Exit 0 always.

**`--retire-list` in `audit-setup.sh` — keep or remove?**

Keep `--retire-list`. It serves a distinct audit context: the audit run gives a single-pass
health + retire signal. `conjure stats` is the dedicated reporting tool. Both can coexist;
they read the same JSONL but have different consumers (CI audit vs. developer telemetry review).

---

### Area 3: Eval Suite Expansion

#### What `conjure eval` already does (v0.7.0, confirmed from source)

- `eval.sh` has three subcommands: `init`, `run`, `--emit-workflow`
- `eval init`: generates `.conjure/eval/promptfooconfig.yaml` from installed skills and
  CLAUDE.md rule lines (skill-used + llm-rubric assertions per rule line)
- `eval run`: `npx --yes promptfoo@0.121.14 eval -c .conjure/eval/promptfooconfig.yaml`
- `--emit-workflow`: emits `.github/workflows/conjure-eval.yml` (promptfoo-action@v1, repeat:3, 80% threshold)
- `audit --budget`: context budget linter in `audit-setup.sh` (EVAL-04)
- `audit` EVAL-05: coverage gap report (diff installed skills vs skill-used assertions in yaml)

#### Gap: per-profile adherence suites and regression baselines

The `v0.8.0` spec adds:
1. **Per-profile adherence suites** — e.g., a ts-next project generates assertions specific to
   TypeScript + Next.js conventions, not just the generic CLAUDE.md rules
2. **Regression baselines beyond scaffold** — ability to capture a baseline run result and detect
   regressions in subsequent runs

#### Integration decision: extend `eval.sh` and add profile suite templates

**Per-profile suites approach:**

The `eval init` command already generates CLAUDE.md rule lines as llm-rubric assertions. For
per-profile suites, `eval init` needs to detect whether a profile was applied (check CLAUDE.md
for `<!-- profile:ts-next -->` markers written by `profiles/ts-next/apply.sh`) and append
profile-specific assertions from `profiles/<name>/eval-assertions.yaml.tmpl` if present.

This is additive to `_build_promptfooconfig()` in `eval.sh`:

```bash
# After existing llm-rubric section:
_detect_applied_profiles() {
  local target_dir="$1"
  # Each profile apply.sh appends <!-- profile:<name> --> marker to CLAUDE.md
  grep -oE 'profile:[a-z0-9_-]+' "$target_dir/CLAUDE.md" 2>/dev/null | sed 's/profile://' | sort -u
}

# In _build_promptfooconfig, after llm-rubric block:
while IFS= read -r profile_name; do
  local profile_assertions="$CONJURE_HOME/profiles/$profile_name/eval-assertions.yaml.tmpl"
  [ -f "$profile_assertions" ] && cat "$profile_assertions" >> "$outfile"
done <<PROFILES_EOF
$(_detect_applied_profiles "$target_dir")
PROFILES_EOF
```

**New template files per profile (NEW, additive):**
`profiles/<name>/eval-assertions.yaml.tmpl` — additional YAML test blocks to append.
Ships for: ts-next, node-nest, go-gin, python-fastapi (the most common profiles).
Does not exist for data-science, polyglot, rust-axum, java-spring, monorepo — added on demand.

**Regression baseline approach:**

`conjure eval run --baseline` saves the promptfoo results JSON (written by promptfoo to stdout
or `--output`) to `.conjure/eval/baseline.json`. A subsequent `eval run --compare` compares
pass rate against the baseline and exits 2 if pass rate drops more than 5pp.

This adds one flag to `cmd_eval_run()` in `eval.sh`. No new worker needed.

**Files to modify:**
- `scripts/eval.sh`: modify `_build_promptfooconfig()` to include per-profile blocks; add
  `--baseline` / `--compare` to `cmd_eval_run()`
- `cli/conjure`: update `cmd_eval` flag parsing to pass `--baseline` / `--compare` through
- `profiles/ts-next/eval-assertions.yaml.tmpl` (NEW)
- `profiles/node-nest/eval-assertions.yaml.tmpl` (NEW)
- `profiles/go-gin/eval-assertions.yaml.tmpl` (NEW)
- `profiles/python-fastapi/eval-assertions.yaml.tmpl` (NEW)

---

### Area 4: Init UX Polish

#### What `conjure init` currently does (v0.7.0, confirmed from source)

`cmd_init` in `cli/conjure` (lines 64–128):
- Parses `--profile=<name>` flag — user must know the profile name in advance
- Parses mode: `new` | `existing` | `migrate`
- Calls `cmd_preflight`, then `init-project.sh`, then optionally `profiles/$profile/apply.sh`
- No auto-detection of project type; `--profile` is purely manual

`scripts/init-project.sh` (160 lines):
- No profile auto-detection
- No interactive wizard (all flags parsed by `cmd_init` before dispatch)
- No detection of `package.json`, `go.mod`, `requirements.txt`, etc.

#### Gap: smart profile detection heuristics

The spec calls for "better profile selection, smarter defaults detection." The minimal approach:
add a `_detect_profile()` function in `cli/conjure` or `scripts/init-project.sh` that probes
for stack fingerprint files and suggests or auto-applies the matching profile.

**Integration decision: `_detect_profile()` helper in `cli/conjure`, called from `cmd_init`**

Keep logic in the dispatcher (not in `init-project.sh`) because:
1. `init-project.sh` already has a clear role (scaffold files) — profile logic is pre-scaffold
2. The dispatcher can read the profile flag and fill it in before calling `init-project.sh`

```bash
_detect_profile() {
  local target="$1"
  # Probe in order: first match wins
  [ -f "$target/next.config.js" ] || [ -f "$target/next.config.ts" ] && echo "ts-next" && return
  [ -f "$target/package.json" ] && grep -q '"nest"' "$target/package.json" && echo "node-nest" && return
  [ -f "$target/go.mod" ] && echo "go-gin" && return
  [ -f "$target/Cargo.toml" ] && echo "rust-axum" && return
  [ -f "$target/requirements.txt" ] || [ -f "$target/pyproject.toml" ] && echo "python-fastapi" && return
  [ -f "$target/build.gradle" ] || [ -f "$target/pom.xml" ] && echo "java-spring" && return
  echo ""  # no detection
}
```

In `cmd_init`, before calling `init-project.sh`:
```bash
if [ -z "$profile" ] && [ -t 0 ]; then  # TTY guard (same pattern as resolve.sh)
  detected="$(_detect_profile "$target")"
  if [ -n "$detected" ]; then
    echo "  ▸ Detected stack: $detected — apply profile? [Y/n]"
    read -r _ans </dev/tty
    case "${_ans:-Y}" in [Yy]*|"") profile="$detected" ;; esac
  fi
fi
```

**Non-TTY path:** no prompt; `detected` profile is logged but not auto-applied. This preserves
the invariant: non-TTY exits 2 / never auto-mutates for interactive questions.

**Files to modify:**
- `cli/conjure`: add `_detect_profile()` helper; modify `cmd_init` to call it when `--profile` absent

**Unchanged:** `scripts/init-project.sh` — profile application happens in `cmd_init` after
`init-project.sh` returns, reusing the existing `bash "$CONJURE_HOME/profiles/$profile/apply.sh"` call.

---

### Area 5: Live-UAT Automation + Test-Harness Hardening

#### Deferred debt from v0.7.0 (confirmed from PROJECT.md)

Four categories:
1. **`git -C "$VAR"` empty-var guard** — proven sandbox-escape: `mktemp` failure → empty var →
   `git -C ""` operates on the real repo. All test sandboxes that call `git -C "$VAR"` need a
   non-empty guard. Affects `tests/run.sh` (confirmed: 857–870, 946–959, 997–1010 use the pattern).
2. **Kill-safe SCHM-STALE swap** — `audit-setup.sh` SCHM-STALE already uses `workspace_state_write`
   pattern (line 484–497), but the workspace state writes use `jq > tmp && mv` atomic swap.
   Confirm whether SCHM-STALE's schema staleness write path is similarly protected or goes direct.
3. **Live `claude` binary smoke** — requires real Claude Code installed. Automate where possible
   (stub the binary in CI); document manual steps for true live runs.
4. **Live promptfoo run gated on key** — `eval run` already skips gracefully when
   `ANTHROPIC_API_KEY` is unset. Make CI skip advisory rather than fail-hard.

#### Integration: `tests/run.sh` hardening (MODIFIED)

**`git -C "$VAR"` guard pattern:**

Add a `_safe_git_C()` helper near the top of `tests/run.sh`:
```bash
_safe_git_C() {
  local _dir="$1"; shift
  [ -z "$_dir" ] && { echo "FATAL: _safe_git_C called with empty dir" >&2; exit 2; }
  git -C "$_dir" "$@"
}
```

Then replace `git -C "$MKTPL_DIR"`, `git -C "$SUBMIT_DIR"`, `git -C "$SKILL_DIR"` with
`_safe_git_C "$MKTPL_DIR"` etc. This surfaces the bug at the call site rather than silently
operating on the real repo.

Alternatively (simpler): add a `[ -n "$MKTPL_DIR" ] || { fail "mktemp failed"; skip; }` guard
immediately after each `mktemp` call. This is the POSIX pattern and doesn't require helper extraction.

**Kill-safe SCHM-STALE:**

Confirm `audit-setup.sh` SCHM-STALE (lines 484–497) emits only advisory `warn()` and `json_check`
calls — no file writes. If so, no atomic swap needed (read-only staleness check). The SCHM-STALE
flag in PROJECT.md likely refers to a future `conjure update` path that would update `cc-schema.json`
in-place — that write needs the `jq > tmp && mv` atomic pattern when implemented. Document the
constraint; no code change needed in v0.8.0 unless the update path is added.

**Live smoke automation:**

Add a CI job stub in `.github/workflows/ci.yml` (or a new `smoke.yml`) that:
- Runs `conjure preflight` (passes in CI since node+git+jq+shellcheck are present)
- Runs `conjure doctor` (new — validates full dep table + .mjs probe)
- Skips `eval run` if `ANTHROPIC_API_KEY` is absent (already the eval.sh behavior)
- Documents remaining manual steps in `tests/MANUAL-UAT.md` (new file, not a code component)

**Files to modify:**
- `tests/run.sh`: add `mktemp` empty-var guards after each `mktemp` call that feeds `git -C`
- `.github/workflows/ci.yml` (if exists) or new `smoke.yml`: add `conjure doctor` job
- `tests/MANUAL-UAT.md` (NEW): document live-binary smoke and MDM hardware steps

---

### Area 6: README + Docs Refresh

Pure content work. No new code components. Targets:
- `README.md` — rewrite covering v0.3–v0.7 (quick start, command reference, feature tour)
- `MIGRATION-GUIDE.md` — sync to current command surface
- `FAILURE-MODES.md` — add v0.7.0 failure modes (workspace rollback, emit-policy MDM, eval gate)

No architecture implications.

---

## Component Interaction Map (v0.8.0 additions)

```
┌────────────────────────────────────────────────────────────────────────────────────────┐
│  ENTRYPOINTS                                                                            │
│  ┌─────────────────────────────────────────────────────────────────────────────────┐   │
│  │  cli/conjure  (bash dispatcher)                        [existing + MODIFIED]     │   │
│  │   ... all v0.7.0 subcommands unchanged ...                                     │   │
│  │   doctor [target]                                      [NEW — v0.8.0]          │   │
│  │   stats [--json] [target]                              [NEW — v0.8.0]          │   │
│  │   eval init|run|--emit-workflow     ─── MODIFIED to pass --baseline/--compare  │   │
│  │   init [new|existing|migrate] ...   ─── MODIFIED to add _detect_profile()      │   │
│  └─────────────────────────────────────────────────────────────────────────────────┘   │
├────────────────────────────────────────────────────────────────────────────────────────┤
│  WORKER SCRIPTS (subprocess via bash scripts/*.sh)                                      │
│  ┌──────────────────────────────────────────────────────────────────────────────────┐  │
│  │  scripts/doctor.sh               [NEW — v0.8.0]                                  │  │
│  │   dep table with versions + .mjs probe + CC version check + schema freshness    │  │
│  │   reads: lib/cc-schema.json (freshness); no lib/mutate.sh needed (read-only)    │  │
│  │   exit 0 (all ok) / exit 2 (required dep missing) — NEVER exit 1                │  │
│  ├──────────────────────────────────────────────────────────────────────────────────┤  │
│  │  scripts/stats.sh                [NEW — v0.8.0]                                  │  │
│  │   reads $TARGET/.claude/telemetry/skill-events.jsonl (opt-in JSONL)             │  │
│  │   reads $TARGET/.claude/skills/**/SKILL.md (installed skills)                   │  │
│  │   reads lib/prices.json (cost estimation)                                       │  │
│  │   jq aggregate: fires, sessions, last_fired, cost_est per skill                │  │
│  │   NEVER sources lib/mutate.sh — purely read-only; exit 0 always                │  │
│  │   --json flag: structured JSON output to stdout                                 │  │
│  ├──────────────────────────────────────────────────────────────────────────────────┤  │
│  │  scripts/eval.sh                 [MODIFIED — v0.8.0]                             │  │
│  │   _build_promptfooconfig(): +_detect_applied_profiles() → per-profile blocks    │  │
│  │   cmd_eval_run(): +--baseline (save results) / +--compare (regression check)   │  │
│  ├──────────────────────────────────────────────────────────────────────────────────┤  │
│  │  cli/conjure cmd_init            [MODIFIED — v0.8.0]                             │  │
│  │   +_detect_profile() helper: fingerprint heuristics → TTY-gated profile prompt  │  │
│  ├──────────────────────────────────────────────────────────────────────────────────┤  │
│  │  tests/run.sh                    [MODIFIED — v0.8.0]                             │  │
│  │   +mktemp empty-var guards after each mktemp that feeds git -C                  │  │
│  │   +doctor subcommand tests                                                       │  │
│  │   +stats subcommand tests                                                        │  │
│  └──────────────────────────────────────────────────────────────────────────────────┘  │
├────────────────────────────────────────────────────────────────────────────────────────┤
│  SHARED LIB (sourced, not dispatched)                                                   │
│  ┌──────────────────────────────────────────────────────────────────────────────────┐  │
│  │ lib/mutate.sh   [existing — UNCHANGED]                                           │  │
│  │  THE write chokepoint — invariant preserved; stats.sh and doctor.sh do NOT use  │  │
│  └──────────────────────────────────────────────────────────────────────────────────┘  │
│  ┌──────────────────────────────────────────────────────────────────────────────────┐  │
│  │ lib/prices.json [existing — UNCHANGED; REUSED by stats.sh for cost estimates]    │  │
│  └──────────────────────────────────────────────────────────────────────────────────┘  │
│  ┌──────────────────────────────────────────────────────────────────────────────────┐  │
│  │ lib/cc-schema.json [existing — UNCHANGED; READ by doctor.sh for CC version gate] │  │
│  └──────────────────────────────────────────────────────────────────────────────────┘  │
│  ┌──────────────────────────────────────────────────────────────────────────────────┐  │
│  │ All other v0.7.0 libs: snapshot.sh, workspace.sh, plugin-helpers.sh,            │  │
│  │ policy-helpers.sh, inventory.sh, log.sh, merge.sh, caps.sh — UNCHANGED          │  │
│  └──────────────────────────────────────────────────────────────────────────────────┘  │
├────────────────────────────────────────────────────────────────────────────────────────┤
│  TEMPLATES + PROFILES (new files)                                                       │
│  ┌──────────────────────────────────────────────────────────────────────────────────┐  │
│  │ profiles/ts-next/eval-assertions.yaml.tmpl       [NEW — v0.8.0]                  │  │
│  │ profiles/node-nest/eval-assertions.yaml.tmpl     [NEW — v0.8.0]                  │  │
│  │ profiles/go-gin/eval-assertions.yaml.tmpl        [NEW — v0.8.0]                  │  │
│  │ profiles/python-fastapi/eval-assertions.yaml.tmpl [NEW — v0.8.0]                 │  │
│  │  appended to .conjure/eval/promptfooconfig.yaml by eval init when profile active │  │
│  └──────────────────────────────────────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────────────────────────────────┘
```

---

## New vs Modified Files — Explicit List

### NEW FILES

| File | Type | Purpose |
|------|------|---------|
| `scripts/doctor.sh` | worker | dep table + versions + .mjs probe + CC version check + schema freshness; verbose user-facing diagnostic |
| `scripts/stats.sh` | worker | read skill-events.jsonl; per-skill fires/sessions/cost aggregate; dead-skill detection; --json output |
| `profiles/ts-next/eval-assertions.yaml.tmpl` | template | profile-specific llm-rubric assertions appended by eval init |
| `profiles/node-nest/eval-assertions.yaml.tmpl` | template | same for NestJS |
| `profiles/go-gin/eval-assertions.yaml.tmpl` | template | same for Go/Gin |
| `profiles/python-fastapi/eval-assertions.yaml.tmpl` | template | same for FastAPI |
| `tests/MANUAL-UAT.md` | doc | documents live-binary + MDM hardware manual steps |

### MODIFIED FILES

| File | Change | Why |
|------|--------|-----|
| `cli/conjure` | add `cmd_doctor`, `cmd_stats` + dispatch entries + usage() lines; add `_detect_profile()` helper; modify `cmd_init` to call it; modify `cmd_eval` to pass `--baseline`/`--compare` | 2 new subcommands + init UX + eval flags |
| `scripts/eval.sh` | add `_detect_applied_profiles()`; modify `_build_promptfooconfig()` to append profile blocks; add `--baseline`/`--compare` to `cmd_eval_run()` | per-profile suites + regression baselines |
| `tests/run.sh` | add empty-var guards after each `mktemp` that feeds `git -C`; add doctor + stats test blocks | harness hardening + new subcommand coverage |
| `.github/workflows/ci.yml` (or new `smoke.yml`) | add `conjure doctor` CI step | live dep check in CI |

### UNCHANGED FILES (confirmed)

| File | Reason |
|------|--------|
| `scripts/preflight.sh` | kept as silent sub-check; doctor.sh is a separate verbose surface |
| `scripts/audit-setup.sh` | retire-list stays; no new sections needed in v0.8.0 |
| `lib/mutate.sh` | API complete; invariant preserved; stats.sh and doctor.sh do not write |
| `lib/snapshot.sh` | not involved in v0.8.0 features |
| `lib/workspace.sh` | not involved |
| `lib/prices.json` | reused read-only by stats.sh |
| `lib/cc-schema.json` | reused read-only by doctor.sh |
| `scripts/workspace.sh` | not involved |
| `scripts/adopt.sh` | not involved |

---

## Data Flow: End-to-End for Each Area

### `conjure doctor` Flow

```
USER: conjure doctor [target]
  │
  ▼
cli/conjure cmd_doctor → scripts/doctor.sh $target
  │
  ├─ _detect_os() → OS classification
  ├─ for each dep in [node git jq rg shellcheck]:
  │    command -v + version flag → pass/fail + fixup hint per OS
  ├─ .mjs probe:
  │    for .claude/hooks/*.mjs in $target:
  │      node --check $hook_file → syntax validate
  │      (node --input-type=module --check is unavailable; use node -e "require('module')
  │       .createRequire(import.meta.url)" or simply `node --check` for syntax-only)
  ├─ CC version check:
  │    claude --version → extract semver
  │    compare vs minimum_conjure_cc_version from lib/cc-schema.json
  ├─ Schema freshness:
  │    read lib/cc-schema.json .updated → compare to today (>90 days = advisory)
  │
  └─ print summary table; exit 0 (all ok) / exit 2 (required missing)
```

### `conjure stats` Flow

```
USER: conjure stats [--json] [target]
  │
  ▼
cli/conjure cmd_stats → scripts/stats.sh $target
  │
  ├─ check jq available (required for JSONL processing)
  ├─ LOG="$target/.claude/telemetry/skill-events.jsonl"
  │    if absent: advise CONJURE_TELEMETRY=1; exit 0
  ├─ Installed skills: find $target/.claude/skills -name SKILL.md → list of names
  ├─ jq aggregate from full JSONL history:
  │    per skill: total_fires, distinct_sessions, last_fired
  │    jq reads skill-events.jsonl, groups by .skill field
  ├─ 30-day filter: same cutoff as audit --retire-list (date -v-30d / date -d '30 days ago')
  ├─ Cost estimate: per skill, read SKILL.md char count → /4 → tokens → * price_per_mtok
  │    price from lib/prices.json (reused, no modification)
  ├─ Dead-skill detection:
  │    installed but never in JSONL at all → "never-fired"
  │    installed, in JSONL, but zero fires in 30 days → "dormant"
  │    ghost: in JSONL but not installed → advisory note only
  ├─ Output:
  │    human mode: ASCII table (skill, fires_total, fires_30d, sessions, last_fired, cost_est, status)
  │    --json mode: JSON object to stdout
  └─ exit 0 (always — read-only; no failure conditions)
```

### `eval init` with Per-Profile Blocks Flow

```
USER: conjure eval init [target]
  │
  ▼
scripts/eval.sh cmd_eval_init $target
  │
  ├─ (existing) list installed skills → skill-used assertions
  ├─ (existing) extract CLAUDE.md rule lines → llm-rubric assertions
  ├─ (NEW) _detect_applied_profiles $target:
  │    grep -oE 'profile:[a-z0-9_-]+' $target/CLAUDE.md → profile name list
  │    for each profile_name:
  │      if $CONJURE_HOME/profiles/$profile_name/eval-assertions.yaml.tmpl exists:
  │        cat template → append to promptfooconfig.yaml tempfile
  └─ mutate_write_file .conjure/eval/promptfooconfig.yaml $tmpfile
```

### `cmd_init` with Profile Detection Flow

```
USER: conjure init [new|existing] [target]  (no --profile flag)
  │
  ▼
cli/conjure cmd_init
  │
  ├─ cmd_preflight || return 1
  ├─ bash init-project.sh $mode $target
  ├─ (NEW) if --profile absent AND tty:
  │    _detect_profile $target → detected profile name or ""
  │    if non-empty: prompt user via /dev/tty [Y/n]
  │    if confirmed: profile="$detected"
  │    if non-tty: log detected profile but do not apply (no auto-mutate)
  ├─ if profile non-empty:
  │    bash $CONJURE_HOME/profiles/$profile/apply.sh $target  (existing path)
  └─ exit 0
```

---

## Dependency-Ordered Build Sequence

### Step 1 — `scripts/doctor.sh` + `cmd_doctor` in `cli/conjure`

**Why first:** Self-contained, no new lib deps, no code deps on any other v0.8.0 work.
Delivers visible user value immediately. Validates that the dep-table pattern works before
building `stats.sh` which has more JSONL complexity.

Requires: `lib/cc-schema.json` (shipped v0.7.0 — read-only), `scripts/preflight.sh` (reference only)
Unblocks: Step 3 (CI smoke step uses `conjure doctor`)

---

### Step 2 — `scripts/stats.sh` + `cmd_stats` in `cli/conjure`

**Why second:** Purely read-only; no new lib deps; `lib/prices.json` already ships. The JSONL
schema is confirmed from the source read of `skill-telemetry.mjs`. Build it before eval expansion
because stats gives the operator visibility that motivates which profiles to add evals for.

Requires: `lib/prices.json` (shipped); telemetry JSONL exists at runtime (opt-in, not a build dep)
Unblocks: Step 4 (eval expansion uses dead-skill data to inform which profiles need assertions)

---

### Step 3 — Test-harness hardening + CI smoke step

**Why third:** The empty-var `git -C` guard is a safety fix. It should land before new tests
for `doctor` and `stats` are written, so the new tests inherit the safe pattern from the start.
The CI smoke step for `conjure doctor` (Step 1) lands here.

Requires: Step 1 (`conjure doctor` must exist before it can be exercised in CI)
Unblocks: Step 5 (init polish tests use the hardened harness)

---

### Step 4 — Eval suite expansion (per-profile blocks + baseline/compare)

**Why fourth:** Depends on the profile name list (existing), `eval.sh` (existing), and profile
template files (new). The `_detect_applied_profiles()` function is simple; the template files
for 4 profiles are the main deliverable. Build this before init polish so that a newly
profile-detected init immediately has corresponding eval assertions available.

Requires: `scripts/eval.sh` (shipped); `profiles/*/apply.sh` marker convention (confirmed existing)
Unblocks: Step 5 (init UX polish — `eval init` after a profile-detected init is the end-to-end flow)

---

### Step 5 — Init UX polish (`_detect_profile()` + TTY-gated prompt)

**Why fifth:** Depends on profiles existing (confirmed) and on the pattern being stable. Place
after eval expansion so that the test for "init detects ts-next, user confirms, then eval init
generates ts-next assertions" can be written as a single integrated test case.

Requires: profile directories (shipped); TTY guard pattern (established in `resolve.sh`)
Unblocks: Step 6 (documentation refresh depends on knowing the final UX surface)

---

### Step 6 — README + docs refresh

**Why last:** Pure content. Depends on all v0.8.0 features being in a stable state so the
documentation accurately reflects the shipped surface.

Requires: Steps 1–5 stable
Unblocks: release

---

### Build order summary table

| Step | Work item | New / Modified files | Key dependency | Unblocks |
|------|-----------|----------------------|----------------|----------|
| 1 | scripts/doctor.sh + cmd_doctor | `scripts/doctor.sh` (N), `cli/conjure` (M) | lib/cc-schema.json (shipped) | Step 3 CI smoke |
| 2 | scripts/stats.sh + cmd_stats | `scripts/stats.sh` (N), `cli/conjure` (M) | lib/prices.json (shipped); telemetry JSONL (runtime) | Step 4 eval visibility |
| 3 | Test harness hardening + CI smoke | `tests/run.sh` (M), CI workflow (M or N) | Step 1 doctor | Step 5 hardened tests |
| 4 | Eval expansion (per-profile + baseline) | `scripts/eval.sh` (M), `cli/conjure` (M), `profiles/*/eval-assertions.yaml.tmpl` (N×4) | eval.sh (shipped); profile markers (confirmed) | Step 5 end-to-end flow |
| 5 | Init UX polish (_detect_profile) | `cli/conjure` (M) | profiles/ (shipped); TTY guard pattern | Step 6 docs |
| 6 | README + docs refresh | `README.md`, `MIGRATION-GUIDE.md`, `FAILURE-MODES.md` (M), `tests/MANUAL-UAT.md` (N) | Steps 1–5 stable | Release |

N = New file, M = Modified file

---

## Anti-Patterns to Avoid

### Anti-Pattern 1: Adding verbose doctor output to `preflight.sh`

**What people do:** Modify `preflight.sh` to emit richer output when called as `conjure doctor`.
**Why it's wrong:** `preflight.sh` is called as a silent sub-check by `cmd_init`, `cmd_audit`, and
the workspace pipeline. These callers redirect or suppress its output. Adding verbose behavior
breaks the sub-check contract and forces all callers to adapt.
**Do this instead:** Keep `preflight.sh` as the silent sub-check. `scripts/doctor.sh` is the
separate verbose surface. Doctor can source `preflight.sh` functions if needed, or inline
equivalent logic.

---

### Anti-Pattern 2: Having `stats.sh` source `lib/mutate.sh`

**What people do:** Source `lib/mutate.sh` at the top of every script for consistency.
**Why it's wrong:** `mutate.sh` sets `DRY_RUN` guards and tracks write state. Sourcing it in a
read-only script adds needless complexity, and any accidental call to a `mutate_*` function
would trigger the dry-run gate rather than failing with "command not found."
**Do this instead:** `stats.sh` is explicitly read-only (no file writes). Do not source
`lib/mutate.sh`. If the script ever needs a write operation, that is a design error to be
questioned, not a reason to add `mutate.sh`.

---

### Anti-Pattern 3: Auto-applying a detected profile without TTY confirmation

**What people do:** When `_detect_profile()` returns a match in `cmd_init`, auto-apply the
profile silently (no prompt).
**Why it's wrong:** A detected `go.mod` might be a Go project that is NOT using Gin. The
profile appends CLAUDE.md content and runs `apply.sh` — these are mutations the user must
approve. Silent auto-apply violates the backup-before-mutate + human-gated mutation invariant.
**Do this instead:** TTY-gate the prompt (`[ -t 0 ]` check). Non-TTY → log the detection but
do not apply. TTY → prompt once, require explicit confirmation.

---

### Anti-Pattern 4: Embedding stats aggregation logic inside `audit-setup.sh`

**What people do:** Extend `audit-setup.sh` with a new `--stats` flag that exposes full telemetry
reporting alongside the health check.
**Why it's wrong:** `audit-setup.sh` is already 695 lines. It has a clear single concern:
health-check the `.claude/` setup. Stats is a separate concern (telemetry reporting). Mixing
them creates a god-script that is harder to test and harder to maintain.
**Do this instead:** `audit --retire-list` covers the dead-skill advisory in the audit context.
`conjure stats` is the dedicated telemetry reporting surface. Both read the same JSONL; they
serve different consumers.

---

### Anti-Pattern 5: `doctor.sh` exiting 1 (instead of 2) on required dep failure

**What people do:** Use `exit 1` for "required dep missing" since that is what `preflight.sh`
currently uses (confirmed: line 109 `exit 1` in `preflight.sh`).
**Why it's wrong:** `preflight.sh` exits 1 (non-zero, non-2) because it predates the project-wide
`exit 2` convention. The convention is: all hooks/CLI/scripts exit 2 on error, never exit 1.
`doctor.sh` is new code — it must follow the v0.8.0 convention (exit 2) even though
`preflight.sh` uses exit 1. Note: `preflight.sh` itself should be audited and its exit 1 changed
to exit 2 as a separate debt item.
**Do this instead:** `doctor.sh` exits 2 on required dep missing. Exit 0 on all-ok.

---

## Integration Points

### `lib/cc-schema.json` → `doctor.sh` (read-only reuse)

`doctor.sh` reads `lib/cc-schema.json` to get `minimum_conjure_cc_version` and `updated` fields.
No modification to the schema file needed. Same read pattern as `audit-setup.sh` (jq one-liner).

### `lib/prices.json` → `stats.sh` (read-only reuse)

`stats.sh` reads `lib/prices.json` for the default model and `input_per_mtok`. Same read pattern
as `audit-setup.sh` cost section (lines 564–628). No modification to `prices.json` needed.

### `skill-events.jsonl` → `stats.sh` (new primary consumer)

The existing `audit --retire-list` section in `audit-setup.sh` is a secondary reader of the
JSONL (read-only, 30-day window, simple fire count). `stats.sh` becomes the primary, dedicated
reader with full history aggregation. Both can coexist since the JSONL is append-only and
neither writer holds an exclusive lock.

### `profiles/*/eval-assertions.yaml.tmpl` → `eval.sh` `_build_promptfooconfig()`

The template files are optional (`[ -f ... ]` guard before reading). Profiles without a
template file silently skip the per-profile block. This means the feature degrades gracefully:
a user on a profile without eval-assertions.yaml.tmpl gets the same eval init output as v0.7.0.

### `_detect_profile()` in `cli/conjure` → `profiles/*/apply.sh` (existing path)

`_detect_profile()` just returns a profile name string. The actual application uses the
already-tested `bash "$CONJURE_HOME/profiles/$profile/apply.sh" "$target"` path (line 95–96
in `cmd_init`). No changes to any profile's `apply.sh` needed.

---

## Sources

- `cli/conjure` (full content read this session; line counts confirmed) — HIGH confidence
- `scripts/preflight.sh` (full content read this session) — HIGH confidence
- `scripts/audit-setup.sh` (lines 620–695 + 503–556 + 246–310 read this session) — HIGH confidence
- `scripts/eval.sh` (full content read this session) — HIGH confidence
- `templates/hooks-nodejs/skill-telemetry.mjs` (full content read this session) — HIGH confidence
- `lib/workspace.sh` (lines 1–80 read; atomic state pattern confirmed) — HIGH confidence
- `scripts/init-project.sh` (full content read this session) — HIGH confidence
- `profiles/ts-next/apply.sh` (read this session; profile marker convention confirmed) — HIGH confidence
- `.planning/PROJECT.md` v0.8.0 milestone context (read this session) — HIGH confidence
- `.planning/research/ARCHITECTURE.md` v0.7.0 (carried forward, full content read) — HIGH confidence
- `tests/run.sh` (grep patterns read; line counts confirmed; ~6712 lines / 579 assertions) — HIGH confidence

---
*Architecture research for: Conjure v0.8.0 Operability + DX integration*
*Researched: 2026-06-04*
