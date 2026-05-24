# Migration Guide

How to bring existing AI-assistant configs into a Conjure-shaped `.claude/`
without losing rules and without breaking running sessions.

## Source-tool support matrix

| Existing config | Detect | Migrate | Notes |
| --- | --- | --- | --- |
| `CLAUDE.md` only | `migrations/from-claude/detect.sh` | `from-claude` | Splits long CLAUDE.md into skills; replaces `@imports` with prose; reorders for compaction. |
| `.claude/` directory (any prior Conjure or hand-rolled) | auto | `from-claude` | Audits, suggests promotions, doesn't delete. |
| `.cursorrules` (Cursor) | file exists | `from-cursor` | Cursor rules → CLAUDE.md trigger-action format. |
| `.cursor/rules/*.mdc` (Cursor new format) | dir exists | `from-cursor` | Per-glob rules → skills with matchers. |
| `.aider.conf.yml` + `CONVENTIONS.md` | file exists | `from-aider` | Conventions → CLAUDE.md; model settings → notes only. |
| `.continue/config.json` | file exists | `from-continue` | MCP server entries → `~/.claude/mcp_servers.json` suggestions. |
| `.github/copilot-instructions.md` | file exists | `from-copilot` | Instructions → CLAUDE.md non-negotiable rules. |
| `.windsurfrules` | file exists | `from-windsurf` | Rules → CLAUDE.md. |

## Universal safety rules

1. **Backup before mutate.** Every migration creates `<target>/.claude.backup-YYYYMMDD-HHMMSS/`
   before touching anything. Verify the backup exists before responding to a prompt.
2. **Dry-run first.** `conjure migrate <source> --dry-run` prints what would change.
3. **No silent deletes.** Migrations RENAME removed files to `<file>.deprecated`,
   they do not `rm`.
4. **Preserve original content as comments.** Migrated CLAUDE.md keeps the
   original rule text as a `<!-- ORIGINAL: ... -->` HTML comment so you can
   diff intent.
5. **Re-run safe.** Idempotent. Running `conjure migrate` twice is a no-op
   on the second run.

## Workflow

```bash
# 1. Inspect what would happen
conjure migrate from-cursor --dry-run /path/to/repo

# 2. Run the migration (backup is automatic)
conjure migrate from-cursor /path/to/repo

# 3. Audit
conjure audit /path/to/repo

# 4. Open Claude Code, paste PROMPT.md with [EXISTING] invocation. Claude
#    will fill in any skill templates left as scaffolds and verify claims
#    against the actual code.

# 5. If anything looks wrong, roll back
rm -rf /path/to/repo/.claude
mv /path/to/repo/.claude.backup-* /path/to/repo/.claude
```

## What gets migrated, what doesn't

### Migrated automatically
- Rule text (with original preserved as comment).
- Routing references to existing files.
- File paths that still exist.
- Hook scripts that meet the 2026 spec.

### Flagged for manual review (NOT auto-changed)
- Rules that reference deleted files.
- Rules in vague form ("write good code") — flagged with `[REVIEW]`.
- Hooks using `exit 1` instead of `exit 2` — auto-fixed but logged.
- MCP server entries with hardcoded secrets — refused (asks user to use env vars).

### Not migrated (manual decision)
- `.cursorrules` `@-mentions` of teammates — Cursor-specific, no Claude equivalent.
- Aider model/voice settings — Claude Code chooses model differently.
- Per-file-glob Cursor rules that overlap heavily — collapsed with `[REVIEW]` note.

## Migration FROM Conjure (downgrade / unfreeze)

```bash
# Restore a backup
mv .claude .claude.purged
mv .claude.backup-<timestamp> .claude
```

## Conflict resolution

When Conjure finds existing CLAUDE.md rules that contradict its template:

- Source-tool rule WINS (we preserve user intent).
- Conjure adds its rule as a comment with `# CONSIDER: <rule>`.
- Audit flags it as a follow-up.

When two source tools provide overlapping rules (e.g. `CLAUDE.md` AND
`.cursorrules`):

- Process in order: existing `.claude/` → `.cursorrules` → `.aider/` → `.continue/` → copilot.
- Later sources only ADD if they don't conflict.
- All preserved rules cite their source: `<!-- src: .cursorrules:42 -->`.

## After migration — checklist

- [ ] Audit passes (`conjure audit`).
- [ ] CLAUDE.md ≤100 lines.
- [ ] Original rules still present as comments OR explicitly removed in CHANGELOG-ish note.
- [ ] Run 3 typical tasks and confirm Claude behaves like before (or better).
- [ ] Old config files (`.cursorrules`, `.windsurfrules` etc.) renamed to
      `<file>.deprecated` — delete after 1 week of confidence.
