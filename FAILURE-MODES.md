# Failure Modes

What to do when something in the Conjure harness breaks. Symptoms → causes
→ fixes.

## graphify unavailable / down

**Symptom**: skill `code-graph` returns errors, queries fail.

**Causes**:
- graphify CLI not installed.
- `graphify-out/` missing (never ran `--mode deep`).
- Graph corrupt (partial write during crash).

**Fix**:
```bash
# Diagnose
which graphify
ls graphify-out/

# Reinstall if needed
uv tool install --force graphify

# Rebuild from scratch
rm -rf graphify-out/
conjure refresh-graph . --full
```

**Fallback while down**: Claude falls back to skill `repo-pack` or `ast-search`
or vanilla `Grep` (per `skills/code-graph/SKILL.md` fallback section).

## MCP server unreachable / slow

**Symptom**: skill descriptions reference MCP tools but they don't fire;
session start is slow.

**Causes**:
- Network down, npm registry slow, server crashed.
- API token expired (GitHub, context7 paid tier).
- MCP SDK version mismatch.

**Fix**:
```bash
# Test each server manually
npx -y @upstash/context7-mcp --help
# Check logs
tail ~/.claude/mcp-*.log
```

**Fallback**: Comment out the offending server in `~/.claude/mcp_servers.json`;
Claude falls back to built-in tools.

## Hook blocks legitimate action

**Symptom**: `permissionDecision: deny` when you expect allow.

**Causes**:
- Matcher regex too broad.
- Hook script returned non-zero unintentionally.
- Pattern match in `pre-bash-block-destructive.sh` overzealous.

**Fix**:
```bash
# Bypass once (review hook first!)
# Edit .claude/settings.json — comment out the matcher temporarily.

# Or fix the hook script:
vi .claude/hooks/pre-bash-block-destructive.sh
# Test:
bash -x .claude/hooks/pre-bash-block-destructive.sh "your-command"
```

**Anti-pattern**: Disabling all hooks. If a hook fires wrong, fix the rule;
don't remove enforcement.

## Hook timeout (>2s)

**Symptom**: Sluggish Claude Code; events not firing.

**Cause**: Hook does too much work (running full test suite, slow formatter).

**Fix**: Move long logic to a skill. Hooks should be `<2s` deterministic
checks only.

## CLAUDE.md grew past 200 lines

**Symptom**: `conjure audit` flags `HARD CAP exceeded`; Claude ignores rules.

**Fix**:
```bash
# Identify candidates to extract
conjure audit . | grep CLAUDE.md
# Move sections into skills:
#   mkdir -p .claude/skills/<topic>/
#   <move content>
#   Replace original section with: "For <topic>, see skills/<topic>/SKILL.md."
```

## Skill doesn't fire on expected request

**Symptom**: User asks something the skill should answer, Claude doesn't load it.

**Cause**: skill `description:` doesn't match user phrasing.

**Fix**: Rewrite description using the user's actual words:
- Bad: `"Database utilities."`
- Good: `"Postgres CSV bulk-import via psycopg2 — invoke when user asks to load CSV into Postgres."`

Then audit:
```bash
conjure audit
```

## Compaction lost critical rules

**Symptom**: After `/compact`, Claude no longer follows a rule.

**Cause**: Rule was buried at the bottom of CLAUDE.md (summarized first) OR
was given in conversation only (never saved to disk).

**Fix**:
- Move rule to TOP of CLAUDE.md (non-negotiables section).
- For conversation-only rules: promote to CLAUDE.md or a skill.

## graphify graph drifted from code

**Symptom**: Graph claims X exists but it's been refactored away.

**Cause**: Graph >7 days old AND >20 commits since build.

**Fix**:
```bash
conjure refresh-graph . --update     # incremental
# or full rebuild after large refactor
conjure refresh-graph . --full
```

The `session-start-context.sh` hook warns when graph is stale.

## Conjure update breaks something

**Symptom**: After `conjure update --apply`, a hook fails or skill loads wrong.

**Fix**:
```bash
# Backup is automatic
ls -la .claude.backup-*

# Roll back
rm -rf .claude
mv .claude.backup-<latest> .claude

# File issue with diagnostic info
conjure audit > audit.log
conjure version >> audit.log
```

## Multiple Claude sessions race-update `.claude/`

**Symptom**: Conflicting changes in `.claude/COMPOUND-CANDIDATES.md` or
backup proliferation.

**Cause**: No locking between sessions.

**Fix**: Coordinate via git — commit `.claude/` after major harness edits.
For team setups, `.claude/` should be version-controlled and reviewed.

## Hook script has wrong exit code

**Symptom**: Destructive action you intended to block proceeded.

**Cause**: Hook used `exit 1` (non-blocking) instead of `exit 2` (block).

**Fix**: Audit all hooks:
```bash
grep -nE '^exit 1$' .claude/hooks/*.sh
# Change to: exit 2
```

## "Conjure version mismatch" warnings

**Symptom**: `conjure update` reports project pinned to older version.

**Decision**:
- If you want the latest: `conjure update --apply` (review diff first).
- If you want to stay pinned: `echo "$VERSION" > .claude/.conjure-version`
  to silence warnings; document why in `.claude/EVENT-LOG.md`.

## Disaster recovery

Lost the entire `.claude/` directory mid-session:

```bash
# 1. Stop Claude Code.
# 2. Restore from most recent backup.
mv .claude.backup-<latest> .claude

# 3. Or, if no backup: scaffold fresh.
conjure init existing

# 4. Re-run discovery via PROMPT.md [EXISTING] invocation.
# 5. graphify graph survives separately at graphify-out/.
```

## `conjure adopt` refuses with "working tree is dirty"

**Symptom**: `conjure adopt .` exits 2 at "Step 1/5 preconditions" on a repo you
believe is clean.

**Cause**: You have uncommitted changes (`git status --porcelain` is non-empty).
adopt refuses a dirty tree so the snapshot/rollback can guarantee a clean restore.
(Conjure's own in-flight artifacts — `RESTRUCTURE-LOG.md`, `.conjure-adopt-state`,
`.conjure-adopt-backups`, `.conjure-archive-*`, `adopt-manifest.json` — are
ignored by this check, so a genuinely clean repo is never blocked.)

**Fix**:
```bash
git status --porcelain        # see what's uncommitted
git stash    # or: git commit -am "wip"   — then retry
conjure adopt .
# Or include the uncommitted work in the snapshot (rollback is snapshot-based, not git):
conjure adopt --force .
```

## A `conjure adopt` run was killed mid-way

**Symptom**: adopt was interrupted (terminal closed, `kill -9`, crash). Re-running
prints "partial run detected (last completed: <step>)".

**Cause**: A partial `.conjure-adopt-state` exists. adopt never auto-mutates after
an interrupted run — it asks you how to recover.

**Fix** (interactive — choose at the `[r]ollback / [c]ontinue / [s]tart-fresh` prompt):
```bash
conjure adopt .          # re-run; pick r / c / s
# Non-interactive (CI) — pass an explicit recovery flag instead:
conjure adopt --rollback .      # undo everything from the snapshot
conjure adopt --resume .        # continue at the next incomplete step (reuses the snapshot)
conjure adopt --start-fresh .   # discard state and snapshot anew
```

## Undo an adoption — `conjure adopt --rollback`

**Symptom**: You ran `conjure adopt` and want the repo back exactly as it was.

**Fix**:
```bash
conjure adopt --rollback .
# Restores every mutated file (sha256-verified against pre-run hashes), removes
# scaffolded layers, and logs a [ROLLBACK] entry. Restore is from the FILESYSTEM
# snapshot under .conjure-adopt-backups/, NOT from git — uncommitted work captured
# in the snapshot is restored too. The snapshot + RESTRUCTURE-LOG.md are kept for
# audit; only .conjure-adopt-state is cleared.
```

## The `restructure` skill blocks a proposal before you can approve it

**Symptom**: During `restructure`, a proposed condensed `CLAUDE.md` is rejected
with "missing required invariants" or audit output about `@import`/size caps —
you never get an approve prompt.

**Cause**: Working as designed. Pre-write gates run *before* approval: the
invariant gate blocks a condensation that dropped a rule (e.g. "hooks must
exit 2"), and `conjure audit` on the staged content blocks `@import` lines or a
CLAUDE.md over the 100-line cap. This prevents an invalid harness from ever being
written.

**Fix**: Let the skill re-draft (choose `edit`) so the condensed `CLAUDE.md`
keeps every listed invariant and contains no `@import`; it re-runs both gates and
re-prompts. To inspect what was flagged, read the staged file under
`.conjure-adopt-state/staging/` and `RESTRUCTURE-LOG.md`.

## `conjure adopt --apply-step` rejects an op with exit 2

**Symptom**: Applying a restructure op fails with a path/op error.

**Cause**: The op-executor validates every op: `op` must be one of
`write` / `archive` / `extract`, required fields `{id, op, status}` must be
present, and a `write` `src` must resolve **under** `.conjure-adopt-state/staging/`
with no `..` escape or protected-dir (`.git/`, `.conjure-*`) target. A malformed
or unsafe op is refused without mutating anything.

**Fix**: Re-propose the op via `conjure adopt --update-manifest` with a valid op
type, the required fields, and a staging-relative `src`. The `restructure` skill
generates these correctly; hand-authored manifests must match the same contract.

## Where to get help

- `reference/ANTI-PATTERNS.md` — common mistakes and fixes.
- `checklists/AUDIT.md` — periodic health check.
- File an issue at: https://github.com/mohandoz/conjure/issues
