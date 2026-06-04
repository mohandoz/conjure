---
phase: 25-plugin-marketplace-emission
reviewed: 2026-06-03T00:00:00Z
depth: standard
iteration: 3
files_reviewed: 7
files_reviewed_list:
  - lib/plugin-helpers.sh
  - scripts/emit-plugin.sh
  - scripts/publish-plugin.sh
  - scripts/audit-setup.sh
  - cli/conjure
  - .claude-plugin/SCHEMAS/plugin.schema.json
  - .claude-plugin/SCHEMAS/marketplace.schema.json
findings:
  critical: 1
  warning: 0
  info: 1
  total: 2
status: issues_found
---

# Phase 25: Code Review Report

**Reviewed:** 2026-06-03T00:00:00Z
**Depth:** standard (iteration 3 — final auto pass)
**Files Reviewed:** 7
**Status:** issues_found

## Summary

Iteration-3 re-review of the plugin/marketplace emission phase. Goals: (a) confirm the
prior two iterations of fixes are correctly applied and (b) catch any NEW regression
introduced by those fixes — especially in the version-resolution and validator changes
in `lib/plugin-helpers.sh`.

**Prior fixes verified — all correctly applied:**

- **CR-01** (exit 1 → 2): all script/CLI/helper failure paths exit 2. Confirmed in
  `emit-plugin.sh`, `publish-plugin.sh`, and `plugin-helpers.sh` (`run_cli_validate`).
- **CR-02** (snapshot-before-overwrite): `emit-plugin.sh:92-97` snapshots the target
  via the blessed `snapshot_create` exception *before* the first overwriting write,
  gated on a pre-existing manifest/settings and on live mode. Reuses the exact
  `$TARGET/.conjure-adopt-backups` root used by `adopt.sh` — no new snapshot path.
- **WR-01** (marketplace-name regex / blank-version fall-through): `emit-plugin.sh:122`
  and `validate_marketplace_json:116` both enforce `^[a-z][a-z0-9-]{0,63}$`. Blank /
  whitespace-only `.conjure-version` now falls through to git-SHA / 0.0.0 (tested
  `\n1.2.3`, `   \n`, empty → `0.0.0`; never an empty version string).
- **WR-02** (validator hardening): empty `name` and empty `version` rejected (tested
  `{"name":""}` → rc 1, `{"version":""}` → rc 1). Marketplace owner / plugins / per-entry
  source checks match schema (tested emitted local + github shapes → rc 0).
- **WR-03** (sed-metachar-safe agent paths): `plugin_build_plugin_json` strips the
  `$target/` prefix with bash parameter expansion + `jq -R/-sc`, not `sed`. Empty
  agents dir correctly omits the field.
- **WR-05** (version corruption): `head -1 | tr -d '[:space:]'` strips trailing
  newlines, CRLF, and surrounding padding (tested CRLF → `1.2.3`, `\t 3.1.4 \t` →
  `3.1.4`). No SIGPIPE abort under `set -euo pipefail`, even on a 100k-line file.
- **WR-06** (POSIX ERE secret scan): uses `[[:space:]]`, not `\s`. Realistic leak
  vectors caught on macOS/BSD grep — `sk-ant-*`, `ghp_*`, quoted credential fields,
  and the MCP `env.API_KEY` nesting all BLOCK with rc 1.
- **iter-2** (reject empty name/version, `--name` CLI flag): `--name`/`--name=` parsed
  in `cli/conjure:487-488` and `emit-plugin.sh:33-34`; `${OWNER_REPO:-...}` keeps owner
  derivation `set -u`-safe when `--name` skips the auto-detect block.
- **WR-07** (note-vs-warn in `audit-setup.sh`): intentionally retained — NOT re-flagged.

`shellcheck -S error -e SC2164,SC2044,SC2034,SC2155` is clean on all four shell files.

**One NEW blocker surfaced by the WR-02 validator hardening:** the emitter's own
first-time output now fails the very validator that iteration 1 tightened. A first-run
`conjure publish-plugin` on a repo with no pre-existing `.claude-plugin/plugin.json`
always exits 2. Detail below.

## Critical Issues

### CR-01: First-time `publish-plugin` always exits 2 — emitted plugin.json has no `name`

**File:** `lib/plugin-helpers.sh:215-297` (`plugin_build_plugin_json`), gated by
`scripts/emit-plugin.sh:86` (`validate_plugin_json "$PLUGIN_JSON" || exit 2`)

**Issue:**
`plugin_build_plugin_json` never sets `.name`. Its merge base is the existing
`plugin.json` (`existing='{}'` when none exists), and the jq pipeline only re-asserts
`version`, `skills`, `agents`, `hooks`, `mcpServers`, and the user-metadata allowlist —
`name` is never derived or assigned. The WR-02 hardening then makes
`validate_plugin_json` require a non-empty string `name`, so the emitter's own
first-run output is rejected and `emit-plugin.sh` exits 2.

This breaks the core happy path ("turn any repo into a plugin"): emission succeeds
only when a prior `plugin.json` already carries a `name`. Reproduced end-to-end:

```
# fresh repo, no .claude-plugin/plugin.json
$ DRY_RUN=1 bash scripts/emit-plugin.sh --path /tmp/e2e --name my-cool-repo --marketplace --enable
✗ plugin.json: 'name' is required and must be a non-empty string
$ echo $?
2

# same repo after pre-seeding {"name":"my-cool-repo"} → exit 0, all writes proceed
```

The `--name` flag does NOT cover this: it is wired only to `MKT_NAME` (the *marketplace*
name), never to plugin.json's `name`. So even an explicit `--name` cannot make a
first-time emit succeed.

**Fix:** Derive and set `.name` in `plugin_build_plugin_json` when the existing manifest
lacks one, mirroring the kebab derivation already present in `emit-plugin.sh:106-116`:

```bash
# plugin_build_plugin_json(target, version, name)
plugin_build_plugin_json() {
  local target="$1"
  local version="$2"
  local fallback_name="${3:-}"
  # ...existing harness discovery + existing= read...

  if [ -z "$fallback_name" ]; then
    fallback_name="$(basename "$target" | tr '[:upper:]' '[:lower:]' \
      | tr '_.' '-' | tr -cd 'a-z0-9-')"
  fi

  updated=$(printf '%s' "$existing" | jq \
    --arg name "$fallback_name" \
    # ...existing args... \
    '. as $orig |
     # ...existing $desc/$kw/... bindings... |
     . |
     (if (.name // "") == "" then .name = $name else . end) |
     .version = $version |
     # ...rest unchanged...')
}
```

Then update the caller `scripts/emit-plugin.sh:80` to pass a name (compute the kebab
derivation before the build, or thread `MKT_NAME` through). Add a `tests/run.sh` case
that runs a first-time emit against a fixture repo with **no** pre-existing
`plugin.json` and asserts exit 0 plus a non-empty `.name` — that path is currently
untested, which is why this regression shipped.

## Info

### IN-01: `.conjure-version` with a blank first line silently resolves to 0.0.0

**File:** `lib/plugin-helpers.sh:182-192` (`resolve_version`)

**Issue:** `head -1 | tr -d '[:space:]'` reads only line 1. A file like `\n1.2.3\n`
(blank first line, real version on line 2) emits the "empty — falling back" warning and
resolves to `0.0.0`, silently ignoring `1.2.3` on line 2. Consistent with the documented
WR-05 "take the first line" behavior, not a correctness bug, but surprising: a stray
leading newline yields `0.0.0`.

**Fix (optional, low priority):** take the first **non-blank** line, e.g.
`grep -m1 -v '^[[:space:]]*$' "$target/.conjure-version" | tr -d '[:space:]'`. The
warning is already emitted, so the behavior is observable.

## Structural Findings (fallow)

No `<structural_findings>` block was provided for this iteration; no structural
pre-pass to reconcile.

---

_Reviewed: 2026-06-03T00:00:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
