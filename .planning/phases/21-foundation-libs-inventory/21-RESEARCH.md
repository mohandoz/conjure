# Phase 21: Foundation Libs + Inventory - Research

**Researched:** 2026-05-28
**Domain:** POSIX bash shared library design; inventory/classification; manifest schema; move-safe archive primitive
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Classification taxonomy**
- D-01: 6 deterministic buckets: `core` / `skill` / `agent` / `planning-doc` / `reference-doc` / `unknown`. The 11-tag scheme in ARCHITECTURE.md is rejected as the CLI contract.
- D-02: `candidate-skill`, `candidate-agent`, `stale-candidate` are LLM judgment — belong to the restructure skill (Phase 23), not deterministic CLI inventory.
- D-03: Classification is path-based and conservative. A markdown file outside its harness directory stays `unknown`, never auto-promoted. Frontmatter only confirms files already in harness directories.
- D-04: Inventory is markdown-only (`*.md`). Hooks (`.mjs`) are out of inventory scope.

**Inventory richness**
- D-05: Skip `git_age_days` — no per-file `git log`. Rationale: staleness is skill judgment; ~500 git-log forks is the primary CR-7 perf threat.
- D-06: Link data = CLAUDE.md outbound links only. One `grep` pass extracts `](path)` links; a file linked from CLAUDE.md → `reference-doc` + `linked_from: ["CLAUDE.md"]`.
- D-07: `reference-doc` by path (docs/, README.md, *.adr.md, CHANGELOG) OR CLAUDE.md-link (D-06).

**Cap & overflow semantics**
- D-08: >500 files → scan up to 500, set `summary.scan_capped: true` + `summary.total_found`, print warning. Do NOT enumerate unscanned files.
- D-09: Per-file boolean `size_cap_exceeded` for line_count violations feeds `size_cap_violations[]`. Scan limit uses separate `summary.scan_capped` + `summary.total_found`. Two distinct names.
- D-10: Harness-first budget when capped. Always include CLAUDE.md + `.claude/**` + `.planning/**` first, then fill remaining with other docs in deterministic order.

**Archive primitive (mutate_archive)**
- D-11: `mutate_archive` lives in `lib/mutate.sh`. Honors `DRY_RUN`, increments `CONJURE_DRY_MUTATION_COUNT`. `lib/caps.sh` sources `lib/mutate.sh` and calls it.
- D-12: Path-preserving mirror layout: `docs/old/notes.md` → `.conjure-archive-<ts>/docs/old/notes.md`. One UTC-timestamped dir per run (`date -u +%Y%m%dT%H%M%SZ`).
- D-13: Move-safety contract: `cp -a` → verify sha256 dest == src sha256 → `rm` original → append src→dest + sha256 + ts to archive ledger. Never unlink unverified content.

### Claude's Discretion

- `lib/log.sh` RESTRUCTURE-LOG.md exact location/header format
- `lib/snapshot.sh` cp -a vs cp -Rp fallback selection
- Symlink/binary/vendored skip-detection mechanics (.git, node_modules, .conjure-adopt-backups exclusion)
- Manifest dry-run `/tmp` write path
- Standard patterns, per research. Follow STACK.md primitives and M-2/M-4 guidance.

### Deferred Ideas (OUT OF SCOPE)

- `--quick` mode skipping wc -l for large files (ADOPT-08 v2)
- `--json` inventory/report output for CI (ADOPT-07 v2)
- Full bidirectional link-graph with corpus-wide reverse index (D-06 keeps it to CLAUDE.md outbound only)
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| INV-01 | Inventory every markdown file and classify into harness bucket (core/skill/agent/planning-doc/reference-doc/unknown) | D-01 through D-07 lock classification logic; §Architecture Patterns shows implementation |
| INV-02 | Emit machine-readable manifest (`adopt-manifest.json`) as CLI↔skill contract | §Manifest Schema section; schema sample from ARCHITECTURE.md with D-01/D-08/D-09 overrides applied |
| INV-03 | Skip binary/symlink/generated/vendored; cap default at 500 files; progress indicator | M-2 pitfall and D-08 drive filtering and cap design; §Don't Hand-Roll covers find exclusions |
| INV-04 | Flag every size-cap violation per file so restructure step can target it | D-09 resolves naming; lib/caps.sh feeds constants; §Code Examples shows wc -l pattern |
| SAFE-03 | No user file ever deleted — stale files archived (moved to timestamped archive dir), never rm'd | D-11/D-12/D-13 lock mutate_archive contract; §Architecture Patterns shows move-safety sequence |
| ADOPT-03 | conjure adopt refuses dirty git tree (exit 2) unless --force | Library primitive only: inventory.sh is read-only; git-clean gate is Phase 22 (adopt.sh). This phase delivers `lib/caps.sh` and ADOPT-03-adjacent snap infra (lib/snapshot.sh) but the gate itself is Phase 22. Note: SAFE-03 is the active Phase 21 requirement. |
</phase_requirements>

---

## Summary

Phase 21 delivers five files that every downstream v0.6.0 component depends on but that have zero inbound dependencies other than `lib/mutate.sh` (already shipped). The build is straightforward POSIX bash, using only tools already in the preflight stack — `find`, `wc -l`, `cp -a`, `sha256sum`/`shasum`, `jq`, and `date -u`. No new packages. No runtime changes.

The primary intellectual work in this phase is not code volume — it is getting three contracts right before any downstream code depends on them: (1) the 6-bucket classification taxonomy and its path-based decision tree, (2) the `adopt-manifest.json` schema with D-01/D-08/D-09 overrides applied to ARCHITECTURE.md's sample, and (3) the `mutate_archive` move-safety contract (D-13 copy→verify→rm→ledger). Once these contracts are locked in tests, Phases 22 and 23 can build on them without reopening Phase 21.

The research surfaces two technical details that must be handled precisely: (a) `mutate_write` currently calls `printf '%s'` without a trailing newline — `lib/log.sh` needs `printf '%s\n'` for its append entries to avoid joining lines, and (b) the `snapshot_create` function must use raw `cp` (not `mutate_cp`) because it is the safety primitive that precedes all `mutate_*` calls — routing it through `DRY_RUN` would suppress the backup and remove the safety net.

**Primary recommendation:** Implement in strict build order — `lib/caps.sh` first (5-line constant export), then `lib/log.sh` (depends only on `mutate.sh`), then `lib/snapshot.sh` (depends on log.sh), then `lib/inventory.sh` + manifest schema (depends on log.sh + caps.sh). Write and pass tests for each lib before moving to the next. The manifest schema finalization (adopt-manifest.json sample + JSON Schema stub) is a deliverable alongside inventory.sh.

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Cap constants | lib/caps.sh | scripts/audit-setup.sh (source-site change) | Single source of truth extracted to lib; consumers source it |
| Structured log writes | lib/log.sh | lib/mutate.sh | log.sh formats entries; mutate_write handles DRY_RUN gate |
| Filesystem snapshot | lib/snapshot.sh | (raw cp — NOT mutate_cp) | Snapshot precedes all mutate_* calls; must be unconditional in live mode |
| Markdown inventory + classification | lib/inventory.sh | lib/caps.sh (size check), lib/log.sh (emit log entry) | Read-only scan; no mutations except manifest write via mutate_write |
| Manifest JSON output | lib/inventory.sh (inventory_emit_manifest) | lib/mutate.sh (mutate_write) | DRY_RUN writes to /tmp; live writes to adopt-manifest.json |
| Move-safe archive primitive | lib/mutate.sh (mutate_archive) | lib/caps.sh (calls it) | All mutations route through lib/mutate.sh — invariant maintained |
| Git-clean precondition (ADOPT-03) | scripts/adopt.sh | — | Phase 22 responsibility; not in Phase 21 libs |

---

## Standard Stack

### Core (all verified — already in preflight, zero new deps)

| Tool | Version | Purpose | Source |
|------|---------|---------|--------|
| `bash` | 3.2+ | All lib files; POSIX compat mandatory | [ASSUMED] — system bash |
| `find -print0 \| xargs -0 wc -l` | POSIX | Batch line-count inventory without per-file fork | [VERIFIED: STACK.md] |
| `cp -a` / `cp -Rp` | macOS 10.5+ / POSIX fallback | Snapshot creation preserving symlinks + timestamps | [VERIFIED: STACK.md] |
| `sha256sum` (Linux) / `shasum -a 256` (macOS) | system | mutate_archive copy-verify step (D-13) | [ASSUMED] — both available on supported platforms |
| `jq -cn --arg ... --slurpfile` | system (preflight dep) | Manifest construction; injection-safe | [VERIFIED: STACK.md] |
| `date -u +%Y%m%dT%H%M%SZ` | POSIX | UTC timestamps for snapshot/archive dirs (M-4) | [VERIFIED: PITFALLS.md M-4] |
| `wc -l < "$path"` | POSIX | Cap detection; redirect form avoids filename noise | [VERIFIED: STACK.md] |
| `git status --porcelain=v1` | git (preflight dep) | Used in lib/snapshot.sh for snapshot-meta.json git state | [VERIFIED: STACK.md] |

### What NOT to Add

| Avoid | Why |
|-------|-----|
| `ripgrep` / `fd` | Not in preflight; `find -print0 | xargs -0` is sufficient for 500 files |
| `git log --since=N.days -- <path>` per file | D-05 explicitly removed this; ~500 git-log forks was the CR-7 threat |
| Associative arrays (`declare -A`) | POSIX bash 3.2+ constraint forbids; use newline-delimited state instead |
| `mapfile` / `readarray` | Bash 4+ only; not on macOS default bash 3.2 |
| `local -n` nameref | Bash 4.3+ only |
| Any npm package | zero-deps envelope |

**Installation:** none required — all tools are already in the preflight stack.

---

## Package Legitimacy Audit

Phase 21 installs zero external packages. All tools used are either POSIX utilities or already-declared preflight dependencies. This section is not applicable.

**Packages removed due to slopcheck verdict:** none
**Packages flagged as suspicious:** none

---

## Architecture Patterns

### System Architecture Diagram

```
lib/caps.sh
  ├─ exports: CLAUDE_MD_CAP=100, SKILL_MD_CAP=200, AGENT_MD_CAP=80
  └─ sources lib/mutate.sh → calls mutate_archive for stale-file moves

lib/log.sh
  ├─ log_init <target_dir>   → creates RESTRUCTURE-LOG.md header via mutate_write
  ├─ log_step <phase> <msg>  → appends [TIMESTAMP] [PHASE] msg via mutate_write --append
  └─ log_fail <msg>          → appends FAIL entry, exits 1

lib/snapshot.sh (depends on log.sh)
  ├─ snapshot_create <target> <backup_root>
  │    raw cp -a (NOT mutate_cp) → .conjure-adopt-backups/conjure-adopt-<UTC-ts>/
  │    writes snapshot-meta.json (git HEAD sha + stash list)
  │    calls log_step SNAPSHOT
  ├─ snapshot_rollback <snapshot_path> <target>
  │    raw cp -a restore + log_step ROLLBACK
  └─ snapshot_list <backup_root>    → sorted newest-first listing

lib/inventory.sh (depends on log.sh, caps.sh)
  ├─ inventory_scan <target>
  │    find -name '*.md' -not path '*/.git/*'
  │                       -not path '*/node_modules/*'
  │                       -not path '*/.conjure-adopt-backups/*'
  │    skip: symlinks (test -L), binary (LC_ALL=C grep -P "\x00")
  │    total count (cheap find | wc -l), cap at 500 (D-08)
  │    harness-first budget ordering (D-10)
  │    → populates CONJURE_INVENTORY_ITEMS (newline-delimited)
  ├─ inventory_classify <filepath> <claude_md_links_file>
  │    path-based decision tree (D-03):
  │      .claude/settings.json or root CLAUDE.md    → core
  │      .claude/skills/*/SKILL.md                  → skill
  │      .claude/agents/*.md                        → agent
  │      .planning/**                               → planning-doc
  │      docs/ | README.md | CHANGELOG | *.adr.md   → reference-doc (D-07)
  │      in CLAUDE.md outbound links (D-06)         → reference-doc
  │      everything else                            → unknown
  │    size_cap_exceeded: wc -l vs cap from caps.sh (D-09)
  └─ inventory_emit_manifest <target> <output_path>
       jq -cn build → mutate_write (DRY_RUN → /tmp/adopt-manifest-dryrun.json)
       calls log_step INVENTORY

lib/mutate.sh (existing — add mutate_archive only)
  └─ mutate_archive <src> <archive_root>
       1. mkdir -p archive_root/path/of/src
       2. cp -a src → archive_root/path/of/src
       3. sha256 dest == sha256 src (abort if mismatch)
       4. rm -f src
       5. append ledger entry
       DRY_RUN → print [dry-run] would archive, increment counter
```

### Recommended Project Structure (files touched/created this phase)

```
lib/
  caps.sh          # NEW — CLAUDE_MD_CAP=100, SKILL_MD_CAP=200, AGENT_MD_CAP=80 + mutate_archive
  log.sh           # NEW — log_init / log_step / log_fail
  snapshot.sh      # NEW — snapshot_create / snapshot_rollback / snapshot_list
  inventory.sh     # NEW — inventory_scan / inventory_classify / inventory_emit_manifest
  mutate.sh        # MODIFIED — add mutate_archive function only; all else unchanged

scripts/
  audit-setup.sh   # MODIFIED — source lib/caps.sh; remove inline cap literals (call-site only)

tests/
  fixtures/
    brownfield-simple/      # NEW fixture — small representative repo for unit tests
      CLAUDE.md             # 15-line valid core doc
      .claude/skills/git/SKILL.md
      .claude/agents/deploy.md
      docs/README.md
      .planning/21-PLAN.md
      symlink-target -> docs/README.md   # symlink skip test
  run.sh           # MODIFIED — add Phase 21 lib tests
```

### Pattern 1: lib shebang + sourcing guard

All new lib files follow the pattern from `lib/mutate.sh` and `lib/merge.sh`: no shebang (they are sourced, not executed), POSIX bash 3.2+, module-level state initialization with `${VAR:-default}` guards for idempotent re-source.

```bash
# lib/caps.sh — sourced cap constants for Conjure.
# Source this file; do not execute directly.
# Requires: lib/mutate.sh already sourced (for mutate_archive).
# POSIX bash 3.2+. No associative arrays, no mapfile, no local -n.

CLAUDE_MD_CAP=100
SKILL_MD_CAP=200
AGENT_MD_CAP=80
```
[VERIFIED: lib/mutate.sh lines 1-17, lib/merge.sh lines 1-15 — sourcing pattern confirmed from live source]

### Pattern 2: mutate_write --append for log entries

`lib/log.sh` writes via `mutate_write --append`. The `mutate_write` function (confirmed from source) uses `printf '%s'` — no trailing newline. Log entries must include their own `\n` to avoid joining with the next line.

```bash
# lib/log.sh — RESTRUCTURE-LOG.md writer.
# Source this file; requires lib/mutate.sh already sourced and DRY_RUN set.

# log_step <phase> <message>
log_step() {
  local phase="$1"
  local message="$2"
  local ts
  ts="$(date -u '+%Y-%m-%d %H:%M:%S')"
  local entry="[${ts}] [${phase}] ${message}
"
  mutate_write "${RESTRUCTURE_LOG_PATH}" "${entry}" --append
}
```
[VERIFIED: lib/mutate.sh lines 51-65 — mutate_write uses printf '%s', no trailing newline]

### Pattern 3: snapshot_create using raw cp (NOT mutate_cp)

Snapshot must be unconditional in live mode. DRY_RUN suppresses `mutate_*` calls — if snapshot were routed through `mutate_cp`, a dry run would have no backup. The anti-pattern from ARCHITECTURE.md is explicit. In dry-run mode: print the would-be snapshot path, skip `cp -a`.

```bash
snapshot_create() {
  local target="$1"
  local backup_root="$2"
  local ts
  ts="$(date -u '+%Y%m%dT%H%M%SZ')"
  local snap_dir="${backup_root}/conjure-adopt-${ts}"
  if [ "${DRY_RUN:-0}" = "1" ]; then
    echo "[dry-run] would snapshot ${target} → ${snap_dir}"
    CONJURE_SNAPSHOT_PATH="${snap_dir}"
    return 0
  fi
  mkdir -p "${snap_dir}"
  cp -a "${target}/." "${snap_dir}/"         # preserve symlinks + timestamps
  # Fallback: if cp -a fails (old platform), retry with cp -Rp
  CONJURE_SNAPSHOT_PATH="${snap_dir}"
  log_step SNAPSHOT "created at ${snap_dir}"
}
```
[VERIFIED: ARCHITECTURE.md Anti-Pattern 2; STACK.md cp -a/cp -Rp; PITFALLS.md M-4]

### Pattern 4: POSIX bash 3.2+ file iteration (no process substitution)

`lib/merge.sh` uses `mktemp` + `while IFS= read -r` because bash 3.2 does not support `while ... done < <(cmd)` reliably. `lib/inventory.sh` must follow the same pattern.

```bash
# CORRECT — bash 3.2 compatible
_find_list="$(mktemp)"
find "${target}" -name '*.md' \
  -not -path '*/.git/*' \
  -not -path '*/node_modules/*' \
  -not -path '*/.conjure-adopt-backups/*' \
  > "${_find_list}"
while IFS= read -r filepath; do
  # process each file
  :
done < "${_find_list}"
rm -f "${_find_list}"
```
[VERIFIED: lib/merge.sh lines 107-123 — identical mktemp + read pattern confirmed from live source]

### Pattern 5: mutate_archive (D-11/D-12/D-13) — move-safety sequence

```bash
# mutate_archive <src_abs> <archive_root>
# Moves src to archive_root preserving path structure. Never deletes without verify.
mutate_archive() {
  local src="$1"
  local archive_root="$2"
  if [ "${DRY_RUN:-0}" = "1" ]; then
    echo "[dry-run] would archive ${src} → ${archive_root}/..."
    CONJURE_DRY_MUTATION_COUNT=$((CONJURE_DRY_MUTATION_COUNT + 1))
    return 0
  fi
  # Derive mirror path (D-12)
  local rel="${src#/}"           # strip leading slash for path-preserving layout
  local dest="${archive_root}/${rel}"
  mkdir -p "$(dirname "${dest}")"
  cp -a "${src}" "${dest}"
  # Verify (D-13) — sha256sum Linux / shasum macOS
  local src_hash dest_hash
  if command -v sha256sum >/dev/null 2>&1; then
    src_hash="$(sha256sum "${src}" | cut -d' ' -f1)"
    dest_hash="$(sha256sum "${dest}" | cut -d' ' -f1)"
  else
    src_hash="$(shasum -a 256 "${src}" | cut -d' ' -f1)"
    dest_hash="$(shasum -a 256 "${dest}" | cut -d' ' -f1)"
  fi
  if [ "${src_hash}" != "${dest_hash}" ]; then
    echo "[mutate_archive] ABORT: sha256 mismatch for ${src} — original preserved" >&2
    rm -f "${dest}"
    return 1
  fi
  rm -f "${src}"
  # Ledger entry (D-13)
  local ledger="${archive_root}/.archive-ledger"
  printf '%s\t%s\t%s\t%s\n' \
    "${src}" "${dest}" "${src_hash}" "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
    >> "${ledger}"
  CONJURE_DRY_MUTATION_COUNT=$((CONJURE_DRY_MUTATION_COUNT + 1))
}
```
[ASSUMED] — pattern derived from D-11/D-12/D-13 decisions and lib/mutate.sh conventions; not yet in codebase

### Pattern 6: Classification decision tree (D-01 through D-07)

```bash
inventory_classify() {
  local filepath="$1"   # absolute path
  local target="$2"     # repo root absolute
  local links_file="$3" # tmp file with CLAUDE.md outbound link paths (one per line)
  local rel="${filepath#${target}/}"

  # Skip symlinks (M-2)
  [ -L "${filepath}" ] && echo "SKIP:symlink" && return 0

  # core — CLAUDE.md at root or .claude/settings.json
  case "${rel}" in
    CLAUDE.md|.claude/settings.json) echo "core"; return 0 ;;
  esac

  # skill — .claude/skills/*/SKILL.md
  case "${rel}" in
    .claude/skills/*/SKILL.md) echo "skill"; return 0 ;;
  esac

  # agent — .claude/agents/*.md
  case "${rel}" in
    .claude/agents/*.md) echo "agent"; return 0 ;;
  esac

  # planning-doc — .planning/**
  case "${rel}" in
    .planning/*) echo "planning-doc"; return 0 ;;
  esac

  # reference-doc by path (D-07)
  case "${rel}" in
    docs/*|README.md|CHANGELOG.md|CHANGELOG|*.adr.md|ARCHITECTURE.md)
      echo "reference-doc"; return 0 ;;
  esac

  # reference-doc by CLAUDE.md link (D-06/D-07)
  if grep -qxF "${rel}" "${links_file}" 2>/dev/null; then
    echo "reference-doc"; return 0
  fi

  echo "unknown"
}
```
[ASSUMED] — derived from D-01 through D-07 decisions; to be verified against test fixtures during implementation

### Pattern 7: Finalized adopt-manifest.json schema

The ARCHITECTURE.md sample with all context decisions applied (D-01 bucket names, D-05 git_age_days removed, D-08 scan_capped/total_found added, D-09 cap_exceeded renamed to size_cap_exceeded):

```json
{
  "schema_version": "1",
  "generated_at": "2026-05-28T14:23:00Z",
  "conjure_version": "0.6.0",
  "target": "/abs/path/to/repo",
  "snapshot_path": "",
  "summary": {
    "total_files": 47,
    "scan_capped": false,
    "total_found": 47,
    "core": 1,
    "skill": 3,
    "agent": 1,
    "planning-doc": 8,
    "reference-doc": 4,
    "unknown": 30
  },
  "files": [
    {
      "path": "CLAUDE.md",
      "classification": "core",
      "line_count": 87,
      "size_bytes": 4200,
      "size_cap_exceeded": false,
      "size_cap_limit": 100,
      "linked_from": []
    },
    {
      "path": "docs/guide.md",
      "classification": "reference-doc",
      "line_count": 45,
      "size_bytes": 1800,
      "size_cap_exceeded": false,
      "size_cap_limit": null,
      "linked_from": ["CLAUDE.md"]
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
  "harness_missing_layers": [],
  "restructure_steps": []
}
```

**Field notes:**
- `summary.scan_capped`: true when total_found > 500 and scan was capped at 500 (D-08)
- `summary.total_found`: raw count from `find | wc -l` before cap applied (D-08)
- `files[].size_cap_exceeded`: true when line_count > size_cap_limit (D-09)
- `files[].size_cap_limit`: 100 for core, 200 for skill, 80 for agent, null for other buckets
- `files[].linked_from`: `["CLAUDE.md"]` if linked via D-06 pass, else `[]`
- `git_age_days` field: removed per D-05
- `restructure_steps[]`: always empty at inventory time; populated by skill in Phase 23
- `snapshot_path`: empty string at inventory time; filled by scripts/adopt.sh in Phase 22

[ASSUMED] — schema derived from ARCHITECTURE.md §3 plus D-01/D-05/D-08/D-09 overrides; to be validated against a JSON Schema file created this phase

### Anti-Patterns to Avoid

- **Snapshot via mutate_cp:** `mutate_cp` is DRY_RUN-guarded — suppressing the snapshot removes the safety net. Use raw `cp -a` unconditionally in live mode.
- **Manifest write via printf/heredoc:** bypasses `mutate_write`, DRY_RUN not honored. Always use `mutate_write`.
- **Process substitution `while ... done < <(cmd)`:** bash 3.2 incompatible. Use `mktemp` + `while IFS= read -r`.
- **`cp -r` (lowercase) for snapshot:** `cp -r` may dereference symlinks on some platforms. Use `cp -a` (GNU/macOS 10.5+) or `cp -Rp` (POSIX) to preserve symlink structure (M-2).
- **`printf '%s'` without `\n` for appended log entries:** mutate_write uses `printf '%s'` — without an explicit `\n` in the content, consecutive log_step calls produce one joined line.
- **Hardcoding cap values:** use `$CLAUDE_MD_CAP`, `$SKILL_MD_CAP`, `$AGENT_MD_CAP` from `lib/caps.sh` — never re-declare literals in inventory.sh or log.sh.
- **mutate_rm on user content:** SAFE-03 forbids deleting user files. `mutate_archive` is the only operation for stale files.
- **Using `git log` per-file in inventory:** D-05 forbids this. ~500 git-log subprocess calls is the primary CR-7 performance threat.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| UTC timestamps | date logic in bash | `date -u +%Y%m%dT%H%M%SZ` | POSIX, matches M-4 guidance, produces unambiguous Z-suffix |
| Symlink detection | inode stat parsing | `test -L "$filepath"` | POSIX builtin, zero deps |
| Binary file detection | magic byte table | `LC_ALL=C grep -Pc "\x00" "$f"` | One-liner; POSIX-compatible approach from PITFALLS.md M-2 |
| sha256 computation | custom hash | `sha256sum` (Linux) / `shasum -a 256` (macOS) — both in POSIX env | Platform-native, no deps, already in preflight |
| JSON manifest construction | shell string concat | `jq -cn --arg --argjson --slurpfile` | Injection-safe; no shell quoting hazards; already required by preflight |
| File line counting | custom wc | `wc -l < "$path"` | Redirect form (no filename noise), POSIX, consistent with audit-setup.sh |
| Batch find + count | per-file subshell | `find -print0 | xargs -0 wc -l` | Single command, handles 2000+ files in <2s on NVMe (STACK.md verified) |

---

## Common Pitfalls

### Pitfall 1: mutate_write leaves no trailing newline (MN-3)

**What goes wrong:** `mutate_write` uses `printf '%s'` — no trailing newline. If `log_step` passes `"[TS] [PHASE] msg"` without a `\n`, consecutive appends join lines: `"[TS1] [PHASE1] msg1[TS2] [PHASE2] msg2"`.

**Root cause:** mutate_write is correct for its general purpose (no forced newline). Log entries must own their own line termination.

**How to avoid:** Always include `\n` in log entry strings: `local entry="[${ts}] [${phase}] ${message}\n"`. Verify in test: grep for `^\[` line count == expected number of entries.

### Pitfall 2: Classification false-promotes non-harness files (D-03)

**What goes wrong:** A SKILL.md living outside `.claude/skills/` is not a harness skill — it is a candidate for the restructure skill to judge (Phase 23). Auto-promoting it to `skill` bucket violates D-03's conservative path-based contract and misleads the downstream skill.

**Root cause:** Frontmatter-first classification (checking `name:` / `description:`) before path check.

**How to avoid:** Path check runs first, always. Frontmatter is checked only to confirm files already in harness directories (e.g., to compute `size_cap_limit` for `.claude/skills/*/SKILL.md`).

### Pitfall 3: Scan count bypasses harness-first budget (D-10)

**What goes wrong:** `find` returns files in filesystem order. On a capped 500-file scan, `.planning/` docs might crowd out `.claude/skills/` files if filesystem order puts `.planning/` first. The skill then cannot see the harness state.

**Root cause:** Naive `find | head -500`.

**How to avoid:** Two-pass inventory: Pass 1 collects `.claude/**` + CLAUDE.md + `.planning/**` (always included). Pass 2 fills the remainder of the 500 budget from all other `.md` files. Implement via separate `find` calls with explicit ordering.

### Pitfall 4: mutate_archive sha256 command unavailable

**What goes wrong:** `sha256sum` is the Linux command; macOS ships `shasum`. If only one is checked, archive fails on the other platform with a "command not found" error, leaving the file in an inconsistent state (dest exists, src not yet removed).

**Root cause:** Assuming one platform's sha256 binary.

**How to avoid:** Check `command -v sha256sum` first; fall back to `shasum -a 256`. Abort the archive entirely if neither is available (never leave a partial state — do not `rm` without verifying).

### Pitfall 5: cp -a unavailable on very old macOS / minimal Alpine

**What goes wrong:** `cp -a` is documented as macOS 10.5+ but CI might use a minimal Alpine image where `cp -a` behaves differently or is not present.

**Root cause:** Assuming GNU/macOS cp -a parity.

**How to avoid:** Test `cp -a` in preflight; fall back to `cp -Rp` on failure. ARCHITECTURE.md already documents this: `cp -Rp` is the POSIX fallback.

### Pitfall 6: jq emit for large manifests

**What goes wrong:** Building the full `files[]` array via string concatenation in bash then passing to `jq --argjson` hits shell ARG_MAX on some systems when the array exceeds ~100KB.

**Root cause:** Bash-side JSON assembly.

**How to avoid:** Use `jq --slurpfile` with a JSONL temp file. Write one JSON object per file to a temp file, then `jq -cn --slurpfile files /tmp/items.jsonl '$files'` assembles the array without shell string limits.

---

## Runtime State Inventory

Phase 21 is a greenfield library addition — no rename, no refactor, no data migration.

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | None — no new datastores introduced | None |
| Live service config | None | None |
| OS-registered state | None | None |
| Secrets/env vars | None — `CLAUDE_MD_CAP`, `SKILL_MD_CAP`, `AGENT_MD_CAP` are constants, not secrets | None |
| Build artifacts | `scripts/audit-setup.sh` references inline cap literals (100/200/80) — verified at lines 26, 54, 78 | Call-site change only: source lib/caps.sh + use `$CLAUDE_MD_CAP` etc. |

---

## Code Examples

### Extract CLAUDE.md outbound links (D-06)

```bash
# Source: CONTEXT.md D-06 + ARCHITECTURE.md §2 classification logic
# Produces a temp file with one relative path per outbound link from CLAUDE.md.
extract_claude_md_links() {
  local target="$1"
  local links_file
  links_file="$(mktemp)"
  if [ -f "${target}/CLAUDE.md" ]; then
    grep -oE '\]\([^)]+\)' "${target}/CLAUDE.md" \
      | sed 's/^](\(.*\))$/\1/' \
      | grep -v '^http' \
      > "${links_file}"
  fi
  echo "${links_file}"  # caller must rm -f this file
}
```

### Build file entry for manifest (one object per file)

```bash
# Source: ARCHITECTURE.md §3 + D-09 size_cap_exceeded rename + D-05 git_age_days removal
# Writes one JSON object (line) to a JSONL accumulator file.
emit_file_entry() {
  local path="$1" classification="$2" line_count="$3"
  local size_bytes="$4" cap_limit="$5" linked_from_json="$6"
  local size_cap_exceeded="false"
  if [ -n "${cap_limit}" ] && [ "${cap_limit}" != "null" ]; then
    [ "${line_count}" -gt "${cap_limit}" ] && size_cap_exceeded="true"
  fi
  jq -cn \
    --arg path "${path}" \
    --arg classification "${classification}" \
    --argjson line_count "${line_count}" \
    --argjson size_bytes "${size_bytes}" \
    --argjson size_cap_exceeded "${size_cap_exceeded}" \
    --argjson size_cap_limit "${cap_limit:-null}" \
    --argjson linked_from "${linked_from_json}" \
    '{path: $path, classification: $classification,
      line_count: $line_count, size_bytes: $size_bytes,
      size_cap_exceeded: $size_cap_exceeded,
      size_cap_limit: $size_cap_limit,
      linked_from: $linked_from}'
}
```

### audit-setup.sh call-site change (caps.sh extraction)

```bash
# BEFORE (audit-setup.sh lines 26, 54, 78 — inline literals):
if [ "$LINES" -le 100 ]; then ...
if [ "$LINES" -gt 200 ]; then ...
if [ "$LINES" -gt 80 ]; then ...

# AFTER — add near top of audit-setup.sh:
source "${CONJURE_HOME}/lib/caps.sh"
# Then replace literals:
if [ "$LINES" -le "${CLAUDE_MD_CAP}" ]; then ...
if [ "$LINES" -gt "${SKILL_MD_CAP}" ]; then ...
if [ "$LINES" -gt "${AGENT_MD_CAP}" ]; then ...
```
[VERIFIED: scripts/audit-setup.sh lines 26, 54, 78 — inline cap values confirmed from live source]

---

## State of the Art

| Old Approach (ARCHITECTURE.md draft) | Current Approach (D-01 applied) | Why Changed |
|---------------------------------------|----------------------------------|-------------|
| 11 classification tags (candidate-skill, candidate-agent, stale-candidate, harness-hook, reference-linked…) | 6 deterministic buckets (core/skill/agent/planning-doc/reference-doc/unknown) | LLM judgment tags belong to restructure skill (D-02); CLI is path-based only (D-03) |
| `cap_exceeded` field name | `size_cap_exceeded` (D-09) | Avoided name collision with `summary.scan_capped` |
| `summary.total_files` only | `summary.scan_capped` + `summary.total_found` + per-bucket counts | D-08 overflow semantics require two distinct overflow signals |
| `git_age_days` per file | removed | D-05: ~500 git-log forks is the CR-7 performance threat; staleness is skill judgment |
| `at_imports_detected` global field | retained | Not overridden by any decision; useful for Phase 22 audit gate |
| `snapshot_path` in manifest | empty string at inventory time | `snapshot_path` is filled by scripts/adopt.sh (Phase 22) — not known at inventory time |

**Deprecated/outdated in earlier research:**
- 11-tag classification scheme: replaced by 6-bucket scheme per D-01/D-02. Do not implement the 11-tag scheme in Phase 21 inventory.

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `sha256sum` (Linux) / `shasum -a 256` (macOS) are both available on all CI targets | Pattern 5 (mutate_archive), Common Pitfall 4 | mutate_archive fails at verify step; need a third fallback or a preflight check |
| A2 | `cp -a` is available on all CI targets (macOS 10.5+, all GNU Linux) | Pattern 3 (snapshot_create), Pitfall 5 | Must fall back to `cp -Rp`; snapshot structure may differ |
| A3 | inventory_classify path-based decision tree handles all real-world path conventions | Pattern 6 (classification) | Edge cases (e.g., `.claude/skills/nested/sub/SKILL.md`) may fall to `unknown` incorrectly — acceptable per D-03 |
| A4 | jq --slurpfile is supported by the jq versions in the preflight stack | Code Example (emit_file_entry) | May need `--rawfile` or a different accumulation strategy on jq <1.6 |
| A5 | RESTRUCTURE-LOG.md lives at `<target_dir>/RESTRUCTURE-LOG.md` (per ARCHITECTURE.md) | Architecture Patterns, Pattern 2 | Planner discretion to place elsewhere; path must be consistent across all log.sh callers |

**If this table is empty:** — it is not empty; see above.

---

## Open Questions

1. **RESTRUCTURE-LOG.md exact path and header format**
   - What we know: ARCHITECTURE.md §5 shows a sample header with `conjure:`, `target:`, `started:`, `snapshot:` YAML-ish fields, followed by `---` separator and entries.
   - What's unclear: whether the log should live at `<target>/RESTRUCTURE-LOG.md` (repo root) or `<target>/.claude/RESTRUCTURE-LOG.md`. Repo root is more discoverable; `.claude/` is more contained.
   - Recommendation: Planner's discretion — repo root is recommended for discoverability (matches ARCHITECTURE.md sample).

2. **sha256 cross-platform command selection**
   - What we know: `sha256sum` (Linux/GNU) and `shasum -a 256` (macOS) both produce the same hash. Neither is guaranteed everywhere.
   - What's unclear: Whether the project's CI matrix includes platforms that have neither (e.g., minimal Alpine without coreutils).
   - Recommendation: Add a preflight check for sha256 capability in `lib/caps.sh` or `mutate_archive`; abort with a clear message if neither is found rather than silently failing the verify step.

3. **adopt-manifest.json location: repo root vs .claude/**
   - What we know: ARCHITECTURE.md places it at `<target>/adopt-manifest.json` (repo root). The CONTEXT.md notes "lives at repo root so the skill can reference it with a simple Read tool call."
   - What's unclear: Whether `.claudeignore` should exclude it to prevent it from being eagerly loaded into context.
   - Recommendation: Repo root is correct per CONTEXT.md. Plan should add `adopt-manifest.json` to `.claudeignore` (or note this for Phase 22 when adopt.sh modifies gitignore/claudeignore).

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| bash 3.2+ | All lib files | ✓ | macOS default 3.2.57; Linux 5.x | None needed |
| jq | inventory_emit_manifest, mutate_archive ledger reads | ✓ | preflight-checked | None (hard dep) |
| find (POSIX) | inventory_scan | ✓ | system | None |
| cp -a | snapshot_create, mutate_archive | ✓ macOS/GNU | macOS 10.5+ | cp -Rp (POSIX) |
| sha256sum / shasum | mutate_archive D-13 verify | ✓ Linux/macOS | system | Abort if neither found |
| date -u | all timestamp generation | ✓ | POSIX | None |
| wc -l | cap detection | ✓ | POSIX | None |
| git status --porcelain=v1 | snapshot-meta.json | ✓ | preflight-checked | Skip git state if not a git repo |

**Missing dependencies with no fallback:** none identified.

**Missing dependencies with fallback:** `sha256sum`/`shasum` — both should be checked; abort if neither.

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Hand-rolled `tests/run.sh` (pass/fail/t helpers) |
| Config file | none — `tests/run.sh` is self-contained |
| Quick run command | `bash tests/run.sh 2>&1 \| tail -20` |
| Full suite command | `bash tests/run.sh` |

Nyquist validation is enabled (`workflow.nyquist_validation: true` in `.planning/config.json`). Tests must be runnable in < 30 seconds for the quick-check gate.

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| INV-01 | classify markdown files into 6 buckets | unit | `bash tests/run.sh 2>&1 \| grep -E "INV-01\|classify"` | ❌ Wave 0 |
| INV-01 | unknown bucket for file outside harness dirs | unit | inline in run.sh | ❌ Wave 0 |
| INV-02 | emit adopt-manifest.json with required top-level keys | unit | inline in run.sh — `jq '.schema_version' adopt-manifest.json` | ❌ Wave 0 |
| INV-02 | summary.* counts match files[] classifications | unit | inline in run.sh | ❌ Wave 0 |
| INV-03 | symlinks skipped; RESTRUCTURE-LOG records skip reason | unit | inline in run.sh with fixture symlink | ❌ Wave 0 |
| INV-03 | >500 file cap: summary.scan_capped=true, total_found>500 | unit | inline in run.sh with synthetic 510-file fixture | ❌ Wave 0 |
| INV-03 | harness-first budget: .claude/** never cut by cap | unit | inline in run.sh | ❌ Wave 0 |
| INV-04 | size_cap_exceeded=true for file over cap | unit | inline in run.sh | ❌ Wave 0 |
| INV-04 | size_cap_violations[] populated | unit | inline in run.sh | ❌ Wave 0 |
| SAFE-03 | mutate_archive: file moved not deleted | unit | inline in run.sh | ❌ Wave 0 |
| SAFE-03 | mutate_archive: sha256 mismatch aborts, src preserved | unit | inline in run.sh (corrupt dest before verify) | ❌ Wave 0 |
| SAFE-03 | mutate_archive DRY_RUN: prints [dry-run] would archive, no file moved | unit | inline in run.sh | ❌ Wave 0 |
| SAFE-03 | archive ledger entry written with ts + sha256 | unit | inline in run.sh | ❌ Wave 0 |
| Phase SC-1 | lib/log.sh: log_init creates RESTRUCTURE-LOG.md header | unit | inline in run.sh | ❌ Wave 0 |
| Phase SC-1 | lib/log.sh: log_step appends [TIMESTAMP] [PHASE] msg | unit | inline in run.sh | ❌ Wave 0 |
| Phase SC-1 | lib/log.sh: DRY_RUN=1 prints entries, no file write | unit | inline in run.sh | ❌ Wave 0 |
| Phase SC-2 | lib/snapshot.sh: snapshot dir non-empty, contains CLAUDE.md and .claude/ | unit | inline in run.sh | ❌ Wave 0 |
| Phase SC-2 | lib/snapshot.sh: DRY_RUN=1 prints path, no cp | unit | inline in run.sh | ❌ Wave 0 |
| Phase SC-4 | adopt-manifest.json sample validates against schema | unit | `jq 'empty' < schema.json && echo ok` | ❌ Wave 0 |
| Phase SC-5 | lib/caps.sh: CLAUDE_MD_CAP=100, SKILL_MD_CAP=200, AGENT_MD_CAP=80 exported | unit | inline in run.sh | ❌ Wave 0 |
| Phase SC-5 | audit-setup.sh uses $CLAUDE_MD_CAP (not literal 100) | smoke | `grep -c 'CLAUDE_MD_CAP' scripts/audit-setup.sh` | ❌ Wave 0 |
| CR-7 perf | --dry-run on 500-file fixture completes < 30s | perf | `time bash tests/run.sh [perf-test]` | ❌ Wave 0 |

### Sampling Rate

- **Per task commit:** `bash tests/run.sh 2>&1 | grep -E "✓|✗|PASS|FAIL"` — verify no regressions against existing 302+ assertions
- **Per wave merge:** `bash tests/run.sh` — full suite including new Phase 21 lib tests
- **Phase gate:** Full suite green before `/gsd-verify-work`

### Wave 0 Gaps

- [ ] `tests/fixtures/brownfield-simple/` — representative fixture with CLAUDE.md, skill, agent, docs/, .planning/, and a symlink for M-2 tests
- [ ] `tests/fixtures/brownfield-simple/generate-large.sh` — script to generate 510+ .md files for cap tests (synthetic, not committed; generated at test time)
- [ ] Phase 21 test block in `tests/run.sh` — covering all Req IDs above
- [ ] `adopt-manifest.schema.json` — JSON Schema file (draft-07) for manifest validation; lives at root or in `schemas/`

*(Existing 302+ test infrastructure covers other phases; Wave 0 adds the brownfield-simple fixture and Phase 21 test block only.)*

---

## Project Constraints (from CLAUDE.md)

| Directive | Impact on Phase 21 |
|-----------|-------------------|
| Tech stack: POSIX bash + Node.js `.mjs` hooks | All lib files must be POSIX bash 3.2+; no associative arrays, no `mapfile`, no `local -n` |
| Safety: backup-before-mutate on every change | snapshot.sh must execute before any mutate_* call; mutate_archive must copy-verify before rm |
| Hooks `exit 2` (never `exit 1`) | `log_fail` should call `exit 2`, not `exit 1`; lib functions use `return 1` for errors |
| Size caps: CLAUDE.md ≤100, SKILL.md ≤200, agent ≤80 | lib/caps.sh is the single source for these values; all consumers must source it |
| Claude Code ≥2.1.117; `@imports` forbidden in CLAUDE.md | RESTRUCTURE-LOG.md must not contain `@import` lines; manifest must flag `at_imports_detected` |
| Quality gate: every PR passes shellcheck, JSON Schema, frontmatter, size caps, coverage | New lib files must pass shellcheck; manifest schema file enables JSON Schema check; tests must cover all new functions |
| No `curl \| sh` foot-guns | Not applicable to this phase (no installation steps) |
| `dependencies: {}` stays empty | No npm packages; zero new deps confirmed |

---

## Security Domain

`security_enforcement` is not set to `false` in `.planning/config.json`. Phase 21 operates entirely on local filesystem files with no network I/O, no authentication, no user-generated input from untrusted sources. The applicable threat surface is narrow.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | No | Not applicable — local CLI tool |
| V3 Session Management | No | Not applicable |
| V4 Access Control | No | Not applicable |
| V5 Input Validation | Partial | `jq` parse-checks manifest JSON; path inputs to classification are repo-local files |
| V6 Cryptography | Partial | sha256 via `sha256sum`/`shasum` — system tools, never hand-rolled |

### Known Threat Patterns for this stack

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Path traversal in manifest paths | Tampering | All paths stored as absolute paths (M-4); `find` scoped to `$target`; never `eval` path strings |
| Shell injection via filenames | Tampering | `find -print0 \| xargs -0` null-delimiter handling; `"$filepath"` always quoted; `jq --arg` for JSON encoding |
| Archive to wrong location | Tampering | `mutate_archive` derives dest from `archive_root + src_rel` — never from user-supplied dest string |
| Unverified copy delete | Tampering / Denial | D-13 sha256 verify before `rm`; abort if mismatch |

---

## Sources

### Primary (HIGH confidence)
- `lib/mutate.sh` — full source read this session; mutate_write behavior, DRY_RUN pattern, counter idiom all confirmed [VERIFIED: live source]
- `lib/merge.sh` — full source read this session; mktemp + while IFS= read pattern, module-level state initialization confirmed [VERIFIED: live source]
- `scripts/audit-setup.sh` lines 1-100 — inline cap literals at lines 26, 54, 78 confirmed [VERIFIED: live source]
- `.planning/phases/21-foundation-libs-inventory/21-CONTEXT.md` — all 13 decisions D-01..D-13 [VERIFIED: planning artifact]
- `.planning/research/ARCHITECTURE.md` — §2 inventory functions + classification, §3 manifest schema sample [VERIFIED: planning artifact]
- `.planning/research/STACK.md` — POSIX primitives verified against official docs (find, cp, wc, jq, date) [VERIFIED: planning artifact]
- `.planning/research/PITFALLS.md` — M-2, M-4, CR-4, CR-7 pitfalls [VERIFIED: planning artifact]
- `.planning/research/SUMMARY.md` — build order, CR-1..7 summary, Phase 1 scope [VERIFIED: planning artifact]
- `.planning/config.json` — `nyquist_validation: true` confirmed [VERIFIED: live source]
- `.planning/REQUIREMENTS.md` — INV-01..04, SAFE-03, ADOPT-03 requirement text [VERIFIED: planning artifact]

### Secondary (MEDIUM confidence)
- `.planning/STATE.md` — current position, key v0.6.0 design decisions summary [VERIFIED: planning artifact]

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all tools are verified in STACK.md against official docs; zero new deps
- Architecture patterns: HIGH — derived from live source (mutate.sh, merge.sh) and locked decisions (D-01..D-13)
- Classification logic: HIGH for bucket names and decision tree structure; ASSUMED for edge-case path patterns (A3)
- mutate_archive: HIGH for contract (D-11/D-12/D-13); ASSUMED for sha256 cross-platform detection (A1)
- Manifest schema: HIGH for required fields and D-01/D-09 overrides; ASSUMED until validated against JSON Schema stub
- Test architecture: HIGH — test harness pattern confirmed from live tests/run.sh and tests/lib/sandbox.sh

**Research date:** 2026-05-28
**Valid until:** 2026-06-28 (stable POSIX domain; 30 days)
