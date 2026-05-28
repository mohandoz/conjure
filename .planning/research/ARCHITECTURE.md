# Architecture Research

**Domain:** Open-source init kit for Claude Code — POSIX bash CLI + Node `.mjs` hooks (Conjure v0.6.0 "Safe Brownfield Adoption")
**Researched:** 2026-05-28
**Confidence:** HIGH (full codebase read directly from repo; all integration points derived from live source)

> **Scope note (subsequent milestone):** This file extends the v0.5.0 ARCHITECTURE.md in place.
> The v0.5.0 architecture is taken as fixed and fully shipped. Everything below is
> additive or a targeted modification to existing files. The core invariant holds:
> **every filesystem write routes through `lib/mutate.sh`**. All new components must
> honor this without exception.

---

## Existing Architecture (v0.5.0, fixed baseline)

```
cli/conjure               — dispatcher: parse flags, call scripts/*, source lib/*
  ├── cmd_init            — init|migrate; --profile; --overlay; --dry-run
  ├── cmd_migrate         — calls migrations/<source>/migrate.sh
  ├── cmd_audit           — calls scripts/audit-setup.sh; --cost; --retire-list
  ├── cmd_update          — --check / --apply / --pr / --cron
  ├── cmd_check           — calls scripts/check.sh; --porcelain; exit 0/1
  ├── cmd_resolve         — calls scripts/resolve.sh; --dry-run
  ├── cmd_refresh_graph   — calls scripts/refresh-graph.sh
  ├── cmd_refresh_overlay — calls scripts/refresh-overlay.sh
  ├── cmd_install_mcp     — calls scripts/install-mcp-stack.sh
  ├── cmd_preflight       — calls scripts/preflight.sh
  ├── cmd_publish         — calls scripts/publish-plugin.sh
  └── cmd_publish_skill   — calls scripts/publish-skill.sh

lib/mutate.sh             — write chokepoint (ALL filesystem mutations go here)
                            mutate_mkdir / mutate_cp / mutate_write / mutate_rm
lib/merge.sh              — 3-way merge; writes conflict sidecars (.conjure-conflict-*)
lib/cost.sh               — char→token→$ estimation
lib/exact-count.mjs       — opt-in exact token counter (Node.js)
lib/prices.json           — per-model price table

scripts/init-project.sh   — scaffold .claude/
scripts/audit-setup.sh    — health-check; size caps; schema validation
scripts/check.sh          — drift detection; read-only; exit 0/1
scripts/resolve.sh        — guided interactive sidecar walker
scripts/preflight.sh      — dependency verification
scripts/update-pr.sh      — PR automation for conjure update --pr
scripts/publish-plugin.sh — marketplace.json update + submission snippet
scripts/publish-skill.sh  — 4-gate skill validation + PR flow
scripts/refresh-graph.sh  — knowledge graph rebuild
scripts/refresh-overlay.sh— org overlay refresh

templates/                — kit templates (CLAUDE.md.tmpl, skills/, agents/, hooks-nodejs/)
profiles/                 — 9 stack profiles (apply.sh per profile)
compliance/               — 4 compliance overlays
tests/
  run.sh               — hand-rolled regression suite (302+ assertions)
  lib/sandbox.sh       — test helper
  fixtures/<profile>/  — committed scaffolds per stack profile
```

Key invariant: **every filesystem write in the kit routes through `lib/mutate.sh`**
(mutate_mkdir / mutate_cp / mutate_write / mutate_rm). All new commands must honor this.

---

## v0.6.0 Design Overview

The new capability = "Safe Brownfield Adoption" with two cooperating halves:

1. **`conjure adopt` (deterministic CLI)** — pure shell, no LLM judgment. Does:
   git-clean gate → full timestamped snapshot backup → inventory + classify all
   markdown → emit `adopt-manifest.json` → scaffold missing harness layers →
   size-cap audit → log all steps to `RESTRUCTURE-LOG.md` → support `--dry-run`
   and `--rollback`.

2. **`restructure` skill (Claude in-session, human-gated)** — LLM judgment only.
   Reads the manifest + source docs → proposes a restructure plan → presents each
   step for human approval → each approved step calls back into `conjure adopt
   --apply-step <step-id>` which executes through `lib/mutate.sh`. The skill
   never touches the filesystem directly.

**Key tension resolved:** Conjure's core value is deterministic + auditable, but
condensing a 21KB/180-line CLAUDE.md requires LLM judgment. Resolution = split
responsibility. The CLI owns all mutations. The skill owns all judgment. The skill
calls the CLI; the CLI never calls the skill.

---

## New Components

### 1. `lib/snapshot.sh` (NEW)

**What:** Snapshot and rollback primitives. Creates a full timestamped backup of
every path that `conjure adopt` will touch. Provides a rollback function to restore
from that snapshot. Used exclusively by `scripts/adopt.sh`.

**Why a lib, not inline:** Snapshot logic is reusable across `adopt` and any future
commands that need pre-operation backups. Follows the same lib pattern as `mutate.sh`
and `merge.sh` — sourced, not dispatched.

**Functions:**

```bash
# snapshot_create <target_dir> <backup_root>
# Creates: <backup_root>/conjure-adopt-<YYYYMMDD-HHMMSS>/
# Copies the entire working state: CLAUDE.md + .claude/ + any RESTRUCTURE-LOG.md
# Returns the snapshot path in CONJURE_SNAPSHOT_PATH (module-level var).
# In dry-run: prints [dry-run] would snapshot <target_dir>, skips actual copy.
snapshot_create() { ... }

# snapshot_rollback <snapshot_path> <target_dir>
# Restores from snapshot: replaces CLAUDE.md, .claude/, RESTRUCTURE-LOG.md
# with the snapshotted versions. Appends a "ROLLBACK" entry to RESTRUCTURE-LOG.md.
# In dry-run: prints [dry-run] would rollback from <snapshot_path>.
snapshot_rollback() { ... }

# snapshot_list <target_dir> <backup_root>
# Prints available snapshots sorted newest-first. Used by --rollback flag.
snapshot_list() { ... }
```

**Module-level state:**
```bash
CONJURE_SNAPSHOT_PATH=""   # set by snapshot_create; read by --rollback
```

**Backup location:** `<target_dir>/.conjure-adopt-backups/conjure-adopt-<timestamp>/`
Not `.claude/` — keeps it separate from the harness content. Gitignore entry added
by `adopt.sh` on first run.

**Implementation notes:**
- Uses `cp -R` for the copy (not mutate_cp) because snapshot_create is itself the
  safety primitive that precedes all mutate_* calls. If snapshot_create fails, no
  mutations proceed.
- Rollback uses `mutate_write` for RESTRUCTURE-LOG.md entry; uses `cp -R` for
  directory restore (mutate_cp does not recurse atomically enough for restore).
- `set -e` guard: any failure in snapshot_create exits the `adopt.sh` pipeline
  immediately via `|| { log_fail "Snapshot failed — aborting"; exit 1; }`.

**New file:** `lib/snapshot.sh`

---

### 2. `lib/inventory.sh` (NEW)

**What:** Walk the target repo and classify every markdown file into one of five
categories. Emit a JSON manifest (`adopt-manifest.json`) that the restructure skill
reads to understand the current doc ecosystem without needing to walk the filesystem
itself.

**Why a lib:** Inventory is read-only (no mutations). Separating it from `adopt.sh`
makes it independently testable and reusable. The restructure skill also calls
`conjure adopt --inventory` to refresh the manifest mid-session.

**Functions:**

```bash
# inventory_scan <target_dir>
# Walks <target_dir> for all .md files (find, POSIX, depth-limited to avoid
# .git, node_modules, .conjure-adopt-backups).
# Classifies each file and populates CONJURE_INVENTORY_ITEMS (newline-delimited
# internal state for POSIX bash 3.2 compat — no associative arrays).
# Returns count of files found in CONJURE_INVENTORY_COUNT.
inventory_scan() { ... }

# inventory_classify <filepath> <target_dir>
# Returns a classification tag via stdout. One of:
#   harness-core       — CLAUDE.md, .claude/settings.json
#   harness-skill      — .claude/skills/*/SKILL.md
#   harness-agent      — .claude/agents/*.md
#   harness-hook       — .claude/hooks/*.mjs
#   planning-gsd       — .planning/**/*.md
#   reference-linked   — explicitly linked from CLAUDE.md via [text](path)
#   candidate-skill    — >20 lines, domain-specific, not already a skill
#   candidate-agent    — contains "subagent" or "agent:" in frontmatter
#   doc-reference      — docs/, README.md, ADRs, runbooks
#   stale-candidate    — not linked, not referenced in 90+ days git log,
#                         or explicitly named stale/archive/deprecated in path
#   unclassified       — anything else
inventory_classify() { ... }

# inventory_emit_manifest <target_dir> <output_path>
# Writes adopt-manifest.json to <output_path>.
# In dry-run: prints [dry-run] would write <output_path>, writes to /tmp instead
#   so the skill can still read it without modifying the working tree.
inventory_emit_manifest() { ... }
```

**Manifest JSON schema** (see dedicated section below).

**Classification logic:**
- `harness-core`: path matches `CLAUDE.md` (root) or `.claude/settings.json`
- `harness-skill`: path matches `.claude/skills/*/SKILL.md`
- `harness-agent`: path matches `.claude/agents/*.md`
- `harness-hook`: path matches `.claude/hooks/*.mjs`
- `planning-gsd`: path has `.planning/` prefix
- `reference-linked`: grep CLAUDE.md for `](path)` markdown link to this file
- `candidate-skill`: wc -l > 20 AND not already harness-skill AND not planning-gsd
  AND file contains at least one heading (`^#`) — heuristic; skill surfaces for judgment
- `candidate-agent`: grep frontmatter for `subagent:` or path is `*/agents/*`
- `doc-reference`: path is `docs/`, `README.md`, `CHANGELOG.md`, `*.adr.md`,
  `ARCHITECTURE.md` outside `.claude/`
- `stale-candidate`: `git log --since=90.days -- <path>` returns no commits AND
  path is not `reference-linked` AND not `harness-*`
- `unclassified`: fallback

**Stale detection dependency:** `git log` (already a hard dep in the repo). If target
is not a git repo, stale-candidate detection is skipped; files fall through to
`unclassified`.

**New file:** `lib/inventory.sh`

---

### 3. Manifest JSON Schema (`adopt-manifest.json`)

Written to `<target_dir>/adopt-manifest.json` by `inventory_emit_manifest`. Read by
the restructure skill. Not written into `.claude/` — lives at repo root so the skill
can reference it with a simple `Read` tool call.

```json
{
  "schema_version": "1",
  "generated_at": "2026-05-28T14:23:00Z",
  "conjure_version": "0.6.0",
  "target": "/abs/path/to/repo",
  "snapshot_path": "/abs/path/to/.conjure-adopt-backups/conjure-adopt-20260528-142300",
  "summary": {
    "total_files": 2180,
    "harness_core": 1,
    "harness_skill": 17,
    "harness_agent": 6,
    "harness_hook": 5,
    "planning_gsd": 35,
    "reference_linked": 12,
    "candidate_skill": 48,
    "candidate_agent": 3,
    "doc_reference": 94,
    "stale_candidate": 203,
    "unclassified": 1756
  },
  "files": [
    {
      "path": "CLAUDE.md",
      "classification": "harness-core",
      "line_count": 180,
      "size_bytes": 21504,
      "cap_exceeded": true,
      "cap_limit": 100,
      "git_age_days": 14,
      "linked_from": [],
      "links_to": [
        ".claude/skills/architecture/SKILL.md",
        "docs/ARCHITECTURE.md"
      ]
    },
    {
      "path": ".claude/skills/architecture/SKILL.md",
      "classification": "harness-skill",
      "line_count": 87,
      "size_bytes": 3200,
      "cap_exceeded": false,
      "cap_limit": 200,
      "git_age_days": 30,
      "linked_from": ["CLAUDE.md"],
      "links_to": []
    }
  ],
  "size_cap_violations": [
    {
      "path": "CLAUDE.md",
      "line_count": 180,
      "cap": 100,
      "overage": 80
    }
  ],
  "at_imports_detected": false,
  "harness_missing_layers": ["hooks"],
  "restructure_steps": []
}
```

**Field notes:**
- `summary.*` counts match the classification enum values (snake_case, not hyphenated)
- `files[].cap_exceeded`: true if `line_count > cap_limit` for the known type
- `files[].cap_limit`: 100 for harness-core (CLAUDE.md), 200 for harness-skill, 80 for harness-agent
- `harness_missing_layers`: populated by adopt.sh after comparing installed .claude/
  against expected four-layer structure; used to scaffold
- `restructure_steps`: empty at inventory time; populated by the restructure skill
  before returning it to the human for approval; CLI reads steps from this field
  when `--apply-step` is called
- `at_imports_detected`: true if `grep -q '^@' CLAUDE.md` (anti-pattern detection,
  reuses audit-setup.sh logic)
- `git_age_days`: days since last commit touching this file; -1 if no git history

---

### 4. `scripts/adopt.sh` (NEW)

**What:** Main worker for `conjure adopt`. Orchestrates the full adopt pipeline.
Sourced `lib/mutate.sh`, `lib/snapshot.sh`, `lib/inventory.sh`. Dispatches to
`scripts/audit-setup.sh` for size-cap reuse. Called by `cmd_adopt` in `cli/conjure`.

**Interface (called by cmd_adopt):**

```
conjure adopt [--dry-run] [--rollback [<snapshot>]] [--force] [target]
conjure adopt --inventory [--dry-run] [target]      # re-run inventory only; refresh manifest
conjure adopt --apply-step <step-id> [--dry-run] [target]   # apply one restructure step
conjure adopt --status [target]                     # print current log tail + available rollbacks
```

**Main adopt pipeline (when no special flag):**

```
Step 0: Preconditions
  git -C $target diff --quiet && git -C $target diff --cached --quiet
    → dirty tree → abort unless --force
  [ -d $target/.claude ] or CLAUDE.md exists → brownfield confirmed
  (if neither → suggest conjure init instead)

Step 1: Snapshot backup
  source lib/snapshot.sh
  snapshot_create $target $target/.conjure-adopt-backups
  → CONJURE_SNAPSHOT_PATH set
  → log_step SNAPSHOT "created at $CONJURE_SNAPSHOT_PATH"

Step 2: Inventory + manifest
  source lib/inventory.sh
  inventory_scan $target
  inventory_emit_manifest $target $target/adopt-manifest.json
  → log_step INVENTORY "scanned $CONJURE_INVENTORY_COUNT files; manifest at adopt-manifest.json"

Step 3: Scaffold missing harness layers
  Read harness_missing_layers from manifest
  For each missing layer: call the appropriate scaffold fragment
    (reuses logic from init-project.sh — don't duplicate, source a shared fragment)
  All scaffolding via mutate_mkdir + mutate_cp
  → log_step SCAFFOLD "added missing layers: <list>"

Step 4: Size-cap audit
  CONJURE_HOME=$CONJURE_HOME bash $CONJURE_HOME/scripts/audit-setup.sh $target
  Capture exit code: 0 = pass, 1 = warnings, 2 = errors
  → log_step AUDIT "exit=$rc; $n violations"
  (adopt continues regardless — restructure skill handles remediation)

Step 5: Summary + next steps
  Print: manifest location, snapshot location, violation summary, how to run restructure skill
  → log_step COMPLETE "adopt phase 1 done; run restructure skill next"
```

**`--rollback` flag:**

```
conjure adopt --rollback [<snapshot-path>] [target]

If <snapshot-path> omitted: call snapshot_list to show available snapshots, prompt user to select.
If <snapshot-path> given: call snapshot_rollback $snapshot_path $target.
Always writes ROLLBACK entry to RESTRUCTURE-LOG.md.
```

**`--apply-step <step-id>` flag (called by restructure skill):**

```
conjure adopt --apply-step <step-id> [target]

Reads adopt-manifest.json → finds step with id=<step-id> in restructure_steps[].
Validates: step.status == "approved" (else exit 1 with error)
Executes the step's operation (see step schema below).
Writes result back to adopt-manifest.json restructure_steps[].status = "applied".
Appends to RESTRUCTURE-LOG.md.
```

**Step operation types (executed by `--apply-step`):**
- `write-file`: `mutate_write <path> <content>` — write new content to a file
- `move-to-skill`: `mutate_mkdir` + `mutate_write` + `mutate_rm` — extract section
  from CLAUDE.md into a new skill; remove from CLAUDE.md
- `archive-file`: `mutate_mkdir .claude/archive` + `mutate_cp src archive/` +
  `mutate_rm src` — archive instead of delete (never-delete rule)
- `scaffold-skill`: `mutate_mkdir` + `mutate_write` — create a new skill stub
- `update-claude-md`: `mutate_write CLAUDE.md <new-content>` — replace CLAUDE.md
  entirely with a new condensed version

**New file:** `scripts/adopt.sh`

**Reuse from existing scripts:**
- `scripts/audit-setup.sh` — called as subprocess for size-cap audit (Step 4);
  not re-implemented
- `scripts/init-project.sh` scaffold fragments — adopt.sh sources the same
  mutate_mkdir/mutate_cp patterns; for missing layer scaffolding, it calls
  `bash $CONJURE_HOME/scripts/init-project.sh existing $target` with guards
  (init-project.sh already skips existing files, so safe to re-run)

---

### 5. `lib/log.sh` (NEW)

**What:** Append-only RESTRUCTURE-LOG.md writer. All steps in the adopt pipeline
and all --apply-step executions write through this lib.

**Why a lib:** The log is written from both `adopt.sh` (pipeline steps) and from
the `--apply-step` handler. Centralizing it ensures consistent format, timestamp,
and dry-run behavior.

**Functions:**

```bash
# log_init <target_dir>
# Writes the RESTRUCTURE-LOG.md header if the file does not yet exist.
# Header includes: conjure version, timestamp, target path, snapshot path.
log_init() { ... }

# log_step <phase> <message>
# Appends one structured line to RESTRUCTURE-LOG.md.
# Format: [YYYY-MM-DD HH:MM:SS] [PHASE] message
# All writes via mutate_write --append.
log_step() { ... }

# log_fail <message>
# Appends a FAIL entry and exits 1. Used for abort conditions.
log_fail() { ... }
```

**RESTRUCTURE-LOG.md format:**

```markdown
# RESTRUCTURE-LOG — conjure adopt

conjure: 0.6.0
target: /abs/path/to/repo
started: 2026-05-28T14:23:00Z
snapshot: /abs/path/to/.conjure-adopt-backups/conjure-adopt-20260528-142300

---

[2026-05-28 14:23:01] [SNAPSHOT] created at .conjure-adopt-backups/conjure-adopt-20260528-142300
[2026-05-28 14:23:02] [INVENTORY] scanned 2180 files; manifest at adopt-manifest.json
[2026-05-28 14:23:03] [SCAFFOLD] added missing layers: hooks
[2026-05-28 14:23:04] [AUDIT] exit=1; 3 violations (see adopt-manifest.json size_cap_violations)
[2026-05-28 14:23:05] [COMPLETE] adopt phase 1 done; run restructure skill next

[2026-05-28 15:01:12] [APPLY] step=condense-claude-md status=applied op=update-claude-md
[2026-05-28 15:01:13] [APPLY] step=extract-skill-architecture status=applied op=move-to-skill
[2026-05-28 15:02:44] [APPLY] step=archive-stale-docs status=applied op=archive-file path=docs/old-notes.md

[2026-05-28 16:30:00] [ROLLBACK] restored from .conjure-adopt-backups/conjure-adopt-20260528-142300
```

**Why RESTRUCTURE-LOG.md and not RESTRUCTURE-LOG.jsonl:**
Markdown is human-readable in any editor, diffs cleanly in git, and is consistent
with conjure's existing audit artifacts. The structured `[TIMESTAMP] [PHASE] message`
format is machine-parseable with awk if needed, without requiring jq at read time.

**New file:** `lib/log.sh`

---

### 6. `templates/skills/restructure/SKILL.md` (NEW)

**What:** The in-session restructure skill. Loaded by Claude Code when the user
invokes restructure-related work. Reads the manifest and source docs; proposes a
restructure plan as numbered steps; requires human approval of each step before
executing; calls `conjure adopt --apply-step <id>` for each approved step.

**Location:** `templates/skills/restructure/SKILL.md`

**Why in `templates/skills/`:** This is a kit skill that `conjure adopt` installs
into `.claude/skills/restructure/SKILL.md` in the target project (as part of Step 3
scaffold). It lives in templates so that future `conjure update` 3-way merges can
propagate improvements to installed copies.

**Install path:** `scripts/adopt.sh` Step 3 copies it to
`$target/.claude/skills/restructure/SKILL.md` via `mutate_cp`. It is not part of
the standard `init-project.sh` scaffold (restructure is brownfield-only).

**Frontmatter:**

```yaml
---
name: restructure
description: >
  Restructure an oversized or cluttered repo into a clean conjure four-layer harness.
  Invoke when the user asks to tidy CLAUDE.md, consolidate docs, extract skills from
  existing docs, archive stale files, or run conjure adopt after init.
allowed-tools: [Read, Bash]
---
```

**Skill body structure (what the SKILL.md instructs Claude to do):**

1. **Load context:** Read `adopt-manifest.json`; if absent, tell user to run
   `conjure adopt` first. Read `RESTRUCTURE-LOG.md` to check for existing state.
2. **Read oversized files:** For each file in `files[]` with `cap_exceeded: true`,
   use the `Read` tool to load it.
3. **Propose restructure plan:** Emit a numbered list of steps. Each step specifies:
   - A human-readable description of what will change
   - The `op` type (write-file, move-to-skill, archive-file, scaffold-skill,
     update-claude-md)
   - The affected paths
   - Why (rationale referencing manifest data)
4. **Wait for human approval per step:** Present step N, wait for user to type
   "approve", "skip", or "edit". Never batch-approve; never proceed without
   explicit approval.
5. **Execute approved step:** Run `conjure adopt --apply-step <step-id> <target>`
   via the `Bash` tool. The step-id is written into `adopt-manifest.json`
   restructure_steps[] by the skill before calling the CLI.
6. **Report result:** Read `RESTRUCTURE-LOG.md` tail to confirm step applied;
   show diff summary.
7. **Repeat** for next step.
8. **Final audit:** Run `conjure audit <target>` to confirm clean state.

**Skill↔CLI callback path (how determinism is preserved):**

```
restructure skill (Claude in-session)
  → computes step content and id purely in-session (no FS writes)
  → writes step definition into adopt-manifest.json via:
       conjure adopt --update-manifest --step-json '<json>' <target>
       (single CLI call; all writes via mutate_write)
  → sets step status to "approved" in manifest via same primitive
  → calls: conjure adopt --apply-step <step-id> <target>
  → the CLI reads the step from manifest, validates status="approved",
    executes via mutate_* primitives, writes log entry
  → skill reads RESTRUCTURE-LOG.md to confirm and report result

The skill NEVER:
  - calls Write tool directly on project files
  - calls Edit tool directly on project files
  - calls Bash with direct cp/mv/rm commands
  - bypasses the CLI for any filesystem operation
```

**Why `Bash` tool but not `Write`/`Edit` tools in `allowed-tools`:**
Restricting to `[Read, Bash]` forces all mutations through the CLI, not through
Claude Code's own file-write tools. The CLI enforces DRY_RUN, logging, and the
mutate.sh chokepoint.

**New file:** `templates/skills/restructure/SKILL.md`

---

### 7. `--update-manifest` helper in `cmd_adopt`

**What:** A sub-operation of `conjure adopt` that lets the restructure skill write
a step definition into `adopt-manifest.json` without needing direct file access.
Accepts `--step-json '<json>'` and merges it into `restructure_steps[]`.

**Why needed:** The skill must communicate step definitions (content, op type,
affected paths) into the manifest atomically. A CLI-mediated write ensures:
- The step JSON is schema-validated before being written
- The write is logged
- The write respects DRY_RUN
- The skill cannot corrupt the manifest with a bad write

**Implementation:** Part of `cmd_adopt` dispatch in `cli/conjure`. Reads manifest
with `jq`, appends the step, writes back via `mutate_write`. Requires `jq` (already
a hard dep in preflight).

---

## Modified Components

### `cli/conjure` — MODIFIED (add `cmd_adopt`)

**Change — Add `cmd_adopt` function:**

```bash
cmd_adopt() {
  local target dryrun rollback_path apply_step force inventory_only
  local update_manifest step_json status_only
  target="$(pwd)"
  dryrun=0; rollback_path=""; apply_step=""; force=0
  inventory_only=0; update_manifest=0; step_json=""; status_only=0

  while [ $# -gt 0 ]; do
    case "$1" in
      --dry-run)         dryrun=1 ;;
      --force)           force=1 ;;
      --rollback)        shift; rollback_path="${1:-latest}" ;;
      --inventory)       inventory_only=1 ;;
      --apply-step)      shift; apply_step="${1:-}" ;;
      --update-manifest) update_manifest=1 ;;
      --step-json)       shift; step_json="${1:-}" ;;
      --status)          status_only=1 ;;
      --help|-h)         echo "Usage: conjure adopt [--dry-run] [--force] [--rollback [<snapshot>]] [--inventory] [--apply-step <id>] [--status] [target]"; return 0 ;;
      *)                 target="$1" ;;
    esac
    shift
  done

  cmd_preflight || return 1
  DRY_RUN="$dryrun" CONJURE_ADOPT_FORCE="$force" \
    CONJURE_ADOPT_ROLLBACK="$rollback_path" \
    CONJURE_ADOPT_APPLY_STEP="$apply_step" \
    CONJURE_ADOPT_INVENTORY_ONLY="$inventory_only" \
    CONJURE_ADOPT_UPDATE_MANIFEST="$update_manifest" \
    CONJURE_ADOPT_STEP_JSON="$step_json" \
    CONJURE_ADOPT_STATUS="$status_only" \
    CONJURE_HOME="$CONJURE_HOME" \
    bash "$CONJURE_HOME/scripts/adopt.sh" "$target"
}
```

Add dispatch: `adopt) shift; cmd_adopt "$@" ;;`
Add `conjure adopt` to the usage() heredoc.

**Change — `cmd_init` / `init-project.sh` scaffold fragment extraction:**
`init-project.sh` already skips existing files. `adopt.sh` can call
`bash $CONJURE_HOME/scripts/init-project.sh existing $target` to scaffold missing
layers. No change to `init-project.sh` needed — idempotency is already the
contract. This is CONFIRMED by reading lines 42-82 of `scripts/init-project.sh`
(all writes are guarded with `[ ! -f ... ]` or `[ ! -d ... ]`).

---

### `lib/mutate.sh` — NO CHANGE

`mutate_rm` was added in v0.5.0 and is already present (confirmed at read time:
lines 67-77 of `lib/mutate.sh`). The v0.6.0 components source `lib/mutate.sh`
and use the existing four functions unchanged. No additions needed.

---

### `scripts/audit-setup.sh` — NO CHANGE

Called as a subprocess by `adopt.sh` (Step 4) to perform size-cap and schema
validation. The existing interface (`bash audit-setup.sh [target]`, exit 0/1/2)
is sufficient. No modifications needed.

---

### `templates/` directory structure — MODIFIED (add restructure skill)

Add: `templates/skills/restructure/SKILL.md`

This is the only template addition. The restructure skill is not added to the
standard init scaffold (it is brownfield-only). It is installed by `adopt.sh`
Step 3 via `mutate_cp`.

---

### `.gitignore` / `.claudeignore` — MODIFIED

`adopt.sh` adds `.conjure-adopt-backups/` to `.gitignore` and `.claudeignore`
if not already present. Uses `mutate_write --append`. This prevents snapshot
backup directories from being committed or read by Claude.

---

## Data Flow: End-to-End

```
USER: conjure adopt [--dry-run] [target]
  │
  ▼
cli/conjure cmd_adopt
  │  parse flags → set env vars
  │  cmd_preflight (verify jq, git, bash deps)
  ▼
scripts/adopt.sh $target
  │
  ├─ Step 0: Preconditions
  │    git diff --quiet && git diff --cached --quiet
  │    (dirty tree → abort unless --force)
  │    confirm brownfield: CLAUDE.md or .claude/ exists
  │
  ├─ Step 1: Snapshot
  │    source lib/snapshot.sh
  │    source lib/log.sh
  │    log_init $target                           → create RESTRUCTURE-LOG.md header
  │    snapshot_create $target .conjure-adopt-backups
  │      cp -R CLAUDE.md .claude/ → backup dir
  │    log_step SNAPSHOT "created at $path"       → mutate_write --append RESTRUCTURE-LOG.md
  │
  ├─ Step 2: Inventory
  │    source lib/inventory.sh
  │    inventory_scan $target
  │      find $target -name '*.md' (POSIX, skip .git node_modules .conjure-adopt-backups)
  │      inventory_classify each file
  │    inventory_emit_manifest $target adopt-manifest.json
  │      jq construct → mutate_write adopt-manifest.json
  │    log_step INVENTORY "scanned N files"
  │
  ├─ Step 3: Scaffold missing layers
  │    read harness_missing_layers from manifest (jq)
  │    bash $CONJURE_HOME/scripts/init-project.sh existing $target
  │      (idempotent; skips existing; uses mutate_mkdir + mutate_cp)
  │    mutate_cp templates/skills/restructure/SKILL.md
  │              $target/.claude/skills/restructure/SKILL.md
  │    log_step SCAFFOLD "added: <layers>"
  │
  ├─ Step 4: Audit
  │    bash $CONJURE_HOME/scripts/audit-setup.sh $target
  │    log_step AUDIT "exit=$rc; $n violations"
  │
  └─ Step 5: Summary + next steps
       print: manifest path, snapshot path, violations, how to invoke restructure skill
       log_step COMPLETE "adopt phase 1 done"


USER: [opens Claude Code in target, restructure skill fires]
  │
  ▼
restructure skill (Claude in-session)
  │
  ├─ Read adopt-manifest.json                     → Bash: conjure adopt --inventory $target
  │    (or just Read tool if manifest is current) → Read: adopt-manifest.json
  │
  ├─ Read oversized CLAUDE.md + key source docs   → Read tool (allowed)
  │
  ├─ Propose restructure plan (N steps)
  │    [step 1] condense CLAUDE.md to ≤100 lines
  │    [step 2] extract architecture section → .claude/skills/architecture/SKILL.md
  │    [step 3] archive 203 stale files       → .claude/archive/<origname>
  │    ...
  │
  ├─ For each step, WAIT for human "approve" / "skip" / "edit"
  │
  ├─ On "approve":
  │    Build step JSON (id, op, content, paths)
  │    → Bash: conjure adopt --update-manifest --step-json '<json>' $target
  │         read manifest → jq append step → mutate_write adopt-manifest.json
  │         log_step UPDATE-MANIFEST "step=<id> registered"
  │    → Bash: conjure adopt --apply-step <id> $target
  │         read manifest → find step by id → validate status="approved"
  │         execute via mutate_* primitives (write-file / move-to-skill / archive-file / etc.)
  │         write step status="applied" to manifest (jq + mutate_write)
  │         log_step APPLY "step=<id> status=applied op=<op>"
  │    → Read: RESTRUCTURE-LOG.md (last 5 lines) to confirm
  │
  └─ Final: conjure audit $target
       → Bash: conjure audit $target
       → print result


USER: conjure adopt --rollback [target]
  │
  ▼
scripts/adopt.sh --rollback
  source lib/snapshot.sh
  source lib/log.sh
  snapshot_list $target .conjure-adopt-backups   → print available snapshots
  prompt (if no snapshot arg given): select snapshot
  snapshot_rollback $selected $target
    rm -rf CLAUDE.md .claude/ (live mode only)
    cp -R backup/CLAUDE.md backup/.claude/ → restore
  log_step ROLLBACK "restored from $path"
  echo "Rollback complete. Verify with: conjure audit $target"
```

---

## Component Interaction Map

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│  ENTRYPOINTS                                                                     │
│  ┌──────────────────────────────────────────────────────────────────────────┐   │
│  │  cli/conjure (bash dispatcher)                    [existing + MODIFIED]   │   │
│  │   ... all v0.5.0 subcommands unchanged ...                               │   │
│  │   adopt [--dry-run|--force|--rollback|--inventory|                       │   │
│  │          --apply-step|--update-manifest|--status]  [NEW — ADPT-*]       │   │
│  └──────────────────────────────────────────────────────────────────────────┘   │
├─────────────────────────────────────────────────────────────────────────────────┤
│  WORKER SCRIPTS (subprocess via bash scripts/*.sh)                              │
│  ┌─────────────────────┐  ┌─────────────────────────────────────────────────┐  │
│  │ ... v0.5.0 workers  │  │ adopt.sh                              [NEW]      │  │
│  │ (unchanged)         │  │  orchestrates full adopt pipeline               │  │
│  │                     │  │  sources: lib/mutate.sh lib/snapshot.sh         │  │
│  │                     │  │           lib/inventory.sh lib/log.sh           │  │
│  │                     │  │  calls:   scripts/init-project.sh (idempotent)  │  │
│  │                     │  │           scripts/audit-setup.sh (subprocess)   │  │
│  │                     │  │  writes:  adopt-manifest.json (via mutate_write) │  │
│  │                     │  │           RESTRUCTURE-LOG.md (via lib/log.sh)   │  │
│  │                     │  │  flags:   --dry-run --force --rollback          │  │
│  │                     │  │           --inventory --apply-step              │  │
│  │                     │  │           --update-manifest --status            │  │
│  └─────────────────────┘  └─────────────────────────────────────────────────┘  │
├─────────────────────────────────────────────────────────────────────────────────┤
│  SHARED LIB (sourced, not dispatched)                                           │
│  ┌──────────────────────────────────────────────────────────────────────────┐   │
│  │ lib/mutate.sh    [existing — UNCHANGED for v0.6.0]                       │   │
│  │  mutate_mkdir / mutate_cp / mutate_write / mutate_rm / mutate_summary    │   │
│  │  ALL filesystem mutations route here — invariant preserved               │   │
│  └──────────────────────────────────────────────────────────────────────────┘   │
│  ┌──────────────────────────────────────────────────────────────────────────┐   │
│  │ lib/snapshot.sh  [NEW]                                                   │   │
│  │  snapshot_create / snapshot_rollback / snapshot_list                    │   │
│  │  cp -R for create (pre-mutate safety) / mutate_write for log entry      │   │
│  └──────────────────────────────────────────────────────────────────────────┘   │
│  ┌──────────────────────────────────────────────────────────────────────────┐   │
│  │ lib/inventory.sh [NEW]                                                   │   │
│  │  inventory_scan / inventory_classify / inventory_emit_manifest           │   │
│  │  read-only scan + jq emit; mutate_write for manifest output              │   │
│  └──────────────────────────────────────────────────────────────────────────┘   │
│  ┌──────────────────────────────────────────────────────────────────────────┐   │
│  │ lib/log.sh       [NEW]                                                   │   │
│  │  log_init / log_step / log_fail                                          │   │
│  │  all writes via mutate_write --append (DRY_RUN honored)                  │   │
│  └──────────────────────────────────────────────────────────────────────────┘   │
│  ┌──────────────────────────────────────────────────────────────────────────┐   │
│  │ lib/merge.sh / lib/cost.sh / lib/exact-count.mjs [existing — unchanged] │   │
│  └──────────────────────────────────────────────────────────────────────────┘   │
├─────────────────────────────────────────────────────────────────────────────────┤
│  IN-SESSION SKILL (Claude Code, human-gated)                                    │
│  ┌──────────────────────────────────────────────────────────────────────────┐   │
│  │ templates/skills/restructure/SKILL.md  [NEW]                             │   │
│  │  installed to: .claude/skills/restructure/SKILL.md by adopt.sh Step 3   │   │
│  │  allowed-tools: [Read, Bash] — NO Write or Edit tool access              │   │
│  │  all mutations via: conjure adopt --update-manifest / --apply-step       │   │
│  │  human-gated: approve/skip/edit per step before any Bash call            │   │
│  └──────────────────────────────────────────────────────────────────────────┘   │
├─────────────────────────────────────────────────────────────────────────────────┤
│  ARTIFACTS (per-repo, not in conjure kit)                                       │
│  adopt-manifest.json         — inventory output; restructure_steps[] state      │
│  RESTRUCTURE-LOG.md          — append-only step audit trail                     │
│  .conjure-adopt-backups/     — snapshot backups (gitignored)                    │
│  .claude/skills/restructure/ — installed restructure skill (gitignored optional)│
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

## New vs Modified Files — Explicit List

### NEW FILES

| File | Type | Purpose |
|------|------|---------|
| `lib/snapshot.sh` | library | snapshot_create / snapshot_rollback / snapshot_list primitives |
| `lib/inventory.sh` | library | inventory_scan / inventory_classify / inventory_emit_manifest |
| `lib/log.sh` | library | log_init / log_step / log_fail → RESTRUCTURE-LOG.md |
| `scripts/adopt.sh` | worker | full adopt pipeline; dispatches to new libs + existing scripts |
| `templates/skills/restructure/SKILL.md` | skill template | restructure skill; installed by adopt.sh Step 3 |

### MODIFIED FILES

| File | Change | Why |
|------|--------|-----|
| `cli/conjure` | add `cmd_adopt` function + `adopt` dispatch entry + usage() update | new subcommand |
| `templates/` (structure) | add `skills/restructure/` directory | new skill template |

### UNCHANGED FILES (confirmed)

| File | Reason |
|------|--------|
| `lib/mutate.sh` | `mutate_rm` already present (v0.5.0); API is complete for v0.6.0 |
| `lib/merge.sh` | no changes needed; not involved in adopt pipeline |
| `scripts/audit-setup.sh` | called as subprocess; existing interface sufficient |
| `scripts/init-project.sh` | called as subprocess for scaffold; idempotent contract already correct |
| `scripts/preflight.sh` | jq already a listed dependency; no new hard deps |
| all other scripts | not involved in adopt flow |

---

## Dependency-Ordered Build Sequence

Dependencies are explicit. Each step lists what it requires and what it unblocks.

### Step 1 — `lib/log.sh`

**Why first:** `adopt.sh` needs logging from the start (including failure logging).
`lib/snapshot.sh` also appends log entries on rollback. Zero external dependencies —
only `lib/mutate.sh` (already shipped). Write the functions + RESTRUCTURE-LOG.md
format + tests for log_init / log_step / log_fail immediately.

Requires: `lib/mutate.sh` (shipped)
Unblocks: Steps 2, 3, 4

---

### Step 2 — `lib/snapshot.sh`

**Why second:** `adopt.sh` calls `snapshot_create` as the very first mutation-guarded
action. Must exist before `adopt.sh` can be written. `log_step` is called inside
`snapshot_create` so `lib/log.sh` must precede it.

Requires: `lib/mutate.sh` (shipped), `lib/log.sh` (Step 1)
Unblocks: Step 4 (`adopt.sh` rollback path)

---

### Step 3 — `lib/inventory.sh` + manifest JSON schema

**Why third:** `adopt.sh` calls inventory after snapshot. Manifest schema must be
finalized before both inventory (writer) and restructure skill (reader) are written.
`lib/log.sh` must precede it for `inventory_emit_manifest` log entries.

Requires: `lib/mutate.sh` (shipped), `lib/log.sh` (Step 1), `jq` (already preflight dep)
Unblocks: Steps 4, 5 (skill reads manifest schema)

---

### Step 4 — `scripts/adopt.sh` + `cmd_adopt` in `cli/conjure`

**Why fourth:** Depends on all three new libs. `adopt.sh` is the pipeline orchestrator
and cannot be written until its dependencies exist. `cmd_adopt` in `cli/conjure` is a
thin wrapper — write it in the same step. Add `--dry-run` path first, live path second
(easier to test). Tests cover: git-clean gate, dry-run output, snapshot creation,
inventory output, scaffold idempotency, rollback.

Requires: Steps 1–3 + `scripts/init-project.sh` (shipped) + `scripts/audit-setup.sh` (shipped)
Unblocks: Step 5 (skill needs the CLI adopt primitives to call back into)

---

### Step 5 — `templates/skills/restructure/SKILL.md`

**Why fifth:** The skill's `--apply-step` and `--update-manifest` callback paths in
`conjure adopt` must exist and be tested before the skill is finalized. Writing the
skill after the CLI ensures the callback commands documented in the skill actually work.
Skill content is markdown/prose — fast to write once the CLI contract is locked.

Requires: Step 4 (`conjure adopt --apply-step`, `--update-manifest` working)
Unblocks: end-to-end brownfield adoption user story

---

### Step 6 — Integration tests for the full adopt + restructure loop

**Why last:** Add fixture (`tests/fixtures/brownfield-argus/`) that simulates the
argus stress case (oversized CLAUDE.md + doc sprawl). Test: adopt --dry-run output,
adopt live run, manifest schema validation, --rollback restores state, --apply-step
executes and logs correctly.

Requires: Steps 1–5 complete
Unblocks: CI coverage of the new capability

---

### Build order summary table

| Step | Work item | New / Modified files | Key dependency | Unblocks |
|------|-----------|----------------------|----------------|----------|
| 1 | `lib/log.sh` — append-only RESTRUCTURE-LOG.md writer | `lib/log.sh` (N) | `lib/mutate.sh` (shipped) | Steps 2, 3, 4 |
| 2 | `lib/snapshot.sh` — snapshot/rollback primitives | `lib/snapshot.sh` (N) | Step 1 | Step 4 (rollback) |
| 3 | `lib/inventory.sh` — inventory + classifier + manifest schema | `lib/inventory.sh` (N) | Steps 1, jq dep | Steps 4, 5 |
| 4 | `scripts/adopt.sh` + `cmd_adopt` in `cli/conjure` | `scripts/adopt.sh` (N), `cli/conjure` (M) | Steps 1–3, init-project.sh, audit-setup.sh | Step 5 |
| 5 | `templates/skills/restructure/SKILL.md` | `templates/skills/restructure/SKILL.md` (N) | Step 4 (CLI primitives locked) | full UX complete |
| 6 | Integration tests (argus fixture) | `tests/fixtures/brownfield-argus/` (N), `tests/run.sh` (M) | Steps 1–5 | CI coverage |

N = New file, M = Modified file

---

## Anti-Patterns to Avoid

### Anti-Pattern 1: Restructure skill using Write/Edit tools directly

**What people do:** Allow the restructure skill to call Claude Code's `Write` or
`Edit` tools to modify `CLAUDE.md` or create skill files directly.
**Why it's wrong:** Bypasses `lib/mutate.sh`, breaking DRY_RUN gating and the
audit log. RESTRUCTURE-LOG.md becomes incomplete. Rollback cannot recover writes
that were not routed through the snapshot-then-mutate path.
**Do this instead:** The skill's `allowed-tools` is `[Read, Bash]`. All FS changes
call `conjure adopt --apply-step` or `conjure adopt --update-manifest`. The CLI is
the only write path.

---

### Anti-Pattern 2: `snapshot_create` using `mutate_cp`

**What people do:** Route the snapshot backup itself through `mutate_cp` to honor
DRY_RUN.
**Why it's wrong:** `snapshot_create` is the safety primitive that precedes all
`mutate_*` calls. If the snapshot is suppressed by DRY_RUN, the subsequent live
mutations have no backup. The snapshot must always execute (or the whole pipeline
must abort in dry-run before mutations).
**Do this instead:** `snapshot_create` uses raw `cp -R` (not `mutate_cp`) and is
always unconditionally executed in live mode. In dry-run mode, `adopt.sh` suppresses
all downstream `mutate_*` calls (via `DRY_RUN=1`) but still reports what the snapshot
path would be. Specifically: in dry-run, `snapshot_create` prints the would-be path
but does not call `cp -R`.

---

### Anti-Pattern 3: Writing the manifest via shell heredoc/printf directly

**What people do:** `printf '%s' "$json_content" > adopt-manifest.json` in `inventory.sh`.
**Why it's wrong:** Bypasses `lib/mutate.sh`; DRY_RUN is not honored; `--dry-run`
would still write the manifest.
**Do this instead:** `inventory_emit_manifest` calls `mutate_write` for the final
manifest write. In dry-run, it writes to a temp path (`/tmp/adopt-manifest-dryrun.json`)
so the restructure skill can still read the dry-run inventory.

---

### Anti-Pattern 4: Blocking adopt on a dirty git working tree without --force

**What people do:** Skip the git-clean precondition to make adopt "more convenient".
**Why it's wrong:** If adopt mutates files while the tree is dirty and then something
fails mid-pipeline, the user's uncommitted changes are mixed with conjure's changes.
Rollback cannot cleanly separate them.
**Do this instead:** `adopt.sh` exits with a clear error message ("working tree is
dirty — commit or stash changes first, or use --force") unless `--force` is passed.
`--force` is documented as "at your own risk; rollback may not fully separate your
changes from conjure's changes".

---

### Anti-Pattern 5: Deleting files during restructure

**What people do:** `mutate_rm` on doc files classified as `stale-candidate` to "clean up".
**Why it's wrong:** The never-delete rule is a hard constraint. Stale-candidate
classification is a heuristic based on git age and link analysis — it can be wrong.
Permanent deletion without confirmation violates the project's safety contract.
**Do this instead:** The `archive-file` operation type moves files to
`.claude/archive/<original-path-encoded>`. The original path is preserved in the
manifest. Archived files can be recovered manually or via `--rollback`. No `mutate_rm`
is ever called on user-owned content files.

---

### Anti-Pattern 6: `adopt.sh` re-implementing scaffold logic from `init-project.sh`

**What people do:** Duplicate the `mutate_mkdir .claude/skills` + `mutate_cp ...`
sequence in `adopt.sh` for scaffold.
**Why it's wrong:** Any changes to the scaffold (new skill templates, new hooks) must
be maintained in two places. `init-project.sh` is already well-tested and idempotent.
**Do this instead:** `adopt.sh` Step 3 calls
`bash $CONJURE_HOME/scripts/init-project.sh existing $target` — this is already
idempotent (all writes guarded with `[ ! -f ]` / `[ ! -d ]`). The restructure skill
install is the only adopt-specific addition on top.

---

## Integration Points

### lib/mutate.sh chokepoint (unchanged invariant)

All v0.6.0 file-writing paths route through `lib/mutate.sh`:
- `adopt.sh` sources `lib/mutate.sh` and uses `mutate_mkdir`, `mutate_cp`,
  `mutate_write` throughout
- `lib/log.sh` uses `mutate_write --append` for all log entries
- `lib/inventory.sh` uses `mutate_write` for manifest output
- `lib/snapshot.sh` uses `mutate_write` only for the log entry on rollback;
  the snapshot `cp -R` is intentionally not routed through `mutate_cp`
  (see Anti-Pattern 2)
- The restructure skill never calls `mutate_*` directly; it calls the CLI
  which internally sources `lib/mutate.sh`

### adopt.sh → audit-setup.sh (Step 4 reuse)

`scripts/audit-setup.sh` is called as a subprocess with the target as argument.
Exit codes: 0 = all pass, 1 = warnings, 2 = errors (hard violations). `adopt.sh`
captures the exit code and logs it; it does not abort on audit failure because the
purpose of adopt is to surface and remediate violations, not to gate on them.

### adopt.sh → init-project.sh (Step 3 reuse)

`scripts/init-project.sh` called in `existing` mode as a subprocess. Already
idempotent — every file write is guarded. Adopt passes the same `$target` and
`CONJURE_HOME` / `DRY_RUN` env vars. The restructure skill install (`mutate_cp
templates/skills/restructure/ $target/.claude/skills/restructure/`) is done
directly in `adopt.sh` after init-project.sh returns.

### Restructure skill → conjure adopt --apply-step (callback contract)

The restructure skill's callback path is:

```
1. Skill computes step definition in-session (pure computation, no FS)
2. Skill calls: Bash → conjure adopt --update-manifest --step-json '<json>' $target
      adopt.sh: jq read manifest → append step → mutate_write manifest
      log_step UPDATE-MANIFEST "step=<id> registered"
      returns 0 on success
3. Skill calls: Bash → conjure adopt --apply-step <step-id> $target
      adopt.sh: jq read manifest → find step by id
      validate: step.status must be "approved"
      execute: mutate_write / mutate_cp / mutate_mkdir / mutate_rm per op type
      jq update manifest: step.status = "applied"
      mutate_write manifest (updated)
      log_step APPLY "step=<id> status=applied"
      returns 0 on success, 1 on validation failure
4. Skill calls: Read → RESTRUCTURE-LOG.md (last N lines to confirm)
```

**Why the skill sets `approved` status:** The skill writes the step with
`status: "approved"` in the JSON it passes to `--update-manifest`. The CLI only
executes steps with `status: "approved"`. This means a step that is registered but
not approved (e.g., the user said "skip") will never execute if `--apply-step` is
called on it — the CLI rejects it. This is an additional safety gate beyond the
human approval in the skill session.

### Version stamp chain (unchanged, not extended for v0.6.0)

`adopt.sh` reads `.claude/.conjure-version` for informational purposes (to include
in the manifest) but does not modify it. Version stamping remains the domain of
`cmd_init` and `cmd_update --apply`.

---

## Architecture Diagram (v0.6.0 additions highlighted)

```
┌────────────────────────────────────────────────────────────────────────────────────┐
│  ENTRYPOINTS                                                                        │
│  ┌─────────────────────────────────────────────────────────────────────────────┐   │
│  │  cli/conjure  (bash dispatcher)                         [existing + MODIFIED]│   │
│  │   init / migrate / audit / update / check / resolve                        │   │
│  │   refresh-graph / refresh-overlay / install-mcp                            │   │
│  │   preflight / publish / publish-skill                                      │   │
│  │   adopt [--dry-run|--force|--rollback|--inventory|                         │   │
│  │          --apply-step|--update-manifest|--status]    [NEW — v0.6.0]       │   │
│  └─────────────────────────────────────────────────────────────────────────────┘   │
│  ┌─────────────────────────────────────────────────────────────────────────────┐   │
│  │  cli/conjure.ps1  (PowerShell shim)                   [existing — unchanged]│   │
│  └─────────────────────────────────────────────────────────────────────────────┘   │
├────────────────────────────────────────────────────────────────────────────────────┤
│  WORKER SCRIPTS                                                                     │
│  ┌───────────────────────────┐   ┌─────────────────────────────────────────────┐  │
│  │ v0.5.0 workers (unchanged)│   │ adopt.sh                          [NEW]      │  │
│  │  init-project.sh ──┐      │   │  Step 0: git-clean precondition             │  │
│  │  audit-setup.sh ───┼──────┼───┤  Step 1: snapshot_create                    │  │
│  │  check.sh          │      │   │  Step 2: inventory_scan + emit_manifest     │  │
│  │  resolve.sh        │      │   │  Step 3: init-project.sh (subprocess) +    │  │
│  │  update-pr.sh      │      │   │          install restructure skill          │  │
│  │  publish-*.sh      │      │   │  Step 4: audit-setup.sh (subprocess)       │  │
│  └───────────────────────────┘   │  Step 5: summary + next-steps msg          │  │
│                                   │  Flags:  --rollback → snapshot_rollback    │  │
│                                   │          --inventory → re-scan only        │  │
│                                   │          --apply-step → execute one step   │  │
│                                   │          --update-manifest → write step def│  │
│                                   └─────────────────────────────────────────────┘  │
├────────────────────────────────────────────────────────────────────────────────────┤
│  SHARED LIB (sourced, not dispatched)                                              │
│  ┌──────────────────────────────────────────────────────────────────────────────┐  │
│  │ lib/mutate.sh   [existing — UNCHANGED]                                       │  │
│  │  mutate_mkdir / mutate_cp / mutate_write / mutate_rm / mutate_summary        │  │
│  │  THE write chokepoint — ALL mutations route here                            │  │
│  └──────────────────────────────────────────────────────────────────────────────┘  │
│  ┌──────────────────────────────────────────────────────────────────────────────┐  │
│  │ lib/snapshot.sh  [NEW — v0.6.0]                                              │  │
│  │  snapshot_create (cp -R before any mutate_*) / snapshot_rollback /           │  │
│  │  snapshot_list                                                               │  │
│  └──────────────────────────────────────────────────────────────────────────────┘  │
│  ┌──────────────────────────────────────────────────────────────────────────────┐  │
│  │ lib/inventory.sh [NEW — v0.6.0]                                              │  │
│  │  inventory_scan / inventory_classify / inventory_emit_manifest              │  │
│  │  → writes adopt-manifest.json via mutate_write                              │  │
│  └──────────────────────────────────────────────────────────────────────────────┘  │
│  ┌──────────────────────────────────────────────────────────────────────────────┐  │
│  │ lib/log.sh       [NEW — v0.6.0]                                              │  │
│  │  log_init / log_step / log_fail                                              │  │
│  │  → writes RESTRUCTURE-LOG.md via mutate_write --append                      │  │
│  └──────────────────────────────────────────────────────────────────────────────┘  │
│  ┌──────────────────────────────────────────────────────────────────────────────┐  │
│  │ lib/merge.sh / lib/cost.sh / lib/exact-count.mjs [existing — unchanged]    │  │
│  └──────────────────────────────────────────────────────────────────────────────┘  │
├────────────────────────────────────────────────────────────────────────────────────┤
│  IN-SESSION SKILL (Claude Code, human-gated, read+bash only)                      │
│  ┌──────────────────────────────────────────────────────────────────────────────┐  │
│  │ .claude/skills/restructure/SKILL.md    (installed by adopt.sh Step 3)       │  │
│  │ template: templates/skills/restructure/SKILL.md  [NEW — v0.6.0]             │  │
│  │  allowed-tools: [Read, Bash]   ← no Write or Edit                           │  │
│  │  reads:  adopt-manifest.json, RESTRUCTURE-LOG.md, source docs               │  │
│  │  writes: via conjure adopt --update-manifest (step def) +                   │  │
│  │               conjure adopt --apply-step (execution)                        │  │
│  │  human-gated: approve/skip/edit per step — NEVER batch-approves             │  │
│  └──────────────────────────────────────────────────────────────────────────────┘  │
├────────────────────────────────────────────────────────────────────────────────────┤
│  PER-REPO ARTIFACTS (written into target, not kit source)                         │
│  adopt-manifest.json         — inventory output; restructure_steps[] state         │
│  RESTRUCTURE-LOG.md          — append-only step audit trail (per session)          │
│  .conjure-adopt-backups/     — snapshot dirs (gitignored by adopt.sh)              │
│  .claude/skills/restructure/ — installed restructure skill                         │
└────────────────────────────────────────────────────────────────────────────────────┘

Adopt pipeline data flow (critical path):
  git-clean gate
    → snapshot_create → RESTRUCTURE-LOG.md header
      → inventory_scan → adopt-manifest.json
        → init-project.sh (idempotent scaffold)
          → audit-setup.sh (size-cap check; subprocess)
            → summary + next steps message

Skill callback data flow:
  skill (Read adopt-manifest.json)
    → human approves step
      → conjure adopt --update-manifest --step-json (write step def to manifest)
        → conjure adopt --apply-step <id> (execute via mutate_*)
          → Read RESTRUCTURE-LOG.md tail (confirm)
```

---

## Sources

- `cli/conjure` (full content read this session — lines 1-477) — HIGH confidence
- `lib/mutate.sh` (full content read this session) — HIGH confidence
- `lib/merge.sh` (full content read this session) — HIGH confidence
- `scripts/init-project.sh` (full content read this session) — HIGH confidence
- `scripts/audit-setup.sh` (lines 1-80 read this session) — HIGH confidence
- `.planning/PROJECT.md` v0.6.0 requirements (read this session) — HIGH confidence
- `.planning/research/ARCHITECTURE.md` v0.5.0 (read this session; carried forward) — HIGH confidence
- `templates/skills/_anatomy/SKILL.md` (frontmatter schema confirmed this session) — HIGH confidence

---
*Architecture research for: Conjure v0.6.0 Safe Brownfield Adoption integration*
*Researched: 2026-05-28*
