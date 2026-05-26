# Phase 17: Drift Detection — Context

**Date:** 2026-05-26
**Phase:** 17 of 20 — Drift Detection
**Goal:** Users can discover whether their installed harness has drifted from the upstream kit snapshot via a single read-only command

---

## Domain

User-facing CLI command: `conjure check`. Read-only — no mutations. Compares installed harness files against the upstream kit snapshot (the files conjure would install/update) and prints a file-level delta report.

---

## Decisions

### Drift classification (3-way)

- **Categories**: `added` (in harness, not in kit), `modified` (in both, content differs), `removed` (in kit, not in harness)
- **Algorithm**: compare sha256 of each file; no git involvement — pure filesystem diff
- **Upstream snapshot source**: the kit files bundled in `$CONJURE_HOME` (the installed conjure directory itself, e.g. `profiles/`, `compliance/`, `CLAUDE.md` template, etc.)
- **Comparison target**: the harness root directory (current working directory, or passed as arg)

### What files are compared

- Compare files listed in the kit manifest OR all files the kit would install (discover from existing `cmd_init` / `cmd_update` logic)
- If no manifest exists, fall back to known kit file patterns: `CLAUDE.md`, `.claude/skills/`, `.claude/hooks/`, `.claude/settings.json`, `lib/`, `scripts/`, `profiles/`
- User-added files (not in kit) are reported as `added` — not errors

### User edit false-positive prevention (SC4)

- A file with ONLY user edits (not upstream changes) would NOT be falsely reported as drifted — BUT this requires 3-way diff (base snapshot). Since conjure doesn't yet store a base snapshot at install time, **v0.5.0 approach**: compare file content directly against the kit template. If file differs from kit template → `modified`. No false-positive suppression in this phase — that's a v0.5.x enhancement.
- Document this limitation in command output: "Note: modified files may include user customizations"

### Exit codes

- Exit 0: harness is fully current (no drift)
- Exit 1: drift detected (any added/modified/removed files)
- These are the exact exit codes from DRIFT-02

### --porcelain output (DRIFT-02)

- One line per file: `<status> <path>` where status is `A` (added), `M` (modified), `R` (removed)
- Machine-readable, no color, no headers
- Example: `M .claude/settings.json\nR profiles/node.sh`

### Human output (default)

- Grouped by category with counts
- Header: "Drift detected: N file(s) differ from upstream kit"
- Color optional (detect tty)
- Example:
  ```
  Modified (2):
    .claude/settings.json
    CLAUDE.md
  Removed (1):
    profiles/node.sh
  ```

### Implementation approach

- New command `cmd_check` in `cli/conjure.sh` (follow pattern of `cmd_update`, `cmd_init`)
- Worker script `scripts/check.sh` (follows `scripts/update.sh` pattern)
- Pure bash + sha256sum/shasum (cross-platform: shasum on macOS, sha256sum on Linux)
- No git operations — pure filesystem comparison
- Read-only: no mutations, no `mutate_*` calls

### Kit snapshot discovery

- `CONJURE_HOME` env var points to the installed conjure directory
- Kit files to check = files that `cmd_init` would write to harness root
- Parse from `scripts/init.sh` or use a hardcoded manifest of known kit files

---

## Canonical Refs

- `.planning/REQUIREMENTS.md` — DRIFT-01, DRIFT-02 definitions
- `cli/conjure.sh` — `cmd_update`, `cmd_init` patterns; where `cmd_check` is added
- `scripts/update.sh` — worker script pattern to follow
- `scripts/init.sh` — source of kit file list
- `lib/mutate.sh` — NOT used (read-only command)
- `tests/run.sh` — where regression tests go

---

## Code Context

### cli/conjure.sh dispatch pattern
- `cmd_<name>()` function defined, then dispatched in the main `case` block
- Check pattern: `conjure.sh` sources worker script or calls it via `bash`

### Cross-platform sha256
```bash
sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}
```

---

## Out of Scope

- 3-way merge / base snapshot storage (v0.5.x)
- `conjure check --json` structured output (REQUIREMENTS.md: deferred to v0.5.x)
- Interactive resolution (Phase 18)
- Auto-PR (Phase 19)

---

## Auto-Mode Note

Gray areas auto-answered in autonomous mode. Decisions follow from existing codebase patterns and REQUIREMENTS.md.
