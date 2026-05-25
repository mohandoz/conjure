# Phase 10: Marketplace Publish - Research

**Researched:** 2026-05-25
**Domain:** Claude Code Plugin System — manifest validation, marketplace schema, CI integration, bash CLI scripting
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** Both jq schema validation AND `claude plugin validate .` run in CI. Belt-and-suspenders: jq validates marketplace.json + plugin.json (fast, no deps); claude CLI validates separately.
- **D-02:** Install the official Anthropic claude CLI via their official install script in ci.yml. If installation fails, CI fails — no silent skips.
- **D-03:** The exact behavior of `claude plugin validate .` (which files it targets) must be determined by the researcher. (RESOLVED — see Standard Stack below.)
- **D-04:** The researcher must study the Anthropic community catalog format and determine the canonical schema before touching the existing file. (RESOLVED — current marketplace.json is structurally wrong and MUST be restructured.)
- **D-05:** `conjure publish` writes HEAD SHA (`git rev-parse HEAD`) to the install field in marketplace.json AND updates the `version` field in both `marketplace.json` and `plugin.json` to match the `VERSION` file.
- **D-06:** `conjure publish` aborts if the working tree is dirty (uncommitted changes).
- **D-07:** `conjure publish` validates the updated JSON locally (jq parse at minimum) before committing through `lib/mutate.sh`.
- **D-08:** All filesystem mutations go through `lib/mutate.sh` (mutate_write). Dry-run is honored via `CONJURE_DRYRUN` env pattern.
- **D-09:** `conjure publish --submit` prints a human-readable checklist of pre-submission steps to stdout AND writes `.claude-plugin/submit-entry.json` with the exact JSON snippet to paste into the catalog PR.
- **D-10:** `.claude-plugin/submit-entry.json` is committed to the repo (goes through mutate_write) — provides an auditable record.
- **D-11:** The stdout checklist includes: pre-submission checks, the `anthropics/claude-plugins-community` PR URL, and step-by-step instructions. No automation of the actual PR creation.
- **D-12:** CI checks that `version` in both `marketplace.json` and `plugin.json` matches the `VERSION` file on every PR. Implemented as a bash check step in `ci.yml` (not release.yml).

### Claude's Discretion

- Exact JSON field layout inside `submit-entry.json` (researcher determines from catalog format)
- Exact wording of stdout checklist messages beyond the items listed in D-11
- Whether `cmd_publish` in cli/conjure is ~10 lines or needs more structure
- Function naming inside `scripts/publish-plugin.sh`

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope.
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| MKTPL-01 | `conjure publish` updates `.claude-plugin/marketplace.json` with current release SHA and validates locally | manifest restructure needed; jq mutation pattern documented below |
| MKTPL-02 | CI validates version fields in marketplace.json + plugin.json match VERSION file on every PR | simple bash diff-check; add to test job in ci.yml |
| MKTPL-03 | CI runs `claude plugin validate .` on every PR; fails on schema errors | exit code behavior verified; apt install method confirmed |
| MKTPL-04 | `conjure publish --submit` prints checklist + writes `.claude-plugin/submit-entry.json` with catalog PR snippet | community catalog submission form URL confirmed; submit-entry.json structure derived below |
</phase_requirements>

---

## Summary

Phase 10 requires restructuring both manifest files, wiring a new `cmd_publish` CLI dispatch, and installing the claude CLI in CI. All three concerns are fully resolvable — the research verified exact schemas by running `claude plugin validate` live on the developer machine.

**Critical discovery:** Both `.claude-plugin/marketplace.json` and `.claude-plugin/plugin.json` currently fail `claude plugin validate`. The marketplace.json is missing the required `owner` object and `plugins` array. The plugin.json has `author` as a string (must be object), `commands` as a key-value object (must be array/string), `agents` as an array of paths (schema requires array), and `skills` as array (schema requires string/array — this one works). Both files need restructuring as part of this phase. The `version` field in both files reads `0.2.0` while `VERSION` reads `0.2.1` — already drifted.

**Primary recommendation:** Fix both manifest files first (Wave 0 setup step), then implement `scripts/publish-plugin.sh` + `cmd_publish`, then the CI additions.

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Version consistency enforcement | CI pipeline | `scripts/publish-plugin.sh` | Drift detection must happen on every PR, not only at publish time |
| Manifest mutation (SHA + version write) | `scripts/publish-plugin.sh` worker | `lib/mutate.sh` chokepoint | Follows existing pattern: worker script + lib write chokepoint |
| JSON schema validation (syntax) | CI pipeline (jq) | `scripts/publish-plugin.sh` local pre-check | jq is already in CI deps; no new install needed |
| Plugin semantic validation | CI pipeline (claude CLI) | Local dev (`conjure publish` calls it) | claude CLI validates plugin manifest semantics |
| Submission artifact generation | `scripts/publish-plugin.sh` | — | `--submit` flag writes submit-entry.json via mutate_write |
| CLI dispatch | `cli/conjure` case table | — | Follows existing cmd_* pattern |

---

## Standard Stack

### Core (no new packages)

| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| bash + stdlib | POSIX | `scripts/publish-plugin.sh` worker | Project constraint: POSIX bash only |
| jq | 1.6+ (CI has 1.8.1) | JSON read + field mutation + validity check | Already in CI deps; in preflight |
| claude CLI | 2.1.150 (local); latest stable in CI | `claude plugin validate .` | Official Anthropic tooling (D-02) |
| git | any | `git rev-parse HEAD`, dirty-tree check | Already a preflight requirement |
| lib/mutate.sh | n/a (existing) | All filesystem writes | Project invariant |

### No New Runtime Dependencies

This phase introduces zero new packages. All required tools are either already in the project (jq, git, lib/mutate.sh) or installed fresh in CI (claude CLI via official installer).

**Installation (CI only):**
```bash
curl -fsSL https://claude.ai/install.sh | bash
```
[VERIFIED: code.claude.com/docs/en/quickstart — official macOS/Linux/WSL install command]

**Apt alternative for Debian/Ubuntu CI (signed repo — avoids curl|bash):**
```bash
sudo install -d -m 0755 /etc/apt/keyrings
sudo curl -fsSL https://downloads.claude.ai/keys/claude-code.asc \
  -o /etc/apt/keyrings/claude-code.asc
echo "deb [signed-by=/etc/apt/keyrings/claude-code.asc] https://downloads.claude.ai/claude-code/apt/stable stable main" \
  | sudo tee /etc/apt/sources.list.d/claude-code.list
sudo apt update
sudo apt install claude-code
```
[VERIFIED: code.claude.com/docs/en/setup — Linux package manager install]

Both methods are documented by Anthropic. The apt method is preferred in CI because package manager signatures are verified automatically (vs curl|bash which requires trusting the pipe). GPG key fingerprint: `31DD DE24 DDFA B679 F42D 7BD2 BAA9 29FF 1A7E CACE`.

---

## Package Legitimacy Audit

> This phase installs no external npm/pip packages. The only new CI dependency is the official `claude-code` binary from Anthropic's signed apt repository or `claude.ai/install.sh`. No third-party packages are introduced.

| Dependency | Source | Age | Maintainer | Disposition |
|-----------|--------|-----|------------|-------------|
| claude-code CLI | Anthropic signed apt repo / claude.ai/install.sh | Official | Anthropic | Approved — official Anthropic tooling |

**Packages removed due to slopcheck [SLOP] verdict:** none
**Packages flagged as suspicious [SUS]:** none

---

## Architecture Patterns

### System Architecture Diagram

```
conjure publish [--submit] [--dry-run]
        │
        ▼
cli/conjure  cmd_publish()
        │  (source lib/mutate.sh)
        │  (parse --submit, --dry-run flags)
        │
        ▼
scripts/publish-plugin.sh
        │
        ├─── dirty-tree check ──► abort with message
        │    git diff --quiet && git diff --cached --quiet
        │
        ├─── read VERSION file → CURRENT_VERSION
        │
        ├─── jq validate .claude-plugin/marketplace.json ──► abort on parse error
        ├─── jq validate .claude-plugin/plugin.json       ──► abort on parse error
        │
        ├─── git rev-parse HEAD → CURRENT_SHA
        │
        ├─── jq build new marketplace.json content
        │    (update .plugins[0].source.sha = CURRENT_SHA)
        │    (update .plugins[0].version    = CURRENT_VERSION)
        │
        ├─── jq build new plugin.json content
        │    (update .version = CURRENT_VERSION)
        │
        ├─── mutate_write .claude-plugin/marketplace.json <new_content>
        ├─── mutate_write .claude-plugin/plugin.json      <new_content>
        │
        ├─── [--submit branch]
        │      ├─── print stdout checklist
        │      └─── mutate_write .claude-plugin/submit-entry.json <snippet>
        │
        └─── mutate_summary

CI (ci.yml test job)
        │
        ├─── Install claude-code (apt signed repo)  ──► fail if install fails
        ├─── Version consistency check              ──► fail if drift detected
        │    (VERSION vs marketplace.json vs plugin.json)
        ├─── jq validate .claude-plugin/*.json      ──► already exists, extend
        └─── claude plugin validate .               ──► exit 1 = CI failure
```

### Recommended Project Structure (additions only)

```
scripts/
└── publish-plugin.sh   # new worker (sources lib/mutate.sh)

cli/conjure             # modified: add cmd_publish + dispatch case

.claude-plugin/
├── marketplace.json    # RESTRUCTURED: add owner + plugins[] (see schema below)
├── plugin.json         # FIXED: author object, remove unsupported fields
└── submit-entry.json   # new: written by --submit, committed via mutate_write

.github/workflows/
└── ci.yml              # modified: add 3 new steps to test job
```

### Pattern 1: Dirty Tree Abort

**What:** Prevents publishing a SHA that doesn't match working state (D-06)
**When to use:** At top of `publish-plugin.sh` before any mutations

```bash
# Source: established bash idiom; verified against CONTEXT.md code_context
if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "ERROR: working tree is dirty — commit or stash changes before publishing" >&2
  exit 1
fi
```

### Pattern 2: jq Field Update via Shell Variable

**What:** Update specific fields in JSON while preserving the rest via jq + mutate_write
**When to use:** For SHA and version field updates in publish-plugin.sh

```bash
# Source: jq manual; pattern used in existing conjure scripts
CURRENT_SHA=$(git rev-parse HEAD)
CURRENT_VERSION=$(cat "$CONJURE_HOME/VERSION")

# Build new marketplace.json content (in-memory, no temp file)
NEW_MKT=$(jq \
  --arg sha "$CURRENT_SHA" \
  --arg ver "$CURRENT_VERSION" \
  '.plugins[0].source.sha = $sha | .plugins[0].version = $ver' \
  "$PLUGIN_DIR/marketplace.json")

# Validate the result before writing
printf '%s' "$NEW_MKT" | jq empty || { echo "ERROR: jq produced invalid JSON" >&2; exit 1; }

mutate_write "$PLUGIN_DIR/marketplace.json" "$NEW_MKT"
```

### Pattern 3: Version Consistency CI Check

**What:** Bash step in ci.yml that diffs VERSION against both JSON files
**When to use:** New step in existing `test` job, before the claude validate step

```bash
# Source: standard bash string comparison
VER=$(cat VERSION)
MKT_VER=$(jq -r '.plugins[0].version // empty' .claude-plugin/marketplace.json)
PLG_VER=$(jq -r '.version // empty' .claude-plugin/plugin.json)
FAIL=0
[ "$MKT_VER" = "$VER" ] || { echo "FAIL: marketplace.json version ($MKT_VER) != VERSION ($VER)"; FAIL=1; }
[ "$PLG_VER" = "$VER" ] || { echo "FAIL: plugin.json version ($PLG_VER) != VERSION ($VER)"; FAIL=1; }
[ "$FAIL" -eq 0 ] || exit 1
echo "OK: all version fields match $VER"
```

### Pattern 4: cmd_publish Dispatch

**What:** New case in cli/conjure following existing cmd_* pattern
**When to use:** Dispatch table at cli/conjure:272-283

```bash
# Source: cli/conjure dispatch pattern (lines 272-283, read this session)
cmd_publish() {
  local submit=0 dryrun=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --submit)   submit=1 ;;
      --dry-run)  dryrun=1 ;;
      -h|--help)  echo "Usage: conjure publish [--submit] [--dry-run]"; return 0 ;;
      *) echo "Unknown flag: $1"; return 1 ;;
    esac
    shift
  done
  DRY_RUN="$dryrun" CONJURE_SUBMIT="$submit" bash "$CONJURE_HOME/scripts/publish-plugin.sh"
}
```

And in the dispatch table (after `preflight` case):
```bash
publish)         shift; cmd_publish "$@"         ;;
```

### Anti-Patterns to Avoid

- **Writing JSON with string concatenation:** Use `jq --arg` + `mutate_write`. Never `echo '{"sha":"'$SHA'"}' > file`.
- **Temp files for jq transformations:** Build the new content in a variable; pass to `mutate_write`. Temp files bypass the DRY_RUN guard.
- **Running `claude plugin validate` before fixing manifests:** The current manifests fail — Wave 0 must fix them first or CI will fail on the validate step immediately.
- **Checking version against `.version` at the marketplace root:** The version that matters in marketplace.json is `.plugins[0].version`, not the root `.version` field.
- **`exit 1` in scripts:** Per CLAUDE.md, hooks `exit 2` on error; scripts use `exit 1` for aborts. However `publish-plugin.sh` is a worker script (not a hook), so `exit 1` is correct here.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| JSON field update | String-replace or sed on JSON | `jq --arg` + `mutate_write` | jq handles whitespace, unicode, escaping; sed on JSON is notoriously fragile |
| Plugin manifest validation | Custom schema parser | `claude plugin validate` | Official CLI knows the exact schema; tracks Anthropic's schema evolution |
| JSON syntax validation | Custom parser | `jq empty <file>` | Already in project, already in CI |
| Git SHA extraction | Parsing git log | `git rev-parse HEAD` | Canonical, 40-char, no parsing |
| Version string comparison | semver library | `[ "$A" = "$B" ]` string equality | Version field is opaque string in JSON; only equality matters here |

**Key insight:** jq is already in the preflight and CI; building redundant JSON manipulation in pure bash (without jq) would be fragile and is explicitly against the project's "no heavy runtime deps" constraint.

---

## Critical Finding: Both Manifest Files Must Be Restructured

This is the most important finding of this research. **Both manifest files currently fail `claude plugin validate`** (verified by running the command in this session against the actual project).

### marketplace.json — Current vs Required

**Current format (INVALID):**
```json
{
  "$schema": "https://json.schemastore.org/claude-code-marketplace.json",
  "name": "conjure",
  "displayName": "Conjure ...",
  "version": "0.2.0",
  "install": { "type": "git", "url": "...", "branch": "main" }
}
```
Errors: `owner: expected object, received undefined` + `plugins: expected array, received undefined`
Warnings: 14 unknown fields (all the metadata fields like displayName, shortDescription, etc.)

**Required format (VALID — verified in this session):**
```json
{
  "name": "conjure",
  "description": "Marketplace for the Conjure Claude Code harness kit.",
  "owner": {
    "name": "mohandoz",
    "email": "33397039+mohandoz@users.noreply.github.com"
  },
  "plugins": [
    {
      "name": "conjure",
      "description": "Production-grade init kit. Lazy-loaded skills, hooks, subagents, knowledge graph, stack profiles, safe migration.",
      "version": "0.2.1",
      "source": {
        "source": "github",
        "repo": "mohandoz/conjure",
        "ref": "main",
        "sha": "<40-char-HEAD-SHA>"
      },
      "author": {
        "name": "mohandoz",
        "email": "33397039+mohandoz@users.noreply.github.com"
      },
      "homepage": "https://github.com/mohandoz/conjure",
      "repository": "https://github.com/mohandoz/conjure",
      "license": "MIT",
      "keywords": ["scaffold", "harness", "skills", "hooks", "subagents", "knowledge-graph", "migration"],
      "category": "developer-tools"
    }
  ]
}
```

The previous metadata fields (displayName, shortDescription, longDescription, categories, tags, icon, screenshots, issues, author at top level, compatibility, install) are all `Unknown field` warnings — they are ignored at runtime but pollute the validate output. They should be removed or moved inside the `plugins[]` entry.

**IMPORTANT:** The `$schema` field pointing to `https://json.schemastore.org/claude-code-marketplace.json` produces no warning and no error — it is listed in the official schema as an accepted optional field. It can be kept.

### plugin.json — Current vs Required

**Current format (INVALID):**
```json
{
  "author": "mohandoz",
  "commands": { "conjure": "cli/conjure" },
  "agents": ["templates/agents/code-explorer.md", ...],
  "skills": ["templates/skills/code-graph", ...],
  "engines": { "claude-code": ">=2.1.117" },
  "minimumClaudeCodeVersion": "2.1.117",
  "mcpServers": { "_note": "..." }
}
```
Errors: `author: expected object, received string` + `commands: Invalid input` + `agents: Invalid input` + `skills: Invalid input` + `mcpServers: Invalid input`

**Required format (VALID — verified in this session):**
```json
{
  "name": "conjure",
  "version": "0.2.1",
  "description": "Production-grade Claude Code harness kit. Lazy-loaded skills, isolated subagents, deterministic hooks, knowledge-graph integration, multi-stack profiles, compliance overlays, safe migration from other AI tools.",
  "author": {
    "name": "mohandoz",
    "email": "33397039+mohandoz@users.noreply.github.com"
  },
  "license": "MIT",
  "repository": "https://github.com/mohandoz/conjure",
  "homepage": "https://github.com/mohandoz/conjure#readme",
  "keywords": ["claude-code", "harness", "skills", "hooks", "subagents", "knowledge-graph", "graphify", "lazy-loading", "scaffold", "migration"],
  "skills": "./templates/skills",
  "agents": ["./templates/agents/code-explorer.md", "./templates/agents/test-writer.md", "./templates/agents/migration-writer.md", "./templates/agents/security-auditor.md", "./templates/agents/doc-writer.md", "./templates/agents/diff-reviewer.md"]
}
```

Notes on field changes:
- `author`: must be `{"name": "...", "email": "..."}` object, not `"mohandoz"` string
- `commands`: the current `{"conjure": "cli/conjure"}` object is invalid. Use `"commands": "./cli/"` or `["./cli/conjure"]` array. Since `conjure` is actually a CLI binary (not a flat .md skill file), using `commands: []` or omitting the field is likely correct; the binary is not a Claude skill command.
- `agents`: array of file paths works (verified). Paths should be `"./templates/agents/..."` with leading `./`.
- `skills`: string path works (verified). Use `"./templates/skills"` (without trailing slash also works).
- `engines`, `minimumClaudeCodeVersion`: these produce "Unknown field" warnings only; they can be kept or removed. Removing reduces noise.
- `mcpServers`: the current value `{"_note": "..."}` is Invalid — remove it entirely. The note can go in README.

### submit-entry.json Structure

Based on the `anthropics/claude-plugins-community` catalog format (verified by reading the actual repo):
```json
{
  "name": "conjure",
  "description": "Production-grade init kit for Claude Code. Lazy-loaded skills, deterministic hooks, isolated subagents, knowledge graph, stack profiles, compliance overlays, safe migration.",
  "source": {
    "source": "github",
    "repo": "mohandoz/conjure",
    "ref": "main",
    "sha": "<40-char-HEAD-SHA>"
  },
  "homepage": "https://github.com/mohandoz/conjure",
  "category": "developer-tools"
}
```

This is the JSON object a maintainer pastes into the community catalog. The submission form URL is `https://claude.ai/settings/plugins/submit` (or `https://platform.claude.com/plugins/submit` for Console users). Direct PRs to `anthropics/claude-plugins-community` are closed automatically.

---

## Common Pitfalls

### Pitfall 1: validate . vs validate path — File Priority

**What goes wrong:** `claude plugin validate .` when run from the repo root will NOT find `.claude-plugin/` because there is no manifest at `./.claude-plugin/marketplace.json` — it looks one level up from where you point it.
**Why it happens:** `claude plugin validate <path>` looks for `<path>/.claude-plugin/marketplace.json` first, then `<path>/.claude-plugin/plugin.json`. Running `claude plugin validate .` from repo root correctly finds `./.claude-plugin/marketplace.json`.
**How to avoid:** Always run `claude plugin validate .` from the repo root. Verified: `claude plugin validate .` (from repo root) finds `.claude-plugin/marketplace.json` and validates it. When BOTH files exist in `.claude-plugin/`, it validates marketplace.json ONLY and ignores plugin.json. To validate plugin.json explicitly, run `claude plugin validate .claude-plugin/plugin.json`.
**Warning signs:** If CI runs `claude plugin validate .` from a subdirectory, it will report "No manifest found in directory."

**CI implication:** The CI step should be:
```yaml
- name: Validate plugin manifests
  run: |
    claude plugin validate .               # validates marketplace.json
    claude plugin validate .claude-plugin/plugin.json  # validates plugin.json explicitly
```

### Pitfall 2: --strict Flag in CI

**What goes wrong:** Using `claude plugin validate . --strict` in CI would fail on the missing `description` top-level field in marketplace.json (warning, not error, but --strict promotes it to error).
**Why it happens:** `--strict` treats all warnings as errors. The marketplace.json description warning disappears once the `description` field is added.
**How to avoid:** Add `"description"` to marketplace.json (verified: adding it eliminates the warning). Do NOT use `--strict` until all warnings are resolved. Per D-01, CI should fail on schema errors, not warnings; don't use `--strict`.

### Pitfall 3: jq Updates Silently Drop Fields

**What goes wrong:** Using `jq '.version = $ver'` on marketplace.json would set `.version` at root level (which is an ignored optional field) instead of `.plugins[0].version` (which is what the validator checks).
**Why it happens:** The version field that matters is nested inside `plugins[0]`, not at the root.
**How to avoid:** Always update `.plugins[0].source.sha` and `.plugins[0].version` for marketplace.json. For plugin.json, `.version` at root is correct.

### Pitfall 4: SHA Written Before Commit

**What goes wrong:** Running `conjure publish` writes the current HEAD SHA into marketplace.json, but then the maintainer commits marketplace.json itself — creating a new SHA that doesn't match what was written.
**Why it happens:** The SHA in marketplace.json points to the HEAD at publish time. The publish commit itself is a new HEAD.
**How to avoid:** Document in the stdout output and checklist that after `conjure publish`, the user must commit the changed manifest files and then the published SHA is the SHA of THAT commit (or a subsequent release tag). The ARCHITECTURE.md notes this is handled in release.yml by a bot commit. For the `conjure publish` command itself (developer use), the flow is: publish writes HEAD SHA → stage + commit marketplace.json + plugin.json → push tag. This is a known workflow sequencing issue documented in the submit checklist.

### Pitfall 5: Version Drift Is Already Present

**What goes wrong:** `VERSION` file currently reads `0.2.1` but both manifest files read `0.2.0`. The MKTPL-02 CI check would fail immediately if added without fixing the manifests first.
**Why it happens:** The version bump to 0.2.1 was not propagated to the manifest files.
**How to avoid:** The manifest restructure (Wave 0) must also update the `version` fields in both files to `0.2.1`. The MKTPL-02 CI step must only be added AFTER the manifests are fixed.

---

## Code Examples

Verified patterns from official sources and live testing:

### Minimal Valid marketplace.json (verified — claude plugin validate exit 0)
```json
{
  "name": "conjure",
  "description": "Marketplace for the Conjure Claude Code harness kit.",
  "owner": { "name": "mohandoz" },
  "plugins": [
    {
      "name": "conjure",
      "source": {
        "source": "github",
        "repo": "mohandoz/conjure",
        "ref": "main",
        "sha": "d07c59bbda32e02f2dcf2ded70d34b78f1e4b820"
      },
      "description": "Production-grade init kit for Claude Code harness."
    }
  ]
}
```
Source: `claude plugin validate` run this session — exit 0, 0 errors, 1 warning (no description at root — resolved by adding `description` field).

### Minimal Valid plugin.json (verified — claude plugin validate exit 0)
```json
{
  "name": "conjure",
  "version": "0.2.1",
  "description": "Production-grade Claude Code harness kit.",
  "author": { "name": "mohandoz" },
  "license": "MIT",
  "repository": "https://github.com/mohandoz/conjure",
  "homepage": "https://github.com/mohandoz/conjure#readme",
  "keywords": ["claude-code", "harness", "skills"],
  "skills": "./templates/skills",
  "agents": ["./templates/agents/code-explorer.md"]
}
```
Source: `claude plugin validate` run this session — exit 0, 0 errors, 0 warnings.

### jq SHA + Version Update (publish-plugin.sh core)
```bash
# Source: jq manual; verified against jq 1.8.1 locally
PLUGIN_DIR="$CONJURE_HOME/.claude-plugin"
SHA=$(git rev-parse HEAD)
VER=$(cat "$CONJURE_HOME/VERSION")

NEW_MKT=$(jq --arg sha "$SHA" --arg ver "$VER" \
  '.plugins[0].source.sha = $sha | .plugins[0].version = $ver' \
  "$PLUGIN_DIR/marketplace.json")
printf '%s' "$NEW_MKT" | jq empty 2>/dev/null \
  || { echo "ERROR: jq output invalid" >&2; exit 1; }
mutate_write "$PLUGIN_DIR/marketplace.json" "$NEW_MKT"

NEW_PLG=$(jq --arg ver "$VER" '.version = $ver' "$PLUGIN_DIR/plugin.json")
printf '%s' "$NEW_PLG" | jq empty 2>/dev/null \
  || { echo "ERROR: jq output invalid" >&2; exit 1; }
mutate_write "$PLUGIN_DIR/plugin.json" "$NEW_PLG"
```

### CI Version Consistency Check
```bash
# Add as new step in .github/workflows/ci.yml test job
VER=$(cat VERSION)
MKT_VER=$(jq -r '.plugins[0].version // empty' .claude-plugin/marketplace.json)
PLG_VER=$(jq -r '.version // empty' .claude-plugin/plugin.json)
RC=0
[ "$MKT_VER" = "$VER" ] || { echo "FAIL: marketplace.json .plugins[0].version ($MKT_VER) != VERSION ($VER)"; RC=1; }
[ "$PLG_VER"  = "$VER" ] || { echo "FAIL: plugin.json .version ($PLG_VER) != VERSION ($VER)"; RC=1; }
[ "$RC" -eq 0 ] && echo "OK: all version fields match $VER"
exit "$RC"
```

### CI claude plugin validate Steps
```yaml
# Add to .github/workflows/ci.yml test job, after "Install deps" step
- name: Install claude CLI
  run: |
    sudo install -d -m 0755 /etc/apt/keyrings
    sudo curl -fsSL https://downloads.claude.ai/keys/claude-code.asc \
      -o /etc/apt/keyrings/claude-code.asc
    echo "deb [signed-by=/etc/apt/keyrings/claude-code.asc] https://downloads.claude.ai/claude-code/apt/stable stable main" \
      | sudo tee /etc/apt/sources.list.d/claude-code.list
    sudo apt update
    sudo apt install -y claude-code
    claude --version

- name: Validate plugin manifests
  run: |
    claude plugin validate .
    claude plugin validate .claude-plugin/plugin.json

- name: Check version consistency
  run: |
    VER=$(cat VERSION)
    MKT_VER=$(jq -r '.plugins[0].version // empty' .claude-plugin/marketplace.json)
    PLG_VER=$(jq -r '.version // empty' .claude-plugin/plugin.json)
    RC=0
    [ "$MKT_VER" = "$VER" ] || { echo "marketplace.json version ($MKT_VER) != VERSION ($VER)"; RC=1; }
    [ "$PLG_VER"  = "$VER" ] || { echo "plugin.json version ($PLG_VER) != VERSION ($VER)"; RC=1; }
    exit "$RC"
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Custom marketplace.json flat format (self-describing) | owner + plugins[] array format | claude CLI 2.x (2025-2026) | Current marketplace.json is structurally invalid — must be restructured |
| author as string | author as object `{"name": "..."}` | claude plugin validate enforces object | Current plugin.json fails validation |
| commands as key-value object | commands as string path or array of paths | Plugin system redesign | Current plugin.json commands field is invalid |
| curl|bash install | Signed apt repo available (Ubuntu/Debian CI) | 2026 | More secure CI install available; curl|bash still works |
| Direct PR to claude-plugins-community | Submission via web form only; direct PRs auto-closed | 2025 | No automated PR creation possible; checklist approach (D-11) is correct |

**Deprecated/outdated in current manifests:**
- `$schema: "https://json.schemastore.org/claude-code-marketplace.json"` — still accepted as optional, no error
- `displayName`, `shortDescription`, `longDescription` — unknown fields, warnings only (can be removed)
- `categories` (array at root of marketplace.json) — unknown, warning only (use `category` inside `plugins[]` entry instead)
- `install` object at marketplace root — unknown field, warning; plugin source goes in `plugins[].source`
- `engines` / `minimumClaudeCodeVersion` — unknown fields, warnings only

---

## `claude plugin validate` Behavior Summary

**Verified in this session against claude 2.1.150.**

| Scenario | Exit Code | Notes |
|----------|-----------|-------|
| No errors, no warnings | 0 | Clean pass |
| Warnings only | 0 | Passes; `--strict` promotes to exit 1 |
| Errors present | 1 | Fails |
| `--strict` with warnings | 1 | Treats warnings as errors |
| Path has both marketplace.json + plugin.json | 0 | Validates marketplace.json only |
| Path has only plugin.json | validates plugin.json | — |
| Path is a specific `.json` file | validates that file directly | Works for both types |
| `claude plugin validate .` from repo root | validates `.claude-plugin/marketplace.json` | Standard CI invocation |

**Files validated when running `claude plugin validate .` from repo root:**
- `.claude-plugin/marketplace.json` (primary — takes precedence when both exist)
- `.claude-plugin/plugin.json` is NOT validated in this case — requires separate explicit invocation

[VERIFIED: live execution in this research session against claude 2.1.150]

---

## Open Questions (RESOLVED)

1. **Does release.yml need updating in this phase?**
   - What we know: CONTEXT.md scopes phase 10 to ci.yml only (MKTPL-02); release.yml changes are scoped to Phase 15 (REL-01).
   - What's unclear: The ARCHITECTURE.md mentions release.yml should run `scripts/publish-plugin.sh` and commit the SHA update. Phase 10 delivers the script — phase 15 wires it into release.yml.
   - Recommendation: Phase 10 does NOT touch release.yml. Document in the script's own header that it is intended to be called from release.yml in Phase 15.

2. **Should `claude plugin validate` run in CI without `--strict`?**
   - What we know: D-01 says "fails on schema errors." Warnings are not errors. `--strict` would fail on the missing marketplace description warning if `description` is not added.
   - What's unclear: Whether the planner wants warnings to be CI-blocking.
   - Recommendation: Use `claude plugin validate .` without `--strict`. Add `description` to marketplace.json to eliminate the only warning. This makes the validate step clean without needing `--strict`.

3. **SHA in marketplace.json after publish commit**
   - What we know: `conjure publish` writes HEAD SHA. The publish commit itself creates a new SHA.
   - Recommendation: Stdout message should say "SHA written: `<sha>`. After committing and tagging, re-run `conjure publish` or update the SHA manually to point to the release tag commit."

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| bash | scripts/publish-plugin.sh | yes | 3.2+ (macOS), 5.x (Linux) | — |
| jq | JSON mutation + validation | yes (local + CI) | local: 1.8.1; CI installs via apt | no fallback — required |
| git | SHA extraction, dirty tree check | yes | any recent | — |
| claude CLI | CI validation (MKTPL-03) | yes (local: 2.1.150) | CI: latest stable via apt | — (D-02: install failure = CI failure) |
| lib/mutate.sh | all filesystem writes | yes (existing) | — | — |

**Missing dependencies with no fallback:** none for local dev. In CI, claude CLI must be installed (D-02 locks this).

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Hand-rolled bash assertions in `tests/run.sh` |
| Config file | none — single entrypoint `tests/run.sh` |
| Quick run command | `bash tests/run.sh` |
| Full suite command | `bash tests/run.sh` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| MKTPL-01 | `conjure publish` writes SHA + version to both JSON files | unit/integration | `bash tests/run.sh` (new assertions) | Wave 0 |
| MKTPL-01 | `conjure publish` aborts on dirty tree | unit | `bash tests/run.sh` (new assertion) | Wave 0 |
| MKTPL-01 | `conjure publish` honors `--dry-run` | unit | `bash tests/run.sh` (new assertion) | Wave 0 |
| MKTPL-02 | Version consistency check script exits non-zero on drift | unit | `bash tests/run.sh` (new assertion) | Wave 0 |
| MKTPL-03 | `claude plugin validate .` passes on both manifest files | smoke | `claude plugin validate . && claude plugin validate .claude-plugin/plugin.json` | after Wave 0 manifest fix |
| MKTPL-04 | `conjure publish --submit` writes submit-entry.json with required fields | unit | `bash tests/run.sh` (new assertion) | Wave 0 |
| MKTPL-04 | `conjure publish --submit` prints checklist to stdout | unit | `bash tests/run.sh` (new assertion) | Wave 0 |

### Sampling Rate

- **Per task commit:** `bash tests/run.sh`
- **Per wave merge:** `bash tests/run.sh && claude plugin validate . && claude plugin validate .claude-plugin/plugin.json`
- **Phase gate:** full suite green + `claude plugin validate` clean before `/gsd-verify-work`

### Wave 0 Gaps

- [ ] `tests/run.sh` — add MKTPL-01 through MKTPL-04 assertions (see test map above)
- [ ] `.claude-plugin/marketplace.json` — restructure to valid schema (required before any validate step runs)
- [ ] `.claude-plugin/plugin.json` — fix author, commands, agents, mcpServers fields

---

## Security Domain

> `security_enforcement` not explicitly false in config.json — including section.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | — |
| V3 Session Management | no | — |
| V4 Access Control | no | — |
| V5 Input Validation | yes | `jq empty` validates JSON before write; jq `--arg` escapes string values |
| V6 Cryptography | no | — |

### Known Threat Patterns for bash + jq JSON mutation

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Shell injection via SHA or version string | Tampering | Use `jq --arg` (not string interpolation) — jq escapes values properly |
| Writing to path outside `.claude-plugin/` | Tampering | Hardcode PLUGIN_DIR as `"$CONJURE_HOME/.claude-plugin"` — do not accept user-supplied path |
| Committing `.claude-plugin/submit-entry.json` with sensitive data | Information Disclosure | submit-entry.json contains only public fields (name, description, source, homepage, category) — no secrets |
| claude CLI install from untrusted source | Spoofing | Use signed apt repo with GPG fingerprint verification (documented above) |

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Community catalog submission only via web form; direct PRs auto-closed | Standard Stack, Open Questions | If PRs are accepted, `--submit` could automate PR creation via `gh pr create` |
| A2 | `claude plugin validate .` on repo root validates marketplace.json (not plugin.json) when both exist | validate behavior summary | Wrong file might be validated in CI, masking plugin.json errors |
| A3 | Apt install of `claude-code` on Ubuntu CI (GitHub Actions `ubuntu-latest`) does not require additional system deps | Environment Availability | CI apt step might fail requiring extra deps |

A2 is verified by direct testing in this session. A1 is confirmed by README of anthropics/claude-plugins-community read this session. A3 is likely correct but not tested in a CI runner.

---

## Sources

### Primary (HIGH confidence)
- `claude plugin validate` — live execution against claude 2.1.150 on actual project files; confirmed exit codes, error messages, file selection behavior
- `code.claude.com/docs/en/plugins-reference` — plugin.json complete schema, author object requirement, skills/agents/commands field types [VERIFIED: fetched this session]
- `code.claude.com/docs/en/plugin-marketplaces` — marketplace.json schema (owner fields, plugins[] required fields, source types) [VERIFIED: fetched this session]
- `code.claude.com/docs/en/quickstart` — claude CLI install command (`curl -fsSL https://claude.ai/install.sh | bash`) [VERIFIED: fetched this session]
- `code.claude.com/docs/en/setup` — apt signed repo install for Ubuntu/Debian [VERIFIED: fetched this session]
- `github.com/anthropics/claude-plugins-community` — submission via web form; direct PRs auto-closed; catalog JSON format [VERIFIED: fetched this session]
- `.claude-plugin/marketplace.json`, `.claude-plugin/plugin.json` — read directly, failures confirmed by validate run
- `lib/mutate.sh` — read directly; mutate_write signature confirmed
- `cli/conjure` (lines 255-283) — dispatch pattern read directly
- `.github/workflows/ci.yml` — existing steps read directly
- `VERSION` file — reads `0.2.1`

### Secondary (MEDIUM confidence)
- `.planning/research/ARCHITECTURE.md` — field list in §"1. scripts/publish-plugin.sh" referenced but some fields (marketplace.json format) are now superseded by live validate testing

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — tools verified present; schemas verified by live execution
- Manifest schema: HIGH — verified by running `claude plugin validate` against test fixtures in this session
- Claude CLI install: HIGH — official docs fetched this session
- Community catalog submission: HIGH — README fetched from anthropics/claude-plugins-community this session
- Pitfalls: HIGH — most discovered by live testing, not training data
- Architecture patterns: HIGH — derived from existing codebase patterns read directly

**Research date:** 2026-05-25
**Valid until:** 2026-06-25 (claude CLI schema could change with any release; re-validate if claude version bumps significantly)
