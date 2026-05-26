# Phase 18: Conflict Resolution — Context

**Date:** 2026-05-26
**Phase:** 18 of 20 — Conflict Resolution
**Goal:** Users can interactively resolve all diff3 conflict sidecars left by `conjure update --apply` without manually editing files

---

## Domain

`conjure resolve` — interactive sidecar walker. After `conjure update --apply` leaves `.conjure-conflict-*` sidecar files, this command walks through each one and prompts the user to keep/apply/edit/skip. Uses `mutate_rm` (Phase 16) to remove resolved sidecars dry-run-safely.

---

## Decisions

### Sidecar discovery

- Sidecars named `.conjure-conflict-<encoded>` where `<encoded>` = relative path with `/` replaced by `_` (from `lib/merge.sh:write_merge_sidecar`)
- Scan: `find . -name ".conjure-conflict-*"` from harness root (or passed target dir)
- Return sorted list for deterministic ordering

### Interactive prompt per sidecar

- Prompt: `[k]eep / [a]pply / [e]dit / [s]kip` — exactly as specified in RESOLVE-01
- `keep`: leave the current file as-is, remove sidecar via `mutate_rm`
- `apply`: replace current file with sidecar content (apply the upstream changes), remove sidecar
- `edit`: open `$EDITOR` on the sidecar file for manual editing, then re-prompt (loop until k/a/s)
- `skip`: leave both current file and sidecar in place (user defers this one)

### Non-interactive guard (RESOLVE-01)

- Check `[ -t 0 ]` before any prompting
- Exit 2 (not 1) with message: `"conjure resolve: stdin is not a TTY — interactive mode required"`
- This matches the project convention: exit 2 = hard prerequisite failure

### All-clear message (RESOLVE-02)

- When no sidecars remain: print `"No conflicts remain"` and exit 0
- Triggered both when: (a) starting with zero sidecars, (b) after resolving all sidecars

### Dry-run support

- `mutate_rm` already handles DRY_RUN — pass through `DRY_RUN` env var
- In dry-run mode: print what would be removed, don't remove

### Implementation structure

- New `cmd_resolve` in `cli/conjure` (same dispatch pattern)
- Worker script `scripts/resolve.sh`
- Sources `lib/mutate.sh` for `mutate_rm`
- Pure bash + readline (read -r -p prompt)
- No external deps beyond bash stdlib

### Editor integration

- `${EDITOR:-vi}` for edit mode
- Must re-prompt after editor exits (loop)

---

## Canonical Refs

- `.planning/REQUIREMENTS.md` — RESOLVE-01, RESOLVE-02 definitions
- `lib/merge.sh` — sidecar naming convention (`.conjure-conflict-<encoded>`)
- `lib/mutate.sh` — `mutate_rm` (Phase 16 deliverable) — use for sidecar removal
- `scripts/check.sh` — structural analog for worker script pattern
- `cli/conjure` — where `cmd_resolve` and dispatch entry go
- `tests/run.sh` — where RESOLVE regression tests go

---

## Code Context

### Sidecar naming (lib/merge.sh lines 59-72)
```
sidecar_name=".conjure-conflict-${encoded}"  # encoded = rel with / → _
sidecar_path="${sidecar_dir}/${sidecar_name}"
```

### mutate_rm interface (lib/mutate.sh)
```bash
source lib/mutate.sh
mutate_rm "$sidecar_path"  # DRY_RUN safe
```

### cmd_ dispatch pattern (cli/conjure)
- Function: `cmd_resolve() { ... }`
- Dispatch entry in `case "$cmd" in`
- Usage line in `show_usage()`

---

## Out of Scope

- TUI side-by-side diff viewer (v0.6.0)
- Auto-resolve strategies (future)
- `conjure resolve --all keep` batch mode (future)

---

## Auto-Mode Note

Auto-answered in autonomous mode. Decisions follow directly from REQUIREMENTS.md and existing merge.sh sidecar patterns.
